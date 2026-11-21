/* string.c - the string functions (memcpy, memset, memmove: mem.s) */
#include <string.h>
#include <stdlib.h>

size_t strlen(const char *s) { const char *p = s; while (*p) p++; return (size_t)(p - s); }
char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++) != 0) ; return r; }
char *strncpy(char *d, const char *s, size_t n)
{
    char *r = d;
    while (n && (*d = *s) != 0) { d++; s++; n--; }
    while (n--) *d++ = 0;
    return r;
}
char *strcat(char *d, const char *s) { strcpy(d + strlen(d), s); return d; }
char *strncat(char *d, const char *s, size_t n)
{
    char *p = d + strlen(d);
    while (n-- && *s) *p++ = *s++;
    *p = 0;
    return d;
}
int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}
int strncmp(const char *a, const char *b, size_t n)
{
    for (; n; n--, a++, b++) {
        if (*a != *b) return (int)(unsigned char)*a - (int)(unsigned char)*b;
        if (!*a) return 0;
    }
    return 0;
}
int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *p = a, *q = b;
    for (; n; n--, p++, q++)
        if (*p != *q) return (int)*p - (int)*q;
    return 0;
}
void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *p = s;
    for (; n; n--, p++) if (*p == (unsigned char)c) return (void *)p;
    return NULL;
}
char *strchr(const char *s, int c)
{
    for (;; s++) {
        if (*s == (char)c) return (char *)s;
        if (!*s) return NULL;
    }
}
char *strrchr(const char *s, int c)
{
    const char *r = NULL;
    for (;; s++) {
        if (*s == (char)c) r = s;
        if (!*s) return (char *)r;
    }
}
char *strstr(const char *h, const char *n)
{
    size_t k = strlen(n);
    if (!k) return (char *)h;
    for (; *h; h++) if (*h == *n && !strncmp(h, n, k)) return (char *)h;
    return NULL;
}
size_t strspn(const char *s, const char *a) { size_t n = 0; while (s[n] && strchr(a, s[n])) n++; return n; }
size_t strcspn(const char *s, const char *r) { size_t n = 0; while (s[n] && !strchr(r, s[n])) n++; return n; }
char *strdup(const char *s) { char *d = malloc(strlen(s) + 1); if (d) strcpy(d, s); return d; }
char *strtok(char *s, const char *delim)
{
    static char *next;
    char *t;
    if (!s) s = next;
    if (!s) return NULL;
    s += strspn(s, delim);
    if (!*s) { next = NULL; return NULL; }
    t = s + strcspn(s, delim);
    if (*t) { *t = 0; next = t + 1; } else next = NULL;
    return s;
}
