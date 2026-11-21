/* bench_hz.c - the two hooks bench.c needs, for vbcc 65816 under Horizon, and main(). */
#include <stdio.h>
#include "horizon.h"

extern void bench_all(void);

unsigned long bench_ms(void) { return hz_uptime(); }

void bench_out(const char *name, unsigned long ms, unsigned long check)
{
    printf("%-8s %6lu ms  check %lu\n", name, ms, check);
}

int main(void)
{
    puts("vbcc 65816 bench (" __DATE__ ")");
    bench_all();
    puts("bench done");
    return 0;
}
