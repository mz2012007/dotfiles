#!/usr/bin/env python3
"""GUI for the GIGABYTE GAMING A16 HID LampArray keyboard controller."""

from __future__ import annotations

import colorsys
import grp
import json
import os
import pwd
import queue
import re
import shutil
import stat
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

APP_NAME = "Gigabyte RGB Studio"
DEFAULT_COLOR = "#00aaff"
PERMISSION_GROUP = "gigabyte-rgb"
UDEV_RULE = """# Access only the GIGABYTE A16 keyboard HID interfaces for RGB control.
SUBSYSTEM==\"hidraw\", KERNEL==\"hidraw*\", ATTRS{idVendor}==\"0414\", ATTRS{idProduct}==\"8104\", GROUP=\"gigabyte-rgb\", MODE=\"0660\"
"""

PRESETS = [
    ("Red", "#ff3b30"), ("Coral", "#ff6b5f"), ("Orange", "#ff9500"),
    ("Amber", "#ffbf00"), ("Yellow", "#ffd60a"), ("Lime", "#a8e000"),
    ("Green", "#30d158"), ("Mint", "#00d6a3"), ("Cyan", "#00d5e8"),
    ("Sky", "#00aaff"), ("Blue", "#2878ff"), ("Indigo", "#5856d6"),
    ("Violet", "#a855f7"), ("Purple", "#bf5af2"), ("Pink", "#ff4fa3"),
    ("Rose", "#ff2d55"), ("White", "#ffffff"), ("Warm", "#ffd7a8"),
]


def config_file() -> Path:
    base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).expanduser()
    return base / "gigabyte-rgb-studio" / "settings.json"


def load_settings() -> dict:
    try:
        data = json.loads(config_file().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_settings(settings: dict) -> None:
    path = config_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(settings, indent=2), encoding="utf-8")
    temporary.replace(path)


def candidate_controllers() -> list[str]:
    here = Path(__file__).resolve().parent
    return [
        os.environ.get("GIGABYTE_KBD_BIN", ""),
        shutil.which("gigabyte-kbd") or "",
        str(Path.home() / ".local/bin/gigabyte-kbd"),
        "/usr/local/bin/gigabyte-kbd",
        "/usr/bin/gigabyte-kbd",
        str(here / "scripts/gigabyte-kbd"),
        str(here / "Gigabyte-Gaming-A16-Linux-KB-Drivers/scripts/gigabyte-kbd"),
    ]


