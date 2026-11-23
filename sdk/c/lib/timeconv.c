/* timeconv.c - time.h's conversions for cc816: gmtime, localtime (the same: no time
 * zones), mktime, difftime, asctime, ctime, strftime. time_t counts seconds since
 * 1970-01-01 00:00 (lib/time.c: Horizon's clock + 946,684,800). */
#include <time.h>
#include <stdio.h>
#include <string.h>

static const char *const wday[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
                                   "Friday", "Saturday"};
static const char *const mon[] = {"January", "February", "March", "April", "May", "June",
                                  "July", "August", "September", "October", "November",
                                  "December"};
static const unsigned char mdays[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

static int leap(int y)
{
    return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
}

static int monlen(int y, int m)
{
    return mdays[m] + (m == 1 && leap(y));
}

struct tm *gmtime(const time_t *t)
{
    static struct tm tm;
    long s = *t;
    long days;
    int y, m;
    unsigned secs;
    days = s / 86400L;
    s %= 86400L;
    if (s < 0) {
        s += 86400L;
        --days;
    }
    secs = (unsigned)(s % 3600);
    tm.tm_hour = (int)(s / 3600);
    tm.tm_min = (int)(secs / 60);
    tm.tm_sec = (int)(secs % 60);
    tm.tm_wday = (int)((days % 7 + 11) % 7);   /* 1970-01-01 was a Thursday */
    y = 1970;
    for (;;) {
        int n = leap(y) ? 366 : 365;
        if (days < 0) {
            --y;
            days += leap(y) ? 366 : 365;
            continue;
        }
        if (days < n)
            break;
        days -= n;
        ++y;
    }
    tm.tm_year = y - 1900;
    tm.tm_yday = (int)days;
    for (m = 0; days >= monlen(y, m); ++m)
        days -= monlen(y, m);
    tm.tm_mon = m;
    tm.tm_mday = (int)days + 1;
    tm.tm_isdst = 0;
    return &tm;
}

struct tm *localtime(const time_t *t)
{
    return gmtime(t);
}

time_t mktime(struct tm *tm)
{
    long days = 0;
    int y, m;
    time_t t;
    /* months and seconds into range, then the days */
    y = tm->tm_year + 1900 + tm->tm_mon / 12;
    m = tm->tm_mon % 12;
    if (m < 0) {
        m += 12;
        --y;
    }
    if (y >= 1970)
        for (int k = 1970; k < y; ++k)
            days += leap(k) ? 366 : 365;
    else
        for (int k = y; k < 1970; ++k)
            days -= leap(k) ? 366 : 365;
    for (int k = 0; k < m; ++k)
        days += monlen(y, k);
    days += tm->tm_mday - 1;
    t = days * 86400L + tm->tm_hour * 3600L + tm->tm_min * 60L + tm->tm_sec;
    *tm = *gmtime(&t);
    return t;
}

long difftime(time_t a, time_t b)
{
    return a - b;
}

char *asctime(const struct tm *tm)
{
    static char buf[26];
    sprintf(buf, "%.3s %.3s%3d %02d:%02d:%02d %d\n", wday[tm->tm_wday % 7],
            mon[tm->tm_mon % 12], tm->tm_mday, tm->tm_hour, tm->tm_min, tm->tm_sec,
            tm->tm_year + 1900);
    return buf;
}

char *ctime(const time_t *t)
{
    return asctime(localtime(t));
}

size_t strftime(char *s, size_t n, const char *fmt, const struct tm *tm)
{
    size_t k = 0;
    char tmp[32];
    const char *add;
    while (*fmt) {
        if (*fmt != '%') {
            if (k + 1 >= n)
                return 0;
            s[k++] = *fmt++;
            continue;
        }
        ++fmt;
        add = tmp;
        switch (*fmt++) {
        case 'a': sprintf(tmp, "%.3s", wday[tm->tm_wday % 7]); break;
        case 'A': add = wday[tm->tm_wday % 7]; break;
        case 'b': case 'h': sprintf(tmp, "%.3s", mon[tm->tm_mon % 12]); break;
        case 'B': add = mon[tm->tm_mon % 12]; break;
        case 'c': sprintf(tmp, "%.3s %.3s %2d %02d:%02d:%02d %d", wday[tm->tm_wday % 7],
                          mon[tm->tm_mon % 12], tm->tm_mday, tm->tm_hour, tm->tm_min,
                          tm->tm_sec, tm->tm_year + 1900); break;
        case 'd': sprintf(tmp, "%02d", tm->tm_mday); break;
        case 'e': sprintf(tmp, "%2d", tm->tm_mday); break;
        case 'F': sprintf(tmp, "%d-%02d-%02d", tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday); break;
        case 'H': sprintf(tmp, "%02d", tm->tm_hour); break;
        case 'I': sprintf(tmp, "%02d", tm->tm_hour % 12 ? tm->tm_hour % 12 : 12); break;
        case 'j': sprintf(tmp, "%03d", tm->tm_yday + 1); break;
        case 'm': sprintf(tmp, "%02d", tm->tm_mon + 1); break;
        case 'M': sprintf(tmp, "%02d", tm->tm_min); break;
        case 'n': add = "\n"; break;
        case 'p': add = tm->tm_hour < 12 ? "AM" : "PM"; break;
        case 'S': sprintf(tmp, "%02d", tm->tm_sec); break;
        case 't': add = "\t"; break;
        case 'T': case 'X': sprintf(tmp, "%02d:%02d:%02d", tm->tm_hour, tm->tm_min, tm->tm_sec); break;
        case 'R': sprintf(tmp, "%02d:%02d", tm->tm_hour, tm->tm_min); break;
        case 'D': case 'x': sprintf(tmp, "%02d/%02d/%02d", tm->tm_mon + 1, tm->tm_mday, tm->tm_year % 100); break;
        case 'u': sprintf(tmp, "%d", tm->tm_wday ? tm->tm_wday : 7); break;
        case 'w': sprintf(tmp, "%d", tm->tm_wday); break;
        case 'U': sprintf(tmp, "%02d", (tm->tm_yday + 7 - tm->tm_wday) / 7); break;
        case 'W': sprintf(tmp, "%02d", (tm->tm_yday + 7 - (tm->tm_wday + 6) % 7) / 7); break;
        case 'y': sprintf(tmp, "%02d", tm->tm_year % 100); break;
        case 'Y': sprintf(tmp, "%d", tm->tm_year + 1900); break;
        case 'Z': add = ""; break;
        case '%': add = "%"; break;
        default: return 0;
        }
        while (*add) {
            if (k + 1 >= n)
                return 0;
            s[k++] = *add++;
        }
    }
    if (k >= n)
        return 0;
    s[k] = 0;
    return k;
}
