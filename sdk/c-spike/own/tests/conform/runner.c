/* runner.c - runs /T/T000.PRG .. /T/Tnnn.PRG one after the other (spawn + wait) and
 * prints a marker line before and after each, with its exit code. Argument: "first count". */
#include <stdio.h>
#include <stdlib.h>
#include <horizon.h>

struct spawn_blk {
    unsigned path; unsigned char pbank;
    unsigned args; unsigned char abank;
    unsigned char prio;
};

int main(void)
{
    char path[24], *p;
    struct spawn_blk b;
    unsigned first, n, i, id, code;
    first = (unsigned)strtoul(hz_args, &p, 10);
    n = (unsigned)strtoul(p, NULL, 10);
    for (i = first; i < first + n; i++) {
        sprintf(path, "/T/T%03u.PRG", i);
        b.path = (unsigned)path; b.pbank = (unsigned char)__cbank();
        b.args = 0; b.abank = 0; b.prio = 1;
        printf("@@BEGIN %u\n", i);
        id = hz_sys(SYS_SPAWN, 0, (unsigned)&b, __cbank());
        if (hz_err) {
            printf("@@END %u spawn-error %u\n", i, hz_err);
            continue;
        }
        code = hz_sys(SYS_WAIT, id, 0, 0);
        printf("\n@@END %u exit %u\n", i, code);
    }
    puts("@@DONE");
    return 0;
}
