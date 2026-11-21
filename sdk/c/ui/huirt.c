/* huirt.c - the C side of the controls library's block (linked with it by hcc): where
 * the block's checks end a program (a control given as a local, a control routine called
 * inside a callback). The message names the function; stdout is flushed first so the
 * program's own output comes before it. */
#include <stdio.h>
#include <stdlib.h>

void __hui_fatal(const char *msg, unsigned what)
{
    fflush(stdout);
    if (what == 0)
        fprintf(stderr, "hui: %s: not in the code bank: give the controls library a global, "
                "static or malloc'd object or a string constant, not a local variable "
                "(sdk/docs/c/apps.md, \"The rule\")\n", msg);
    else
        fprintf(stderr, "hui: %s: a control routine called inside a callback (a list's "
                "row function, the copy callback): a callback may only draw\n", msg);
    exit(70);
}
