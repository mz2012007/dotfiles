import time
import requests

from lib.logger import log
from lib.utils import format_size

CHUNK_SIZE = 1024  # 1KB


def download(url: str, dest: str):
    session = requests.Session()

    start = time.time()
    downloaded = 0

    with session.get(url, stream=True, timeout=20) as r:
        r.raise_for_status()

        total = int(r.headers.get("content-length", 0))

        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=CHUNK_SIZE):
                if not chunk:
                    continue

                f.write(chunk)
                downloaded += len(chunk)


                percent = (downloaded / total * 100) if total else 0
                elapsed = time.time() - start

                speed = (
                    downloaded / elapsed / (1024 * 1024)
                    if elapsed > 0 else 0
                )

                bar_len = 30
                filled = int(bar_len * percent / 100)

                bar = "█" * filled + "░" * (bar_len - filled)

#                size_mb = downloaded / (1024 * 1024)
#                total_mb = total / (1024 * 1024) if total else 0
                size_mb = format_size(downloaded)
                total_mb = format_size(total) if total else 0

                print(
                    f"\r{log.CYAN}[{bar}]{log.RESET} "
                    f"{percent:0.2f}% "
                    f"{size_mb} / {log.BLUE}{total_mb} "
                    f"| {log.GREEN}{speed:5.2f} MB/s{log.RESET}",
                    end="",
                    flush=True
                )


    print()

    log.success(("saved ", log.GREEN), (dest, log.CYAN))

    return dest


