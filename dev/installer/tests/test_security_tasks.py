from __future__ import annotations

from pathlib import Path

from voidsetup.tasks import security


def _suid_file(path: Path) -> Path:
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(0o4755)
    return path


def test_legacy_suid_paths(monkeypatch, tmp_path: Path) -> None:
    bad = _suid_file(tmp_path / "sleep")
    clean = tmp_path / "poweroff"
    clean.write_text("#!/bin/sh\n")
    clean.chmod(0o755)
    monkeypatch.setattr(security, "LEGACY_SUID_PATHS", (bad, clean, tmp_path / "missing"))
    assert security.legacy_suid_paths() == [bad]


async def test_check_legacy_suid(monkeypatch, tmp_path: Path, make_context) -> None:
    bad = _suid_file(tmp_path / "sleep")
    monkeypatch.setattr(security, "LEGACY_SUID_PATHS", (bad,))
    assert not await security.check_legacy_suid(make_context())

    bad.chmod(0o755)
    assert await security.check_legacy_suid(make_context())


async def test_remove_legacy_suid_dry_run(monkeypatch, tmp_path: Path, make_context) -> None:
    bad = _suid_file(tmp_path / "sleep")
    monkeypatch.setattr(security, "LEGACY_SUID_PATHS", (bad,))
    await security.remove_legacy_suid(make_context(dry_run=True))
    # A dry run must not change the mode.
    assert security.legacy_suid_paths() == [bad]
