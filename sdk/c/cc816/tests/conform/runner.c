/* runner.c - runs /T/T000.PRG .. /T/Tnnn.PRG one after the other (spawn + wait) and
 * prints a marker line before and after each, with its exit code. Arguments: first count. */
#include <stdio.h>
#include <stdlib.h>
#include <horizon.h>

int main(int argc, char **argv)
{
    char path[24];
    unsigned first, n, i;
    int id, code;
    if (argc < 3)
        return 1;
    first = (unsigned)strtoul(argv[1], NULL, 10);
    n = (unsigned)strtoul(argv[2], NULL, 10);
    for (i = first; i < first + n; i++) {
        sprintf(path, "/T/T%03u.PRG", i);
        printf("@@BEGIN %u\n", i);
        fflush(stdout);
        id = hz_spawn_path(path, 0, 1);
        if (id < 0) {
            printf("@@END %u spawn-error %u\n", i, hz_errno);
            continue;
        }
        code = hz_wait((unsigned)id);
        printf("\n@@END %u exit %u\n", i, (unsigned)code);
    }
    puts("@@DONE");
    return 0;
}
