/* stack.c - the stack guard: recursion deeper than the stack. Run in the tiny model
 * (about 4 KB of stack): the program must end with the overflow message. With the
 * argument "ok" it recurses only a little (built with --debug: the usage report). */
#include <stdio.h>
#include <string.h>
#include <horizon.h>

static unsigned depth(unsigned n)
{
    volatile char pad[60];
    pad[0] = (char)n;
    return n ? depth(n - 1) + pad[0] : 0;
}

int main(int argc, char **argv)
{
    unsigned n = (argc > 1 && !strcmp(argv[1], "ok")) ? 10 : 200;
    printf("recursing %u levels, %u bytes free\n", n, hz_stack_free());
    n = depth(n);
    printf("result %u, guard %s\n", n, hz_stack_check() ? "overwritten" : "intact");
    return 0;
}
