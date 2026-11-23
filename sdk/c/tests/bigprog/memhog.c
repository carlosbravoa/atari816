/* memhog.c - the large code model's test of a failed start: takes banks until only three
 * are free (Horizon's loader needs a window, a code bank and a scratch bank, which it gives
 * back), starts the program given as the argument, and says how it ended. A large program
 * that needs two or more other code banks then finds one free bank: its loader
 * (lib/xload.c) says "not enough memory" and the program ends with exit code 1. */
#include <horizon.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    unsigned n = 0;
    int t, code;
    if (argc < 2) {
        printf("memhog: give the program's path\n");
        return 2;
    }
    while (hz_mem_info() > 3) {
        hz_bank_alloc();
        if (hz_errno)
            break;
        n++;
    }
    printf("memhog: %u banks taken, %u free\n", n, hz_mem_info());
    t = hz_spawn_path(argv[1], 0, 1);
    if (t < 0) {
        printf("memhog: spawn failed, error %u\n", hz_errno);
        return 1;
    }
    code = hz_wait((unsigned)t);
    printf("memhog: the program ended with code %d\n", code);
    return 0;
}
