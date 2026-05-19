import os

# ANSI colors
RESET = "\033[0m"
BOLD = "\033[1m"

RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
MAGENTA = "\033[35m"


def format_size(size):
    if size is None:
        return "?"
    size = int(size)

    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024:
            return f"{size:.1f}{unit}"
        size /= 1024

def get_free_space(path="/"):
    stat = os.statvfs(path)

    free_bytes = stat.f_bavail * stat.f_frsize

    return free_bytes

def color(text, c):
    return f"{c}{text}{RESET}"


