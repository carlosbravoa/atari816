/* r030_uchar_compare.c - a compare of an unsigned char (promoted to int: 0-255) with a
 * constant of 0 or more, or with another unsigned char, is done unsigned (cheaper: no
 * sign flip); with a negative constant or a signed value it must stay signed. */
static volatile unsigned char c200 = 200, c0 = 0, c255 = 255;
static volatile int neg = -5;
static volatile unsigned short us = 40000u;

int main(void)
{
    unsigned char i;
    unsigned n = 0;
    if (!(c200 < 201) || c200 < 200 || !(c200 > 100) || c200 > 200)
        return 1;
    if (!(c200 > -1) || c0 < -1 || !(c0 >= 0) || !(c255 <= 255) || c255 > 254 == 0)
        return 2;
    if (!(c0 > neg) || c200 < neg)
        return 3;
    if (!(c200 < c255) || c255 < c200 || c0 > c200)
        return 4;
    if (!(c255 < 32767) || c255 >= 300)
        return 5;
    if (!(us > c200) || us < 39999u)
        return 6;
    for (i = 0; i < 200; i++)
        n++;
    if (n != 200)
        return 7;
    for (i = 250; i >= 245 && i <= 255; i++)    /* wraps to 0 after 255 */
        n++;
    if (n != 206)
        return 8;
    return 0;
}
