/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The Atari816 back end (Horizon 0.30, hgame): the DOS model's arena in
   17 banks, mode 13h's A000 IS the full-screen framebuffer (320 x 200,
   stride 320, one bank: the engine draws into it as into a VGA's memory,
   nothing is copied), the 200 rows shown 180 at a time (the view follows
   the pointer: PORTING-NOTES.md "The screen"), keys and mouse from hgame,
   the OPL2 from hg_opl_write, the clock from the microsecond counter (or
   the virtual clock with /V, as the host's, for comparing runs).
   Stage 1: a skeleton that boots the engine to its first screens. */
#include "xcompat.h"
#include <hgame.h>
#include <horizon.h>
#include "plat.h"

int xcom_main(int argc, char **argv);
void xd_init(int argc, char **argv);
extern unsigned char xd_banks[17];

char g_plat_dir[128];
int g_plat_virtual;

static unsigned long clock_counts, last_us;
static unsigned spare_a000;             /* the arena's own bank 10 before mode 13h */
static int screen_on, pan, mx = 160, my = 100, mb;
static int presses[2], press_x[2], press_y[2];
static unsigned char dac_seen[768];
static unsigned long poll_us;

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
    xd_mem = (xd_ptr)xd_mkfp(0, 0);
    return 0;
}

#define XD_TICK_STEP 60

unsigned long plat_counts(void)
{
    unsigned long us, d;

    if (g_plat_virtual) {
        clock_counts += XD_TICK_STEP;
        return clock_counts;
    }
    us = hg_us();
    d = us - last_us;
    last_us = us;
    clock_counts += (d * 611UL) >> 9;   /* 1.1934 PIT counts a microsecond */
    return clock_counts;
}

void plat_wait_counts(unsigned long n)
{
    clock_counts += n;
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

void plat_poll(void)
{
    unsigned k, b;
    unsigned long us = hg_us();
    int i;

    if (us - poll_us < 8000UL)
        return;
    poll_us = us;
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
        /* the pointer in 320 x 200: the 180 rows shown follow it */
        mx = hg_mouse_x;
        my = hg_mouse_y + pan;
        b = hg_mouse_b;
        for (i = 0; i < 2; i++)
            if ((b & (1u << i)) && !(mb & (1 << i))) {
                presses[i]++;
                press_x[i] = mx;
                press_y[i] = my;
            }
        mb = (int)(b & 3);
        k = (unsigned)(hg_mouse_y * 20 / 179);
        if ((int)k != pan) {
            pan = (int)k;
            hg_scroll(0, pan);
        }
        if (memcmp(dac_seen, xd_dac, 768)) {
            static unsigned char rgb[768];
            memcpy(dac_seen, xd_dac, 768);
            for (i = 0; i < 768; i++)
                rgb[i] = (unsigned char)(xd_dac[i] << 2 | xd_dac[i] >> 4);
            hg_palette(0, 256, rgb);
        }
    }
}

unsigned plat_key(void)
{
    unsigned k;

    plat_poll();
    if (!keyn)
        return 0;
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

void plat_setmode(int m)
{
    if (m == 0x13 && !screen_on) {
        if (hg_screen_fb(HG_320X180, "X-COM", 320, 200) < 0) {
            printf("xcom: no full screen\n");
            exit(1);
        }
        hg_palette_black();
        xd_banks[10] = (unsigned char)hg_fb_bank;   /* A000 is the framebuffer */
        screen_on = 1;
    } else if (m != 0x13 && screen_on) {
        hg_close();
        xd_banks[10] = (unsigned char)spare_a000;
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

    if (i < argc && !strcmp(argv[i], "/V")) {
        g_plat_virtual = 1;
        i++;
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
