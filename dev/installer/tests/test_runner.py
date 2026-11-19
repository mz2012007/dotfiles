from __future__ import annotations

import asyncio

import pytest

from voidsetup.errors import CommandError, ExecutionCancelled
from voidsetup.runner import Runner
from voidsetup.session_log import SessionLogger


@pytest.fixture
def runner() -> Runner:
    return Runner(SessionLogger())


async def test_dry_run_does_not_execute(tmp_path) -> None:
    marker = tmp_path / "marker"
    runner = Runner(SessionLogger(), dry_run=True)
    result = await runner.run("sh", "-c", f"touch {marker}")
    assert result.ok
    assert not marker.exists()


async def test_run_streams_and_captures(tmp_path) -> None:
    runner = Runner(SessionLogger())
    result = await runner.run("sh", "-c", "printf 'hello\\nworld\\n'", capture=True)
    assert result.returncode == 0
    assert result.output.splitlines() == ["hello", "world"]


async def test_run_stdin(tmp_path) -> None:
    runner = Runner(SessionLogger())
    result = await runner.run("cat", input="piped text\n", capture=True)
    assert result.output == "piped text"


async def test_check_raises_command_error() -> None:
    runner = Runner(SessionLogger())
    with pytest.raises(CommandError) as excinfo:
        await runner.run("sh", "-c", "echo bad >&2; exit 7")
    assert excinfo.value.returncode == 7
    assert "bad" in str(excinfo.value)


async def test_check_false_returns_result() -> None:
    runner = Runner(SessionLogger())
    result = await runner.run("sh", "-c", "exit 4", check=False)
    assert result.returncode == 4
    assert not result.ok


async def test_missing_command_is_reported() -> None:
    runner = Runner(SessionLogger())
    with pytest.raises(CommandError) as excinfo:
        await runner.run("voidsetup-command-that-does-not-exist")
    # 127 = not found; 126 can occur when a PATH entry is unreadable.
    assert excinfo.value.returncode in (126, 127)


async def test_output_runs_even_in_dry_run() -> None:
    runner = Runner(SessionLogger(), dry_run=True)
    assert (await runner.output("printf", "probe")).strip() == "probe"


async def test_output_check_false() -> None:
    runner = Runner(SessionLogger())
    output = await runner.output("sh", "-c", "echo out; echo err >&2; exit 3", check=False)
    assert "out" in output
    assert "err" in output


async def test_probe_result_exposes_exit_code() -> None:
    runner = Runner(SessionLogger())
    result = await runner.probe_result("sh", "-c", "exit 9", check=False)
    assert result.returncode == 9
    assert not result.ok


async def test_timeout_is_local_to_the_command() -> None:
    runner = Runner(SessionLogger())
    with pytest.raises(CommandError) as excinfo:
        await runner.run("sh", "-c", "sleep 5", timeout=0.1)
    assert excinfo.value.returncode == 124
    assert not runner.cancelled
    # The runner must remain usable after a timeout.
    assert (await runner.output("printf", "ok")).strip() == "ok"


async def test_probe_timeout_terminates_it() -> None:
    runner = Runner(SessionLogger())
    with pytest.raises(CommandError) as excinfo:
        await runner.probe_result("sh", "-c", "sleep 5", timeout=0.1)
    assert excinfo.value.returncode == 124
    # The runner must remain usable after a probe timeout.
    assert (await runner.output("printf", "ok")).strip() == "ok"


async def test_cancel_kills_current_command() -> None:
    runner = Runner(SessionLogger())
    task = asyncio.create_task(runner.run("sh", "-c", "sleep 5"))
    await asyncio.sleep(0.2)
    await runner.cancel()
    with pytest.raises(ExecutionCancelled):
        await task
    assert runner.cancelled


async def test_cancelled_runner_refuses_new_commands() -> None:
    runner = Runner(SessionLogger())
    await runner.cancel()
    with pytest.raises(ExecutionCancelled):
        await runner.run("true")
    with pytest.raises(ExecutionCancelled):
        await runner.output("true")
    runner.reset_cancel()
    assert (await runner.output("printf", "again")).strip() == "again"
