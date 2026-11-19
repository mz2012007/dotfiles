from __future__ import annotations

from pathlib import Path

from voidsetup.config import Settings
from voidsetup.models import CheckResult
from voidsetup.preflight import check_environment, required_failures


def _void(monkeypatch) -> None:
    monkeypatch.setattr(
        "voidsetup.preflight._os_release",
        lambda: {"ID": "void", "PRETTY_NAME": "Void Linux"},
    )


def test_required_failures_only_counts_required_fails() -> None:
    checks = [
        CheckResult("a", "a", "fail", required=True),
        CheckResult("b", "b", "fail", required=False),
        CheckResult("c", "c", "warn", required=True),
        CheckResult("d", "d", "ok", required=True),
    ]
    assert [check.id for check in required_failures(checks)] == ["a"]


def test_environment_ok_on_void(monkeypatch, settings: Settings) -> None:
    _void(monkeypatch)
    monkeypatch.setattr("voidsetup.preflight.shutil.which", lambda name: f"/usr/bin/{name}")
    checks = check_environment(settings, ["packages"], package_groups=["base"])
    assert not required_failures(checks)
    by_id = {check.id: check for check in checks}
    assert by_id["os"].status == "ok"
    assert by_id["packages-file"].status == "ok"
    assert by_id["package-groups"].status == "ok"


def test_unknown_package_group_fails(monkeypatch, settings: Settings) -> None:
    _void(monkeypatch)
    monkeypatch.setattr("voidsetup.preflight.shutil.which", lambda name: f"/usr/bin/{name}")
    checks = check_environment(settings, ["packages"], package_groups=["nope"])
    failures = required_failures(checks)
    assert failures
    assert any("unknown" in check.detail for check in failures)


def test_missing_packages_file_fails_when_needed(monkeypatch, tmp_path: Path) -> None:
    _void(monkeypatch)
    monkeypatch.setattr("voidsetup.preflight.shutil.which", lambda name: f"/usr/bin/{name}")
    bare = Settings(dotfiles=tmp_path, state_dir=tmp_path / "state")
    checks = check_environment(bare, ["packages"], package_groups=["base"])
    assert any(check.id == "packages-file" and check.failed for check in checks)
    assert required_failures(checks)


def test_missing_command_is_reported(monkeypatch, settings: Settings) -> None:
    _void(monkeypatch)
    monkeypatch.setattr(
        "voidsetup.preflight.shutil.which",
        lambda name: None if name == "stow" else f"/usr/bin/{name}",
    )
    checks = check_environment(settings, ["stow"])
    stow = next(check for check in checks if check.id == "command-stow")
    assert stow.failed
    assert stow.required


def test_audit_is_read_only_and_returns_checks(settings: Settings) -> None:
    from voidsetup.preflight import audit_system

    checks = audit_system(settings)
    assert all(isinstance(check, CheckResult) for check in checks)
