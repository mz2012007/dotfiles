#ifndef DB_H
#define DB_H

#include <sqlite3.h>
#include "scan.h"

int db_open(sqlite3 **db);
void db_close(sqlite3 *db);

int db_init(sqlite3 *db);

int db_get_tracked_id(
    sqlite3 *db,
    const char *root_path
);

int db_insert_path(
    sqlite3 *db,
    int tracked_id,
    const char *rel_path,
    int type
);

int db_remove_path(
    sqlite3 *db,
    int tracked_id,
    const char *rel_path
);

int db_load_paths(
    sqlite3 *db,
    int tracked_id,
    struct path_list *list
);

#endif
