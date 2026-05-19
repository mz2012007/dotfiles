from dataclasses import dataclass
from typing import Optional

@dataclass
class Package:
    name: str
    version: str
    filename: str
    sha256: str
    size: Optional[int] = None
    description: str = None
    status: Optional[str] = None
    installed_size: Optional[int] = None
