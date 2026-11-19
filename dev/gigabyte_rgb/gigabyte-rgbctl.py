#!/usr/bin/env python3
"""Hyprland helper for GIGABYTE A16 keyboard RGB."""
from __future__ import annotations

import colorsys
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

APP = "Gigabyte RGB"
DEFAULT_COLOR = "#00aaff"
PRESETS = [
    ("Red", "#ff3b30"), ("Orange", "#ff9500"), ("Yellow", "#ffd60a"),
    ("Green", "#30d158"), ("Mint", "#00d6a3"), ("Cyan", "#00d5e8"),
    ("Sky", "#00aaff"), ("Blue", "#2878ff"), ("Indigo", "#5856d6"),
    ("Purple", "#a855f7"), ("Pink", "#ff4fa3"), ("Rose", "#ff2d55"),
    ("White", "#ffffff"), ("Warm", "#ffd7a8"), ("Ice", "#a8eaff"),
]


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).expanduser()


def app_dir() -> Path:
    return config_home() / "gigabyte-rgb-studio"


def controller_path() -> Path:
    settings_path = app_dir() / "settings.json"
    try:
        saved = json.loads(settings_path.read_text(encoding="utf-8")).get("controller_path")
        if saved and Path(saved).is_file():
            return Path(saved).expanduser().resolve()
    except (OSError, ValueError, AttributeError):
        pass

    candidates = [
        Path.home() / "Gigabyte-Gaming-A16-Linux-KB-Drivers/scripts/gigabyte-kbd",
        Path("/usr/local/bin/gigabyte-kbd"),
        Path.home() / ".local/bin/gigabyte-kbd",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError(
        "gigabyte-kbd controller not found. Open RGB Studio once and select the project's "
        "scripts/gigabyte-kbd file so its path is saved."
    )


def state_path() -> Path:
    return app_dir() / "hyprland-state.json"


def lock_path() -> Path:
    return app_dir() / "hyprland.lock"


def read_controller_config() -> dict | None:
    """Read the controller's own config as the canonical color/brightness state.

    RGB Studio and direct gigabyte-kbd commands update this file. Reading it on
    every operation prevents the Hyprland helper from reverting to its own
    stale default color when brightness changes.
    """
    path = config_home() / "gigabyte-kbd.conf"
    values: dict[str, str] = {}
    try:
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    except OSError:
        return None

    color = values.get("color", "").strip()
    try:
        intensity = max(0, min(255, int(values.get("intensity", "255"))))
    except ValueError:
        intensity = 255
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", "#" + color.lstrip("#")):
        return None
    color = "#" + color.lstrip("#").lower()
    return {"color": color, "brightness": round(intensity * 100 / 255)}


def read_state() -> dict:
    """Read canonical controller state, with a JSON fallback for first use."""
    state = {}
    try:
        loaded = json.loads(state_path().read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            state = loaded
    except (OSError, ValueError):
        pass

    color = state.get("color", DEFAULT_COLOR)
    if not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        color = DEFAULT_COLOR
    try:
        brightness = max(0, min(100, int(state.get("brightness", 100))))
    except (TypeError, ValueError):
        brightness = 100

    # Always prefer the controller config. It is shared with RGB Studio and
    # gigabyte-kbd itself, so external color changes are picked up immediately.
    controller_state = read_controller_config()
    if controller_state is not None:
        color = controller_state["color"]
        brightness = controller_state["brightness"]

    return {"color": color.lower(), "brightness": brightness}


def write_state(state: dict) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".rgb-state-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(state, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def notify(title: str, message: str, urgency: str = "low", timeout_ms: int = 1200) -> None:
    executable = shutil.which("notify-send")
    if executable:
        subprocess.run(
            [executable, "-a", APP, "-r", "73104", "-t", str(timeout_ms), "-u", urgency, title, message],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    elif urgency == "critical":
        print(f"{title}: {message}", file=sys.stderr)


def apply_color(color: str, brightness: int) -> None:
    controller = controller_path()
    intensity = round(max(0, min(100, brightness)) * 255 / 100)
    command = [sys.executable, str(controller), "color", color.lstrip("#"), "--intensity", str(intensity)]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=20, check=False)
    if result.returncode != 0:
        output = result.stdout.strip() or f"Controller exited with status {result.returncode}."
        if "Permission denied" in output or "PermissionError" in output:
            output = "Access to the keyboard HID device was denied. Check the gigabyte-rgb udev rule and group membership."
        raise RuntimeError(output[-1200:])


def with_lock(action, wait_seconds: float = 2.0):
    app_dir().mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + max(0.0, wait_seconds)
    with lock_path().open("w", encoding="utf-8") as lock:
        while True:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("RGB controller is busy. Try the key again.")
                time.sleep(0.025)
        try:
            return action()
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def set_color(color: str) -> None:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError("Color must be a six-digit HEX value.")

    def action():
        state = read_state()
        apply_color(color, state["brightness"])
        state["color"] = color.lower()
        write_state(state)
        return state

    state = with_lock(action)
    if state is not None:
        notify("Keyboard color", f"{state['color'].upper()} · {state['brightness']}%")


def change_brightness(direction: str, step: int) -> None:
    step = max(1, min(25, abs(step)))

    def action():
        state = read_state()
        delta = step if direction == "up" else -step
        new_value = max(0, min(100, state["brightness"] + delta))
        if new_value == state["brightness"]:
            return state
        apply_color(state["color"], new_value)
        state["brightness"] = new_value
        write_state(state)
        return state

    state = with_lock(action, wait_seconds=3.0)
    if state is not None:
        notify_brightness(state)


def set_brightness(value: int) -> None:
    value = max(0, min(100, int(value)))

    def action():
        state = read_state()
        if value == state["brightness"]:
            return state
        apply_color(state["color"], value)
        state["brightness"] = value
        write_state(state)
        return state

    state = with_lock(action, wait_seconds=3.0)
    if state is not None:
        notify_brightness(state)


def notify_brightness(state: dict) -> None:
    value = state["brightness"]
    filled = round(value / 10)
    bar = "█" * filled + "░" * (10 - filled)
    notify("Keyboard RGB", f"{bar}  {value}%  ·  {state['color'].upper()}")


def enable_firmware_mode() -> None:
    """Hand keyboard lighting control back to the laptop firmware."""
    def action():
        controller = controller_path()
        result = subprocess.run(
            [sys.executable, str(controller), "auto"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
            check=False,
        )
        if result.returncode != 0:
            output = result.stdout.strip() or f"Controller exited with status {result.returncode}."
            if "Permission denied" in output or "PermissionError" in output:
                output = "Access to the keyboard HID device was denied. Check the gigabyte-rgb udev rule and group membership."
            raise RuntimeError(output[-1200:])
        return True

    with_lock(action, wait_seconds=3.0)
    notify("Keyboard firmware", "Firmware mode enabled · use Fn+Space to cycle lighting")


def mode_notification(active: bool) -> None:
    if active:
        notify("RGB MODE", "↑/↓ Brightness  ·  K Color picker  ·  F Firmware  ·  Esc Exit", timeout_ms=3200)
    else:
        notify("RGB MODE", "Control mode closed", timeout_ms=900)


class ColorPicker:
    BG = "#10141c"
    PANEL = "#191f2a"
    TEXT = "#f1f5fb"
    MUTED = "#95a1b3"
    BLUE = "#3988ff"

    def __init__(self):
        state = read_state()
        self.color = state["color"]
        r, g, b = (int(self.color[i:i + 2], 16) / 255 for i in (1, 3, 5))
        self.hue_value, self.saturation, self.value = colorsys.rgb_to_hsv(r, g, b)
        self.width, self.height = 340, 220
        self.sv_image = None
        self.hue_image = None

        self.root = tk.Tk()
        self.root.title("Keyboard RGB · Color Picker")
        self.root.configure(bg=self.BG)
        self.root.resizable(False, False)
        self.root.attributes("-topmost", True)
        self._build()
        self._draw_all()
        self.root.bind("<Escape>", lambda _event: self.root.destroy())
        self.root.bind("<Return>", lambda _event: self.apply())
        self.root.after(500, lambda: self.root.attributes("-topmost", False))

    def label(self, parent, text, size=10, color=None, bold=False):
        return tk.Label(parent, text=text, bg=parent.cget("bg"), fg=color or self.TEXT,
                        font=("DejaVu Sans", size, "bold" if bold else "normal"))

    def _build(self):
        outer = tk.Frame(self.root, bg=self.BG, padx=18, pady=16)
        outer.pack()
        self.label(outer, "CHOOSE KEYBOARD COLOR", 10, self.MUTED, True).pack(anchor="w")
        self.label(outer, "Pick any color from the spectrum", 17, self.TEXT, True).pack(anchor="w", pady=(4, 13))

        row = tk.Frame(outer, bg=self.BG)
        row.pack()
        self.sv = tk.Canvas(row, width=self.width, height=self.height, highlightthickness=0,
                            cursor="crosshair", bd=0)
        self.sv.pack(side="left")
        self.sv.bind("<Button-1>", self.pick_sv)
        self.sv.bind("<B1-Motion>", self.pick_sv)
        self.hue_canvas = tk.Canvas(row, width=24, height=self.height, highlightthickness=0,
                             cursor="hand2", bd=0)
        self.hue_canvas.pack(side="left", padx=(10, 0))
        self.hue_canvas.bind("<Button-1>", self.pick_hue)
        self.hue_canvas.bind("<B1-Motion>", self.pick_hue)

        preview_row = tk.Frame(outer, bg=self.BG)
        preview_row.pack(fill="x", pady=(12, 9))
        self.swatch = tk.Frame(preview_row, bg=self.color, width=42, height=30,
                               highlightthickness=1, highlightbackground="#ffffff")
        self.swatch.pack(side="left")
        self.swatch.pack_propagate(False)
        self.hex_label = self.label(preview_row, self.color.upper(), 11, self.TEXT, True)
        self.hex_label.pack(side="left", padx=10)
        self.label(preview_row, "Click a color, then Apply", 9, self.MUTED).pack(side="right")

        self.label(outer, "QUICK COLORS", 9, self.MUTED, True).pack(anchor="w", pady=(5, 7))
        palette = tk.Frame(outer, bg=self.BG)
        palette.pack(fill="x")
        for index, (name, color) in enumerate(PRESETS):
            chip = tk.Canvas(palette, width=34, height=34, bg=self.BG,
                             highlightthickness=0, cursor="hand2")
            chip.create_oval(4, 4, 30, 30, fill=color, outline="#ffffff" if color == "#ffffff" else color)
            chip.bind("<Button-1>", lambda _event, c=color: self.set_color(c))
            chip.bind("<Enter>", lambda _event, n=name: self.root.title(f"Keyboard RGB · {n}"))
            chip.bind("<Leave>", lambda _event: self.root.title("Keyboard RGB · Color Picker"))
            chip.grid(row=index // 8, column=index % 8, padx=(0, 7), pady=(0, 5))

        buttons = tk.Frame(outer, bg=self.BG)
        buttons.pack(fill="x", pady=(12, 0))
        tk.Button(buttons, text="Cancel", command=self.root.destroy, bg=self.PANEL,
                  fg=self.TEXT, activebackground="#303b4d", activeforeground=self.TEXT,
                  relief="flat", padx=18, pady=9, font=("DejaVu Sans", 9)).pack(side="right")
        tk.Button(buttons, text="Apply color", command=self.apply, bg=self.BLUE,
                  fg="white", activebackground="#2675e8", activeforeground="white",
                  relief="flat", padx=20, pady=9, font=("DejaVu Sans", 9, "bold")).pack(side="right", padx=(0, 8))

    def _draw_all(self):
        photo = tk.PhotoImage(width=self.width, height=self.height)
        for y in range(self.height):
            v = 1.0 - y / (self.height - 1)
            row = []
            for x in range(self.width):
                s = x / (self.width - 1)
                rgb = colorsys.hsv_to_rgb(self.hue_value, s, v)
                row.append("#" + "".join(f"{round(c * 255):02x}" for c in rgb))
            photo.put("{" + " ".join(row) + "}", to=(0, y))
        self.sv_image = photo
        self.sv.delete("all")
        self.sv.create_image(0, 0, image=photo, anchor="nw")
        self._draw_hue()
        self._draw_marker()

    def _draw_hue(self):
        photo = tk.PhotoImage(width=24, height=self.height)
        for y in range(self.height):
            rgb = colorsys.hsv_to_rgb(y / (self.height - 1), 1, 1)
            color = "#" + "".join(f"{round(c * 255):02x}" for c in rgb)
            photo.put(color, to=(0, y, 24, y + 1))
        self.hue_image = photo
        self.hue_canvas.delete("all")
        self.hue_canvas.create_image(0, 0, image=photo, anchor="nw")
        y = self.hue_value_to_y()
        self.hue_canvas.create_rectangle(0, y - 2, 24, y + 2, outline="#ffffff", width=2)

    def hue_value_to_y(self):
        return round(self.hue_value * (self.height - 1))

    def _draw_marker(self):
        self.sv.delete("marker")
        x = round(self.saturation * (self.width - 1))
        y = round((1 - self.value) * (self.height - 1))
        self.sv.create_oval(x - 7, y - 7, x + 7, y + 7, outline="#111111", width=3, tags="marker")
        self.sv.create_oval(x - 5, y - 5, x + 5, y + 5, outline="#ffffff", width=2, tags="marker")

    def _update_color(self):
        rgb = colorsys.hsv_to_rgb(self.hue_value, self.saturation, self.value)
        self.color = "#" + "".join(f"{round(c * 255):02x}" for c in rgb)
        self.swatch.configure(bg=self.color)
        self.hex_label.configure(text=self.color.upper())

    def set_color(self, color):
        self.color = color.lower()
        r, g, b = (int(self.color[i:i + 2], 16) / 255 for i in (1, 3, 5))
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        self.hue_value, self.saturation, self.value = h, s, v
        self._draw_all()
        self.swatch.configure(bg=self.color)
        self.hex_label.configure(text=self.color.upper())

    def pick_sv(self, event):
        self.saturation = min(1, max(0, event.x / (self.width - 1)))
        self.value = 1 - min(1, max(0, event.y / (self.height - 1)))
        self._draw_marker()
        self._update_color()

    def pick_hue(self, event):
        self.hue_value = min(1, max(0, event.y / (self.height - 1)))
        self._draw_all()
        self._update_color()

    def apply(self):
        try:
            set_color(self.color)
        except Exception as exc:
            messagebox.showerror(APP, str(exc), parent=self.root)
            return
        self.root.destroy()

    def run(self):
        self.root.mainloop()


def main(argv: list[str]) -> int:
    if len(argv) == 1 or argv[1] in {"-h", "--help"}:
        print(
            "Usage: gigabyte-rgbctl picker | brightness up|down [step] | "
            "brightness set <0-100> | firmware | mode enter|exit | status"
        )
        return 0
    try:
        if argv[1] == "picker":
            ColorPicker().run()
            return 0
        if argv[1] in {"firmware", "auto"} and len(argv) == 2:
            enable_firmware_mode()
            return 0
        if argv[1] == "brightness" and len(argv) >= 3:
            if argv[2] in {"up", "down"}:
                step = int(argv[3]) if len(argv) >= 4 else 5
                change_brightness(argv[2], step)
                return 0
            if argv[2] == "set" and len(argv) >= 4:
                set_brightness(int(argv[3]))
                return 0
        if argv[1] == "mode" and len(argv) >= 3:
            if argv[2] == "enter":
                mode_notification(True)
                return 0
            if argv[2] == "exit":
                mode_notification(False)
                return 0
        if argv[1] == "status":
            state = read_state()
            print(f"Color: {state['color']}\nBrightness: {state['brightness']}%")
            return 0
        raise ValueError("Unknown command. Run gigabyte-rgbctl --help.")
    except Exception as exc:
        notify("RGB control failed", str(exc), "critical")
        print(f"{APP}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
