/* hello.c - a console C program for Horizon (vbcc 65816, large data model) */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "horizon.h"

static int sumto(int *p, int n) { int s = 0; while (n--) s += *p++; return s; }
static void bump(int *p) { *p += 1; }

int gl[4] = { 10, 20, 30, 40 };
const char hello2[] = "(and once through the raw puts syscall)\n";

int main(void)
{
    int loc = 41, arr[3];
    unsigned long t = hz_uptime();
    arr[0] = 1; arr[1] = 2; arr[2] = 3;
    puts("Hello from C (vbcc 65816) on the Atari816!");
    hz_puts(hello2);
    hz_puts("argument string through puts: [");
    hz_puts(hz_args);
    hz_puts("]\n");
    printf("argument string: \"%s\" (%u characters, %u by strlen)\n", hz_args,
           __hz_arglen, (unsigned)strlen(hz_args));
    bump(&loc);
    printf("&local passed: %d (42)  local array: %d (6)  global: %d (100)\n",
           loc, sumto(arr, 3), sumto(gl, 4));
    printf("pointers: &loc %p  arr %p  gl %p  main %p\n", (void *)&loc, (void *)arr,
           (void *)gl, (void *)main);
    printf("uptime %lu ms, 32-bit: %lu\n", t, 123456789UL * 3);
    printf("inline-asm syscalls: task %u, uptime %lu ms ", hz_getpid(), hz_uptime_i());
    fflush(stdout);
    hz_putc_i('!');
    hz_putc_i('\n');
    {   /* the heap: large model from the end of bss to $FF00 of the code bank, tiny model
         * from the end of bss to WEND in the window */
        char *p = malloc(3000), *q = malloc(2000);
        int ok = p && q;
        if (ok) { memset(p, 'x', 3000); memset(q, 'y', 2000); ok = p[2999] == 'x' && q[0] == 'y'; }
        printf("malloc: %p %p %s\n", (void *)p, (void *)q, ok ? "ok" : "FAILED");
        free(q); free(p);
    }
    {   /* data in another bank: bank_alloc + a far pointer (any model) */
        unsigned bank = hz_balloc(), i;
        unsigned long sum = 0;
        char __far *b;
        if (hz_err) { printf("bank_alloc error %u\n", hz_err); return 1; }
        b = (char __far *)((unsigned long)bank << 16);
        for (i = 0; i < 1000; i++) b[i * 60u] = (char)i;
        for (i = 0; i < 1000; i++) sum += (unsigned char)b[i * 60u];
        printf("bank $%02X through a far pointer: sum %lu (124716)\n", bank, sum);
    }
    return 0;
}
