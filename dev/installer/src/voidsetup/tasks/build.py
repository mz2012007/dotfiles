"""Build local programs and install user-level extras."""

from __future__ import annotations

import shutil
from pathlib import Path

from ..context import Context
from ..packages import missing_packages, parse_local_package_names
from ..util import get_plymouth_themes


async def build_dwm(ctx: Context) -> None:
    directory = ctx.settings.dotfiles / ctx.settings.dwm_dir
    if not directory.is_dir():
        ctx.skip(f"dwm directory not found: {directory}")
    ctx.require("make")
    await ctx.run("make", "clean", cwd=directory)
    await ctx.run("make", cwd=directory)
    await ctx.run("make", "install", sudo=True, cwd=directory)


async def build_dwmblocks(ctx: Context) -> None:
    directory = ctx.settings.dotfiles / ctx.settings.dwmblocks_dir
    if not directory.is_dir():
        ctx.skip(f"dwmblocks directory not found: {directory}")
    ctx.require("make")
    await ctx.run("make", "clean", cwd=directory)
    await ctx.run("make", cwd=directory)
    await ctx.run("make", "install", sudo=True, cwd=directory)


async def install_tpm(ctx: Context) -> None:
    tpm = Path.home() / ctx.settings.tpm_dir
    if tpm.is_dir():
        await ctx.run("git", "-C", str(tpm), "pull", "--ff-only", check=False)
    else:
        await ctx.run("git", "clone", "--depth", "1", ctx.settings.tpm_repo, str(tpm))
    installer = tpm / "bin" / "install_plugins"
    if installer.is_file():
        await ctx.run(str(installer), check=False)
    else:
        ctx.logger.warn("TPM install_plugins not found; open tmux and press prefix + I")


async def check_tpm(ctx: Context) -> bool:
    return (Path.home() / ctx.settings.tpm_dir / "bin" / "install_plugins").is_file()


async def install_mpv(ctx: Context) -> None:
    mpv = Path.home() / ctx.settings.mpv_dir
    if mpv.is_dir():
        await ctx.run("git", "-C", str(mpv), "pull", "--ff-only", check=False)
        return
    await ctx.run(
        "git",
        "clone",
        "--depth",
        "1",
        "--filter=blob:none",
        "--sparse",
        ctx.settings.mpv_repo,
        str(mpv),
    )
    await ctx.run("git", "-C", str(mpv), "sparse-checkout", "set", "scripts")


async def check_mpv(ctx: Context) -> bool:
    return (Path.home() / ctx.settings.mpv_dir / "scripts").is_dir()


async def install_local_packages(ctx: Context) -> None:
    directory = ctx.settings.dotfiles / ctx.settings.local_pkg_dir
    if not directory.is_dir():
        ctx.skip(f"local package directory not found: {directory}")
    packages = sorted(directory.glob("*.xbps"))
    if not packages:
        ctx.skip("no local .xbps packages")
    names = parse_local_package_names(packages)
    if not names:
        ctx.skip("could not derive package names from local .xbps files")

    await ctx.run("xbps-rindex", "-a", *(str(path) for path in packages), cwd=directory)
    listing = await ctx.probe("xbps-query", "-l")
    missing = missing_packages(names, listing)
    if not missing:
        ctx.logger.info("all local packages are already installed")
        return
    await ctx.run(
        "xbps-install",
        "-Suy",
        "--repository",
        str(directory),
        "-y",
        *missing,
        sudo=True,
    )


async def check_local_packages(ctx: Context) -> bool:
    directory = ctx.settings.dotfiles / ctx.settings.local_pkg_dir
    packages = sorted(directory.glob("*.xbps"))
    if not packages:
        return True
    names = parse_local_package_names(packages)
    if not names:
        return True
    listing = await ctx.probe("xbps-query", "-l")
    return not missing_packages(names, listing)


async def update_fonts(ctx: Context) -> None:
    if shutil.which("fc-cache") is None:
        ctx.skip("fc-cache is not installed")
    await ctx.run("fc-cache", "-f")


async def set_plymouth(ctx: Context) -> None:
    theme = ctx.plymouth_theme
    if not theme:
        ctx.skip("no Plymouth theme configured (use --plymouth-theme or config)")
    themes = get_plymouth_themes()
    if themes and theme not in themes:
        raise ValueError(f"unknown Plymouth theme {theme!r}; available: {', '.join(themes)}")
    if shutil.which("plymouth-set-default-theme") is None:
        ctx.skip("plymouth-set-default-theme is not installed")
    await ctx.run("plymouth-set-default-theme", "-R", theme, sudo=True)


async def check_plymouth(ctx: Context) -> bool:
    if not ctx.plymouth_theme:
        return False
    try:
        current = (await ctx.probe("plymouth-set-default-theme")).strip()
    except Exception:
        return False
    return current == ctx.plymouth_theme


async def update_grub(ctx: Context) -> None:
    if shutil.which("grub-mkconfig") is None:
        ctx.skip("grub-mkconfig is not installed")
    await ctx.run("grub-mkconfig", "-o", "/boot/grub/grub.cfg", sudo=True)
