#include "sync.h"

#include <string.h>

int path_exists(
    const struct path_list *list,
    const char *path
)
{
    for (
        size_t i = 0;
        i < list->count;
        i++
    ) {
        if (
            strcmp(
                list->items[i].rel_path,
                path
            ) == 0
        ) {
            return 1;
        }
    }

    return 0;
}
