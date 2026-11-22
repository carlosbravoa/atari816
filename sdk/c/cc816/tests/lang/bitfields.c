/* bitfields.c - bit-fields: signed and unsigned, several storage units, long fields
 * wider than 16 bits, in unions, a zero width, wrapping on assignment. */
struct flags {
    unsigned a : 3;
    signed b : 4;
    unsigned c : 9;         /* 3 + 4 + 9: the first unit (16 bits) is full */
    int d : 1;
    unsigned : 0;           /* the next field starts a new unit */
    unsigned e : 5;
};
struct wide { unsigned long x : 20; long y : 12; unsigned char z : 3; };
union both { unsigned all; struct { unsigned lo : 8, hi : 8; } p; };

int main(void)
{
    struct flags f = { 5, -3, 300, -1, 17 };
    struct wide w = { 0xFFFFFL, -2048, 7 };
    union both u;
    if (f.a != 5 || f.b != -3 || f.c != 300 || f.d != -1 || f.e != 17)
        return 1;
    f.a = 9;                /* 9 & 7 = 1 */
    f.b = 8;                /* 8 in a signed 4-bit field: -8 */
    f.c += 300;             /* 600 & 511 = 88 */
    if (f.a != 1 || f.b != -8 || f.c != 88)
        return 2;
    if (w.x != 0xFFFFFL || w.y != -2048 || w.z != 7)
        return 3;
    w.x++;
    w.y = 2047;
    if (w.x != 0 || w.y != 2047)
        return 4;
    u.all = 0x1234;
    if (u.p.lo != 0x34 || u.p.hi != 0x12)
        return 5;
    u.p.hi = 0xAB;
    if (u.all != 0xAB34)
        return 6;
    if (sizeof(struct flags) != 2 + 2 + 2 || sizeof(struct wide) != 4 + 1)
        return 7;
    return 0;
}
