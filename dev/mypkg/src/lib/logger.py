from datetime import datetime


class Logger:

    # styles
    RESET = "\033[0m"
    BOLD = "\033[1m"

    # colors
    BLACK = "\033[30m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"

    BRIGHT_BLACK = "\033[90m"
    BRIGHT_RED = "\033[91m"
    BRIGHT_GREEN = "\033[92m"
    BRIGHT_YELLOW = "\033[93m"
    BRIGHT_BLUE = "\033[94m"
    BRIGHT_MAGENTA = "\033[95m"
    BRIGHT_CYAN = "\033[96m"
    BRIGHT_WHITE = "\033[97m"

    COLORS = {
        "INFO": CYAN,
        "WARNING": YELLOW,
        "ERROR": RED,
        "PROCESS": BLUE,
        "DEBUG": MAGENTA,
        "SUCCESS": GREEN,
    }

    def __init__(self, log_file="app.log", debug=False):
        self.log_file = log_file
        self.debug_mode = debug

    def now(self):
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def c(self, text, color):
        if color is None:
            color = self.RESET
        return f"{color}{text}{self.RESET}"

    def paint(self, *parts):
        result = ""
        for text, color in parts:
            if text is None:
                continue
            if color is None:
                color = self.RESET
            result += self.c(str(text), color)
        return result

    def print(self, *parts, end="\n", sep=" ", flush=False):
        print(self.paint(*parts), end=end, sep=sep, flush=flush)

    def write_file(self, level, message):
        with open(self.log_file, "a") as f:
            f.write(f"[{self.now()}] [{level}] {message}\n")

    def emit(self, level, *parts, end="\n"):
        if level == "DEBUG" and not self.debug_mode:
            return

        level_color = self.COLORS.get(level, self.WHITE)

        time_part = self.c(f"[{self.now()}]", self.MAGENTA)

        level_part = self.paint(
            ("[", self.BOLD),
            (level, level_color),
            ("]", self.BOLD),
        )

        if len(parts) == 1 and isinstance(parts[0], str):
            message = parts[0]
        else:
            message = self.paint(*parts)

        print(f"{time_part} {level_part} {message}", end=end)
        self.write_file(level, message)

    def info(self, *parts): self.emit("INFO", *parts)
    def warning(self, *parts): self.emit("WARNING", *parts)
    def error(self, *parts): self.emit("ERROR", *parts)
    def process(self, *parts): self.emit("PROCESS", *parts)
    def debug(self, *parts): self.emit("DEBUG", *parts)
    def success(self, *parts): self.emit("SUCCESS", *parts)

    def set_debug(self, enabled=True):
        self.debug_mode = enabled

    def progress(self, current, total, width=30):
        if total == 0:
            total = 1

        percent = current / total
        filled = int(width * percent)

        bar = "█" * filled + "-" * (width - filled)

        print(
            f"\r{self.CYAN}[{bar}]{self.RESET} {int(percent * 100)}%",
            end="",
            flush=True
        )

        if current >= total:
            print()


log = Logger()
