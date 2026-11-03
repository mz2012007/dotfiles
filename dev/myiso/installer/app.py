"""Main Textual application."""
from textual.app import App
from textual.binding import Binding
from installer.screens.config_screen import ConfigScreen
from installer.models.installer_config import InstallerConfig

class MyISOInstaller(App):
    TITLE = "myiso Installer"
    SUB_TITLE = "Void Linux Installer"
    CSS = """
    #title {
        text-align: center;
        text-style: bold;
        padding: 1;
    }
    #config-form {
        padding: 0 2;
        height: 1fr;
        overflow-y: auto;
    }
    Label {
        margin-top: 1;
    }
    Input, Select {
        margin-bottom: 0;
    }
    """

    BINDINGS = [
        Binding("f1", "help", "Help"),
        Binding("f5", "toggle_log", "Logs"),
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "continue", "Continue"),
    ]

    def on_mount(self) -> None:
        # Load default config (for initial values and repo/arch)
        default_config = InstallerConfig.from_file("config/installer.conf")
        self.push_screen(ConfigScreen(default_config))

    def action_help(self) -> None:
        self.notify("Help: myiso installer – use arrow keys, Enter to select.", title="Help")

    def action_toggle_log(self) -> None:
        self.notify("Log panel toggled (not implemented in this demo).", title="Logs")

    def action_cancel(self) -> None:
        self.notify("Installation cancelled at safe point.", title="Cancel")

    def action_continue(self) -> None:
        self.notify("Continue – use buttons on screen.", title="Continue")
