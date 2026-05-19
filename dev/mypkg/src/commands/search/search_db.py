import sqlite3


def search_packages(db_path, query, limit=20):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
    SELECT
        p.name,
        pv.version,
        pv.size,
        pv.installed_size,
        pv.architecture,
        pv.description,
        EXISTS (
            SELECT 1
            FROM installed_packages ip
            WHERE ip.package_version_id = pv.id
              AND ip.install_state = 'installed'
        ) AS installed
    FROM package_versions pv
    JOIN packages p
        ON p.id = pv.package_id
    WHERE p.name LIKE ?
    ORDER BY p.name, pv.version DESC
    LIMIT ?
    """, (
        f"%{query}%",
        limit
    ))

    rows = cur.fetchall()
    conn.close()
    return rows
