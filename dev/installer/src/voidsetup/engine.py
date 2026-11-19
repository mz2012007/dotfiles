"""Sequential task execution with resume, checks and dependency handling."""

from __future__ import annotations

import asyncio
import time
import traceback
from dataclasses import dataclass
from typing import Callable, Iterable, Mapping

from .context import Context
from .errors import ExecutionCancelled, SkipTask
from .models import RunStatus, Severity, Task, TaskResult, TaskStatus
from .registry import TASKS
from .state import RunState, StateStore

StartHook = Callable[[Task, int, int], None]
ResultHook = Callable[[Task, TaskResult], None]


@dataclass(slots=True)
class ExecutionHooks:
    on_start: StartHook | None = None
    on_result: ResultHook | None = None


class Executor:
    def __init__(
        self,
        ctx: Context,
        plan: Iterable[str],
        *,
        store: StateStore | None = None,
        hooks: ExecutionHooks | None = None,
        resume: bool = False,
        tasks: Mapping[str, Task] | None = None,
    ) -> None:
        self.ctx = ctx
        self.plan = list(plan)
        self.store = store
        self.hooks = hooks or ExecutionHooks()
        self.resume = resume
        self.tasks: dict[str, Task] = dict(tasks) if tasks is not None else TASKS
        self.results: list[TaskResult] = []
        self._by_id: dict[str, TaskResult] = {}

    async def run(self) -> list[TaskResult]:
        state: RunState | None = None
        if self.store is not None and not self.ctx.dry_run:
            state = self.store.begin(self.ctx.options.profile, self.plan, resume=self.resume)
            self.store.save(state)

        cancelled = False
        stopped = False
        total = len(self.plan)

        for index, task_id in enumerate(self.plan, start=1):
            task = self.tasks[task_id]

            if stopped or cancelled or self.ctx.cancel_event.is_set():
                if not cancelled and not stopped:
                    cancelled = True
                await self._finish(
                    task,
                    TaskResult(task.id, TaskStatus.BLOCKED, error="run aborted"),
                    state,
                    index,
                    total,
                )
                continue

            if self.resume and state is not None:
                previous = state.tasks.get(task.id)
                if previous is not None and previous.status is TaskStatus.OK:
                    await self._finish(
                        task,
                        TaskResult(task.id, TaskStatus.SKIPPED, detail="already completed in previous run"),
                        state,
                        index,
                        total,
                        persist=False,
                    )
                    continue

            missing_dependencies = [
                dependency
                for dependency in task.depends_on
                if dependency not in self._by_id or not self._by_id[dependency].ok
            ]
            if missing_dependencies:
                result = TaskResult(
                    task.id,
                    TaskStatus.BLOCKED,
                    error="missing or failed dependency: " + ", ".join(missing_dependencies),
                )
                await self._finish(task, result, state, index, total)
                if task.severity is Severity.REQUIRED:
                    stopped = True
                continue

            if task.dangerous and not self.ctx.options.allow_destructive:
                result = TaskResult(
                    task.id,
                    TaskStatus.FAILED,
                    error="destructive task requires --allow-destructive",
                )
                self.ctx.logger.error(f"{task.id}: {result.error}")
                await self._finish(task, result, state, index, total)
                if task.severity is Severity.REQUIRED:
                    stopped = True
                continue

            if task.check is not None:
                try:
                    already_done = await task.check(self.ctx)
                except ExecutionCancelled as exc:
                    await self._finish(
                        task,
                        TaskResult(task.id, TaskStatus.ABORTED, error=str(exc) or "aborted"),
                        state,
                        index,
                        total,
                    )
                    cancelled = True
                    continue
                except asyncio.CancelledError:
                    raise
                except Exception as exc:  # checks must never be fatal
                    self.ctx.logger.warn(f"check for {task.id} failed, running task anyway: {exc}")
                    already_done = False
                if already_done:
                    await self._finish(
                        task,
                        TaskResult(task.id, TaskStatus.SKIPPED, detail="already done"),
                        state,
                        index,
                        total,
                    )
                    continue

            if state is not None:
                state.start_task(task.id)
                self.store.save(state)  # type: ignore[union-attr]
            self._call_start(task, index, total)
            self.ctx.logger.info(f"▶ [{index}/{total}] {task.name}")

            started = time.monotonic()
            status = TaskStatus.OK
            error: str | None = None
            detail: str | None = None
            try:
                await task.func(self.ctx)
            except SkipTask as exc:
                status = TaskStatus.SKIPPED
                detail = exc.reason
                self.ctx.logger.info(f"skipped {task.id}: {exc.reason}")
            except ExecutionCancelled as exc:
                status = TaskStatus.ABORTED
                error = str(exc) or "aborted"
                cancelled = True
            except asyncio.CancelledError:
                if state is not None:
                    state.finish_task(task.id, TaskStatus.ABORTED, error="worker cancelled")
                    self.store.save(state)  # type: ignore[union-attr]
                raise
            except Exception as exc:
                status = TaskStatus.FAILED
                error = f"{type(exc).__name__}: {exc}"
                self.ctx.logger.error(f"{task.id}: {error}")
                self.ctx.logger.debug(traceback.format_exc())

            duration = time.monotonic() - started
            result = TaskResult(task.id, status, duration=duration, error=error, detail=detail)
            await self._finish(task, result, state, index, total)

            if status is TaskStatus.FAILED and task.severity is Severity.REQUIRED:
                stopped = True
            if status is TaskStatus.ABORTED:
                cancelled = True

        if state is not None and not self.ctx.dry_run:
            if cancelled or self.ctx.cancel_event.is_set():
                state.finish_run(RunStatus.ABORTED)
            elif any(
                result.status in (TaskStatus.FAILED, TaskStatus.BLOCKED)
                and self.tasks[result.task_id].severity is Severity.REQUIRED
                for result in self.results
            ):
                state.finish_run(RunStatus.FAILED)
            else:
                state.finish_run(RunStatus.COMPLETED)
            self.store.save(state)  # type: ignore[union-attr]

        return self.results

    async def _finish(
        self,
        task: Task,
        result: TaskResult,
        state: RunState | None,
        index: int,
        total: int,
        *,
        persist: bool = True,
    ) -> None:
        self.results.append(result)
        self._by_id[task.id] = result
        if persist and state is not None and not self.ctx.dry_run:
            state.finish_task(
                task.id,
                result.status,
                duration=result.duration,
                error=result.error,
                detail=result.detail,
            )
            self.store.save(state)  # type: ignore[union-attr]
        if self.hooks.on_result is not None:
            try:
                self.hooks.on_result(task, result)
            except Exception:
                self.ctx.logger.debug(traceback.format_exc())

    def _call_start(self, task: Task, index: int, total: int) -> None:
        if self.hooks.on_start is None:
            return
        try:
            self.hooks.on_start(task, index, total)
        except Exception:
            self.ctx.logger.debug(traceback.format_exc())
