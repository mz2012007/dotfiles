"""System-level tasks: repositories, time, updates, DNS, sysctl, firewall."""

from __future__ import annotations

import shutil
from pathlib import Path

from ..context import Context
from ..util import has_immutable

SYSCTL_CONTENT = """\
# Managed by voidsetup. Keep local overrides in this file or another drop-in.
vm.swappiness = 60
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 65536
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs = 3000
vm.page-cluster = 0
"""


async def add_repos(ctx: Context) -> None:
    for repo in ctx.settings.repos:
        await ctx.write_file(repo.config_path, repo.content, root=True)
        ctx.logger.info(f"repository {repo.name}: {repo.url}")


async def check_repos(ctx: Context) -> bool:
    for repo in ctx.settings.repos:
        try:
            text = repo.config_path.read_text(encoding="utf-8")
        except OSError:
            return False
        if text.strip() != f"repository={repo.url}":
            return False
    return True


async def set_timezone(ctx: Context) -> None:
    zone = Path("/usr/share/zoneinfo") / ctx.settings.timezone
    if not zone.exists():
        ctx.skip(f"timezone not found: {ctx.settings.timezone}")
    await ctx.symlink(zone, "/etc/localtime", root=True)
    if shutil.which("chronyc"):
        await ctx.run("chronyc", "makestep", sudo=True, check=False)


async def check_timezone(ctx: Context) -> bool:
    zone = Path("/usr/share/zoneinfo") / ctx.settings.timezone
    try:
        return Path("/etc/localtime").resolve() == zone.resolve()
    except OSError:
        return False


async def sync_time(ctx: Context) -> None:
    did_something = False
    if shutil.which("chronyc"):
        await ctx.run("chronyc", "makestep", sudo=True, check=False)
        did_something = True
    if shutil.which("hwclock"):
        await ctx.run("hwclock", "--systohc", sudo=True, check=False)
        did_something = True
    if not did_something:
        ctx.skip("neither chronyc nor hwclock is installed")


async def update_system(ctx: Context) -> None:
    ctx.require("xbps-install")
    await ctx.run("xbps-install", "-Syu", "-y", sudo=True)
    await ctx.run("xbps-install", "-uy", "xbps", sudo=True, check=False)
    await ctx.run("xbps-install", "-Syu", "-y", sudo=True)


async def write_sysctl(ctx: Context) -> None:
    await ctx.write_file(ctx.settings.sysctl_file, SYSCTL_CONTENT, root=True)
    await ctx.run("sysctl", "--system", sudo=True, check=False)


async def check_sysctl(ctx: Context) -> bool:
    try:
        return ctx.settings.sysctl_file.read_text(encoding="utf-8") == SYSCTL_CONTENT
    except OSError:
        return False


async def manage_dns(ctx: Context) -> None:
    source = ctx.settings.dotfiles / ctx.settings.resolv_source
    if not source.is_file():
        ctx.skip(f"resolv.conf source not found: {source}")
    content = source.read_text(encoding="utf-8")
    target = ctx.settings.resolv_target
    await ctx.write_file(target, content, root=True, clear_immutable=True)
    if ctx.settings.resolv_immutable:
        await ctx.run("chattr", "+i", str(target), sudo=True, check=False)
    else:
        ctx.logger.info(
            "resolv.conf is left mutable so NetworkManager/DHCP can update DNS; "
            "set resolv_immutable = true to pin it"
        )


async def check_dns(ctx: Context) -> bool:
    source = ctx.settings.dotfiles / ctx.settings.resolv_source
    target = ctx.settings.resolv_target
    try:
        if source.read_text(encoding="utf-8") != target.read_text(encoding="utf-8"):
            return False
        if target.stat().st_uid != 0:
            return False
    except OSError:
        return False
    return has_immutable(target) == ctx.settings.resolv_immutable


async def enable_ufw(ctx: Context) -> None:
    if shutil.which("ufw") is None:
        ctx.skip("ufw is not installed")
    await ctx.run("ufw", "default", "deny", "incoming", sudo=True)
    await ctx.run("ufw", "default", "allow", "outgoing", sudo=True)
    await ctx.run("ufw", "--force", "enable", sudo=True)


async def check_ufw(ctx: Context) -> bool:
    try:
        text = Path("/etc/ufw/ufw.conf").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return any(line.strip().upper() == "ENABLED=YES" for line in text.splitlines())
