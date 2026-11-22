/* hz_timer.c - Digger's time for Horizon (upstream's sdl_timer.c): the frame pacing, the
 * sound's 72.8 Hz interrupt, the vertical blanks (the view, the screen, the input).
 *
 * The clock. A Horizon program runs no code in interrupts, and the kernel's uptime counts
 * in 10 ms steps, the frame counter in 16.7 ms: neither times a sound step of 13.7 ms. The
 * music timer (sample_timer) can: the kernel sends the program's port a message every
 * 3,434 us (a quarter of a sound step) with the count of periods since the start (the count follows
 * the microsecond clock even when messages are dropped). So the clock is that count x
 * 3,434 us. While the game waits for the end of its frame it sleeps until the next period,
 * or until the next vertical blank when nothing is due before it; while it works (its logic
 * and its drawing, up to 100 ms in a busy scene) the drawing calls look at the clock when,
 * by the work they did, the next sound step or blank should have come (hzt_work, plan).
 * Then:
 *
 *  - the sound's interrupt (soundint) runs when its 13,736 us have come, so the PC
 *    speaker's steps keep their length whatever the game is doing;
 *  - at a vertical blank (the frame counter moved): hgame's frame (the events, the keys),
 *    the view one step nearer to the digger (sent to Marga for the next blank: it glides
 *    at 60 Hz), and, between the game's frames only, the rectangles drawn to the screen.
 *
 * gethrt() is upstream's "wait for the end of the frame": until dgstate.ftime microseconds
 * (80,000: 12.5 frames a second, the original's speed) after the last frame began, to the
 * clock's 3.4 ms. /S:0 (ftime 1): no waiting (the recorded games' tests).
 * Without the music timer (no Lau: before REV $0A) the clock is the frame counter. */
#include <stdio.h>
#include <stdlib.h>
#include <hgame.h>
#include "def.h"
#include "hardware.h"
#include "game.h"
#include "digger.h"
#include "input.h"
#include "main.h"
#include "sound.h"
#include "hz_plat.h"

uint32_t getframe(void);

#define TICK_US  3434UL                 /* the music timer's period: a quarter sound step */
#define FRAME_US 16658UL                /* a vertical blank (60.03 a second) */
#define SND_US   13736UL                /* the sound's interrupt: 72.8 a second */
#define LATE(a, b) ((long)((a) - (b)) >= 0)     /* clock a is at or past b (wraps) */

bool hzt_fast;
bool hzt_title;                         /* the title screen is shown (hz_vid.c) */
extern unsigned hzt_nshots;             /* (the pictures' test, below) */

/* ---------------------------------------------------------------- the clock */

static int tport = -1;                  /* the music timer's port; -1: the frame counter */
static unsigned tcount, lastraw;
static unsigned long clk;               /* microseconds (wraps every 71 minutes) */
static bool clk_on;

static void clock_init(void)
{
    if (clk_on)
        return;
    clk_on = true;
    lastraw = hz_frame();
    tport = hz_port_create();
    if (tport >= 0) {
        hz_sample_timer((unsigned)tport, TICK_US);
        if (hz_errno) {                 /* no Lau (or the timer is another program's) */
            hz_port_close((unsigned)tport);
            tport = -1;
        }
    }
}

static void take(const hz_msg *m)
{
    unsigned c = m->b[2] | (unsigned)m->b[3] << 8, n = c - tcount;
    tcount = c;
    while (n--)                         /* (no multiply: n is small) */
        clk += TICK_US;
}

/* the clock now; block: first sleep until the next period */
static void clock_update(bool block)
{
    hz_msg m;
    if (tport < 0) {
        unsigned f;
        if (block)
            hz_vsync();
        f = hz_frame();
        clk += (unsigned long)(unsigned)(f - lastraw) * FRAME_US;
        lastraw = f;
        return;
    }
    if (block && !hz_recv((unsigned)tport, &m))
        take(&m);
    while (!hz_recv((unsigned)tport | RV_POLL, &m))
        take(&m);
}

/* ---------------------------------------------------------------- statistics */

/* (printed at the end, hz_main.c) the game frames; those that began later than their time
 * (their predecessor's logic and drawing took longer than a frame); the CPU time of a
 * frame; how far the frames' starts were from the 80 ms beat; the sound's steps' delay;
 * the view's moves; the time from a key (as read at a vertical blank) to the frame that
 * reads it and to the screen showing that frame */
struct hzt_stats hzt_st;

/* ---------------------------------------------------------------- the view */

static int view = 0, title_t = 0;

