"""Runit services and user group membership."""

from __future__ import annotations

import grp
import os
import pwd
from pathlib import Path

from ..context import Context

DENIED_GROUPS = {
    "root",
    "daemon",
    "bin",
    "sys",
    "kmem",
    "mail",
    "nogroup",
    "utmp",
    "tty",
    "xbuilder",
    "dnsmasq",
    "_dhcpcd",
}

# Not automatically rejected: some users really do want these, but they are
# effectively root-equivalent and must be a deliberate choice.
POWERFUL_GROUPS = {
    "disk": "raw block-device access is effectively root access",
    "docker": "the docker daemon socket is effectively root access",
    "libvirt": "the libvirt socket can control virtual machines and host devices",
}


def _existing_group(name: str) -> bool:
    try:
        grp.getgrnam(name)
        return True
    except KeyError:
        return False


def _user_group_names() -> set[str]:
    try:
        user = pwd.getpwuid(os.geteuid()).pw_name
        gids = os.getgrouplist(user, pwd.getpwuid(os.geteuid()).pw_gid)
        return {grp.getgrgid(gid).gr_name for gid in gids}
    except (KeyError, OSError):
        return set()


async def enable_services(ctx: Context) -> None:
    enabled = 0
    for name in ctx.settings.services:
        service = Path("/etc/sv") / name
        link = Path("/var/service") / name
        if not service.exists():
            ctx.logger.warn(f"service not installed, skipping: {name}")
            continue
        if link.is_symlink() and os.readlink(link) == str(service):
            continue
        await ctx.run("ln", "-sfnT", str(service), str(link), sudo=True, quiet=True)
        enabled += 1
    if enabled == 0:
        ctx.logger.info("all available services are already enabled")
    else:
        ctx.logger.info(f"enabled {enabled} service(s)")


async def check_services(ctx: Context) -> bool:
    for name in ctx.settings.services:
        service = Path("/etc/sv") / name
        if not service.exists():
            continue
        link = Path("/var/service") / name
        if not link.is_symlink() or os.readlink(link) != str(service):
            return False
    return True


async def add_groups(ctx: Context) -> None:
    current = _user_group_names()
    wanted: list[str] = []
    for name in ctx.settings.groups:
        if name in DENIED_GROUPS:
            ctx.logger.warn(f"refusing to add the user to privileged/system group: {name}")
            continue
        if not _existing_group(name):
            ctx.logger.warn(f"group does not exist, skipping: {name}")
            continue
        if name in POWERFUL_GROUPS:
            ctx.logger.warn(f"adding powerful group {name}: {POWERFUL_GROUPS[name]}")
        if name not in current and name not in wanted:
            wanted.append(name)

    if not wanted:
        ctx.logger.info("user already belongs to all configured groups")
        return

    user = pwd.getpwuid(os.geteuid()).pw_name
    await ctx.run("usermod", "-aG", ",".join(wanted), user, sudo=True)
    ctx.logger.warn("group changes take effect after you log out and back in")


async def check_groups(ctx: Context) -> bool:
    current = _user_group_names()
    for name in ctx.settings.groups:
        if name in DENIED_GROUPS or not _existing_group(name):
            continue
        if name not in current:
            return False
    return True
