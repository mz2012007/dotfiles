import sqlite3
from commands.install.model import Package


def get_package(db_path: str, name: str):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
    SELECT
        p.name,
        pv.version,
        pv.filename,
        pv.size,
        pv.description,
        COALESCE(
            (
                SELECT ip.install_state
                FROM installed_packages ip
                WHERE ip.package_version_id = pv.id
                  AND ip.install_state = 'installed'
                LIMIT 1
            ),
            'NOT INSTALLED'
        ) AS status,
        pv.installed_size,
        pv.sha256
    FROM packages p
    JOIN package_versions pv
        ON pv.package_id = p.id
    WHERE p.name = ?
    ORDER BY pv.id DESC
    LIMIT 1
    """, (name,))

    row = cur.fetchone()
    conn.close()

    if not row:
        return None

    return Package(
        name=row[0],
        version=row[1],
        filename=row[2],
        size=row[3],
        description=row[4],
        status=row[5],
        installed_size=row[6],
        sha256=row[7]
    )


def mark_installed(db_path: str, name: str, version: str = None, architecture: str = None):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    if version is None and architecture is None:
        cur.execute("""
        SELECT
            p.id,
            pv.id,
            pv.version,
            pv.architecture
        FROM packages p
        JOIN package_versions pv
            ON pv.package_id = p.id
        WHERE p.name = ?
        ORDER BY pv.id DESC
        LIMIT 1
        """, (name,))
    elif version is not None and architecture is None:
        cur.execute("""
        SELECT
            p.id,
            pv.id,
            pv.version,
            pv.architecture
        FROM packages p
        JOIN package_versions pv
            ON pv.package_id = p.id
        WHERE p.name = ?
          AND pv.version = ?
        ORDER BY pv.id DESC
        LIMIT 1
        """, (name, version))
    else:
        cur.execute("""
        SELECT
            p.id,
            pv.id,
            pv.version,
            pv.architecture
        FROM packages p
        JOIN package_versions pv
            ON pv.package_id = p.id
        WHERE p.name = ?
          AND pv.version = ?
          AND pv.architecture = ?
        ORDER BY pv.id DESC
        LIMIT 1
        """, (name, version, architecture))

    row = cur.fetchone()

    if not row:
        conn.close()
        return

    package_id, package_version_id, installed_version, pkg_arch = row

    cur.execute("""
    INSERT INTO installed_packages (
        package_id,
        package_version_id,
        installed_version,
        architecture,
        install_state
    )
    VALUES (
        ?, ?, ?, ?, 'installed'
    )
    ON CONFLICT(package_id, architecture)
    DO UPDATE SET
        package_version_id = excluded.package_version_id,
        installed_version = excluded.installed_version,
        install_state = 'installed'
    """, (
        package_id,
        package_version_id,
        installed_version,
        pkg_arch
    ))

    conn.commit()
    conn.close()


def mark_not_installed(db_path: str, name: str):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
    UPDATE installed_packages
    SET install_state = 'not-installed'
    WHERE package_id = (
        SELECT id
        FROM packages
        WHERE name = ?
    )
    """, (name,))

    conn.commit()
    conn.close()
