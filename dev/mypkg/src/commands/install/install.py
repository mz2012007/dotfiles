from commands.install.install_db import get_package, mark_installed
from commands.install.cli import show_info1, ask_confirm
from commands.install.download import download
from commands.install.extract import extract_deb
from commands.install.hash import verify_hash

from lib.logger import log
from lib.timer import Timer

import os

base_url = "http://deb.debian.org/debian"


def _run(args):
    names = args.pkg_name
    db_path = "./cache/mypkg.db"

    timer = Timer()

    packages = []

    # =========================
    # 1. collect packages
    # =========================

    for name in names:
        pkg = get_package(db_path, name)

        if not pkg:
            log.error(("package not found: ", log.RED), (name, log.YELLOW))
            continue

        show_info(pkg)
        packages.append(pkg)

    if not packages:
        log.error("no valid packages")
        return

    # =========================
    # 2. confirm once
    # =========================

    if not args.yes:
        if not ask_confirm():
            log.warning("cancelled")
            return

    # =========================
    # 3. download all
    # =========================

    timer.start("download")

    for pkg in packages:
        pkg.deb_path = f"/tmp/{pkg.name}.deb"

        url = f"{BASE_URL}/{pkg.filename}"

        log.process(("downloading: ", log.CYAN), (pkg.name, log.YELLOW))

        download(url, pkg.deb_path)

    timer.end("download")

    # =========================
    # 4. verify all
    # =========================

    timer.start("verifying")

    verified = []

    for pkg in packages:
        log.process(("verifying: ", log.CYAN), (pkg.name, log.YELLOW))

        if not verify_hash(pkg.deb_path, getattr(pkg, "sha256", None)):
            log.error(("hash mismatch: ", log.RED), (pkg.name, log.YELLOW))

            os.remove(pkg.deb_path)
            continue

        log.success(("verified: ", log.GREEN), (pkg.name, log.CYAN))

        verified.append(pkg)

    timer.end("verifying")

    if not verified:
        log.error("no verified packages")
        return

    # =========================
    # 5. extract all
    # =========================

    for pkg in verified:
        extract_dir = f"/tmp/{pkg.name}_extracted"

        log.process(("extracting: ", log.CYAN), (pkg.name, log.YELLOW))

        extract_deb(pkg.deb_path, extract_dir)

        log.success(("extracted to: ", log.GREEN), (extract_dir, log.CYAN))

        pkg.extract_dir = extract_dir

    # =========================
    # 6. mark installed
    # =========================

    for pkg in verified:
        mark_installed(db_path, pkg.name)

        log.success(("installed: ", log.GREEN), (pkg.name, log.CYAN))




from commands.install.install_db import (
    get_package,
    mark_installed
)

from commands.install.cli import (
    ask_confirm,
    render_transaction
)

from commands.install.download import download
from commands.install.extract import extract_deb
from commands.install.hash import verify_hash

from lib.logger import log
from lib.timer import Timer

import os


BASE_URL = "http://deb.debian.org/debian"


def build_transaction(packages):

    transaction = []

    for pkg in packages:

        action = "install"

        if getattr(pkg, "installed_version", None):

            if pkg.installed_version != pkg.version:
                action = "upgrade"

            else:
                action = "reinstall"

        transaction.append({

            "name": pkg.name,

            "action": action,

            "old_version": (
                pkg.installed_version
                if getattr(pkg, "installed_version", None)
                else "-"
            ),

            "new_version": pkg.version,

            "size": pkg.size
        })

    return transaction


def run(args):

    names = args.pkg_name

    db_path = "./cache/mypkg.db"

    timer = Timer()

    packages = []

    # =========================
    # 1. collect packages
    # =========================

    for name in names:

        pkg = get_package(
            db_path,
            name
        )

        if not pkg:

            log.error(
                ("package not found: ", log.RED),
                (name, log.YELLOW)
            )

            continue

        packages.append(pkg)

    if not packages:

        log.error("no valid packages")

        return

    # =========================
    # 2. render transaction
    # =========================

    transaction = build_transaction(
        packages
    )
    transaction = build_transaction(packages)

    # =========================
    # 2. render or single view
    # =========================

    if len(packages) == 1:

        pkg = packages[0]

        # import هنا أو فوق حسب تنظيمك
        from commands.install.cli import show_info

        show_info1(pkg)

    else:

        render_transaction(transaction)

    # =========================
    # 3. confirm once
    # =========================

    if not args.yes:

        if not ask_confirm():

            log.warning("cancelled")

            return

    # =========================
    # 4. download all
    # =========================

    timer.start("download")

    for pkg in packages:

        pkg.deb_path = (
            f"/tmp/{pkg.name}.deb"
        )

        url = (
            f"{BASE_URL}/{pkg.filename}"
        )

        log.process(
            ("downloading: ", log.CYAN),
            (pkg.name, log.YELLOW)
        )

        download(
            url,
            pkg.deb_path
        )

    timer.end("download")

    # =========================
    # 5. verify all
    # =========================

    timer.start("verifying")

    verified = []

    for pkg in packages:

        log.process(
            ("verifying: ", log.CYAN),
            (pkg.name, log.YELLOW)
        )

        if not verify_hash(
            pkg.deb_path,
            getattr(pkg, "sha256", None)
        ):

            log.error(
                ("hash mismatch: ", log.RED),
                (pkg.name, log.YELLOW)
            )

            os.remove(pkg.deb_path)

            continue

        log.success(
            ("verified: ", log.GREEN),
            (pkg.name, log.CYAN)
        )

        verified.append(pkg)

    timer.end("verifying")

    if not verified:

        log.error("no verified packages")

        return

    # =========================
    # 6. extract all
    # =========================

    for pkg in verified:

        extract_dir = (
            f"/tmp/{pkg.name}_extracted"
        )

        log.process(
            ("extracting: ", log.CYAN),
            (pkg.name, log.YELLOW)
        )

        extract_deb(
            pkg.deb_path,
            extract_dir
        )

        log.success(
            ("extracted to: ", log.GREEN),
            (extract_dir, log.CYAN)
        )

        pkg.extract_dir = extract_dir

    # =========================
    # 7. mark installed
    # =========================

    for pkg in verified:

        mark_installed(
            db_path,
            pkg.name
        )

        log.success(
            ("installed: ", log.GREEN),
            (pkg.name, log.CYAN)
        )
