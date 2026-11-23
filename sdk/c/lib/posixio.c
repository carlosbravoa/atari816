/* posixio.c - POSIX's file descriptors on Horizon (cc816): open, creat, read, write, lseek,
 * close, unlink, isatty (fcntl.h, unistd.h).
 *
 *   0, 1, 2      the console, through stdin / stdout / stderr (their buffers)
 *   3 and up     Horizon's handle + 3: no buffer here, each read or write is one call
 *
 * A descriptor opened read-only reads ahead into 512 bytes of the heap (when the heap has
 * them): code written for DOS or Unix reads records of a few bytes, and each call to the
 * card costs about a millisecond (Xargon's tile table: 3,600 reads of 1 or 2 bytes). A
 * read of 512 bytes or more goes straight to the card.
 *
 * Horizon's seek is absolute and it has no "tell": the position and the size are kept here,
 * as stdio does (the size from stat at open, plus what is written past it). Horizon's own
 * modes are read, read/write (the file must exist), create/truncate and append; open's
 * flags are mapped onto them (O_CREAT without O_TRUNC on a file that exists: read/write). */
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <horizon.h>

int __hz_seterrno(void);

#define NH 8                    /* Horizon's handles: files 0-3, URLs 4-7 */
#define D_OPEN   1
#define D_READ   2
#define D_WRITE  4
#define D_APPEND 8

#define RABUF 512

static unsigned char dflags[NH];
static long dpos[NH], dsize[NH];        /* the position (the program's), the size */
static unsigned char *rbuf[NH];         /* read-ahead: the bytes at dpos .. */
static unsigned rhead[NH], rcount[NH];  /* the next one's index, how many are left */

/* the card's position is dpos + rcount: back to dpos (the read-ahead dropped) */
static int drop(int h)
{
    if (rcount[h]) {
        rcount[h] = 0;
        if (hz_seek((unsigned)h, (unsigned long)dpos[h]) == -1 && hz_errno)
            return __hz_seterrno();
    }
    return 0;
}

static int handle_of(int fd)
{
    int h = fd - 3;
    if (h < 0 || h >= NH || !(dflags[h] & D_OPEN)) {
        errno = EBADF;
        return -1;
    }
    return h;
}

int open(const char *path, int flags, ...)
{
    hz_fileinfo st;
    unsigned mode, df;
    int h, exists, acc = flags & O_ACCMODE;

    exists = hz_stat_path(path, &st) == 0;
    if (exists && (st.attr & HZ_ATTR_DIR)) {
        errno = EISDIR;
        return -1;
    }
    if ((flags & O_CREAT) && (flags & O_EXCL) && exists) {
        errno = EEXIST;
        return -1;
    }
    if (!exists && !(flags & O_CREAT)) {
        errno = ENOENT;
        return -1;
    }
    df = D_OPEN | (acc == O_WRONLY ? D_WRITE : acc == O_RDWR ? D_READ | D_WRITE : D_READ);
    if (flags & O_APPEND)
        df |= D_APPEND;
    if (!exists || ((flags & O_TRUNC) && acc != O_RDONLY))
        mode = HZ_O_CREATE;             /* (create, or make it empty) */
    else if (acc == O_RDONLY)
        mode = HZ_O_READ;
    else
        mode = HZ_O_RDWR;
    h = hz_open(path, mode);
    if (h < 0)
        return __hz_seterrno();
    if (h >= NH) {                      /* (never: Horizon has 8 handles) */
        hz_close((unsigned)h);
        errno = EMFILE;
        return -1;
    }
    dflags[h] = (unsigned char)df;
    dpos[h] = 0;
    rcount[h] = rhead[h] = 0;
    rbuf[h] = df == (D_OPEN | D_READ) ? (unsigned char *)malloc(RABUF) : 0;
    dsize[h] = mode == HZ_O_CREATE ? 0 : (long)st.size;
    return h + 3;
}

int creat(const char *path, int mode)
{
    (void)mode;
    return open(path, O_WRONLY | O_CREAT | O_TRUNC);
}

