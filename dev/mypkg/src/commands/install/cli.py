# commands/install/cli.py

from lib.logger import log
from lib.utils import format_size, get_free_space

def show_info1(info):

    log.print(("====================", log.CYAN))
    log.print(("PACKAGE INFO", log.BOLD))
    log.print(("====================\n", log.CYAN))

    log.print(("Name: ", log.BOLD), (info.name, log.YELLOW))
    log.print(("Version: ", log.BOLD), (info.version, log.CYAN))
    if info.size:
        mb = format_size(info.size)
        log.print(("Size to download: ", log.BOLD), (f"{mb}", log.GREEN))

    if info.installed_size:
        mb = format_size(info.installed_size)
        free = format_size(get_free_space()-info.installed_size)
        log.print(("Size required on disk: ", log.BOLD), (f"{mb}", log.GREEN))
        log.print(("Space available on disk: ", log.BOLD), (f"{free}", log.GREEN))

    if info.status:
        log.print(("Status: ", log.BOLD), (str(info.status), log.MAGENTA))

    log.print(("====================\n", log.CYAN))


def ask_confirm():
    while True:
        ans = input("Proceed? [y/n]: ").strip().lower()

        if ans in ("y", "yes"):
            return True

        if ans in ("n", "no"):
            return False



def render_transaction(rows, summary=None):

    headers = (
        "Name",
        "Action",
        "Version",
        "New version",
        "Download size"
    )

    # normalize rows (prevent None / type issues)
    clean = []

    for r in rows:

        clean.append((
            str(r["name"]),
            str(r["action"]),
            str(r["old_version"]),
            str(r["new_version"]),
            format_size(r["size"]) if r.get("size") else "-"
        ))

    # column widths
    widths = []

    for i in range(len(headers)):

        w = len(headers[i])

        for row in clean:

            w = max(w, len(str(row[i])))

        widths.append(w)

    # header
    for i, h in enumerate(headers):

        log.print(
            (f"{h:<{widths[i]}}", log.BOLD),
            ("  ", None),
        )

    print()

    # separator
    total_width = sum(widths) + (len(widths) * 2)

    print("-" * total_width)

    # rows
    for row in clean:

        log.print(
            (f"{row[0]:<{widths[0]}}", log.CYAN),
            ("  ", None),

            (f"{row[1]:<{widths[1]}}", log.YELLOW),
            ("  ", None),

            (f"{row[2]:<{widths[2]}}", log.WHITE),
            ("  ", None),

            (f"{row[3]:<{widths[3]}}", log.GREEN),
            ("  ", None),

            (f"{row[4]:<{widths[4]}}", log.MAGENTA),
        )

    print()

    # summary block (xbps style)
    if summary:

        log.print(
            (f"Size to download:        ", log.BOLD),
            (summary.get("download", "-"), log.CYAN)
        )

        log.print(
            (f"Size required on disk:   ", log.BOLD),
            (summary.get("disk", "-"), log.CYAN)
        )

        log.print(
            (f"Space available on disk:  ", log.BOLD),
            (summary.get("free", "-"), log.GREEN)
        )

        print()

from lib.logger import log
from lib.utils import format_size


def show_info(info):

    headers = (
        "Name",
        "Action",
        "Version",
        "New version",
        "Download size"
    )

    action = getattr(info, "status", "install")
    old_version = getattr(info, "installed_version", "-")
    new_version = getattr(info, "version", "-")

    size = format_size(info.size) if getattr(info, "size", None) else "-"

    row = (
        info.name,
        action,
        old_version,
        new_version,
        size
    )

    widths = [
        max(len(headers[i]), len(str(row[i])))
        for i in range(len(headers))
    ]

    # header
    for i, h in enumerate(headers):
        log.print(
            (f"{h:<{widths[i]}}", log.BOLD),
            ("  ", None),
            end=""
        )
    print()

    print("-" * (sum(widths) + (len(widths) * 2)))

    colors = [
        log.CYAN,
        log.YELLOW,
        log.WHITE,
        log.GREEN,
        log.MAGENTA
    ]

    # row
    for i, col in enumerate(row):
        log.print(
            (f"{str(col):<{widths[i]}}", colors[i]),
            ("  ", None),
            end=""
        )
    print()


def render_transaction(rows, summary=None):

    headers = (
        "Name",
        "Action",
        "Version",
        "New version",
        "Download size"
    )

    clean = []

    for r in rows:
        clean.append((
            str(r["name"]),
            str(r["action"]),
            str(r["old_version"]),
            str(r["new_version"]),
            format_size(r["size"]) if r.get("size") else "-"
        ))

    widths = [
        max(len(headers[i]), max(len(str(row[i])) for row in clean))
        for i in range(len(headers))
    ]

    # header
    for i, h in enumerate(headers):
        log.print(
            (f"{h:<{widths[i]}}", log.BOLD),
            ("  ", None),
            end=""
        )

    print()

    print("-" * (sum(widths) + (len(widths) * 2)))

    colors = [
        log.CYAN,
        log.YELLOW,
        log.WHITE,
        log.GREEN,
        log.MAGENTA
    ]

    # rows
    for row in clean:

        for i, col in enumerate(row):
            log.print(
                (f"{str(col):<{widths[i]}}", colors[i]),
                ("  ", None),
                end=""
            )

        print()



    if summary or True:

        print()

        def line(label, value, color):

            log.print(
                (f"{label:<25}", log.BOLD),
                (value, color)
            )

        # summary block
        if summary:

            line(
                "Size to download:",
                summary.get("download", "-"),
                log.GREEN
            )

            line(
                "Size required on disk:",
                summary.get("disk", "-"),
                log.GREEN
            )

            line(
                "Space available on disk:",
                summary.get("free", "-"),
                log.CYAN
            )
