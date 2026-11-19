"""Task registry and profiles (the replacement for EXEC_PLAN and fzf)."""

from __future__ import annotations

from .errors import PlanningError
from .models import Profile, Severity, Task
from .tasks import build, dotfiles, finish, packages, security, services, system


def _task(task: Task) -> Task:
    return task


TASKS: dict[str, Task] = {
    task.id: task
    for task in (
        _task(
            Task(
                "repos",
                "Add XBPS repositories",
                "Write the custom repository definitions under /etc/xbps.d.",
                system.add_repos,
                group="system",
                requires_root=True,
                check=system.check_repos,
            )
        ),
        _task(
            Task(
                "timezone",
                "Set timezone",
                "Point /etc/localtime at the configured zoneinfo entry.",
                system.set_timezone,
                group="system",
                requires_root=True,
                check=system.check_timezone,
            )
        ),
        _task(
            Task(
                "sync_time",
                "Sync clock",
                "Step chrony and write the system clock to the RTC.",
                system.sync_time,
                group="system",
                requires_root=True,
                severity=Severity.OPTIONAL,
            )
        ),
        _task(
            Task(
                "update",
                "Update system",
                "Run xbps-install -Syu and update xbps itself.",
                system.update_system,
                group="system",
                requires_root=True,
            )
        ),
        _task(
            Task(
                "packages",
                "Install package groups",
                "Install the groups selected from packages.sh.",
                packages.install_packages,
                group="packages",
                requires_root=True,
                depends_on=("update",),
                check=packages.check_packages,
            )
        ),
        _task(
            Task(
                "dirs_user",
                "Create user directories",
                "Create the home directories used by the dotfiles.",
                dotfiles.make_user_dirs,
                group="dotfiles",
                check=dotfiles.check_user_dirs,
            )
        ),
        _task(
            Task(
                "dirs_root",
                "Create system directories",
                "Create /etc, /usr/share, /boot and /mnt/srv directories.",
                dotfiles.make_root_dirs,
                group="dotfiles",
                requires_root=True,
                check=dotfiles.check_root_dirs,
            )
        ),
        _task(
            Task(
                "backup_home",
                "Back up home (destructive)",
                "Move everything except dotfiles/ and bak/ into bak/<timestamp>/.",
                dotfiles.backup_home,
                group="dotfiles",
                dangerous=True,
                check=dotfiles.check_backup_home,
            )
        ),
        _task(
            Task(
                "stow",
                "Stow dotfiles",
                "Run stow --restow for the dotfiles repository.",
                dotfiles.stow_dotfiles,
                group="dotfiles",
                check=dotfiles.check_stow,
            )
        ),
        _task(
            Task(
                "copy_configs",
                "Copy system configs",
                "rsync the myroot configuration and user SSH/tmux files.",
                dotfiles.copy_configs,
                group="dotfiles",
                requires_root=True,
                depends_on=("dirs_root",),
            )
        ),
        _task(
            Task(
                "mk_files",
                "Create MPD files",
                "Touch the MPD database, pid, state and log files.",
                dotfiles.make_files,
                group="dotfiles",
                severity=Severity.OPTIONAL,
                depends_on=("dirs_user",),
                check=dotfiles.check_files,
            )
        ),
        _task(
            Task(
                "cleanup_stray",
                "Remove stray tmux dir",
                "Remove the old 'templates/ ' directory created by a typo.",
                dotfiles.remove_stray_template_dir,
                group="dotfiles",
                severity=Severity.OPTIONAL,
            )
        ),
        _task(
            Task(
                "power_polkit",
                "Install polkit power rule",
                "Let active admin-group users reboot/power off without SUID.",
                security.install_power_polkit,
                group="security",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=security.check_power_polkit,
            )
        ),
        _task(
            Task(
                "harden_suid",
                "Remove legacy SUID bits",
                "Remove SUID from sleep, poweroff, reboot, hostname and zzz.",
                security.remove_legacy_suid,
                group="security",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=security.check_legacy_suid,
            )
        ),
        _task(
            Task(
                "services",
                "Enable runit services",
                "Link installed services from /etc/sv into /var/service.",
                services.enable_services,
                group="services",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=services.check_services,
            )
        ),
        _task(
            Task(
                "groups",
                "Add user to groups",
                "Add the user to a curated set of existing groups.",
                services.add_groups,
                group="services",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=services.check_groups,
            )
        ),
        _task(
            Task(
                "sysctl",
                "Apply sysctl tuning",
                "Write /etc/sysctl.d/99-voidsetup.conf and apply it.",
                system.write_sysctl,
                group="system",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=system.check_sysctl,
            )
        ),
        _task(
            Task(
                "dns",
                "Manage resolv.conf",
                "Copy the configured resolv.conf without the old immutable flag.",
                system.manage_dns,
                group="system",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=system.check_dns,
            )
        ),
        _task(
            Task(
                "ufw",
                "Enable UFW",
                "Deny incoming, allow outgoing and enable the firewall.",
                system.enable_ufw,
                group="system",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=system.check_ufw,
            )
        ),
        _task(
            Task(
                "dwm",
                "Build dwm",
                "Run make clean install in .config/dwm/dwm.",
                build.build_dwm,
                group="build",
                requires_root=True,
                severity=Severity.OPTIONAL,
            )
        ),
        _task(
            Task(
                "dwmblocks",
                "Build dwmblocks",
                "Run make clean install in .config/dwm/dwmblocks.",
                build.build_dwmblocks,
                group="build",
                requires_root=True,
                severity=Severity.OPTIONAL,
            )
        ),
        _task(
            Task(
                "tmux",
                "Install TPM",
                "Clone/update tmux plugin manager and install plugins.",
                build.install_tpm,
                group="build",
                severity=Severity.OPTIONAL,
                depends_on=("dirs_user",),
                check=build.check_tpm,
            )
        ),
        _task(
            Task(
                "mpv",
                "Install mpv config",
                "Sparse-clone the mpv scripts repository.",
                build.install_mpv,
                group="build",
                severity=Severity.OPTIONAL,
                depends_on=("dirs_user",),
                check=build.check_mpv,
            )
        ),
        _task(
            Task(
                "local_packages",
                "Install local packages",
                "Index .xbps files and install their packages.",
                build.install_local_packages,
                group="packages",
                requires_root=True,
                severity=Severity.OPTIONAL,
                depends_on=("update",),
                check=build.check_local_packages,
            )
        ),
        _task(
            Task(
                "fonts",
                "Refresh font cache",
                "Run fc-cache -f after fonts are installed.",
                build.update_fonts,
                group="build",
                severity=Severity.OPTIONAL,
            )
        ),
        _task(
            Task(
                "plymouth",
                "Set Plymouth theme",
                "Select and rebuild the configured Plymouth theme.",
                build.set_plymouth,
                group="boot",
                requires_root=True,
                severity=Severity.OPTIONAL,
                check=build.check_plymouth,
            )
        ),
        _task(
            Task(
                "grub",
                "Regenerate GRUB",
                "Run grub-mkconfig after theme/boot changes.",
                build.update_grub,
                group="boot",
                requires_root=True,
                severity=Severity.OPTIONAL,
            )
        ),
        _task(
            Task(
                "finish",
                "Finish",
                "Log the result and send a desktop notification.",
                finish.finish,
                group="finish",
                severity=Severity.OPTIONAL,
            )
        ),
    )
}

