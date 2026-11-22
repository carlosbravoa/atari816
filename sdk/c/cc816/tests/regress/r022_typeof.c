/* r022_typeof.c - typeof (GNU C, and __typeof__) was refused with a syntax error: the
 * vendored pycparser knows it only in its C23 mode. cc816's documentation said it was
 * there. Found while writing tests/lang/gnuext.c. */
int main(void)
{
    long x = 70000L;
    typeof(x) y = x + 1;
    __typeof__(int) z = 2;
    typeof(&x) p = &x;
    if (sizeof y != 4 || y != 70001L || z != 2 || *p != 70000L)
        return 1;
    return 0;
}
