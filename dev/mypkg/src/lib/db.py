import sqlite3


SQL = {
    "insert_package": """
    INSERT INTO packages (
        name,
        homepage,
        section,
        source
    )
    VALUES (
        ?, ?, ?, ?
    )
    ON CONFLICT(name)
    DO UPDATE SET
        homepage = excluded.homepage,
        section = excluded.section,
        source = excluded.source
    """,

    "insert_package_version": """
    INSERT INTO package_versions (
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
    VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
    )
    ON CONFLICT(package_id, version, architecture)
    DO UPDATE SET
        maintainer = excluded.maintainer,
        description = excluded.description,
        filename = excluded.filename,
        size = excluded.size,
        installed_size = excluded.installed_size,
        priority = excluded.priority,
        md5 = excluded.md5,
        sha256 = excluded.sha256,
        depends = excluded.depends,
        pre_depends = excluded.pre_depends
    """
}


def init_db(db_path):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("PRAGMA foreign_keys = ON;")
    cur.execute("PRAGMA journal_mode = OFF;")
    cur.execute("PRAGMA synchronous = OFF;")
    cur.execute("PRAGMA temp_store = MEMORY;")
    cur.execute("PRAGMA cache_size = -50000;")
    cur.execute("PRAGMA mmap_size = 268435456;")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS packages (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        homepage TEXT,
        section TEXT,
        source TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS repositories (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        base_url TEXT NOT NULL,
        distribution TEXT,
        component TEXT,
        architecture TEXT,
        enabled INTEGER DEFAULT 1,
        priority INTEGER DEFAULT 0,
        gpg_key TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS package_versions (
        id INTEGER PRIMARY KEY,
        package_id INTEGER NOT NULL,
        version TEXT NOT NULL,
        architecture TEXT,
        maintainer TEXT,
        description TEXT,
        filename TEXT,
        size INTEGER,
        installed_size INTEGER,
        priority TEXT,
        md5 TEXT,
        sha256 TEXT,
        depends TEXT,
        pre_depends TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(package_id)
            REFERENCES packages(id)
            ON DELETE CASCADE,
        UNIQUE(package_id, version, architecture)
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS package_relations (
        id INTEGER PRIMARY KEY,
        package_version_id INTEGER NOT NULL,
        relation_type TEXT NOT NULL,
        target_package_id INTEGER,
        target_package_name TEXT NOT NULL,
        version_operator TEXT,
        version_value TEXT,
        architecture_constraint TEXT,
        alternative_group INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(package_version_id)
            REFERENCES package_versions(id)
            ON DELETE CASCADE,
        FOREIGN KEY(target_package_id)
            REFERENCES packages(id)
            ON DELETE SET NULL,
        CHECK(relation_type IN (
            'depends',
            'pre-depends',
            'recommends',
            'suggests',
            'conflicts',
            'breaks',
            'replaces',
            'provides'
        ))
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS package_files (
        id INTEGER PRIMARY KEY,
        package_version_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT,
        file_size INTEGER,
        checksum TEXT,
        is_config INTEGER DEFAULT 0,
        is_directory INTEGER DEFAULT 0,
        mode TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(package_version_id)
            REFERENCES package_versions(id)
            ON DELETE CASCADE,
        UNIQUE(package_version_id, file_path)
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS installed_packages (
        id INTEGER PRIMARY KEY,
        package_id INTEGER NOT NULL,
        package_version_id INTEGER,
        installed_version TEXT NOT NULL,
        architecture TEXT,
        install_state TEXT DEFAULT 'installed',
        installed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        installed_by TEXT,
        manual INTEGER DEFAULT 0,
        auto_installed INTEGER DEFAULT 0,
        hold INTEGER DEFAULT 0,
        install_reason TEXT,
        repository_id INTEGER,
        FOREIGN KEY(package_id)
            REFERENCES packages(id)
            ON DELETE CASCADE,
        FOREIGN KEY(package_version_id)
            REFERENCES package_versions(id)
            ON DELETE SET NULL,
        FOREIGN KEY(repository_id)
            REFERENCES repositories(id)
            ON DELETE SET NULL,
        UNIQUE(package_id, architecture)
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        finished_at TIMESTAMP,
        error TEXT
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS transaction_items (
        id INTEGER PRIMARY KEY,
        transaction_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        package_version_id INTEGER,
        target_path TEXT,
        old_value TEXT,
        new_value TEXT,
        rollback_data TEXT,
        status TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(transaction_id)
            REFERENCES transactions(id)
            ON DELETE CASCADE,
        FOREIGN KEY(package_version_id)
            REFERENCES package_versions(id)
            ON DELETE SET NULL
    )
    """)

    indexes = [
        """
        CREATE INDEX IF NOT EXISTS idx_packages_name
        ON packages(name)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_package_versions_package_id
        ON package_versions(package_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_package_versions_version
        ON package_versions(version)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_relations_package_version_id
        ON package_relations(package_version_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_relations_target_name
        ON package_relations(target_package_name)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_relations_type
        ON package_relations(relation_type)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_package_files_package_version_id
        ON package_files(package_version_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_package_files_path
        ON package_files(file_path)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_installed_packages_package_id
        ON installed_packages(package_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_transactions_status
        ON transactions(status)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_transaction_items_transaction_id
        ON transaction_items(transaction_id)
        """
    ]

    for index in indexes:
        cur.execute(index)

    conn.commit()
    return conn
