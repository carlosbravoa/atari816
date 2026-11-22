/* strings.h - POSIX's: the case-blind comparisons (also in string.h, as glibc has them),
 * for programs that include this header for them (Digger's ini.c). */
#ifndef _STRINGS_H
#define _STRINGS_H
#include <stddef.h>
int strcasecmp(const char *a, const char *b);
int strncasecmp(const char *a, const char *b, size_t n);
#endif