PROFILES: dict[str, Profile] = {
    profile.id: profile
    for profile in (
        Profile(
            "old_lab",
            "Full setup",
            "The old-lab workflow without wiping the home directory.",
            (
                "repos",
                "timezone",
                "sync_time",
                "update",
                "packages",
                "dirs_user",
                "dirs_root",
                "stow",
                "copy_configs",
                "mk_files",
                "cleanup_stray",
                "power_polkit",
                "harden_suid",
                "services",
                "groups",
                "sysctl",
                "dns",
                "ufw",
                "dwm",
                "dwmblocks",
                "tmux",
                "mpv",
                "local_packages",
                "fonts",
                "plymouth",
                "grub",
                "finish",
            ),
        ),
        Profile(
            "during_work",
            "Maintenance",
            "Safe repeatable maintenance: time, updates, packages, fonts.",
            ("sync_time", "update", "packages", "fonts", "finish"),
        ),
        Profile(
            "dotfiles",
            "Dotfiles only",
            "Stow dotfiles, copy configs and refresh user-level extras.",
            (
                "dirs_user",
                "stow",
                "copy_configs",
                "mk_files",
                "cleanup_stray",
                "tmux",
                "mpv",
                "fonts",
                "finish",
            ),
        ),
        Profile(
            "fresh",
            "Fresh home (destructive)",
            "Back up and clear the home directory, then run the full setup.",
            (
                "backup_home",
                "repos",
                "timezone",
                "sync_time",
                "update",
                "packages",
                "dirs_user",
                "dirs_root",
                "stow",
                "copy_configs",
                "mk_files",
                "cleanup_stray",
                "power_polkit",
                "harden_suid",
                "services",
                "groups",
                "sysctl",
                "dns",
                "ufw",
                "dwm",
                "dwmblocks",
                "tmux",
                "mpv",
                "local_packages",
                "fonts",
                "plymouth",
                "grub",
                "finish",
            ),
        ),
        Profile(
            "repair",
            "Repair old damage",
            "Remove legacy SUID bits, repair resolv.conf and the stray tmux directory.",
            ("harden_suid", "dns", "cleanup_stray"),
        ),
        Profile(
            "custom",
            "Custom",
            "Choose individual tasks and package groups.",
            (),
        ),
    )
}


