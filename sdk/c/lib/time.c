/* time.c - time() and clock() from Horizon's clock.
 *
 * time(): Horizon counts seconds since 2000-01-01 00:00 (time_get); C's time_t counts
 * from 1970-01-01 (gmtime, localtime, mktime, strftime of the library use that), so
 * 946,684,800 is added. The board has no battery clock: the Desktop and the shell set
 * it at start from /SYSTEM/CLOCK or the PC; never set, it counts from 2000-01-01.
 * clock(): the library's time.h says CLOCKS_PER_SEC is 50, so clock() is the uptime in
 * 20 ms steps. For milliseconds use hz_uptime().
 */
#include <time.h>
#include <horizon.h>

#define EPOCH_2000 946684800L

time_t time(time_t *t)
{
    time_t v = hz_time_get() + EPOCH_2000;
    if (t)
        *t = v;
    return v;
}

clock_t clock(void)
{
    return (clock_t)((unsigned long)hz_uptime() / (1000 / CLOCKS_PER_SEC));
}
