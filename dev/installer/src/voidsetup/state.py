"""Atomic JSON state so an interrupted run can be resumed."""

from __future__ import annotations

import json
import os
import tempfile
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .errors import StateError
from .models import RunStatus, TaskStatus
from .util import now_iso


@dataclass(slots=True)
class TaskState:
    status: TaskStatus = TaskStatus.PENDING
    started_at: str | None = None
    finished_at: str | None = None
    duration: float = 0.0
    error: str | None = None
    detail: str | None = None

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["status"] = self.status.value
        return data

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TaskState":
        raw_status = data.get("status", TaskStatus.PENDING.value)
        try:
            status = TaskStatus(raw_status)
        except ValueError:
            status = TaskStatus.PENDING
        return cls(
            status=status,
            started_at=_optional_str(data.get("started_at")),
            finished_at=_optional_str(data.get("finished_at")),
            duration=float(data.get("duration") or 0.0),
            error=_optional_str(data.get("error")),
            detail=_optional_str(data.get("detail")),
        )


@dataclass(slots=True)
class RunState:
    run_id: str
    profile: str
    plan: list[str]
    started_at: str
    updated_at: str
    status: RunStatus = RunStatus.RUNNING
    finished_at: str | None = None
    tasks: dict[str, TaskState] = field(default_factory=dict)
    version: int = 1

    @classmethod
    def new(cls, profile: str, plan: list[str]) -> "RunState":
        stamp = now_iso()
        return cls(
            run_id=uuid.uuid4().hex,
            profile=profile,
            plan=list(plan),
            started_at=stamp,
            updated_at=stamp,
        )

    @property
    def is_resumable(self) -> bool:
        return self.status in (RunStatus.RUNNING, RunStatus.FAILED, RunStatus.ABORTED)

    def task_state(self, task_id: str) -> TaskState:
        return self.tasks.setdefault(task_id, TaskState())

    def start_task(self, task_id: str) -> None:
        state = self.task_state(task_id)
        state.status = TaskStatus.RUNNING
        state.started_at = now_iso()
        state.finished_at = None
        state.error = None
        state.detail = None
        self.updated_at = now_iso()

    def finish_task(
        self,
        task_id: str,
        status: TaskStatus,
        *,
        duration: float = 0.0,
        error: str | None = None,
        detail: str | None = None,
    ) -> None:
        state = self.task_state(task_id)
        state.status = status
        state.finished_at = now_iso()
        state.duration = duration
        state.error = error
        state.detail = detail
        self.updated_at = now_iso()

    def finish_run(self, status: RunStatus) -> None:
        self.status = status
        self.finished_at = now_iso()
        self.updated_at = self.finished_at

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "run_id": self.run_id,
            "profile": self.profile,
            "plan": self.plan,
            "started_at": self.started_at,
            "updated_at": self.updated_at,
            "finished_at": self.finished_at,
            "status": self.status.value,
            "tasks": {task_id: state.to_dict() for task_id, state in self.tasks.items()},
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "RunState":
        raw_status = data.get("status", RunStatus.RUNNING.value)
        try:
            status = RunStatus(raw_status)
        except ValueError:
            status = RunStatus.RUNNING
        tasks: dict[str, TaskState] = {}
        raw_tasks = data.get("tasks")
        if isinstance(raw_tasks, dict):
            for task_id, task_data in raw_tasks.items():
                if isinstance(task_id, str) and isinstance(task_data, dict):
                    tasks[task_id] = TaskState.from_dict(task_data)
        plan = data.get("plan")
        if not isinstance(plan, list):
            plan = []
        return cls(
            run_id=str(data.get("run_id") or uuid.uuid4().hex),
            profile=str(data.get("profile") or "custom"),
            plan=[str(item) for item in plan],
            started_at=str(data.get("started_at") or now_iso()),
            updated_at=str(data.get("updated_at") or now_iso()),
            status=status,
            finished_at=_optional_str(data.get("finished_at")),
            tasks=tasks,
            version=int(data.get("version") or 1),
        )


def _optional_str(value: object) -> str | None:
    return str(value) if value is not None else None


class StateStore:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)

    def load(self) -> RunState | None:
        if not self.path.is_file():
            return None
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                raise ValueError("state root is not an object")
            return RunState.from_dict(data)
        except (OSError, ValueError, json.JSONDecodeError):
            self._quarantine()
            return None

    def save(self, state: RunState) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(prefix=".state.", dir=self.path.parent)
        tmp = Path(tmp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(state.to_dict(), handle, indent=2, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, self.path)
        finally:
            if tmp.exists():
                tmp.unlink()

    def begin(self, profile: str, plan: list[str], *, resume: bool) -> RunState:
        if resume:
            existing = self.load()
            if existing is not None and existing.is_resumable:
                # Resuming a different plan could silently skip a task that the
                # previous run never attempted. Require the exact same plan;
                # ``--fresh`` is the explicit way to start over.
                if existing.plan != list(plan):
                    raise StateError(
                        "saved state belongs to a different task plan; "
                        "use --fresh to start a new run"
                    )
                existing.profile = profile
                existing.status = RunStatus.RUNNING
                existing.finished_at = None
                existing.updated_at = now_iso()
                existing.tasks = {
                    task_id: task_state
                    for task_id, task_state in existing.tasks.items()
                    if task_id in plan
                }
                return existing
        return RunState.new(profile, plan)

    def reset(self) -> None:
        try:
            self.path.unlink()
        except FileNotFoundError:
            pass

    def _quarantine(self) -> None:
        try:
            target = self.path.with_suffix(self.path.suffix + ".corrupt")
            os.replace(self.path, target)
        except OSError:
            pass
