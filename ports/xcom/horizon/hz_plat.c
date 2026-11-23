/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The Atari816 back end (Horizon 0.30, hgame): the DOS model's arena in
   17 banks, mode 13h's A000 IS the full-screen framebuffer (320 x 200,
   stride 320, one bank: the engine draws into it as into a VGA's memory,
   nothing is copied), the 200 rows shown 180 at a time (the view follows
   the pointer: PORTING-NOTES.md "The screen"), keys and mouse from hgame,
   the OPL2 from hg_opl_write, the clock from the microsecond counter (or
   the virtual clock with /V, as the host's, for comparing runs).

   Polling (PORTING-NOTES.md "Polling"): the engine polls the keyboard, the
   mouse and the clock all the time (an 8088 had them for free). Here a
   clock reading is a syscall (uptime_us, about 40 us), so:
   - plat_counts reads it once and converts with 16-bit shifts and adds;
   - plat_poll (from every xd_poll) does the platform's work (hg_poll's
     events, the pointer, the pan, the palette) at most every 8 ms, from the
     clock already read, and the palette only when the DAC was written;
   - where the engine spins waiting for input (two empty keyboard polls
     less than 2 ms apart) the next one waits for the vertical blank
     (hz_vsync: the CPU sleeps), and timer_pace / delay sleep the same way.

   Options before the engine's own: /V the virtual clock and the test
   pictures (plat.h "test runs"; the pointer then moves only by the
   script); /T n the seconds of no input that end a test run; /S the
   blitter's work waited for at once (horizon/hz_bb.c: BENCH's checks read
   the back buffer behind its back). */
#include "xcompat.h"
#include <hgame.h>
#include <horizon.h>
#include "plat.h"

int xcom_main(int argc, char **argv);
void hz_bb_screen(int on);
extern int g_bb_wait;
void xd_init(int argc, char **argv);
extern unsigned char xd_banks[17];

char g_plat_dir[128];
int g_plat_virtual;

static unsigned long clock_counts, last_us, poll_us, key_us;
static unsigned spare_a000, spare_d000; /* the arena's own banks 10 and 13 before mode 13h */
static int screen_on, pan = -1, mx = 160, my = 100, mb;
static int presses[2], press_x[2], press_y[2];
static unsigned vpolls;

/* hgame sends a scroll at hg_end (the frame's end); this program has no frames
   (it keeps its own time and polls: hg_poll): the scroll is sent at once
   (PORTING-NOTES.md, SDK needs: an hgame call for it) */
extern hz_fsscroll hg__scr;
extern unsigned char hg__scr_dirty;

static void send_view(void)
{
    if (hg__scr_dirty) {
        hz_fs_scroll(&hg__scr);
        hg__scr_dirty = 0;
    }
}

int plat_arena(void)
{
    unsigned i;
    void __far *b;

    for (i = 0; i < 17; i++) {
        b = hz_far_alloc();
        if (!b)
            return -1;
        xd_banks[i] = (unsigned char)HZ_BANK(b);
    }
    spare_a000 = xd_banks[10];
    spare_d000 = xd_banks[13];
    xd_mem = (xd_ptr)xd_mkfp(0, 0);
    return 0;
}

#define XD_TICK_STEP 60

/* PIT counts (1.193182 a microsecond): d + d/8 + d/16 + d/256 + d/512 is
   1.193359 d (0.015 % fast), in 16-bit steps for the usual short gaps. */
unsigned long plat_counts(void)
{
    unsigned long us, d;

    if (g_plat_virtual) {
        clock_counts += XD_TICK_STEP;
        return clock_counts;
    }
    us = (unsigned long)hg_us();
    d = us - last_us;
    last_us = us;
    if (d < 0x10000UL) {
        unsigned w = (unsigned)d;
        clock_counts += d + (w >> 3) + (w >> 4) + (w >> 8) + (w >> 9);
    } else
        clock_counts += (d * 611UL) >> 9;
    return clock_counts;
}

