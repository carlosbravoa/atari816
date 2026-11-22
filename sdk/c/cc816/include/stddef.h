/* stddef.h - cc816 (Horizon C SDK). size_t and ptrdiff_t are 16 bits: one object is at
 * most 65,535 bytes. */
#ifndef _STDDEF_H
#define _STDDEF_H
#ifndef __SIZE_T
#define __SIZE_T 1
typedef unsigned int size_t;
#endif
#ifndef __PTRDIFF_T
#define __PTRDIFF_T 1
typedef int ptrdiff_t;
#endif
#ifndef __WCHAR_T
#define __WCHAR_T 1
typedef unsigned int wchar_t;
#endif
#ifndef NULL
#define NULL ((void *)0)
#endif
#define offsetof(type, member) ((size_t)&((type *)0)->member)
#endif
