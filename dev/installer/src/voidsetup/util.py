"""Small filesystem and subprocess helpers."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SAFE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+:@-]*$")


def expand_path(value: str | Path) -> Path:
    """Expand ``~`` and environment variables in a path."""

    return Path(os.path.expandvars(os.path.expanduser(str(value))))


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def atomic_write_text(path: Path, text: str, mode: int = 0o644) -> None:
    """Write text atomically, creating parent directories as needed."""

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def has_immutable(path: Path) -> bool:
    """Return True when the file has the ext2/3/4 immutable attribute.

    This is a best-effort read-only probe; filesystems that do not support
    ``lsattr`` simply return False.
    """

    if not path.exists():
        return False
    if shutil.which("lsattr") is None:
        return False
    try:
        result = subprocess.run(
            ["lsattr", "-d", str(path)],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    if result.returncode != 0 or not result.stdout.strip():
        return False
    attrs = result.stdout.split()[0]
    return "i" in attrs


def path_owner_name(path: Path) -> str:
    """Best-effort owner name for a path (empty when unknown)."""

    try:
        import pwd

        return pwd.getpwuid(path.stat().st_uid).pw_name
    except (ImportError, KeyError, OSError):
        return ""


def prune_logs(log_dir: Path, keep: int = 20) -> list[Path]:
    """Delete old ``*.log`` files, keeping the newest *keep* files."""

    if keep < 1 or not log_dir.is_dir():
        return []
    logs = sorted(
        (path for path in log_dir.glob("*.log") if path.is_file()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    removed: list[Path] = []
    for path in logs[keep:]:
        try:
            path.unlink()
            removed.append(path)
        except OSError:
            pass
    return removed


def get_plymouth_themes() -> list[str]:
    """List installed Plymouth themes without failing when Plymouth is absent."""

    if shutil.which("plymouth-set-default-theme") is None:
        return []
    try:
        result = subprocess.run(
            ["plymouth-set-default-theme", "-l"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def parse_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def is_safe_name(value: str) -> bool:
    return bool(SAFE_NAME_RE.fullmatch(value))


def quote_command(command: tuple[str, ...]) -> str:
    import shlex

    return shlex.join(command)