unsigned long plat_now(void)
{
    return clock_counts;
}

void plat_wait_counts(unsigned long n)
{
    clock_counts += n;
}

/* The engine waits for time (timer_pace, delay): the CPU sleeps through
   whole frames while more than one is left. */
void plat_sleep_counts(unsigned long n)
{
    unsigned long t0 = plat_counts();

    while (n > 20000UL && plat_counts() - t0 < n - 20000UL) {
        hz_vsync();
        xd_poll();
    }
    while (plat_counts() - t0 < n)
        xd_poll();
}

/* HID usage -> PC scan code (the BIOS's high byte). */
static unsigned char scan_of(unsigned u)
{
    static const char row1[] = "qwertyuiop", row2[] = "asdfghjkl", row3[] = "zxcvbnm";
    const char *p;
    char c;

    if (u >= 0x04 && u <= 0x1D) {
        c = (char)('a' + u - 0x04);
        if ((p = strchr(row1, c)) != NULL) return (unsigned char)(0x10 + (p - row1));
        if ((p = strchr(row2, c)) != NULL) return (unsigned char)(0x1E + (p - row2));
        if ((p = strchr(row3, c)) != NULL) return (unsigned char)(0x2C + (p - row3));
    }
    if (u >= 0x1E && u <= 0x27)
        return (unsigned char)(0x02 + u - 0x1E);
    if (u >= 0x3A && u <= 0x43)
        return (unsigned char)(0x3B + u - 0x3A);        /* F1-F10 */
    switch (u) {
    case 0x28: return 0x1C;     /* Enter */
    case 0x29: return 0x01;     /* Esc */
    case 0x2A: return 0x0E;     /* Backspace */
    case 0x2B: return 0x0F;     /* Tab */
    case 0x2C: return 0x39;     /* Space */
    case 0x2D: case 0x56: return 0x0C;  /* - */
    case 0x2E: case 0x57: return 0x0D;  /* = + */
    case 0x4A: return 0x47;     /* Home */
    case 0x4B: return 0x49;     /* PgUp */
    case 0x4C: return 0x53;     /* Del */
    case 0x4D: return 0x4F;     /* End */
    case 0x4E: return 0x51;     /* PgDn */
    case 0x4F: return 0x4D;     /* Right */
    case 0x50: return 0x4B;     /* Left */
    case 0x51: return 0x50;     /* Down */
    case 0x52: return 0x48;     /* Up */
    }
    return 0;
}

static unsigned keyq[16];
static int keyn;

/* The screen as the model has it: the DAC when it was written, the pan
   (the 180 rows shown of 200) where the pointer is. */
static int view_on, vtop;               /* the battle view shown split, its top row */
#define VIEW_SPLIT 124                  /* screen lines of the view; the panel's 56 below */

/* The screen as the model has it: the DAC when it was written, and which of
   the 200 rows the 180 lines show. Normally they follow the pointer: at
   screen line s it is at row s + s * 20 / 179, and the lines show rows from
   s * 20 / 179 (every row reachable, the view moving a row for 9 of the
   pointer). On the battle view the panel (rows 144-199) is shown whole at
   lines 124-179 (Marga's split) and lines 0-123 show 124 of the view's 144
   rows, following the pointer while it is over them. The virtual clock's
   runs follow the engine's pointer (the same pictures as the host's). */
static void show(void)
{
    int i, k, t = vtop;

    if (!screen_on)
        return;
    if (view_on) {
        if (g_plat_virtual) {
            if (my < 144)
                t = my * 20 / 143;
        } else if (hg_mouse_y < VIEW_SPLIT)
            t = hg_mouse_y * 20 / (VIEW_SPLIT - 1);
        k = 1000 + t;
    } else
        k = g_plat_virtual ? my * 20 / 199 : (int)((unsigned)hg_mouse_y * 20u / 179u);
    if (k != pan) {
        if (view_on) {
            vtop = t;
            hg_scroll(0, vtop);
            if (pan < 1000)
                hg_split(VIEW_SPLIT, 0, 144);
        } else {
            if (pan >= 1000)
                hg_split(0, 0, 0);
            hg_scroll(0, k);
        }
        pan = k;
        send_view();
    }
    if (xd_dac_dirty) {
        static unsigned char rgb[768];
        xd_dac_dirty = 0;
        for (i = 0; i < 768; i++)
            rgb[i] = (unsigned char)(xd_dac[i] << 2 | xd_dac[i] >> 4);
        hg_palette(0, 256, rgb);
    }
}

