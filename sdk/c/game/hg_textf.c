/* hg_textf.c - hgame: printf-style text (its own file: only games that use it link the
 * printf code). */
#include <stdio.h>
#include <stdarg.h>
#include "hg_int.h"

void hg_textf(int x, int y, unsigned ink, const char *fmt, ...)
{
    char buf[96];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    hg_text(x, y, buf, ink);
}
