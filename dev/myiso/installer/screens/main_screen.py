"""Main installer screen."""
import asyncio
from pathlib import Path
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, ProgressBar, Button
from textual.containers import Vertical, Horizontal
from installer.widgets.stage_list import StageList
from installer.widgets.log_view import LogView
from installer.services.runner import BashRunner
from installer.services.logger import InstallerLogger
from installer.services.state import InstallerState, STAGES
from installer.models.installer_config import InstallerConfig

class MainScreen(Screen):
    def __init__(self):
        super().__init__()
        self.logger = InstallerLogger()
        self.runner = BashRunner(self.logger)
        self.state = InstallerState()
        self.config = InstallerConfig.from_file()

    def compose(self):
        yield Header()
        with Vertical():
            yield Static("myiso Installer", id="title")
            yield StageList(self.state, id="stage-list")
            yield ProgressBar(total=100, show_eta=False, id="progress-bar")
            yield LogView(id="log-view")
            with Horizontal():
                yield Button("Start Installation", id="start-button", variant="primary")
                yield Button("Exit", id="exit-button", variant="error")
        yield Footer()

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "start-button":
            await self.start_installation()
        elif event.button.id == "exit-button":
            self.app.exit()

    async def start_installation(self):
        self.query_one("#start-button", Button).disabled = True
        await self._run_stages()

    async def _run_stages(self):
        # Step 1: Preflight
        await self._run_stage("preflight", "scripts/preflight.sh", [], {})

        # Step 2: Disk selection (only for demonstration, we require config target_disk set)
        if not self.config.target_disk:
            self.log_view.write("Error: target_disk not set in config.")
            return
        await self._run_stage("disk", "scripts/list_disks.sh", [], {})

        # Confirm destructive operations
        if not await self._confirm_disk():
            self.log_view.write("Installation cancelled.")
            return

        # Proceed with other stages
        disk = self.config.target_disk
        root = self.config.mount_root
        profile = self.config.profile
        repo = self.config.repo_url
        arch = self.config.arch
        kernel = self.config.kernel
        bootloader = self.config.bootloader

        stages_to_run = [
            ("partition", "scripts/partition.sh", ["--disk", disk]),
            ("format", "scripts/format.sh", ["--disk", disk, "--filesystem", self.config.filesystem]),
            ("mount", "scripts/mount.sh", ["--disk", disk, "--root", root]),
            ("base", "scripts/base.sh", ["--root", root, "--repo", repo, "--arch", arch]),
            ("packages", "scripts/packages.sh", ["--root", root, "--profile", profile, "--repo", repo]),
            ("kernel", "scripts/kernel.sh", ["--root", root, "--kernel", kernel]),
            ("network", "scripts/network.sh", ["--root", root, "--hostname", self.config.hostname]),
            ("users", "scripts/users.sh", ["--root", root, "--username", self.config.username]),
            ("configuration", "scripts/configuration.sh", [
                "--root", root,
                "--hostname", self.config.hostname,
                "--timezone", self.config.timezone,
                "--locale", self.config.locale,
                "--keyboard", self.config.keyboard,
            ]),
            ("bootloader", "scripts/bootloader.sh", [
                "--root", root,
                "--disk", disk,
                "--bootloader", bootloader,
            ]),
            ("cleanup", "scripts/cleanup.sh", ["--root", root]),
            ("finalize", "scripts/finalize.sh", ["--root", root]),
        ]

        for stage, script, args in stages_to_run:
            success = await self._run_stage(stage, script, args, {})
            if not success:
                return

        self.log_view.write("[green]Installation completed successfully![/]")

    async def _run_stage(self, stage: str, script: str, args: list, env: dict) -> bool:
        self.state.mark_running(stage)
        self._update_stage_ui(stage)
        self.log_view.write(f"Starting stage: {stage}")
        exit_code = await self.runner.run(
            script=script,
            args=args,
            environment=env,
            on_stdout=lambda line: self._handle_output(line),
            on_stderr=lambda line: self._handle_output(line, error=True),
        )
        if exit_code == 0:
            self.state.mark_done(stage)
            self._update_stage_ui(stage)
            self.log_view.write(f"[green]Stage {stage} completed successfully.[/]")
            return True
        else:
            self.state.mark_failed(stage)
            self._update_stage_ui(stage)
            self.log_view.write(f"[red]Stage {stage} failed with exit code {exit_code}.[/]")
            await self._show_error(stage, exit_code)
            return False

    def _handle_output(self, line: str, error: bool = False):
        if error:
            self.log_view.write(f"[red]{line}[/]")
        else:
            self.log_view.write(line)

    def _update_stage_ui(self, stage: str):
        stage_list = self.query_one("#stage-list", StageList)
        stage_list.refresh_stage(stage)
        # Update progress bar
        total = len(STAGES)
        done = sum(1 for s in STAGES if self.state.get(s) == "done")
        running = 1 if self.state.get(stage) == "running" else 0
        progress = (done + running * 0.5) / total * 100
        self.query_one("#progress-bar", ProgressBar).update(progress=progress)

    async def _confirm_disk(self) -> bool:
        from installer.screens.confirm_screen import ConfirmScreen
        disk = self.config.target_disk
        confirmed = await self.app.push_screen_wait(ConfirmScreen(disk))
        return confirmed

    async def _show_error(self, stage: str, exit_code: int):
        from installer.screens.error_screen import ErrorScreen
        await self.app.push_screen_wait(ErrorScreen(stage, exit_code, self.logger.path))
