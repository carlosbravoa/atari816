/* r010_float_init_conv.c - an initialiser or assignment of another arithmetic type,
 * without a cast: int e = 97.0; char c = 97.0; long l = 2.5; float f = 'a'; and the
 * same through variables. cc816 first moved a float constant into the 16-bit register
 * by its low word (int e = 97.0; gave 0), a mistake of the fix for r008. Found by the
 * c-testsuite (00175.c). */
static int gi(double d) { int e = d; return e; }

int main(void)
{
    volatile double v = 97.75;
    volatile long big = 123456789L;
    int e = 97.0;
    char c = 97.0;
    long l = 2.5;
    unsigned u = 65535.0;
    float f = 'a', g = 97, h = big;
    int i;
    double w;
    i = 97.9;
    w = 3;
    if (e != 97 || c != 97 || l != 2L || u != 65535u || i != 97)
        return 1;
    if (f != 97.0f || g != 97.0f || h != 123456792.0f || w != 3.0)
        return 2;
    if (gi(v) != 97 || gi(-v) != -97)
        return 3;
    {
        int k = v;
        long m = -v;
        unsigned char b = v;
        if (k != 97 || m != -97L || b != 97)
            return 4;
    }
    return 0;
}
