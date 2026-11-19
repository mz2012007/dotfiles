"""Configuration and default paths.

The defaults mirror the original ``install.sh`` for mz2012007/dotfiles, but
they are conservative: nothing is written to the system unless a task that
does so is explicitly selected.
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field, replace
from pathlib import Path

from .errors import ConfigError
from .util import expand_path, is_safe_name

DEFAULT_STATE_DIR = "~/.local/state/voidsetup"
DEFAULT_CONFIG_FILE = "~/.config/voidsetup/config.toml"

DEFAULT_REPOS = (
    (
        "sofijacom-void-repository",
        "https://github.com/sofijacom/void-package/releases/latest/download/",
    ),
    (
        "my-repo",
        "https://raw.githubusercontent.com/mz2012007/void-xbps/refs/heads/main/x86_64",
    ),
)

DEFAULT_SERVICES = (
    "NetworkManager",
    "agetty-tty1",
    "agetty-tty2",
    "dbus",
    "earlyoom",
    "chronyd",
    "fake-hwclock",
    "lightdm",
    "preload",
    "zramen",
    "udevd",
    "elogind",
    "fcron",
    "ufw",
    "rsyslogd",
)

DEFAULT_GROUPS = (
    "wheel",
    "adm",
    "audio",
    "video",
    "input",
    "network",
    "storage",
    "lp",
    "scanner",
    "optical",
    "kvm",
    "plugdev",
    "bluetooth",
    "mpd",
    "pulse",
    "pulse-access",
    "usbmon",
    "dialout",
    "cdrom",
    "floppy",
    "rtkit",
)

DEFAULT_USER_DIRS = (
    "~/Desktop",
    "~/Downloads",
    "~/Pictures/screenshots",
    "~/Music/playlists",
    "~/Music/songs",
    "~/.config/tmux/plugins",
    "~/.config/tmux/templates",
    "~/.config/mpd",
    "~/.ssh",
)

DEFAULT_ROOT_DIRS = (
    "/etc/modprobe.d",
    "/etc/X11/xorg.conf.d",
    "/etc/xdg/autostart",
    "/etc/polkit-1/rules.d",
    "/etc/lightdm",
    "/boot/grub/themes",
    "/usr/share/fonts",
    "/usr/share/themes",
    "/usr/share/plymouth/themes",
    "/usr/share/xsessions",
    "/mnt/srv/docker/comp",
    "/mnt/srv/docker/cont/n8n/data",
    "/mnt/srv/docker/cont/nginx",
    "/mnt/srv/docker/cont/heimdall/config",
    "/mnt/srv/docker/cont/syncthing/config",
    "/mnt/srv/data",
    "/mnt/srv/data/media",
    "/mnt/srv/docker/cont/npm/data",
    "/mnt/srv/docker/cont/npm/letsencrypt",
    "/mnt/srv/docker/cont/pyload",
    "/mnt/srv/downloads/pyload",
    "/mnt/srv/docker/cont/jellyfin/config",
    "/mnt/srv/docker/cont/nextcloud/db",
    "/mnt/srv/docker/cont/nextcloud/db-backup",
    "/mnt/srv/docker/cont/nextcloud/html",
    "/mnt/srv/docker/cont/portainer",
)


@dataclass(frozen=True, slots=True)
class Repo:
    name: str
    url: str

    def __post_init__(self) -> None:
        if not is_safe_name(self.name):
            raise ConfigError(f"invalid repository name: {self.name!r}")
        if not self.url.startswith(("https://", "http://")):
            raise ConfigError(f"repository URL must be http(s): {self.url!r}")
        if any(char.isspace() for char in self.url):
            raise ConfigError(f"repository URL contains whitespace: {self.url!r}")

    @property
    def config_path(self) -> Path:
        return Path("/etc/xbps.d") / f"{self.name}.conf"

    @property
    def content(self) -> str:
        return f"repository={self.url}\n"


@dataclass(frozen=True, slots=True)
class RsyncPair:
    """One config copy.

    ``src`` is relative to the dotfiles directory. When ``contents`` is true
    the contents of a source directory are copied (``src/`` -> ``dest/``),
    matching the trailing-slash behaviour of the original script.
    """

    src: str
    dest: str
    contents: bool = False
    root_owned: bool = False


DEFAULT_RSYNC_PAIRS = (
    RsyncPair("my-config/myroot/etc/modprobe.d/blacklist.conf", "/etc/modprobe.d/", root_owned=True),
    RsyncPair("my-config/myroot/etc/X11/xorg.conf.d", "/etc/X11/xorg.conf.d/", contents=True, root_owned=True),
    RsyncPair("my-config/myroot/etc/xdg/autostart/nm-applet.desktop", "/etc/xdg/autostart/", root_owned=True),
    RsyncPair("my-config/myroot/etc/polkit-1/rules.d/my-safe.rules", "/etc/polkit-1/rules.d/", root_owned=True),
    RsyncPair("my-config/myroot/etc/lightdm/lightdm.conf", "/etc/lightdm/", root_owned=True),
    RsyncPair("my-config/myroot/etc/lightdm/lightdm-gtk-greeter.conf", "/etc/lightdm/", root_owned=True),
    RsyncPair("my-config/myroot/usr/share/fonts", "/usr/share/fonts/", contents=True, root_owned=True),
    RsyncPair("my-config/myroot/myhome/.config/tmux/tmux.conf", "~/.config/tmux/"),
    RsyncPair("my-config/myroot/myhome/.config/tmux/tmux.conf.pack2", "~/.config/tmux/"),
    RsyncPair("my-config/myroot/myhome/.config/tmux/templates", "~/.config/tmux/templates/", contents=True),
    RsyncPair(".config/fish", "/root/.config/", contents=True, root_owned=True),
    RsyncPair("fcrontab", "/var/spool/fcron/", contents=True, root_owned=True),
    RsyncPair("my-config/myroot/usr/share/themes", "/usr/share/themes/", contents=True, root_owned=True),
    RsyncPair("my-config/myroot/etc/default/grub", "/etc/default/grub", root_owned=True),
    RsyncPair("my-config/myroot/boot/grub/themes", "/boot/grub/themes/", contents=True, root_owned=True),
    RsyncPair("my-config/docker-compose.yml", "/mnt/srv/docker/comp/docker-compose.yml", root_owned=True),
    RsyncPair("my-config/myroot/etc/hosts", "/etc/hosts", root_owned=True),
    RsyncPair("my-config/myroot/etc/hostname", "/etc/hostname", root_owned=True),
    RsyncPair("my-config/myroot/usr/share/plymouth/themes", "/usr/share/plymouth/themes/", contents=True, root_owned=True),
    RsyncPair("my-config/myroot/usr/share/xsessions", "/usr/share/xsessions/", contents=True, root_owned=True),
    RsyncPair("my-config/myroot/myhome/.ssh/agent", "~/.ssh/agent/", contents=True),
    RsyncPair("my-config/myroot/myhome/.ssh/config", "~/.ssh/config"),
    RsyncPair("my-config/myroot/myhome/.ssh/known_hosts", "~/.ssh/known_hosts"),
)


def _default_dotfiles() -> Path:
    return Path.home() / "dotfiles"


def _default_state_dir() -> Path:
    return Path.home() / ".local" / "state" / "voidsetup"


@dataclass(frozen=True, slots=True)
class Settings:
    dotfiles: Path = field(default_factory=_default_dotfiles)
    state_dir: Path = field(default_factory=_default_state_dir)
    config_file: Path = field(default_factory=lambda: Path.home() / ".config" / "voidsetup" / "config.toml")
    packages_file: Path | None = None
    timezone: str = "Africa/Cairo"
    repos: tuple[Repo, ...] = tuple(Repo(*item) for item in DEFAULT_REPOS)
    services: tuple[str, ...] = DEFAULT_SERVICES
    groups: tuple[str, ...] = DEFAULT_GROUPS
    user_dirs: tuple[str, ...] = DEFAULT_USER_DIRS
    root_dirs: tuple[str, ...] = DEFAULT_ROOT_DIRS
    rsync_pairs: tuple[RsyncPair, ...] = DEFAULT_RSYNC_PAIRS
    resolv_source: str = "my-config/myroot/etc/resolv.conf"
    resolv_target: Path = Path("/etc/resolv.conf")
    resolv_immutable: bool = False
    sysctl_file: Path = Path("/etc/sysctl.d/99-voidsetup.conf")
    power_polkit: bool = True
    admin_group: str = "wheel"
    dwm_dir: str = ".config/dwm/dwm"
    dwmblocks_dir: str = ".config/dwm/dwmblocks"
    tpm_dir: str = ".config/tmux/plugins/tpm"
    tpm_repo: str = "https://github.com/tmux-plugins/tpm"
    mpv_dir: str = ".config/mpv"
    mpv_repo: str = "https://github.com/mz2012007/mpv.git"
    local_pkg_dir: str = "pkg-xbps"
    plymouth_theme: str | None = None
    tui_theme: str = "textual-dark"
    log_keep: int = 20

    @property
    def packages_path(self) -> Path:
        return self.packages_file or (self.dotfiles / "packages.sh")

    @property
    def state_file(self) -> Path:
        return self.state_dir / "state.json"

    @property
    def logs_dir(self) -> Path:
        return self.state_dir / "logs"

    def with_overrides(self, **changes: object) -> "Settings":
        return replace(self, **changes)

    def resolved(self, value: str | Path) -> Path:
        return expand_path(value)


def _as_str_tuple(value: object, *, name: str) -> tuple[str, ...]:
    if isinstance(value, str):
        return tuple(item.strip() for item in value.split(",") if item.strip())
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return tuple(item.strip() for item in value if item.strip())
    raise ConfigError(f"{name} must be a list of strings")


def _as_bool(value: object, *, name: str) -> bool:
    if not isinstance(value, bool):
        raise ConfigError(f"{name} must be true or false")
    return value


def _as_int(value: object, *, name: str) -> int:
    # bool is a subclass of int; reject it explicitly.
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigError(f"{name} must be an integer")
    return value


def _as_str(value: object, *, name: str) -> str:
    if not isinstance(value, str):
        raise ConfigError(f"{name} must be a string")
    return value


def _path_value(data: dict[str, object], key: str, default: str) -> Path:
    raw = data.get(key, default)
    if not isinstance(raw, str):
        raise ConfigError(f"{key} must be a path string")
    return expand_path(raw)


def _parse_repos(value: object) -> tuple[Repo, ...]:
    if not isinstance(value, list):
        raise ConfigError("repos must be an array of tables")
    repos: list[Repo] = []
    for item in value:
        if not isinstance(item, dict):
            raise ConfigError("each repo must be a table with name and url")
        name = item.get("name")
        url = item.get("url")
        if not isinstance(name, str) or not isinstance(url, str):
            raise ConfigError("each repo requires string name and url")
        repos.append(Repo(name, url))
    return tuple(repos)


def load_settings(config_path: Path | None = None) -> Settings:
    """Load settings from TOML and environment overrides.

    Environment variables:
      * ``VOIDSETUP_CONFIG`` - config file path
      * ``VOIDSETUP_DOTFILES`` - dotfiles directory
      * ``VOIDSETUP_STATE_DIR`` - state/log directory
    """

    env_config = os.environ.get("VOIDSETUP_CONFIG")
    path = expand_path(config_path or env_config or DEFAULT_CONFIG_FILE)
    if config_path is not None and not path.exists():
        raise ConfigError(f"config file not found: {path}")

    data: dict[str, object] = {}
    if path.exists():
        try:
            data = tomllib.loads(path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise ConfigError(f"cannot read config file {path}: {exc}") from exc
        except tomllib.TOMLDecodeError as exc:
            raise ConfigError(f"invalid TOML in {path}: {exc}") from exc

    dotfiles_env = os.environ.get("VOIDSETUP_DOTFILES")
    state_env = os.environ.get("VOIDSETUP_STATE_DIR")
    dotfiles = expand_path(dotfiles_env) if dotfiles_env else _path_value(data, "dotfiles", "~/dotfiles")
    state_dir = expand_path(state_env) if state_env else _path_value(data, "state_dir", DEFAULT_STATE_DIR)

    kwargs: dict[str, object] = {
        "dotfiles": dotfiles,
        "state_dir": state_dir,
        "config_file": path,
    }
    if "timezone" in data:
        kwargs["timezone"] = _as_str(data["timezone"], name="timezone")
    if "repos" in data:
        kwargs["repos"] = _parse_repos(data["repos"])
    if "services" in data:
        kwargs["services"] = _as_str_tuple(data["services"], name="services")
    if "groups" in data:
        kwargs["groups"] = _as_str_tuple(data["groups"], name="groups")
    if "user_dirs" in data:
        kwargs["user_dirs"] = _as_str_tuple(data["user_dirs"], name="user_dirs")
    if "root_dirs" in data:
        kwargs["root_dirs"] = _as_str_tuple(data["root_dirs"], name="root_dirs")
    if "resolv_source" in data:
        kwargs["resolv_source"] = _as_str(data["resolv_source"], name="resolv_source")
    if "resolv_target" in data:
        kwargs["resolv_target"] = expand_path(
            _as_str(data["resolv_target"], name="resolv_target")
        )
    if "resolv_immutable" in data:
        kwargs["resolv_immutable"] = _as_bool(
            data["resolv_immutable"], name="resolv_immutable"
        )
    if "sysctl_file" in data:
        kwargs["sysctl_file"] = expand_path(
            _as_str(data["sysctl_file"], name="sysctl_file")
        )
    if "power_polkit" in data:
        kwargs["power_polkit"] = _as_bool(data["power_polkit"], name="power_polkit")
    if "admin_group" in data:
        kwargs["admin_group"] = _as_str(data["admin_group"], name="admin_group")
    if "plymouth_theme" in data:
        value = data["plymouth_theme"]
        if value is not None and not isinstance(value, str):
            raise ConfigError("plymouth_theme must be a string or empty")
        kwargs["plymouth_theme"] = value or None
    if "tui_theme" in data:
        kwargs["tui_theme"] = _as_str(data["tui_theme"], name="tui_theme")
    if "log_keep" in data:
        kwargs["log_keep"] = _as_int(data["log_keep"], name="log_keep")

    settings = Settings(**kwargs)  # type: ignore[arg-type]
    _validate_settings(settings)
    return settings


def _validate_settings(settings: Settings) -> None:
    if not settings.timezone:
        raise ConfigError("timezone must not be empty")
    if "/" not in settings.timezone and settings.timezone != "UTC":
        raise ConfigError(f"invalid timezone: {settings.timezone!r}")
    if any(part in ("", ".", "..") for part in settings.timezone.split("/")):
        raise ConfigError(f"invalid timezone: {settings.timezone!r}")
    for key, path in (
        ("resolv_target", settings.resolv_target),
        ("sysctl_file", settings.sysctl_file),
    ):
        if not path.is_absolute():
            raise ConfigError(f"{key} must be an absolute path")
    source = Path(settings.resolv_source)
    if source.is_absolute() or ".." in source.parts:
        raise ConfigError("resolv_source must be a relative path inside dotfiles")
    for name in settings.services:
        if not is_safe_name(name):
            raise ConfigError(f"invalid service name: {name!r}")
    for name in settings.groups:
        if not is_safe_name(name):
            raise ConfigError(f"invalid group name: {name!r}")
    if not is_safe_name(settings.admin_group):
        raise ConfigError(f"invalid admin group: {settings.admin_group!r}")
    if not settings.tui_theme or not is_safe_name(settings.tui_theme):
        raise ConfigError(f"invalid tui_theme: {settings.tui_theme!r}")
    if settings.log_keep < 1:
        raise ConfigError("log_keep must be >= 1")


def default_config_toml() -> str:
    """A commented sample configuration."""

    return """\
