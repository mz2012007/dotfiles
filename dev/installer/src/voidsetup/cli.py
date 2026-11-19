"""Command-line interface for voidsetup."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import subprocess
import sys
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Sequence

from rich.console import Console
from rich.table import Table
from rich.text import Text

from . import __version__
from .config import Settings, default_config_toml, load_settings
from .context import Context
from .engine import ExecutionHooks, Executor
from .errors import ConfigError, PlanningError, SudoError, VoidSetupError
from .models import RunOptions, Severity, TaskResult, TaskStatus
from .packages import PackageCatalog, conflicting_groups, validate_package_names
from .preflight import check_environment, required_failures
from .registry import (
    PROFILES,
    TASKS,
    dangerous_tasks,
    requires_root,
    resolve_plan,
    task_ids,
)
from .runner import Runner
from .session_log import LogLevel, LogRecord, SessionLogger
from .state import StateStore
from .sudo import ensure_sudo
from .util import expand_path, get_plymouth_themes, parse_csv

STATUS_STYLE = {
    "ok": "green",
    "warn": "yellow",
    "fail": "red",
    "info": "cyan",
    TaskStatus.OK: "green",
    TaskStatus.SKIPPED: "cyan",
    TaskStatus.FAILED: "red",
    TaskStatus.BLOCKED: "red",
    TaskStatus.ABORTED: "red",
    TaskStatus.RUNNING: "yellow",
    TaskStatus.PENDING: "dim",
}


def _status_text(value: object) -> Text:
    text = str(getattr(value, "value", value))
    return Text(text, style=STATUS_STYLE.get(value, STATUS_STYLE.get(text, "dim")))


def _json_default(value: object) -> Any:
    if isinstance(value, TaskStatus):
        return value.value
    if isinstance(value, Path):
        return str(value)
    if hasattr(value, "value"):
        return value.value
    raise TypeError(f"cannot serialise {type(value)!r}")


def _print_json(payload: object, console: Console | None = None) -> None:
    text = json.dumps(payload, indent=2, default=_json_default, sort_keys=True)
    (console or Console()).print(text, markup=False, highlight=False, soft_wrap=True)


def _plan_table(plan: Sequence[str], settings: Settings, *, title: str = "Execution plan") -> Table:
    store = StateStore(settings.state_file)
    state = store.load()
    table = Table(title=title, show_lines=False)
    table.add_column("#", justify="right", style="dim")
    table.add_column("Task", style="bold")
    table.add_column("Name")
    table.add_column("Group", style="dim")
    table.add_column("Root", justify="center")
    table.add_column("Kind", justify="center")
    table.add_column("Last", justify="center")
    for index, task_id in enumerate(plan, start=1):
        task = TASKS[task_id]
        last = state.tasks.get(task_id).status if state and task_id in state.tasks else TaskStatus.PENDING
        table.add_row(
            str(index),
            task.id,
            task.name,
            task.group,
            "yes" if task.requires_root else "",
            task.severity.value,
            _status_text(last),
        )
    return table


def _task_table() -> Table:
    table = Table(title="Tasks")
    table.add_column("ID", style="bold")
    table.add_column("Group", style="dim")
    table.add_column("Name")
    table.add_column("Root", justify="center")
    table.add_column("Kind", justify="center")
    table.add_column("Deps", style="dim")
    for task in TASKS.values():
        table.add_row(
            task.id,
            task.group,
            task.name,
            "yes" if task.requires_root else "",
            task.severity.value + (" (danger)" if task.dangerous else ""),
            ", ".join(task.depends_on),
        )
    return table


def _profiles_table() -> Table:
    table = Table(title="Profiles")
    table.add_column("ID", style="bold")
    table.add_column("Name")
    table.add_column("Tasks", justify="right")
    table.add_column("Description")
    for profile in PROFILES.values():
        table.add_row(profile.id, profile.name, str(len(profile.tasks)), profile.description)
    return table


def _packages_table(catalog: PackageCatalog) -> Table:
    table = Table(title=f"Package groups ({len(catalog.groups)})")
    table.add_column("Group", style="bold")
    table.add_column("Packages", justify="right")
    for name, packages in catalog.groups.items():
        display = catalog.display_name(name)
        label = display if display == name else f"{display} [{name}]"
        table.add_row(label, str(len(packages)))
    return table


def _load_catalog(settings: Settings) -> PackageCatalog:
    return PackageCatalog.load(settings.packages_path)


def _select_groups(args: argparse.Namespace, settings: Settings, console: Console) -> tuple[str, ...]:
    catalog = _load_catalog(settings)
    if getattr(args, "all_groups", False):
        selected = catalog.names()
    else:
        selected = tuple(parse_csv(getattr(args, "groups", None)))
    unknown = [name for name in selected if not catalog.has_group(name)]
    if unknown:
        raise PlanningError("unknown package groups: " + ", ".join(unknown))
    for conflict in conflicting_groups(selected):
        console.print(Text(f"warning: {conflict}", style="yellow"))
    return selected


def _select_plan(args: argparse.Namespace) -> list[str]:
    tasks = parse_csv(getattr(args, "tasks", None)) or None
    return resolve_plan(
        profile=getattr(args, "profile", None),
        tasks=tasks,
        skip=parse_csv(getattr(args, "skip", None)),
    )


def _print_checks(console: Console, checks: list, *, title: str = "Preflight") -> None:
    table = Table(title=title)
    table.add_column("", width=3)
    table.add_column("Check", style="bold")
    table.add_column("Detail")
    for check in checks:
        icon = {"ok": "✓", "warn": "!", "fail": "✗", "info": "i"}.get(check.status, "?")
        table.add_row(Text(icon, style=STATUS_STYLE.get(check.status, "dim")), check.label, check.detail)
    console.print(table)


def _check_plan_ready(
    plan: Sequence[str],
    settings: Settings,
    groups: Sequence[str],
    console: Console,
    *,
    force: bool,
    dry_run: bool = False,
    manual_packages: tuple[str, ...] = (),
) -> list:
    checks = check_environment(
        settings,
        plan,
        package_groups=groups,
        manual_packages=manual_packages,
    )
    if dry_run:
        checks = [check for check in checks if check.id != "sudo-session"]
    interesting = [check for check in checks if check.status in {"warn", "fail"}]
    if interesting:
        _print_checks(console, interesting, title="Preflight warnings")
    failures = required_failures(checks)
    if failures and not force:
        console.print(Text("preflight failed; fix the errors above or pass --force", style="red"))
    return failures


def _make_console_sink(console: Console, *, verbose: bool):
    def sink(record: LogRecord) -> None:
        if record.level is LogLevel.DEBUG and not verbose:
            return
        if record.level is LogLevel.OUTPUT:
            console.print(Text.from_ansi(record.message), soft_wrap=True, highlight=False)
            return
        prefix = {
            LogLevel.DEBUG: "· ",
            LogLevel.INFO: "ℹ ",
            LogLevel.WARN: "! ",
            LogLevel.ERROR: "✖ ",
            LogLevel.COMMAND: "$ ",
        }.get(record.level, "")
        style = {
            LogLevel.DEBUG: "dim",
            LogLevel.WARN: "yellow",
            LogLevel.ERROR: "red",
            LogLevel.COMMAND: "cyan",
        }.get(record.level, "")
        console.print(Text(prefix + record.message, style=style), soft_wrap=True)

    return sink


def _print_summary(console: Console, results: Sequence[TaskResult], log_path: Path | None) -> None:
    table = Table(title="Run summary")
    table.add_column("Task", style="bold")
    table.add_column("Status", justify="center")
    table.add_column("Time", justify="right")
    table.add_column("Detail")
    for result in results:
        task = TASKS[result.task_id]
        detail = result.error or result.detail or ""
        table.add_row(task.id, _status_text(result.status), f"{result.duration:.1f}s", detail)
    console.print(table)
    counts: dict[str, int] = {}
    for result in results:
        counts[result.status.value] = counts.get(result.status.value, 0) + 1
    summary = "  ".join(f"{key}: {value}" for key, value in sorted(counts.items()))
    console.print(Text(summary, style="bold"))
    if log_path:
        console.print(Text(f"log: {log_path}", style="dim"))


def _run_failed_required(results: Sequence[TaskResult]) -> bool:
    return any(
        result.status in (TaskStatus.FAILED, TaskStatus.BLOCKED)
        and TASKS[result.task_id].severity is Severity.REQUIRED
        for result in results
    )


async def _execute_run(
    args: argparse.Namespace,
    settings: Settings,
    console: Console,
    plan: list[str],
    groups: tuple[str, ...],
    manual: tuple[str, ...],
) -> int:
    from .sudo import sudo_cached

    messages = Console(stderr=True) if args.json else console
    store = StateStore(settings.state_file)
    if args.fresh and not args.dry_run:
        store.reset()
    if args.resume:
        existing = store.load()
        if existing is None or not existing.is_resumable:
            messages.print(Text("no unfinished run found; starting a new run", style="yellow"))
        elif existing.plan != plan:
            messages.print(
                Text(
                    "error: the unfinished state belongs to a different task plan; "
                    "use --fresh to start over",
                    style="red",
                )
            )
            return 2

    if not args.dry_run and requires_root(plan) and not sudo_cached():
        messages.print(Text("sudo authentication is required for root tasks", style="yellow"))
        try:
            ensure_sudo(interactive=sys.stdin.isatty())
        except SudoError as exc:
            messages.print(Text(f"error: {exc}", style="red"))
            return 3

    log_path = settings.logs_dir / f"{datetime.now():%Y%m%d-%H%M%S}.log"
    sink = None if args.json else _make_console_sink(console, verbose=args.verbose)
    logger = SessionLogger(log_path, sink=sink, keep_logs=settings.log_keep)
    runner = Runner(logger, dry_run=args.dry_run)
    options = RunOptions(
        profile=args.profile or "custom",
        dry_run=args.dry_run,
        resume=args.resume,
        allow_destructive=args.allow_destructive,
        reboot=args.reboot,
        assume_yes=args.yes,
        package_groups=groups,
        manual_packages=manual,
        plymouth_theme=args.plymouth_theme or settings.plymouth_theme,
    )
    ctx = Context(
        settings=settings,
        runner=runner,
        logger=logger,
        options=options,
        package_groups=groups,
        manual_packages=manual,
        plymouth_theme=options.plymouth_theme,
    )

    loop = asyncio.get_running_loop()
    handlers: list[signal.Signals] = []

    def request_cancel() -> None:
        if not ctx.cancel_event.is_set():
            messages.print(Text("\ninterrupt received; stopping after the current command…", style="yellow"))
            ctx.cancel_event.set()
            asyncio.create_task(runner.cancel())

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, request_cancel)
            handlers.append(sig)
        except (NotImplementedError, RuntimeError):
            pass

    if not args.dry_run:
        await runner.start_keepalive()

    logger.info(f"voidsetup {__version__}")
    logger.info(f"profile: {options.profile}; tasks: {len(plan)}; dry-run: {args.dry_run}")
    if groups:
        logger.info("package groups: " + ", ".join(groups))
    if manual:
        logger.info("manual packages: " + ", ".join(manual))

    executor = Executor(
        ctx,
        plan,
        store=store,
        hooks=ExecutionHooks(),
        resume=args.resume,
    )

    try:
        results = await executor.run()
    finally:
        await runner.stop_keepalive()
        for sig in handlers:
            try:
                loop.remove_signal_handler(sig)
            except (NotImplementedError, RuntimeError):
                pass
        logger.close()

    aborted = any(result.status is TaskStatus.ABORTED for result in results)
    if args.json:
        payload = {
            "ok": not _run_failed_required(results) and not aborted,
            "aborted": aborted,
            "dry_run": args.dry_run,
            "profile": options.profile,
            "log": str(log_path),
            "state": str(settings.state_file),
            "results": [
                {
                    "task": result.task_id,
                    "status": result.status.value,
                    "duration": round(result.duration, 3),
                    "error": result.error,
                    "detail": result.detail,
                }
                for result in results
            ],
        }
        _print_json(payload)
    else:
        _print_summary(console, results, log_path)

    failed = _run_failed_required(results)
    if args.reboot and not args.dry_run and not failed and not aborted:
        messages.print(Text("rebooting…", style="yellow"))
        subprocess.run(["sudo", "-n", "reboot"], check=False)
    return 1 if failed or aborted else 0


def cmd_run(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    if args.json and not args.yes:
        console.print(Text("error: --json requires --yes", style="red"))
        return 2
    plan = _select_plan(args)
    if not plan:
        console.print(Text("error: empty execution plan", style="red"))
        return 2
    dangerous = dangerous_tasks(plan)
    if dangerous and not args.allow_destructive:
        console.print(
            Text(
                "error: plan contains destructive tasks ("
                + ", ".join(dangerous)
                + "); pass --allow-destructive to continue",
                style="red",
            )
        )
        return 2

    try:
        manual = validate_package_names(parse_csv(getattr(args, "packages", None)))
    except ValueError as exc:
        console.print(Text(f"error: {exc}", style="red"))
        return 2

    groups: tuple[str, ...] = ()
    if args.groups or args.all_groups:
        try:
            groups = _select_groups(args, settings, console)
        except (ConfigError, PlanningError, FileNotFoundError) as exc:
            console.print(Text(f"error: {exc}", style="red"))
            return 2

    if "packages" in plan and not groups and not manual:
        if args.yes:
            console.print(
                Text(
                    "error: the packages task is selected but no groups or packages were given; "
                    "pass --groups GROUP[,GROUP], --packages PKG[,PKG] or --skip packages",
                    style="red",
                )
            )
            return 2
        if sys.stdin.isatty():
            try:
                catalog = _load_catalog(settings)
            except (ConfigError, FileNotFoundError):
                catalog = None
            if catalog is not None:
                console.print(Text("Available package groups: " + ", ".join(catalog.groups), style="dim"))
                try:
                    raw = input("Package groups (comma-separated, empty to skip): ")
                except EOFError:
                    raw = ""
                if raw.strip():
                    groups = tuple(parse_csv(raw))
                    unknown = [name for name in groups if not catalog.has_group(name)]
                    if unknown:
                        console.print(Text("error: unknown package groups: " + ", ".join(unknown), style="red"))
                        return 2
            try:
                raw_packages = input("Individual packages (comma-separated, empty to skip): ")
            except EOFError:
                raw_packages = ""
            try:
                manual = validate_package_names(parse_csv(raw_packages))
            except ValueError as exc:
                console.print(Text(f"error: {exc}", style="red"))
                return 2

    if not args.json:
        console.print(_plan_table(plan, settings))
        if groups:
            console.print(Text("package groups: " + ", ".join(groups), style="dim"))
        if manual:
            console.print(Text("manual packages: " + ", ".join(manual), style="dim"))
        if args.dry_run:
            console.print(Text("dry-run: no system changes will be made", style="yellow"))
        if not args.yes:
            if not sys.stdin.isatty():
                console.print(Text("error: refusing to run without --yes in a non-interactive shell", style="red"))
                return 2
            answer = input("Proceed? [y/N] ").strip().lower()
            if answer not in ("y", "yes"):
                console.print(Text("cancelled", style="yellow"))
                return 0

    check_console = Console(stderr=True) if args.json else console
    failures = _check_plan_ready(
        plan,
        settings,
        groups,
        check_console,
        force=args.force,
        dry_run=args.dry_run,
        manual_packages=manual,
    )
    if failures and not args.force:
        return 3
    if failures and args.force:
        check_console.print(Text("continuing despite preflight failures (--force)", style="yellow"))

    return asyncio.run(_execute_run(args, settings, console, plan, groups, manual))


def cmd_plan(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    plan = _select_plan(args)
    if args.json:
        _print_json(
            {
                "profile": args.profile,
                "tasks": [
                    {
                        "id": task_id,
                        "name": TASKS[task_id].name,
                        "group": TASKS[task_id].group,
                        "requires_root": TASKS[task_id].requires_root,
                        "severity": TASKS[task_id].severity.value,
                        "dangerous": TASKS[task_id].dangerous,
                    }
                    for task_id in plan
                ],
            }
        )
    else:
        console.print(_plan_table(plan, settings))
    return 0


def cmd_list(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    if args.json:
        _print_json(
            [
                {
                    "id": task.id,
                    "name": task.name,
                    "description": task.description,
                    "group": task.group,
                    "requires_root": task.requires_root,
                    "severity": task.severity.value,
                    "dangerous": task.dangerous,
                    "depends_on": list(task.depends_on),
                }
                for task in TASKS.values()
            ]
        )
    else:
        console.print(_task_table())
    return 0


def cmd_profiles(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    if args.json:
        _print_json(
            [
                {
                    "id": profile.id,
                    "name": profile.name,
                    "description": profile.description,
                    "tasks": list(profile.tasks),
                }
                for profile in PROFILES.values()
            ]
        )
    else:
        console.print(_profiles_table())
    return 0


def cmd_packages(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    catalog = _load_catalog(settings)
    if args.json:
        _print_json({name: list(packages) for name, packages in catalog.groups.items()})
    else:
        console.print(_packages_table(catalog))
        if catalog.warnings:
            for warning in catalog.warnings:
                console.print(Text(f"warning: {warning}", style="yellow"))
    return 0


def cmd_doctor(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    checks = check_environment(settings, task_ids(), audit=True)
    if args.json:
        _print_json([asdict(check) for check in checks])
    else:
        _print_checks(console, checks, title="voidsetup doctor")
        fails = sum(1 for check in checks if check.failed)
        warns = sum(1 for check in checks if check.warned)
        style = "red" if fails else ("yellow" if warns else "green")
        console.print(Text(f"{fails} failure(s), {warns} warning(s)", style=style))
    return 1 if required_failures(checks) else 0


def cmd_themes(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    themes = get_plymouth_themes()
    if args.json:
        _print_json(themes)
    elif themes:
        for theme in themes:
            console.print(theme)
    else:
        console.print(Text("no Plymouth themes found", style="yellow"))
    return 0


def cmd_schemes(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    """List the colour schemes available to the Textual TUI."""

    from textual.app import App

    themes = sorted(App().available_themes)
    if args.json:
        _print_json({"current": settings.tui_theme, "themes": themes})
        return 0
    table = Table(title=f"TUI colour schemes (current: {settings.tui_theme})")
    table.add_column("Scheme", style="bold")
    table.add_column("Current", justify="center")
    for theme in themes:
        table.add_row(theme, "✓" if theme == settings.tui_theme else "")
    console.print(table)
    console.print(Text("change with Ctrl+T inside the TUI", style="dim"))
    return 0


def cmd_init_config(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    path = settings.config_file
    if path.exists() and not args.force:
        console.print(Text(f"config already exists: {path} (use --force to overwrite)", style="yellow"))
        return 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(default_config_toml(), encoding="utf-8")
    console.print(Text(f"wrote {path}", style="green"))
    return 0


def cmd_tui(args: argparse.Namespace, settings: Settings, console: Console) -> int:
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        console.print(Text("error: the TUI needs an interactive terminal", style="red"))
        return 2
    from .app import VoidSetupApp

    app = VoidSetupApp(settings, initial_profile=args.profile, dry_run=args.dry_run)
    try:
        app.run()
    except KeyboardInterrupt:
        return 130
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="voidsetup",
        description="Async, resumable setup for Void Linux.",
    )
    parser.add_argument("--config", type=Path, help="TOML configuration file")
    parser.add_argument("--dotfiles", type=Path, help="override the dotfiles directory")
    parser.add_argument("--state-dir", type=Path, help="override the state/log directory")
    parser.add_argument("--verbose", action="store_true", help="show debug output")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")

    sub = parser.add_subparsers(dest="command")

    def add_selection(p: argparse.ArgumentParser) -> None:
        p.add_argument("--profile", choices=list(PROFILES), help="named task profile")
        p.add_argument("--tasks", help="comma-separated task ids (custom plan)")
        p.add_argument("--skip", default="", help="comma-separated task ids to skip")

    p = sub.add_parser("tui", help="launch the Textual interface")
    p.add_argument("--profile", choices=list(PROFILES), help="initial profile")
    p.add_argument("--dry-run", action="store_true", help="show commands without running them")
    p.set_defaults(func=cmd_tui)

    p = sub.add_parser("run", help="run a plan non-interactively")
    add_selection(p)
    p.add_argument("--groups", help="comma-separated package groups")
    p.add_argument("--all-groups", action="store_true", help="select every package group")
    p.add_argument(
        "--packages",
        default="",
        help="comma-separated individual package names to install",
    )
    p.add_argument("--plymouth-theme", help="Plymouth theme name")
    p.add_argument("--dry-run", action="store_true", help="show commands without running them")
    p.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    p.add_argument("--force", action="store_true", help="continue despite preflight failures")
    p.add_argument("--allow-destructive", action="store_true", help="allow tasks such as backup_home")
    p.add_argument("--reboot", action="store_true", help="reboot after a successful run")
    p.add_argument("--json", action="store_true", help="print a machine-readable result (requires --yes)")
    group = p.add_mutually_exclusive_group()
    group.add_argument("--resume", action="store_true", help="resume an unfinished run")
    group.add_argument("--fresh", action="store_true", help="discard previous state before running")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("plan", help="show the tasks that would run")
    add_selection(p)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser("list", help="list all tasks")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("profiles", help="list profiles")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_profiles)

    p = sub.add_parser("packages", help="list package groups from packages.sh")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_packages)

    p = sub.add_parser("doctor", help="run preflight and safety audits")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser("themes", help="list Plymouth themes")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_themes)

    p = sub.add_parser("schemes", help="list TUI colour schemes")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_schemes)

    p = sub.add_parser("init-config", help="write a sample configuration file")
    p.add_argument("--force", action="store_true", help="overwrite an existing file")
    p.set_defaults(func=cmd_init_config)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    raw_argv = list(argv) if argv is not None else sys.argv[1:]
    args = parser.parse_args(raw_argv)
    if args.command is None:
        if sys.stdout.isatty():
            args.command = "tui"
            args.profile = None
            args.dry_run = False
            args.func = cmd_tui
        else:
            parser.print_help()
            return 0

    # Keep stdout machine-readable when --json is in use; all human messages
    # (errors, preflight warnings, progress) go to stderr.
    console = Console(stderr="--json" in raw_argv)
    try:
        if args.command == "init-config":
            # Do not parse an existing (possibly broken) config when the user
            # explicitly asked to write a new one. Honour VOIDSETUP_CONFIG too.
            target = expand_path(
                args.config
                or os.environ.get("VOIDSETUP_CONFIG")
                or Path.home() / ".config" / "voidsetup" / "config.toml"
            )
            settings = Settings().with_overrides(config_file=target)
        else:
            settings = load_settings(args.config)
        overrides: dict[str, object] = {}
        if args.dotfiles:
            overrides["dotfiles"] = expand_path(args.dotfiles)
        if args.state_dir:
            overrides["state_dir"] = expand_path(args.state_dir)
        if overrides:
            settings = settings.with_overrides(**overrides)
        return int(args.func(args, settings, console))
    except (ConfigError, PlanningError, VoidSetupError) as exc:
        console.print(Text(f"error: {exc}", style="red"))
        return 2
    except KeyboardInterrupt:
        console.print(Text("interrupted", style="yellow"))
        return 130
