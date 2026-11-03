import asyncio
import tempfile
import os
from installer.services.runner import BashRunner
from installer.services.logger import InstallerLogger

def test_runner_success():
    with tempfile.TemporaryDirectory() as tmpdir:
        logger = InstallerLogger(log_dir=os.path.join(tmpdir, "logs"))
        runner = BashRunner(logger)
        exit_code = asyncio.run(runner.run(
            script="scripts/finalize.sh",
            args=["--root", tmpdir, "--dry-run"]
        ))
        assert exit_code == 0

def test_runner_failure():
    logger = InstallerLogger(log_dir="logs/test")
    runner = BashRunner(logger)
    exit_code = asyncio.run(runner.run("scripts/nonexistent.sh"))
    assert exit_code == 127
