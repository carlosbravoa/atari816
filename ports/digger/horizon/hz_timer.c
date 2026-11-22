/* hz_timer.c - Digger's frame timing for Horizon (upstream's sdl_timer.c), and the view.
 *
 * gethrt() is upstream's "wait for the end of the frame": the game draws a frame, then
 * waits until dgstate.ftime microseconds (80,000 by default: 12.5 frames a second, the
 * original's speed) have passed since the last one. The clock here is Marga's frame
 * counter (60.03 a second, 16,658 us each); the wait is hgame's frames (events, keys, the
 * sound's ticks, the view moved). /S:0 (ftime 1): no waiting at all (the recorded games'
 * tests), the events still read once a frame. */
#include <stdlib.h>
#include <hgame.h>
#include "def.h"
#include "hardware.h"
#include "game.h"
#include "digger.h"
#include "input.h"
#include "main.h"
#include "hz_plat.h"

#define FRAME_US 16658UL

bool hzt_fast;
bool hzt_title;                         /* the title screen is shown (hz_vid.c) */

static unsigned long now_us;            /* the frame counter, in microseconds */
static unsigned lastraw;
static unsigned long target;
static bool clock_on;

static void clock_update(void)
{
    unsigned f = hz_frame();
    if (!clock_on) {
        clock_on = true;
        lastraw = f;
    }
    now_us += (unsigned long)(unsigned)(f - lastraw) * FRAME_US;
    lastraw = f;
}

/* ---------------------------------------------------------------- the view */

static int view = 0, title_t = 0;

/* where the playfield's view should start (0 .. HZ_VIEW_MAX rows below row 28) */
static int view_target(void)
{
    int i, n = 0, sum = 0;
    if (hzt_title) {
        /* the title: its top part 6 s, then down to show the bottom line (the copyright)
         * 3 s, and up again; a key that changes the mode brings the top back */
        if (mode_change)
            title_t = 0;
        ++title_t;
        if (title_t >= 60 * 6 + 40 + 60 * 3 + 40)
            title_t = 0;
        if (title_t < 360)
            return 0;
        if (title_t < 400)
            return title_t - 360;
        if (title_t < 580)
            return HZ_VIEW_MAX;
        return HZ_VIEW_MAX - (title_t - 580);
    }
    title_t = 0;
    for (i = 0; i < dgstate.diggers; i++)
        if (digalive(i)) {
            sum += diggery(i) * 2 + 15;
            ++n;
        }
    if (!n)
        return view;
    /* the digger in the middle of the 332 rows shown */
    i = sum / n - (HZ_PANEL + (360 - HZ_PANEL) / 2);
    return i < 0 ? 0 : i > HZ_VIEW_MAX ? HZ_VIEW_MAX : i;
}

void hzt_camera(void)
{
    int t = view_target(), v = view;
    if (t > v)
        v += t - v > 3 ? 3 : t - v;
    else if (t < v)
        v -= v - t > 3 ? 3 : v - t;
    if (v != view) {
        view = v;
        hg_split(HZ_PANEL, 0, HZ_PANEL + view);
    }
}

/* ---------------------------------------------------------------- frames */

/* one of hgame's frames: wait for the vertical blank, read the events and keys, the
 * sound's interrupts that are due, the view */
static unsigned lastpump;

void hzt_pump(void)
{
    if (!hg_frame()) {                  /* Alt+F4 (upstream: SDL_QUIT) */
        finish();
        exit(0);
    }
    if (hzt_fast)
        hg_end();       /* (now: the next hg_frame waits for nothing if a blank came) */
    hzv_show();                         /* the frame drawn, while the beam is at the top */
    clock_update();
    lastpump = lastraw;
    hzk_poll();
    hzs_tick();
    hzt_camera();
}

void inittimer(void)
{
    clock_update();
    target = now_us;
}

int32_t getkips(void)
{
    return 1;
}

void olddelay(int16_t t)
{
    (void)t;
}

/* the statistics (hzt_stats, at the end): game frames, those that came late (their
 * drawing and logic took longer than the frame), and the CPU time they took */
unsigned long hzt_frames, hzt_late, hzt_busy_us, hzt_maxbusy_us;
static unsigned long busy_from;

void gethrt(bool minsleep, int mult)
{
    unsigned long period, busy;
    (void)minsleep;
    clock_update();
    if (busy_from && mult == 1) {
        busy = now_us - busy_from;
        hzt_busy_us += busy;
        if (busy > hzt_maxbusy_us)
            hzt_maxbusy_us = busy;
        ++hzt_frames;
        if (now_us > target + dgstate.ftime)    /* past the end of this frame already */
            ++hzt_late;
    }
    if (dgstate.ftime <= 1) {           /* /S:0: as fast as it goes */
        hzt_fast = true;
        if (hz_frame() != lastpump)
            hzt_pump();
        return;
    }
    hzt_fast = false;
    period = dgstate.ftime / (unsigned long)(mult > 0 ? mult : 1);
    target += period;
    /* far behind (a stall, a pause) or far ahead: start counting from now */
    if (now_us > target + 4 * period || target > now_us + 4 * period)
        target = now_us + period;
    do
        hzt_pump();
    while (now_us < target);
    busy_from = now_us;
}
