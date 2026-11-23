/* stdio.c - the C streams on Horizon for cc816: FILE, the console, files on the card.
 *
 *   stdin, stdout, stderr     the console: stdout and stderr line-buffered (128 bytes: a
 *                             line is sent at '\n', before stdin is read and at exit),
 *                             stdin a line typed with echo and editing (hz_getline);
 *                             ctrl-C, or ctrl-D at the start of a line, is its end (EOF)
 *   fopen fclose freopen      files: 1 KB of buffer each, from the heap (malloc); when
 *                             the heap has no 1 KB free, 128 bytes, else the FILE's own
 *                             2 bytes (slow, but the file opens: setvbuf(f, NULL,
 *                             _IONBF, 0) chooses that too, and frees the 1 KB). The
 *                             FILE structures themselves are static (FOPEN_MAX: Horizon
 *                             has 4 handles). Modes r w a, + for both ways, x (fail when
 *                             it exists), b (ignored)
 *   fseek ftell rewind fgetpos fsetpos
 *                             any 32-bit position; Horizon's seek is absolute and there is
 *                             no "tell", so the position and the size are kept here (the
 *                             size from stat at open, plus what is written past it)
 *   at exit                   _EXIT_1_hzstdio (a destructor: cc816 lists it for the
 *                             startup): stdout and stderr flushed, every file closed
 *
 * Horizon has 4 file handles for the whole system: fopen fails with errno ENFILE when none is left.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <horizon.h>
#include "stdio_int.h"

int __hz_seterrno(void);

static unsigned char ibuf[CONBUF + 2], obuf[CONBUF + 1], ebuf[CONBUF + 1];
static FILE sin_ = {ibuf, ibuf, 0, CONBUF + 1, F_READ | F_CON | F_STATIC, -1, EOF, 0, 0, 0};
static FILE sout_ = {obuf, obuf, 0, CONBUF, F_WRITE | F_LINE | F_CON | F_STATIC, -1, EOF, 0, 0, 0};
static FILE serr_ = {ebuf, ebuf, 0, CONBUF, F_WRITE | F_LINE | F_CON | F_STATIC, -1, EOF, 0, 0, 0};
FILE *stdin = &sin_, *stdout = &sout_, *stderr = &serr_;

FILE *__hz_files;               /* the open files (fopen), newest first */

/* ---- the buffer's way to the console or the card */

/* write n bytes of the buffer: 0, or EOF on an error */
static int put_out(FILE *f, unsigned n)
{
    hz_io io;
    int r;
    if (f->flags & F_CON) {
        f->base[n] = 0;                 /* (console buffers have room for the 0) */
        hz_puts((char *)f->base);
        return 0;
    }
    if ((f->flags & F_APPEND) && f->pos != f->fsize) {  /* "a": every write at the end */
        if (hz_seek(f->fh, f->fsize) == -1 && hz_errno) {
            __hz_seterrno();
            return EOF;
        }
        f->pos = f->fsize;
    }
    io.handle = (unsigned char)f->fh;
    HZ_U24(io.buf, f->base);
    io.len = n;
    r = hz_write(&io);
    if (r < 0) {
        __hz_seterrno();
        return EOF;
    }
    f->pos += (unsigned)r;
    if (f->pos > f->fsize)
        f->fsize = f->pos;
    if ((unsigned)r != n) {
        errno = ENOSPC;
        return EOF;
    }
    return 0;
}

/* the console: a line from the keyboard (stdout and stderr flushed first) */
static int con_in(FILE *f)
{
    int r;
    fflush(stdout);
    fflush(stderr);
    r = hz_getline((char *)f->base, CONBUF);
    if (r < 0)
        return 0;                       /* ctrl-C or ctrl-D: the end of input */
    f->base[r] = '\n';
    return r + 1;
}

/* refill a read buffer: bytes read, 0 at the end, -1 on an error */
static int fill_in(FILE *f)
{
    hz_io io;
    int r;
    if (f->flags & F_CON)
        return con_in(f);
    io.handle = (unsigned char)f->fh;
    HZ_U24(io.buf, f->base);
    io.len = f->size;
    r = hz_read(&io);
    if (r < 0) {
        __hz_seterrno();
        return -1;
    }
    f->pos += (unsigned)r;
    return r;
}

