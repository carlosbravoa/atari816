/* enums.c - enumerations with negative values and values above 32767. */
enum small { NEG = -5, ZERO = 0, POS = 7 };
enum big { B1 = 40000u, B2, B3 = 65535u };
enum huge { H1 = 100000L, H2 };
enum seq { A, B, C = 10, D, E = C + D };

static int classify(enum small s)
{
    switch (s) {
    case NEG: return -1;
    case ZERO: return 0;
    default: return 1;
    }
}

int main(void)
{
    enum small s = NEG;
    enum big b = B2;
    long h = H2;
    if (s >= 0 || NEG != -5 || classify(NEG) != -1 || classify(POS) != 1)
        return 1;
    if (b != 40001u || B3 != 65535u || b < 40000u)
        return 2;
    if (h != 100001L || H1 != 100000L)
        return 3;
    if (A != 0 || B != 1 || D != 11 || E != 21)
        return 4;
    if (sizeof(enum small) != 2 || sizeof(enum big) != 2)
        return 5;
    s = (enum small)(s + 12);
    if (s != POS)
        return 6;
    return 0;
}
