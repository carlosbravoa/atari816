/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The sound on the Atari816 (PORTING-NOTES.md "Sound").

   Music: MUSD.PRG (mus/musd.c), next to XCOM.PRG, spawned at the start at
   priority 0: it owns Horizon's music timer and the OPL2 and runs upstream's
   AdLib driver on them, so the music keeps its time while the engine draws
   or thinks. It reads MUSIC.PAK once when it starts (before the engine
   opens anything: the system has 4 file handles; a task cannot read
   another's memory); music.c's hooks (patches/src-0002-sound.patch) tell it
   each track to play, the stops, the FM effects; plat/timer.c the sound on/off. The
   engine's own driver runs as on the host; its OPL2 writes (plat_opl) go
   nowhere while the task plays (without it, e.g. no Lau: to the OPL2, at
   the engine's clock readings as before).

   Effects: plat/sb.c's Sound Blaster blocks (SOUNDS.PAK's 4-bit ADPCM at
   6,000 / 8,000 Hz, in the sound's UMB) decoded once to signed 8-bit in far
   banks of their own (a cache by address and checksum) and played on Lau,
   one at a time as the card did. With /V each one prints the host's -sb line
   ("xcom: sfx ...") for tests/sound.sh. */
#include "xcompat.h"
#include <hgame.h>
#include <horizon.h>
#include "plat.h"
#include "sb.h"

#define SFX_VOL 255                     /* Lau volume: the full one, as Prince's and Xargon's effects (160 before: 4 dB softer; tests/sound.sh: RMS, no clipping) */

static int rport = -1, mport = -1;

static int put(unsigned char *b)
{
    hz_msg m;
    long t0 = hz_uptime();

    if (mport < 0)
        return -1;
    memcpy(m.b, b, 16);
    while (hz_send((unsigned)mport, &m)) {
        if (hz_errno != HZ_EAGAIN || hz_uptime() - t0 > 200)
            return -1;
        hz_yield();
    }
    return 0;
}

static int get(unsigned char what, unsigned ms, hz_msg *m)
{
    long t0 = hz_uptime();

    for (;;) {
        if (!hz_recv((unsigned)rport | RV_POLL, m)) {
            if (m->b[0] == what)
                return 0;
            continue;
        }
        if (hz_uptime() - t0 > (long)ms)
            return -1;
        hz_yield();
    }
}

static void quit(void)
{
    unsigned char b[16] = { 'Q' };

    put(b);
}

void hz_snd_start(void)
{
    static char path[160];
    char arg[8];
    hz_msg m;
    int t;

    if (!hg_has_opl() || (rport = hz_port_create()) < 0)
        return;
    if (hz_prog_dir(path, 128) < 0)
        path[0] = 0;
    strcat(path, "MUSD.PRG");
    sprintf(arg, "%d", rport);
    t = hz_spawn_path(path, arg, 0);
    if (t < 0) {
        printf("xcom: no music task (%s)\n", path);
        return;
    }
    if (get('H', 3000, &m) || !m.b[2]) {
        printf("xcom: the music task did not start\n");
        hz_kill((unsigned)t);
        return;
    }
    mport = m.b[1];
    atexit(quit);
}

void hz_snd_opl(int reg, int val)
{
    if (mport < 0)
        hg_opl_write((unsigned)reg, (unsigned)val);
}

void plat_mus_play(int track, int loop, unsigned char *buf, unsigned len)
{
    unsigned char b[16] = { 'P' };

    (void)buf;                          /* (the task has its own MUSIC.PAK: a task cannot read
                                           another's memory) */
    b[1] = (unsigned char)track;
    b[2] = (unsigned char)loop;
    b[3] = (unsigned char)len;
    b[4] = (unsigned char)(len >> 8);
    put(b);
}

/* /M: the music task's own timing (mus/musd.c 'M', 'R'): 1 and its reply in r[16] */
int hz_snd_stats(int on, unsigned char *r)
{
    unsigned char b[16] = { 'M' };
    hz_msg m;

    if (mport < 0)
        return 0;
    if (on) {
        b[1] = 1;
        put(b);
        return 0;
    }
    b[0] = 'R';
    if (put(b) || get('R', 300, &m))
        return 0;
    memcpy(r, m.b, 16);
    return 1;
}

void plat_mus_stop(void)
{
    unsigned char b[16] = { 'S' };

    put(b);
}

void plat_mus_fx(int sfx)
{
    unsigned char b[16] = { 'F' };

    b[1] = (unsigned char)sfx;
    put(b);
}

void plat_mus_sound(int on)
{
    unsigned char b[16] = { 'O' };

    b[1] = (unsigned char)(on != 0);
    put(b);
}

/* ---------------------------------------------------------------- effects */

#define NCACHE 32
#define NBANK  3

static struct {
    unsigned long lin;
    unsigned sum, bytes;
    hg_sound *s;
} cache[NCACHE];
static int ncache, voice = -1;
static signed char far *bank[NBANK];
static unsigned used[NBANK];

static void cache_clear(void)
{
    int i;

    if (voice >= 0)
        hg_stop(voice);
    voice = -1;
    for (i = 0; i < ncache; i++)
        hg_sound_free(cache[i].s);
    ncache = 0;
    for (i = 0; i < NBANK; i++)
        used[i] = 0;
}

static hg_sound *sound_of(const unsigned char far *src, unsigned bytes, unsigned rate,
                          int kind, unsigned long lin, unsigned sum)
{
    unsigned long need = kind == 0 ? bytes : 2UL * bytes;
    unsigned n;
    int i, b;

    for (i = 0; i < ncache; i++)
        if (cache[i].lin == lin && cache[i].sum == sum && cache[i].bytes == bytes)
            return cache[i].s;
    if (need > 0xFF00UL || kind == 2)
        return NULL;
    for (b = 0; b < NBANK; b++) {
        if (!bank[b])
            bank[b] = (signed char far *)hz_far_alloc();
        if (bank[b] && 0x10000UL - used[b] >= need)
            break;
    }
    if (b == NBANK || ncache == NCACHE) {
        cache_clear();
        b = 0;
        if (!bank[0])
            return NULL;
    }
    n = sb_decode(src, bytes, kind, bank[b] + used[b]);
    cache[ncache].s = hg_sound_from(bank[b] + used[b], n, rate, 8);
    if (!cache[ncache].s)
        return NULL;
    used[b] += n;
    cache[ncache].lin = lin;
    cache[ncache].sum = sum;
    cache[ncache].bytes = bytes;
    return cache[ncache++].s;
}

void plat_sfx(const unsigned char far *src, unsigned bytes, unsigned rate, int kind,
              unsigned long lin, unsigned sum)
{
    PERF_T0(pt0);
    hg_sound *s = sound_of(src, bytes, rate, kind, lin, sum);

    if (voice >= 0)
        hg_stop(voice);
    voice = s ? hg_play(s, SFX_VOL) : -1;
    PERF_IO(PF_SFX, NULL, voice < 0 ? 1UL : 0UL, pt0);
    if (g_plat_virtual)
        printf("xcom: sfx %lu sfx %d %u at %05lX %u Hz sum %04X samples %lu voice %d\n",
               plat_now() / 1193UL, kind, bytes, lin, rate, sum, s ? s->len : 0UL, voice);
}

/* every effect decoded once, when the engine has loaded them all (the first geoscape):
   starting one is then a cache hit and Lau's start, well under a millisecond */
void plat_sfx_preload(const unsigned char far *src, unsigned bytes, unsigned rate, int kind,
                      unsigned long lin)
{
    PERF_T0(pt0);
    sound_of(src, bytes, rate, kind, lin, sb_sum(src, bytes));
    PERF_IO(PF_SFXDEC, NULL, bytes, pt0);
}

void plat_sfx_stop(void)
{
    if (voice >= 0)
        hg_stop(voice);
    voice = -1;
    if (g_plat_virtual)
        printf("xcom: sfx %lu halt\n", plat_now() / 1193UL);
}
