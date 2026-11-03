from installer.models.installer_config import InstallerConfig
from pathlib import Path

def test_config_load():
    config = InstallerConfig.from_file(Path("config/installer.conf"))
    assert config.hostname == "myiso"
    assert config.profile == "minimal"

