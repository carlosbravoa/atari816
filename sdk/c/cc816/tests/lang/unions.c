/* unions.c - unions: the members share their bytes, sizes, the first member
 * initialised, a designated member, in structures. */
union word { unsigned int w; unsigned char b[2]; };
union any { long l; float f; char c; int a[3]; };
struct tagged { int kind; union { int i; long l; } v; };

static union word gw = { 0x1234 };
static union any ga = { .c = 'x' };
static struct tagged gt = { 2, { .l = 70000L } };

int main(void)
{
    union word w;
    union any a;
    w.w = 0xABCD;
    if (w.b[0] != 0xCD || w.b[1] != 0xAB)       /* little-endian */
        return 1;
    if (sizeof(union word) != 2 || sizeof(union any) != 6 || sizeof(struct tagged) != 6)
        return 2;
    if (gw.b[0] != 0x34 || ga.c != 'x' || gt.v.l != 70000L || gt.kind != 2)
        return 3;
    a.l = 0x3F800000L;
    if (a.f != 1.0f)
        return 4;
    a.a[2] = 5;
    if (a.a[2] != 5)
        return 5;
    w = gw;
    if (w.w != 0x1234)
        return 6;
    return 0;
}
