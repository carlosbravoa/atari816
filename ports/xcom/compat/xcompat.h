/* SPDX-License-Identifier: GPL-3.0-or-later */
/* xcompat.h: given to every upstream file first (-include). Open Watcom's
   16-bit large model on top of the platform: the keywords, the DOS and
   BIOS calls (xdos.h), and on the host (gcc, 64-bit Linux) the C types
   made to behave as the DOS program's where it matters:
   - `long` is 32 bits (#define long int, after the system headers): the
     random numbers (rng.c's 32-bit state), file offsets and every long
     product wrap as on DOS; the printf family is wrapped (xdos.h) so that
     "%ld" still reads the value;
   - `int` is 16 bits: no compiler flag gives gcc a 16-bit int, so the host
     compiles copies of the files in which tools/host16.py made `int` a
     `short` and `unsigned` an `unsigned short` (main, va_arg's type and
     lines marked "host16: native" keep the native int); structures are
     packed (#pragma pack(1) below), as cc816's are. Expressions still
     promote to the 32-bit int (PORTING-NOTES.md, "The host build");
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
#if defined(__CC816_FAR_DATA__)
/* cc816's far data model (hcc --data far): every plain pointer is far, as the engine's
   were on DOS. Its __near objects (hot data in DGROUP) are writable globals, which stay in
   the main bank anyway; its __near pointers become far ones (one pointer kind: an
   address of a far object never loses its bank). */
#undef __near
#define XD_FAR_DATA 1
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
#define long int    /* host16: native */
/* The host compiles tools/host16.py's copies of the files: int is short there (16
   bits, as on DOS), and every structure from here on is packed as cc816 packs them
   (the C library's headers above, and any included later, keep their layout: the copy
   wraps each #include <...> in the default packing). */
#pragma pack(1)
#endif

#include "xdos.h"
#include "xport.h"

#endif
