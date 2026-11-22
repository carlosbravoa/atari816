/* stdio.c - the C streams on Horizon, over the C library's own buffering.
 *
 * vbcc's library (vclib, binary only) buffers FILEs itself: getc/putc, fgets, fputs,
 * fread, fwrite, printf, scanf, ... work on the FILE's buffer and call _fillbuf,
 * _flushbuf, _putbuf, which call __read and __write here. Its simulator version has no
 * files (fopen returns NULL), its ftell keeps only 16 bits and its exit flushes no
 * console. So this file supplies, with the library's FILE layout (stdio.h):
 *
 *   stdin, stdout, stderr     the console: stdout and stderr line-buffered (128 bytes),
 *                             stdin a line typed with echo and editing (hz_getline)
 *   __read, __write           console and file I/O (SYS_READ, SYS_WRITE)
 *   fopen fclose freopen fseek ftell remove rename
 *   _EXIT_1_hzstdio           at exit: every FILE flushed and closed
 *
 * A FILE's filehandle is Horizon's handle + HZ_FH (vclib treats 0 as "no file" and
 * 1-3 as stdin, stdout, stderr). Horizon has 4 file handles for the whole system (URLs
 * and connections have 4 more): fopen fails with errno ENFILE when none is left.
 * Horizon's seek is absolute and there is no "tell", so the position and the size of
 * every open handle are kept here; SEEK_END uses the size from stat at open plus what
 * was written past it.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <horizon.h>

#define HZ_FH     4               /* FILE filehandle = Horizon handle + HZ_FH */
#define HZ_NH     8               /* handles 0-7 */
#ifdef HZ_TINY
#define FILEBUF   512             /* the tiny model's heap is small */
#else
#define FILEBUF   1024
#endif
#define CONBUF    128

extern FILE *__firstfile, *__lastfile;
int __hz_seterrno(void);

static char ibuf[CONBUF + 2], obuf[CONBUF + 2], ebuf[CONBUF + 2];
static FILE sin_ = {1, _READABLE | _LINEBUF | _ISTTY | _NOTMYBUF, 0, CONBUF, ibuf, ibuf, 0, 0};
static FILE sout_ = {2, _WRITEABLE | _LINEBUF | _ISTTY | _NOTMYBUF, 0, CONBUF, obuf, obuf, 0, 0};
static FILE serr_ = {3, _WRITEABLE | _LINEBUF | _ISTTY | _NOTMYBUF, 0, CONBUF, ebuf, ebuf, 0, 0};
FILE *stdin = &sin_, *stdout = &sout_, *stderr = &serr_;

/* per Horizon handle: position, size, append mode */
static long fpos[HZ_NH], fsize[HZ_NH];
static unsigned char fappend[HZ_NH];

/* ---- the console */

static char line[CONBUF + 1];
static unsigned lpos, llen;
static unsigned char leof;

static unsigned con_write(const char *p, unsigned len)
{
    unsigned left = len, n, i;
    while (left) {
        n = left > CONBUF ? CONBUF : left;
        for (i = 0; i < n; ++i)
            line[i] = p[i];
        line[n] = 0;
        hz_puts(line);
        p += n;
        left -= n;
    }
    return len;
}

static unsigned con_read(char *p, unsigned len)
{
    static char in[CONBUF + 1];
    unsigned n = 0;
    int r;
    if (lpos >= llen) {
        if (leof)
            return 0;
        fflush(stdout);
        fflush(stderr);
        r = hz_getline(in, sizeof(in) - 1);
        if (r < 0) {                    /* ctrl-C or ctrl-D: end of input */
            leof = 1;
            return 0;
        }
        in[r] = '\n';
        llen = r + 1;
        lpos = 0;
    }
    while (n < len && lpos < llen)
        p[n++] = in[lpos++];
    return n;
}

/* ---- the library's hooks */

