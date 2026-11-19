from __future__ import annotations

from pathlib import Path

import pytest

from voidsetup.engine import Executor
from voidsetup.errors import ExecutionCancelled, SkipTask
from voidsetup.models import RunStatus, Severity, TaskStatus
from voidsetup.state import StateStore

from .conftest import make_task


async def test_successful_plan_runs_in_order(make_context) -> None:
    calls: list[str] = []

    async def first(_ctx):
        calls.append("first")

    async def second(_ctx):
        calls.append("second")

    tasks = {"first": make_task("first", first), "second": make_task("second", second)}
    results = await Executor(make_context(), ["first", "second"], tasks=tasks).run()
    assert calls == ["first", "second"]
    assert [result.status for result in results] == [TaskStatus.OK, TaskStatus.OK]


async def test_check_skips_task(make_context) -> None:
    called = False

    async def func(_ctx):
        nonlocal called
        called = True

    async def check(_ctx):
        return True

    tasks = {"done": make_task("done", func, check=check)}
    results = await Executor(make_context(), ["done"], tasks=tasks).run()
    assert results[0].status is TaskStatus.SKIPPED
    assert results[0].detail == "already done"
    assert not called


async def test_check_error_does_not_block_task(make_context) -> None:
    called = False

    async def func(_ctx):
        nonlocal called
        called = True

    async def check(_ctx):
        raise RuntimeError("probe broke")

    tasks = {"t": make_task("t", func, check=check)}
    results = await Executor(make_context(), ["t"], tasks=tasks).run()
    assert results[0].status is TaskStatus.OK
    assert called


async def test_cancellation_during_check_aborts_cleanly(make_context, tmp_path: Path) -> None:
    async def check(_ctx):
        raise ExecutionCancelled("cancelled while probing")

    tasks = {
        "probe": make_task("probe", check=check),
        "later": make_task("later"),
    }
    store = StateStore(tmp_path / "state.json")
    results = await Executor(make_context(), ["probe", "later"], tasks=tasks, store=store).run()
    assert results[0].status is TaskStatus.ABORTED
    assert results[1].status is TaskStatus.BLOCKED
    state = store.load()
    assert state is not None
    assert state.status is RunStatus.ABORTED


async def test_skip_task(make_context) -> None:
    async def func(_ctx):
        raise SkipTask("not installed")

    tasks = {"t": make_task("t", func)}
    results = await Executor(make_context(), ["t"], tasks=tasks).run()
    assert results[0].status is TaskStatus.SKIPPED
    assert results[0].detail == "not installed"


async def test_required_failure_stops_the_plan(make_context) -> None:
    async def fail(_ctx):
        raise RuntimeError("boom")

    async def later(_ctx):
        raise AssertionError("must not run")

    tasks = {
        "fail": make_task("fail", fail, severity=Severity.REQUIRED),
        "later": make_task("later", later),
    }
    results = await Executor(make_context(), ["fail", "later"], tasks=tasks).run()
    assert results[0].status is TaskStatus.FAILED
    assert "boom" in (results[0].error or "")
    assert results[1].status is TaskStatus.BLOCKED


async def test_optional_failure_continues(make_context) -> None:
    calls: list[str] = []

    async def fail(_ctx):
        raise RuntimeError("optional boom")

    async def later(_ctx):
        calls.append("later")

    tasks = {
        "fail": make_task("fail", fail, severity=Severity.OPTIONAL),
        "later": make_task("later", later),
    }
    results = await Executor(make_context(), ["fail", "later"], tasks=tasks).run()
    assert results[0].status is TaskStatus.FAILED
    assert results[1].status is TaskStatus.OK
    assert calls == ["later"]


async def test_failed_dependency_blocks_dependants(make_context) -> None:
    async def fail(_ctx):
        raise RuntimeError("nope")

    tasks = {
        "dep": make_task("dep", fail, severity=Severity.OPTIONAL),
        "child": make_task("child", depends_on=("dep",)),
    }
    results = await Executor(make_context(), ["dep", "child"], tasks=tasks).run()
    assert results[0].status is TaskStatus.FAILED
    assert results[1].status is TaskStatus.BLOCKED
    assert "dep" in (results[1].error or "")


