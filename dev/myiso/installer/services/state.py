"""Installer state management."""
import json
from pathlib import Path
from typing import Any

STAGES = [
    "preflight",
    "disk",
    "partition",
    "format",
    "mount",
    "base",
    "packages",
    "kernel",
    "network",
    "users",
    "configuration",
    "bootloader",
    "cleanup",
    "finalize",
]

class InstallerState:
    def __init__(self, state_file: Path = Path("logs/state.json")):
        self.state_file = state_file
        self._state = self._load()

    def _load(self) -> dict[str, Any]:
        if self.state_file.exists():
            try:
                return json.loads(self.state_file.read_text())
            except (json.JSONDecodeError, OSError):
                pass
        return {stage: "pending" for stage in STAGES}

    def save(self):
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(json.dumps(self._state, indent=2))

    def get(self, key: str, default=None):
        return self._state.get(key, default)

    def set(self, key: str, value):
        self._state[key] = value
        self.save()

    def mark_done(self, stage: str):
        self.set(stage, "done")

    def mark_running(self, stage: str):
        self.set(stage, "running")

    def mark_pending(self, stage: str):
        self.set(stage, "pending")

    def mark_failed(self, stage: str):
        self.set(stage, "failed")
