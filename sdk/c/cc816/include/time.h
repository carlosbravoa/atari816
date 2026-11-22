/* time.h - cc816 (Horizon C SDK; lib/time.c, lib/cc816/timeconv.c). time() counts seconds
 * since 1970 (Horizon's clock, no time zones); clock() counts 50 a second. */
#ifndef _TIME_H
#define _TIME_H
#include <stddef.h>
#define CLOCKS_PER_SEC 50
#ifndef __TIME_T
#define __TIME_T 1
typedef long time_t;
#endif
#ifndef __CLOCK_T
#define __CLOCK_T 1
typedef long clock_t;
#endif
struct tm {
    int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst;
};
time_t time(time_t *t);
clock_t clock(void);
long difftime(time_t a, time_t b);     /* (a long: no floating point) */
time_t mktime(struct tm *tm);
struct tm *gmtime(const time_t *t);
struct tm *localtime(const time_t *t);
char *asctime(const struct tm *tm);
char *ctime(const time_t *t);
size_t strftime(char *s, size_t n, const char *fmt, const struct tm *tm);
#endif
