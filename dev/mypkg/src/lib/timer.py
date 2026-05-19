import time

from lib.logger import log

class Timer:
    def __init__(self):
        self.tasks = {}
        self.results = {}

    def start(self, name: str):
        self.tasks[name] = time.time()
        log.info(
                 ("start: ",log.GREEN),
                 (f"{name}",log.RESET)
        )

    def end(self, name: str):
        if name not in self.tasks:
            log.error(
                     (f"{name}",log.BOLD),
                     ("not started",log.RESET)
            )
            return

        elapsed = time.time() - self.tasks[name]
        self.results[name] = elapsed

        log.success(
                    (f"end: ",log.GREEN),
                    (f"{name}",log.RESET),
                    (" -> ",log.BLUE),
                    (f"{elapsed:.4f}",log.RESET),
                    ("s",log.MAGENTA)
        )


    def summary(self):
        log.print(("\n=== TIMER SUMMARY ===",log.GREEN))

        total = 0
        for name, t in self.results.items():
            log.print(
                      (f"{name}",log.CYAN),
                      (": ",log.BOLD),
                      (f"{t:.4f}",log.MAGENTA),
                      ("s",log.RESET)
            )
            total += t

        log.print(("--------------------", log.GREEN))
        log.print(
                  ("TOTAL: ",log.CYAN),
                  (f"{total:.4f}",log.MAGENTA),
                  ("s",log.RESET)
        )


