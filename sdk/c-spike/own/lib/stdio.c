/* stdio.c - console output for cc816 programs: a line buffer sent with SYS_PUTS. */
#include <stdio.h>
#include <string.h>
#include <horizon.h>

static FILE f_in = {0}, f_out = {1}, f_err = {2};
FILE *stdin = &f_in, *stdout = &f_out, *stderr = &f_err;

static char obuf[129];
static unsigned olen;

int fflush(FILE *f)
{
    (void)f;
    if (olen) {
        obuf[olen] = 0;
        __cop(SYS_PUTS, 0, (unsigned)obuf, __cbank());
        olen = 0;
    }
    return 0;
}

int putchar(int c)
{
    obuf[olen++] = (char)c;
    if (c == '\n' || olen == 128)
        fflush(stdout);
    return c & 255;
}

int fputc(int c, FILE *f) { (void)f; return putchar(c); }

int fputs(const char *s, FILE *f)
{
    (void)f;
    while (*s)
        putchar(*s++);
    return 0;
}

int puts(const char *s)
{
    fputs(s, stdout);
    putchar('\n');
    return 0;
}

int getchar(void) { return EOF; }

/* formatted output: a sink is a buffer (with a limit) or the console */
struct sink { char *p; unsigned n, max; int con; };

static void out(struct sink *k, char c)
{
    if (k->con)
        putchar(c);
    else if (k->n + 1 < k->max)
        k->p[k->n] = c;
    k->n++;
}

static int vformat(struct sink *k, const char *fmt, va_list ap)
{
    char tmp[12];
    char c;
    while ((c = *fmt++) != 0) {
        int left = 0, zero = 0, plus = 0, space = 0, width = 0, prec = -1, lng = 0, alt = 0;
        unsigned long v;
        int neg, base, len, i, pad;
        const char *s;
        char *t;
        if (c != '%') {
            out(k, c);
            continue;
        }
        for (;;) {
            c = *fmt;
            if (c == '-') left = 1;
            else if (c == '0') zero = 1;
            else if (c == '+') plus = 1;
            else if (c == ' ') space = 1;
            else if (c == '#') alt = 1;
            else break;
            fmt++;
        }
        if (*fmt == '*') { width = va_arg(ap, int); fmt++; if (width < 0) { left = 1; width = -width; } }
        else while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        if (*fmt == '.') {
            fmt++;
            prec = 0;
            if (*fmt == '*') { prec = va_arg(ap, int); fmt++; }
            else while (*fmt >= '0' && *fmt <= '9') prec = prec * 10 + (*fmt++ - '0');
        }
        while (*fmt == 'l' || *fmt == 'h' || *fmt == 'z' || *fmt == 't') {
            if (*fmt == 'l') lng = 1;
            fmt++;
        }
        c = *fmt++;
        neg = 0;
        base = 10;
        s = tmp;
        len = 0;
        switch (c) {
        case 'd': case 'i':
            if (lng) { long x = va_arg(ap, long); if (x < 0) { neg = 1; v = (unsigned long)-x; } else v = (unsigned long)x; }
            else { int x = va_arg(ap, int); if (x < 0) { neg = 1; v = (unsigned)-x; } else v = (unsigned)x; }
            goto num;
        case 'u': base = 10; goto unum;
        case 'x': case 'X': base = 16; goto unum;
        case 'o': base = 8; goto unum;
        case 'p': base = 16; lng = 0; alt = 0; out(k, '0'); out(k, 'x'); goto unum;
        unum:
            if (lng) v = va_arg(ap, unsigned long);
            else v = va_arg(ap, unsigned);
        num:
            t = tmp + sizeof tmp;
            do {
                unsigned dgt = (unsigned)(v % base);
                *--t = (char)(dgt < 10 ? '0' + dgt : (c == 'X' ? 'A' : 'a') + dgt - 10);
                v /= base;
            } while (v);
            len = (int)(tmp + sizeof tmp - t);
            s = t;
            if (prec >= 0) zero = 0;
            {
                int sign = neg || plus || space;
                int z = prec > len ? prec - len : 0;
                if (zero && !left && width > len + sign) z = width - len - sign;
                pad = width - len - z - sign;
                if (!left) while (pad-- > 0) out(k, ' ');
                if (neg) out(k, '-'); else if (plus) out(k, '+'); else if (space) out(k, ' ');
                while (z-- > 0) out(k, '0');
                for (i = 0; i < len; i++) out(k, s[i]);
                if (left) while (pad-- > 0) out(k, ' ');
            }
            continue;
        case 'c':
            tmp[0] = (char)va_arg(ap, int);
            s = tmp;
            len = 1;
            break;
        case 's':
            s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            len = 0;
            while (s[len] && (prec < 0 || len < prec)) len++;
            break;
        case '%':
            out(k, '%');
            continue;
        default:
            out(k, '%');
            out(k, c);
            continue;
        }
        pad = width - len;
        if (!left) while (pad-- > 0) out(k, ' ');
        for (i = 0; i < len; i++) out(k, s[i]);
        if (left) while (pad-- > 0) out(k, ' ');
    }
    return (int)k->n;
}

int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap)
{
    struct sink k;
    int r;
    k.p = buf; k.n = 0; k.max = n; k.con = 0;
    r = vformat(&k, fmt, ap);
    if (n) buf[k.n < n ? k.n : n - 1] = 0;
    return r;
}

int vsprintf(char *buf, const char *fmt, va_list ap) { return vsnprintf(buf, 65535u, fmt, ap); }

int vprintf(const char *fmt, va_list ap)
{
    struct sink k;
    k.p = 0; k.n = 0; k.max = 0; k.con = 1;
    return vformat(&k, fmt, ap);
}

int vfprintf(FILE *f, const char *fmt, va_list ap) { (void)f; return vprintf(fmt, ap); }

int printf(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}

int fprintf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int r;
    (void)f;
    va_start(ap, fmt);
    r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}

int sprintf(char *buf, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsnprintf(buf, 65535u, fmt, ap);
    va_end(ap);
    return r;
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
