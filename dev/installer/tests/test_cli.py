from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from rich.console import Console

from voidsetup.cli import _select_groups, main
from voidsetup.errors import PlanningError
from voidsetup.models import TaskStatus
from voidsetup.state import RunState, StateStore


@pytest.fixture
def cli_env(dotfiles: Path, tmp_path: Path, monkeypatch):
    state = tmp_path / "state"
    monkeypatch.setenv("VOIDSETUP_DOTFILES", str(dotfiles))
    monkeypatch.setenv("VOIDSETUP_STATE_DIR", str(state))
    monkeypatch.setenv("VOIDSETUP_CONFIG", str(tmp_path / "missing-config.toml"))
    monkeypatch.setattr(
        "voidsetup.preflight._os_release",
        lambda: {"ID": "void", "PRETTY_NAME": "Void Linux"},
    )
    return state


def _json(capsys):
    out, err = capsys.readouterr()
    assert out.strip(), err
    return json.loads(out)


def test_plan_json(cli_env, capsys) -> None:
    assert main(["plan", "--profile", "during_work", "--json"]) == 0
    payload = _json(capsys)
    assert payload["profile"] == "during_work"
    ids = [task["id"] for task in payload["tasks"]]
    assert ids[0] == "sync_time"
    assert "packages" in ids


def test_list_json(cli_env, capsys) -> None:
    assert main(["list", "--json"]) == 0
    payload = _json(capsys)
    assert len(payload) > 10
    assert any(task["id"] == "stow" and task["dangerous"] is False for task in payload)


def test_profiles_json(cli_env, capsys) -> None:
    assert main(["profiles", "--json"]) == 0
    payload = _json(capsys)
    assert {profile["id"] for profile in payload} >= {
        "old_lab",
        "during_work",
        "fresh",
        "repair",
        "custom",
    }


def test_packages_json(cli_env, capsys) -> None:
    assert main(["packages", "--json"]) == 0
    payload = _json(capsys)
    assert payload["base"] == ["bash", "coreutils", "sudo"]
    assert payload["blutouth"] == ["bluez", "blueman"]


def test_themes_json(cli_env, capsys) -> None:
    assert main(["themes", "--json"]) == 0
    assert isinstance(_json(capsys), list)


def test_doctor_json(cli_env, capsys) -> None:
    code = main(["doctor", "--json"])
    assert code in (0, 1)
    payload = _json(capsys)
    assert any(check["id"] == "os" for check in payload)
    assert all("status" in check for check in payload)


def test_plan_errors_go_to_stderr_in_json_mode(cli_env, capsys) -> None:
    assert main(["plan", "--tasks", "nope", "--json"]) == 2
    out, err = capsys.readouterr()
    assert out == ""
    assert "unknown task" in err


def test_run_json_requires_yes(cli_env, capsys) -> None:
    assert main(["run", "--profile", "during_work", "--json"]) == 2
    out, err = capsys.readouterr()
    assert out == ""
    assert "--json requires --yes" in err


def test_run_refuses_destructive_without_flag(cli_env, capsys) -> None:
    code = main(["run", "--profile", "fresh", "--dry-run", "--yes"])
    assert code == 2
    out, _ = capsys.readouterr()
    assert "backup_home" in out


def test_run_packages_without_groups_fails(cli_env, capsys) -> None:
    code = main(["run", "--profile", "custom", "--tasks", "packages", "--dry-run", "--yes"])
    assert code == 2
    out, _ = capsys.readouterr()
    assert "no groups" in out


def test_run_dry_run_end_to_end(cli_env, capsys) -> None:
    code = main(
        [
            "run",
            "--profile",
            "during_work",
            "--skip",
            "packages",
            "--dry-run",
            "--yes",
            "--force",
        ]
    )
    out, _ = capsys.readouterr()
    assert code == 0
    assert "dry-run" in out
    assert "Run summary" in out
    assert not (cli_env / "state.json").exists()


def test_run_json_end_to_end(cli_env, capsys) -> None:
    code = main(
        [
            "run",
            "--profile",
            "during_work",
            "--skip",
            "packages",
            "--dry-run",
            "--yes",
            "--json",
            "--force",
        ]
    )
    payload = _json(capsys)
    assert code == 0
    assert payload["ok"] is True
    assert payload["dry_run"] is True
    assert {result["task"] for result in payload["results"]} == {
        "sync_time",
        "update",
        "fonts",
        "finish",
    }


