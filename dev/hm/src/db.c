#include "db.h"
#include "scan.h"

#include <stddef.h>
#include <string.h>

static const char *SCHEMA =
    "CREATE TABLE IF NOT EXISTS tracked ("
    "id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "root_path TEXT NOT NULL UNIQUE,"
    "created_at INTEGER NOT NULL"
    ");"

    "CREATE TABLE IF NOT EXISTS paths ("
    "id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "tracked_id INTEGER NOT NULL,"
    "rel_path TEXT NOT NULL,"
    "type INTEGER NOT NULL,"
    "FOREIGN KEY(tracked_id) REFERENCES tracked(id) ON DELETE CASCADE,"
    "UNIQUE(tracked_id, rel_path)"
    ");";

int db_open(sqlite3 **db)
{
    return sqlite3_open("hm.db", db);
}

void db_close(sqlite3 *db)
{
    if (db)
        sqlite3_close(db);
}

int db_init(sqlite3 *db)
{
    char *errmsg = NULL;

    int rc = sqlite3_exec(
        db,
        SCHEMA,
        NULL,
        NULL,
        &errmsg
    );

    if (rc != SQLITE_OK) {
        sqlite3_free(errmsg);
        return -1;
    }

    return 0;
}


int db_get_tracked_id(
    sqlite3 *db,
    const char *root_path
)
{
    sqlite3_stmt *stmt = NULL;

    const char *sql =
        "SELECT id "
        "FROM tracked "
        "WHERE root_path = ?;";

    if (
        sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &stmt,
            NULL
        ) != SQLITE_OK
    ) {
        return -1;
    }

    sqlite3_bind_text(
        stmt,
        1,
        root_path,
        -1,
        SQLITE_TRANSIENT
    );

    int id = -1;

    if (
        sqlite3_step(stmt)
        == SQLITE_ROW
    ) {
        id =
            sqlite3_column_int(
                stmt,
                0
            );
    }

    sqlite3_finalize(stmt);

    return id;
}


int db_remove_path(
    sqlite3 *db,
    int tracked_id,
    const char *rel_path
)
{
    sqlite3_stmt *stmt = NULL;

    const char *sql =
        "DELETE FROM paths "
        "WHERE tracked_id = ? "
        "AND rel_path = ?;";

    if (
        sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &stmt,
            NULL
        ) != SQLITE_OK
    ) {
        return -1;
    }

    sqlite3_bind_int(
        stmt,
        1,
        tracked_id
    );

    sqlite3_bind_text(
        stmt,
        2,
        rel_path,
        -1,
        SQLITE_TRANSIENT
    );

    sqlite3_step(stmt);

    sqlite3_finalize(stmt);

    return 0;
}


int db_load_paths(
    sqlite3 *db,
    int tracked_id,
    struct path_list *list
)
{
    sqlite3_stmt *stmt = NULL;

    const char *sql =
        "SELECT rel_path, type "
        "FROM paths "
        "WHERE tracked_id = ?;";

    memset(
        list,
        0,
        sizeof(*list)
    );

    if (
        sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &stmt,
            NULL
        ) != SQLITE_OK
    ) {
        return -1;
    }

    sqlite3_bind_int(
        stmt,
        1,
        tracked_id
    );

    while (
        sqlite3_step(stmt)
        == SQLITE_ROW
    ) {

        const char *rel_path =
            (const char *)
            sqlite3_column_text(
                stmt,
                0
            );

        int type =
            sqlite3_column_int(
                stmt,
                1
            );

        path_list_push(
            list,
            rel_path,
            type
        );
    }

    sqlite3_finalize(stmt);

    return 0;
}

int db_insert_path(
    sqlite3 *db,
    int tracked_id,
    const char *rel_path,
    int type
)
{
    sqlite3_stmt *stmt = NULL;

    const char *sql =
        "INSERT OR IGNORE INTO paths "
        "(tracked_id, rel_path, type) "
        "VALUES (?, ?, ?);";

    if (
        sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &stmt,
            NULL
        ) != SQLITE_OK
    ) {
        return -1;
    }

    sqlite3_bind_int(
        stmt,
        1,
        tracked_id
    );

    sqlite3_bind_text(
        stmt,
        2,
        rel_path,
        -1,
        SQLITE_TRANSIENT
    );

    sqlite3_bind_int(
        stmt,
        3,
        type
    );

    sqlite3_step(stmt);

    sqlite3_finalize(stmt);

    return 0;
}
