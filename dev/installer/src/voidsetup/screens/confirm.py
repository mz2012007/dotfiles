"""Small reusable confirmation modal."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Static


class ConfirmScreen(ModalScreen[bool]):
    BINDINGS = [Binding("escape", "cancel", "Cancel")]

    def __init__(
        self,
        message: str,
        *,
        title: str = "Confirm",
        yes_label: str = "Yes",
        no_label: str = "Cancel",
        danger: bool = False,
    ) -> None:
        super().__init__()
        self.message = message
        self.title_text = title
        self.yes_label = yes_label
        self.no_label = no_label
        self.danger = danger

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-dialog"):
            yield Static(self.title_text, classes="dialog-title")
            yield Static(self.message, classes="dialog-message")
            with Horizontal(classes="actions"):
                yield Button(self.no_label, id="no")
                yield Button(
                    self.yes_label,
                    id="yes",
                    variant="error" if self.danger else "primary",
                )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")

    def action_cancel(self) -> None:
        self.dismiss(False)
