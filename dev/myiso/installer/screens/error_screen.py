"""Error screen shown when a stage fails."""
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, Button
from textual.containers import Vertical, Horizontal

class ErrorScreen(Screen):
    def __init__(self, stage: str, exit_code: int, log_path):
        super().__init__()
        self.stage = stage
        self.exit_code = exit_code
        self.log_path = log_path

    def compose(self):
        yield Header()
        with Vertical():
            yield Static("[bold red]Installation Failed[/]")
            yield Static(f"Stage: {self.stage}")
            yield Static(f"Exit code: {self.exit_code}")
            yield Static(f"Log file: {self.log_path}")
            with Horizontal():
                yield Button("Retry", id="retry-btn")
                yield Button("Exit", id="exit-btn")
        yield Footer()

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "retry-btn":
            self.dismiss(True)
        elif event.button.id == "exit-btn":
            self.dismiss(False)
