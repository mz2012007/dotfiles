"""Asynchronous Bash script runner with live output streaming."""
import asyncio
import os
from pathlib import Path
from typing import Optional, Callable
from installer.services.logger import InstallerLogger

class BashRunner:
    def __init__(self, logger: InstallerLogger):
        self.logger = logger
        self.current_process: Optional[asyncio.subprocess.Process] = None

    async def run(
        self,
        script: str,
        args: list[str] | None = None,
        environment: dict[str, str] | None = None,
        cwd: str | None = None,
        on_stdout: Callable[[str], None] | None = None,
        on_stderr: Callable[[str], None] | None = None,
    ) -> int:
        args = args or []
        environment = environment or {}
        script_path = Path(script)
        if not script_path.is_file():
            self.logger.error(f"Script not found: {script}")
            return 127

        cmd = ["bash", str(script_path), *args]
        env = {**os.environ, **environment}

        self.logger.info(f"Executing: {' '.join(cmd)}")
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            env=env,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.current_process = proc

        async def read_stream(stream, callback, level):
            while True:
                line = await stream.readline()
                if not line:
                    break
                text = line.decode(errors="replace").rstrip()
                if callback:
                    callback(text)
                if level == "error":
                    self.logger.error(text)
                else:
                    self.logger.info(text)

        await asyncio.gather(
            read_stream(proc.stdout, on_stdout, "info"),
            read_stream(proc.stderr, on_stderr, "error"),
        )
        exit_code = await proc.wait()
        self.current_process = None
        if exit_code != 0:
            self.logger.error(f"Script exited with code {exit_code}")
        else:
            self.logger.info("Script completed successfully")
        return exit_code

    async def cancel(self):
        if self.current_process and self.current_process.returncode is None:
            self.current_process.terminate()
            try:
                await asyncio.wait_for(self.current_process.wait(), timeout=5)
            except asyncio.TimeoutError:
                self.current_process.kill()