def _validate_registry() -> None:
    for task in TASKS.values():
        for dependency in task.depends_on:
            if dependency not in TASKS:
                raise RuntimeError(f"task {task.id!r} depends on unknown task {dependency!r}")
            if dependency == task.id:
                raise RuntimeError(f"task {task.id!r} depends on itself")
    for profile in PROFILES.values():
        for task_id in profile.tasks:
            if task_id not in TASKS:
                raise RuntimeError(f"profile {profile.id!r} references unknown task {task_id!r}")


_validate_registry()


def get_task(task_id: str) -> Task:
    try:
        return TASKS[task_id]
    except KeyError as exc:
        raise PlanningError(f"unknown task: {task_id!r}") from exc


def task_ids() -> list[str]:
    return list(TASKS)


def expand_plan(task_ids: list[str] | tuple[str, ...], *, include_deps: bool = True) -> list[str]:
    """Return tasks with dependencies inserted before dependants."""

    for task_id in task_ids:
        get_task(task_id)
    result: list[str] = []
    if not include_deps:
        result = list(dict.fromkeys(task_ids))
    else:
        def visit(task_id: str) -> None:
            if task_id in result:
                return
            for dependency in get_task(task_id).depends_on:
                visit(dependency)
            result.append(task_id)

        for task_id in task_ids:
            visit(task_id)
    return result


def remove_with_dependents(plan: list[str], to_skip: set[str]) -> list[str]:
    """Remove skipped tasks and any selected tasks that depend on them."""

    if not to_skip:
        return list(plan)
    removed = set(to_skip)
    changed = True
    while changed:
        changed = False
        for task_id in plan:
            if task_id in removed:
                continue
            task = get_task(task_id)
            if any(dependency in removed for dependency in task.depends_on):
                removed.add(task_id)
                changed = True
    return [task_id for task_id in plan if task_id not in removed]


def resolve_plan(
    *,
    profile: str | None = None,
    tasks: list[str] | tuple[str, ...] | None = None,
    skip: list[str] | tuple[str, ...] = (),
    include_deps: bool = True,
) -> list[str]:
    if profile == "custom":
        if not tasks:
            raise PlanningError("the custom profile needs --tasks (or use the TUI)")
        selected = list(tasks)
    elif profile is not None:
        if tasks:
            raise PlanningError("use either --profile or --tasks, not both")
        try:
            selected = list(PROFILES[profile].tasks)
        except KeyError as exc:
            raise PlanningError(f"unknown profile: {profile!r}") from exc
        if not selected:
            raise PlanningError("the selected profile has no tasks")
    elif tasks:
        selected = list(tasks)
    else:
        raise PlanningError("no profile or tasks selected")
    for task_id in selected:
        get_task(task_id)
    for task_id in skip:
        get_task(task_id)
    plan = expand_plan(selected, include_deps=include_deps)
    return remove_with_dependents(plan, set(skip))


def dangerous_tasks(plan: list[str]) -> list[str]:
    return [task_id for task_id in plan if get_task(task_id).dangerous]


def requires_root(plan: list[str]) -> bool:
    return any(get_task(task_id).requires_root for task_id in plan)
