/* mem.h - Turbo C's: string.h's block functions, and setmem */
#ifndef XMEM_H
#define XMEM_H
#include <string.h>
#define setmem(p, n, v) memset((p), (v), (n))
#endif
