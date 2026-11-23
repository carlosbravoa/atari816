/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The host back end (Linux, headless): the reference build. The engine
   runs as on DOS with the port's C in place of upstream's assembly; input
   comes from upstream's own KEYS scripts; the screen is written as a
   picture (PPM) every time the engine waits for input and the picture
   changed since the last one, and at the end. The clock is virtual
   (plat.h): the same run gives the same pictures and log on any machine.

     xcomhost [-C packdir] [-o shotdir] [-t seconds] XCOMXT-OPTIONS...
       -C   the packs (default data/packs); the engine runs there (its saves too)
       -o   where the pictures go (default build/host/shots)
       -t   end the run after this much idle virtual time (default 30 s) */
#include "xcompat.h"
#include "plat.h"
#include "input.h"
#undef calloc
#undef free

int xcom_main(int argc, char **argv);
void xd_init(int argc, char **argv);

char g_plat_dir[128];
int g_plat_virtual = 1;

static unsigned char *arena;
static unsigned long vclock;            /* PIT counts */
static unsigned long idle_since;
static unsigned idle_limit = 30;
static char shot_dir[256] = "build/host/shots";
static unsigned char last[64000 + 768];
static int nshot, mode = 3, dirty;
static int mx = 160, my = 100;

int plat_arena(void)
{
    arena = calloc(1, XD_ARENA + 16);
    xd_mem = arena;
    return arena ? 0 : -1;
}

/* Each reading of the clock moves it on (a busy loop ends); waits move it
   by their length. 1193 counts are a millisecond. */
#define XD_TICK_STEP 60

unsigned long plat_counts(void)
{
    vclock += XD_TICK_STEP;
    return vclock;
}

void plat_wait_counts(unsigned long n)
{
    vclock += n;
}

static void shot(const char *why)
{
    char name[300];
    const unsigned char *fb = (const unsigned char *)MK_FP(0xA000, 0);
    FILE *f;
    int i;

    if (mode != 0x13)
        return;
    if (!memcmp(last, fb, 64000) && !memcmp(last + 64000, xd_dac, 768))
        return;
    memcpy(last, fb, 64000);
    memcpy(last + 64000, xd_dac, 768);
    sprintf(name, "%s/shot%04d.ppm", shot_dir, nshot);
    f = fopen(name, "wb");
    if (!f)
        return;
    fprintf(f, "P6\n320 200\n255\n");
    for (i = 0; i < 64000; i++) {
        const unsigned char *c = xd_dac + fb[i] * 3;
        fputc(c[0] << 2 | c[0] >> 4, f);
        fputc(c[1] << 2 | c[1] >> 4, f);
        fputc(c[2] << 2 | c[2] >> 4, f);
    }
    fclose(f);
    printf("host: shot%04d at %lu ms (%s)\n", nshot, vclock / 1193UL, why);
    nshot++;
}

static unsigned long last_shot;

/* The engine's waits (a script's WAIT, the pacing) poll: a picture when the
   screen changed, at most one every 500 ms of virtual time. */
void plat_poll(void)
{
    if (vclock - last_shot > 1193UL * 500) {
        int n = nshot;
        shot("poll");
        if (nshot != n)
            last_shot = vclock;
    }
}

/* No keyboard: the KEYS script gives the input. A wait with nothing to give
   for idle_limit virtual seconds ends the run (a last picture first). */
unsigned plat_key(void)
{
    /* the engine asks for a key: a picture if the screen changed (at most
       one every 200 ms of virtual time) */
    if (vclock - last_shot > 1193UL * 200) {
        int n = nshot;
        shot("waiting for input");
        if (nshot != n)
            last_shot = vclock;
    }
    if (g_script || !idle_since)
        idle_since = vclock ? vclock : 1;
    else if (vclock - idle_since > idle_limit * 1193182UL) {
        shot("end");
        printf("host: no more input at %lu ms: end\n", vclock / 1193UL);
        exit(0);
    }
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
    idle_since = 0;
}

void plat_setmode(int m)
{
    mode = m;
    if (m == 0x13)
        memset((void *)MK_FP(0xA000, 0), 0, 64000);
}

void plat_present(int x0, int y0, int x1, int y1)
{
    (void)x0; (void)y0; (void)x1; (void)y1;
    dirty = 1;
}

static FILE *opl_log;

void plat_opl(int reg, int val)
{
    if (opl_log)
        fprintf(opl_log, "%lu %02X %02X\n", vclock / 1193UL, reg, val);
}

void plat_note(const char *s)
{
    fprintf(stderr, "%s\n", s);
}

/* Input resets the idle time (input_key's script reads). */
void plat_input_seen(void)
{
    idle_since = 0;
}

static void at_end(void)
{
    shot("exit");
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
            idle_limit = (unsigned)atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "-opl"))
            opl_log = fopen(argv[i + 1], "w");
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
    argv[i - 1] = "XCOMXT";
    xd_init(argc - i + 1, argv + i - 1);
    atexit(at_end);
    return xcom_main(argc - i + 1, argv + i - 1);
}
