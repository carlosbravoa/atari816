/* r004_coalesce32.c - 32-bit results that take their operand's place (the register
 * allocator coalesces the result of a two-word add, sub, logic op, shift, multiply or
 * divide with an operand: each word of the operand must be read before that word of the
 * result is written), checked against values computed on the host. */
int main(void)
{
    unsigned long x = 12345, s = 0, t = 7, u;
    unsigned i;
    for (i = 0; i < 300; i++) {
        x = x * 1103515245UL + 12345UL;
        s += (x >> 16) & 0x7FFF;
        s ^= x / 7;
        t = (t << 3) | (t >> 29);
        t = t - x;
        t ^= ~s;
        u = -t;
        t = u + s;
        s = (i & 1) ? s >> 1 : s * 3;
    }
    return x == 924520333UL && s == 847688129UL && t == 2969373414UL ? 0 : 1;
}