void plat_view(int on)
{
    if (on != view_on) {
        view_on = on;
        show();
    }
}

/* screen line s (the real pointer) -> the model's row */
static int row_of(int s)
{
    if (view_on)
        return s < VIEW_SPLIT ? s + vtop : s + 20;
    return s + (int)((unsigned)s * 20u / 179u);
}

void plat_poll(void)
{
    unsigned k, b;
    int i;

    if (g_plat_virtual) {
        /* a test run: the script is the input; the system's events now and
           then (the clock is the model's, not read here) */
        if (++vpolls & 63)
            return;
        if (!hg_poll())
            exit(0);
        show();
        return;
    }
    if (last_us - poll_us < 8000UL)
        return;
    poll_us = last_us;
    if (!hg_poll())
        exit(0);
    while ((k = hg_key_next()) != 0)
        if (keyn < 16) {
            unsigned ch = k >> 8;
            if (ch == '\n')
                ch = 13;
            keyq[keyn++] = (unsigned)scan_of(k & 0xFF) << 8 | (ch & 0xFF);
        }
    if (screen_on) {
        /* the pointer in 320 x 200: the 180 rows shown follow it. Its position
           now (ws_mouse: hgame's full screen gets motion events only while a
           button is held), halved from the kernel's 640 x 360 */
        hz_mouse m;
        b = hz_ws_mouse(0xFF, &m);
        if (b == 0xFFFF)
            b = hg_mouse_b;
        else {
            hg_mouse_x = m.sx >> 1;
            hg_mouse_y = m.sy >> 1;
        }
        b |= hg_mouse_b & 3;            /* (a click between two polls) */
        mx = hg_mouse_x;
        show();                         /* (the rows shown move first) */
        my = row_of(hg_mouse_y);
        for (i = 0; i < 2; i++)
            if ((b & (1u << i)) && !(mb & (1 << i))) {
                presses[i]++;
                press_x[i] = mx;
                press_y[i] = my;
            }
        mb = (int)(b & 3);
    }
}

unsigned plat_key(void)
{
    unsigned k;

    if (g_plat_virtual)
        return 0;
    plat_poll();
    if (!keyn) {
        /* nothing: an engine that asks again within 2 ms is only waiting
           for input; it sleeps to the next frame */
        if (last_us - key_us < 2000UL) {
            hz_vsync();
            poll_us = 0;                /* the events of that frame at the next poll */
        }
        key_us = last_us;
        return 0;
    }
    k = keyq[0];
    memmove(keyq, keyq + 1, --keyn * sizeof keyq[0]);
    return k;
}

void plat_mouse(int *x, int *y, int *buttons)
{
    *x = mx;
    *y = my;
    *buttons = mb;
}

int plat_mouse_press(int b, int *x, int *y)
{
    int n = presses[b & 1];

    presses[b & 1] = 0;
    *x = press_x[b & 1];
    *y = press_y[b & 1];
    return n;
}

void plat_mouse_set(int x, int y)
{
    mx = x;
    my = y;
}

static int exit_shot;

static void at_end(void)
{
    if (screen_on)
        xd_shot_point(0, "exit");
}

