"""Live execution screen."""

from __future__ import annotations

import asyncio
import traceback
from datetime import datetime
from pathlib import Path

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, DataTable, Footer, Header, ProgressBar, RichLog, Static
from rich.text import Text

from ..context import Context
from ..engine import ExecutionHooks, Executor
from ..models import RunOptions, Task, TaskResult, TaskStatus
from ..registry import TASKS
from ..runner import Runner
from ..session_log import LogLevel, LogRecord, SessionLogger
from ..state import StateStore
from .confirm import ConfirmScreen
from .summary import SummaryScreen

STATUS_STYLE = {
    TaskStatus.PENDING: "dim",
    TaskStatus.RUNNING: "yellow",
    TaskStatus.OK: "green",
    TaskStatus.SKIPPED: "cyan",
    TaskStatus.FAILED: "red",
    TaskStatus.BLOCKED: "red",
    TaskStatus.ABORTED: "red",
}


class ExecutionScreen(Screen):
    def __init__(self, plan: list[str], options: RunOptions) -> None:
        super().__init__()
        self.plan = list(plan)
        self.options = options
        self.cancel_event = asyncio.Event()
        self.runner: Runner | None = None
        self.logger: SessionLogger | None = None
        self.log_path: Path | None = None
        self.results: list[TaskResult] = []
        self.fatal_error: str | None = None
        self._finished = False

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical(id="exec-body"):
            yield Static("Preparing…", id="current-task", classes="screen-title")
            yield ProgressBar(total=max(len(self.plan), 1), show_eta=True, id="progress")
            with Horizontal(id="exec-columns"):
                with Vertical(id="status-pane"):
                    yield DataTable(id="status-table", zebra_stripes=True, show_header=True)
                yield RichLog(
                    id="log",
                    markup=False,
                    highlight=True,
                    wrap=True,
                    max_lines=5000,
                    auto_scroll=True,
                )
            with Horizontal(classes="actions"):
                yield Static("", id="exec-hint", classes="muted")
                yield Button("Abort", id="abort", variant="error")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#status-table", DataTable)
        table.add_column("Task", key="task")
        table.add_column("Status", key="status", width=10)
        table.add_column("Time", key="time", width=8)
        for task_id in self.plan:
            task = TASKS[task_id]
            table.add_row(
                task.name,
                Text("pending", style="dim"),
                "—",
                key=task_id,
            )
        self._run()

    def _set_status(self, task_id: str, status: TaskStatus, duration: float | None = None) -> None:
        if not self.is_mounted:
            return
        table = self.query_one("#status-table", DataTable)
        try:
            table.update_cell(task_id, "status", Text(status.value, style=STATUS_STYLE.get(status, "dim")))
            if duration is not None:
                table.update_cell(task_id, "time", f"{duration:.1f}s")
        except Exception:
            pass

    def _on_log(self, record: LogRecord) -> None:
        if not self.is_mounted or record.level is LogLevel.DEBUG:
            return
        if record.level is LogLevel.OUTPUT:
            text = Text.from_ansi(record.message)
        else:
            prefix = {
                LogLevel.INFO: "ℹ ",
                LogLevel.WARN: "! ",
                LogLevel.ERROR: "✖ ",
                LogLevel.COMMAND: "$ ",
            }.get(record.level, "")
            style = {
                LogLevel.WARN: "yellow",
                LogLevel.ERROR: "red",
                LogLevel.COMMAND: "cyan",
            }.get(record.level, "")
            text = Text(prefix + record.message, style=style)
        try:
            self.query_one("#log", RichLog).write(text)
        except Exception:
            pass

    @work(exclusive=True, group="execution")
    async def _run(self) -> None:
        settings = self.app.settings  # type: ignore[attr-defined]
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.log_path = settings.logs_dir / f"{stamp}.log"
        self.logger = SessionLogger(self.log_path, sink=self._on_log, keep_logs=settings.log_keep)
        logger = self.logger
        self.runner = Runner(logger, dry_run=self.options.dry_run)
        context = Context(
            settings=settings,
            runner=self.runner,
            logger=logger,
            options=self.options,
            cancel_event=self.cancel_event,
            package_groups=self.options.package_groups,
            plymouth_theme=self.options.plymouth_theme,
        )

        logger.info("voidsetup TUI")
        logger.info(
            f"profile: {self.options.profile}; tasks: {len(self.plan)}; "
            f"dry-run: {self.options.dry_run}"
        )
        self.query_one("#exec-hint", Static).update(
            "dry-run: no system changes will be made"
            if self.options.dry_run
            else "root tasks use the sudo session started before execution"
        )

        hooks = ExecutionHooks(
            on_start=self._on_start,
            on_result=self._on_result,
        )
        store = StateStore(settings.state_file)

        try:
            if not self.options.dry_run:
                await self.runner.start_keepalive()
            self.results = await Executor(
                context,
                self.plan,
                store=store,
                hooks=hooks,
                resume=self.options.resume,
            ).run()
            logger.info("run finished")
        except asyncio.CancelledError:
            logger.warn("execution worker cancelled")
            raise
        except Exception as exc:
            self.fatal_error = f"{type(exc).__name__}: {exc}"
            logger.error(f"unexpected execution error: {self.fatal_error}")
            logger.debug(traceback.format_exc())
        finally:
            await self.runner.stop_keepalive()
            logger.close()
            self._finished = True

        self.app.last_results = self.results  # type: ignore[attr-defined]
        self.app.last_log_path = self.log_path  # type: ignore[attr-defined]
        try:
            self.app.push_screen(  # type: ignore[attr-defined]
                SummaryScreen(
                    results=self.results,
                    options=self.options,
                    log_path=self.log_path,
                    fatal_error=self.fatal_error,
                    plan=self.plan,
                )
            )
        except Exception:
            pass

    def _on_start(self, task: Task, index: int, total: int) -> None:
        if not self.is_mounted:
            return
        self.query_one("#current-task", Static).update(
            f"[b]{index}/{total}[/b]  {task.name}"
        )
        self._set_status(task.id, TaskStatus.RUNNING)

    def _on_result(self, task: Task, result: TaskResult) -> None:
        if not self.is_mounted:
            return
        self._set_status(task.id, result.status, result.duration)
        progress = self.query_one("#progress", ProgressBar)
        progress.advance(1)
        if result.error:
            self.query_one("#current-task", Static).update(
                f"[red]{task.name}[/red] — {result.error}"
            )
        elif result.detail:
            self.query_one("#current-task", Static).update(
                f"[cyan]{task.name}[/cyan] — {result.detail}"
            )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "abort":
            self.app.push_screen(
                ConfirmScreen(
                    "Stop the current command and skip the remaining tasks?",
                    title="Abort execution",
                    yes_label="Abort",
                    no_label="Continue",
                    danger=True,
                ),
                callback=self._abort_confirmed,
            )

    def _abort_confirmed(self, confirmed: bool | None) -> None:
        if not confirmed:
            return
        self.cancel_event.set()
        self.query_one("#abort", Button).disabled = True
        if self.runner is not None:
            self.run_worker(self.runner.cancel(), group="cancel")
        self.notify("Stopping after the current command…", severity="warning")

    def on_unmount(self) -> None:
        if not self._finished:
            self.cancel_event.set()
            if self.runner is not None:
                self.runner.cancel_sync()
