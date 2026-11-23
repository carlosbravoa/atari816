/* hz_heap.h - included in every file of the port after xcompat.h (the Makefile's
 * -include): malloc, calloc and realloc that never return NULL. The main bank's heap is
 * 7 KB and upstream, written for DOS's 640 KB, seldom checks (a board's texts, a macro):
 * out of memory stops the game with a line that says so (hz_dos.c) instead of going on
 * with a null pointer (writes at the main bank's start, a text drawn from address 0). */
#ifndef HZ_HEAP_H
#define HZ_HEAP_H
#include <stddef.h>
void *hz_malloc_or_quit(size_t n);
void *hz_calloc_or_quit(size_t n, size_t size);
void *hz_realloc_or_quit(void *p, size_t n);
/* the heap's state on the console (a board's start: tests/check.sh compares them) */
void hz_heap_report(const char *what, const char *name);
#define malloc(n) hz_malloc_or_quit(n)
#define calloc(n, s) hz_calloc_or_quit(n, s)
#define realloc(p, n) hz_realloc_or_quit(p, n)
#endif
