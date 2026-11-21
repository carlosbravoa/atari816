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

#define ZONE 256

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
