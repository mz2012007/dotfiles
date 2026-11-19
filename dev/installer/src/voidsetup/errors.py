"""Exceptions used across voidsetup."""

from __future__ import annotations


class VoidSetupError(Exception):
    """Base class for expected, user-facing errors."""


class ConfigError(VoidSetupError):
    """The configuration is missing or invalid."""


class PlanningError(VoidSetupError):
    """The requested task plan is invalid."""


class StateError(VoidSetupError):
    """The saved state cannot be used for the requested run."""


class SudoError(VoidSetupError):
    """A sudo session could not be created or refreshed."""


class CommandError(VoidSetupError):
    """A subprocess returned a non-zero exit code."""

    def __init__(self, command: tuple[str, ...], returncode: int, output: str = "") -> None:
        self.command = command
        self.returncode = returncode
        self.output = output
        rendered = " ".join(command)
        detail = f": {output}" if output else ""
        super().__init__(f"command failed ({returncode}): {rendered}{detail}")


class SkipTask(VoidSetupError):
    """Raised by a task to signal that it is intentionally not applicable."""

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


class ExecutionCancelled(VoidSetupError):
    """Raised when the user aborts a run."""


class TaskFailed(VoidSetupError):
    """A task failed with a user-facing explanation."""