def test_init_config_roundtrip(cli_env, tmp_path: Path, capsys) -> None:
    path = tmp_path / "configs" / "config.toml"
    assert main(["--config", str(path), "init-config"]) == 0
    assert path.is_file()
    assert 'admin_group = "wheel"' in path.read_text()

    assert main(["--config", str(path), "init-config"]) == 1
    assert main(["--config", str(path), "init-config", "--force"]) == 0

    path.write_text("invalid toml = [")
    assert main(["--config", str(path), "init-config", "--force"]) == 0
    assert 'admin_group = "wheel"' in path.read_text()


def test_resume_rejects_a_different_plan(cli_env, capsys) -> None:
    store = StateStore(cli_env / "state.json")
    saved = RunState.new("custom", ["update", "packages"])
    saved.finish_task("update", TaskStatus.OK)
    store.save(saved)

    code = main(["run", "--tasks", "fonts", "--resume", "--dry-run", "--yes"])
    out, _ = capsys.readouterr()
    assert code == 2
    assert "different task plan" in out


def test_schemes_json(cli_env, capsys) -> None:
    assert main(["schemes", "--json"]) == 0
    payload = _json(capsys)
    assert "textual-dark" in payload["themes"]
    assert payload["current"] == "textual-dark"


def test_run_rejects_unsafe_package_name(cli_env, capsys) -> None:
    code = main(
        [
            "run",
            "--profile",
            "custom",
            "--tasks",
            "packages",
            "--packages",
            "vim;rm",
            "--dry-run",
            "--yes",
        ]
    )
    out, _ = capsys.readouterr()
    assert code == 2
    assert "invalid package name" in out


def test_run_installs_manual_packages(cli_env, capsys, monkeypatch) -> None:
    from voidsetup.context import Context

    calls: list[tuple[str, ...]] = []

    async def fake_probe(self, *args, **kwargs) -> str:
        return ""

    async def fake_run(self, *args, **kwargs) -> None:
        calls.append(tuple(str(arg) for arg in args))
        return None

    monkeypatch.setattr(Context, "probe", fake_probe)
    monkeypatch.setattr(Context, "run", fake_run)

    code = main(
        [
            "run",
            "--profile",
            "custom",
            "--tasks",
            "packages",
            "--packages",
            "neovim,git",
            "--dry-run",
            "--yes",
            "--json",
            "--force",
        ]
    )
    payload = _json(capsys)
    assert code == 0
    assert payload["ok"] is True
    assert calls
    # The first call is the `update` dependency; the second is the packages task.
    assert any("neovim" in call and "git" in call for call in calls)


def test_manual_packages_work_without_package_file(
    cli_env, tmp_path: Path, capsys, monkeypatch
) -> None:
    from voidsetup.context import Context

    empty_dotfiles = tmp_path / "empty-dotfiles"
    empty_dotfiles.mkdir()
    monkeypatch.setenv("VOIDSETUP_DOTFILES", str(empty_dotfiles))

    async def fake_probe(self, *args, **kwargs) -> str:
        return ""

    async def fake_run(self, *args, **kwargs) -> None:
        return None

    monkeypatch.setattr(Context, "probe", fake_probe)
    monkeypatch.setattr(Context, "run", fake_run)

    code = main(
        [
            "run",
            "--profile",
            "custom",
            "--tasks",
            "packages",
            "--packages",
            "vim",
            "--dry-run",
            "--yes",
            "--json",
            "--force",
        ]
    )
    payload = _json(capsys)
    assert code == 0
    assert payload["ok"] is True


def test_group_alias_is_accepted(settings) -> None:
    args = SimpleNamespace(all_groups=False, groups="bluetooth")
    assert _select_groups(args, settings, Console()) == ("bluetooth",)


def test_unknown_group_is_rejected(settings) -> None:
    args = SimpleNamespace(all_groups=False, groups="nope")
    with pytest.raises(PlanningError):
        _select_groups(args, settings, Console())
