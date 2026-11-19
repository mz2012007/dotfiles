"""Sudo session helpers."""

from __future__ import annotations

import os
import shutil
import subprocess

from .errors import SudoError


def sudo_available() -> bool:
    return shutil.which("sudo") is not None


def sudo_cached() -> bool:
    """Return True when ``sudo -n -v`` succeeds without prompting."""

    if os.geteuid() == 0:
        return True
    if not sudo_available():
        return False
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
        return False
    return result.returncode == 0


def ensure_sudo(*, interactive: bool = True) -> None:
    """Create or validate a sudo timestamp.

    The TUI calls this while suspended so the password prompt is shown in the
    normal terminal. Non-interactive callers get a clear error instead.
    """

    if os.geteuid() == 0:
        return
    if not sudo_available():
        raise SudoError("sudo is not installed")
    if sudo_cached():
        return
    if not interactive:
        raise SudoError(
            "sudo needs a password but the session is not cached; "
            "run `sudo -v` first or use --dry-run"
        )
    try:
        result = subprocess.run(["sudo", "-v"], check=False)
    except OSError as exc:
        raise SudoError(f"cannot run sudo: {exc}") from exc
    if result.returncode != 0 or not sudo_cached():
        raise SudoError("sudo authentication failed or was cancelled")
