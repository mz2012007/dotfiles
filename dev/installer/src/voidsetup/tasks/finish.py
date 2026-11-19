"""Final notification task."""

from __future__ import annotations

import os
import shutil

from ..context import Context


async def finish(ctx: Context) -> None:
    log_path = ctx.logger.path
    ctx.logger.info("Void Linux setup finished")
    if log_path:
        ctx.logger.info(f"log: {log_path}")
    if shutil.which("notify-send") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        await ctx.run(
            "notify-send",
            "voidsetup",
            "Void Linux setup finished",
            check=False,
        )
