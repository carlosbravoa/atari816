/* hello.c - a console C program for Horizon (cc65, 65816 native with 8-bit registers) */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "horizon.h"

int main(int argc, char **argv)
{
    int i;
    unsigned long t = hz_uptime();
    puts("Hello from C on the Atari816!");
    hz_puts("(and once through the raw puts syscall)\n");
    printf("argument string: \"%s\" (%u characters)\n", hz_args, strlen(hz_args));
    for (i = 0; i < argc; i++)
        printf("argv[%d] = %s\n", i, argv[i]);
    printf("code bank $%02X, uptime %lu ms, 32-bit: %lu\n", hz_bank, t, 123456789UL * 3);
    {   /* the heap: from the end of bss to the C stack (top of the code bank) - 4 KB */
        char *p = malloc(30000), *q = malloc(20000);
        printf("malloc: %p %p, largest free block now %u bytes\n", p, q, _heapmaxavail());
        free(q); free(p);
    }
    return 0;
}
