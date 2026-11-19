"""Read-only environment and safety audit."""

from __future__ import annotations

import asyncio

from rich.text import Text
from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, DataTable, Footer, Header, Static

from ..preflight import check_environment
from ..registry import task_ids

STATUS_STYLE = {"ok": "green", "warn": "yellow", "fail": "red", "info": "cyan"}


class DoctorScreen(Screen):
    BINDINGS = [Binding("escape", "back", "Back")]

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical(id="doctor-body"):
            yield Static("Doctor", classes="screen-title")
            yield Static("Read-only checks; nothing is changed.", id="doctor-status", classes="muted")
            yield DataTable(id="doctor-table", zebra_stripes=True, show_header=True)
            with Horizontal(classes="actions"):
                yield Button("Back", id="back", variant="primary")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#doctor-table", DataTable)
        table.add_column("", key="icon", width=3)
        table.add_column("Check", key="check")
        table.add_column("Detail", key="detail")
        self._load()

    @work(exclusive=True, group="doctor")
    async def _load(self) -> None:
        settings = self.app.settings  # type: ignore[attr-defined]
        checks = await asyncio.to_thread(
            check_environment,
            settings,
            task_ids(),
            audit=True,
        )
        table = self.query_one("#doctor-table", DataTable)
        for check in checks:
            icon = {"ok": "✓", "warn": "!", "fail": "✗", "info": "i"}.get(check.status, "?")
            table.add_row(
                Text(icon, style=STATUS_STYLE.get(check.status, "dim")),
                check.label,
                check.detail,
            )
        fails = sum(1 for check in checks if check.failed)
        warns = sum(1 for check in checks if check.warned)
        style = "red" if fails else ("yellow" if warns else "green")
        self.query_one("#doctor-status", Static).update(
            Text(f"{fails} failure(s), {warns} warning(s)", style=style)
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back":
            self.app.pop_screen()

    def action_back(self) -> None:
        self.app.pop_screen()
