"""Parse the bash package-group file without executing it."""

from __future__ import annotations

import re
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .errors import ConfigError
from .util import is_safe_name

_ASSIGN_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=\((.*)$")
_ALIASES = {"bluetooth": "blutouth"}
_LOCAL_XBPS_RE = re.compile(r"^(?P<name>.+?)-\d[^-]*\.(?:x86_64|noarch)\.xbps$")


@dataclass(frozen=True, slots=True)
class PackageSelection:
    """What the user picked: whole groups and/or individual package names."""

    groups: tuple[str, ...] = ()
    packages: tuple[str, ...] = ()

    @property
    def is_empty(self) -> bool:
        return not self.groups and not self.packages

    def normalized(self) -> "PackageSelection":
        return PackageSelection(
            groups=tuple(dict.fromkeys(self.groups)),
            packages=validate_package_names(self.packages),
        )


def validate_package_names(names: Iterable[str]) -> tuple[str, ...]:
    """Return unique, safe package names; reject anything shell-unsafe."""

    result: list[str] = []
    seen: set[str] = set()
    for raw in names:
        name = str(raw).strip()
        if not name:
            continue
        if not is_safe_name(name):
            raise ValueError(f"invalid package name: {name!r}")
        if name not in seen:
            seen.add(name)
            result.append(name)
    return tuple(result)


@dataclass(frozen=True, slots=True)
class PackageCatalog:
    groups: dict[str, tuple[str, ...]]
    warnings: tuple[str, ...] = ()

    @classmethod
    def load(cls, path: Path) -> "PackageCatalog":
        path = Path(path)
        if not path.is_file():
            raise ConfigError(f"package file not found: {path}")
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise ConfigError(f"cannot read package file {path}: {exc}") from exc
        catalog = parse_package_groups(text)
        if not catalog.groups:
            raise ConfigError(f"no package arrays found in {path}")
        return catalog

    def names(self) -> tuple[str, ...]:
        return tuple(self.groups)

    def canonical(self, group: str) -> str:
        if group in self.groups:
            return group
        alias = _ALIASES.get(group)
        if alias and alias in self.groups:
            return alias
        return group

    def has_group(self, group: str) -> bool:
        return self.canonical(group) in self.groups

    def display_name(self, group: str) -> str:
        """A friendly name for the historical typo groups."""

        canonical = self.canonical(group)
        reverse = {target: alias for alias, target in _ALIASES.items()}
        return reverse.get(canonical, canonical)

    def resolve(
        self,
        selected: Iterable[str],
        extra: Iterable[str] = (),
    ) -> tuple[tuple[str, ...], tuple[str, ...]]:
        """Return (packages, unknown groups), preserving order and de-duplicating.

        *extra* holds manually selected package names. They are appended after
        the groups, so group order stays stable and duplicates are installed once.
        """

        packages: list[str] = []
        unknown: list[str] = []
        seen: set[str] = set()
        for group in selected:
            canonical = self.canonical(group)
            if canonical not in self.groups:
                unknown.append(group)
                continue
            for package in self.groups[canonical]:
                if package not in seen:
                    seen.add(package)
                    packages.append(package)
        for package in validate_package_names(extra):
            if package not in seen:
                seen.add(package)
                packages.append(package)
        return tuple(packages), tuple(unknown)

    def resolve_selection(self, selection: PackageSelection) -> tuple[tuple[str, ...], tuple[str, ...]]:
        return self.resolve(selection.groups, selection.packages)

    def count(self, group: str) -> int:
        return len(self.groups.get(self.canonical(group), ()))


def _strip_comment(line: str) -> str:
    quote: str | None = None
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quote is not None:
            escaped = True
            continue
        if char in ("'", '"'):
            if quote is None:
                quote = char
            elif quote == char:
                quote = None
        elif char == "#" and quote is None:
            return line[:index]
    return line


def _tokenize(content: str) -> list[str]:
    try:
        return shlex.split(content, comments=False, posix=True)
    except ValueError:
        return content.split()


def parse_package_groups(text: str) -> PackageCatalog:
    """Parse simple ``name=(...)`` bash arrays.

    The parser intentionally supports only arrays of plain words, which is all
    the dotfiles package file uses. It never executes the file.
    """

    groups: dict[str, tuple[str, ...]] = {}
    warnings: list[str] = []
    current: str | None = None
    buffer: list[str] = []

    def finish(name: str, content: str) -> None:
        packages = tokenize_packages(name, content, warnings)
        if name in groups:
            warnings.append(f"duplicate group {name!r}; keeping the last definition")
        groups[name] = tuple(packages)

    for raw_line in text.splitlines():
        line = _strip_comment(raw_line)
        if current is None:
            match = _ASSIGN_RE.match(line)
            if not match:
                continue
            current = match.group(1)
            rest = match.group(2)
            if ")" in rest:
                finish(current, rest.split(")", 1)[0])
                current = None
                buffer = []
            else:
                buffer = [rest]
            continue

        if ")" in line:
            buffer.append(line.split(")", 1)[0])
            finish(current, " ".join(buffer))
            current = None
            buffer = []
        else:
            buffer.append(line)

    if current is not None:
        warnings.append(f"unclosed array {current!r}; ignored")
        finish(current, " ".join(buffer))
        warnings.append(f"group {current!r} may be incomplete")

    return PackageCatalog(groups=groups, warnings=tuple(warnings))


def tokenize_packages(group: str, content: str, warnings: list[str]) -> list[str]:
    packages: list[str] = []
    for token in _tokenize(content):
        token = token.strip()
        if not token:
            continue
        if not is_safe_name(token):
            warnings.append(f"ignoring invalid package name {token!r} in {group!r}")
            continue
        packages.append(token)
    return packages


def installed_check_package(package: str, listing: str) -> bool:
    """Whether ``xbps-query -l`` output contains *package*."""

    pattern = re.compile(rf"^ii\s+{re.escape(package)}-", re.MULTILINE)
    return bool(pattern.search(listing))


def missing_packages(packages: Iterable[str], listing: str) -> list[str]:
    return [package for package in packages if not installed_check_package(package, listing)]


def parse_local_package_names(paths: Iterable[Path]) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for path in paths:
        match = _LOCAL_XBPS_RE.match(Path(path).name)
        if not match:
            continue
        name = match.group("name")
        if is_safe_name(name) and name not in seen:
            seen.add(name)
            names.append(name)
    return names


def conflicting_groups(selected: Iterable[str]) -> list[str]:
    """Return human-readable warnings for known conflicting selections."""

    chosen = set(selected)
    conflicts: list[str] = []
    if {"sound_pulseaudio", "sound_pipewire"} <= chosen:
        conflicts.append(
            "sound_pulseaudio and sound_pipewire are both selected; "
            "normally you should pick only one."
        )
    return conflicts
