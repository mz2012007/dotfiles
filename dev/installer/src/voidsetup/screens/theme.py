"""Colour-scheme picker for the Textual TUI."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, SelectionList, Static
from textual.widgets.selection_list import Selection


class ThemeScreen(ModalScreen[str | None]):
    """Preview and apply one of Textual's built-in colour schemes."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "apply", "Apply"),
    ]

    def __init__(self, current: str, themes: dict[str, object]) -> None:
        super().__init__()
        self.original = current
        self.themes = dict(themes)
        self.current = current if current in self.themes else next(iter(self.themes), current)

    def compose(self) -> ComposeResult:
        with Vertical(id="theme-dialog"):
            yield Static("TUI colour scheme", classes="dialog-title")
            yield Static(
                "Move with the arrow keys to preview. Enter saves the scheme "
                "to your voidsetup config; Escape keeps the old one.",
                classes="muted",
            )
            yield SelectionList[str](
                *[
                    Selection(name, name, initial_state=name == self.current)
                    for name in self.themes
                ],
                id="theme-list",
            )
            yield Static("", id="theme-preview", classes="muted")
            with Horizontal(classes="actions"):
                yield Button("Cancel", id="cancel")
                yield Button("Apply", id="apply", variant="primary")

    def on_mount(self) -> None:
        self.query_one("#theme-list", SelectionList).focus()
        self._preview(self.current)

    def _preview(self, name: str) -> None:
        if name not in self.themes:
            return
        self.current = name
        self.app.theme = name  # type: ignore[attr-defined]
        theme = self.themes[name]
        kind = "dark" if getattr(theme, "dark", True) else "light"
        self.query_one("#theme-preview", Static).update(
            f"Previewing [b]{name}[/b] ({kind})."
        )

    def _apply(self) -> None:
        self.dismiss(self.current)

    def on_selection_list_selection_highlighted(
        self, event: SelectionList.SelectionHighlighted
    ) -> None:
        name = str(event.selection.value)
        if name in self.themes:
            self._preview(name)

    def on_selection_list_selection_toggled(
        self, event: SelectionList.SelectionToggled
    ) -> None:
        name = str(event.selection.value)
        if name not in {str(value) for value in event.control.selected}:
            return
        for other in list(event.control.selected):
            if str(other) != name:
                event.control.deselect(other)
        self._preview(name)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "apply":
            self._apply()
        elif event.button.id == "cancel":
            self.action_cancel()

    def action_cancel(self) -> None:
        self.app.theme = self.original  # type: ignore[attr-defined]
        self.dismiss(None)

    def action_apply(self) -> None:
        self._apply()
