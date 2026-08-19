"""Live log view widget."""
from textual.widgets import RichLog

class LogView(RichLog):
    def __init__(self):
        super().__init__(wrap=True, highlight=True, markup=True)
        self.border_title = "Logs"
