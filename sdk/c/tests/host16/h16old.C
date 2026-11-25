/* h16old.C - host16.py's test of old C (a DOS program's: FILE.C, K&R definitions,
 * implicit int, functions called before their declaration, C library functions declared
 * again, a structure first named in a prototype) and of a port's fix-ups (h16old.fix).
 * Built on the PC through host16.py with h16lib.c, it prints one line per check that
 * fails, then "host16 old C: N failures"; without the fix-ups two checks fail. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "h16old.h"

struct box { int w, h; };

static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)

int main(void)
{
    int pair[2];
    struct box b;
    char buf[8];
    unsigned u = 65535u;
    int minus_one = 0;
    CHECK(twice(21) == 42);
    CHECK(scale(6, 7) == 42);
    CHECK(widen(0x1234, 5) == 0x51234L);
    fill_pair(pair, 3, 4);
    CHECK(pair[0] == 3 && pair[1] == 4);
    b.w = 6;
    b.h = 7;
    CHECK(box_area(&b) == 42);
    CHECK(later(20) == 21);             /* called before its declaration */
    CHECK(sizeof(later(0)) == 2);       /* (C89's implicit int: 16 bits) */
    CHECK(abs(-5) == 5);
    strcpy(buf, "ok");
    CHECK(buf[0] == 'o' && buf[2] == 0);
    CHECK(counted() == 7);              /* 3 + sizeof(short) + sizeof(short) */
    /* a 16-bit unsigned against -1: equal on the Atari816 (-1 is 0xFFFF there); the PC
       promotes both to a 32-bit int (a fix-up) */
    if (u == -1)
        minus_one = 1;
    CHECK(minus_one);
    CHECK(is_high_code((int)0x9000u));         /* (h16old.h: a fix-up) */
#ifndef __OPTIMIZE__
    CHECK(!"the preprocessor saw -O1 (__OPTIMIZE__)");
#endif
    printf("host16 old C: %d failures\n", fails);
    return fails != 0;
}

int later(int v)
{
    return v + 1;
}
