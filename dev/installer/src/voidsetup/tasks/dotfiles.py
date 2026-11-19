"""Dotfiles tasks: stow, rsync, directories and the optional home backup."""

from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

from ..context import Context
from ..errors import TaskFailed
from ..util import expand_path

_STOW_CONFLICT_RE = re.compile(
    r"cannot stow (?P<package>\S+) over existing target (?P<target>.+?) since"
)


async def make_user_dirs(ctx: Context) -> None:
    for raw in ctx.settings.user_dirs:
        directory = expand_path(raw)
        await ctx.mkdir(directory)
        if directory.name == ".ssh" and not ctx.dry_run:
            directory.chmod(0o700)


async def check_user_dirs(ctx: Context) -> bool:
    return all(expand_path(raw).is_dir() for raw in ctx.settings.user_dirs)


async def make_root_dirs(ctx: Context) -> None:
    seen: set[Path] = set()
    for raw in ctx.settings.root_dirs:
        directory = expand_path(raw)
        if directory in seen:
            continue
        seen.add(directory)
        await ctx.mkdir(directory, root=True)


async def check_root_dirs(ctx: Context) -> bool:
    return all(expand_path(raw).is_dir() for raw in ctx.settings.root_dirs)


async def backup_home(ctx: Context) -> None:
    """Move everything except dotfiles and bak into a timestamped folder."""

    if not ctx.options.allow_destructive:
        raise RuntimeError("backup_home requires --allow-destructive")
    home = Path.home()
    keep = {"dotfiles", "bak"}
    entries = sorted(
        (entry for entry in home.iterdir() if entry.name not in keep),
        key=lambda entry: entry.name,
    )
    if not entries:
        ctx.logger.info("home already contains only dotfiles and bak")
        return

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    destination = home / "bak" / stamp
    if ctx.dry_run:
        for entry in entries:
            ctx.logger.command(f"[dry-run] move {entry} -> {destination / entry.name}")
        return
    destination.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        target = destination / entry.name
        ctx.logger.warn(f"moving {entry} -> {target}")
        shutil.move(str(entry), str(target))


async def check_backup_home(ctx: Context) -> bool:
    home = Path.home()
    keep = {"dotfiles", "bak"}
    return not any(entry.name not in keep for entry in home.iterdir())


def _stow_command(ctx: Context, *extra: str) -> list[str]:
    dotfiles = ctx.settings.dotfiles
    return [
        "stow",
        *extra,
        "--restow",
        "--target",
        str(Path.home()),
        "--dir",
        str(dotfiles),
        ".",
    ]


def parse_stow_conflicts(output: str) -> list[Path]:
    """Extract conflicting target paths from GNU Stow's simulate output."""

    conflicts: list[Path] = []
    for line in output.splitlines():
        match = _STOW_CONFLICT_RE.search(line)
        if not match:
            continue
        target = match.group("target").strip()
        path = Path(target)
        if not path.is_absolute():
            path = Path.home() / path
        if path not in conflicts:
            conflicts.append(path)
    return conflicts


async def _simulate_stow(ctx: Context) -> tuple[int, str]:
    # This is a read-only probe and must run even in dry-run mode.
    result = await ctx.probe_result(*_stow_command(ctx, "--simulate"), check=False)
    return result.returncode, result.output


async def stow_dotfiles(ctx: Context) -> None:
    ctx.require("stow")
    dotfiles = ctx.settings.dotfiles
    if not dotfiles.is_dir():
        raise TaskFailed(f"dotfiles directory not found: {dotfiles}")

    returncode, output = await _simulate_stow(ctx)
    conflicts = parse_stow_conflicts(output)
    if conflicts:
        listing = "\n".join(f"  - {path}" for path in conflicts)
        if ctx.dry_run:
            ctx.logger.warn(f"stow would hit {len(conflicts)} conflicting file(s):")
            for path in conflicts:
                ctx.logger.warn(f"  - {path}")
            if not ctx.options.allow_destructive:
                ctx.logger.warn(
                    "without --allow-destructive the real run would stop here"
                )
            ctx.skip("dry-run: stow conflicts detected")
        if not ctx.options.allow_destructive:
            raise TaskFailed(
                f"stow found {len(conflicts)} conflicting target file(s):\n{listing}\n"
                "Move them aside, or pass --allow-destructive to back them up "
                "under the state directory automatically."
            )
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_root = ctx.settings.state_dir / "stow-backups" / stamp
        home = Path.home()
        for path in conflicts:
            try:
                relative = path.relative_to(home)
            except ValueError:
                relative = Path(path.name)
            destination = backup_root / relative
            await ctx.mkdir(destination.parent)
            if destination.exists():
                raise TaskFailed(f"backup target already exists: {destination}")
            ctx.logger.warn(f"moving conflicting target {path} -> {destination}")
            await ctx.run("mv", "--", str(path), str(destination))
        ctx.logger.warn(f"conflicting files were backed up to {backup_root}")

    await ctx.run(*_stow_command(ctx), cwd=dotfiles)


async def check_stow(ctx: Context) -> bool:
    dotfiles = ctx.settings.dotfiles
    if not dotfiles.is_dir() or shutil.which("stow") is None:
        return False
    try:
        returncode, output = await _simulate_stow(ctx)
    except Exception:
        return False
    if returncode != 0 or "would cause conflicts" in output or "All operations aborted" in output:
        return False
    markers = ("LINK:", "UNLINK:", "MKDIR:", "RMDIR:")
    return not any(marker in output for marker in markers)


async def copy_configs(ctx: Context) -> None:
    ctx.require("rsync")
    copied = 0
    for pair in ctx.settings.rsync_pairs:
        source = ctx.settings.dotfiles / pair.src
        destination = expand_path(pair.dest)
        if not source.exists():
            ctx.logger.warn(f"source not found, skipping: {source}")
            continue

        destination_is_dir = pair.contents or str(pair.dest).endswith(("/", "\\"))
        directory = destination if destination_is_dir else destination.parent
        await ctx.mkdir(directory, root=pair.root_owned)

        source_arg = str(source) + ("/" if pair.contents else "")
        destination_arg = str(destination) + ("/" if destination_is_dir else "")
        for arg in (source_arg, destination_arg):
            if "\n" in arg:
                raise TaskFailed("newline in rsync path")

        if pair.root_owned:
            command = ["rsync", "-aAX", "--chown=root:root"]
        else:
            # -a would try to preserve ownership; a normal user cannot do that.
            command = ["rsync", "-rlpt"]
        command.extend([source_arg, destination_arg])

        await ctx.run(*command, sudo=pair.root_owned)
        copied += 1
        ctx.logger.info(f"copied {source} -> {destination}")

    if copied == 0:
        ctx.skip("none of the configured copy sources exist")


async def make_files(ctx: Context) -> None:
    directory = Path.home() / "mpd"
    await ctx.mkdir(directory)
    for name in ("mpd.db", "mpd.pid", "mpdstate", "mpd.log"):
        path = directory / name
        if ctx.dry_run:
            ctx.logger.command(f"[dry-run] touch {path}")
            continue
        path.touch()
        ctx.logger.info(f"touched {path}")


async def check_files(ctx: Context) -> bool:
    directory = Path.home() / "mpd"
    return all((directory / name).exists() for name in ("mpd.db", "mpd.pid", "mpdstate", "mpd.log"))


async def remove_stray_template_dir(ctx: Context) -> None:
    """Repair the trailing-space directory created by the old script."""

    stray = Path.home() / ".config/tmux/templates/ "
    if not stray.exists():
        ctx.skip("no stray tmux directory")
    await ctx.remove(stray)
