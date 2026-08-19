"""Persistent and live logging."""
import logging
from datetime import datetime
from pathlib import Path

class InstallerLogger:
    def __init__(self, log_dir: Path = Path("logs")):
        self.log_dir = log_dir
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.log_file = self.log_dir / f"installer-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
        self._setup_logger()

    def _setup_logger(self):
        self.logger = logging.getLogger("myiso")
        self.logger.setLevel(logging.DEBUG)
        formatter = logging.Formatter(
            "%(asctime)s [%(levelname)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
        fh = logging.FileHandler(self.log_file, encoding="utf-8")
        fh.setFormatter(formatter)
        self.logger.addHandler(fh)

    def info(self, msg: str):
        self.logger.info(msg)

    def error(self, msg: str):
        self.logger.error(msg)

    def debug(self, msg: str):
        self.logger.debug(msg)

    @property
    def path(self) -> Path:
        return self.log_file
