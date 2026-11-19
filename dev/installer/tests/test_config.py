from __future__ import annotations

import tomllib
from pathlib import Path

import pytest

from voidsetup.config import Settings, default_config_toml, load_settings, save_tui_theme
from voidsetup.errors import ConfigError


def test_defaults_are_hermetic(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("VOIDSETUP_CONFIG", raising=False)
    monkeypatch.delenv("VOIDSETUP_DOTFILES", raising=False)
    monkeypatch.delenv("VOIDSETUP_STATE_DIR", raising=False)

    settings = load_settings()
    assert settings.dotfiles == tmp_path / "dotfiles"
    assert settings.state_dir == tmp_path / ".local" / "state" / "voidsetup"
    assert settings.config_file == tmp_path / ".config" / "voidsetup" / "config.toml"


def test_environment_overrides(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("VOIDSETUP_DOTFILES", str(tmp_path / "df"))
    monkeypatch.setenv("VOIDSETUP_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("VOIDSETUP_CONFIG", str(tmp_path / "missing.toml"))
    settings = load_settings()
    assert settings.dotfiles == tmp_path / "df"
    assert settings.state_dir == tmp_path / "st"


def test_toml_overrides(tmp_path: Path) -> None:
    config = tmp_path / "config.toml"
    config.write_text(
        """\
dotfiles = "/srv/dotfiles"
state_dir = "/srv/state"
timezone = "UTC"
services = ["dbus", "elogind"]
groups = ["wheel", "audio"]
resolv_immutable = true
admin_group = "wheel"
plymouth_theme = "bgrt"
log_keep = 5

[[repos]]
name = "test"
url = "https://example.invalid/repo"
"""
    )
    settings = load_settings(config)
    assert settings.dotfiles == Path("/srv/dotfiles")
    assert settings.state_dir == Path("/srv/state")
    assert settings.timezone == "UTC"
    assert settings.services == ("dbus", "elogind")
    assert settings.groups == ("wheel", "audio")
    assert settings.resolv_immutable is True
    assert settings.plymouth_theme == "bgrt"
    assert settings.log_keep == 5
    assert settings.repos[0].name == "test"


def test_missing_explicit_config_is_an_error(tmp_path: Path) -> None:
    with pytest.raises(ConfigError):
        load_settings(tmp_path / "missing.toml")


def test_invalid_toml_is_an_error(tmp_path: Path) -> None:
    config = tmp_path / "config.toml"
    config.write_text("this is not toml = [")
    with pytest.raises(ConfigError):
        load_settings(config)


@pytest.mark.parametrize(
    "body",
    [
        'groups = ["bad group"]',
        'services = ["bad/service"]',
        'timezone = "Cairo"',
        'timezone = "../etc/passwd"',
        "timezone = 5",
        "log_keep = 0",
        'log_keep = "5"',
        "log_keep = true",
        'resolv_immutable = "false"',
        "power_polkit = 1",
        'resolv_target = "relative/path"',
        'resolv_source = "../outside"',
        "plymouth_theme = 5",
        'tui_theme = ""',
        "tui_theme = 5",
        'admin_group = "bad group"',
        '[[repos]]\nname = "x"\nurl = "ftp://example.com"',
    ],
)
def test_invalid_settings_are_rejected(tmp_path: Path, body: str) -> None:
    config = tmp_path / "config.toml"
    config.write_text(body + "\n")
    with pytest.raises(ConfigError):
        load_settings(config)


def test_sample_config_is_valid_toml() -> None:
    data = tomllib.loads(default_config_toml())
    assert data["admin_group"] == "wheel"
    assert data["resolv_immutable"] is False
    assert data["tui_theme"] == "textual-dark"
    assert len(data["repos"]) == 2


def test_save_tui_theme_preserves_other_settings(tmp_path: Path) -> None:
    config = tmp_path / "configs" / "config.toml"
    config.parent.mkdir()
    config.write_text('# keep this comment\ndotfiles = "~/dotfiles"\ntui_theme = "nord"\n')

    assert load_settings(config).tui_theme == "nord"
    save_tui_theme(config, "dracula")

    text = config.read_text()
    assert "# keep this comment" in text
    assert 'dotfiles = "~/dotfiles"' in text
    assert 'tui_theme = "dracula"' in text
    assert load_settings(config).tui_theme == "dracula"


def test_save_tui_theme_creates_missing_config(tmp_path: Path) -> None:
    config = tmp_path / "new" / "config.toml"
    save_tui_theme(config, "gruvbox")
    assert load_settings(config).tui_theme == "gruvbox"


def test_with_overrides() -> None:
    settings = Settings()
    updated = settings.with_overrides(timezone="UTC", log_keep=2)
    assert updated.timezone == "UTC"
    assert updated.log_keep == 2
    assert settings.timezone == "Africa/Cairo"
