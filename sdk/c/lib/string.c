/* string.c - string.h for cc816 (memcpy, memmove, memset, strlen, strcpy and memcmp are
 * rt/cc816/mem.s). */
#include <string.h>
#include <stdlib.h>

void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = s;
    unsigned char ch = (unsigned char)c;
    for (; n; --n, ++p)
        if (*p == ch)
            return (void *)p;
    return 0;
}

char *strncpy(char *d, const char *s, size_t n)
{
    char *r = d;
    while (n && *s) {
        *d++ = *s++;
        --n;
    }
    while (n--)
        *d++ = 0;
    return r;
}

char *strcat(char *d, const char *s)
{
    strcpy(d + strlen(d), s);
    return d;
}

char *strncat(char *d, const char *s, size_t n)
{
    char *p = d + strlen(d);
    while (n-- && *s)
        *p++ = *s++;
    *p = 0;
    return d;
}

int strcmp(const char *a, const char *b)
{
    const unsigned char *p = (const unsigned char *)a, *q = (const unsigned char *)b;
    while (*p && *p == *q) {
        ++p;
        ++q;
    }
    return *p < *q ? -1 : *p > *q;
}

int strncmp(const char *a, const char *b, size_t n)
{
    const unsigned char *p = (const unsigned char *)a, *q = (const unsigned char *)b;
    for (; n; --n, ++p, ++q) {
        if (*p != *q)
            return *p < *q ? -1 : 1;
        if (!*p)
            break;
    }
    return 0;
}

int strcoll(const char *a, const char *b)
{
    return strcmp(a, b);
}

size_t strxfrm(char *d, const char *s, size_t n)
{
    size_t len = strlen(s);
    if (n) {
        strncpy(d, s, n - 1);
        d[n - 1] = 0;
    }
    return len;
}

char *strchr(const char *s, int c)
{
    char ch = (char)c;
    for (;; ++s) {
        if (*s == ch)
            return (char *)s;
        if (!*s)
            return 0;
    }
}

char *strrchr(const char *s, int c)
{
    const char *r = 0;
    char ch = (char)c;
    for (;; ++s) {
        if (*s == ch)
            r = s;
        if (!*s)
            return (char *)r;
    }
}

char *strstr(const char *s, const char *t)
{
    size_t n = strlen(t);
    if (!n)
        return (char *)s;
    for (; *s; ++s)
        if (*s == *t && !strncmp(s, t, n))
            return (char *)s;
    return 0;
}

size_t strspn(const char *s, const char *set)
{
    const char *p = s;
    while (*p && strchr(set, *p))
        ++p;
    return (size_t)(p - s);
}

size_t strcspn(const char *s, const char *set)
{
    const char *p = s;
    while (*p && !strchr(set, *p))
        ++p;
    return (size_t)(p - s);
}

char *strpbrk(const char *s, const char *set)
{
    for (; *s; ++s)
        if (strchr(set, *s))
            return (char *)s;
    return 0;
}

char *strtok(char *s, const char *delim)
{
    static char *next;
    char *t;
    if (!s)
        s = next;
    if (!s)
        return 0;
    s += strspn(s, delim);
    if (!*s) {
        next = 0;
        return 0;
    }
    t = s + strcspn(s, delim);
    if (*t)
        *t++ = 0;
    else
        t = 0;
    next = t;
    return s;
}

char *strdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *d = malloc(n);
    if (d)
        memcpy(d, s, n);
    return d;
}

size_t strnlen(const char *s, size_t n)
{
    size_t k = 0;
    while (k < n && s[k])
        ++k;
    return k;
}

static int lc(int c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

int strcasecmp(const char *a, const char *b)
{
    int x, y;
    do {
        x = lc((unsigned char)*a++);
        y = lc((unsigned char)*b++);
    } while (x && x == y);
    return x - y;
}

int strncasecmp(const char *a, const char *b, size_t n)
{
    int x, y;
    for (; n; --n) {
        x = lc((unsigned char)*a++);
        y = lc((unsigned char)*b++);
        if (x != y || !x)
            return x - y;
    }
    return 0;
}
