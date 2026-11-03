"""Interactive configuration screen."""
import asyncio
from textual.screen import Screen
from textual.widgets import Header, Footer, Static, Input, Select, Button, Label
from textual.containers import Vertical, Horizontal
from installer.models.installer_config import InstallerConfig

class ConfigScreen(Screen):
    def __init__(self, config: InstallerConfig):
        super().__init__()
        self.config = config
        self.disks = []
        self.selected_disk = config.target_disk

    def compose(self):
        yield Header()
        with Vertical(id="config-form"):
            yield Static("System Configuration", id="title")
            yield Label("Select Target Disk:")
            yield Select([], id="disk-select", prompt="Loading disks...")
            yield Label("Profile:")
            yield Select(
                [
                    ("Minimal", "minimal"),
                    ("Server", "server"),
                    ("Desktop", "desktop"),
                    ("Development", "development"),
                    ("Custom", "custom"),
                ],
                id="profile-select",
                value=self.config.profile,
            )
            yield Label("Hostname:")
            yield Input(value=self.config.hostname, id="hostname-input")
            yield Label("Username:")
            yield Input(value=self.config.username, id="username-input")
            yield Label("Password:")
            yield Input(password=True, id="password-input")
            yield Label("Timezone (e.g., UTC, Europe/Berlin):")
            yield Input(value=self.config.timezone, id="timezone-input")
            yield Label("Locale (e.g., en_US.UTF-8):")
            yield Input(value=self.config.locale, id="locale-input")
            yield Label("Keyboard layout (e.g., us, de):")
            yield Input(value=self.config.keyboard, id="keyboard-input")
            yield Label("Filesystem:")
            yield Select(
                [
                    ("ext4", "ext4"),
                    ("xfs", "xfs"),
                    ("btrfs", "btrfs"),
                ],
                id="filesystem-select",
                value=self.config.filesystem,
            )
            yield Label("Kernel:")
            yield Select(
                [
                    ("linux", "linux"),
                    ("linux-lts", "linux-lts"),
                ],
                id="kernel-select",
                value=self.config.kernel,
            )
            yield Label("Bootloader:")
            yield Select(
                [
                    ("GRUB", "grub"),
                    ("Syslinux", "syslinux"),
                ],
                id="bootloader-select",
                value=self.config.bootloader,
            )
            with Horizontal():
                yield Button("Confirm", id="confirm-btn", variant="primary")
                yield Button("Exit", id="exit-btn", variant="error")
        yield Footer()

    async def on_mount(self):
        # Load disks asynchronously
        asyncio.create_task(self._load_disks())

    async def _load_disks(self):
        try:
            proc = await asyncio.create_subprocess_exec(
                "bash", "scripts/list_disks.sh",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            output = stdout.decode().strip()
            self.disks = []
            if output:
                for line in output.splitlines():
                    parts = line.split()
                    if parts:
                        self.disks.append(parts[0])  # /dev/sda
            # Update Select options
            disk_select = self.query_one("#disk-select", Select)
            disk_select.set_options([(d, d) for d in self.disks])
            if self.selected_disk in self.disks:
                disk_select.value = self.selected_disk
            elif self.disks:
                disk_select.value = self.disks[0]
        except Exception as e:
            self.notify(f"Failed to list disks: {e}", severity="error")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "confirm-btn":
            self._confirm()
        elif event.button.id == "exit-btn":
            self.app.exit()

    def _confirm(self):
        config = InstallerConfig(
            target_disk=self.query_one("#disk-select", Select).value or "",
            profile=self.query_one("#profile-select", Select).value,
            hostname=self.query_one("#hostname-input", Input).value.strip(),
            username=self.query_one("#username-input", Input).value.strip(),
            timezone=self.query_one("#timezone-input", Input).value.strip(),
            locale=self.query_one("#locale-input", Input).value.strip(),
            keyboard=self.query_one("#keyboard-input", Input).value.strip(),
            filesystem=self.query_one("#filesystem-select", Select).value,
            kernel=self.query_one("#kernel-select", Select).value,
            bootloader=self.query_one("#bootloader-select", Select).value,
            mount_root="/mnt/myiso",
            repo_url=self.config.repo_url,
            arch=self.config.arch,
        )
        if not config.target_disk:
            self.notify("Please select a target disk", severity="error")
            return
        if not config.hostname:
            self.notify("Hostname cannot be empty", severity="error")
            return
        if not config.username:
            self.notify("Username cannot be empty", severity="error")
            return

        password = self.query_one("#password-input", Input).value

        # Import here to avoid circular imports
        from installer.screens.main_screen import MainScreen
        self.app.switch_screen(MainScreen(config, password))
