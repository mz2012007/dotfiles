#!/usr/bin/env python

from cli.parser import build_parser

from commands.search import search
from commands.update import update
from commands.install import install

from lib.logger import log

COMMANDS = {
    "search": search.run,
    "update": update.run,
    "install": install.run,
}


def main():
    parser = build_parser()
    args = parser.parse_args()

    log.print(("-------------------",log.GREEN))
    COMMANDS[args.command](args)


if __name__ == "__main__":
    main()

