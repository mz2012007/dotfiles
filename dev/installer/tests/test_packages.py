from __future__ import annotations

from pathlib import Path

import pytest

from voidsetup.errors import ConfigError
from voidsetup.packages import (
    PackageCatalog,
    PackageSelection,
    conflicting_groups,
    installed_check_package,
    missing_packages,
    parse_local_package_names,
    parse_package_groups,
    validate_package_names,
)


def test_parse_inline_and_multiline_arrays() -> None:
    catalog = parse_package_groups(
        """\
# comment
base=(bash sudo)
gui=(
  alacritty  # inline comment
  firefox
)
quoted=("hello world" 'single quoted')
"""
    )
    assert catalog.groups["base"] == ("bash", "sudo")
    assert catalog.groups["gui"] == ("alacritty", "firefox")
    # spaces are rejected by the safe-name filter
    assert "hello world" not in catalog.groups["quoted"]


def test_parse_unclosed_array_is_reported() -> None:
    catalog = parse_package_groups("broken=(bash sudo\n")
    assert catalog.groups["broken"] == ("bash", "sudo")
    assert any("unclosed" in warning for warning in catalog.warnings)


def test_parse_duplicate_group_keeps_last() -> None:
    catalog = parse_package_groups("x=(one)\nx=(two)\n")
    assert catalog.groups["x"] == ("two",)
    assert any("duplicate" in warning for warning in catalog.warnings)


def test_bluetooth_alias_resolves_to_typo_group() -> None:
    catalog = parse_package_groups("blutouth=(bluez blueman)\n")
    packages, unknown = catalog.resolve(["bluetooth"])
    assert unknown == ()
    assert packages == ("bluez", "blueman")
    assert catalog.count("bluetooth") == 2
    assert catalog.display_name("blutouth") == "bluetooth"
    assert catalog.has_group("bluetooth")
    assert not catalog.has_group("nope")


def test_resolve_deduplicates_and_preserves_order() -> None:
    catalog = parse_package_groups("a=(one two)\nb=(two three)\n")
    packages, unknown = catalog.resolve(["b", "a", "missing"])
    assert packages == ("two", "three", "one")
    assert unknown == ("missing",)


def test_load_missing_file_raises(tmp_path: Path) -> None:
    with pytest.raises(ConfigError):
        PackageCatalog.load(tmp_path / "missing.sh")


def test_installed_and_missing_packages() -> None:
    listing = "ii bash-5.2_1 x86_64\nii sudo-1.9_1 x86_64\n"
    assert installed_check_package("bash", listing)
    assert not installed_check_package("ba", listing)  # must not prefix-match
    assert missing_packages(["bash", "firefox"], listing) == ["firefox"]


def test_parse_local_package_names() -> None:
    paths = [
        Path("/tmp/ccze-2.19_1.x86_64.xbps"),
        Path("/tmp/tool-1.0_1.noarch.xbps"),
        Path("/tmp/xmonad"),
        Path("/tmp/not-a-package.xbps"),
    ]
    assert parse_local_package_names(paths) == ["ccze", "tool"]


def test_conflicting_groups() -> None:
    assert conflicting_groups(["sound_pulseaudio", "sound_pipewire"])
    assert conflicting_groups(["sound_pulseaudio"]) == []


def test_resolve_appends_manual_packages_without_duplicates() -> None:
    catalog = parse_package_groups("base=(bash coreutils)\n")
    packages, unknown = catalog.resolve(["base"], ["vim", "bash", "git"])
    assert packages == ("bash", "coreutils", "vim", "git")
    assert unknown == ()
    assert catalog.resolve_selection(PackageSelection(("base",), ("vim",)))[0] == (
        "bash",
        "coreutils",
        "vim",
    )


def test_package_selection_normalizes_and_reports_empty() -> None:
    assert PackageSelection().is_empty
    selection = PackageSelection(("base", "base"), ("vim", " vim", "vim"))
    assert selection.normalized() == PackageSelection(("base",), ("vim",))
    assert not selection.is_empty


@pytest.mark.parametrize("name", ["bad name", "vim;rm", "../etc/passwd", "pkg$(id)"])
def test_unsafe_manual_package_names_are_rejected(name: str) -> None:
    with pytest.raises(ValueError, match="invalid package name"):
        validate_package_names([name])


def test_empty_manual_names_are_ignored() -> None:
    assert validate_package_names(["", "  ", "vim"]) == ("vim",)
