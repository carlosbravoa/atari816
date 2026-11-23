/* bench_hz.c - the two hooks bench.c needs, and main() (bench.c is the benchmark the
 * compiler trials used, unchanged). */
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
    puts("bench");
    bench_all();
    puts("bench done");
    return 0;
}
