/* xcompat.h - Borland Turbo C's names for Xargon's files on Horizon (hcc -include: before
 * every upstream file). The DOS headers themselves (dos.h, conio.h, io.h, alloc.h, mem.h)
 * are in compat/; what they declare is in hz_dos.c. */
#ifndef XCOMPAT_H
#define XCOMPAT_H
#include <stdlib.h>
#include <string.h>

/* Turbo C's memory model keywords: a far pointer is cc816's __far */
#define far __far
#define near
#define huge __far

/* Turbo C's stdlib.h */
#ifndef max
#define max(a, b) (((a) > (b)) ? (a) : (b))
#define min(a, b) (((a) < (b)) ? (a) : (b))
#endif
char *itoa(int v, char *s, int radix);
char *ltoa(long v, char *s, int radix);
char *ultoa(unsigned long v, char *s, int radix);
/* Turbo C's rand (its sequence: the recorded demo replays only with it) and random(n) */
int bc_rand(void);
void bc_srand(unsigned seed);
#define rand() bc_rand()
#define srand(s) bc_srand(s)
#define random(n) ((int)(((long)bc_rand() * (n)) / 0x8000L))

/* the BIOS's tick counter at 0040:006C, which upstream reads (and waits on) through the
 * pointer myclock: hz_frame.c's, a function (declared by upstream's own declarations of
 * myclock, int * or char *) */
#define myclock (hzc_tick())

/* upstream's main is started by horizon/hz_main.c */
#define main xargon_main
#endif
