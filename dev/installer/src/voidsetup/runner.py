"""Async subprocess runner with dry-run, streaming output and cancellation."""

from __future__ import annotations

import asyncio
import os
import shlex
import signal
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

from .errors import CommandError, ExecutionCancelled
from .session_log import SessionLogger
from .util import quote_command


@dataclass(frozen=True, slots=True)
class CommandResult:
    command: tuple[str, ...]
    returncode: int
    output: str = ""

    @property
    def ok(self) -> bool:
        return self.returncode == 0


class Runner:
    """Run system commands sequentially.

    ``run`` never executes anything in dry-run mode. Read-only probes should
    use :meth:`output`, which deliberately still runs so checks can report
    whether a task is already complete.
    """

    def __init__(self, logger: SessionLogger, *, dry_run: bool = False) -> None:
        self.logger = logger
        self.dry_run = dry_run
        self._current: asyncio.subprocess.Process | None = None
        self._cancel_event = asyncio.Event()
        self._keepalive: asyncio.Task[None] | None = None
        self._started_at = 0.0

    @property
    def cancelled(self) -> bool:
        return self._cancel_event.is_set()

    def reset_cancel(self) -> None:
        self._cancel_event.clear()

    async def run(
        self,
        *args: str | os.PathLike[str],
        sudo: bool = False,
        check: bool = True,
        cwd: str | Path | None = None,
        env: Mapping[str, str] | None = None,
        input: str | bytes | None = None,
        timeout: float | None = None,
        quiet: bool = False,
        capture: bool = False,
    ) -> CommandResult:
        """Execute a command, streaming its combined stdout/stderr."""

        command = tuple(str(arg) for arg in args)
        full = ("sudo", "-n", *command) if sudo else command
        rendered = quote_command(full)

        if self.dry_run:
            self.logger.command(f"[dry-run] {rendered}")
            return CommandResult(full, 0, "")

        if self.cancelled:
            raise ExecutionCancelled("run cancelled")

        self.logger.command(rendered)
        child_env = {**os.environ, **(env or {})}
        stdin_mode = asyncio.subprocess.PIPE if input is not None else asyncio.subprocess.DEVNULL

        started = time.monotonic()
        try:
            proc = await asyncio.create_subprocess_exec(
                *full,
                cwd=str(cwd) if cwd else None,
                env=child_env,
                stdin=stdin_mode,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                start_new_session=True,
            )
        except FileNotFoundError as exc:
            raise CommandError(full, 127, str(exc)) from exc
        except PermissionError as exc:
            raise CommandError(full, 126, str(exc)) from exc

        self._current = proc
        captured: list[str] = []
        tail: deque[str] = deque(maxlen=200)
        try:
            async with asyncio.timeout(timeout):
                if input is not None and proc.stdin is not None:
                    payload = input.encode() if isinstance(input, str) else input
                    proc.stdin.write(payload)
                    await proc.stdin.drain()
                    proc.stdin.close()

                assert proc.stdout is not None
                async for raw_line in proc.stdout:
                    line = raw_line.decode(errors="replace").rstrip("\r\n")
                    if not line:
                        continue
                    tail.append(line)
                    if capture:
                        captured.append(line)
                    if not quiet:
                        self.logger.output(line)

                returncode = await proc.wait()
        except TimeoutError as exc:
            # A timeout is local to this command; do not mark the whole run
            # as cancelled (that would make every later task fail).
            await self._terminate(proc)
            raise CommandError(full, 124, f"timed out after {timeout}s") from exc
        finally:
            self._current = None

        elapsed = time.monotonic() - started
        self.logger.debug(f"finished in {elapsed:.2f}s with code {returncode}: {rendered}")

        if self.cancelled:
            raise ExecutionCancelled("run cancelled")

        result = CommandResult(full, returncode, "\n".join(captured) or "\n".join(tail))
        if check and returncode != 0:
            raise CommandError(full, returncode, "\n".join(tail))
        return result

    async def probe_result(
        self,
        *args: str | os.PathLike[str],
        sudo: bool = False,
        check: bool = True,
        cwd: str | Path | None = None,
        env: Mapping[str, str] | None = None,
        timeout: float | None = 30,
    ) -> CommandResult:
        """Run a read-only probe and return its exit code and output.

        Probes are intentionally executed even in dry-run mode. They must not
        mutate the system. ``LC_ALL=C`` is set for stable parsing.
        """

        command = tuple(str(arg) for arg in args)
        full = ("sudo", "-n", *command) if sudo else command
        if self.cancelled:
            raise ExecutionCancelled("run cancelled")

        probe_env = {**os.environ, "LC_ALL": "C", **(env or {})}
        self.logger.debug(f"probe: {quote_command(full)}")
        try:
            proc = await asyncio.create_subprocess_exec(
                *full,
                cwd=str(cwd) if cwd else None,
                env=probe_env,
                stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        except FileNotFoundError as exc:
            raise CommandError(full, 127, str(exc)) from exc
        except PermissionError as exc:
            raise CommandError(full, 126, str(exc)) from exc
        except TimeoutError as exc:
            # Do not leave a stray probe process behind.
            try:
                proc.kill()
                await asyncio.wait_for(proc.wait(), timeout=5)
            except (ProcessLookupError, TimeoutError):
                pass
            raise CommandError(full, 124, f"timed out after {timeout}s") from exc

        text = stdout.decode(errors="replace")
        error_text = stderr.decode(errors="replace")
        combined = (text + error_text).strip()
        if self.cancelled:
            raise ExecutionCancelled("run cancelled")
        if check and proc.returncode != 0:
            raise CommandError(full, proc.returncode, combined)
        return CommandResult(full, proc.returncode, combined)

    async def output(
        self,
        *args: str | os.PathLike[str],
        sudo: bool = False,
        check: bool = True,
        cwd: str | Path | None = None,
        env: Mapping[str, str] | None = None,
        timeout: float | None = 30,
    ) -> str:
        result = await self.probe_result(
            *args,
            sudo=sudo,
            check=check,
            cwd=cwd,
            env=env,
            timeout=timeout,
        )
        return result.output

    async def start_keepalive(self, interval: float = 45.0) -> None:
        """Refresh the sudo timestamp in the background."""

        if self.dry_run or self._keepalive is not None:
            return
        self._keepalive = asyncio.create_task(self._keepalive_loop(interval))

    async def _keepalive_loop(self, interval: float) -> None:
        warned = False
        while True:
            await asyncio.sleep(interval)
            try:
                proc = await asyncio.create_subprocess_exec(
                    "sudo",
                    "-n",
                    "-v",
                    stdin=asyncio.subprocess.DEVNULL,
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                code = await proc.wait()
            except OSError:
                code = 1
            if code != 0 and not warned:
                warned = True
                self.logger.warn("sudo session is no longer active; root tasks may fail")

    async def stop_keepalive(self) -> None:
        if self._keepalive is None:
            return
        self._keepalive.cancel()
        try:
            await self._keepalive
        except asyncio.CancelledError:
            pass
        self._keepalive = None

    @staticmethod
    async def _terminate(proc: asyncio.subprocess.Process) -> None:
        if proc.returncode is not None:
            return
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            return
        try:
            await asyncio.wait_for(proc.wait(), timeout=5)
        except TimeoutError:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            await proc.wait()

    async def cancel(self) -> None:
        """Cancel the current command (SIGTERM, then SIGKILL after 5s)."""

        self._cancel_event.set()
        proc = self._current
        if proc is None or proc.returncode is not None:
            return
        await self._terminate(proc)

    def cancel_sync(self) -> None:
        """Best-effort cancellation for shutdown paths that cannot await."""

        self._cancel_event.set()
        proc = self._current
        if proc is not None and proc.returncode is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass


def shell_join(command: Sequence[str]) -> str:
    return shlex.join(command)
