/* r002_farbyte.c - bug 2: a byte read through a far pointer was a 16-bit read (and #$FF):
 * at a bank's last byte (b[65535u]) it touched the next bank and Horizon ended the
 * program. Fixed: 8-bit reads for far and volatile bytes.
 * Bug 3: far pointer + an unsigned constant of 32768 or more (b + 65535u) was sign-extended
 * (the pointer went backwards). Fixed: unsigned indexes are zero-extended. */
#include <horizon.h>

int main(void)
{
    unsigned char __far *b = hz_far_alloc();
    unsigned char __far *q;
    int ok;
    if (!b)
        return 2;
    b[65535u] = 9;
    b[65534u] = 7;
    q = b + 65535u;
    ok = b[65535u] == 9 && *q == 9 && q[-1] == 7;
    hz_far_free(b);
    return ok ? 0 : 1;
}
