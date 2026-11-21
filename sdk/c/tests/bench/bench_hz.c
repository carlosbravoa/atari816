/* bench_hz.c - the two hooks bench.c needs, and main() (bench.c is the compiler trials'
 * benchmark, unchanged: sdk/c-spike/vbcc/bench/bench.c). */
#include <stdio.h>
#include <horizon.h>

extern void bench_all(void);

unsigned long bench_ms(void) { return hz_uptime(); }

void bench_out(const char *name, unsigned long ms, unsigned long check)
{
    printf("%-8s %6lu ms  check %lu\n", name, ms, check);
}

int main(void)
{
    puts("vbcc 65816 bench");
    bench_all();
    puts("bench done");
    return 0;
}
