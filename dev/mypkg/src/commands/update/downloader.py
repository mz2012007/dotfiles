import os
import time
import requests

from lib.logger import log
from lib.utils import format_size
from lib.network import resolve_url_v2


SESSION = requests.Session()
CHUNK_SIZE = 1024


class DownloadError(Exception):
    pass


def download(url: str, dest: str, retries: int = 2):

    os.makedirs(os.path.dirname(dest), exist_ok=True)

    # resolve
    info = resolve_url_v2(url)

    # network check
    if not info.network["status"]:
        log.error(
            ("network unavailable ", log.RED),
            ("interface / dns / internet failed", log.YELLOW)
        )
        return None

    # url check
    if info.error:
        log.error(
            ("url error ", log.RED),
            (info.error, log.YELLOW)
        )
        return None

    part_file = dest + ".part"

    for attempt in range(retries + 1):

        try:
            start = time.time()
            downloaded = 0

            log.process(
                ("download ", log.CYAN),
                (info.name, log.YELLOW),
                (" | attempt ", log.BOLD),
                (str(attempt + 1), log.MAGENTA)
            )

            with SESSION.get(
                info.url,
                stream=True,
                timeout=20
            ) as r:

                r.raise_for_status()

                total = info.size or int(
                    r.headers.get("content-length", 0)
                )

                with open(part_file, "wb") as f:

                    for chunk in r.iter_content(CHUNK_SIZE):

                        if not chunk:
                            continue

                        f.write(chunk)
                        downloaded += len(chunk)

                        elapsed = time.time() - start

                        speed = (
                            downloaded / elapsed 
                            if elapsed > 0 else 0
                        )

                        percent = (
                            downloaded / total * 100
                            if total else 0
                        )

                        bar_len = 30
                        filled = int(bar_len * percent / 100)

                        bar = "█" * filled + "░" * (bar_len - filled)

                        print(
                            f"\r{log.CYAN}[{bar}]{log.RESET} "
                            f"{percent:5.1f}% "
                            f"{format_size(downloaded)} / "
                            f"{log.BLUE}{format_size(total)}{log.RESET} "
                            f"| {log.GREEN}{format_size(speed)} {log.RESET}",
                            end="",
                            flush=True
                        )

            os.replace(part_file, dest)

            print()

            log.success(
                ("saved ", log.GREEN),
                (dest, log.CYAN)
            )

            return dest

        except requests.exceptions.ConnectionError:
            log.error(("network error ", log.RED), ("dns / connection failed", log.YELLOW))

        except requests.exceptions.Timeout:
            log.error(("timeout ", log.RED), ("retrying...", log.YELLOW))

        except requests.exceptions.HTTPError as e:
            log.error(("HTTP error ", log.RED), (str(e), log.YELLOW))
            break

        except Exception as e:
            log.error(("unexpected error ", log.RED), (str(e), log.YELLOW))
            break

        time.sleep(1)

    raise DownloadError(f"Failed to download {url}")
