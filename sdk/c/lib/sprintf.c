/* sprintf.c - sprintf, snprintf, vsprintf, vsnprintf (cc816; the formatting: fmt.c) */
#include <stdio.h>
#include <stdarg.h>

int __hz_vformat(void (*out)(int c, void *ctx), void *ctx, const char *fmt, va_list ap);

struct sbuf {
    char *p;
    size_t room;                /* bytes that may still be stored (the 0 not counted) */
};

static void to_buf(int c, void *ctx)
{
    struct sbuf *b = ctx;
    if (b->room) {
        *b->p++ = (char)c;
        --b->room;
    }
}

int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap)
{
    struct sbuf b;
    int r;
    b.p = buf;
    b.room = n ? n - 1 : 0;
    r = __hz_vformat(to_buf, &b, fmt, ap);
    if (n)
        *b.p = 0;
    return r;
}

int vsprintf(char *buf, const char *fmt, va_list ap)
{
    return vsnprintf(buf, 0xFFFF, fmt, ap);
}

int snprintf(char *buf, size_t n, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsnprintf(buf, n, fmt, ap);
    va_end(ap);
    return r;
}

int sprintf(char *buf, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsnprintf(buf, 0xFFFF, fmt, ap);
    va_end(ap);
    return r;
}
