"""Main Textual application."""
from textual.app import App
from textual.binding import Binding
from installer.screens.main_screen import MainScreen

class MyISOInstaller(App):
    TITLE = "myiso Installer"
    SUB_TITLE = "Void Linux Installer"
    CSS = """
    #title {
        text-align: center;
        text-style: bold;
        padding: 1;
    }
    #stage-list {
        height: 1fr;
        border: solid $accent;
        padding: 0 1;
    }
    #progress-bar {
        height: 1;
        margin: 1 0;
    }
    #log-view {
        height: 12;
        border: solid $panel;
    }
    """

    BINDINGS = [
        Binding("f1", "help", "Help"),
        Binding("f5", "toggle_log", "Logs"),
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "continue", "Continue"),
    ]

    def on_mount(self) -> None:
        self.push_screen(MainScreen())

    def action_help(self) -> None:
        self.notify("Help: myiso installer – use arrow keys, Enter to select.", title="Help")

    def action_toggle_log(self) -> None:
        self.notify("Log panel toggled (not implemented in this demo).", title="Logs")

    def action_cancel(self) -> None:
        self.notify("Installation cancelled at safe point.", title="Cancel")

    def action_continue(self) -> None:
        self.notify("Continue – use buttons on screen.", title="Continue")
