from commands.search.search_db import search_packages
from lib.utils import color, CYAN, YELLOW, BOLD, format_size


def run(args):
    db_path = "./cache/mypkg.db"

    results = search_packages(db_path,args.query)

    print( color(f"\nResults for '{args.query}':\n", CYAN) )

    for (
        name,
        version,
        size,
        installed_size,
        architecture,
        desc,
        installed
        ) in results:

        status = "[*]" if installed else "[ ]"

        print(
            f"{status} "
            f"{color(name, BOLD)} "
            f"{version} "
            f"{architecture}"
        )

        print(
            f"  size: {color(format_size(size), YELLOW)}"
        )

        if installed_size:
            print(
                f"  installed size: {format_size(installed_size)}"
            )

        if desc:
            print(f"  {desc[:80]}")

        print("-" * 50)
