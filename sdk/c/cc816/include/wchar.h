/* wchar.h - cc816 (Horizon C SDK). wchar_t is 16 bits (unsigned int): a character of
 * Unicode's first plane. L"..." strings are read from a UTF-8 source. Only the string and
 * memory functions are here (no locale, no wide input or output). */
#ifndef _WCHAR_H
#define _WCHAR_H
#ifndef __SIZE_T
#define __SIZE_T 1
typedef unsigned int size_t;
#endif
#ifndef __WCHAR_T
#define __WCHAR_T 1
typedef unsigned int wchar_t;
#endif
typedef unsigned int wint_t;
typedef struct { int __state; } mbstate_t;
#ifndef NULL
#define NULL ((void *)0)
#endif
#define WCHAR_MIN 0
#define WCHAR_MAX 0xFFFFu
#define WEOF ((wint_t)0xFFFFu)

size_t wcslen(const wchar_t *s);
wchar_t *wcscpy(wchar_t *d, const wchar_t *s);
wchar_t *wcsncpy(wchar_t *d, const wchar_t *s, size_t n);
wchar_t *wcscat(wchar_t *d, const wchar_t *s);
int wcscmp(const wchar_t *a, const wchar_t *b);
int wcsncmp(const wchar_t *a, const wchar_t *b, size_t n);
wchar_t *wcschr(const wchar_t *s, wchar_t c);
wchar_t *wcsrchr(const wchar_t *s, wchar_t c);
wchar_t *wmemcpy(wchar_t *d, const wchar_t *s, size_t n);
wchar_t *wmemmove(wchar_t *d, const wchar_t *s, size_t n);
wchar_t *wmemset(wchar_t *d, wchar_t c, size_t n);
int wmemcmp(const wchar_t *a, const wchar_t *b, size_t n);
wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n);
#endif
