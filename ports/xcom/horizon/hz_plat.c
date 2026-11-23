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
static unsigned long load_t0;           /* the start (the loading screen), until the first input wait */
static unsigned spare_a000, spare_d000; /* the arena's own banks 10 and 13 before mode 13h */
static int screen_on, pan = -1, mx = 160, my = 100, mb;
static int presses[2], press_x[2], press_y[2];
static unsigned vpolls;

/* hgame sends a scroll at hg_end (the frame's end) or at hg_poll; this program has
   no frames (it keeps its own time and polls): the view is sent at once,
   hg_view_send() */

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


/* The microsecond clock (hg_us: 32 bits, it wraps every 71.6 minutes the machine is
   on). /U n adds n to it (tests: a machine on for a long time, its wrap a few seconds
   after the start). Only differences of two readings are used, which the wrap does not
   disturb (unsigned arithmetic). */
static unsigned long us_offset;

unsigned long plat_us(void)
{
    return (unsigned long)hg_us() + us_offset;
}

/* PIT counts (1.193182 a microsecond) from microseconds d: d + d/8 + d/16 + d/256 +
   d/512 is 1.193359 d (0.015 % fast), in 16-bit steps for the usual short gaps; a
   long gap (a load, the first reading) in two parts, so that no product passes 32
   bits (d * 611 did from 7 s on). */
unsigned long plat_us_to_counts(unsigned long d)
{
    if (d < 0x10000UL) {
        unsigned w = (unsigned)d;
        return d + (w >> 3) + (w >> 4) + (w >> 8) + (w >> 9);
    }
    return (d >> 9) * 611UL + (((unsigned)d & 511u) * 611UL >> 9);
}

