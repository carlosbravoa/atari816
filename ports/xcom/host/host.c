/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The host back end (Linux, headless): the reference build. The engine
   runs as on DOS with the port's C in place of upstream's assembly; input
   comes from upstream's own KEYS scripts; the model's test pictures
   (plat.h "test runs": where the engine polls or waits and the screen
   changed) are written as PPM files, and a line for each on stdout. The
   clock is virtual (plat.h): the same run gives the same pictures and log
   on any machine, and the same as the Atari816's with /V.

     xcomhost [-C packdir] [-o shotdir] [-t seconds] XCOMXT-OPTIONS...
       -C   the packs (default data/packs); the engine runs there (its saves too)
       -o   where the pictures go (default build/host/shots)
       -t   end the run after this much idle virtual time (default 30 s)
       -opl FILE  the OPL2's register writes: "TICK MS REG VAL" (TICK: the music
            driver's ticks so far, plat/timer.c), and the track starts and stops
            ("# play TRACK LOOP BYTES", "# stop", "# fx N")
       -sb FILE   the Sound Blaster's blocks (plat/sb.c): "MS sfx KIND BYTES at LIN
            RATE Hz sum SUM samples N", "MS halt" */
#include "xcompat.h"
#include "plat.h"
#include "input.h"
#include "sb.h"
#undef calloc
#undef free
/* (the host's own files, pictures and logs, are not the engine's: not counted as the
   model's open files, plat/xdos.c) */
#undef fopen
#undef fclose

int xcom_main(int argc, char **argv);
void xd_init(int argc, char **argv);

char g_plat_dir[128];
int g_plat_virtual = 1;

static unsigned char *arena;
static unsigned long vclock;            /* PIT counts */
static char shot_dir[256] = "build/host/shots";
static int mx = 160, my = 100;

void plat_progress(void)
{
}

int plat_arena(void)
{
    arena = calloc(1, XD_ARENA + 16);
    xd_mem = arena;
    return arena ? 0 : -1;
}

/* Each reading of the clock moves it on (a busy loop ends); waits move it
   by their length. 1193 counts are a millisecond. */

unsigned long plat_counts(void)
{
    vclock += XD_TICK_STEP;
    return vclock;
}

void plat_wait_counts(unsigned long n)
{
    vclock += n;
}

void plat_sleep_counts(unsigned long n)
{
    vclock += n;
}

unsigned long plat_now(void)
{
    return vclock;
}

/* A picture of the model's screen (plat.h "test runs"): shotNNNN.ppm. */
void plat_shot(unsigned n, unsigned long ms, unsigned long sum, const char *why)
{
    char name[300];
    const unsigned char *fb = (const unsigned char *)MK_FP(0xA000, 0);
    FILE *f;
    int i;                              /* host16: native (64,000 pixels) */

    sprintf(name, "%s/shot%04u.ppm", shot_dir, n);
    f = fopen(name, "wb");
    if (f) {
        fprintf(f, "P6\n320 200\n255\n");
        for (i = 0; i < 64000; i++) {
            const unsigned char *c = xd_dac + fb[i] * 3;
            fputc(c[0] << 2 | c[0] >> 4, f);
            fputc(c[1] << 2 | c[1] >> 4, f);
            fputc(c[2] << 2 | c[2] >> 4, f);
        }
        fclose(f);
    }
    printf("xcom: shot %u at %lu ms sum %08lx (%s)\n", n, ms, sum, why);
}

void plat_end(void)
{
    printf("xcom: end at %lu ms\n", vclock / 1193UL);
    exit(0);
}

void plat_poll(void)
{
}

/* the engine busy for long (the voxel lines): nothing here */
void plat_busy_poll(void)
{
}

/* a KEYS script's WAIT between two looks at the mouse (the virtual clock: nothing) */
void plat_script_wait(void)
{
}

/* No keyboard: the KEYS script gives the input. */
unsigned plat_key(void)
{
    return 0;
}

void plat_mouse(int *x, int *y, int *buttons)
{
    *x = mx;
    *y = my;
    *buttons = 0;
}

int plat_mouse_press(int b, int *x, int *y)
{
    (void)b;
    *x = mx;
    *y = my;
    return 0;
}

void plat_mouse_set(int x, int y)
{
    mx = x;
    my = y;
}

void plat_setmode(int m)
{
    if (m == 0x13)
        memset((void *)MK_FP(0xA000, 0), 0, 64000);
}

void plat_present(int x0, int y0, int x1, int y1)
{
    (void)x0; (void)y0; (void)x1; (void)y1;
}

