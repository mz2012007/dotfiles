"""Disk selection screen (simplified: shows list of disks)."""
from textual.screen import Screen
from textual.widgets import Header, Footer, ListView, ListItem, Label, Button
from textual.containers import Vertical

class DiskScreen(Screen):
    def __init__(self, disks: list[str]):
        super().__init__()
        self.disks = disks

    def compose(self):
        yield Header()
        with Vertical():
            yield Label("Select target disk:")
            yield ListView(*[ListItem(Label(disk)) for disk in self.disks], id="disk-list")
            yield Button("Confirm Selection", id="confirm-disk")
        yield Footer()

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "confirm-disk":
            list_view = self.query_one("#disk-list", ListView)
            if list_view.index is not None:
                selected = self.disks[list_view.index]
                self.dismiss(selected)
            else:
                self.notify("No disk selected", severity="warning")
