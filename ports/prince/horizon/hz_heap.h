/* hz_heap.h - included first in every file of the port (the Makefile's -include): malloc,
 * calloc and realloc that never return NULL. The main bank's heap is 12 KB and upstream,
 * written for a PC, seldom checks: out of memory stops the game with a line that says so
 * (hz_sys.c) instead of going on with a null pointer (writes at the main bank's start, or
 * a resource silently not loaded). */
#ifndef HZ_HEAP_H
#define HZ_HEAP_H
#include <stddef.h>
void *hz_malloc_or_quit(size_t n);
void *hz_calloc_or_quit(size_t n, size_t size);
void *hz_realloc_or_quit(void *p, size_t n);
#define malloc(n) hz_malloc_or_quit(n)
#define calloc(n, s) hz_calloc_or_quit(n, s)
#define realloc(p, n) hz_realloc_or_quit(p, n)
#endif
