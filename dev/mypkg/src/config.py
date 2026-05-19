import configparser
from pathlib import Path

def load_config():
    config_path = Path(__file__).resolve().parents[2] / "mypkg/config.ini"

    config = configparser.ConfigParser()
    read_ok = config.read(config_path)

    if not read_ok:
        raise FileNotFoundError(f"config.ini not found at {config_path}")

    return config
