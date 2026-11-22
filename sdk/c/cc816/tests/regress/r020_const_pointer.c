/* r020_const_pointer.c - a pointer variable holding a constant address (p = (char *)0x100;
 * *p), near or far: the optimiser put the constant in the access and the code generator
 * stopped with an internal error ("address base #256"). Found by compiling mutated test
 * programs (tests/diag's robustness check). */
int main(void)
{
    unsigned char *p = (unsigned char *)0x100;      /* the program's first bytes */
    unsigned char __far *f = (unsigned char __far *)0x00000100L;   /* the window's */
    volatile unsigned k = 0x100;
    volatile unsigned long kf = 0x100;
    unsigned char *q = (unsigned char *)k;
    unsigned char __far *g = (unsigned char __far *)kf;
    if (p[0] != q[0] || p[3] != q[3] || *p != *q)
        return 1;
    if (f[0] != g[0] || f[5] != g[5])
        return 2;
    return 0;
}
