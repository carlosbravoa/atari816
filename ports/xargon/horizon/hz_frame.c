/* hz_frame.c - the time on Horizon for Xargon's files: the vertical blank (hgame's frame,
 * 60.03 a second), the BIOS clock upstream counts its frames by, the VGA's retrace bit and
 * the game port (the joystick), all from the frame.
 *
 * Upstream's code waits by reading memory an interrupt changes: the BIOS tick at
 * 0040:006C (18.2 a second; the game moves one step a tick), the VGA status register's
 * retrace bit. A Horizon program has no interrupts: each read goes through here, and a
 * read that would see nothing new waits for the next vertical blank (hgame's hg_frame:
 * the events, the sound's ticks) instead of spinning. The tick counts the blanks at
 * 18.2065 / 60.03 (19,876 / 65,536) a blank, so the game runs at the original's speed. */
#include <stdio.h>
#include <stdlib.h>
#include <hgame.h>
#include <horizon.h>
#include "hz_plat.h"
#include "gr.h"
#include "x_obj.h"
#include "xargon.h"

unsigned hzf_frames;
static int tick;                        /* the BIOS tick */
static unsigned frac;                   /* its fraction, in 65536ths */
static unsigned tick_f;                 /* the frame counter the tick was brought to */
static unsigned rd_f, rd_n;             /* the frame of the last read of the tick, reads */
static unsigned lastvbl;                /* the frame counter at the last retrace seen */
static unsigned char zeros;             /* the retrace bit read as 0 since then */
static unsigned joy1, joy2;             /* the joysticks, this frame */
static unsigned gp_reads;               /* reads of the game port since it was fired */
static unsigned char gp_cx, gp_cy;      /* the one-shots' times (in reads / 3) */
unsigned char hzf_stats;
unsigned hzf_busy;                      /* /BUSY:ms: a slower machine (the tests) */
static unsigned long st_frames, st_late, st_blanks, st_busy;
static unsigned st_maxlen, st_maxbusy, st_lastflip, st_tickf, st_lasttick = 0xFFFF;
static unsigned long st_t0;

/* the recorded demo (upstream's macros: gamectrl.c plays the keys of DEMO_MAC.XR0): its
 * start and its end on the console, with where the game is then (tests/check.sh compares
 * the end with tests/demo.ref: the game logic and the compiler, frame for frame) */
extern int macplay, gamecount;
static int demo_on;

static void demo_state(const char *what)
{
    printf("xargon: demo %s at frame %d: score %lu, health %d, emeralds %d, hero %d at "
           "%d, %d, %d objects\n", what, gamecount, pl.score, pl.health, pl.emeralds,
           objs[0].objkind, objs[0].x, objs[0].y, numobjs);
}

static void demo_watch(void)
{
    if (macplay && !demo_on) {
        demo_on = 1;
        printf("xargon: demo started\n");
    } else if (!macplay && demo_on) {
        demo_on = 0;
        demo_state("ended");
    } else if (demo_on == 1 && gamecount >= 1500) {
        demo_on = 2;                    /* (the tests' check point: about 85 s in) */
        demo_state("reached");
    }
}

/* one frame: hgame's (it waits for the next vertical blank: events, the sound's ticks),
 * then the page and palette for the next blank, the keys, the sound effects' ends */
static unsigned served;                 /* the frame counter at the last service */

/* the two joysticks (the kernel's call: hgame reads them once a frame of its own) */
static void joysticks(void)
{
    unsigned d = hz_joystick(), t = hz_x;
    if (hz_errno)
        d = t = 0;
    joy1 = (d & 15) | ((t & 1) ? HG_FIRE : 0);
    joy2 = ((d >> 4) & 15) | ((t & 2) ? HG_FIRE : 0);
}

void hzf_pump(void)
{
    if (!hg_frame())
        exit(0);                        /* (the window closed: Alt+F4) */
    joysticks();
    hzv_display();
    hzk_frame();
    hzs_frame();
    served = hz_frame();
}

/* the events, the keys and the music once a vertical blank even when the game does not
 * wait for one (its frames late: no hzf_pump between them) */
static void service(unsigned f)
{
    if (f == served)
        return;
    served = f;
    if (!hg_poll())
        exit(0);
    joysticks();
    hzk_frame();
    hzs_frame();
}

/* the frame counter, the tick brought up to it */
static unsigned now(void)
{
    unsigned f = hz_frame(), d = f - tick_f;
    unsigned long x;
    tick_f = f;
    if (d > 600)
        d = 600;                        /* (after a pause: no jump of minutes) */
    hzf_frames += d;
    x = (unsigned long)frac + (unsigned long)d * 19876UL;
    tick += (int)(x >> 16);
    frac = (unsigned)x;
    return f;
}

/* upstream's *myclock. Single reads cost nothing; the third read within one vertical
 * blank is a loop waiting for the tick to change: it waits for the next blank (a pump) */
int *hzc_tick(void)
{
    unsigned f = now();
    service(f);
    if ((unsigned)tick != st_lasttick) {    /* (statistics: the blank a tick came at) */
        st_lasttick = (unsigned)tick;
        st_tickf = f;
    }
    if (f == rd_f) {
        if (++rd_n >= 2) {
            hzf_pump();
            f = now();
            rd_n = 0;
        }
    } else
        rd_n = 0;
    rd_f = f;
    return &tick;
}

