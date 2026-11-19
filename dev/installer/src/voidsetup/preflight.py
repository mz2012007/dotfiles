"""Preflight checks and a non-destructive audit of old installer damage."""

from __future__ import annotations

import grp
import os
import pwd
import shutil
import stat
import subprocess
from pathlib import Path
from typing import Iterable

from .config import Settings
from .models import CheckResult, Severity
from .packages import PackageCatalog, conflicting_groups
from .registry import TASKS
from .util import has_immutable, path_owner_name

COMMAND_REQUIREMENTS: dict[str, tuple[str, ...]] = {
    "repos": ("xbps-install",),
    "update": ("xbps-install",),
    "packages": ("xbps-install",),
    "local_packages": ("xbps-install", "xbps-rindex"),
    "stow": ("stow",),
    "copy_configs": ("rsync",),
    "tmux": ("git",),
    "mpv": ("git",),
    "dwm": ("make",),
    "dwmblocks": ("make",),
    "fonts": ("fc-cache",),
    "ufw": ("ufw",),
    "plymouth": ("plymouth-set-default-theme",),
    "grub": ("grub-mkconfig",),
}


def _check(check_id: str, label: str, status: str, detail: str = "", *, required: bool = False) -> CheckResult:
    return CheckResult(id=check_id, label=label, status=status, detail=detail, required=required)


def _os_release() -> dict[str, str]:
    path = Path("/etc/os-release")
    if not path.is_file():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"')
    return values


def current_user_groups() -> set[str]:
    try:
        user = pwd.getpwuid(os.geteuid()).pw_name
        gids = os.getgrouplist(user, pwd.getpwuid(os.geteuid()).pw_gid)
        return {grp.getgrgid(gid).gr_name for gid in gids}
    except (KeyError, OSError):
        return set()