unsigned long plat_counts(void)
{
    unsigned long us;

    if (g_plat_virtual) {
        clock_counts += XD_TICK_STEP;
        return clock_counts;
    }
    us = plat_us();
    if (us < last_us && last_us - us > 0x80000000UL)
        printf("xcom: the microsecond clock wrapped (at %lu ms of play)\n", clock_counts / 1193UL);
    clock_counts += plat_us_to_counts(us - last_us);
    last_us = us;
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
static int loading;

static void show(void)
{
    int i, k, t = vtop;

    if (!screen_on || loading)
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
        hg_view_send();
    }
    if (xd_dac_dirty) {
        static unsigned char __far rgb[768];  /* (__far: out of the main bank, which is full) */
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
        /* the pointer in 320 x 200: the 180 rows shown follow it. hgame's
           hg_mouse_x/y follow the mouse in 320 x 180 (halved from the kernel's
           640 x 360), a button held or not; the presses are counted here, from the
           buttons held at each poll (not hg_mouse_clicked: the engine's INT 33h
           counts presses per button, with the place of the last one) */
        b = hg_mouse_b;
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
    if (load_t0) {
        /* the first wait for input: the start menu (how long the start took); the
           loading screen ends, the engine's screen and palette are shown */
        loading = 0;
        pan = -1;
        xd_dac_dirty = 1;
        show();
        printf("xcom: ready for input %lu ms after the start, %lu KB read (machine on %lu ms)\n",
               (plat_us() - load_t0) / 1000UL, xd_bytes_read / 1024UL,
               (unsigned long)hz_uptime());
        load_t0 = 0;
    }
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

/* ---------------------------------------------------------------- the screen of the
   program's own: loading, messages. The full screen (320 x 400: rows 0-199 mode 13h's
   screen, 205-348 the battle view's back buffer, 349-388 its cursor box,
   horizon/hz_bb.c) is opened at the start for the loading screen and kept for the
   engine's mode 13h. */
static int fb_open;
static unsigned long load_drawn;
static unsigned load_x;

static int screen_fb(void)
{
    if (fb_open)
        return 0;
    if (hg_screen_fb(HG_320X180, "X-COM", 320, 400) < 0)
        return -1;
    fb_open = 1;
    return 0;
}

static void text_centre(int y, const char *t, unsigned ink)
{
    hg_text((320 - (int)strlen(t) * HG_FONT_W) / 2, y, t, ink);
}

/* What is read before the start menu (measured: the engine's reads from the start to
   its first wait for input, about 70 KB with NOINTRO); the bar is full there */
#define LOAD_BYTES 72000UL
#define BAR_X 60
#define BAR_W 200
#define LOAD_Y 205                      /* the loading screen's rows: 205-384 */
#define BAR_Y (LOAD_Y + 112)

/* The loading screen: in rows 205-384 (the battle view's, unused until a battle), shown
   from the start until the engine first waits for input (its start menu, or the intro),
   so that its own black screen while it loads is not seen; the engine's palette waits
   till then. Not in test runs (/V: the screen is the model's from the start). */
static void loading_screen(void)
{
    if (g_plat_virtual || screen_fb() < 0)
        return;
    hg_color(0, 0, 0, 0);
    hg_color(1, 0xE0, 0xE0, 0xE0);
    hg_color(2, 0x40, 0x60, 0xA0);
    hg_color(3, 0x90, 0xB0, 0xF0);
    hg_fill(0, LOAD_Y, 320, 180, 0);
    text_centre(LOAD_Y + 60, "X-COM: UFO DEFENSE", 3);
    text_centre(LOAD_Y + 76, "XCOM-XT on the Atari816", 1);
    text_centre(LOAD_Y + 96, "Loading...", 1);
    hg_rect(BAR_X - 2, BAR_Y - 2, BAR_W + 4, 12, 2);
    hg_flush(0);
    hg_scroll(0, LOAD_Y);
    hg_view_send();
    loading = 1;
    load_x = 0;
    load_t0 = load_drawn = plat_us();
}

/* after each read: the bar, at most every 50 ms */
void plat_progress(void)
{
    unsigned long now, b;
    unsigned x;

    if (!loading)
        return;
    now = plat_us();
    if (now - load_drawn < 50000UL)
        return;
    load_drawn = now;
    b = xd_bytes_read > LOAD_BYTES ? LOAD_BYTES : xd_bytes_read;
    x = (unsigned)(b * BAR_W / LOAD_BYTES);
    if (x > load_x) {
        hg_fill(BAR_X + (int)load_x, BAR_Y, (int)(x - load_x), 8, 3);
        hg_flush(0);
        load_x = x;
    }
}

/* A message the player must see (the data missing, the engine stopped): the screen
   cleared, the lines centred, until a key or a click (2 minutes at most); also on the
   console ("xcom: message: ..."). */
static void message_screen(const char *const *lines, int n)
{
    int i, y;
    unsigned long t0;

    for (i = 0; i < n; i++)
        printf("xcom: message: %s\n", lines[i]);
    loading = 0;
    if (screen_fb() < 0)
        return;
    if (screen_on) {
        hz_bb_screen(0);
        hg_split(0, 0, 0);
        hg_scroll(0, 0);
        hg_view_send();
    }
    hg_color(0, 0, 0, 0);
    hg_color(1, 0xE0, 0xE0, 0xE0);
    hg_color(3, 0x90, 0xB0, 0xF0);
    hg_fill(0, 0, 320, 200, 0);
    y = (180 - n * 12) / 2;
    for (i = 0; i < n; i++, y += 12)
        text_centre(y, lines[i], i ? 1 : 3);
    hg_flush(1);
    t0 = plat_us();
    while (hg_frame()) {
        if (hg_key_next() || hg_mouse_b)
            break;
        if (plat_us() - t0 > 120000000UL)
            break;
    }
}

/* The engine's printf (compat/xdos.h): to the console as before, its last lines kept
   for the message when it stops with an error (xd_exit) */
#undef printf
#undef exit
static char said[3][48];
static int nsaid;

int xd_printf(const char *fmt, ...)
{
    char b[200], *p, *q;
    va_list ap;
    int n;

    va_start(ap, fmt);
    n = vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    fputs(b, stdout);
    for (p = b; *p; p = q) {
        q = strchr(p, '\n');
        if (!q)
            q = p + strlen(p);
        if (q > p && strncmp(p, "xcom:", 5)) {
            int k = nsaid < 3 ? nsaid++ : 2;
            if (nsaid == 3 && k == 2) {
                memmove(said[0], said[1], sizeof said[0]);
                memmove(said[1], said[2], sizeof said[0]);
            }
            int m = (int)(q - p) < 47 ? (int)(q - p) : 47;
            memcpy(said[k], p, (size_t)m);
            said[k][m] = 0;
        }
        if (*q)
            q++;
    }
    return n;
}

/* exit with an error: what the engine said, on the screen first */
void xd_exit(int code)
{
    if (code) {
        const char *l[6];
        int n = 0, i;
        l[n++] = "X-COM stopped:";
        for (i = 0; i < nsaid; i++)
            l[n++] = said[i];
        if (!nsaid)
            l[n++] = "(an error, see the console)";
        l[n++] = "";
        l[n++] = "Press a key.";
        message_screen(l, n);
    }
    exit(code);
}

void plat_setmode(int m)
{
    if (m == 0x13 && !screen_on) {
        if (screen_fb() < 0) {
            printf("xcom: no full screen\n");
            exit(1);
        }
        if (!loading)
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
        fb_open = 0;
        xd_banks[10] = (unsigned char)spare_a000;
        xd_banks[13] = (unsigned char)spare_d000;
        screen_on = 0;
    }
}

void plat_present(int x0, int y0, int x1, int y1)
{
    (void)x0; (void)y0; (void)x1; (void)y1;
}

void hz_snd_opl(int reg, int val);
void hz_snd_start(void);

void plat_opl(int reg, int val)
{
    hz_snd_opl(reg, val);               /* (horizon/hz_snd.c: the music task's, else the OPL2) */
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

/* the banks this program holds now (its code, the DOS memory, the framebuffer, the
   atlas sheets, ...): what APP.INF's mem= must cover */
static unsigned my_banks(void)
{
    hz_taskinfo t;
    unsigned i, me = hz_getpid();

    for (i = 0; i < 16; i++)
        if (!hz_task_info(i, &t) && t.id == me)
            return t.banks;
    return 0;
}

void plat_end(void)
{
    hz_bb_stats();
    printf("xcom: %u banks held\n", my_banks());
    /* (the machine's own time too: how long a test run takes in the emulator) */
    printf("xcom: end at %lu ms (machine %lu s)\n", clock_counts / 1193UL,
           (unsigned long)hz_uptime() / 1000UL);
    exit(0);
}

/* "@FILE" among the arguments: the words of FILE in its place (the shell's line holds
   about 70 characters; a test's options are longer: tests/*.args) */
static char *more_argv[40];
static char __far more_text[512];       /* (__far: out of the full main bank) */

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
        } else if (i + 1 < argc && !strcmp(argv[i], "/U")) {
            us_offset = strtoul(argv[i + 1], NULL, 10);
            i += 2;
        } else
            break;
    }
    if (hz_prog_dir(g_plat_dir, sizeof g_plat_dir) < 0)
        g_plat_dir[0] = 0;
    if (g_plat_dir[0])
        hz_chdir(g_plat_dir);
    {
        /* the game's data: the packs XCOMCONV made from the player's own copy, in the
           program's folder (README.TXT) */
        hz_fileinfo st;
        if (hz_stat_path("PACKS.VER", &st) < 0 || hz_stat_path("VGA/UIV.PAK", &st) < 0) {
            static const char *l[10];
            l[0] = "X-COM: the game's data is missing";
            l[1] = "";
            l[2] = "This program needs the packs made by";
            l[3] = "XCOMCONV from your own copy of";
            l[4] = "X-COM: UFO Defense, in its folder:";
            l[5] = g_plat_dir[0] ? g_plat_dir : "(the program's folder)";
            l[6] = "PACKS.VER, the .PAK files, VGA/.";
            l[7] = "See README.TXT there.";
            l[8] = "";
            l[9] = "Press a key.";
            message_screen(l, 10);
            exit(1);
        }
    }
    g_plat_dir[0] = 0;                  /* names relative to the program's folder */
    if (plat_arena()) {
        static const char *l[4] = { "X-COM: not enough memory", "",
                                    "It needs 17 free banks (1.1 MB) for", "the DOS machine's memory." };
        message_screen(l, 4);
        return 1;
    }
    loading_screen();
    argv[i - 1] = "XCOMXT";
    {
        /* the VGA mode unless the options name another: the engine would pick EGA (the
           model has no XMS, its test for a VGA's memory), and the app starts with no
           options at all */
        int k, mode = 0;
        for (k = i; k < argc; k++)
            if (!stricmp(argv[k], "VGA") || !stricmp(argv[k], "EGA")
                || !stricmp(argv[k], "CGA") || !stricmp(argv[k], "HERC"))
                mode = 1;
        if (!mode && argc < 39) {
            argv[argc++] = "VGA";
            argv[argc] = NULL;
        }
    }
    xd_init(argc - i + 1, argv + i - 1);
    hz_snd_start();                     /* MUSD.PRG, before the engine opens files */
    printf("xcom: start (%u banks)\n", my_banks());
    return xcom_main(argc - i + 1, argv + i - 1);
}