unsigned int __write(int fh, const char *p, unsigned int len)
{
    hz_io io;
    int h, r;
    if (!len)
        return 0;
    if (fh == 2 || fh == 3)
        return con_write(p, len);
    h = fh - HZ_FH;
    if (h < 0 || h >= HZ_NH) {
        errno = EBADF;
        return (unsigned)-1;
    }
    if (fappend[h] && fpos[h] != fsize[h]) {     /* "a": every write at the end */
        if (hz_seek(h, fsize[h]) == -1)
            return (unsigned)__hz_seterrno();
        fpos[h] = fsize[h];
    }
    io.handle = (unsigned char)h;
    HZ_U24(io.buf, p);
    io.len = len;
    r = hz_write(&io);
    if (r < 0)
        return (unsigned)__hz_seterrno();
    fpos[h] += (unsigned)r;
    if (fpos[h] > fsize[h])
        fsize[h] = fpos[h];
    return (unsigned)r;
}

unsigned int __read(int fh, char *p, unsigned int len)
{
    hz_io io;
    int h, r;
    if (fh == 1)
        return con_read(p, len);
    h = fh - HZ_FH;
    if (h < 0 || h >= HZ_NH) {
        errno = EBADF;
        return (unsigned)-1;
    }
    io.handle = (unsigned char)h;
    HZ_U24(io.buf, p);
    io.len = len;
    r = hz_read(&io);
    if (r < 0)
        return (unsigned)__hz_seterrno();
    fpos[h] += (unsigned)r;
    return (unsigned)r;
}

/* ---- opening and closing */

static void unlink_file(FILE *f)
{
    if (f->prev)
        f->prev->next = f->next;
    else
        __firstfile = f->next;
    if (f->next)
        f->next->prev = f->prev;
    else
        __lastfile = f->prev;
}

static int is_console(FILE *f)
{
    return f == stdin || f == stdout || f == stderr;
}

/* open name into f (a fresh or a reused FILE) */
static FILE *open_into(FILE *f, const char *name, const char *mode)
{
    unsigned hmode, flags;
    int h, plus = 0, excl = 0;
    const char *m;
    hz_fileinfo st;
    char *buf;

    for (m = mode + 1; *m; ++m) {
        if (*m == '+')
            plus = 1;
        else if (*m == 'x')
            excl = 1;
    }
    switch (*mode) {
    case 'r': hmode = plus ? HZ_O_RDWR : HZ_O_READ;
              flags = plus ? _READABLE | _WRITEABLE : _READABLE; break;
    case 'w': hmode = HZ_O_CREATE;
              flags = plus ? _READABLE | _WRITEABLE : _WRITEABLE; break;
    case 'a': hmode = HZ_O_APPEND;
              flags = plus ? _READABLE | _WRITEABLE : _WRITEABLE; break;
    default:  errno = EINVAL; return 0;
    }
    if (excl && hz_stat_path(name, &st) == 0) {
        errno = EEXIST;
        return 0;
    }
    buf = malloc(FILEBUF);
    if (!buf) {
        errno = ENOMEM;
        return 0;
    }
    h = hz_open(name, hmode);
    if (h < 0) {
        free(buf);
        __hz_seterrno();
        return 0;
    }
    if (h >= HZ_NH) {                   /* (cannot happen: handles are 0-7) */
        hz_close(h);
        free(buf);
        errno = EMFILE;
        return 0;
    }
    fpos[h] = fsize[h] = 0;
    fappend[h] = (*mode == 'a');
    if (*mode != 'w' && hz_stat_path(name, &st) == 0)
        fsize[h] = (long)st.size;
    if (*mode == 'a')
        fpos[h] = fsize[h];             /* Horizon's append mode opens at the end */
    f->filehandle = (unsigned char)(h + HZ_FH);
    f->flags = flags;
    f->count = 0;
    f->bufsize = FILEBUF;
    f->pointer = f->base = buf;
    return f;
}

FILE *fopen(const char *name, const char *mode)
{
    FILE *f = malloc(sizeof(FILE));
    if (!f) {
        errno = ENOMEM;
        return 0;
    }
    if (!open_into(f, name, mode)) {
        free(f);
        return 0;
    }
    f->next = 0;
    f->prev = __lastfile;
    if (__lastfile)
        __lastfile->next = f;
    else
        __firstfile = f;
    __lastfile = f;
    return f;
}