void plat_setmode(int m)
{
    if (m == 0x13 && !screen_on) {
        /* rows 0-199 mode 13h's screen, 205-348 the battle view's back buffer,
           349-388 its cursor box (horizon/hz_bb.c) */
        if (hg_screen_fb(HG_320X180, "X-COM", 320, 400) < 0) {
            printf("xcom: no full screen\n");
            exit(1);
        }
        hg_palette_black();
        xd_banks[10] = (unsigned char)hg_fb_bank;   /* A000 is the framebuffer */
        xd_banks[13] = (unsigned char)(hg_fb_bank + 1); /* D004 its row 205 (plat.h) */
        hz_bb_screen(1);
        screen_on = 1;
        pan = -1;
        xd_dac_dirty = 1;
        if (g_plat_shots && !exit_shot) {
            exit_shot = 1;
            atexit(at_end);             /* (after hg_close's: run before it) */
        }
    } else if (m != 0x13 && screen_on) {
        hz_bb_screen(0);
        view_on = 0;
        hg_close();
        xd_banks[10] = (unsigned char)spare_a000;
        xd_banks[13] = (unsigned char)spare_d000;
        screen_on = 0;
    }
}

void plat_present(int x0, int y0, int x1, int y1)
{
    (void)x0; (void)y0; (void)x1; (void)y1;
}

void plat_opl(int reg, int val)
{
    hg_opl_write((unsigned)reg, (unsigned)val);
}

void plat_note(const char *s)
{
    printf("%s\n", s);
}

/* A test picture (plat.h): the screen shown as the model has it, the line,
   then the screen held still for four frames (the emulator's --shot-on
   takes its picture two frames after the line; the virtual clock does not
   move meanwhile). */
void plat_shot(unsigned n, unsigned long ms, unsigned long sum, const char *why)
{
    int i;

    show();
    printf("xcom: shot %u at %lu ms sum %08lx (%s) pan %d\n", n, ms, sum, why, pan);
    for (i = 0; i < 4; i++)
        hz_vsync();
}

void hz_bb_stats(void);

void plat_end(void)
{
    hz_bb_stats();
    printf("xcom: end at %lu ms\n", clock_counts / 1193UL);
    exit(0);
}

/* "@FILE" among the arguments: the words of FILE in its place (the shell's line holds
   about 70 characters; a test's options are longer: tests/*.args) */
static char *more_argv[40];
static char more_text[512];

static int args_from_file(int argc, char **argv, char ***out)
{
    int i, n = 0;
    for (i = 0; i < argc && n < 39; i++) {
        if (argv[i][0] == '@' && n < 38) {
            FILE *f = fopen(argv[i] + 1, "r");
            size_t len;
            char *p;
            if (!f)
                continue;
            len = fread(more_text, 1, sizeof more_text - 1, f);
            fclose(f);
            more_text[len] = 0;
            for (p = strtok(more_text, " \t\r\n"); p && n < 39; p = strtok(NULL, " \t\r\n"))
                more_argv[n++] = p;
        } else
            more_argv[n++] = argv[i];
    }
    more_argv[n] = NULL;
    *out = more_argv;
    return n;
}

int main(int argc, char **argv)
{
    int i = 1;

    argc = args_from_file(argc, argv, &argv);

    for (;;) {
        if (i < argc && !strcmp(argv[i], "/V")) {
            g_plat_virtual = 1;
            g_plat_shots = 1;
            i++;
        } else if (i < argc && !strcmp(argv[i], "/S")) {
            g_bb_wait = 1;
            i++;
        } else if (i + 1 < argc && !strcmp(argv[i], "/T")) {
            g_plat_idle = (unsigned)atoi(argv[i + 1]);
            i += 2;
        } else
            break;
    }
    if (hz_prog_dir(g_plat_dir, sizeof g_plat_dir) < 0)
        g_plat_dir[0] = 0;
    if (g_plat_dir[0])
        hz_chdir(g_plat_dir);
    g_plat_dir[0] = 0;                  /* names relative to the program's folder */
    if (plat_arena()) {
        printf("xcom: not enough memory (17 banks for the DOS memory)\n");
        return 1;
    }
    argv[i - 1] = "XCOMXT";
    xd_init(argc - i + 1, argv + i - 1);
    printf("xcom: start\n");
    return xcom_main(argc - i + 1, argv + i - 1);
}