/* ---- the buffer's states: reading (F_RDING), writing (F_WRING) or neither */

/* write out what is buffered: 0, or EOF */
int __hz_flushw(FILE *f)
{
    unsigned n;
    if (!(f->flags & F_WRING))
        return 0;
    n = (unsigned)(f->ptr - f->base);
    f->flags &= ~F_WRING;
    f->ptr = f->base;
    f->cnt = 0;
    if (n && put_out(f, n)) {
        f->flags |= F_ERR;
        return EOF;
    }
    return 0;
}

/* leave the reading state: the card's position goes back to the first byte not read */
static int drop_read(FILE *f)
{
    long back = (long)f->cnt + (f->ungot != EOF);
    f->flags &= ~F_RDING;
    f->cnt = 0;
    f->ptr = f->base;
    f->ungot = EOF;
    if (back && !(f->flags & F_CON)) {
        f->pos -= back;
        if (hz_seek(f->fh, f->pos) == -1 && hz_errno) {
            __hz_seterrno();
            f->flags |= F_ERR;
            return EOF;
        }
    }
    return 0;
}

/* the slow path of fputc: start writing, or a line, the buffer's end, no buffering */
int __hz_putslow(int c, FILE *f)
{
    if (!(f->flags & F_WRITE)) {
        errno = EBADF;
        f->flags |= F_ERR;
        return EOF;
    }
    if (f->flags & F_RDING)
        drop_read(f);
    if (!(f->flags & F_WRING)) {
        f->flags |= F_WRING;
        f->ptr = f->base;
        f->cnt = f->size;
    }
    *f->ptr++ = (unsigned char)c;
    --f->cnt;
    if ((f->flags & F_NOBUF) || ((f->flags & F_LINE) && c == '\n') || !f->cnt) {
        if (__hz_flushw(f))
            return EOF;
    }
    return (unsigned char)c;
}

int fputc(int c, FILE *f)
{
    if ((f->flags & (F_WRING | F_LINE | F_NOBUF)) == F_WRING && f->cnt > 1) {
        *f->ptr++ = (unsigned char)c;
        --f->cnt;
        return (unsigned char)c;
    }
    return __hz_putslow(c, f);
}

int putc(int c, FILE *f)
{
    return fputc(c, f);
}

int putchar(int c)
{
    return fputc(c, stdout);
}

/* the slow path of fgetc: start reading, or the buffer is empty */
int __hz_getslow(FILE *f)
{
    int n;
    if (f->ungot != EOF) {
        n = f->ungot;
        f->ungot = EOF;
        return n;
    }
    if (!(f->flags & F_READ)) {
        errno = EBADF;
        f->flags |= F_ERR;
        return EOF;
    }
    if (f->flags & F_WRING) {
        if (__hz_flushw(f))
            return EOF;
    }
    if ((f->flags & F_RDING) && f->cnt) {
        --f->cnt;
        return *f->ptr++;
    }
    if (f->flags & F_EOF)
        return EOF;
    n = fill_in(f);
    f->ptr = f->base;
    f->cnt = 0;
    f->flags |= F_RDING;
    if (n <= 0) {
        f->flags |= n ? F_ERR : F_EOF;
        return EOF;
    }
    f->cnt = (unsigned)n - 1;
    return *f->ptr++;
}

int fgetc(FILE *f)
{
    if ((f->flags & F_RDING) && f->cnt && f->ungot == EOF) {
        --f->cnt;
        return *f->ptr++;
    }
    return __hz_getslow(f);
}

int getc(FILE *f)
{
    return fgetc(f);
}

int getchar(void)
{
    return fgetc(stdin);
}

int ungetc(int c, FILE *f)
{
    if (c == EOF || f->ungot != EOF)
        return EOF;
    if ((f->flags & F_RDING) && f->ptr > f->base && f->ptr[-1] == (unsigned char)c) {
        --f->ptr;
        ++f->cnt;
    } else {
        if (f->flags & F_WRING)
            __hz_flushw(f);
        f->ungot = (unsigned char)c;
    }
    f->flags &= ~F_EOF;
    return (unsigned char)c;
}