/* the VGA's input status 1 (3DA): bit 3 in the vertical retrace. The first read after a
 * blank sees it; a read after one of 0 waits for the next blank (a pump); after a page
 * flip, the blank that shows the new page */
unsigned char hzf_retrace(void)
{
    unsigned f = now();
    if (hzv_show != hzv_shown) {
        /* a page flip written (the CRTC's start address): the page drawn (the blitter
         * done) is shown from the next blank on. The game goes on at once; what it draws
         * next waits for that blank only when it is sent before it (hzv_flush) */
        hzv_sync();
        hzv_display();
        hzv_flip_frame = hz_frame();
        hzv_flip_wait = 1;
        zeros = 0;
        service(f);
        demo_watch();                   /* (a game frame has ended) */
        return 9;
    }
    if (f != lastvbl) {
        lastvbl = f;
        zeros = 0;
        return 9;
    }
    if (zeros) {
        hzf_pump();
        lastvbl = now();
        zeros = 0;
        return 9;
    }
    zeros = 1;
    return 0;
}

/* ---------------------------------------------------------------- statistics */

/* A game frame (upstream's play loop: the logic, the drawing, the page flip, the wait for
 * the next BIOS tick) is counted at its page flip: its length in vertical blanks (from the
 * flip before), and "busy": from the blank its tick came at to the flip (the CPU's work in
 * blanks; the tick comes every 3.3 blanks, so a frame busy for 3 or more is late) */

void hzf_flipped(void)
{
    unsigned f, len, busy;
    if (hzf_busy) {                     /* (the CPU kept busy, as on a slower machine) */
        unsigned long t = hz_uptime();
        while (hz_uptime() - t < hzf_busy)
            ;
    }
    f = hz_frame();
    len = f - st_lastflip;
    busy = f - st_tickf;
    st_lastflip = f;
    if (len > 60 || busy > 60) {        /* (a pause, a menu, a level loading: not counted) */
        st_tickf = f;
        return;
    }
    ++st_frames;
    st_blanks += len;
    st_busy += busy;
    if (len > st_maxlen)
        st_maxlen = len;
    if (busy > st_maxbusy)
        st_maxbusy = busy;
    if (busy >= 3)
        ++st_late;
    if (hzf_stats && hz_uptime() - st_t0 >= 10000) {
        hzf_report();
        st_t0 = hz_uptime();
    }
}

extern unsigned long hzv_cnt[4], hzv_fast, hzv_gmade, hzv_gwait;

void hzf_report(void)
{
    printf("xargon: hero %d at %d, %d (state %d), level %d, view %d, %d, score %lu, health %d\n",
           objs[0].objkind, objs[0].x, objs[0].y, objs[0].state, pl.level, gamevp.vpox,
           gamevp.vpoy, pl.score, pl.health);
    {
        extern int vocflag, musicflag, soundf;
        printf("xargon: sound: effects %d, music %d (Lau %d, OPL2 %d, playing %d), noise %d\n",
               vocflag, musicflag, hg_has_lau(), hg_has_opl(), hg_opl_playing(), soundf);
    }
    unsigned long n = st_frames ? st_frames : 1;
    printf("xargon: shapes a frame: %lu queued at once, by hz_vga.c sprites %lu, cells %lu, "
           "font %lu (glyphs made %lu, waits %lu in all)\n", hzv_fast / n, hzv_cnt[0] / n,
           hzv_cnt[3] / n, hzv_cnt[1] / n, hzv_gmade, hzv_gwait);
    printf("xargon: %lu game frames, %lu.%02lu blanks apart (most %u), busy %lu.%02lu blanks "
           "(most %u), %lu late; heap free %u, %u banks free\n", st_frames, st_blanks / n,
           st_blanks * 100 / n % 100, st_maxlen, st_busy / n, st_busy * 100 / n % 100,
           st_maxbusy, st_late, hz_heap_free(), hz_mem_info());
}

/* the game port (201): bits 0 and 1 the X and Y one-shots (high for a time that grows
 * with the stick's position, after a write starts them), bits 4 and 5 the buttons (0 when
 * pressed). Joystick 1's directions; its trigger is button 2 (upstream's fire2: jump),
 * joystick 2's trigger button 1 (fire1: shoot). Positions 10, 20, 30 for left / centre /
 * right (hz_cfg.c calibrates the game for them) */
void hzf_gameport_fire(void)
{
    gp_reads = 0;
    gp_cx = (unsigned char)((joy1 & HG_LEFT) ? 10 : (joy1 & HG_RIGHT) ? 30 : 20);
    gp_cy = (unsigned char)((joy1 & HG_UP) ? 10 : (joy1 & HG_DOWN) ? 30 : 20);
}

unsigned char hzf_gameport(void)
{
    unsigned char v = 0xF0;
    unsigned t = gp_reads / 3;
    if (gp_reads < 1000)
        ++gp_reads;
    if (t < gp_cx)
        v |= 1;
    if (t < gp_cy)
        v |= 2;
    if (joy2 & HG_FIRE)
        v &= (unsigned char)~0x10;
    if (joy1 & HG_FIRE)
        v &= (unsigned char)~0x20;
    return v;
}
