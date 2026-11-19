"""Package selection modal: whole groups and/or individual packages."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Input, SelectionList, Static
from textual.widgets.selection_list import Selection

from ..packages import (
    PackageCatalog,
    PackageSelection,
    conflicting_groups,
    validate_package_names,
)


class PackagesScreen(ModalScreen[PackageSelection | None]):
    """Choose package groups, individual packages, or a mix of both."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("enter", "apply", "Apply"),
    ]

    def __init__(self, selection: PackageSelection, catalog: PackageCatalog) -> None:
        super().__init__()
        initial = selection.normalized()
        self.catalog = catalog
        self._groups: set[str] = set(initial.groups)
        self._packages: set[str] = set(initial.packages)
        self.all_packages: list[str] = sorted(
            {package for packages in catalog.groups.values() for package in packages}
            | self._packages
        )
        self._filter = ""
        self._tab = "groups"
        self._rebuilding = False

    # ------------------------------------------------------------------ UI
    def compose(self) -> ComposeResult:
        with Vertical(id="packages-dialog"):
            yield Static("Package selection", classes="dialog-title")
            yield Static(
                "Choose whole groups, individual packages, or both. "
                "Space toggles; Enter applies.",
                classes="muted",
            )
            with Horizontal(id="package-tabs"):
                yield Button("Groups", id="tab-groups", classes="tab-button")
                yield Button("Individual packages", id="tab-packages", classes="tab-button")
            with Vertical(id="groups-pane"):
                yield SelectionList[str](
                    *[
                        Selection(
                            f"{self.catalog.display_name(name)} ({len(packages)} packages)",
                            name,
                            initial_state=name in self._groups,
                        )
                        for name, packages in self.catalog.groups.items()
                    ],
                    id="group-list",
                )
            with Vertical(id="packages-pane"):
                yield Input(placeholder="Filter packages…", id="package-filter")
                yield SelectionList[str](
                    *[
                        Selection(name, name, initial_state=name in self._packages)
                        for name in self._visible_packages()
                    ],
                    id="package-list",
                )
                with Horizontal(classes="add-row"):
                    yield Input(
                        placeholder="Type a package name, then press Add or Enter",
                        id="package-add",
                    )
                    yield Button("Add", id="add-package")
            yield Static("", id="package-status", classes="muted")
            with Horizontal(classes="actions"):
                yield Button("All", id="all")
                yield Button("None", id="none")
                yield Button("Cancel", id="cancel")
                yield Button("Apply", id="apply", variant="primary")

    def on_mount(self) -> None:
        self._sync_package_selection(self.query_one("#package-list", SelectionList))
        self._switch_tab("groups")
        self._refresh_status()

    # -------------------------------------------------------------- helpers
    def _visible_packages(self) -> list[str]:
        if not self._filter:
            return list(self.all_packages)
        return [name for name in self.all_packages if self._filter in name.lower()]

    def _selection(self) -> PackageSelection:
        return PackageSelection(
            groups=tuple(name for name in self.catalog.groups if name in self._groups),
            packages=tuple(sorted(self._packages)),
        ).normalized()

    def _sync_package_selection(self, selection: SelectionList[str]) -> None:
        """Fold the visible list state into the authoritative set."""

        if self._rebuilding:
            return
        visible = {str(option.value) for option in selection.options}
        chosen = {str(value) for value in selection.selected}
        for value in visible:
            if value in chosen:
                self._packages.add(value)
            else:
                self._packages.discard(value)

    def _rebuild_packages(self) -> None:
        selection = self.query_one("#package-list", SelectionList)
        self._sync_package_selection(selection)
        self._rebuilding = True
        try:
            selection.set_options(
                [
                    Selection(name, name, initial_state=name in self._packages)
                    for name in self._visible_packages()
                ]
            )
        finally:
            self._rebuilding = False

    def _refresh_status(self) -> None:
        selection = self._selection()
        packages, unknown = self.catalog.resolve_selection(selection)
        text = (
            f"[b]{len(selection.groups)}[/b] group(s), "
            f"[b]{len(selection.packages)}[/b] individual package(s) "
            f"→ [b]{len(packages)}[/b] unique package(s)"
        )
        if unknown:
            text += f"\n[red]unknown groups: {', '.join(unknown)}[/red]"
        for conflict in conflicting_groups(selection.groups):
            text += f"\n[yellow]⚠ {conflict}[/yellow]"
        self.query_one("#package-status", Static).update(text)

    def _switch_tab(self, tab: str) -> None:
        self._tab = tab
        self.query_one("#groups-pane", Vertical).display = tab == "groups"
        self.query_one("#packages-pane", Vertical).display = tab == "packages"
        self.query_one("#tab-groups", Button).variant = "primary" if tab == "groups" else "default"
        self.query_one("#tab-packages", Button).variant = "primary" if tab == "packages" else "default"
        target = "group-list" if tab == "groups" else "package-list"
        self.query_one(f"#{target}", SelectionList).focus()

    def _add_package(self) -> None:
        field = self.query_one("#package-add", Input)
        try:
            names = validate_package_names(field.value.split())
        except ValueError as exc:
            self.notify(str(exc), severity="error")
            return
        if not names:
            return
        self.all_packages = sorted(set(self.all_packages) | set(names))
        self._packages.update(names)
        field.value = ""
        self.query_one("#package-filter", Input).value = ""
        self._filter = ""
        self._rebuild_packages()
        self._refresh_status()
        self.query_one("#package-list", SelectionList).focus()

    def _set_all(self, enabled: bool) -> None:
        if self._tab == "groups":
            selection = self.query_one("#group-list", SelectionList)
            if enabled:
                selection.select_all()
            else:
                selection.deselect_all()
            self._groups = set(selection.selected) if enabled else set()
        else:
            selection = self.query_one("#package-list", SelectionList)
            if enabled:
                selection.select_all()
                self._packages.update(str(value) for value in selection.selected)
            else:
                selection.deselect_all()
                self._packages.clear()
        self._refresh_status()

    def _apply(self) -> None:
        self._sync_package_selection(self.query_one("#package-list", SelectionList))
        self.dismiss(self._selection())

    # --------------------------------------------------------------- events
    def on_button_pressed(self, event: Button.Pressed) -> None:
        button_id = event.button.id
        if button_id == "tab-groups":
            self._switch_tab("groups")
        elif button_id == "tab-packages":
            self._switch_tab("packages")
        elif button_id == "all":
            self._set_all(True)
        elif button_id == "none":
            self._set_all(False)
        elif button_id == "add-package":
            self._add_package()
        elif button_id == "cancel":
            self.dismiss(None)
        elif button_id == "apply":
            self._apply()

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "package-filter":
            self._filter = event.value.strip().lower()
            self._rebuild_packages()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        # Input consumes Enter itself, so the screen-level binding never fires.
        if event.input.id == "package-add":
            self._add_package()
        else:
            self._apply()

    def on_selection_list_selected_changed(self, event: SelectionList.SelectedChanged) -> None:
        list_id = event.control.id
        if list_id == "group-list":
            self._groups = {str(value) for value in event.control.selected}
        elif list_id == "package-list":
            self._sync_package_selection(event.control)
        self._refresh_status()

    def action_cancel(self) -> None:
        self.dismiss(None)

    def action_apply(self) -> None:
        if isinstance(self.focused, Input) and self.focused.id == "package-add":
            self._add_package()
            return
        self._apply()
