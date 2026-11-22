/* asm.c - inline assembly: a memory fill loop, locals and parameters read and written
 * through %[name] (int, char, long, a near and a far pointer), globals by their
 * assembler name and by %[name], an enumerator, a .macro from a file-scope asm, a C
 * function called from assembly, values kept across asm statements, a naked function,
 * @labels in two asm statements of one function. */
#include <horizon.h>
#include <string.h>

unsigned counter = 5;
static unsigned char buf[64];
enum { STEP = 7 };

asm(".macro ADD2\n"
    "\tclc\n"
    "\tadc #2\n"
    ".endmacro");

int twice(int x) { return 2 * x; }

/* unsigned add3(a, b, c): the arguments at 3,s 5,s 7,s, the result in A */
__attribute__((naked)) unsigned add3(unsigned a, unsigned b, unsigned c)
{
    __asm__("\tlda 3,s\n"
            "\tclc\n"
            "\tadc 5,s\n"
            "\tclc\n"
            "\tadc 7,s\n"
            "\trts");
}

/* the fill loop of a porter: 8-bit stores, Y the index (scratch: no need to keep it) */
static void fill(unsigned char *p, unsigned n, unsigned char v)
{
    asm volatile("\tldy #0\n"
                 "\tsep #$20\n"
                 "\tlda %[v]\n"
                 "@l:\tcpy %[n]\n"
                 "\tbcs @d\n"
                 "\tsta (%[p]),y\n"
                 "\tiny\n"
                 "\tbra @l\n"
                 "@d:\trep #$20");
}

static unsigned sum_far(unsigned char __far *fp, unsigned n)
{
    unsigned s = 0;
    asm("\tldy #0\n"
        "\tstz __rg+0\n"            /* a scratch register: free to use */
        "@l:\tcpy %[n]\n"
        "\tbcs @d\n"
        "\tlda [%[fp]],y\n"
        "\tand #$00FF\n"
        "\tclc\n"
        "\tadc __rg+0\n"
        "\tsta __rg+0\n"
        "\tiny\n"
        "\tbra @l\n"
        "@d:\tlda __rg+0\n"
        "\tsta %[s]");
    return s;
}

int main(void)
{
    int x = 10, y = 0, r = 0, i;
    long big = 100000L;
    char c = 'a';
    long kept = 0x12345678L;
    unsigned char __far *far = hz_far_alloc();
    int bad = 0;

    asm("\tlda %[x]\n\tclc\n\tadc #%[STEP]\n\tsta %[y]");
    bad |= (y != 17);
    asm("\tlda _counter\n\tADD2\n\tsta %[counter]");
    bad |= (counter != 7) << 1;
    fill(buf, 50, 0x5A);
    bad |= (buf[0] != 0x5A || buf[49] != 0x5A || buf[50] != 0) << 2;
    asm("\tlda %[big]\n\tclc\n\tadc #1\n\tsta %[big]\n"
        "\tlda %[big]+2\n\tadc #0\n\tsta %[big]+2");
    bad |= (big != 100001L) << 3;
    asm("\tlda #$1234\n\tsta %[c]");    /* a char: made a valid char again after it */
    bad |= (c != 0x34) << 4;
    asm("\tpei (%[x])\n\tjsr _twice\n\tply\n\tsta %[r]");      /* a C function */
    bad |= (r != 20) << 5;
    bad |= (add3(1, 20, 300) != 321) << 6;
    for (i = 0; i < 3; i++)                                    /* in a loop */
        asm("\tlda %[x]\n\tasl a\n\tsta %[x]");
    bad |= (x != 80) << 7;
    bad |= (kept != 0x12345678L) << 8;
    if (far) {
        for (i = 0; i < 10; i++)
            far[i] = (unsigned char)(i * 3);
        bad |= (sum_far(far, 10) != 135) << 9;
        hz_far_free(far);
    }
    return bad;
}
