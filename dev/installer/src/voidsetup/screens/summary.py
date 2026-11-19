"""Post-run summary."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from rich.text import Text
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, DataTable, Footer, Header, Static

from ..models import RunOptions, Severity, TaskResult, TaskStatus
from ..registry import TASKS
from .confirm import ConfirmScreen

STATUS_STYLE = {
    TaskStatus.OK: "green",
    TaskStatus.SKIPPED: "cyan",
    TaskStatus.FAILED: "red",
    TaskStatus.BLOCKED: "red",
    TaskStatus.ABORTED: "red",
    TaskStatus.PENDING: "dim",
    TaskStatus.RUNNING: "yellow",
}


class SummaryScreen(Screen):
    def __init__(
        self,
        results: list[TaskResult],
        options: RunOptions,
        log_path: Path | None,
        fatal_error: str | None = None,
        plan: list[str] | None = None,
    ) -> None:
        super().__init__()
        self.results = results
        self.options = options
        self.log_path = log_path
        self.fatal_error = fatal_error
        self.plan = list(plan) if plan else []

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical(id="summary-body"):
            yield Static("Run summary", classes="screen-title")
            yield Static("", id="summary-text")
            yield DataTable(id="summary-table", zebra_stripes=True, show_header=True)
            yield Static("", id="summary-log", classes="muted")
            with Horizontal(classes="actions"):
                yield Button("Resume failed", id="resume", variant="warning")
                yield Button("Reboot", id="reboot", variant="warning")
                yield Button("New run", id="new")
                yield Button("Quit", id="quit", variant="primary")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#summary-table", DataTable)
        table.add_column("Task", key="task")
        table.add_column("Status", key="status", width=10)
        table.add_column("Time", key="time", width=8)
        table.add_column("Detail", key="detail")
        for result in self.results:
            task = TASKS[result.task_id]
            detail = result.error or result.detail or ""
            table.add_row(
                task.name,
                Text(result.status.value, style=STATUS_STYLE.get(result.status, "dim")),
                f"{result.duration:.1f}s",
                detail,
                key=result.task_id,
            )

        failed = self._failed_required()
        aborted = any(result.status is TaskStatus.ABORTED for result in self.results)
        counts: dict[str, int] = {}
        for result in self.results:
            counts[result.status.value] = counts.get(result.status.value, 0) + 1
        summary = "   ".join(f"{name}: {count}" for name, count in sorted(counts.items()))
        if self.fatal_error:
            summary += f"\n\n[b red]Run failed before completion:[/b red]\n{self.fatal_error}"
        elif self.options.dry_run:
            summary += "\n\n[b yellow]Dry run: nothing was changed.[/b yellow]"
        elif aborted:
            summary += "\n\n[b red]Run aborted.[/b red]"
        elif failed:
            summary += "\n\n[b red]One or more required tasks failed.[/b red]"
        else:
            summary += "\n\n[b green]All required tasks completed.[/b green]"
        self.query_one("#summary-text", Static).update(summary)
        self.query_one("#summary-log", Static).update(
            Text(f"log: {self.log_path}" if self.log_path else "log: unavailable")
        )
        reboot = self.query_one("#reboot", Button)
        reboot.disabled = (
            self.options.dry_run or failed or aborted or bool(self.fatal_error)
        )
        resume = self.query_one("#resume", Button)
        resume.disabled = not self._can_resume()

    def _failed_required(self) -> bool:
        return any(
            result.status in (TaskStatus.FAILED, TaskStatus.BLOCKED)
            and TASKS[result.task_id].severity is Severity.REQUIRED
            for result in self.results
        )

    def _can_resume(self) -> bool:
        if not self.plan or self.options.dry_run or self.fatal_error:
            return False
        return any(
            result.status in (TaskStatus.FAILED, TaskStatus.BLOCKED, TaskStatus.ABORTED)
            for result in self.results
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "quit":
            self.app.exit()
        elif event.button.id == "new":
            from .profile import ProfileScreen

            self.app.push_screen(ProfileScreen(initial=self.options.profile))
        elif event.button.id == "resume":
            from .execution import ExecutionScreen

            if not self.plan:
                self.notify("No plan to resume.", severity="warning")
                return
            self.app.push_screen(
                ExecutionScreen(self.plan, replace(self.options, resume=True))
            )
        elif event.button.id == "reboot":
            self.app.push_screen(
                ConfirmScreen(
                    "Reboot now? Make sure no work is unsaved.",
                    title="Reboot",
                    yes_label="Reboot",
                    danger=True,
                ),
                callback=self._reboot_confirmed,
            )

    def _reboot_confirmed(self, confirmed: bool | None) -> None:
        if confirmed:
            self.run_worker(self.app.reboot_async())  # type: ignore[attr-defined]
