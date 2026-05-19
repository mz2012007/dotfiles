from dataclasses import dataclass
from typing import Optional
import os
import re
import socket
import subprocess
import urllib.error
import urllib.parse
import urllib.request

def _has_active_interface():
    try:
        return subprocess.call(
            "ip link show | grep -q 'state UP'",
            shell=True
        ) == 0
    except Exception:
        return False


def _dns_working(test_domain="google.com"):
    try:
        socket.gethostbyname(test_domain)
        return True
    except socket.gaierror:
        return False


def _internet_working():
    try:
        socket.create_connection(("1.1.1.1", 53), timeout=2)
        return True
    except OSError:
        return False


def check_network_status():
    interface = _has_active_interface()
    dns = _dns_working()
    internet = _internet_working()

    return {
        "interface_up": interface,
        "dns_ok": dns,
        "internet_ok": internet,
        "status": interface and dns and internet,
    }


@dataclass
class URLMeta:
    url: str
    final_url: Optional[str] = None
    is_valid: bool = False
    status: Optional[int] = None
    content_type: Optional[str] = None
    size: Optional[int] = None
    filename: Optional[str] = None
    error: Optional[str] = None


def _extract_filename(url, headers):
    cd = headers.get("Content-Disposition")
    if cd:
        match = re.search(r'filename="?([^";]+)"?', cd)
        if match:
            return match.group(1)

    path = urllib.parse.urlparse(url).path
    name = os.path.basename(path)
    return name if name else "index.html"


def _extract_size(headers):
    cl = headers.get("Content-Length")
    try:
        return int(cl) if cl else None
    except ValueError:
        pass

    cr = headers.get("Content-Range")
    if cr and "/" in cr:
        try:
            return int(cr.split("/")[-1])
        except ValueError:
            pass

    return None


def inspect_url(url: str, timeout=10) -> URLMeta:

    parsed = urllib.parse.urlparse(url)

    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return URLMeta(url=url, error="invalid url")

    req = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": "Mozilla/5.0"}
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            headers = r.headers

            return URLMeta(
                url=url,
                final_url=r.url,
                is_valid=200 <= r.status < 400,
                status=r.status,
                content_type=headers.get("Content-Type"),
                size=_extract_size(headers),
                filename=_extract_filename(r.url, headers),
            )

    except urllib.error.HTTPError as e:
        return URLMeta(
            url=url,
            status=e.code,
            is_valid=False,
            error=f"HTTPError: {e.reason}",
        )

    except urllib.error.URLError as e:
        return URLMeta(
            url=url,
            is_valid=False,
            error=f"URLError: {e.reason}",
        )

    except Exception as e:
        return URLMeta(
            url=url,
            is_valid=False,
            error=str(e),
        )

@dataclass
class ResolveResult:
    url: str
    name: Optional[str]
    size: Optional[int]
    status: Optional[int]
    is_valid: bool
    error: Optional[str]
    network: dict

def resolve_url_v2(url: str) -> ResolveResult:

    net = check_network_status()

    if not net["status"]:
        return ResolveResult(
            url=url,
            name=None,
            size=None,
            status=None,
            is_valid=False,
            error="network unavailable",
            network=net
        )

    meta = inspect_url(url)

    return ResolveResult(
        url=meta.final_url or url,
        name=meta.filename,
        size=meta.size,
        status=meta.status,
        is_valid=meta.is_valid,
        error=meta.error,
        network=net,
    )
