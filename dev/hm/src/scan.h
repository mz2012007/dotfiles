#ifndef SCAN_H
#define SCAN_H

#include <stddef.h>

#define HM_FILE 0
#define HM_DIR 1

struct path_entry {
    char *rel_path;
    int type;
};

struct path_list {
    struct path_entry *items;
    size_t count;
    size_t capacity;
};

int scan_directory(
    const char *root,
    struct path_list *list
);

int path_list_push(
    struct path_list *list,
    const char *rel_path,
    int type
);

void path_list_free(
    struct path_list *list
);

#endif