async def test_missing_dependency_blocks_task(make_context) -> None:
    async def func(_ctx):
        raise AssertionError("must not run")

    tasks = {"child": make_task("child", func, depends_on=("absent",))}
    results = await Executor(make_context(), ["child"], tasks=tasks).run()
    assert results[0].status is TaskStatus.BLOCKED


async def test_dangerous_task_requires_opt_in(make_context) -> None:
    ran = False

    async def func(_ctx):
        nonlocal ran
        ran = True

    tasks = {"danger": make_task("danger", func, dangerous=True)}
    results = await Executor(make_context(), ["danger"], tasks=tasks).run()
    assert results[0].status is TaskStatus.FAILED
    assert not ran

    results = await Executor(
        make_context(allow_destructive=True), ["danger"], tasks=tasks
    ).run()
    assert results[0].status is TaskStatus.OK
    assert ran


async def test_cancelled_task_aborts_remaining(make_context) -> None:
    async def cancel(_ctx):
        raise ExecutionCancelled("user aborted")

    tasks = {
        "cancel": make_task("cancel", cancel),
        "later": make_task("later"),
    }
    results = await Executor(make_context(), ["cancel", "later"], tasks=tasks).run()
    assert results[0].status is TaskStatus.ABORTED
    assert results[1].status is TaskStatus.BLOCKED


async def test_pre_set_cancel_event_blocks_everything(make_context, tmp_path: Path) -> None:
    ctx = make_context()
    ctx.cancel_event.set()
    store = StateStore(tmp_path / "state.json")
    results = await Executor(ctx, ["t"], tasks={"t": make_task("t")}, store=store).run()
    assert results[0].status is TaskStatus.BLOCKED
    state = store.load()
    assert state is not None
    assert state.status is RunStatus.ABORTED


async def test_dry_run_does_not_write_state_or_execute(make_context, tmp_path: Path) -> None:
    marker = tmp_path / "marker"

    async def func(ctx):
        await ctx.run("sh", "-c", f"touch {marker}")

    store = StateStore(tmp_path / "state.json")
    results = await Executor(
        make_context(dry_run=True),
        ["t"],
        tasks={"t": make_task("t", func)},
        store=store,
    ).run()
    assert results[0].status is TaskStatus.OK
    assert not marker.exists()
    assert not store.path.exists()


async def test_resume_skips_completed_tasks(make_context, tmp_path: Path) -> None:
    store = StateStore(tmp_path / "state.json")
    calls: list[str] = []
    fail = {"enabled": True}

    async def first(_ctx):
        calls.append("first")

    async def second(_ctx):
        calls.append("second")
        if fail["enabled"]:
            raise RuntimeError("transient")

    tasks = {
        "first": make_task("first", first),
        "second": make_task("second", second),
    }
    first_results = await Executor(make_context(), ["first", "second"], tasks=tasks, store=store).run()
    assert first_results[0].status is TaskStatus.OK
    assert first_results[1].status is TaskStatus.FAILED
    assert store.load().status is RunStatus.FAILED  # type: ignore[union-attr]

    calls.clear()
    fail["enabled"] = False
    resumed = await Executor(
        make_context(resume=True),
        ["first", "second"],
        tasks=tasks,
        store=store,
        resume=True,
    ).run()
    assert calls == ["second"]
    assert resumed[0].status is TaskStatus.SKIPPED
    assert resumed[1].status is TaskStatus.OK
    final_state = store.load()
    assert final_state is not None
    assert final_state.status is RunStatus.COMPLETED
    # Resume must not downgrade a completed task to "skipped".
    assert final_state.tasks["first"].status is TaskStatus.OK


async def test_unexpected_task_exception_is_recorded(make_context) -> None:
    async def explode(_ctx):
        raise KeyError("bad")

    tasks = {"explode": make_task("explode", explode)}
    results = await Executor(make_context(), ["explode"], tasks=tasks).run()
    assert results[0].status is TaskStatus.FAILED
    assert "KeyError" in (results[0].error or "")