ssize_t read(int fd, void *buf, size_t n)
{
    hz_io io;
    int h, r, c;
    unsigned char *p;

    if (fd == 0) {                      /* the console: what stdin has (a line at a time) */
        p = (unsigned char *)buf;
        for (r = 0; (unsigned)r < n; ) {
            c = getchar();
            if (c == EOF)
                break;
            p[r++] = (unsigned char)c;
            if (c == '\n')
                break;
        }
        return r;
    }
    h = handle_of(fd);
    if (h < 0)
        return -1;
    if (!(dflags[h] & D_READ)) {
        errno = EBADF;
        return -1;
    }
    if (n == 0)
        return 0;
    if (rbuf[h] && n < RABUF) {
        /* (as many as asked, unless the file ends: as a read from the card) */
        p = (unsigned char *)buf;
        for (r = 0; (unsigned)r < n; ) {
            unsigned k;
            if (!rcount[h]) {           /* (the card's position is dpos) */
                io.handle = (unsigned char)h;
                HZ_U24(io.buf, rbuf[h]);
                io.len = RABUF;
                c = hz_read(&io);
                if (c < 0)
                    return r ? r : __hz_seterrno();
                if (c == 0)
                    break;
                rhead[h] = 0;
                rcount[h] = (unsigned)c;
            }
            k = n - (unsigned)r;
            if (k > rcount[h])
                k = rcount[h];
            memcpy(p + r, rbuf[h] + rhead[h], k);
            rhead[h] += k;
            rcount[h] -= k;
            dpos[h] += k;
            r += (int)k;
        }
        return r;
    }
    if (drop(h))
        return -1;
    io.handle = (unsigned char)h;
    HZ_U24(io.buf, buf);
    io.len = (unsigned short)n;
    r = hz_read(&io);
    if (r < 0)
        return __hz_seterrno();
    dpos[h] += (unsigned)r;
    return r;
}

ssize_t write(int fd, const void *buf, size_t n)
{
    hz_io io;
    int h, r;

    if (fd == 1 || fd == 2) {
        r = (int)fwrite(buf, 1, n, fd == 1 ? stdout : stderr);
        fflush(fd == 1 ? stdout : stderr);
        return r;
    }
    h = handle_of(fd);
    if (h < 0)
        return -1;
    if (!(dflags[h] & D_WRITE)) {
        errno = EBADF;
        return -1;
    }
    if (n == 0)
        return 0;
    if ((dflags[h] & D_APPEND) && dpos[h] != dsize[h]) {
        if (hz_seek((unsigned)h, (unsigned long)dsize[h]) == -1 && hz_errno)
            return __hz_seterrno();
        dpos[h] = dsize[h];
    }
    io.handle = (unsigned char)h;
    HZ_U24(io.buf, buf);
    io.len = (unsigned short)n;
    r = hz_write(&io);
    if (r < 0)
        return __hz_seterrno();
    dpos[h] += (unsigned)r;
    if (dpos[h] > dsize[h])
        dsize[h] = dpos[h];
    if ((unsigned)r != n) {
        errno = ENOSPC;
        return r ? r : -1;
    }
    return r;
}

off_t lseek(int fd, off_t off, int whence)
{
    long pos;
    int h;
    unsigned n;

    if (fd >= 0 && fd <= 2) {
        errno = ESPIPE;
        return -1;
    }
    h = handle_of(fd);
    if (h < 0)
        return -1;
    if (whence == SEEK_SET)
        pos = off;
    else if (whence == SEEK_CUR)
        pos = dpos[h] + off;
    else if (whence == SEEK_END)
        pos = dsize[h] + off;
    else {
        errno = EINVAL;
        return -1;
    }
    if (pos < 0) {
        errno = EINVAL;
        return -1;
    }
    if (rcount[h] && pos >= dpos[h] && pos - dpos[h] <= (long)rcount[h]) {
        n = (unsigned)(pos - dpos[h]);  /* (forward within the read-ahead) */
        rhead[h] += n;
        rcount[h] -= n;
        dpos[h] = pos;
        return pos;
    }
    /* (with bytes read ahead the card is past dpos: a seek even to dpos) */
    if (pos != dpos[h] || rcount[h]) {
        rcount[h] = 0;
        if (hz_seek((unsigned)h, (unsigned long)pos) == -1 && hz_errno)
            return __hz_seterrno();
        dpos[h] = pos;
        if (pos > dsize[h] && (dflags[h] & D_WRITE))
            dsize[h] = pos;
    }
    return pos;
}

int close(int fd)
{
    int h;
    if (fd >= 0 && fd <= 2)
        return 0;                       /* (the console stays) */
    h = handle_of(fd);
    if (h < 0)
        return -1;
    dflags[h] = 0;
    rcount[h] = 0;
    if (rbuf[h]) {
        free(rbuf[h]);
        rbuf[h] = 0;
    }
    if (hz_close((unsigned)h) != 0)
        return __hz_seterrno();
    return 0;
}

int unlink(const char *path)
{
    if (hz_delete(path) != 0)
        return __hz_seterrno();
    return 0;
}

int isatty(int fd)
{
    if (fd >= 0 && fd <= 2)
        return 1;
    if (handle_of(fd) >= 0)
        errno = ENOTTY;
    return 0;
}
