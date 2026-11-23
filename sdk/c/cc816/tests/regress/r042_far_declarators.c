/* r042_far_declarators.c - DOS compilers' declarators (ports/xcom, PORTING-NOTES.md
 * section 4, items 3 and 4): a far qualifier before a later declarator's '*' (`T __far *a,
 * __far *b;`, `int n = 1, __far *p;`) was refused ("Invalid declarator"); it applies to
 * that declarator. A far function pointer `void (__far *f)(void)` was refused; it is
 * accepted (__far ignored, with a warning: a function pointer is the main-bank entry). A
 * qualified pointer to a structure declared before the structure is defined (`struct n
 * __near *p;` then `struct n {...};`) did not see the definition. Also the DOS spellings
 * _far, __huge, _near. */
// FLAGS: -w
#include <horizon.h>

unsigned char __far *pa, __far *pb;
int n1 = 1, __far *pn;
static void (__far *fp)(void);
struct node __near *later;
struct node { int v0, v1; };
static struct node nd = { 11, 22 };
char _far *dosf;
char __huge *dosh;
struct two { unsigned char __far *a, __far *b; int k; };

static int hit;
static void f(void) { hit++; }

int main(void)
{
    unsigned char __far *bank = hz_far_alloc();
    struct two t;
    int x = 5, __far *xp;
    if (!bank)
        return 1;
    pa = bank;
    pb = bank + 1;
    *pa = 3;
    *pb = 4;
    if (sizeof pa != 4 || sizeof pb != 4 || pa[1] != 4 || sizeof pn != 4)
        return 2;
    fp = f;
    fp();
    if (hit != 1 || sizeof fp != 2)
        return 3;
    later = &nd;
    if (later->v1 != 22 || sizeof *later != 4)
        return 4;
    t.a = bank;
    t.b = bank + 1;
    if (sizeof t != 10 || *t.b != 4)
        return 5;
    xp = &x;
    if (*xp != 5 || sizeof xp != 4 || sizeof dosf != 4 || sizeof dosh != 4 || n1 != 1)
        return 6;
    hz_far_free(bank);
    return 0;
}
