from __future__ import annotations

from textual.widgets import SelectionList

from voidsetup.app import VoidSetupApp
from voidsetup.packages import parse_package_groups
from voidsetup.screens.plan import PackagesScreen


async def test_probe_package_click(settings) -> None:
    app = VoidSetupApp(settings)
    catalog = parse_package_groups(
        "base=(bash coreutils)\ngui=(alacritty firefox)\n"
    )
    async with app.run_test(size=(120, 42)) as pilot:
        captured: list[object] = []
        app.push_screen(PackagesScreen([], catalog), callback=captured.append)
        await pilot.pause()
        screen = app.screen
        assert isinstance(screen, PackagesScreen)
        selection = screen.query_one("#group-list", SelectionList)
        print("widget region", selection.region)
        print("options", selection._options)
        # Click directly on the first option row.
        await pilot.click(selection, offset=(5, 1))
        await pilot.pause()
        print("after click selected", selection.selected, "highlighted", selection.highlighted)
        assert selection.selected == ["base"]

        await pilot.click("#all")
        await pilot.pause()
        print("after all", selection.selected)
        assert set(selection.selected) == {"base", "gui"}

        await pilot.click("#apply")
        await pilot.pause()
        print("callback", captured)
        assert captured == [["base", "gui"]]
