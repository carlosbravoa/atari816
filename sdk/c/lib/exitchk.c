/* exitchk.c - the stack checks (rt/crt0.s calls __hz_exitchk just before SYS_EXIT).
 *
 * The stack grows down from just below the argument string to its lowest address,
 * ___hz_stklo: window $0100 in the large model (about 32 KB of stack), WEND in the tiny
 * model ($7000 by default: about 4 KB). The startup fills the lowest 256 bytes (the guard
 * zone) with a pattern; if any of it changed at exit, the stack came within 256 bytes of
 * its end or past it (into the large model's direct page, the tiny model's heap and data)
 * and the program says so on the console. Only a write into the zone is seen: a local
 * array of more than 256 bytes that is never written can jump over it. Linked with hcc
 * --debug, the startup paints the whole stack and the exit reports the most the program
 * used ("stack: 1234 of 31900 bytes used").
 */
#include <horizon.h>

#define HZ_GUARD  0xC35A
#define HZ_PAINTW 0xA5A5
#define ZONE 256

#ifdef __CC816__
/* cc816 (one memory model) has two stacks: the hardware stack in the window (return
 * addresses, arguments, spilled registers) from $0100 to S at the start, and the software
 * stack in the code bank (arrays, structures, locals whose address is taken) from
 * __hz_sslo to $FFF0 (hcc --stack N). rt/cc816/crt0.s fills both guard zones (and paints
 * both stacks with --debug), and has hz_stack_free() and hz_sstack_free(). */
#define HSLO  0x0100
#define SSTOP 0xFFF0
extern unsigned __hz_stktop, __hz_sslo, __hz_paintflag, __hz_heappeak;
extern char *__hz_heapstart, *__hz_heapend;

static unsigned __far *win(unsigned off)
{
    return (unsigned __far *)HZ_FARPTR(0, off);
}

static int hard_ok(void)
{
    unsigned a;
    for (a = HSLO; a < HSLO + ZONE; a += 2)
        if (*win(a) != HZ_GUARD)
            return 0;
    return 1;
}

static int soft_ok(void)
{
    const unsigned *p = (const unsigned *)__hz_sslo;
    unsigned i;
    for (i = 0; i < ZONE / 2; ++i)
        if (p[i] != HZ_GUARD)
            return 0;
    return 1;
}

int hz_stack_check(void)
{
    return hard_ok() && soft_ok() ? 0 : -1;
}

static char *utoa_(unsigned v, char *end)
{
    *end = 0;
    do {
        *--end = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    return end;
}

static void say(const char *a, unsigned v, const char *b, unsigned w, const char *c)
{
    char n1[8], n2[8];
    hz_puts(a);
    hz_puts(utoa_(v, n1 + 7));
    if (b) {
        hz_puts(b);
        hz_puts(utoa_(w, n2 + 7));
    }
    hz_puts(c);
}

void __hz_exitchk(void)
{
    unsigned a;
    const unsigned *p;
    if (!hard_ok())
        say("\nstack overflow: the guard zone at window address ", HSLO, 0, 0,
            " (the stack's last 256 bytes) was written; the program used more stack "
            "than it has (docs/c/reference.md, \"The stacks\")\n");
    if (!soft_ok())
        say("\nstack overflow: the software stack's guard zone at ", __hz_sslo, 0, 0,
            " (its last 256 bytes, in the code bank) was written; the program's arrays, "
            "structures and locals whose address is taken need more: hcc --stack N "
            "(docs/c/reference.md, \"The stacks\")\n");
    if (__hz_paintflag) {
        for (a = HSLO + ZONE; a < __hz_stktop && *win(a) == HZ_PAINTW; a += 2)
            ;
        say("stack: ", __hz_stktop - a, " of ", __hz_stktop - HSLO - ZONE, " bytes used\n");
        for (p = (const unsigned *)(__hz_sslo + ZONE); p < (const unsigned *)SSTOP &&
             *p == HZ_PAINTW; ++p)
            ;
        say("software stack: ", SSTOP - (unsigned)p, " of ", SSTOP - __hz_sslo - ZONE,
            " bytes used\n");
        say("heap: ", __hz_heappeak, " of ", (unsigned)(__hz_heapend - __hz_heapstart),
            " bytes used at most (malloc; a file open with fopen takes 1 KB)\n");
    }
}

#else

extern char __hz_stklo[], __hz_paint[];   /* linker symbols: their addresses are values */
extern unsigned __hz_stktop;

static unsigned stklo(void)
{
    return HZ_OFF(__hz_stklo);
}

static unsigned __far *win(unsigned off)
{
    return (unsigned __far *)HZ_FARPTR(0, off);
}

int hz_stack_check(void)
{
    unsigned a, lo = stklo();
    for (a = lo; a < lo + ZONE; a += 2)
        if (*win(a) != HZ_GUARD)
            return -1;
    return 0;
}

unsigned hz_stack_free(void)
{
    char here;
    return HZ_OFF(&here) - stklo();
}

static char *utoa_(unsigned v, char *end)
{
    *end = 0;
    do {
        *--end = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    return end;
}

static void say(const char *a, unsigned v, const char *b, unsigned w, const char *c)
{
    char n1[8], n2[8];
    hz_puts(a);
    hz_puts(utoa_(v, n1 + 7));
    if (b) {
        hz_puts(b);
        hz_puts(utoa_(w, n2 + 7));
    }
    hz_puts(c);
}

void __hz_exitchk(void)
{
    unsigned lo = stklo(), a;
    if (hz_stack_check())
        say("\nstack overflow: the guard zone at window address ", lo, 0, 0,
            " (the stack's last 256 bytes) was written; the program used more stack "
            "than it has (docs/c/reference.md, \"The stack\")\n");
    if (HZ_OFF(__hz_paint)) {
        for (a = lo + ZONE; a < __hz_stktop && *win(a) == HZ_PAINTW; a += 2)
            ;
        say("stack: ", __hz_stktop - a, " of ", __hz_stktop - lo - ZONE,
            " bytes used\n");
    }
}

#endif
