/* SPDX-License-Identifier: GPL-3.0-or-later */
/* xcompat.h: given to every upstream file first (-include). Open Watcom's
   16-bit large model on top of the platform: the keywords, the DOS and
   BIOS calls (xdos.h), and on the host (gcc, 64-bit Linux) the C types
   made to behave as the DOS program's where it matters:
   - `long` is 32 bits (#define long int, after the system headers): the
     random numbers (rng.c's 32-bit state), file offsets and every long
     product wrap as on DOS; the printf family is wrapped (xdos.h) so that
     "%ld" still reads the value;
   - `int` stays 32 bits (no compiler flag gives gcc a 16-bit int): code
     that depends on 16-bit wrap-around differs (see PORTING-NOTES.md).
   On the Atari816 (cc816) int is 16 and long 32 bits already. */
#ifndef XCOMPAT_H
#define XCOMPAT_H

/* Every system header an upstream file includes, first: they must not see
   the macros below. */
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>
#include <limits.h>
#include <unistd.h>
#if !defined(__CC816__)
#include <strings.h>
#include <stdint.h>
#include <time.h>
#include <errno.h>
#include <dirent.h>
#endif

/* Upstream's files see XCOM_PORT: the port's changes (patches/src-*.patch). */
#define XCOM_PORT 1

/* ---------------------------------------------------------------- keywords */
#if defined(__CC816__)
#define far         __far
#define huge        __far
#else
#define __far
#define far
#define huge
#define __huge
#endif
#define __near
#define near
#define __cdecl
#define __pascal
#define __interrupt
#define __loadds
#define __saveregs
#define _Seg16

#if !defined(__CC816__)
/* 32-bit long, as on DOS (see above); a long long is not used upstream. */
#define long int
#endif

#include "xdos.h"
#include "xport.h"

#endif
