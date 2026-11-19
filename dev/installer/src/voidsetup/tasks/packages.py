"""Install package groups and manually selected packages from packages.sh."""

from __future__ import annotations

from ..context import Context
from ..packages import PackageCatalog, PackageSelection, missing_packages


def _selected(ctx: Context) -> PackageSelection:
    return PackageSelection(
        groups=tuple(ctx.package_groups or ctx.options.package_groups),
        packages=tuple(ctx.manual_packages or ctx.options.manual_packages),
    )


def _load_catalog(ctx: Context) -> PackageCatalog:
    return PackageCatalog.load(ctx.settings.packages_path)


def _resolve(ctx: Context) -> tuple[PackageSelection, tuple[str, ...], tuple[str, ...]]:
    selection = _selected(ctx).normalized()
    if selection.groups:
        packages, unknown = _load_catalog(ctx).resolve_selection(selection)
    else:
        # Manual-only selections do not need packages.sh at all.
        packages, unknown = selection.packages, ()
    return selection, packages, unknown


async def install_packages(ctx: Context) -> None:
    selection, packages, unknown = _resolve(ctx)
    if selection.is_empty:
        ctx.skip("no package groups or individual packages selected")
    if unknown:
        raise ValueError("unknown package groups: " + ", ".join(unknown))
    if not packages:
        ctx.skip("selected packages contain no package names")

    listing = await ctx.probe("xbps-query", "-l")
    missing = missing_packages(packages, listing)
    if not missing:
        ctx.logger.info("all selected packages are already installed")
        return

    ctx.logger.info(
        f"installing {len(missing)} packages "
        f"from {len(selection.groups)} group(s) and {len(selection.packages)} manual package(s)"
    )
    await ctx.run("xbps-install", "-Suy", "-y", *missing, sudo=True)


async def check_packages(ctx: Context) -> bool:
    selection, packages, unknown = _resolve(ctx)
    if selection.is_empty:
        return True
    if unknown:
        raise ValueError("unknown package groups: " + ", ".join(unknown))
    listing = await ctx.probe("xbps-query", "-l")
    return not missing_packages(packages, listing)
