from __future__ import annotations

from dataclasses import replace

from voidsetup.context import Context
from voidsetup.tasks import services


async def test_denied_groups_are_never_added(monkeypatch, make_context) -> None:
    monkeypatch.setattr(services, "_existing_group", lambda name: True)
    monkeypatch.setattr(services, "_user_group_names", lambda: set())
    calls: list[tuple[str, ...]] = []

    async def fake_run(self, *args, **kwargs):
        calls.append(tuple(str(arg) for arg in args))

        class Result:
            ok = True
            returncode = 0
            output = ""

        return Result()

    monkeypatch.setattr(Context, "run", fake_run)
    ctx = make_context()
    ctx.settings = replace(
        ctx.settings,
        groups=("root", "sys", "wheel", "audio", "disk"),
    )
    await services.add_groups(ctx)

    assert len(calls) == 1
    assert calls[0][0] == "usermod"
    assert calls[0][2] == "wheel,audio,disk"


async def test_check_groups_ignores_denied_and_missing(monkeypatch, make_context) -> None:
    monkeypatch.setattr(
        services,
        "_existing_group",
        lambda name: name != "does-not-exist",
    )
    monkeypatch.setattr(services, "_user_group_names", lambda: {"wheel"})
    ctx = make_context()
    ctx.settings = replace(
        ctx.settings,
        groups=("wheel", "root", "does-not-exist", "audio"),
    )
    assert not await services.check_groups(ctx)
    ctx.settings = replace(ctx.settings, groups=("wheel", "root", "does-not-exist"))
    assert await services.check_groups(ctx)
