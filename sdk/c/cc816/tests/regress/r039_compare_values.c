/* r039_compare_values.c - compares as values (opt.setcc: d = a < b without branches,
 * the carry or the sign rotated into A) and in branches, 16 and 32 bits, signed and
 * unsigned, against variables, constants, 0 and the edges; x < 0 and x >= 0 of a long
 * (its high word's sign alone); _Bool from a value and from a _Bool (copied as it is).
 * Each against the same compare made by an if.
 * LEVELS: 0 1 2 */
#include <stdbool.h>

static volatile int one = 1, zero = 0;
#define REL(OP, a, b) ((a) OP (b) ? one : zero)
#define ALL(T, a, b) \
    if ((T)((a) < (b)) != REL(<, a, b) || (T)((a) <= (b)) != REL(<=, a, b) || \
        (T)((a) > (b)) != REL(>, a, b) || (T)((a) >= (b)) != REL(>=, a, b) || \
        (T)((a) == (b)) != REL(==, a, b) || (T)((a) != (b)) != REL(!=, a, b)) return __LINE__

static int v16(int a, int b, unsigned ua, unsigned ub)
{
    int r;
    ALL(int, a, b);
    ALL(int, ua, ub);
    ALL(int, a, 0);
    ALL(int, a, 1);
    ALL(int, a, -1);
    ALL(int, a, 32767);
    ALL(int, a, -32768);
    ALL(int, a, 1000);
    ALL(int, ua, 0u);
    ALL(int, ua, 1u);
    ALL(int, ua, 65535u);
    ALL(int, ua, 40000u);
    ALL(int, 0, a);
    ALL(int, 100, a);
    ALL(int, 50000u, ua);
    r = (a < b) + (ua >= ub) * 2 + (a == 7) * 4 + (ua != 0) * 8;
    if (r != REL(<, a, b) + REL(>=, ua, ub) * 2 + REL(==, a, 7) * 4 + REL(!=, ua, 0) * 8)
        return 1;
    return 0;
}

static int v32(long a, long b, unsigned long ua, unsigned long ub)
{
    long r;
    ALL(long, a, b);
    ALL(long, ua, ub);
    ALL(long, a, 0L);
    ALL(long, a, 1L);
    ALL(long, a, -1L);
    ALL(long, a, 0x7FFFFFFFL);
    ALL(long, a, -2147483647L - 1);
    ALL(long, a, 0x2800L);
    ALL(long, a, -20000L);
    ALL(long, a, 65536L);
    ALL(long, ua, 0UL);
    ALL(long, ua, 0xFFFFFFFFUL);
    ALL(long, ua, 0xA101UL);
    ALL(long, ua, 0x10000UL);
    ALL(long, 0L, a);
    ALL(long, 70000L, a);
    r = (a < b) + (ua >= ub) * 2 + (a == 70000L) * 4 + (ua != 0) * 8 + (a < 0) * 16 +
        (a >= 0) * 32;
    if (r != REL(<, a, b) + REL(>=, ua, ub) * 2 + REL(==, a, 70000L) * 4 + REL(!=, ua, 0) * 8 +
             REL(<, a, 0) * 16 + REL(>=, a, 0) * 32)
        return 1;
    if (a < 0) {
        if (!REL(<, a, 0)) return 2;
    } else if (REL(<, a, 0)) {
        return 3;
    }
    if (a >= 0 ? !REL(>=, a, 0) : REL(>=, a, 0))
        return 4;
    return 0;
}

struct cell { bool tunnel, tile, cube; unsigned char pad; };

static int bools(int x, long y, const struct cell *c)
{
    bool b1 = x, b2 = y, b3 = c->tunnel, b4 = c->cube && !c->tile;
    bool b5 = b3;               /* (a _Bool copied: 0 or 1 already) */
    if (b1 != REL(!=, x, 0) || b2 != REL(!=, y, 0L) || b3 != (c->tunnel ? one : zero))
        return 1;
    if (b4 != ((c->cube ? one : zero) & (c->tile ? zero : one)) || b5 != b3 || (b5 + b5) > 2)
        return 2;
    return 0;
}

int main(void)
{
    static const long e32[] = { 0, 1, -1, 2, -2, 0x7FFF, 0x8000, -0x8000, 0xFFFF, 0x10000,
                                -0x10000, 0x27FF, 0x2800, 0x2801, -20000, -19999, 70000,
                                0xA100, 0xA101, 0xA102, 0x7FFFFFFFL, -0x7FFFFFFFL,
                                -2147483647L - 1, 0x12345678L, -0x12345678L };
    static const struct cell cs[3] = { { 1, 0, 1, 0 }, { 0, 1, 0, 9 }, { 1, 1, 1, 0 } };
    unsigned i, j;
    int r;
    for (i = 0; i < sizeof e32 / sizeof e32[0]; i++)
        for (j = 0; j < sizeof e32 / sizeof e32[0]; j++) {
            long a = e32[i], b = e32[j];
            if ((r = v16((int)a, (int)b, (unsigned)a, (unsigned)b)) != 0)
                return r;
            if ((r = v32(a, b, (unsigned long)a, (unsigned long)b)) != 0)
                return 1000 + r;
            if ((r = bools((int)a, b, &cs[(i + j) % 3])) != 0)
                return 2000 + r;
        }
    return 0;
}
