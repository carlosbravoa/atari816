/* SPDX-License-Identifier: GPL-3.0-or-later */
/* src/timer.c's interface (timer.h) on the platform's clock: upstream's
   reprograms the PIT and hooks INT 08h; here the clock is plat_counts()
   (PIT counts) and the hook (the music, 72.8 Hz) is called from
   timer_read and xd_poll whenever its time has come, as the interrupt
   would have between two of the engine's instructions. */
#include "xcompat.h"
#include "plat.h"
#include "input.h"
#include "timer.h"

#define FAST_DIV 16384u

static void (*tick_hook)(void);
static unsigned long hook_next;
static int in_hook;
int g_pace_log;

void timer_run_hook(void)
{
    unsigned long now;
    int n = 0;

    if (!tick_hook || in_hook)
        return;
    now = plat_counts();
    in_hook = 1;
    while ((long)(now - hook_next) >= 0 && n++ < 8) {
        hook_next += FAST_DIV;
        tick_hook();
    }
    if ((long)(now - hook_next) >= 0)
        hook_next = now + FAST_DIV;     /* far behind: no catching up */
    in_hook = 0;
}

void timer_init(void)
{
}

void timer_hook(void (*fn)(void))
{
    if (fn && !tick_hook)
        hook_next = plat_counts() + FAST_DIV;
    tick_hook = fn;
}

void timer_shutdown(void)
{
    tick_hook = 0;
}

unsigned long timer_read(void)
{
    unsigned long t = plat_counts();

    timer_run_hook();
    return t;
}

unsigned long timer_ms(unsigned long counts)
{
    return counts / 1193UL;
}

void timer_pace(unsigned long t0, unsigned ms, int what)
{
    unsigned long lim = ms * 1193UL, now = plat_counts();

    if (now - t0 < lim) {
        if (g_plat_virtual)
            plat_wait_counts(lim - (now - t0));
        else
            while (timer_read() - t0 < lim)
                xd_poll();
    }
    if (g_pace_log && what)
        log_printf("PACE %c %u %lu", what, ms, (timer_read() - t0) / 1193UL);
}
