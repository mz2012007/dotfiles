"""Welcome screen."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Static

from .. import __version__


class WelcomeScreen(Screen):
    BINDINGS = [
        Binding("d", "doctor", "Doctor"),
        Binding("q", "quit", "Quit"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical(id="welcome-body"):
            with Vertical(id="welcome-card"):
                yield Static("voidsetup", id="welcome-title")
                yield Static(
                    "A resumable, dry-runnable Void Linux setup tool.\n"
                    "Every system change is an explicit task; nothing runs until you press Start.",
                    id="welcome-subtitle",
                )
                yield Static(
                    "Tip: run with dry-run enabled first to inspect every command.",
                    classes="muted",
                )
                with Horizontal(classes="actions"):
                    yield Button("Doctor", id="doctor")
                    yield Button("Start", id="start", variant="primary")
                    yield Button("Quit", id="quit")
                yield Static(f"v{__version__}", id="welcome-version", classes="muted")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#start", Button).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "start":
            from .profile import ProfileScreen

            self.app.push_screen(
                ProfileScreen(initial=getattr(self.app, "initial_profile", None))
            )
        elif event.button.id == "doctor":
            from .doctor import DoctorScreen

            self.app.push_screen(DoctorScreen())
        elif event.button.id == "quit":
            self.app.exit()

    def action_doctor(self) -> None:
        from .doctor import DoctorScreen

        self.app.push_screen(DoctorScreen())

    def action_quit(self) -> None:
        self.app.exit()
