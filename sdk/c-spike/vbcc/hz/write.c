/* write.c - __write(), where vbcc's stdio output ends: the Horizon console (SYS_PUTS),
 * in pieces of at most 128 bytes copied into a zero-terminated buffer. Every fd goes
 * to the console in this spike (no files). */
#include "horizon.h"

static char line[129];

unsigned int __write(int fd, const char *p, unsigned int len)
{
    unsigned int left = len, n, i;
    while (left) {
        n = left > 128 ? 128 : left;
        for (i = 0; i < n; ++i) line[i] = p[i];
        line[n] = 0;
        hz_puts(line);
        p += n;
        left -= n;
    }
    return len;
}
