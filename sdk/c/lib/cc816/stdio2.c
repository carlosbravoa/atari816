/* stdio2.c - strings and blocks on the C streams (cc816): fputs, puts, fgets, fread,
 * fwrite. */
#include <stdio.h>
#include <string.h>
#include "stdio_int.h"

int fputs(const char *s, FILE *f)
{
    while (*s)
        if (fputc((unsigned char)*s++, f) == EOF)
            return EOF;
    return 0;
}

int puts(const char *s)
{
    if (fputs(s, stdout) == EOF)
        return EOF;
    return fputc('\n', stdout) == EOF ? EOF : 0;
}

char *fgets(char *s, int n, FILE *f)
{
    char *p = s;
    int c;
    if (n <= 0)
        return 0;
    while (--n > 0) {
        c = fgetc(f);
        if (c == EOF) {
            if (p == s || ferror(f))
                return 0;
            break;
        }
        *p++ = (char)c;
        if (c == '\n')
            break;
    }
    *p = 0;
    return s;
}

size_t fread(void *buf, size_t size, size_t n, FILE *f)
{
    unsigned char *p = buf;
    unsigned long want = (unsigned long)size * n;
    unsigned long got = 0;
    unsigned k;
    int c;
    if (!size || !n)
        return 0;
    while (got < want) {
        if ((f->flags & F_RDING) && f->cnt && f->ungot == EOF) {
            k = f->cnt;
            if (k > want - got)
                k = (unsigned)(want - got);
            memcpy(p, f->ptr, k);
            f->ptr += k;
            f->cnt -= k;
            p += k;
            got += k;
            continue;
        }
        c = __hz_getslow(f);
        if (c == EOF)
            break;
        *p++ = (unsigned char)c;
        ++got;
    }
    return (size_t)(got / size);
}

size_t fwrite(const void *buf, size_t size, size_t n, FILE *f)
{
    const unsigned char *p = buf;
    unsigned long want = (unsigned long)size * n;
    unsigned long done = 0;
    unsigned k;
    if (!size || !n)
        return 0;
    while (done < want) {
        if ((f->flags & (F_WRING | F_LINE | F_NOBUF)) == F_WRING && f->cnt > 1) {
            k = f->cnt - 1;
            if (k > want - done)
                k = (unsigned)(want - done);
            memcpy(f->ptr, p, k);
            f->ptr += k;
            f->cnt -= k;
            p += k;
            done += k;
            continue;
        }
        if (__hz_putslow(*p, f) == EOF)
            break;
        ++p;
        ++done;
    }
    return (size_t)(done / size);
}
