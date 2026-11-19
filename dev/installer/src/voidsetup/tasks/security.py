"""A narrow polkit replacement for the old SUID hacks."""

from __future__ import annotations

import stat
from pathlib import Path

from ..context import Context

# These are the binaries the old installer made SUID. None of them need the
# bit: polkit and sudo are the supported mechanisms on Void Linux.
LEGACY_SUID_PATHS = (
    Path("/usr/bin/sleep"),
    Path("/usr/sbin/sleep"),
    Path("/usr/bin/poweroff"),
    Path("/usr/sbin/poweroff"),
    Path("/usr/bin/reboot"),
    Path("/usr/sbin/reboot"),
    Path("/usr/bin/hostname"),
    Path("/usr/sbin/hostname"),
    Path("/usr/bin/zzz"),
    Path("/usr/sbin/zzz"),
)


def legacy_suid_paths() -> list[Path]:
    """Return existing legacy binaries that still carry the SUID bit."""

    found: list[Path] = []
    for path in LEGACY_SUID_PATHS:
        try:
            if stat.S_ISUID & path.stat().st_mode:
                found.append(path)
        except OSError:
            continue
    return found


def power_rule(admin_group: str) -> str:
    return f"""\
// Managed by voidsetup. Allows local, active members of {admin_group} to
// power off, reboot or suspend without SUID binaries.
polkit.addRule(function(action, subject) {{
    if ((action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.reboot" ||
         action.id == "org.freedesktop.login1.suspend") &&
        subject.local && subject.active && subject.isInGroup("{admin_group}")) {{
        return polkit.Result.YES;
    }}
}});
"""


async def install_power_polkit(ctx: Context) -> None:
    if not ctx.settings.power_polkit:
        ctx.skip("power polkit rule disabled in config")
    path = Path("/etc/polkit-1/rules.d/60-voidsetup-power.rules")
    await ctx.write_file(path, power_rule(ctx.settings.admin_group), root=True)


async def check_power_polkit(ctx: Context) -> bool:
    if not ctx.settings.power_polkit:
        return True
    path = Path("/etc/polkit-1/rules.d/60-voidsetup-power.rules")
    try:
        return path.read_text(encoding="utf-8") == power_rule(ctx.settings.admin_group)
    except OSError:
        return False


async def remove_legacy_suid(ctx: Context) -> None:
    """Remove the SUID bits left behind by the old installer."""

    found = legacy_suid_paths()
    if not found:
        ctx.skip("no legacy SUID bits found")

    for path in found:
        ctx.logger.warn(f"removing legacy SUID bit from {path}")
        await ctx.run("chmod", "u-s", str(path), sudo=True)

    ctx.logger.info(f"removed SUID from {len(found)} legacy binary path(s)")


async def check_legacy_suid(ctx: Context) -> bool:
    return not legacy_suid_paths()
