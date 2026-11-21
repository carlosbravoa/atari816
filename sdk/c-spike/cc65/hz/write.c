/* write.c - the POSIX-ish write() that cc65's stdio (puts, printf, fputs) ends in.
 * fd 1 and 2 go to the Horizon console (SYS_PUTS, in pieces of at most 128 bytes).
 * Other descriptors: not in this spike (-1, errno EBADF would come with files).
 */
#include <unistd.h>
#include <errno.h>
#include "horizon.h"

static char line[129];

int __fastcall__ write(int fd, const void *buf, unsigned count)
{
    const char *p = (const char *)buf;
    unsigned left = count, n, i;
    if (fd != 1 && fd != 2) { errno = EBADF; return -1; }
    while (left) {
        n = left > 128 ? 128 : left;
        for (i = 0; i < n; ++i) line[i] = p[i];
        line[n] = 0;
        hz_puts(line);
        p += n;
        left -= n;
    }
    return count;
}
