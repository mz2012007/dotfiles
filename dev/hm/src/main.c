#include "add.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr,
                "usage: hm add <path>\n");
        return 1;
    }

    if (strcmp(argv[1], "add") == 0)
        return cmd_add(argv[2]);

    fprintf(stderr, "unknown command\n");

    return 1;
}
