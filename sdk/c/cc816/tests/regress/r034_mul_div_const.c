/* r034_mul_div_const.c - multiplies by constants with many one-bits and signed divides by
 * powers of two, now done inline (shifts with adds or subtracts: x * 31 = x * 32 - x; a
 * signed x / 16 = (x + 15 if negative) >> 16 arithmetically) instead of calling __mul16
 * and __sdiv16: the Xargon port spent 13 % of its time there (its objects are 31-byte
 * structures, its positions are divided by 16). Checked against the plain helpers' results
 * (a variable divisor or factor) for many values, negative ones and the edges.
 * LEVELS: 0 1 2 */
static volatile int vk;

static int ok_mul(int x)
{
    int k;
    k = vk + 31;   if (x * 31 != x * k) return 0;
    k = vk + 15;   if (x * 15 != x * k) return 0;
    k = vk + 23;   if (x * 23 != x * k) return 0;
    k = vk + 29;   if (x * 29 != x * k) return 0;
    k = vk + 63;   if (x * 63 != x * k) return 0;
    k = vk + 255;  if (x * 255 != x * k) return 0;
    k = vk + 7;    if (x * 7 != x * k) return 0;
    k = vk + 96;   if (x * 96 != x * k) return 0;
    k = vk + 1000; if (x * 1000 != x * k) return 0;
    k = vk + 3;    if ((unsigned)x * 3u != (unsigned)x * (unsigned)k) return 0;
    k = vk + 0x7FFF; if (x * 0x7FFF != x * k) return 0;
    k = vk - 31;   if (x * -31 != x * k) return 0;
    return 1;
}

static int ok_div(int x)
{
    int k;
    k = vk + 2;    if (x / 2 != x / k) return 0;
    k = vk + 4;    if (x / 4 != x / k) return 0;
    k = vk + 16;   if (x / 16 != x / k) return 0;
    k = vk + 256;  if (x / 256 != x / k) return 0;
    k = vk + 512;  if (x / 512 != x / k) return 0;
    k = vk + 0x4000; if (x / 0x4000 != x / k) return 0;
    k = vk + 8;    if (x % 8 != x % k) return 0;
    return 1;
}

int main(void)
{
    static const int edge[] = { 0, 1, -1, 2, -2, 15, -15, 16, -16, 17, -17, 31, -31, 255,
                                -255, 256, -256, 1000, -1000, 32767, -32767, -32768,
                                16383, -16384, 12345, -12345 };
    unsigned i;
    int x;
    for (i = 0; i < sizeof edge / sizeof edge[0]; i++) {
        if (!ok_mul(edge[i]))
            return 1;
        if (!ok_div(edge[i]))
            return 2;
    }
    for (x = -32768; ; x += 97) {       /* (a walk over the whole range) */
        if (!ok_mul(x))
            return 3;
        if (!ok_div(x))
            return 4;
        if (x > 32767 - 97)
            break;
    }
    if ((-17) / 16 != -1 || (-16) / 16 != -1 || (-15) / 16 != 0 || 17 / 16 != 1)
        return 5;
    {
        volatile int m = -17;
        int y = m;
        if (y / 16 != -1 || y / 2 != -8 || (y * 31) != -527)
            return 6;
    }
    return 0;
}
