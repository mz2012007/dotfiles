"""Live log view widget."""
from textual.widgets import RichLog

class LogView(RichLog):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, wrap=True, highlight=True, markup=True, **kwargs)
        self.border_title = "Logs"