/* The battle view: the C of plat/vgabat.c draws it (the reference). */
int plat_bb_sprite(const unsigned char *spr, int kind, unsigned dest, unsigned top,
                   unsigned bottom, unsigned lx, unsigned rx)
{
    (void)spr; (void)kind; (void)dest; (void)top; (void)bottom; (void)lx; (void)rx;
    return 0;
}
int plat_bb_fill(unsigned off, unsigned w, unsigned rows, int colour)
{
    (void)off; (void)w; (void)rows; (void)colour;
    return 0;
}
int plat_bb_present(unsigned off, unsigned w, unsigned rows)
{
    (void)off; (void)w; (void)rows;
    return 0;
}
int plat_bb_shift(long dx)
{
    (void)dx;
    return 0;
}
int plat_bb_box(unsigned off, unsigned w, unsigned rows, int out)
{
    (void)off; (void)w; (void)rows; (void)out;
    return 0;
}
int plat_bb_arrow(const unsigned char *px, int x, int y, int qx, int qy, int qw, int qh)
{
    (void)px; (void)x; (void)y; (void)qx; (void)qy; (void)qw; (void)qh;
    return 0;
}
void plat_bb_sync(void)
{
}
void plat_view(int on)
{
    (void)on;
}
void plat_mem_changed(const void *p, unsigned long n)
{
    (void)p; (void)n;
}

static FILE *opl_log, *sb_log;

void plat_opl(int reg, int val)
{
    if (opl_log)
        fprintf(opl_log, "%lu %lu %02X %02X\n", g_hook_ticks, vclock / 1193UL, reg, val);
}

/* music.c's hooks (patches/src-0002-sound.patch): the Atari816 hands these to its
   music task; here they are marks in the OPL2's log */
void plat_mus_play(int track, int loop, unsigned char *buf, unsigned len)
{
    (void)buf;
    if (opl_log)
        fprintf(opl_log, "# play %d %d %u at tick %lu\n", track, loop, len, g_hook_ticks);
}

void plat_mus_stop(void)
{
    if (opl_log)
        fprintf(opl_log, "# stop at tick %lu\n", g_hook_ticks);
}

void plat_mus_sound(int on)
{
    if (opl_log)
        fprintf(opl_log, "# sound %d at tick %lu\n", on, g_hook_ticks);
}

void plat_mus_fx(int sfx)
{
    if (opl_log)
        fprintf(opl_log, "# fx %d at tick %lu\n", sfx, g_hook_ticks);
}

/* a Sound Blaster block: the line the Atari816 prints for it too (horizon/hz_snd.c) */
void plat_sfx(const unsigned char *src, unsigned bytes, unsigned rate, int kind,
              unsigned long lin, unsigned sum)
{
    static signed char pcm[65536 * 2];
    unsigned n = sb_decode(src, bytes, kind, pcm);

    if (sb_log)
        fprintf(sb_log, "%lu sfx %d %u at %05lX %u Hz sum %04X samples %u\n",
                vclock / 1193UL, kind, bytes, lin, rate, sum, n);
}

/* every effect once when loaded (the Atari816 decodes them then): nothing here */
void plat_sfx_preload(const unsigned char *src, unsigned bytes, unsigned rate, int kind,
                      unsigned long lin)
{
    (void)src; (void)bytes; (void)rate; (void)kind; (void)lin;
}

void plat_sfx_stop(void)
{
    if (sb_log)
        fprintf(sb_log, "%lu halt\n", vclock / 1193UL);
}

void plat_note(const char *s)
{
    fprintf(stderr, "%s\n", s);
}

static void at_end(void)
{
    xd_shot_point(0, "exit");
}

int main(int argc, char **argv)
{
    const char *dir = "data/packs";
    char cwd[256];
    int i = 1;

    while (i + 1 < argc && argv[i][0] == '-') {
        if (!strcmp(argv[i], "-C"))
            dir = argv[i + 1];
        else if (!strcmp(argv[i], "-o"))
            strncpy(shot_dir, argv[i + 1], sizeof shot_dir - 1);
        else if (!strcmp(argv[i], "-t"))
            g_plat_idle = (unsigned)atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "-opl"))
            opl_log = fopen(argv[i + 1], "w");
        else if (!strcmp(argv[i], "-sb"))
            sb_log = fopen(argv[i + 1], "w");
        i += 2;
    }
    if (shot_dir[0] != '/' && getcwd(cwd, sizeof cwd)) {
        char t[256];
        snprintf(t, sizeof t, "%s/%s", cwd, shot_dir);
        strcpy(shot_dir, t);
    }
    if (chdir(dir)) {
        fprintf(stderr, "host: no folder %s (make data)\n", dir);
        return 1;
    }
    if (plat_arena())
        return 1;
    g_plat_shots = 1;
    argv[i - 1] = "XCOMXT";
    xd_init(argc - i + 1, argv + i - 1);
    atexit(at_end);
    return xcom_main(argc - i + 1, argv + i - 1);
}
