#define _XOPEN_SOURCE 700

#include "add.h"
#include "db.h"
#include "scan.h"
#include "sync.h"

#include <sqlite3.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <string.h>

int cmd_add(const char *path)
{
    sqlite3 *db = NULL;
    sqlite3_stmt *stmt = NULL;

    char *resolved = realpath(path, NULL);

    if (!resolved) {
        perror("realpath");
        return 1;
    }

    if (db_open(&db) != SQLITE_OK) {
        fprintf(stderr, "failed to open database\n");
        free(resolved);
        return 1;
    }

    if (db_init(db) != 0) {
        fprintf(stderr, "failed to initialize database\n");
        db_close(db);
        free(resolved);
        return 1;
    }

    const char *sql =
        "INSERT OR IGNORE INTO tracked "
        "(root_path, created_at) "
        "VALUES (?, ?);";

    if (
        sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &stmt,
            NULL
        ) != SQLITE_OK
    ) {
        db_close(db);
        free(resolved);
        return 1;
    }

    sqlite3_bind_text(
        stmt,
        1,
        resolved,
        -1,
        SQLITE_TRANSIENT
    );

    sqlite3_bind_int64(
        stmt,
        2,
        time(NULL)
    );

    sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    int tracked_id =
        db_get_tracked_id(
            db,
            resolved
        );

    if (tracked_id < 0) {

        fprintf(
            stderr,
            "failed to get tracked id\n"
        );

        free(resolved);
        db_close(db);

        return 1;
    }

    struct path_list filesystem_list;
    struct path_list db_list;

    if (
        scan_directory(
            resolved,
            &filesystem_list
        ) != 0
    ) {

        fprintf(
            stderr,
            "failed to scan directory\n"
        );

        free(resolved);
        db_close(db);

        return 1;
    }

    if (
        db_load_paths(
            db,
            tracked_id,
            &db_list
        ) != 0
    ) {

        fprintf(
            stderr,
            "failed to load paths\n"
        );

        path_list_free(
            &filesystem_list
        );

        free(resolved);
        db_close(db);

        return 1;
    }

    printf(
        "Scanning: %s\n\n",
        resolved
    );

    size_t new_count = 0;
    size_t removed_count = 0;
    size_t unchanged_count = 0;

    for (
        size_t i = 0;
        i < filesystem_list.count;
        i++
    ) {

        struct path_entry *entry =
            &filesystem_list.items[i];

        char full_path[4096];

        if (
            strcmp(
                entry->rel_path,
                "."
            ) == 0
        ) {
            snprintf(
                full_path,
                sizeof(full_path),
                "%s",
                resolved
            );
        }
        else {
            snprintf(
                full_path,
                sizeof(full_path),
                "%s/%s",
                resolved,
                entry->rel_path
            );
        }

        if (
            path_exists(
                &db_list,
                entry->rel_path
            )
        ) {

            printf(
                "%-8s %s\n",
                "EXISTS",
                full_path
            );

            unchanged_count++;
        }
        else {

            printf(
                "%-8s %s\n",
                "NEW",
                full_path
            );

            db_insert_path(
                db,
                tracked_id,
                entry->rel_path,
                entry->type
            );

            new_count++;
        }
    }

    for (
        size_t i = 0;
        i < db_list.count;
        i++
    ) {

        struct path_entry *entry =
            &db_list.items[i];

        if (
            path_exists(
                &filesystem_list,
                entry->rel_path
            )
        ) {
            continue;
        }

        char full_path[4096];

        if (
            strcmp(
                entry->rel_path,
                "."
            ) == 0
        ) {
            snprintf(
                full_path,
                sizeof(full_path),
                "%s",
                resolved
            );
        }
        else {
            snprintf(
                full_path,
                sizeof(full_path),
                "%s/%s",
                resolved,
                entry->rel_path
            );
        }

        printf(
            "%-8s %s\n",
            "REMOVED",
            full_path
        );

        db_remove_path(
            db,
            tracked_id,
            entry->rel_path
        );

        removed_count++;
    }

    printf(
        "\nSummary:\n"
    );

    printf(
        "  New: %zu\n",
        new_count
    );

    printf(
        "  Removed: %zu\n",
        removed_count
    );

    printf(
        "  Unchanged: %zu\n",
        unchanged_count
    );

    path_list_free(
        &filesystem_list
    );

    path_list_free(
        &db_list
    );

    free(resolved);
    db_close(db);

    return 0;
}