# voidsetup configuration
# Copy to ~/.config/voidsetup/config.toml and edit as needed.

dotfiles = "~/dotfiles"
state_dir = "~/.local/state/voidsetup"
timezone = "Africa/Cairo"

# Enable only when you really want a static resolv.conf; keeping it immutable
# prevents NetworkManager from updating DNS.
resolv_immutable = false

# Installs a narrow polkit rule so admin-group users can reboot/power off
# without SUID binaries. Set to false if you manage polkit yourself.
power_polkit = true
admin_group = "wheel"

# Plymouth theme. Empty means "leave the current theme alone".
plymouth_theme = ""

# Colour scheme for the Textual TUI. Change it with Ctrl+T in the TUI.
tui_theme = "textual-dark"

# services = ["NetworkManager", "dbus", "elogind", "lightdm"]
# groups = ["wheel", "audio", "video", "input", "network", "storage"]

[[repos]]
name = "sofijacom-void-repository"
url = "https://github.com/sofijacom/void-package/releases/latest/download/"

[[repos]]
name = "my-repo"
url = "https://raw.githubusercontent.com/mz2012007/void-xbps/refs/heads/main/x86_64"
"""


def save_tui_theme(path: Path, theme: str) -> None:
    """Persist the chosen TUI colour scheme without rewriting other settings.

    The TOML file is edited line-by-line on purpose: a full serialisation would
    drop comments and reorder user configuration.
    """

    if not is_safe_name(theme):
        raise ConfigError(f"invalid tui_theme: {theme!r}")
    path = Path(path)
    try:
        lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
    except OSError as exc:
        raise ConfigError(f"cannot read config file {path}: {exc}") from exc

    assignment = f'tui_theme = "{theme}"'
    for index, line in enumerate(lines):
        if line.lstrip().startswith("tui_theme") and "=" in line:
            lines[index] = assignment
            break
    else:
        lines.append(assignment)

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    except OSError as exc:
        raise ConfigError(f"cannot write config file {path}: {exc}") from exc
