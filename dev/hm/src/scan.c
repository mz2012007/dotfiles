#define _XOPEN_SOURCE 700

#include "scan.h"

#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>

int path_list_push(
    struct path_list *list,
    const char *rel_path,
    int type
)
{
    if (list->count == list->capacity) {

        size_t new_capacity =
            list->capacity ? list->capacity * 2 : 64;

        struct path_entry *tmp =
            realloc(
                list->items,
                new_capacity *
                sizeof(struct path_entry)
            );

        if (!tmp)
            return -1;

        list->items = tmp;
        list->capacity = new_capacity;
    }

    list->items[list->count].rel_path =
        strdup(rel_path);

    list->items[list->count].type =
        type;

    list->count++;

    return 0;
}

static int scan_recursive(
    const char *root,
    const char *rel_path,
    struct path_list *list
)
{
    char full_path[4096];

    if (strcmp(rel_path, ".") == 0)
        snprintf(
            full_path,
            sizeof(full_path),
            "%s",
            root
        );
    else
        snprintf(
            full_path,
            sizeof(full_path),
            "%s/%s",
            root,
            rel_path
        );

    struct stat st;

    if (lstat(full_path, &st) != 0)
        return -1;

    if (S_ISDIR(st.st_mode)) {

        path_list_push(
            list,
            rel_path,
            HM_DIR
        );

        DIR *dir =
            opendir(full_path);

        if (!dir)
            return -1;

        struct dirent *entry;

        while (
            (entry = readdir(dir))
        ) {

            if (
                strcmp(
                    entry->d_name,
                    "."
                ) == 0
                ||
                strcmp(
                    entry->d_name,
                    ".."
                ) == 0
            )
                continue;

            char child_rel[4096];

            if (
                strcmp(
                    rel_path,
                    "."
                ) == 0
            )
                snprintf(
                    child_rel,
                    sizeof(child_rel),
                    "%s",
                    entry->d_name
                );
            else
                snprintf(
                    child_rel,
                    sizeof(child_rel),
                    "%s/%s",
                    rel_path,
                    entry->d_name
                );

            scan_recursive(
                root,
                child_rel,
                list
            );
        }

        closedir(dir);
    }
    else {

        path_list_push(
            list,
            rel_path,
            HM_FILE
        );
    }

    return 0;
}

int scan_directory(
    const char *root,
    struct path_list *list
)
{
    memset(
        list,
        0,
        sizeof(*list)
    );

    return scan_recursive(
        root,
        ".",
        list
    );
}

void path_list_free(
    struct path_list *list
)
{
    for (
        size_t i = 0;
        i < list->count;
        i++
    ) {
        free(
            list->items[i].rel_path
        );
    }

    free(list->items);

    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
}
