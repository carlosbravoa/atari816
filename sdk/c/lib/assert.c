/* assert.c - a failed assert(): the message on stderr, then abort (cc816) */
#include <stdio.h>
#include <stdlib.h>

void __hz_assert(const char *expr, const char *file, unsigned line)
{
    fflush(stdout);
    fprintf(stderr, "assertion failed: %s, file %s, line %u\n", expr, file, line);
    fflush(stderr);
    abort();
}
