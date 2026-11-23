/* asmfar.c - C and movable assembly (asmfar.s: rt/model.inc's FUNC). Built with
 * hcc --code large, hcc may put each assembly function in another bank, as it does a C
 * function; built for the small code model, the same file is ordinary assembly.
 *
 *   make                    the small code model
 *   make HZ_CODE=large HCCFLAGS="--main-room 0"     every movable function in other banks
 *
 * The assembly reads a global of the main bank (scale), calls a C function back (twice),
 * calls through a function pointer, has a jump table, and takes the bank of the main
 * bank (#^scale, recorded with XBANK). */
#include <stdio.h>

int scale = 3;

int twice(int x)
{
    return 2 * x;
}

/* asmfar.s */
int asm_sum(const int *v, int n);       /* twice(the sum of v[i] * scale) */
int asm_op(int op, int a, int b);       /* 0 a + b, 1 a - b, 2 the larger, else -1 */
int asm_apply(int (*f)(int), int x);    /* f(x) */
int (*asm_twice_ptr(void))(int);        /* twice's 16-bit address, from assembly */
int (*asm_op_ptr(void))(int, int, int); /* asm_op's */
unsigned asm_where(void);               /* PBR << 8 | 1 when #^scale is the main bank */
unsigned asm_main_bank(void);           /* the main bank's number (__cbank) */

static int checks, fails;

static void check(int ok, const char *what)
{
    checks++;
    if (!ok) {
        fails++;
        printf("FAIL %s\n", what);
    }
}

static int add1(int x)
{
    return x + 1;
}

int main(void)
{
    static int v[4] = { 1, 2, 3, 4 };
    int (*sum)(const int *, int) = asm_sum;
    unsigned w;

    check(asm_sum(v, 4) == 60, "asm_sum: (1+2+3+4) * 3 * 2");
    check(asm_sum(v, 0) == 0, "asm_sum of none");
    scale = 5;
    check(sum(v, 4) == 100, "asm_sum through a pointer, scale 5");
    check(asm_op(0, 7, 5) == 12, "asm_op add");
    check(asm_op(1, 7, 5) == 2, "asm_op sub");
    check(asm_op(2, 7, 9) == 9, "asm_op max");
    check(asm_op(3, 7, 5) == -1, "asm_op bad");
    check(asm_apply(add1, 41) == 42, "asm_apply(add1, 41)");
    check(asm_apply(asm_twice_ptr(), 21) == 42, "asm_apply(asm_twice_ptr(), 21)");
    check(asm_op_ptr()(2, 3, 8) == 8, "asm_op through asm_op_ptr()");
    w = asm_where();
    check(w & 1, "#^scale: the main bank");
    printf("asmfar: asm_where in bank $%02X, the main bank $%02X\n", w >> 8,
           asm_main_bank());
    printf("asmfar: %d checks, %d failures\n", checks, fails);
    if (!fails)
        printf("ASMFAR PASS\n");
    return fails != 0;
}