int fflush(FILE *f)
{
    int r = 0;
    if (!f) {
        r |= __hz_flushw(stdout) | __hz_flushw(stderr);
        for (f = __hz_files; f; f = f->next)
            r |= __hz_flushw(f);
        return r ? EOF : 0;
    }
    if (f->flags & F_WRING)
        return __hz_flushw(f);
    return 0;
}

/* ---- opening and closing */

static void unlink_file(FILE *f)
{
    FILE **pp;
    for (pp = &__hz_files; *pp; pp = &(*pp)->next)
        if (*pp == f) {
            *pp = f->next;
            break;
        }
}

/* open name into f (a fresh or a reused FILE) */
static FILE *open_into(FILE *f, const char *name, const char *mode)
{
    unsigned hmode, flags;
    int h, plus = 0, excl = 0;
    const char *m;
    hz_fileinfo st;
    unsigned char *buf;
    unsigned size;

    for (m = mode + 1; *m; ++m) {
        if (*m == '+')
            plus = 1;
        else if (*m == 'x')
            excl = 1;
    }
    switch (*mode) {
    case 'r': hmode = plus ? HZ_O_RDWR : HZ_O_READ;
              flags = plus ? F_READ | F_WRITE : F_READ; break;
    case 'w': hmode = HZ_O_CREATE;
              flags = plus ? F_READ | F_WRITE : F_WRITE; break;
    case 'a': hmode = HZ_O_APPEND;
              flags = (plus ? F_READ | F_WRITE : F_WRITE) | F_APPEND; break;
    default:  errno = EINVAL; return 0;
    }
    if (excl && hz_stat_path(name, &st) == 0) {
        errno = EEXIST;
        return 0;
    }
    h = hz_open(name, hmode);
    if (h < 0) {
        __hz_seterrno();
        return 0;
    }
    /* the buffer: 1 KB from the heap, or less, or the FILE's own two bytes */
    size = FILEBUF;
    buf = malloc(FILEBUF);
    if (!buf) {
        size = FILESMALL;
        buf = malloc(FILESMALL);
    }
    flags |= F_MYBUF;
    if (!buf) {
        size = sizeof f->tiny;
        buf = f->tiny;
        flags &= ~F_MYBUF;
    }
    f->pos = f->fsize = 0;
    if (*mode != 'w' && hz_stat_path(name, &st) == 0)
        f->fsize = (long)st.size;
    if (*mode == 'a')
        f->pos = f->fsize;              /* Horizon's append mode opens at the end */
    f->fh = h;
    f->flags = flags;
    f->cnt = 0;
    f->size = size;
    f->ptr = f->base = buf;
    f->ungot = EOF;
    return f;
}

/* the FILE structures: static, one for each of Horizon's handles (a FILE beyond them,
 * from freopen's or a program's own use, comes from the heap) */
static FILE pool[FOPEN_MAX];
static unsigned char inpool[FOPEN_MAX];

static FILE *new_file(void)
{
    unsigned i;
    for (i = 0; i < FOPEN_MAX; i++)
        if (!inpool[i]) {
            inpool[i] = 1;
            return &pool[i];
        }
    return malloc(sizeof(FILE));
}

static void free_file(FILE *f)
{
    unsigned i;
    for (i = 0; i < FOPEN_MAX; i++)
        if (f == &pool[i]) {
            inpool[i] = 0;
            return;
        }
    free(f);
}

FILE *fopen(const char *name, const char *mode)
{
    FILE *f = new_file();
    if (!f) {
        errno = ENOMEM;
        return 0;
    }
    if (!open_into(f, name, mode)) {
        free_file(f);
        return 0;
    }
    f->next = __hz_files;
    __hz_files = f;
    return f;
}

static int close_handle(FILE *f)
{
    int r = __hz_flushw(f);
    if (f->fh >= 0 && hz_close(f->fh) != 0 && !r)
        r = __hz_seterrno();
    if ((f->flags & F_MYBUF) && f->base)
        free(f->base);
    f->base = f->ptr = 0;
    f->fh = -1;
    f->flags = 0;
    f->cnt = 0;
    return r;
}

