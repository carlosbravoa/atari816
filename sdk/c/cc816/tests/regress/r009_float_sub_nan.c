/* r009_float_sub_nan.c - a - b with b a NaN gives b (made quiet) with its own sign, as an
 * IEEE operation does (x86 too); cc816's __fsub negated b first, so the NaN's sign
 * flipped. Found by tests/fpu (genfp.py). Also checks the other NaN and signed-zero
 * results of + and - the runtime promises. */
static unsigned long bits(float f)
{
    union { float f; unsigned long u; } v;
    v.f = f;
    return v.u;
}

static float mk(unsigned long u)
{
    union { float f; unsigned long u; } v;
    v.u = u;
    return v.f;
}

int main(void)
{
    volatile float nan = mk(0x7F800001UL), nn = mk(0xFFC00005UL), one = 1.0f;
    volatile float pz = 0.0f, nz = mk(0x80000000UL);
    if (bits(one - nan) != 0x7FC00001UL)
        return 1;                       /* the NaN, quiet, sign kept */
    if (bits(one - nn) != 0xFFC00005UL)
        return 2;
    if (bits(nan - one) != 0x7FC00001UL || bits(nan + nn) != 0x7FC00001UL)
        return 3;                       /* the first NaN */
    if (bits(nz - pz) != 0x80000000UL || bits(pz - pz) != 0 || bits(nz + nz) != 0x80000000UL)
        return 4;                       /* -0 - 0 = -0, 0 - 0 = +0, -0 + -0 = -0 */
    if (bits(one - one) != 0)
        return 5;                       /* x - x = +0 */
    return 0;
}
