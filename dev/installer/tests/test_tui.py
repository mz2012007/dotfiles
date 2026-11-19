from __future__ import annotations

from textual.widgets import Button, SelectionList

from voidsetup.app import VoidSetupApp
from voidsetup.models import RunOptions, TaskResult, TaskStatus
from voidsetup.screens.execution import ExecutionScreen
from voidsetup.screens.plan import PackagesScreen, PlanScreen
from voidsetup.screens.profile import ProfileScreen
from voidsetup.screens.summary import SummaryScreen
from voidsetup.screens.theme import ThemeScreen
from voidsetup.screens.welcome import WelcomeScreen


async def test_navigation_and_package_modal(settings) -> None:
    app = VoidSetupApp(settings, initial_profile="during_work", dry_run=True)
    async with app.run_test(size=(120, 42)) as pilot:
        await pilot.pause()
        assert isinstance(app.screen, WelcomeScreen)

        await pilot.click("#start")
        await pilot.pause()
        assert isinstance(app.screen, ProfileScreen)

        await pilot.press("enter")
        await pilot.pause()
        assert isinstance(app.screen, PlanScreen)
        assert app.screen.profile.id == "during_work"

        await pilot.click("#packages")
        await pilot.pause()
        assert isinstance(app.screen, PackagesScreen)
        assert len(app.screen.catalog.groups) > 0

        await pilot.press("escape")
        await pilot.pause()
        assert isinstance(app.screen, PlanScreen)


async def test_dry_run_execution_reaches_summary(settings) -> None:
    app = VoidSetupApp(settings, dry_run=True)
    async with app.run_test(size=(120, 42)) as pilot:
        app.push_screen(ExecutionScreen(["fonts"], RunOptions(profile="custom", dry_run=True)))
        for _ in range(80):
            await pilot.pause(0.05)
            if isinstance(app.screen, SummaryScreen):
                break
        assert isinstance(app.screen, SummaryScreen)
        assert len(app.last_results) == 1
        assert app.last_results[0].task_id == "fonts"
        assert app.screen.fatal_error is None
        assert app.screen.query_one("#resume", Button).disabled


async def test_summary_offers_resume_after_failure(settings) -> None:
    app = VoidSetupApp(settings)
    async with app.run_test(size=(120, 42)) as pilot:
        app.push_screen(
            SummaryScreen(
                results=[TaskResult("packages", TaskStatus.FAILED, error="boom")],
                options=RunOptions(profile="custom"),
                log_path=None,
                plan=["update", "packages"],
            )
        )
        await pilot.pause()
        screen = app.screen
        assert isinstance(screen, SummaryScreen)
        assert not screen.query_one("#resume", Button).disabled


async def test_manual_package_selection_adds_packages_task(settings) -> None:
    app = VoidSetupApp(settings, initial_profile="during_work", dry_run=True)
    async with app.run_test(size=(120, 44)) as pilot:
        await pilot.click("#start")
        await pilot.pause()
        await pilot.press("enter")
        await pilot.pause()
        await pilot.click("#packages")
        await pilot.pause()
        await pilot.click("#tab-packages")
        await pilot.pause()
        await pilot.press("space")
        await pilot.pause()
        await pilot.click("#package-add")
        await pilot.pause()
        for character in "vim":
            await pilot.press(character)
        await pilot.press("enter")
        await pilot.pause()
        await pilot.click("#apply")
        await pilot.pause()

        assert isinstance(app.screen, PlanScreen)
        assert "vim" in app.manual_packages
        assert len(app.manual_packages) == 2
        tasks = app.screen.query_one("#task-list", SelectionList)
        assert "packages" in tasks.selected


async def test_theme_scheme_can_be_previewed_and_saved(settings, tmp_path) -> None:
    config = tmp_path / "config.toml"
    config.write_text('admin_group = "wheel"\n')
    settings = settings.with_overrides(config_file=config)
    app = VoidSetupApp(settings, dry_run=True)
    original = str(app.theme)
    async with app.run_test(size=(120, 44)) as pilot:
        await pilot.press("ctrl+t")
        await pilot.pause()
        assert isinstance(app.screen, ThemeScreen)
        await pilot.press("down")
        await pilot.pause()
        chosen = app.screen.current
        assert chosen != original
        assert str(app.theme) == chosen
        await pilot.click("#apply")
        await pilot.pause()
        assert str(app.theme) == chosen
        assert f'tui_theme = "{chosen}"' in config.read_text()


async def test_theme_cancel_restores_previous_scheme(settings, tmp_path) -> None:
    config = tmp_path / "config.toml"
    app = VoidSetupApp(settings.with_overrides(config_file=config), dry_run=True)
    original = str(app.theme)
    async with app.run_test(size=(120, 44)) as pilot:
        await pilot.press("ctrl+t")
        await pilot.pause()
        await pilot.press("down")
        await pilot.pause()
        await pilot.press("escape")
        await pilot.pause()
        assert str(app.theme) == original
        assert not config.exists()


def test_summary_counts_blocked_required_as_failure(settings) -> None:
    screen = SummaryScreen(
        results=[TaskResult("packages", TaskStatus.BLOCKED, error="dependency failed")],
        options=RunOptions(profile="custom"),
        log_path=None,
    )
    assert screen._failed_required()

    optional = SummaryScreen(
        results=[TaskResult("fonts", TaskStatus.BLOCKED, error="dependency failed")],
        options=RunOptions(profile="custom"),
        log_path=None,
    )
    assert not optional._failed_required()