static int close_handle(FILE *f)
{
    int r = 0, h;
    if (f->flags & _WRITE)
        r = _flushbuf(f);
    h = f->filehandle - HZ_FH;
    if (h >= 0 && h < HZ_NH) {
        if (hz_close(h) != 0 && !r)
            r = __hz_seterrno();
    }
    if (!(f->flags & _NOTMYBUF) && f->base)
        free(f->base);
    f->base = f->pointer = 0;
    f->filehandle = 0;
    f->flags = 0;
    f->count = 0;
    return r;
}

int fclose(FILE *f)
{
    int r;
    if (!f)
        return EOF;
    if (is_console(f))
        return fflush(f);
    r = close_handle(f);
    unlink_file(f);
    free(f);
    return r ? EOF : 0;
}

FILE *freopen(const char *name, const char *mode, FILE *f)
{
    if (!f || is_console(f)) {
        errno = EINVAL;                 /* the console streams cannot be redirected */
        return 0;
    }
    close_handle(f);
    if (!open_into(f, name, mode)) {
        unlink_file(f);
        free(f);
        return 0;
    }
    return f;
}

/* ---- positions */

int fseek(FILE *f, long off, int whence)
{
    long pos;
    int h;
    if (!f)
        return -1;
    if (is_console(f)) {
        errno = ESPIPE;
        return -1;
    }
    h = f->filehandle - HZ_FH;
    if (h < 0 || h >= HZ_NH) {
        errno = EBADF;
        return -1;
    }
    if (f->flags & _WRITE) {
        if (_flushbuf(f))
            return -1;
    }
    if (whence == SEEK_CUR)
        pos = fpos[h] - ((f->flags & _READ) ? f->count : 0) + off;
    else if (whence == SEEK_END)
        pos = fsize[h] + off;
    else if (whence == SEEK_SET)
        pos = off;
    else {
        errno = EINVAL;
        return -1;
    }
    if (pos < 0) {
        errno = EINVAL;
        return -1;
    }
    f->flags &= ~(_EOF | _READ | _WRITE);
    f->count = 0;
    f->pointer = f->base;
    if (hz_seek(h, pos) == -1) {
        f->flags |= _ERR;
        return __hz_seterrno();
    }
    fpos[h] = pos;
    if (pos > fsize[h])
        fsize[h] = pos;
    return 0;
}

long ftell(FILE *f)
{
    int h;
    if (!f)
        return -1;
    if (is_console(f)) {
        errno = ESPIPE;
        return -1;
    }
    h = f->filehandle - HZ_FH;
    if (h < 0 || h >= HZ_NH) {
        errno = EBADF;
        return -1;
    }
    if (f->flags & _READ)
        return fpos[h] - f->count;
    if (f->flags & _WRITE)
        return fpos[h] + (f->pointer - f->base);
    return fpos[h];
}

/* ---- files by name */

int remove(const char *name)
{
    return hz_delete(name) ? __hz_seterrno() : 0;
}

int rename(const char *from, const char *to)
{
    hz_renameblk b;
    HZ_U24(b.from, from);
    HZ_U24(b.to, to);
    return hz_rename(&b) ? __hz_seterrno() : 0;
}

/* ---- at exit (rt/crt0.s runs the destructors after the atexit functions) */

void _EXIT_1_hzstdio(void)
{
    FILE *f;
    fflush(stdout);
    fflush(stderr);
    while ((f = __firstfile) != 0)
        fclose(f);
}

/* ---- scanf: the library's sscanf, fscanf and scanf are its integer-only variants
 * (sscanf.1.o comes first in libvc.a); these call the full vfscanf, which is the float
 * library's when the program is linked with --float. strtod (atof) the same way: the
 * float library's own strtod reads nothing. */
#include <stdarg.h>

int sscanf(const char *s, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vsscanf(s, fmt, ap);
    va_end(ap);
    return r;
}

int fscanf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfscanf(f, fmt, ap);
    va_end(ap);
    return r;
}

int scanf(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfscanf(stdin, fmt, ap);
    va_end(ap);
    return r;
}

double strtod(const char *s, char **end)
{
    float v = 0;
    int n = 0;
    if (sscanf(s, "%f%n", &v, &n) < 1)
        n = 0;
    if (end)
        *end = (char *)s + n;
    return v;
}
