/* stdarg.h - cc816 (Horizon C SDK). The arguments are on the hardware stack (bank 0), each
 * at least 2 bytes (a char comes as an int), so a va_list is a far pointer into bank 0 and
 * va_arg reads through it. */
#ifndef _STDARG_H
#define _STDARG_H
typedef char __far *va_list;
#define __va_sz(t) (sizeof(t) < 2 ? 2 : sizeof(t))
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, t) (*(t __far *)(((ap) += __va_sz(t)) - __va_sz(t)))
#define va_end(ap) ((void)0)
#define va_copy(d, s) ((d) = (s))
#endif
