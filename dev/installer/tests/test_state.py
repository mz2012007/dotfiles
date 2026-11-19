from __future__ import annotations

import json
from pathlib import Path

import pytest

from voidsetup.errors import StateError
from voidsetup.models import RunStatus, TaskStatus
from voidsetup.state import RunState, StateStore, TaskState


def test_run_state_roundtrip() -> None:
    state = RunState.new("during_work", ["update", "packages"])
    state.start_task("update")
    state.finish_task("update", TaskStatus.OK, duration=1.5)
    restored = RunState.from_dict(state.to_dict())
    assert restored.run_id == state.run_id
    assert restored.profile == "during_work"
    assert restored.plan == ["update", "packages"]
    assert restored.tasks["update"].status is TaskStatus.OK
    assert restored.tasks["update"].duration == 1.5


def test_task_state_tolerates_bad_status() -> None:
    task = TaskState.from_dict({"status": "nonsense", "duration": "2.5"})
    assert task.status is TaskStatus.PENDING
    assert task.duration == 2.5


def test_store_roundtrip_and_reset(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    store = StateStore(path)
    state = RunState.new("custom", ["fonts"])
    store.save(state)
    loaded = store.load()
    assert loaded is not None
    assert loaded.run_id == state.run_id
    store.reset()
    assert store.load() is None


def test_store_quarantines_corrupt_state(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    path.write_text("{not json")
    store = StateStore(path)
    assert store.load() is None
    assert not path.exists()
    assert path.with_suffix(".json.corrupt").exists()


def test_begin_resume_keeps_completed_tasks(tmp_path: Path) -> None:
    store = StateStore(tmp_path / "state.json")
    state = RunState.new("custom", ["a", "b"])
    state.finish_task("a", TaskStatus.OK)
    store.save(state)

    resumed = store.begin("custom", ["a", "b"], resume=True)
    assert resumed.run_id == state.run_id
    assert resumed.tasks["a"].status is TaskStatus.OK
    assert resumed.status is RunStatus.RUNNING


def test_begin_resume_rejects_a_changed_plan(tmp_path: Path) -> None:
    store = StateStore(tmp_path / "state.json")
    state = RunState.new("custom", ["a", "b"])
    state.finish_task("a", TaskStatus.OK)
    store.save(state)

    with pytest.raises(StateError):
        store.begin("custom", ["a", "b", "c"], resume=True)
    with pytest.raises(StateError):
        store.begin("custom", ["a"], resume=True)


def test_begin_without_resume_ignores_a_changed_plan(tmp_path: Path) -> None:
    store = StateStore(tmp_path / "state.json")
    old = RunState.new("custom", ["a"])
    old.finish_task("a", TaskStatus.OK)
    store.save(old)

    new = store.begin("custom", ["b"], resume=False)
    assert new.run_id != old.run_id
    assert new.plan == ["b"]


def test_begin_without_resume_starts_fresh(tmp_path: Path) -> None:
    store = StateStore(tmp_path / "state.json")
    old = RunState.new("custom", ["a"])
    old.finish_run(RunStatus.COMPLETED)
    store.save(old)

    new = store.begin("custom", ["b"], resume=False)
    assert new.run_id != old.run_id
    assert new.tasks == {}


def test_is_resumable() -> None:
    state = RunState.new("custom", [])
    assert state.is_resumable
    state.finish_run(RunStatus.COMPLETED)
    assert not state.is_resumable
    state.finish_run(RunStatus.FAILED)
    assert state.is_resumable


def test_saved_file_is_valid_json(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    StateStore(path).save(RunState.new("custom", ["fonts"]))
    data = json.loads(path.read_text())
    assert data["version"] == 1
    assert data["status"] == "running"
    assert "tasks" in data