/* where the playfield's view should start (0 .. HZ_VIEW_MAX rows below row 28) */
static int view_target(void)
{
    int i, n = 0, sum = 0;
    if (hzt_title && hzt_nshots)        /* (the pictures' test: the title's top, still) */
        return 0;
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

/* one step a vertical blank: a quarter of the way (at least 1 row, at most 4): the digger
 * moves 6 rows a game frame (5 blanks), the view follows in steps of 1-2 rows */
void hzt_camera(void)
{
    int t = view_target(), v = view, d;
    d = t - v;
    if (d) {
        ++hzt_st.view_need;
        if (d > 0)
            v += d >= 16 ? 4 : (d + 3) / 4;
        else
            v -= -d >= 16 ? 4 : (-d + 3) / 4;
    }
    if (v != view) {
        ++hzt_st.view_moves;
        view = v;
        hg_split(HZ_PANEL, 0, HZ_PANEL + view);
    }
}

/* ---------------------------------------------------------------- the service */

static unsigned long snd_next;          /* when the next sound step is due */
static unsigned vbl_seen;               /* the frame counter at the last blank served */
static unsigned long vbl_clk;
static unsigned long key_t;             /* a key read at a blank, waiting for its frame */
static bool key_wait, key_used;
static unsigned long key_frame_t;

/* the keys player 1 moves and fires with, newly down at this blank? (statistics) */
static void key_watch(void)
{
    unsigned i;
    if (key_wait || key_used)
        return;
    for (i = 0; i < 5; i++)
        if (keycodes[i][0] > 0 && hg_key_pressed((unsigned)keycodes[i][0])) {
            key_t = clk;
            key_wait = true;
            return;
        }
}

/* a vertical blank: hgame's frame (input; the view sent: taken at the next blank) and, when
 * show, the rectangles drawn since to the screen (only between the game's frames: never a
 * half-drawn one) */
static void vblank(bool show)
{
    if (!hg_frame()) {                  /* Alt+F4 (upstream: SDL_QUIT) */
        finish();
        exit(0);
    }
    hg_end();       /* (the frame closed at once: the next hg_frame waits for nothing if
                       a blank came since) */
    if (show) {
        hzv_show();
        if (key_used) {                 /* the frame that read the key is on the screen */
            unsigned long d = clk - key_t;
            key_used = false;
            hzt_st.key_n++;
            hzt_st.key_show_us += d;
            if (d > hzt_st.key_show_max)
                hzt_st.key_show_max = d;
        }
    }
    hzk_poll();
    key_watch();
    hzt_camera();
}

/* the work done (hzt_work's units: bytes drawn + 64 a call) and what a unit costs in
 * microseconds (x 256, learnt as the game goes: the game's own logic between the drawing
 * calls is in it too): the next look at the clock comes after the work that should take
 * until the next sound step or vertical blank */
static unsigned budget;                 /* units of work before the next look */
static unsigned long u_since;           /* units since the clock last moved */
static unsigned long rate = 256;
static unsigned long last_clk;

static void plan(void)
{
    unsigned long next = snd_next, need;
    if (LATE(next, vbl_clk + FRAME_US))
        next = vbl_clk + FRAME_US;
    need = LATE(clk, next) ? 0 : next - clk;
    /* (a little early: the estimate is rough, and the clock is up to a period behind) */
    need = need > 2800 ? need - 2000 : 800;
    need = (need << 8) / rate;
    budget = need > 6144 ? 6144 : need < 128 ? 128 : (unsigned)need;
}

/* the sound's steps that are due, a vertical blank's work if one came (block: first sleep
 * until the clock's next period) */
static void service(bool show, bool block)
{
    unsigned f;
    clock_update(block);
    if (clk != last_clk) {
        if (u_since >= 256 && !block) {
            unsigned long r = ((clk - last_clk) << 8) / u_since;
            rate = (rate * 3 + r) >> 2;
            if (rate < 32)
                rate = 32;
        }
        u_since = 0;
        last_clk = clk;
    }
    while (LATE(clk, snd_next)) {
        unsigned long late = clk - snd_next;
        if (late > 200000UL) {          /* (a stall: start again from now) */
            snd_next = clk;
            late = 0;
        }
        soundint();
        hzt_st.snd_n++;
        hzt_st.snd_late_us += late;
        if (late > hzt_st.snd_late_max)
            hzt_st.snd_late_max = late;
        snd_next += SND_US;
    }
    if (show || clk - vbl_clk >= 14000UL) {     /* (else no blank can have come yet) */
        f = hz_frame();
        if (f != vbl_seen) {
            vbl_seen = f;
            vbl_clk = clk;
            vblank(show);
        }
    }
    plan();
}

/* (hz_vid.c) the drawing calls' work: a look at the clock (a syscall or two, about
 * 0.2 ms) when the work planned (plan) is done */
void hzt_work(unsigned bytes)
{
    unsigned u = bytes + 64;
    u_since += u;
    if (u >= budget)
        service(false, false);
    else
        budget -= u;
}

void hzt_pump(void)
{
    service(true, false);
}

/* ---------------------------------------------------------------- upstream's calls */

static unsigned long target, frame_t;
static bool started;

void inittimer(void)
{
    clock_init();
    clock_update(false);
    target = clk;
    if (!started) {
        started = true;
        snd_next = clk;
        vbl_clk = clk;
    }
}

int32_t getkips(void)
{
    return 1;
}

void olddelay(int16_t t)
{
    (void)t;
}

/* ---------------------------------------------------------------- the pictures' test */

/* SHOTS.TXT next to the program (tests/frames.sh): game frames (upstream's frame count,
 * getframe) at which the picture is to be taken. There the game stops for a moment: the
 * frame drawn goes to the screen, the view goes straight to its place, and when both are
 * shown the program prints "digger: shot N frame F"; the emulator (run816.py --shot-on)
 * takes the picture two vertical blanks later; the picture stays for six. So a picture is
 * of a game frame, whatever the program's timing (its code's place, the clock's phase). */
unsigned long hzt_shots[16];
unsigned hzt_nshots;
static unsigned shot_i;

static void blank_wait(void)            /* the next vertical blank, its work, the screen */
{
    unsigned f = hz_frame();
    while (hz_frame() == f)
        hz_vsync();
    clock_update(false);
    vbl_seen = hz_frame();
    vbl_clk = clk;
    vblank(true);
}

static void shot_check(void)
{
    unsigned i;
    if (shot_i >= hzt_nshots || getframe() != hzt_shots[shot_i])
        return;
    view = view_target();               /* the view at its place at once */
    hg_split(HZ_PANEL, 0, HZ_PANEL + view);
    blank_wait();                       /* the frame drawn shown, the view sent */
    blank_wait();                       /* (the view taken at this blank) */
    printf("digger: shot %u frame %lu\n", shot_i + 1, (unsigned long)getframe());
    for (i = 0; i < 6; i++)
        blank_wait();
    ++shot_i;
}

void gethrt(bool minsleep, int mult)
{
    unsigned long period, busy, d;
    (void)minsleep;
    clock_init();
    if (hzt_nshots && mult == 1)
        shot_check();
    service(true, false);
    if (frame_t && mult == 1 && dgstate.ftime > 1) {
        busy = clk - frame_t;
        hzt_st.frames++;
        hzt_st.busy_us += busy;
        if (busy > hzt_st.busy_max)
            hzt_st.busy_max = busy;
        if (busy > dgstate.ftime)       /* past the end of its frame */
            hzt_st.late++;
    }
    if (dgstate.ftime <= 1) {           /* /S:0: as fast as it goes */
        hzt_fast = true;
        frame_t = clk;
        return;
    }
    hzt_fast = false;
    period = dgstate.ftime / (unsigned long)(mult > 0 ? mult : 1);
    target += period;
    /* far behind (a stall, a pause) or far ahead: start counting from now */
    if (LATE(clk, target + 4 * period) || LATE(target, clk + 4 * period + 1))
        target = clk + period;
    while (!LATE(clk, target)) {
        /* sleep: until the coming vertical blank when the next sound step and the frame's
         * end come after it (the screen's copy then starts right at the blank), else until
         * the clock's next period */
        unsigned long nb = vbl_clk + FRAME_US;
        if (tport >= 0 && LATE(snd_next, nb) && LATE(target, nb)) {
            hz_vsync();
            service(true, false);
        } else
            service(true, true);
    }
    if (mult == 1) {
        if (frame_t) {                  /* the beat: how far from 80 ms after the last */
            d = clk - frame_t;
            d = d > period ? d - period : period - d;
            if (d > 40000UL)            /* (a pause, a level drawn: not the beat) */
                hzt_st.beat_far++;
            else {
                hzt_st.beat_n++;
                hzt_st.beat_us += d;
                if (d > hzt_st.beat_max)
                    hzt_st.beat_max = d;
            }
        }
        frame_t = clk;
        if (key_wait) {                 /* this frame reads the key */
            hzt_st.key_frame_us += clk - key_t;
            key_wait = false;
            key_used = true;
        }
    }
}
