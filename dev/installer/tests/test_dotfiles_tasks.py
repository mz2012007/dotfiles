from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import pytest

from voidsetup.config import RsyncPair
from voidsetup.errors import SkipTask
from voidsetup.tasks import dotfiles
from voidsetup.tasks.dotfiles import (
    check_user_dirs,
    copy_configs,
    make_user_dirs,
    parse_stow_conflicts,
)

CONFLICT_OUTPUT = (
    "WARNING! stowing . would cause conflicts:\n"
    "  * cannot stow dotfiles/.config/mimeapps.list over existing target "
    ".config/mimeapps.list since neither a link nor a directory and --adopt "
    "not specified\n"
    "All operations aborted.\n"
)


def test_parse_stow_conflicts() -> None:
    output = """\
WARNING! stowing . would cause conflicts:
  * cannot stow dotfiles/.config/mimeapps.list over existing target .config/mimeapps.list since neither a link nor a directory and --adopt not specified
  * cannot stow dotfiles/.config/pavucontrol.ini over existing target .config/pavucontrol.ini since neither a link nor a directory and --adopt not specified
All operations aborted.
"""
    conflicts = parse_stow_conflicts(output)
    assert conflicts == [
        Path.home() / ".config/mimeapps.list",
        Path.home() / ".config/pavucontrol.ini",
    ]


def test_parse_stow_conflicts_ignores_links() -> None:
    assert parse_stow_conflicts("LINK: .config/foo => dotfiles/.config/foo\n") == []


async def test_copy_configs_dry_run(make_context, settings, tmp_path: Path) -> None:
    source = settings.dotfiles / "my-config/myroot/etc/hosts"
    destination = tmp_path / "etc" / "hosts"
    ctx = make_context(dry_run=True)
    ctx.settings = replace(
        ctx.settings,
        rsync_pairs=(RsyncPair("my-config/myroot/etc/hosts", str(destination)),),
    )
    await copy_configs(ctx)
    assert source.is_file()
    assert not destination.exists()


async def test_copy_configs_copies_file(make_context, settings, tmp_path: Path) -> None:
    destination = tmp_path / "etc" / "hosts"
    ctx = make_context()
    ctx.settings = replace(
        ctx.settings,
        rsync_pairs=(RsyncPair("my-config/myroot/etc/hosts", str(destination)),),
    )
    await copy_configs(ctx)
    assert destination.read_text() == "127.0.0.1 localhost\n"


async def test_copy_configs_copies_directory_contents(
    make_context, settings, tmp_path: Path
) -> None:
    source_dir = settings.dotfiles / "my-config/myroot/etc/extra"
    source_dir.mkdir(parents=True)
    (source_dir / "one.conf").write_text("one\n")
    (source_dir / "nested").mkdir()
    (source_dir / "nested" / "two.conf").write_text("two\n")
    destination = tmp_path / "target"
    ctx = make_context()
    ctx.settings = replace(
        ctx.settings,
        rsync_pairs=(
            RsyncPair("my-config/myroot/etc/extra", str(destination), contents=True),
        ),
    )
    await copy_configs(ctx)
    assert (destination / "one.conf").read_text() == "one\n"
    assert (destination / "nested" / "two.conf").read_text() == "two\n"


async def test_missing_source_is_skipped(make_context, settings, tmp_path: Path) -> None:
    ctx = make_context()
    ctx.settings = replace(
        ctx.settings,
        rsync_pairs=(RsyncPair("does/not/exist", str(tmp_path / "unused")),),
    )
    with pytest.raises(SkipTask):
        await copy_configs(ctx)


async def test_check_stow_detects_conflicts(monkeypatch, make_context) -> None:
    monkeypatch.setattr(dotfiles.shutil, "which", lambda name: "/usr/bin/stow")

    async def fake_simulate(_ctx):
        return 1, CONFLICT_OUTPUT

    monkeypatch.setattr(dotfiles, "_simulate_stow", fake_simulate)
    assert not await dotfiles.check_stow(make_context())


async def test_stow_dry_run_skips_on_conflicts(monkeypatch, make_context) -> None:
    monkeypatch.setattr(dotfiles.shutil, "which", lambda name: "/usr/bin/stow")

    async def fake_simulate(_ctx):
        return 1, CONFLICT_OUTPUT

    monkeypatch.setattr(dotfiles, "_simulate_stow", fake_simulate)
    with pytest.raises(SkipTask) as excinfo:
        await dotfiles.stow_dotfiles(make_context(dry_run=True))
    assert "conflict" in excinfo.value.reason.lower()


async def test_user_dirs_are_created(make_context, tmp_path: Path) -> None:
    first = tmp_path / "one"
    second = tmp_path / "two"
    ctx = make_context()
    ctx.settings = replace(ctx.settings, user_dirs=(str(first), str(second)))
    assert not await check_user_dirs(ctx)
    await make_user_dirs(ctx)
    assert first.is_dir() and second.is_dir()
    assert await check_user_dirs(ctx)
