from __future__ import annotations

import os
from pathlib import Path

import pytest

from voidsetup.errors import SkipTask, TaskFailed


async def test_write_file_creates_parents(make_context, tmp_path: Path) -> None:
    ctx = make_context()
    target = tmp_path / "a" / "b" / "file.conf"
    await ctx.write_file(target, "hello\n")
    assert target.read_text() == "hello\n"


async def test_write_file_is_idempotent(make_context, tmp_path: Path) -> None:
    ctx = make_context()
    target = tmp_path / "file.conf"
    await ctx.write_file(target, "hello\n")
    first = target.stat().st_mtime_ns
    await ctx.write_file(target, "hello\n")
    assert target.stat().st_mtime_ns == first


async def test_write_file_dry_run_changes_nothing(make_context, tmp_path: Path) -> None:
    ctx = make_context(dry_run=True)
    target = tmp_path / "file.conf"
    await ctx.write_file(target, "hello\n")
    assert not target.exists()


async def test_mkdir_and_remove(make_context, tmp_path: Path) -> None:
    ctx = make_context()
    directory = tmp_path / "one" / "two"
    await ctx.mkdir(directory)
    assert directory.is_dir()
    (directory / "file").write_text("x")
    await ctx.remove(directory)
    assert not directory.exists()


async def test_mkdir_dry_run(make_context, tmp_path: Path) -> None:
    ctx = make_context(dry_run=True)
    directory = tmp_path / "not-created"
    await ctx.mkdir(directory)
    assert not directory.exists()


async def test_symlink_and_remove(make_context, tmp_path: Path) -> None:
    ctx = make_context()
    target = tmp_path / "target"
    target.write_text("data")
    link = tmp_path / "link"
    await ctx.symlink(target, link)
    assert link.is_symlink()
    assert os.readlink(link) == str(target)
    await ctx.remove(link)
    assert not link.exists()


async def test_symlink_dry_run(make_context, tmp_path: Path) -> None:
    ctx = make_context(dry_run=True)
    target = tmp_path / "target"
    target.write_text("data")
    link = tmp_path / "link"
    await ctx.symlink(target, link)
    assert not link.exists()


async def test_run_dry_run(make_context) -> None:
    ctx = make_context(dry_run=True)
    result = await ctx.run("true")
    assert result.ok


async def test_probe_really_runs(make_context) -> None:
    ctx = make_context(dry_run=True)
    assert (await ctx.probe("printf", "x")).strip() == "x"


async def test_skip_raises(make_context) -> None:
    ctx = make_context()
    with pytest.raises(SkipTask) as excinfo:
        ctx.skip("not applicable")
    assert excinfo.value.reason == "not applicable"


async def test_require_missing_command(make_context) -> None:
    ctx = make_context()
    with pytest.raises(TaskFailed):
        ctx.require("voidsetup-command-that-does-not-exist")
