/* r011_float_helper_addr.c - float operations whose operands and result are given to the
 * runtime helper by their direct-page addresses (ldx #__rg+k: gen.py's ...i and ...x
 * entries). Two faults while they were added: the peephole pass did not count
 * "ldx #__rg+0" as a read of both words, so it dropped the store of a parameter's high
 * word (a + b of two parameters gave garbage); and __rg+0's address, 0, was taken for "no
 * destination", so a result meant for __rg+0 was not stored ((a * z) / (a * z) gave
 * a / (a * z)). Found by tests/float before the change reached a release. */
static float add(float a, float b) { return a + b; }
static float quo(float x, float y) { return (x * y) / (x * y); }
volatile float a = 1.0f, two = 2.0f, three = 3.0f, nz = -0.0f;

static unsigned long bits(float f)
{
    union { float f; unsigned long u; } v;
    v.f = f;
    return v.u;
}

int main(void)
{
    if (add(1.5f, -2.25f) != -0.75f || add(two, three) != 5.0f)
        return 1;
    if ((a * two) / (three * two) != 1.0f / 3.0f)
        return 2;
    if ((two * three) / (a * two) != 3.0f || (two * three) - (a * two) != 4.0f)
        return 3;
    if (bits((a * nz) / (a * nz)) != 0xFFC00000UL || bits(quo(a, nz)) != 0xFFC00000UL)
        return 4;                       /* -0 / -0: the default NaN */
    if (quo(two, three) != 1.0f)
        return 5;
    return 0;
}
