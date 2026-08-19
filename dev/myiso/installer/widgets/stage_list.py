"""Stage list widget."""
from textual.widgets import Static
from textual.containers import Vertical
from installer.services.state import InstallerState, STAGES

class StageList(Vertical):
    def __init__(self, state: InstallerState, **kwargs):
        super().__init__(**kwargs)
        self.state = state

    def compose(self):
        for stage in STAGES:
            yield Static(self._format_stage(stage), id=f"stage-{stage}")

    def _format_stage(self, stage: str) -> str:
        status = self.state.get(stage, "pending")
        symbol = {
            "done": "[green]✓[/]",
            "running": "[yellow]▶[/]",
            "failed": "[red]✗[/]",
            "pending": "[ ]",
        }.get(status, "[ ]")
        return f"{symbol} {stage.replace('_', ' ').title()}"

    def refresh_stage(self, stage: str):
        widget = self.query_one(f"#stage-{stage}", Static)
        widget.update(self._format_stage(stage))
