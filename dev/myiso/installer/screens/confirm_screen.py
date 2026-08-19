"""Destructive operation confirmation screen."""
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, Input, Button
from textual.containers import Vertical, Horizontal

class ConfirmScreen(Screen):
    def __init__(self, disk: str):
        super().__init__()
        self.disk = disk

    def compose(self):
        yield Header()
        with Vertical():
            yield Static(f"[bold red]WARNING[/]")
            yield Static(f"All data on {self.disk} will be destroyed.")
            yield Static("Type DESTROY to continue.")
            yield Input(placeholder="DESTROY", id="confirm-input")
            with Horizontal():
                yield Button("Confirm", id="confirm-btn", variant="error")
                yield Button("Cancel", id="cancel-btn")
        yield Footer()

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "confirm-btn":
            value = self.query_one("#confirm-input", Input).value.strip()
            if value == "DESTROY":
                self.dismiss(True)
            else:
                self.notify("Invalid confirmation text", severity="error")
        elif event.button.id == "cancel-btn":
            self.dismiss(False)
