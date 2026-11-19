"""Task/package selection and run options."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import (
    Button,
    Checkbox,
    Footer,
    Header,
    Select,
    SelectionList,
    Static,
)
from textual.widgets.selection_list import Selection

from ..models import Profile
from ..packages import PackageCatalog, PackageSelection
from ..registry import TASKS, dangerous_tasks, expand_plan
from ..state import StateStore
from ..util import get_plymouth_themes
from .packages import PackagesScreen  # re-exported for existing imports/tests
from .theme import ThemeScreen


class PlanScreen(Screen):
    BINDINGS = [
        Binding("escape", "back", "Back"),
        Binding("ctrl+s", "start", "Start"),
        Binding("ctrl+t", "schemes", "Schemes"),
    ]

    def __init__(self, profile: Profile) -> None:
        super().__init__()
        self.profile = profile
        if profile.tasks:
            expanded = expand_plan(profile.tasks)
            # Destructive tasks must be selected deliberately.
            self._initial = {
                task_id for task_id in expanded if not TASKS[task_id].dangerous
            }
        else:
            self._initial = set()

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical(id="plan-body"):
            yield Static(f"Plan — {self.profile.name}", classes="screen-title")
            yield Static(self.profile.description, id="plan-desc", classes="muted")
            with Horizontal(id="plan-columns"):
                with Vertical(id="tasks-pane"):
                    yield Static("Tasks", classes="pane-title")
                    yield SelectionList[str](
                        *[
                            Selection(
                                f"{task.group}: {task.name} — {task.description}",
                                task.id,
                                initial_state=task.id in self._initial,
                            )
                            for task in TASKS.values()
                        ],
                        id="task-list",
                    )
                with Vertical(id="options-pane"):
                    yield Static("Options", classes="pane-title")
                    yield Checkbox("Dry run (show commands only)", id="dry-run")
                    yield Checkbox("Resume unfinished run", id="resume")
                    yield Checkbox("Allow destructive tasks", id="allow-dangerous")
                    yield Static("Plymouth theme", classes="label")
                    yield Select([], id="plymouth", allow_blank=True, prompt="Keep current")
                    yield Button("Package selection… (0)", id="packages")
                    yield Button("Colour scheme…", id="schemes")
                    yield Static("", id="plan-summary", classes="muted")
                    yield Static(
                        "Selecting packages automatically adds the packages task. "
                        "Destructive tasks are never selected by default.",
                        classes="hint",
                    )
            with Horizontal(classes="actions"):
                yield Button("Back", id="back")
                yield Button("Start", id="start", variant="primary")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#task-list", SelectionList).focus()
        self.query_one("#dry-run", Checkbox).value = bool(
            self.app.options.dry_run  # type: ignore[attr-defined]
        )
        select = self.query_one("#plymouth", Select)
        themes = get_plymouth_themes()
        if themes:
            select.set_options([(theme, theme) for theme in themes])
            configured = self.app.options.plymouth_theme  # type: ignore[attr-defined]
            if configured and configured in themes:
                select.value = configured
        else:
            select.disabled = True
            select.prompt = "Plymouth not installed"

        state = StateStore(self.app.settings.state_file).load()  # type: ignore[attr-defined]
        resume = self.query_one("#resume", Checkbox)
        if state is not None and state.is_resumable:
            resume.disabled = False
            resume.value = True
        else:
            resume.disabled = True
            resume.value = False
        self._refresh_summary()

    def _refresh_summary(self) -> None:
        selected = list(self.query_one("#task-list", SelectionList).selected)
        dangerous = any(TASKS[task_id].dangerous for task_id in selected)
        allow = self.query_one("#allow-dangerous", Checkbox)
        allow.disabled = not dangerous
        if not dangerous:
            allow.value = False
        groups = len(self.app.package_groups)  # type: ignore[attr-defined]
        manual = len(self.app.manual_packages)  # type: ignore[attr-defined]
        self.query_one("#plan-summary", Static).update(
            f"[b]{len(selected)}[/b] task(s) selected\n"
            f"[b]{groups}[/b] group(s) + [b]{manual}[/b] individual package(s)\n"
            f"colour scheme: [b]{self.app.theme}[/b]  ·  profile: [b]{self.profile.id}[/b]"
        )
        self.query_one("#packages", Button).label = (
            f"Package selection… ({groups + manual})"
        )

    def on_selection_list_selected_changed(self, event: SelectionList.SelectedChanged) -> None:
        self._refresh_summary()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back":
            self.app.pop_screen()
        elif event.button.id == "packages":
            try:
                catalog = PackageCatalog.load(self.app.settings.packages_path)  # type: ignore[attr-defined]
            except Exception as exc:
                # Manual packages still work without packages.sh.
                catalog = PackageCatalog(groups={}, warnings=(str(exc),))
                self.notify(f"Groups unavailable ({exc}); you can still add packages manually.", severity="warning")
            current = PackageSelection(
                tuple(self.app.package_groups) if catalog.groups else (),  # type: ignore[attr-defined]
                tuple(self.app.manual_packages),  # type: ignore[attr-defined]
            )
            self.app.push_screen(  # type: ignore[attr-defined]
                PackagesScreen(current, catalog),
                callback=self._packages_done,
            )
        elif event.button.id == "schemes":
            self.app.open_theme_screen()  # type: ignore[attr-defined]
        elif event.button.id == "start":
            self.run_worker(self._start(), exclusive=True, group="start")

    def _packages_done(self, result: PackageSelection | None) -> None:
        if result is None:
            return
        self.app.package_groups = list(result.groups)  # type: ignore[attr-defined]
        self.app.manual_packages = list(result.packages)  # type: ignore[attr-defined]
        if not result.is_empty:
            tasks = self.query_one("#task-list", SelectionList)
            tasks.select("packages")
            self.notify(
                "Package selection saved; the packages task is selected.",
                title="Packages",
            )
        self._refresh_summary()

    async def _start(self) -> None:
        selection = self.query_one("#task-list", SelectionList)
        selected = list(selection.selected)
        groups = tuple(self.app.package_groups)  # type: ignore[attr-defined]
        manual = tuple(self.app.manual_packages)  # type: ignore[attr-defined]

        # A package selection is meaningless without the task that installs it.
        if (groups or manual) and "packages" not in selected:
            selected.append("packages")
            selection.select("packages")
            self.notify("Added the packages task for your selection.", title="Packages")

        if not selected:
            self.notify("Select at least one task.", severity="warning")
            return
        # Keep the profile's intentional order, then append custom extras.
        if self.profile.tasks:
            ordered = [task_id for task_id in self.profile.tasks if task_id in selected]
            ordered += [task_id for task_id in selected if task_id not in ordered]
        else:
            ordered = selected
        plan = expand_plan(ordered)
        added = [task_id for task_id in plan if task_id not in selected]
        if added:
            self.notify("Dependencies added: " + ", ".join(added), severity="information")

        dangerous = dangerous_tasks(plan)
        allow = self.query_one("#allow-dangerous", Checkbox).value
        if dangerous and not allow:
            self.notify(
                "This plan contains destructive tasks: " + ", ".join(dangerous),
                severity="error",
            )
            return

        if "packages" in plan and not groups and not manual:
            self.notify(
                "The packages task has no selection; it will be skipped. "
                "Use Package selection to choose groups or individual packages.",
                severity="warning",
            )

        dry_run = self.query_one("#dry-run", Checkbox).value
        resume = self.query_one("#resume", Checkbox).value
        if resume:
            saved = StateStore(self.app.settings.state_file).load()  # type: ignore[attr-defined]
            if saved is not None and saved.is_resumable and saved.plan != plan:
                self.notify(
                    "The saved run belongs to a different task plan. "
                    "Uncheck Resume to start a new run.",
                    severity="error",
                )
                return
        select = self.query_one("#plymouth", Select)
        theme = select.value if select.value is not Select.NULL else None
        plymouth = str(theme) if theme else None

        await self.app.launch_execution(  # type: ignore[attr-defined]
            plan,
            profile=self.profile.id,
            dry_run=dry_run,
            resume=resume,
            allow_destructive=allow,
            plymouth_theme=plymouth,
        )

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_start(self) -> None:
        self.run_worker(self._start(), exclusive=True, group="start")

    def action_schemes(self) -> None:
        self.app.open_theme_screen()  # type: ignore[attr-defined]