def validate_controller(path: str) -> tuple[bool, str]:
    candidate = Path(path).expanduser()
    if not candidate.is_file():
        return False, "That file does not exist. Select the project's scripts/gigabyte-kbd file."
    try:
        result = subprocess.run(
            [sys.executable, str(candidate), "detect"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=12, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"Could not run the controller: {exc}"

    output = result.stdout.strip()
    ids = re.search(r"\b0414\s+8104\b", output, re.IGNORECASE)
    if result.returncode == 0 and ids:
        return True, output or "GIGABYTE 0414:8104 detected."
    return False, output or "The controller did not detect the GIGABYTE LampArray device."


def install_permissions() -> int:
    """Install a narrowly-scoped udev rule and add the invoking user to its group."""
    if os.geteuid() != 0:
        print("This setup action must be run through pkexec.", file=sys.stderr)
        return 1

    try:
        invoking_uid = int(os.environ["PKEXEC_UID"])
        account = pwd.getpwuid(invoking_uid)
    except (KeyError, ValueError) as exc:
        print(f"Cannot identify the user who started the application: {exc}", file=sys.stderr)
        return 1

    try:
        try:
            grp.getgrnam(PERMISSION_GROUP)
        except KeyError:
            subprocess.run(["groupadd", "--system", PERMISSION_GROUP], check=True)

        subprocess.run(["usermod", "-aG", PERMISSION_GROUP, account.pw_name], check=True)

        rule_path = Path("/etc/udev/rules.d/99-gigabyte-rgb.rules")
        rule_path.parent.mkdir(parents=True, exist_ok=True)
        rule_path.write_text(UDEV_RULE, encoding="utf-8")

        subprocess.run(["udevadm", "control", "--reload-rules"], check=True)
        subprocess.run(["udevadm", "trigger", "--action=change", "--subsystem-match=hidraw"], check=True)
        subprocess.run(["udevadm", "settle", "--timeout=15"], check=True)

        # Confirm that the LampArray hidraw node actually received the intended group.
        group_gid = grp.getgrnam(PERMISSION_GROUP).gr_gid
        lamp_nodes = []
        for sys_node in Path("/sys/class/hidraw").glob("hidraw*"):
            descriptor = sys_node / "device" / "report_descriptor"
            try:
                raw_descriptor = descriptor.read_bytes()
                if bytes((0x05, 0x59, 0x09, 0x01)) not in raw_descriptor:
                    continue
                device_node = Path("/dev") / sys_node.name
                node_stat = device_node.stat()
                lamp_nodes.append((device_node, node_stat))
            except OSError:
                continue

        if not lamp_nodes:
            raise RuntimeError("Could not locate the LampArray hidraw node after refreshing udev.")

        incorrectly_configured = [
            (node, node_stat)
            for node, node_stat in lamp_nodes
            if node_stat.st_gid != group_gid or not (node_stat.st_mode & stat.S_IWGRP)
        ]
        if incorrectly_configured:
            details = ", ".join(
                f"{node} (group={grp.getgrgid(node_stat.st_gid).gr_name}, mode={stat.S_IMODE(node_stat.st_mode):04o})"
                for node, node_stat in incorrectly_configured
            )
            raise RuntimeError(
                "The udev rule was written, but it did not grant the RGB group access to: " + details
            )
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"Permission setup failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"Access configured for {account.pw_name}.\n"
        f"Udev rule: /etc/udev/rules.d/99-gigabyte-rgb.rules\n"
        "Log out of your desktop session and log back in once.\n"
        "After that, RGB control will not ask for a password.\n"
        "The HID device permissions were refreshed.\n"
        + "Verified LampArray node(s): "
        + ", ".join(str(node) for node, _node_stat in lamp_nodes)
    )
    return 0



class RGBApp:
    BG = "#0d1016"
    PANEL = "#171c25"
    PANEL_2 = "#202735"
    BORDER = "#2a3444"
    TEXT = "#f2f5fa"
    MUTED = "#8f9bad"
    BLUE = "#3988ff"

    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title(APP_NAME)
        self.root.geometry("760x850")
        self.root.minsize(680, 790)
        self.root.configure(bg=self.BG)

        self.settings = load_settings()
        self.controller = self._load_controller()
        self.hue = 0.55
        self.saturation = 1.0
        self.value = 1.0
        self.color = DEFAULT_COLOR
        self.brightness = tk.IntVar(value=100)
        self.status = tk.StringVar(value="Ready" if self.controller else "Controller not configured")
        self.busy = False
        self.results: queue.Queue[tuple[str, bool, str]] = queue.Queue()
        self._sv_photo = None
        self._hue_photo = None
        self._sv_width = 370
        self._sv_height = 210

        self._setup_style()
        self._build_ui()
        self._set_color(DEFAULT_COLOR, update_hue=True)
        self.root.after(100, self._poll_results)

        if not self.controller:
            self.root.after(300, self.choose_controller)
        else:
            self.root.after(350, lambda: self.run_controller(["info"], "Checking keyboard…", "info"))

    def _load_controller(self) -> str | None:
        saved = str(self.settings.get("controller_path", "")).strip()
        if saved and Path(saved).is_file():
            return str(Path(saved).resolve())

        for candidate in candidate_controllers():
            if not candidate or not Path(candidate).is_file():
                continue
            valid, _ = validate_controller(candidate)
            if valid:
                resolved = str(Path(candidate).resolve())
                self.settings["controller_path"] = resolved
                save_settings(self.settings)
                return resolved
        return None

    def _setup_style(self):
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TButton", font=("DejaVu Sans", 9), padding=(11, 8),
                        background=self.PANEL_2, foreground=self.TEXT, borderwidth=0)
        style.map("TButton", background=[("active", "#344258"), ("disabled", "#242b36")])
        style.configure("Primary.TButton", font=("DejaVu Sans", 10, "bold"), padding=(15, 11),
                        background=self.BLUE, foreground="#ffffff")
        style.map("Primary.TButton", background=[("active", "#2675e8")])
        style.configure("Danger.TButton", background="#512b36", foreground="#ffc1c9")
        style.map("Danger.TButton", background=[("active", "#713b48")])
        style.configure("Horizontal.TScale", background=self.PANEL, troughcolor="#344052")
        style.configure("TProgressbar", troughcolor=self.PANEL_2, background=self.BLUE, borderwidth=0)

    def _card(self, parent, **kwargs):
        return tk.Frame(parent, bg=self.PANEL, highlightthickness=1,
                        highlightbackground=self.BORDER, **kwargs)

    def _label(self, parent, text, size=10, color=None, bold=False):
        return tk.Label(parent, text=text, bg=parent.cget("bg"),
                        fg=color or self.TEXT,
                        font=("DejaVu Sans", size, "bold" if bold else "normal"))

    def _build_ui(self):
        outer = tk.Frame(self.root, bg=self.BG)
        outer.pack(fill="both", expand=True, padx=24, pady=20)

        header = tk.Frame(outer, bg=self.BG)
        header.pack(fill="x", pady=(0, 16))
        left = tk.Frame(header, bg=self.BG)
        left.pack(side="left", fill="x", expand=True)
        self._label(left, "GIGABYTE  /  LIGHTING", 9, self.BLUE, True).pack(anchor="w")
        self._label(left, "RGB Studio", 25, self.TEXT, True).pack(anchor="w", pady=(3, 1))
        self._label(left, "Keyboard color and brightness", 10, self.MUTED).pack(anchor="w")
        ttk.Button(header, text="Locate script", command=self.choose_controller).pack(side="right", anchor="n")

        status_card = self._card(outer)
        status_card.pack(fill="x", pady=(0, 14))
        status_row = tk.Frame(status_card, bg=self.PANEL)
        status_row.pack(fill="x", padx=15, pady=12)
        self._label(status_row, "KEYBOARD DEVICE", 9, self.MUTED, True).pack(side="left")
        self.status_label = tk.Label(status_row, textvariable=self.status, bg=self.PANEL,
                                     fg="#75d69a", font=("DejaVu Sans", 9, "bold"))
        self.status_label.pack(side="right")

        color_card = self._card(outer)
        color_card.pack(fill="both", expand=True, pady=(0, 14))
        color = tk.Frame(color_card, bg=self.PANEL)
        color.pack(fill="both", expand=True, padx=16, pady=15)

        top = tk.Frame(color, bg=self.PANEL)
        top.pack(fill="x", pady=(0, 10))
        self._label(top, "CHOOSE A COLOR", 9, self.MUTED, True).pack(side="left")
        self.color_hex = tk.Label(top, text=self.color.upper(), bg=self.PANEL_2,
                                   fg=self.TEXT, font=("DejaVu Sans Mono", 10, "bold"),
                                   padx=10, pady=5)
        self.color_hex.pack(side="right")

        picker_row = tk.Frame(color, bg=self.PANEL)
        picker_row.pack(fill="x")
        self.sv_canvas = tk.Canvas(picker_row, width=self._sv_width, height=self._sv_height,
                                  bg="#ffffff", highlightthickness=0, cursor="crosshair")
        self.sv_canvas.pack(side="left", anchor="n")
        self.sv_canvas.bind("<Button-1>", self._pick_sv)
        self.sv_canvas.bind("<B1-Motion>", self._pick_sv)

        hue_column = tk.Frame(picker_row, bg=self.PANEL)
        hue_column.pack(side="left", fill="y", padx=(13, 0))
        self.hue_canvas = tk.Canvas(hue_column, width=26, height=self._sv_height,
                                    bg=self.PANEL, highlightthickness=0, cursor="hand2")
        self.hue_canvas.pack(side="left")
        self.hue_canvas.bind("<Button-1>", self._pick_hue)
        self.hue_canvas.bind("<B1-Motion>", self._pick_hue)
        preview_column = tk.Frame(hue_column, bg=self.PANEL)
        preview_column.pack(side="left", fill="y", padx=(12, 0))
        self.preview = tk.Frame(preview_column, bg=self.color, width=72, height=72,
                                highlightthickness=1, highlightbackground="#566174")
        self.preview.pack(anchor="n")
        self.preview.pack_propagate(False)
        self._label(preview_column, "PREVIEW", 8, self.MUTED, True).pack(anchor="center", pady=(8, 0))
        self._label(color, "Drag inside the large color field; use the rainbow strip to change hue.",
                    9, self.MUTED).pack(anchor="w", pady=(11, 13))

        self._label(color, "QUICK PALETTE", 9, self.MUTED, True).pack(anchor="w", pady=(0, 9))
        palette = tk.Frame(color, bg=self.PANEL)
        palette.pack(fill="x")
        self.palette_items = []
        for i, (name, value) in enumerate(PRESETS):
            chip = tk.Canvas(palette, width=30, height=30, bg=self.PANEL,
                             highlightthickness=0, cursor="hand2")
            chip.create_oval(3, 3, 27, 27, fill=value, outline="#ffffff" if value == "#ffffff" else value, width=1)
            chip.bind("<Button-1>", lambda _e, c=value: self._set_color(c, update_hue=True))
            chip.bind("<Enter>", lambda _e, c=name: self.status.set(f"Palette: {c}"))
            chip.bind("<Leave>", self._status_idle)
            chip.grid(row=i // 9, column=i % 9, padx=(0, 9), pady=(0, 8), sticky="w")
            self.palette_items.append(chip)

        brightness_card = self._card(outer)
        brightness_card.pack(fill="x", pady=(0, 14))
        brightness = tk.Frame(brightness_card, bg=self.PANEL)
        brightness.pack(fill="x", padx=16, pady=14)
        brightness_top = tk.Frame(brightness, bg=self.PANEL)
        brightness_top.pack(fill="x")
        self._label(brightness_top, "BRIGHTNESS", 9, self.MUTED, True).pack(side="left")
        self.brightness_value = self._label(brightness_top, "100%", 16, self.TEXT, True)
        self.brightness_value.pack(side="right")
        self.scale = ttk.Scale(brightness, from_=0, to=100, orient="horizontal",
                               command=self._brightness_changed)
        self.scale.set(100)
        self.scale.pack(fill="x", pady=(13, 7))
        tick_row = tk.Frame(brightness, bg=self.PANEL)
        tick_row.pack(fill="x")
        for value in ("0%", "25%", "50%", "75%", "100%"):
            self._label(tick_row, value, 8, self.MUTED).pack(side="left", expand=True)

        actions = tk.Frame(outer, bg=self.BG)
        actions.pack(fill="x", pady=(0, 10))
        self.apply_button = ttk.Button(actions, text="Apply to keyboard", style="Primary.TButton", command=self.apply)
        self.apply_button.pack(side="left", fill="x", expand=True, padx=(0, 7))
        ttk.Button(actions, text="Turn off", style="Danger.TButton", command=self.turn_off).pack(side="left", padx=(7, 0))

        bottom = tk.Frame(outer, bg=self.BG)
        bottom.pack(fill="x")
        ttk.Button(bottom, text="Restore last color", command=lambda: self.run_controller(["restore"], "Restoring last color…", "restore")).pack(side="left")
        ttk.Button(bottom, text="Firmware / Fn+Space", command=self.enable_auto).pack(side="left", padx=8)
        ttk.Button(bottom, text="Set up access (once)", command=self.setup_permissions).pack(side="right")

        self._label(outer,
                    "Brightness is emulated by RGB scaling. Firmware mode lets Fn+Space control brightness,\n"
                    "but uses the color stored in the keyboard firmware.",
                    8, "#728095").pack(anchor="w", pady=(13, 0))
        self.progress = ttk.Progressbar(outer, mode="indeterminate")
        self.progress.pack(fill="x", pady=(9, 0))

    def _draw_sv(self):
        width, height = self._sv_width, self._sv_height
        photo = tk.PhotoImage(width=width, height=height)
        for y in range(height):
            value = 1.0 - y / max(1, height - 1)
            colors = []
            for x in range(width):
                saturation = x / max(1, width - 1)
                rgb = colorsys.hsv_to_rgb(self.hue, saturation, value)
                colors.append("#" + "".join(f"{round(channel * 255):02x}" for channel in rgb))
            photo.put("{" + " ".join(colors) + "}", to=(0, y))
        self._sv_photo = photo
        self.sv_canvas.delete("image")
        self.sv_canvas.create_image(0, 0, image=self._sv_photo, anchor="nw", tags="image")
        self._draw_marker()

    def _draw_hue(self):
        width, height = 26, self._sv_height
        photo = tk.PhotoImage(width=width, height=height)
        for y in range(height):
            rgb = colorsys.hsv_to_rgb(y / max(1, height - 1), 1.0, 1.0)
            color = "#" + "".join(f"{round(channel * 255):02x}" for channel in rgb)
            photo.put(color, to=(0, y, width, y + 1))
        self._hue_photo = photo
        self.hue_canvas.delete("all")
        self.hue_canvas.create_image(0, 0, image=self._hue_photo, anchor="nw")
        y = self.hue * (height - 1)
        self.hue_canvas.create_rectangle(0, y - 2, width, y + 2,
                                         outline="#ffffff", width=2)

    def _draw_marker(self):
        x = self.saturation * (self._sv_width - 1)
        y = (1.0 - self.value) * (self._sv_height - 1)
        self.sv_canvas.delete("marker")
        self.sv_canvas.create_oval(x - 7, y - 7, x + 7, y + 7,
                                   outline="#10131a", width=3, tags="marker")
        self.sv_canvas.create_oval(x - 5, y - 5, x + 5, y + 5,
                                   outline="#ffffff", width=2, tags="marker")

    def _pick_sv(self, event):
        self.saturation = min(1.0, max(0.0, event.x / (self._sv_width - 1)))
        self.value = 1.0 - min(1.0, max(0.0, event.y / (self._sv_height - 1)))
        self._draw_marker()
        self._update_color_from_hsv()

    def _pick_hue(self, event):
        self.hue = min(1.0, max(0.0, event.y / (self._sv_height - 1)))
        self._draw_sv()
        self._draw_hue()
        self._update_color_from_hsv()

    def _update_color_from_hsv(self):
        rgb = colorsys.hsv_to_rgb(self.hue, self.saturation, self.value)
        self.color = "#" + "".join(f"{round(channel * 255):02x}" for channel in rgb)
        self._update_preview()

    def _set_color(self, value: str, update_hue: bool = False):
        value = value.strip().lower()
        if not re.fullmatch(r"#[0-9a-f]{6}", value):
            return
        self.color = value
        r, g, b = (int(value[index:index + 2], 16) / 255 for index in (1, 3, 5))
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if update_hue or s > 0:
            self.hue = h
        self.saturation, self.value = s, v
        self._draw_sv()
        self._draw_hue()
        self._update_preview()

    def _update_preview(self):
        self.preview.configure(bg=self.color)
        self.color_hex.configure(text=self.color.upper())

    def _brightness_changed(self, raw):
        percent = int(float(raw) + 0.5)
        self.brightness.set(percent)
        self.brightness_value.configure(text=f"{percent}%")

    def _status_idle(self, _event=None):
        if not self.busy:
            self.status.set("Ready" if self.controller else "Controller not configured")

    def choose_controller(self):
        path = filedialog.askopenfilename(
            title="Select the gigabyte-kbd controller script",
            filetypes=[("gigabyte-kbd controller", "gigabyte-kbd"), ("Python files", "*.py"), ("All files", "*")],
            parent=self.root,
        )
        if not path:
            return
        valid, details = validate_controller(path)
        if not valid:
            messagebox.showerror(APP_NAME, f"This does not look like the working controller:\n\n{details}\n\nSelect the project's scripts/gigabyte-kbd file.", parent=self.root)
            return
        self.controller = str(Path(path).resolve())
        self.settings["controller_path"] = self.controller
        save_settings(self.settings)
        self.status.set("Controller saved")
        self.status_label.configure(fg="#75d69a")
        messagebox.showinfo(APP_NAME, "Controller verified and saved.\nThe application will remember this location next time.", parent=self.root)
        self.run_controller(["info"], "Checking keyboard…", "info")

    def run_controller(self, args: list[str], label: str, operation: str):
        if self.busy:
            return
        if not self.controller or not Path(self.controller).is_file():
            self.controller = None
            self.status.set("Controller location missing")
            self.choose_controller()
            return
        self.busy = True
        self.status.set(label)
        self.status_label.configure(fg="#f0c76b")
        self.progress.start(10)
        self.apply_button.configure(state="disabled")

        def worker():
            try:
                command = [sys.executable, self.controller, *args]
                result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=30, check=False)
                output = result.stdout.strip() or ("Operation completed." if result.returncode == 0 else "No output from controller.")
                self.results.put((operation, result.returncode == 0, output))
            except (OSError, subprocess.TimeoutExpired) as exc:
                self.results.put((operation, False, str(exc)))

        threading.Thread(target=worker, daemon=True).start()

    def setup_permissions(self):
        pkexec = shutil.which("pkexec")
        if not pkexec:
            self._show_manual_setup()
            return
        if self.busy:
            return
        self.busy = True
        self.status.set("Configuring device access…")
        self.status_label.configure(fg="#f0c76b")
        self.progress.start(10)
        self.apply_button.configure(state="disabled")

        def worker():
            try:
                command = [pkexec, sys.executable, str(Path(__file__).resolve()), "--install-permissions"]
                result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=90, check=False)
                self.results.put(("permissions", result.returncode == 0,
                                  result.stdout.strip() or f"Permission setup exited with status {result.returncode}."))
            except (OSError, subprocess.TimeoutExpired) as exc:
                self.results.put(("permissions", False, str(exc)))

        threading.Thread(target=worker, daemon=True).start()

    def _show_manual_setup(self):
        command = """getent group gigabyte-rgb >/dev/null || sudo groupadd --system gigabyte-rgb
sudo usermod -aG gigabyte-rgb "$USER"
printf '%s\\n' 'SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="0414", ATTRS{idProduct}=="8104", GROUP="gigabyte-rgb", MODE="0660"' | sudo tee /etc/udev/rules.d/99-gigabyte-rgb.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
"""
        window = tk.Toplevel(self.root)
        window.title("One-time permission setup")
        window.configure(bg=self.BG)
        window.transient(self.root)
        window.grab_set()
        frame = tk.Frame(window, bg=self.BG, padx=16, pady=16)
        frame.pack(fill="both", expand=True)
        self._label(frame, "Run this once in a terminal", 12, self.TEXT, True).pack(anchor="w", pady=(0, 8))
        text = tk.Text(frame, width=78, height=8, bg=self.PANEL, fg=self.TEXT,
                       insertbackground=self.TEXT, relief="flat", font=("DejaVu Sans Mono", 9), wrap="none")
        text.pack(fill="both", expand=True)
        text.insert("1.0", command)
        text.configure(state="disabled")
        row = tk.Frame(frame, bg=self.BG)
        row.pack(fill="x", pady=(10, 0))
        ttk.Button(row, text="Copy commands", command=lambda: self._copy_text(command)).pack(side="left")
        ttk.Button(row, text="Close", command=window.destroy).pack(side="right")
        self._label(frame, "Then log out and back in once. No password is needed for normal RGB changes after that.", 9, self.MUTED).pack(anchor="w", pady=(10, 0))

    def _copy_text(self, value):
        self.root.clipboard_clear()
        self.root.clipboard_append(value)
        self.status.set("Setup commands copied")

    def _poll_results(self):
        try:
            while True:
                operation, success, output = self.results.get_nowait()
                self.busy = False
                self.progress.stop()
                self.apply_button.configure(state="normal")
                if success:
                    self.status.set("Access ready — relogin once" if operation == "permissions" else "Connected · ready")
                    self.status_label.configure(fg="#75d69a")
                    if operation == "permissions":
                        messagebox.showinfo(APP_NAME, output, parent=self.root)
                    elif operation == "info":
                        self._show_info(output)
                else:
                    permission_problem = (
                        "Permission denied" in output
                        or "Operation not permitted" in output
                        or "PermissionError: [Errno 13]" in output
                    )
                    self.status.set("Access setup required" if permission_problem else "Operation failed")
                    self.status_label.configure(fg="#ff7d89")
                    if permission_problem:
                        device_match = re.search(r"Permission denied:\s*['\"]([^'\"]*hidraw\d+)['\"]", output)
                        device = device_match.group(1) if device_match else "/dev/hidraw device"
                        messagebox.showwarning(
                            APP_NAME,
                            f"Linux blocked access to {device}.\n\n"
                            "The keyboard was detected, but your account does not yet have permission to control its RGB.\n\n"
                            "1. Click ‘Set up access (once)’ below.\n"
                            "2. Approve the administrator prompt.\n"
                            "3. Log out of your desktop session completely, then log back in.\n"
                            "4. Start RGB Studio again.\n\n"
                            "This is a one-time setup; normal color and brightness changes will not ask for your password.",
                            parent=self.root,
                        )
                    else:
                        # The controller may print a Python traceback. Show it in a scrollable
                        # detail dialog rather than flooding the main UI with raw diagnostics.
                        messagebox.showerror(APP_NAME, output[-2500:], parent=self.root)
        except queue.Empty:
            pass
        self.root.after(100, self._poll_results)

    def _show_info(self, output):
        # Keep the status line compact; full diagnostic output remains available in a dialog.
        if output:
            self.status.set("Keyboard detected · LampArray")
            self.status_label.configure(fg="#75d69a")

    def apply(self):
        intensity = round(self.brightness.get() * 255 / 100)
        self.run_controller(["color", self.color[1:], "--intensity", str(intensity)],
                            f"Applying {self.color.upper()} at {self.brightness.get()}%…", "apply")

    def turn_off(self):
        self.run_controller(["off"], "Turning keyboard lighting off…", "off")

    def enable_auto(self):
        messagebox.showinfo(
            APP_NAME,
            "Firmware mode hands lighting control back to the keyboard. Fn+Space can cycle brightness, "
            "but it uses the color stored in the keyboard firmware, not the color selected here.",
            parent=self.root,
        )
        self.run_controller(["auto"], "Enabling firmware mode…", "auto")


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--install-permissions":
        return install_permissions()
    root = tk.Tk()
    RGBApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
