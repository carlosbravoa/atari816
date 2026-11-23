/* wchar.c - cc816's wide string functions (wchar.h): wchar_t is 16 bits. */
#include <wchar.h>
#include <string.h>

size_t wcslen(const wchar_t *s)
{
    const wchar_t *p = s;
    while (*p)
        ++p;
    return (size_t)(p - s);
}

wchar_t *wcscpy(wchar_t *d, const wchar_t *s)
{
    wchar_t *r = d;
    while ((*d++ = *s++) != 0)
        ;
    return r;
}

wchar_t *wcsncpy(wchar_t *d, const wchar_t *s, size_t n)
{
    wchar_t *r = d;
    while (n && *s) {
        *d++ = *s++;
        --n;
    }
    while (n--)
        *d++ = 0;
    return r;
}

wchar_t *wcscat(wchar_t *d, const wchar_t *s)
{
    wcscpy(d + wcslen(d), s);
    return d;
}

int wcscmp(const wchar_t *a, const wchar_t *b)
{
    while (*a && *a == *b) {
        ++a;
        ++b;
    }
    return *a < *b ? -1 : *a > *b;
}

int wcsncmp(const wchar_t *a, const wchar_t *b, size_t n)
{
    for (; n; --n, ++a, ++b) {
        if (*a != *b)
            return *a < *b ? -1 : 1;
        if (!*a)
            break;
    }
    return 0;
}

wchar_t *wcschr(const wchar_t *s, wchar_t c)
{
    for (;; ++s) {
        if (*s == c)
            return (wchar_t *)s;
        if (!*s)
            return NULL;
    }
}

wchar_t *wcsrchr(const wchar_t *s, wchar_t c)
{
    const wchar_t *r = NULL;
    for (;; ++s) {
        if (*s == c)
            r = s;
        if (!*s)
            return (wchar_t *)r;
    }
}

wchar_t *wmemcpy(wchar_t *d, const wchar_t *s, size_t n)
{
    return (wchar_t *)memcpy(d, s, n * sizeof(wchar_t));
}

wchar_t *wmemmove(wchar_t *d, const wchar_t *s, size_t n)
{
    return (wchar_t *)memmove(d, s, n * sizeof(wchar_t));
}

wchar_t *wmemset(wchar_t *d, wchar_t c, size_t n)
{
    wchar_t *p = d;
    while (n--)
        *p++ = c;
    return d;
}

int wmemcmp(const wchar_t *a, const wchar_t *b, size_t n)
{
    for (; n; --n, ++a, ++b)
        if (*a != *b)
            return *a < *b ? -1 : 1;
    return 0;
}

wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n)
{
    for (; n; --n, ++s)
        if (*s == c)
            return (wchar_t *)s;
    return NULL;
}
