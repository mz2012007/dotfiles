"""Core data models: tasks, profiles, results and run options."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING, Awaitable, Callable

if TYPE_CHECKING:
    from .context import Context

_ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class Severity(str, Enum):
    REQUIRED = "required"
    OPTIONAL = "optional"


class TaskStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    OK = "ok"
    FAILED = "failed"
    SKIPPED = "skipped"
    BLOCKED = "blocked"
    ABORTED = "aborted"

    @property
    def successful(self) -> bool:
        return self in (TaskStatus.OK, TaskStatus.SKIPPED)

    @property
    def terminal(self) -> bool:
        return self is not TaskStatus.PENDING and self is not TaskStatus.RUNNING


class RunStatus(str, Enum):
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    ABORTED = "aborted"


TaskFunc = Callable[["Context"], Awaitable[None]]
CheckFunc = Callable[["Context"], Awaitable[bool]]
RollbackFunc = Callable[["Context"], Awaitable[None]]


@dataclass(frozen=True, slots=True)
class Task:
    """A single, independently runnable setup step."""

    id: str
    name: str
    description: str
    func: TaskFunc
    group: str = "core"
    requires_root: bool = False
    severity: Severity = Severity.REQUIRED
    depends_on: tuple[str, ...] = ()
    dangerous: bool = False
    check: CheckFunc | None = None
    rollback: RollbackFunc | None = None

    def __post_init__(self) -> None:
        if not _ID_RE.fullmatch(self.id):
            raise ValueError(f"invalid task id: {self.id!r}")
        if not self.name.strip():
            raise ValueError(f"task {self.id!r} has an empty name")
        for dep in self.depends_on:
            if not _ID_RE.fullmatch(dep):
                raise ValueError(f"task {self.id!r} has invalid dependency {dep!r}")


@dataclass(frozen=True, slots=True)
class Profile:
    """A named, ordered list of task ids."""

    id: str
    name: str
    description: str
    tasks: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class RunOptions:
    """Options that affect one execution of a plan."""

    profile: str = "custom"
    dry_run: bool = False
    resume: bool = False
    allow_destructive: bool = False
    reboot: bool = False
    assume_yes: bool = False
    package_groups: tuple[str, ...] = ()
    manual_packages: tuple[str, ...] = ()
    plymouth_theme: str | None = None


@dataclass(slots=True)
class TaskResult:
    task_id: str
    status: TaskStatus
    duration: float = 0.0
    error: str | None = None
    detail: str | None = None

    @property
    def ok(self) -> bool:
        return self.status.successful


@dataclass(slots=True)
class CheckResult:
    """Result of one preflight or audit check."""

    id: str
    label: str
    status: str
    detail: str = ""
    required: bool = False

    @property
    def failed(self) -> bool:
        return self.status == "fail"

    @property
    def warned(self) -> bool:
        return self.status == "warn"


def default_task_order(tasks: dict[str, Task]) -> list[str]:
    """Return ids in registry insertion order."""

    return list(tasks)


__all__ = [
    "CheckResult",
    "Profile",
    "RollbackFunc",
    "RunOptions",
    "RunStatus",
    "Severity",
    "Task",
    "TaskResult",
    "TaskStatus",
]
