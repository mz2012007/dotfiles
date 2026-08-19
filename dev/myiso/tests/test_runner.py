import asyncio
import pytest
from installer.services.runner import BashRunner
from installer.services.logger import InstallerLogger

@pytest.mark.asyncio
async def test_runner_success():
    logger = InstallerLogger(log_dir="logs/test")
    runner = BashRunner(logger)
    code = await runner.run("scripts/finalize.sh", ["--root", "/tmp/test-root", "--dry-run"])
    assert code == 0

@pytest.mark.asyncio
async def test_runner_failure():
    logger = InstallerLogger(log_dir="logs/test")
    runner = BashRunner(logger)
    code = await runner.run("scripts/nonexistent.sh")
    assert code == 127
