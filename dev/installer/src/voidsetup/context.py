"""Execution context passed to every task."""

from __future__ import annotations

import asyncio
import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import NoReturn

from .config import Settings
from .errors import SkipTask, TaskFailed
from .models import RunOptions
from .runner import CommandResult, Runner
from .session_log import SessionLogger
from .util import atomic_write_text, expand_path, has_immutable


@dataclass(slots=True)
class Context:
    settings: Settings
    runner: Runner
    logger: SessionLogger
    options: RunOptions
    cancel_event: asyncio.Event = field(default_factory=asyncio.Event)
    package_groups: tuple[str, ...] = ()
    manual_packages: tuple[str, ...] = ()
    plymouth_theme: str | None = None

    def __post_init__(self) -> None:
        if self.plymouth_theme is None:
            self.plymouth_theme = self.settings.plymouth_theme

    @property
    def dry_run(self) -> bool:
        return self.options.dry_run

    def path(self, value: str | Path) -> Path:
        return expand_path(value)

    async def run(
        self,
        *args: str | os.PathLike[str],
        sudo: bool = False,
        check: bool = True,
        cwd: str | Path | None = None,
        input: str | bytes | None = None,
        quiet: bool = False,
        capture: bool = False,
        timeout: float | None = None,
    ) -> CommandResult:
        return await self.runner.run(
            *args,
            sudo=sudo,
            check=check,
            cwd=cwd,
            input=input,
            quiet=quiet,
            capture=capture,
            timeout=timeout,
        )

    async def probe(
        self,
        *args: str | os.PathLike[str],
        sudo: bool = False,
        check: bool = True,
    ) -> str:
        return await self.runner.output(*args, sudo=sudo, check=check)

    async def probe_result(
        self,
        *args: str | os.PathLike[str],
        sudo: bool = False,
        check: bool = True,
    ) -> CommandResult:
        return await self.runner.probe_result(*args, sudo=sudo, check=check)

    async def write_file(
        self,
        path: str | Path,
        content: str,
        *,
        root: bool = False,
        mode: int = 0o644,
        clear_immutable: bool = False,
    ) -> None:
        target = self.path(path)
        try:
            unchanged = target.read_text(encoding="utf-8", errors="replace") == content
        except OSError:
            unchanged = False
        if unchanged:
            wrong_owner = False
            if root:
                try:
                    wrong_owner = target.stat().st_uid != 0
                except OSError:
                    wrong_owner = True
            if not wrong_owner and not (clear_immutable and has_immutable(target)):
                self.logger.debug(f"unchanged: {target}")
                return

        if self.dry_run:
            self.logger.command(f"[dry-run] write {target} ({len(content)} bytes)")
            return

        if root:
            await self.mkdir(target.parent, root=True)
            if clear_immutable and has_immutable(target):
                await self.run("chattr", "-i", str(target), sudo=True, check=False, quiet=True)
            await self.run("tee", str(target), sudo=True, input=content, quiet=True)
            await self.run("chmod", f"{mode:o}", str(target), sudo=True, quiet=True)
            await self.run("chown", "root:root", str(target), sudo=True, quiet=True)
            self.logger.info(f"wrote {target}")
            return

        atomic_write_text(target, content, mode=mode)
        self.logger.info(f"wrote {target}")

    async def mkdir(self, path: str | Path, *, root: bool = False, mode: int = 0o755) -> None:
        target = self.path(path)
        if target.is_dir():
            return
        if self.dry_run:
            self.logger.command(f"[dry-run] mkdir -p {target}")
            return
        if root:
            await self.run("install", "-d", "-m", f"{mode:o}", str(target), sudo=True, quiet=True)
        else:
            target.mkdir(parents=True, exist_ok=True)
        self.logger.debug(f"created directory {target}")

    async def symlink(self, target: str | Path, link: str | Path, *, root: bool = False) -> None:
        link_path = self.path(link)
        target_path = self.path(target)
        if link_path.is_symlink() and os.readlink(link_path) == str(target_path):
            return
        if self.dry_run:
            self.logger.command(f"[dry-run] ln -sfn {target_path} {link_path}")
            return
        if root:
            await self.run("ln", "-sfnT", str(target_path), str(link_path), sudo=True, quiet=True)
        else:
            if link_path.exists() or link_path.is_symlink():
                link_path.unlink()
            link_path.parent.mkdir(parents=True, exist_ok=True)
            link_path.symlink_to(target_path)
        self.logger.info(f"linked {link_path} -> {target_path}")

    async def remove(self, path: str | Path, *, root: bool = False) -> None:
        target = self.path(path)
        if not target.exists() and not target.is_symlink():
            return
        if self.dry_run:
            self.logger.command(f"[dry-run] rm -rf -- {target}")
            return
        if root:
            await self.run("rm", "-rf", "--", str(target), sudo=True, quiet=True)
        elif target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        else:
            target.unlink()
        self.logger.info(f"removed {target}")

    def skip(self, reason: str) -> NoReturn:
        raise SkipTask(reason)

    def require(self, command: str) -> None:
        if shutil.which(command) is None:
            raise TaskFailed(f"required command not found: {command}")
