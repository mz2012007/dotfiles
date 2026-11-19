"""The Textual application."""

from __future__ import annotations

import asyncio
from dataclasses import replace
from pathlib import Path

from textual.app import App
from textual.binding import Binding

from .config import Settings, save_tui_theme
from .models import RunOptions, TaskResult
from .registry import requires_root
from .screens.execution import ExecutionScreen
from .screens.theme import ThemeScreen
from .screens.welcome import WelcomeScreen
from .sudo import ensure_sudo, sudo_cached
from .errors import SudoError


class VoidSetupApp(App[None]):
    TITLE = "voidsetup"
    SUB_TITLE = "Void Linux setup"
    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit"),
        Binding("ctrl+t", "schemes", "Schemes"),
        Binding("f1", "help", "Help"),
    ]
    CSS = """
    Screen {
        background: $surface;
    }

    .screen-title {
        text-style: bold;
        color: $accent;
        padding: 1 2 0 2;
    }

    .muted {
        color: $text-muted;
        padding: 0 2;
    }

    .label {
        color: $text-muted;
        padding: 1 1 0 1;
    }

    .hint {
        color: $text-muted;
        padding: 1 1;
    }

    .pane-title {
        text-style: bold;
        padding: 1 1 0 1;
    }

    .actions {
        height: auto;
        align: right middle;
        padding: 1 2;
    }

    Button {
        margin-left: 1;
    }

    #welcome-body {
        height: 1fr;
        align: center middle;
    }

    #welcome-card {
        width: 82;
        max-width: 90%;
        height: auto;
        border: round $primary;
        background: $panel;
        padding: 1 2;
    }

    #welcome-title {
        text-align: center;
        text-style: bold;
        color: $accent;
        padding: 1 0;
    }

    #welcome-subtitle {
        text-align: center;
        color: $text-muted;
        padding: 0 1;
    }

    #welcome-version {
        text-align: right;
    }

    #profile-body {
        height: 1fr;
    }

    #profiles {
        height: 1fr;
        margin: 1 2;
        border: round $primary;
    }

    #profile-description {
        margin: 1 2;
        padding: 1 2;
        border: round $primary;
        background: $panel;
    }

    #plan-body {
        height: 1fr;
    }

    #plan-columns {
        height: 1fr;
        padding: 0 2;
    }

    #tasks-pane {
        width: 2fr;
        border: round $primary;
        margin-right: 1;
    }

    #task-list {
        height: 1fr;
    }

    #options-pane {
        width: 42;
        border: round $primary;
        background: $panel;
    }

    #plan-summary {
        padding: 1;
    }

    #exec-body {
        height: 1fr;
    }

    #progress {
        margin: 0 2;
    }

    #exec-columns {
        height: 1fr;
        padding: 0 2;
    }

    #status-pane {
        width: 44%;
        border: round $primary;
        margin-right: 1;
    }

    #status-table {
        height: 1fr;
    }

    #log {
        width: 56%;
        border: round $primary;
        background: $panel;
    }

    #summary-body {
        height: 1fr;
    }

    #summary-table {
        height: 1fr;
        margin: 0 2;
    }

    #summary-log {
        padding: 0 2;
    }

    #doctor-body {
        height: 1fr;
    }

    #doctor-table {
        height: 1fr;
        margin: 0 2;
    }

    PackagesScreen {
        align: center middle;
        background: $background 60%;
    }

    #packages-dialog {
        width: 82;
        max-width: 90%;
        height: 82%;
        border: thick $accent;
        background: $panel;
        padding: 1 2;
    }

    #package-tabs {
        height: auto;
    }

    #groups-pane, #packages-pane {
        height: 1fr;
    }

    #groups-pane SelectionList, #packages-pane SelectionList {
        height: 1fr;
        margin: 1 0;
        border: round $primary;
    }

    #package-filter {
        margin: 1 0 0 0;
    }

    .add-row {
        height: auto;
    }

    .add-row Input {
        width: 1fr;
        margin-right: 1;
    }

    #group-list {
        height: 1fr;
        margin: 1 0;
        border: round $primary;
    }

    ThemeScreen {
        align: center middle;
        background: $background 60%;
    }

    #theme-dialog {
        width: 74;
        max-width: 90%;
        height: 70%;
        border: thick $accent;
        background: $panel;
        padding: 1 2;
    }

    #theme-list {
        height: 1fr;
        margin: 1 0;
        border: round $primary;
    }

    ConfirmScreen {
        align: center middle;
        background: $background 60%;
    }

    #confirm-dialog {
        width: 70;
        max-width: 90%;
        height: auto;
        border: thick $warning;
        background: $panel;
        padding: 1 2;
    }

    .dialog-title {
        text-style: bold;
        color: $accent;
        padding-bottom: 1;
    }

    .dialog-message {
        padding: 1 0;
    }
    """

    def __init__(
        self,
        settings: Settings,
        *,
        initial_profile: str | None = None,
        dry_run: bool = False,
    ) -> None:
        super().__init__()
        self.settings = settings
        self.initial_profile = initial_profile
        if settings.tui_theme in self.available_themes:
            self.theme = settings.tui_theme
        self.options = RunOptions(
            profile=initial_profile or "custom",
            dry_run=dry_run,
            plymouth_theme=settings.plymouth_theme,
        )
        self.package_groups: list[str] = []
        self.manual_packages: list[str] = []
        self.last_results: list[TaskResult] = []
        self.last_log_path: Path | None = None

    def on_mount(self) -> None:
        self.push_screen(WelcomeScreen())

    def action_help(self) -> None:
        self.notify(
            "Tab/arrows: move · Space: toggle · Enter: confirm · "
            "Ctrl+T: colour scheme · Ctrl+Q: quit",
            title="Keys",
        )

    def action_schemes(self) -> None:
        self.open_theme_screen()

    def open_theme_screen(self) -> None:
        """Open the colour-scheme picker and persist the chosen theme."""

        if not self.available_themes:
            self.notify("No colour schemes are available in this Textual build.", severity="warning")
            return
        self.push_screen(
            ThemeScreen(str(self.theme), dict(self.available_themes)),
            callback=self._theme_done,
        )

    def _theme_done(self, theme: str | None) -> None:
        if not theme or theme == self.settings.tui_theme:
            return
        try:
            save_tui_theme(self.settings.config_file, theme)
        except Exception as exc:
            self.notify(f"Cannot save colour scheme: {exc}", severity="error")
            return
        self.settings = self.settings.with_overrides(tui_theme=theme)
        # Keep the live preview visible; it is now the saved scheme.
        self.notify(f"Colour scheme saved: {theme}", title="Schemes")

    async def launch_execution(
        self,
        plan: list[str],
        *,
        profile: str,
        dry_run: bool,
        resume: bool,
        allow_destructive: bool,
        plymouth_theme: str | None,
    ) -> None:
        if not dry_run and requires_root(plan) and not sudo_cached():
            with self.suspend():
                try:
                    ensure_sudo(interactive=True)
                except SudoError as exc:
                    self.notify(f"sudo: {exc}", severity="error")
                    return
        self.options = replace(
            self.options,
            profile=profile,
            dry_run=dry_run,
            resume=resume,
            allow_destructive=allow_destructive,
            package_groups=tuple(self.package_groups),
            manual_packages=tuple(self.manual_packages),
            plymouth_theme=plymouth_theme,
        )
        self.push_screen(ExecutionScreen(plan, self.options))

    async def reboot_async(self) -> None:
        if self.options.dry_run:
            return
        if not sudo_cached():
            with self.suspend():
                try:
                    ensure_sudo(interactive=True)
                except SudoError as exc:
                    self.notify(f"sudo: {exc}", severity="error")
                    return
        with self.suspend():
            process = await asyncio.create_subprocess_exec(
                "sudo",
                "-n",
                "reboot",
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            returncode = await process.wait()
        if returncode != 0:
            self.notify("reboot failed", severity="error")
