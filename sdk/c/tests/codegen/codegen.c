/* codegen.c - the compiler's known trouble spots (docs/c/reference.md, "Compiler
 * notes"): 32-bit values loaded from arrays and through pointers, in both models. hcc
 * repairs the large model's pattern (hzc.fix_asm) and compiles the tiny model with -nox.
 * Prints CODEGEN PASS or CODEGEN FAIL. */
#include <stdio.h>
#include <string.h>

static unsigned checks, fails;
static void check(int ok, const char *what)
{
    ++checks;
    if (!ok) {
        ++fails;
        printf("FAIL: %s\n", what);
    }
}

long ltbl[4] = {0x11112222L, 0x33334444L, -2L, 0x7FFFFFFFL};
unsigned long utbl[3] = {0xDEADBEEFUL, 1UL, 0x80000000UL};
const char *ptbl[3] = {"zero", "one", "two"};
struct rec { int a; long b; char *s; } rtbl[3] = {{1, 100000L, "x"}, {2, -100000L, "yy"}, {3, 7L, "zzz"}};
struct node { int v; struct node *next; long w; };

long getl(int i) { return ltbl[i]; }
unsigned long getu(int i) { return utbl[i]; }
const char *getp(int i) { return ptbl[i]; }
long getb(int i) { return rtbl[i].b; }
char *gets_(int i) { return rtbl[i].s; }
long through(long *p, int i) { return p[i]; }
long chain(struct node *n) { return n->next->w; }
int deref(int **pp, int i) { return *pp[i]; }
long sum(void) { long s = 0; int i; for (i = 0; i < 4; i++) s += ltbl[i]; return s; }

/* lib/stdio.c's pattern: two long arrays, one index, += then a compare (vbcc saved X in Y
 * and then indexed [r0],y with it: hzc.fix_ysave) */
static long posa[8], sizea[8];
int grow(int h, unsigned r)
{
    posa[h] += r;
    if (posa[h] > sizea[h]) {
        sizea[h] = posa[h];
        return 1;
    }
    return 0;
}

/* a pointer member of a static structure, read and written at offset 0 (vbcc read the
 * member's offset there: hzc.fix_nearoff). Tiny model: every pointer is 16 bits; large
 * model: __near ones (the controls library's structures, hui.h). */
#ifdef __MNEAR
#define NEARP
#else
#define NEARP __near
#endif
struct nrec { int a; int b; char NEARP *s; struct nnode NEARP *n; };
struct nnode { int v0; int v1; };
static struct nnode nn = {11, 22};
static char ntext[] = "abc";
static struct nrec nr = {1, 2, ntext, &nn};
int nfirst(void) { return nr.s[0]; }
int nsecond(void) { return nr.s[1]; }
int nfield0(void) { return nr.n->v0; }
int nfield1(void) { return nr.n->v1; }
void nstore(void) { nr.s[0] = 'X'; nr.n->v0 = 33; }

int main(void)
{
    volatile int zero = 0, one = 1, two = 2, three = 3;
    static int x = 5, y = 6;
    static int *pv[2];
    static struct node n2 = {2, 0, 0x22222222L}, n1 = {1, &n2, 0x11111111L};
    char b[40];
    pv[0] = &x;
    pv[1] = &y;
    check(getl(one) == 0x33334444L && getl(two) == -2L && getl(three) == 0x7FFFFFFFL, "long table");
    check(getu(zero) == 0xDEADBEEFUL && getu(two) == 0x80000000UL, "unsigned long table");
    check(!strcmp(getp(one), "one") && !strcmp(getp(two), "two"), "pointer table");
    check(getb(one) == -100000L && getb(two) == 7L, "long field of a struct table");
    check(!strcmp(gets_(two), "zzz"), "pointer field of a struct table");
    check(through(ltbl, three) == 0x7FFFFFFFL, "long through a pointer");
    check(chain(&n1) == 0x22222222L, "long through a chain of pointers");
    check(deref(pv, one) == 6, "pointer table dereferenced");
    check(sum() == (long)(0x11112222UL + 0x33334444UL - 2UL + 0x7FFFFFFFUL), "sum over a long table");
    posa[3] = 100000L;
    sizea[3] = 100050L;
    check(grow(three, 40) == 0 && grow(three, 40) == 1 && sizea[3] == 100080L && posa[3] == 100080L,
          "long arrays: += and compare");
    sprintf(b, "%ld %lu %s", ltbl[one], utbl[two], ptbl[zero]);
    check(!strcmp(b, "858997828 2147483648 zero"), "table values as arguments");
    check(nfirst() == 'a' && nsecond() == 'b', "near pointer member, element 0 and 1");
    check(nfield0() == 11 && nfield1() == 22, "near pointer member, fields at 0 and 2");
    nstore();
    check(ntext[0] == 'X' && nn.v0 == 33 && nn.v1 == 22, "near pointer member, stores at 0");
    printf("codegen: %u checks, %u failures\n", checks, fails);
    printf(fails ? "CODEGEN FAIL\n" : "CODEGEN PASS\n");
    return 0;
}
