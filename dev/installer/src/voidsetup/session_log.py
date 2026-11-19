"""Session logging that can feed both a TUI and a plain terminal."""

from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Callable

from .util import prune_logs


class LogLevel(str, Enum):
    DEBUG = "debug"
    INFO = "info"
    WARN = "warn"
    ERROR = "error"
    COMMAND = "command"
    OUTPUT = "output"


@dataclass(frozen=True, slots=True)
class LogRecord:
    level: LogLevel
    message: str
    timestamp: datetime


LogSink = Callable[[LogRecord], None]


class SessionLogger:
    """Write a human-readable log file and optionally mirror records to a sink."""

    def __init__(
        self,
        path: Path | None = None,
        *,
        sink: LogSink | None = None,
        keep_logs: int = 20,
    ) -> None:
        self.path = Path(path) if path else None
        self._sink = sink
        self._lock = threading.Lock()
        self._closed = False
        self._handle = None
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            prune_logs(self.path.parent, keep_logs)
            self._handle = self.path.open("a", encoding="utf-8")

    def emit(self, level: LogLevel, message: str) -> None:
        record = LogRecord(level=level, message=message, timestamp=datetime.now())
        with self._lock:
            if self._handle is not None and not self._closed:
                stamp = record.timestamp.strftime("%Y-%m-%d %H:%M:%S")
                self._handle.write(f"{stamp} {level.value.upper():7} {message}\n")
                self._handle.flush()
        if self._sink is not None:
            self._sink(record)

    def debug(self, message: str) -> None:
        self.emit(LogLevel.DEBUG, message)

    def info(self, message: str) -> None:
        self.emit(LogLevel.INFO, message)

    def warn(self, message: str) -> None:
        self.emit(LogLevel.WARN, message)

    def error(self, message: str) -> None:
        self.emit(LogLevel.ERROR, message)

    def command(self, message: str) -> None:
        self.emit(LogLevel.COMMAND, message)

    def output(self, message: str) -> None:
        self.emit(LogLevel.OUTPUT, message)

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            if self._handle is not None:
                self._handle.close()
                self._handle = None

    def __enter__(self) -> "SessionLogger":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()
