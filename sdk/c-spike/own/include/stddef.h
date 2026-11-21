#ifndef _STDDEF_H
#define _STDDEF_H
typedef unsigned int size_t;
typedef int ptrdiff_t;
typedef unsigned char wchar_t;
#ifndef NULL
#define NULL ((void *)0)
#endif
#define offsetof(t, m) ((size_t)&((t *)0)->m)
#endif
