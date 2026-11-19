"""Profile selection screen."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from ..registry import PROFILES


class ProfileScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("enter", "continue", "Continue"),
    ]

    def __init__(self, initial: str | None = None) -> None:
        super().__init__()
        self.initial = initial if initial in PROFILES else next(iter(PROFILES))

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical(id="profile-body"):
            yield Static("Choose a profile", classes="screen-title")
            yield Static(
                "Profiles are just ordered task lists. You can adjust them on the next screen.",
                classes="muted",
            )
            yield OptionList(
                *[
                    Option(f"{profile.name}  [{profile.id}]", id=profile.id)
                    for profile in PROFILES.values()
                ],
                id="profiles",
            )
            yield Static("", id="profile-description", classes="panel-text")
            with Horizontal(classes="actions"):
                yield Button("Back", id="back")
                yield Button("Continue", id="continue", variant="primary")
        yield Footer()

    def on_mount(self) -> None:
        options = self.query_one("#profiles", OptionList)
        for index, profile in enumerate(PROFILES.values()):
            if profile.id == self.initial:
                options.highlighted = index
                break
        self._update_description(self.initial)
        options.focus()

    def _update_description(self, profile_id: str | None) -> None:
        if not profile_id or profile_id not in PROFILES:
            return
        profile = PROFILES[profile_id]
        self.query_one("#profile-description", Static).update(
            f"[b]{profile.name}[/b]\n{profile.description}\n"
            f"[dim]{len(profile.tasks)} task(s)[/dim]"
        )

    def on_option_list_option_highlighted(self, event: OptionList.OptionHighlighted) -> None:
        self._update_description(event.option.id)

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        if event.option.id:
            self._open(event.option.id)

    def _selected_profile(self) -> str | None:
        options = self.query_one("#profiles", OptionList)
        if options.highlighted is not None:
            option = options.get_option_at_index(options.highlighted)
            return option.id
        return None

    def _open(self, profile_id: str) -> None:
        from .plan import PlanScreen

        self.app.push_screen(PlanScreen(PROFILES[profile_id]))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back":
            self.app.pop_screen()
        elif event.button.id == "continue":
            profile_id = self._selected_profile()
            if profile_id:
                self._open(profile_id)

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_continue(self) -> None:
        profile_id = self._selected_profile()
        if profile_id:
            self._open(profile_id)