def check_environment(
    settings: Settings,
    plan: Iterable[str] = (),
    *,
    package_groups: Iterable[str] = (),
    manual_packages: Iterable[str] = (),
    audit: bool = False,
) -> list[CheckResult]:
    plan_list = list(plan)
    checks: list[CheckResult] = []

    release = _os_release()
    is_void = release.get("ID") == "void" or "Void" in release.get("NAME", "")
    checks.append(
        _check(
            "os",
            "Void Linux",
            "ok" if is_void else "fail",
            release.get("PRETTY_NAME", "unknown distribution"),
            required=True,
        )
    )

    if os.geteuid() == 0:
        checks.append(_check("root", "Not running as root", "fail", "run voidsetup as your user", required=True))
    else:
        checks.append(_check("root", "Not running as root", "ok", pwd.getpwuid(os.geteuid()).pw_name))

    dotfiles = settings.dotfiles
    checks.append(
        _check(
            "dotfiles",
            "Dotfiles directory",
            "ok" if dotfiles.is_dir() else "fail",
            str(dotfiles),
            required=True,
        )
    )
    # Manual-only package selections do not need packages.sh.
    packages_needed = "local_packages" in plan_list or (
        "packages" in plan_list and bool(tuple(package_groups))
    )
    packages_path = settings.packages_path
    if packages_path.is_file():
        checks.append(_check("packages-file", "packages.sh", "ok", str(packages_path)))
    else:
        checks.append(
            _check(
                "packages-file",
                "packages.sh",
                "fail" if packages_needed else "warn",
                str(packages_path),
                required=packages_needed,
            )
        )

    if packages_path.is_file() and packages_needed:
        try:
            catalog = PackageCatalog.load(packages_path)
        except Exception as exc:  # ConfigError
            checks.append(_check("packages-parse", "Package groups", "fail", str(exc), required=True))
        else:
            groups = tuple(package_groups)
            manual = tuple(manual_packages)
            unknown: tuple[str, ...] = ()
            if groups or manual:
                _, unknown = catalog.resolve(groups, manual)
            if unknown:
                checks.append(
                    _check(
                        "package-groups",
                        "Selected packages",
                        "fail",
                        "unknown: " + ", ".join(unknown),
                        required=True,
                    )
                )
            elif "packages" in plan_list and not groups and not manual:
                checks.append(
                    _check(
                        "package-groups",
                        "Selected packages",
                        "warn",
                        "none selected; the packages task will be skipped",
                    )
                )
            else:
                details = ", ".join([*groups, *manual]) or "not needed"
                checks.append(
                    _check(
                        "package-groups",
                        "Selected packages",
                        "ok",
                        details,
                    )
                )
            for conflict in conflicting_groups(package_groups):
                checks.append(_check("package-conflict", "Package conflicts", "warn", conflict))

    needed_commands: dict[str, set[str]] = {}
    root_tasks: list[str] = []
    for task_id in plan_list:
        task = TASKS.get(task_id)
        if task is None:
            continue
        if task.requires_root:
            root_tasks.append(task_id)
            needed_commands.setdefault("sudo", set()).add(task_id)
        for command in COMMAND_REQUIREMENTS.get(task_id, ()):
            needed_commands.setdefault(command, set()).add(task_id)

    for command in sorted(needed_commands):
        source_tasks = needed_commands[command]
        required = any(TASKS[task_id].severity is Severity.REQUIRED for task_id in source_tasks)
        found = shutil.which(command)
        checks.append(
            _check(
                f"command-{command}",
                f"Command: {command}",
                "ok" if found else ("fail" if required else "warn"),
                found or "not found",
                required=required and not found,
            )
        )

    if root_tasks and shutil.which("sudo") and os.geteuid() != 0:
        try:
            result = subprocess.run(
                ["sudo", "-n", "-v"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            result = None
        if result is not None and result.returncode == 0:
            checks.append(_check("sudo-session", "sudo session", "ok", "cached"))
        else:
            checks.append(
                _check(
                    "sudo-session",
                    "sudo session",
                    "warn",
                    "not cached; voidsetup will ask before root tasks",
                )
            )

    if dotfiles.is_dir() and not (dotfiles / ".stow-local-ignore").exists():
        checks.append(
            _check(
                "stow-ignore",
                "stow ignore file",
                "warn",
                ".stow-local-ignore not found; stow may link unexpected files",
            )
        )

    if "stow" in plan_list and dotfiles.is_dir() and shutil.which("stow"):
        try:
            result = subprocess.run(
                [
                    "stow",
                    "--simulate",
                    "--restow",
                    "--target",
                    str(Path.home()),
                    "--dir",
                    str(dotfiles),
                    ".",
                ],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            result = None
        if result is not None:
            from .tasks.dotfiles import parse_stow_conflicts

            conflicts = parse_stow_conflicts(result.stdout + result.stderr)
            if conflicts:
                checks.append(
                    _check(
                        "stow-conflicts",
                        "stow conflicts",
                        "warn",
                        f"{len(conflicts)} existing target file(s) conflict; the stow task "
                        "will stop unless --allow-destructive backs them up",
                    )
                )
            elif result.returncode == 0:
                checks.append(_check("stow-conflicts", "stow conflicts", "ok", "none"))
            else:
                detail = (result.stdout + result.stderr).strip().splitlines()
                checks.append(
                    _check(
                        "stow-conflicts",
                        "stow conflicts",
                        "warn",
                        detail[0] if detail else "stow --simulate failed",
                    )
                )

    if audit:
        checks.extend(audit_system(settings))

    return checks


def audit_system(settings: Settings) -> list[CheckResult]:
    """Detect leftovers from the old script that are worth fixing."""

    checks: list[CheckResult] = []
    user = pwd.getpwuid(os.geteuid()).pw_name
    uid = os.geteuid()

    # resolv.conf ownership and immutable flag
    resolv = settings.resolv_target
    if resolv.exists():
        owner = path_owner_name(resolv)
        if owner and owner != "root":
            checks.append(
                _check(
                    "resolv-owner",
                    "resolv.conf ownership",
                    "warn",
                    f"owned by {owner}; system DNS config should be root-owned",
                )
            )
        immutable = has_immutable(resolv)
        if immutable and not settings.resolv_immutable:
            checks.append(
                _check(
                    "resolv-immutable",
                    "resolv.conf immutable flag",
                    "warn",
                    "set by the old installer; NetworkManager cannot update DNS (use the dns task to fix)",
                )
            )
        elif immutable:
            checks.append(_check("resolv-immutable", "resolv.conf immutable flag", "info", "configured"))
        else:
            checks.append(_check("resolv-immutable", "resolv.conf immutable flag", "ok", "not set"))

    # unnecessary SUID bits
    for raw_path in (
        "/usr/bin/sleep",
        "/usr/sbin/sleep",
        "/usr/bin/poweroff",
        "/usr/sbin/poweroff",
        "/usr/bin/reboot",
        "/usr/sbin/reboot",
        "/usr/bin/hostname",
        "/usr/sbin/hostname",
        "/usr/bin/zzz",
        "/usr/sbin/zzz",
    ):
        path = Path(raw_path)
        try:
            mode = path.stat().st_mode
        except OSError:
            continue
        if mode & stat.S_ISUID:
            checks.append(
                _check(
                    f"suid-{path.name}",
                    f"SUID bit: {path}",
                    "warn",
                    "unnecessary privilege-escalation surface; prefer polkit/sudoers",
                )
            )

    groups = current_user_groups()
    if "root" in groups:
        checks.append(
            _check(
                "root-group",
                f"User {user} is in the root group",
                "fail",
                "remove the user from group root: sudo gpasswd -d USER root",
                required=True,
            )
        )
    else:
        checks.append(_check("root-group", "Root group membership", "ok", "not a member"))

    try:
        log_stat = Path("/var/log").stat()
        if log_stat.st_uid == uid:
            checks.append(
                _check(
                    "var-log-owner",
                    "/var/log ownership",
                    "warn",
                    f"owned by {user}; the old script recursively chowned system logs",
                )
            )
    except OSError:
        pass

    docker_sock = Path("/var/run/docker.sock")
    try:
        sock_stat = docker_sock.stat()
        if sock_stat.st_uid == uid:
            checks.append(
                _check(
                    "docker-sock-owner",
                    "docker.sock ownership",
                    "warn",
                    f"owned by {user}; add the user to the docker group instead of chowning the socket",
                )
            )
    except OSError:
        pass

    stray_template = Path.home() / ".config/tmux/templates/ "
    if stray_template.exists():
        checks.append(
            _check(
                "tmux-stray-dir",
                "Stray tmux directory",
                "warn",
                f"remove the directory with the trailing space: {stray_template!r}",
            )
        )

    sysctl_conf = Path("/etc/sysctl.conf")
    try:
        text = sysctl_conf.read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""
    if "vm.swappiness = 60" in text and "vm.min_free_kbytes = 65536" in text:
        checks.append(
            _check(
                "sysctl-legacy",
                "/etc/sysctl.conf legacy tuning",
                "warn",
                "the old script replaced this file; move custom values to /etc/sysctl.d/99-voidsetup.conf",
            )
        )

    return checks


def required_failures(checks: Iterable[CheckResult]) -> list[CheckResult]:
    return [check for check in checks if check.failed and check.required]
