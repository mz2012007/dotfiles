import sqlite3
from lib.db import SQL

def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def insert_packages(conn, packages, chunk_size=2000):

    cur = conn.cursor()

    conn.execute("BEGIN")

    package_batch = []
    version_batch = []

    # cache to avoid repeated SELECT
    package_cache = {}

    for package_row, version_row in gen_rows(packages):

        package_batch.append(package_row)
        version_batch.append(version_row)

        if len(package_batch) >= chunk_size:

            insert_batch(cur, package_batch, version_batch, package_cache)

            package_batch.clear()
            version_batch.clear()

    if package_batch:
        insert_batch(cur, package_batch, version_batch, package_cache)

    conn.commit()


def insert_batch(cur, package_batch, version_batch, package_cache):

    # =========================
    # Insert packages (UPSERT)
    # =========================

    cur.executemany(
        SQL["insert_package"],
        package_batch
    )

    # refresh cache only once per batch
    cur.execute("SELECT name, id FROM packages")
    package_cache.update(cur.fetchall())

    # =========================
    # Insert versions
    # =========================

    for row in version_batch:

        (
            package_name,
            version,
            architecture,
            maintainer,
            description,
            filename,
            size,
            installed_size,
            priority,
            md5,
            sha256,
            depends,
            pre_depends
        ) = row

        package_id = package_cache.get(package_name)

        if not package_id:
            continue

        cur.execute(
            SQL["insert_package_version"],
            (
                package_id,
                version,
                architecture,
                maintainer,
                description,
                filename,
                size,
                installed_size,
                priority,
                md5,
                sha256,
                depends,
                pre_depends
            )
        )


def gen_rows(packages):

    for p in packages:

        name = p.get("Package")
        if not name:
            continue

        package_row = (
            name,
            p.get("Homepage"),
            p.get("Section"),
            p.get("Source")
        )

        version_row = (
            name,
            p.get("Version"),
            p.get("Architecture"),
            p.get("Maintainer"),
            p.get("Description"),
            p.get("Filename"),
            to_int(p.get("Size")),
            to_int(p.get("Installed-Size")),
            p.get("Priority"),
            p.get("MD5sum"),
            p.get("SHA256"),
            p.get("Depends"),
            p.get("Pre-Depends")
        )

        yield package_row, version_row