int fclose(FILE *f)
{
    int r;
    if (!f)
        return EOF;
    if (f->flags & F_STATIC)
        return fflush(f);
    r = close_handle(f);
    unlink_file(f);
    free_file(f);
    return r ? EOF : 0;
}

FILE *freopen(const char *name, const char *mode, FILE *f)
{
    if (!f || (f->flags & F_STATIC)) {
        errno = EINVAL;                 /* the console streams cannot be redirected */
        return 0;
    }
    close_handle(f);
    if (!open_into(f, name, mode)) {
        unlink_file(f);
        free_file(f);
        return 0;
    }
    return f;
}

int setvbuf(FILE *f, char *buf, int mode, size_t size)
{
    if (!f || mode < _IOFBF || mode > _IONBF)
        return -1;
    fflush(f);
    f->flags &= ~(F_LINE | F_NOBUF);
    if (mode == _IOLBF)
        f->flags |= F_LINE;
    else if (mode == _IONBF)
        f->flags |= F_NOBUF;
    if (f->flags & F_CON)
        return 0;
    if (!buf && mode == _IONBF) {
        /* no buffer: the library's (1 KB of heap) is given back; the FILE's own 2 bytes */
        buf = (char *)f->tiny;
        size = sizeof f->tiny;
    }
    if (buf && size > 1) {
        if (f->flags & F_RDING)
            drop_read(f);
        if (f->flags & F_MYBUF)
            free(f->base);
        f->flags &= ~F_MYBUF;
        f->base = f->ptr = (unsigned char *)buf;
        f->size = size;
        f->cnt = 0;
        f->flags &= ~(F_RDING | F_WRING);
    }
    return 0;
}

void setbuf(FILE *f, char *buf)
{
    setvbuf(f, buf, buf ? _IOFBF : _IONBF, BUFSIZ);
}

/* ---- positions */

int fseek(FILE *f, long off, int whence)
{
    long pos;
    if (!f)
        return -1;
    if (f->flags & F_CON) {
        errno = ESPIPE;
        return -1;
    }
    if (f->flags & F_WRING) {
        if (__hz_flushw(f))
            return -1;
    }
    if (whence == SEEK_CUR)
        pos = ftell(f) + off;
    else if (whence == SEEK_END)
        pos = f->fsize + off;
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
    f->flags &= ~(F_EOF | F_RDING | F_WRING);
    f->cnt = 0;
    f->ptr = f->base;
    f->ungot = EOF;
    if (hz_seek(f->fh, pos) == -1 && hz_errno) {
        f->flags |= F_ERR;
        return __hz_seterrno();
    }
    f->pos = pos;
    if (pos > f->fsize)
        f->fsize = pos;
    return 0;
}

long ftell(FILE *f)
{
    if (!f)
        return -1;
    if (f->flags & F_CON) {
        errno = ESPIPE;
        return -1;
    }
    if (f->flags & F_RDING)
        return f->pos - f->cnt - (f->ungot != EOF);
    if (f->flags & F_WRING)
        return ((f->flags & F_APPEND) ? f->fsize : f->pos) + (f->ptr - f->base);
    return f->pos - (f->ungot != EOF);
}

void rewind(FILE *f)
{
    fseek(f, 0, SEEK_SET);
    f->flags &= ~F_ERR;
}

int fgetpos(FILE *f, fpos_t *pos)
{
    long p = ftell(f);
    if (p < 0)
        return -1;
    *pos = p;
    return 0;
}

int fsetpos(FILE *f, const fpos_t *pos)
{
    return fseek(f, *pos, SEEK_SET);
}

int feof(FILE *f)
{
    return (f->flags & F_EOF) != 0;
}

int ferror(FILE *f)
{
    return (f->flags & F_ERR) != 0;
}

void clearerr(FILE *f)
{
    f->flags &= ~(F_EOF | F_ERR);
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

FILE *tmpfile(void)
{
    errno = ENOSYS;
    return 0;
}

char *tmpnam(char *s)
{
    (void)s;
    return 0;
}

/* ---- at exit (the startup runs the destructors after the atexit functions) */

void _EXIT_1_hzstdio(void)
{
    __hz_flushw(stdout);
    __hz_flushw(stderr);
    while (__hz_files)
        fclose(__hz_files);
}
