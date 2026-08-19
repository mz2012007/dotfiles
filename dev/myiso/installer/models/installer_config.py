"""Installer configuration model."""
from dataclasses import dataclass, field
from pathlib import Path
import configparser

@dataclass
class InstallerConfig:
    hostname: str = "myiso"
    username: str = "user"
    timezone: str = "UTC"
    locale: str = "en_US.UTF-8"
    keyboard: str = "us"
    filesystem: str = "ext4"
    kernel: str = "linux"
    profile: str = "minimal"
    bootloader: str = "grub"
    repo_url: str = "https://repo-default.voidlinux.org/current"
    arch: str = "x86_64"
    target_disk: str = ""
    mount_root: str = "/mnt/myiso"

    @classmethod
    def from_file(cls, path: Path = Path("config/installer.conf")) -> "InstallerConfig":
        config = configparser.ConfigParser()
        config.read(path)
        section = config["installer"] if config.has_section("installer") else {}
        return cls(
            hostname=section.get("hostname", cls.hostname),
            username=section.get("username", cls.username),
            timezone=section.get("timezone", cls.timezone),
            locale=section.get("locale", cls.locale),
            keyboard=section.get("keyboard", cls.keyboard),
            filesystem=section.get("filesystem", cls.filesystem),
            kernel=section.get("kernel", cls.kernel),
            profile=section.get("profile", cls.profile),
            bootloader=section.get("bootloader", cls.bootloader),
            repo_url=section.get("repo_url", cls.repo_url),
            arch=section.get("arch", cls.arch),
        )
