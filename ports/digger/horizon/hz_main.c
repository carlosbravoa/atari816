/* hz_main.c - Digger's start on Horizon: main() (upstream's main.c is built with
 * -Dmain=digger_main, as upstream's Windows build makes it SDL_main) goes to the program's
 * folder first, so that DIGGER.SCO (the high scores), DIGGER.INI and the recordings are
 * kept next to DIGGER.PRG; then the helpers upstream takes from the system (fbsd_sup.c,
 * digger_log.c). */
#undef main
#include <stdarg.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <horizon.h>
#include "def.h"
#include "digger_log.h"
#include "hz_plat.h"

char hz_progdir[128];
static unsigned long t0;

int digger_main(int argc, char *argv[]);
uint32_t getframe(void);

/* at the end: how long the run took (the recorded games' tests: their speed), and the
 * timing statistics (hz_timer.c) */
static unsigned long avg(unsigned long sum, unsigned long n)
{
    return n ? sum / n : 0;
}

static void report(void)
{
    struct hzt_stats *s = &hzt_st;
    unsigned long ms = (unsigned long)hz_uptime() - t0;
    printf("digger: %lu game frames in %lu.%02lu s\n", (unsigned long)getframe(), ms / 1000,
           ms % 1000 / 10);
    if (!s->frames)
        return;
    printf("digger: paced frames %lu, late %lu, busy %lu ms a frame (most %lu)\n",
           s->frames, s->late, avg(s->busy_us, s->frames) / 1000, s->busy_max / 1000);
    printf("digger: beat: frame starts off 80 ms by %lu us on average (most %lu; %lu "
           "starts after a pause or a level drawn)\n", avg(s->beat_us, s->beat_n), s->beat_max,
           s->beat_far);
    printf("digger: sound: %lu steps, %lu us late on average (most %lu)\n", s->snd_n,
           avg(s->snd_late_us, s->snd_n), s->snd_late_max);
    printf("digger: view: off target at %lu blanks, moved at %lu\n", s->view_need,
           s->view_moves);
    printf("digger: keys: %lu, to their frame %lu ms, to the screen %lu ms (most %lu)\n",
           s->key_n, avg(s->key_frame_us, s->key_n) / 1000, avg(s->key_show_us, s->key_n) / 1000,
           s->key_show_max / 1000);
}

int main(int argc, char *argv[])
{
    int n = hz_prog_dir(hz_progdir, sizeof hz_progdir);
    if (n > 0) {
        if (n > 1)
            hz_progdir[n - 1] = 0;      /* (chdir: without the last '/') */
        hz_chdir(hz_progdir);
        if (n > 1)
            hz_progdir[n - 1] = '/';
    } else
        hz_progdir[0] = 0;
    t0 = (unsigned long)hz_uptime();
    atexit(report);
    return digger_main(argc, argv);
}

void strupr(char *str)
{
    while (*str) {
        *str = (char)toupper((unsigned char)*str);
        str++;
    }
}

/* the log: the console (upstream's digger_log.c locks it for its threads) */
void digger_log_vprintf(const char *fmt, va_list ap)
{
    vfprintf(stdout, fmt, ap);
}

void digger_log_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    digger_log_vprintf(fmt, ap);
    va_end(ap);
}

/* upstream's farmalloc (def.h): a bank of far memory for a buffer of up to 64 KB */
void __far *hz_farmalloc(unsigned long n)
{
    if (n == 0 || n > 0x10000UL)
        return 0;
    return hz_far_alloc();
}

void hz_farfree(void __far *p)
{
    if (p)
        hz_far_free(p);
}
