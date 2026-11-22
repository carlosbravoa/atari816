/* scanll.c - scanf's long long conversions for cc816: %lld %lli %llu %llo %llx (and j:
 * intmax_t is long long), linked only into programs that use long long
 * (rt/cc816/ll_hooks.s installs __hz_scanll as scan.c's __hz_scan_ll). A sign, 0x for %x and %i, a leading 0 for %i's
 * octal, as scan.c reads the shorter sizes. */

typedef int (*hz_getfn)(void *ctx);
typedef void (*hz_ungetfn)(int c, void *ctx);

int __hz_scanll(hz_getfn get, hz_ungetfn unget, void *ctx, unsigned width, unsigned base,
                unsigned *nread, void *to)
{
    unsigned long long v = 0;
    int c, neg = 0, any = 0;
    unsigned d;
#define GET() (c = get(ctx), c != -1 ? ++*nread : 0, c)
    GET();
    if ((c == '-' || c == '+') && width) {
        neg = c == '-';
        --width;
        GET();
    }
    if (c == '0' && width && (base == 0 || base == 16)) {
        any = 1;
        --width;
        GET();
        if ((c == 'x' || c == 'X') && width) {
            --width;
            GET();
            base = 16;
            any = 0;
        } else if (base == 0)
            base = 8;
    }
    if (base == 0)
        base = 10;
    while (width) {
        if (c >= '0' && c <= '9')
            d = (unsigned)(c - '0');
        else if (c >= 'a' && c <= 'z')
            d = (unsigned)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'Z')
            d = (unsigned)(c - 'A' + 10);
        else
            break;
        if (d >= base)
            break;
        v = v * base + d;
        any = 1;
        --width;
        GET();
    }
    if (c != -1) {
        unget(c, ctx);
        --*nread;
    }
    if (!any)
        return 0;
    if (neg)
        v = 0ULL - v;
    if (to)
        *(unsigned long long *)to = v;
    return 1;
}
