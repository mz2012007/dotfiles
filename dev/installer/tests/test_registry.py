from __future__ import annotations

import pytest

from voidsetup.errors import PlanningError
from voidsetup.registry import (
    PROFILES,
    TASKS,
    dangerous_tasks,
    expand_plan,
    remove_with_dependents,
    requires_root,
    resolve_plan,
)


def test_registry_is_consistent() -> None:
    assert TASKS
    for task in TASKS.values():
        for dependency in task.depends_on:
            assert dependency in TASKS
            assert dependency != task.id
    for profile in PROFILES.values():
        for task_id in profile.tasks:
            assert task_id in TASKS


def test_expand_plan_puts_dependencies_first() -> None:
    plan = expand_plan(["packages"])
    assert plan.index("update") < plan.index("packages")
    plan = expand_plan(["copy_configs"])
    assert plan.index("dirs_root") < plan.index("copy_configs")


def test_expand_plan_deduplicates() -> None:
    plan = expand_plan(["fonts", "fonts", "finish"])
    assert plan == ["fonts", "finish"]


def test_remove_with_dependents() -> None:
    plan = expand_plan(["packages", "fonts"])
    reduced = remove_with_dependents(plan, {"update"})
    assert "update" not in reduced
    assert "packages" not in reduced
    assert "fonts" in reduced


def test_resolve_profile_and_skip() -> None:
    plan = resolve_plan(profile="during_work")
    assert plan[0] == "sync_time"
    assert "packages" in plan
    plan = resolve_plan(profile="during_work", skip=["update"])
    assert "update" not in plan
    assert "packages" not in plan


def test_custom_profile_accepts_tasks() -> None:
    assert resolve_plan(profile="custom", tasks=["fonts"]) == ["fonts"]


def test_custom_profile_without_tasks_fails() -> None:
    with pytest.raises(PlanningError):
        resolve_plan(profile="custom")


def test_profile_and_tasks_are_mutually_exclusive() -> None:
    with pytest.raises(PlanningError):
        resolve_plan(profile="during_work", tasks=["fonts"])


def test_unknown_profile_task_and_skip() -> None:
    with pytest.raises(PlanningError):
        resolve_plan(profile="nope")
    with pytest.raises(PlanningError):
        resolve_plan(tasks=["nope"])
    with pytest.raises(PlanningError):
        resolve_plan(tasks=["fonts"], skip=["nope"])


def test_fresh_profile_requires_destructive_backup() -> None:
    plan = resolve_plan(profile="fresh")
    assert dangerous_tasks(plan) == ["backup_home"]


def test_repair_profile_is_non_destructive() -> None:
    plan = resolve_plan(profile="repair")
    assert {"harden_suid", "dns", "cleanup_stray"} <= set(plan)
    assert dangerous_tasks(plan) == []


def test_requires_root() -> None:
    assert requires_root(resolve_plan(profile="during_work"))
    assert not requires_root(["fonts"])
