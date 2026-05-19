import os

from config import load_config
from lib.network import resolve_url_v2
from commands.update.downloader import download
from commands.search.parser import parse_packages_file
from commands.update.update_db import insert_packages
from lib.db import init_db
from lib.timer import Timer
from lib.logger import log


def run(args):

    timer = Timer()

    config = load_config()

    base_url = config["repo"]["base_url"]
    cache_dir = config["cache"]["dir"]

    repo = args.repo
    arch = args.arch

    os.makedirs(cache_dir, exist_ok=True)

    url = (
        f"{base_url}/dists/"
        f"{repo}/main/"
        f"binary-{arch}/Packages.gz"
    )

    gz_path = os.path.join(cache_dir, "Packages.gz")
    db_path = os.path.join(cache_dir, "mypkg.db")

    # resolve
    timer.start("resolve")
    info = resolve_url_v2(url)
    timer.end("resolve")

    # url validation
    if info.error:
        log.error(info.error)
        return

    # download
    timer.start("download")
    download(info.url, gz_path)
    timer.end("download")

    # db init
    timer.start("db")
    conn = init_db(db_path)
    timer.end("db")

    # parse
    timer.start("parse")
    packages = parse_packages_file(gz_path)
    timer.end("parse")

    # insert
    timer.start("insert")
    insert_packages(conn, packages)
    timer.end("insert")

    timer.summary()
