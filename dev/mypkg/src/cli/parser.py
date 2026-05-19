import argparse


def build_parser():
    parser = argparse.ArgumentParser(prog="mypkg")

    sub = parser.add_subparsers(
        dest="command",
        required=True
    )


    # install
    p_install = sub.add_parser("install")

    p_install.add_argument(
        "pkg_name",
        nargs="+",   # one or more packages
        help="package names to install"
    )

    p_install.add_argument(
        "--yes",
        action="store_true",
        help="auto confirm"
    )

    # search
    p_search = sub.add_parser("search")
    p_search.add_argument("query")

    # update
    p_update = sub.add_parser("update")

    p_update.add_argument(
        "--repo",
        default="stable"
    )

    p_update.add_argument(
        "--arch",
        default="amd64"
    )

    return parser
