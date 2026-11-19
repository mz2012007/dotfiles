"""Shared fixtures for the voidsetup test suite."""

from __future__ import annotations

from pathlib import Path

import pytest

from voidsetup.config import Settings
from voidsetup.context import Context
from voidsetup.models import RunOptions, Severity, Task
from voidsetup.runner import Runner
from voidsetup.session_log import SessionLogger

PACKAGES_SH = """\
# a small, deterministic package file
base=(bash coreutils sudo)
gui=(alacritty firefox)
blutouth=(bluez blueman)
sound_pulseaudio=(pulseaudio)
sound_pipewire=(pipewire wireplumber)
broken=(bad name)
"""


@pytest.fixture
def dotfiles(tmp_path: Path) -> Path:
    directory = tmp_path / "dotfiles"
    (directory / "my-config" / "myroot").mkdir(parents=True)
    (directory / "my-config" / "myroot" / "etc").mkdir(parents=True)
    (directory / "my-config" / "myroot" / "etc" / "hosts").write_text("127.0.0.1 localhost\n")
    (directory / "packages.sh").write_text(PACKAGES_SH)
    (directory / ".stow-local-ignore").write_text("README.md\n")
    return directory


@pytest.fixture
def settings(dotfiles: Path, tmp_path: Path) -> Settings:
    return Settings(dotfiles=dotfiles, state_dir=tmp_path / "state")


@pytest.fixture
def make_context(settings: Settings):
    """Build a Context with an in-memory logger and a real (unprivileged) runner."""

    def factory(
        *,
        dry_run: bool = False,
        allow_destructive: bool = False,
        groups: tuple[str, ...] = (),
        plymouth_theme: str | None = None,
        resume: bool = False,
    ) -> Context:
        logger = SessionLogger()
        runner = Runner(logger, dry_run=dry_run)
        options = RunOptions(
            dry_run=dry_run,
            allow_destructive=allow_destructive,
            package_groups=groups,
            resume=resume,
            plymouth_theme=plymouth_theme,
        )
        return Context(
            settings=settings,
            runner=runner,
            logger=logger,
            options=options,
            package_groups=groups,
            plymouth_theme=plymouth_theme,
        )

    return factory


def make_task(
    task_id: str,
    func=None,
    *,
    check=None,
    depends_on: tuple[str, ...] = (),
    severity: Severity = Severity.REQUIRED,
    dangerous: bool = False,
    requires_root: bool = False,
    group: str = "test",
) -> Task:
    if func is None:

        async def func(_ctx):  # type: ignore[no-redef]
            return None

    return Task(
        id=task_id,
        name=task_id.replace("_", " ").title(),
        description=f"test task {task_id}",
        func=func,  # type: ignore[arg-type]
        group=group,
        requires_root=requires_root,
        severity=severity,
        depends_on=depends_on,
        dangerous=dangerous,
        check=check,
    )
