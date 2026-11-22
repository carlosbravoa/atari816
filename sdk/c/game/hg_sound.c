/* hg_sound.c - hgame: POKEY effects with envelopes (stepped every 20 ms), samples on Lau
 * (from memory, .WAV files, or made here), music by Horizon's music engine. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hg_int.h"

extern void (*hg__hook_pause)(int on);

/* ---------------------------------------------------------------- POKEY */

typedef struct {
    int f, df;                  /* pitch (AUDF) and its step a tick */
    int v, dv;                  /* volume 0-15 and its fall a tick */
    unsigned c;                 /* distortion bits (AUDC's high nibble) */
    unsigned n;                 /* ticks left + 1 */
} voice;

static voice vo[4];
static unsigned char used;      /* the voices written (to silence) */
static unsigned long tlast;
static int music_paused_by_us;

static void tick(void)
{
    unsigned i;
    voice *v = vo;
    for (i = 0; i < 4; i++, v++) {
        if (!v->n)
            continue;
        if (--v->n == 0) {
            hz_sound_write(i * 2 + 1, 0);           /* AUDC = 0: silent */
            continue;
        }
        hz_sound_write(i * 2, (unsigned)v->f & 0xFF);
        hz_sound_write(i * 2 + 1, v->c | (unsigned)v->v);
        v->f += v->df;
        v->v -= v->dv;
        if (v->v < 0)
            v->v = 0;
    }
}

/* every frame: the ticks of 20 ms that passed (at most 3 at once) */
static void frame_tick(void)
{
    unsigned long now = (unsigned long)hz_uptime();
    unsigned n = 0;
    if (!tlast || now - tlast > 200)
        tlast = now - 20;
    while (now - tlast >= 20 && n < 3) {
        tlast += 20;
        ++n;
        tick();
    }
    if (now - tlast >= 20)
        tlast = now;
}

static void close_sound(void);
static void pause_sound(int on);

static void hooks(void)
{
    hg__hook_sound = frame_tick;
    hg__hook_close_sound = close_sound;
    hg__hook_pause = pause_sound;
}

void hg_sfx(unsigned v, unsigned pitch, int dpitch, unsigned vol, unsigned dvol,
            unsigned ticks, unsigned dist)
{
    voice *p;
    if (v > 3) {
        hg__fail("hg_sfx", "POKEY voices are 0-3");
        return;
    }
    hooks();
    p = &vo[v];
    p->f = (int)(pitch & 0xFF);
    p->df = dpitch;
    p->v = (int)(vol > 15 ? 15 : vol);
    p->dv = (int)dvol;
    p->c = dist & 0xF0;
    p->n = ticks + 1;
    used |= (unsigned char)(1 << v);
}

void hg_tone(unsigned v, unsigned pitch, unsigned vol, unsigned ticks)
{
    hg_sfx(v, pitch, 0, vol, 0, ticks, HG_TONE);
}

unsigned hg_pitch(unsigned hz)
{
    if (hz < 125)
        hz = 125;
    return (unsigned)(31960UL / hz) - 1;
}

/* the two 16-bit voices: POKEY's channels joined in pairs (1 + 2, 3 + 4), clocked at
 * 1.79 MHz: f = 1789790 / (2 x (AUDF16 + 7)), any pitch from 14 Hz, exactly */
static unsigned char audctl, notes;

void hg_note(unsigned v, unsigned hz, unsigned vol)
{
    unsigned long d;
    unsigned lo = v ? 4 : 0;            /* AUDF of the low channel (3 or 1) */
    unsigned char bits = v ? 0x28 : 0x50;   /* join 4 + 3, 3 at 1.79 MHz; 2 + 1, 1 */
    if (v > 1) {
        hg__fail("hg_note", "voices 0 (channels 1 + 2) and 1 (3 + 4)");
        return;
    }
    hooks();
    if ((audctl & bits) != bits) {
        audctl |= bits;
        hz_sound_write(8, audctl);
        hz_sound_write(lo + 1, 0);      /* the low channel silent: the pair sounds */
    }
    notes |= (unsigned char)(1 << v);
    if (hz < 14 || vol == 0) {
        hz_sound_write(lo + 3, 0);
        return;
    }
    d = 894895UL / hz;
    d = d > 7 ? d - 7 : 0;
    if (d > 0xFFFF)
        d = 0xFFFF;
    hz_sound_write(lo, (unsigned)d & 0xFF);
    hz_sound_write(lo + 2, (unsigned)(d >> 8));
    hz_sound_write(lo + 3, HG_TONE | (vol > 15 ? 15 : vol));
}

void hg_sound_off(void)
{
    unsigned i;
    for (i = 0; i < 4; i++) {
        vo[i].n = 0;
        if (used & (1 << i))
            hz_sound_write(i * 2 + 1, 0);
    }
    if (notes) {
        hz_sound_write(3, 0);
        hz_sound_write(7, 0);
        notes = 0;
    }
    if (audctl) {
        audctl = 0;
        hz_sound_write(8, 0);
    }
    if (hg_has_lau())
        hz_sample_stop(0xFFFF);
}

/* ---------------------------------------------------------------- Lau */

static signed char lau = -1;

int hg_has_lau(void)
{
    if (lau < 0) {
        hz_sample_stat();
        lau = (signed char)(hz_errno == 0);
    }
    return lau;
}

static hg_sound *newsound(unsigned long addr, unsigned long len, unsigned rate,
                          unsigned bits)
{
    hg_sound *s = (hg_sound *)malloc(sizeof *s);
    if (!s) {
        hg__fail("hg_sound", "no memory");
        return 0;
    }
    s->addr = addr;
    s->len = len;
    s->rate = rate;
    s->bits = (unsigned char)bits;
    s->loop = 0;
    hooks();
    return s;
}

hg_sound *hg_sound_from(const void *data, unsigned long len, unsigned rate, unsigned bits)
{
    if (!data || !len || (bits != 8 && bits != 16) || rate < 1000) {
        hg__fail("hg_sound_from", "data, a length, 8 or 16 bits, a rate of 1000 or more");
        return 0;
    }
    return newsound((unsigned long)data, len, rate, bits);
}

void hg_sound_free(hg_sound *s)
{
    if (s)
        free(s);                        /* (its far memory stays until hg_close) */
}

static int rd(int fh, unsigned long addr, unsigned long n)
{
    hz_io io;
    unsigned long k, a;
    while (n) {
        a = 0x10000UL - (addr & 0xFFFF);
        k = n < a ? n : a;
        if (k > 0x8000UL)
            k = 0x8000UL;
        io.handle = (unsigned char)fh;
        HZ_U24(io.buf, HG__PTR(addr));
        io.len = (unsigned short)k;
        if (hz_read(&io) != (int)k)
            return -1;
        addr += k;
        n -= k;
    }
    return 0;
}

static unsigned long le32(const unsigned char *p)
{
    return p[0] | ((unsigned long)p[1] << 8) | ((unsigned long)p[2] << 16) |
           ((unsigned long)p[3] << 24);
}

/* unsigned 8-bit samples (WAV) -> signed */
static void flip(unsigned long a, unsigned long n)
{
    unsigned char __far *p;
    unsigned k, i;
    unsigned long room;
    while (n) {
        room = 0x10000UL - (a & 0xFFFF);
        k = (unsigned)(n < room ? n : (room > 0xFFFF ? 0xFFFF : room));
        p = HG__PTR(a);
        for (i = 0; i < k; i++)
            p[i] ^= 0x80;
        a += k;
        n -= k;
    }
}

hg_sound *hg_sound_load(const char *path)
{
    unsigned char hd[12], ck[8], fmt[16];
    unsigned long size, a;
    unsigned rate = 16000, bits = 8, n;
    hg_sound *s = 0;
    int fh;
    hz_fileinfo st;
    const char *dot;

    fh = hz_open(path, HZ_O_READ);
    if (fh < 0) {
        hg__fail("hg_sound_load", hz_strerror(hz_errno));
        return 0;
    }
    dot = strrchr(path, '.');
    if (dot && (!strcmp(dot, ".WAV") || !strcmp(dot, ".wav"))) {
        if (rd(fh, (unsigned long)(void *)hd, 12) || memcmp(hd, "RIFF", 4) ||
            memcmp(hd + 8, "WAVE", 4))
            goto bad;
        size = 0;
        for (n = 0; n < 32; n++) {              /* the chunks: fmt, then data */
            if (rd(fh, (unsigned long)(void *)ck, 8))
                goto bad;
            size = le32(ck + 4);
            if (!memcmp(ck, "fmt ", 4)) {
                if (size < 16 || rd(fh, (unsigned long)(void *)fmt, 16))
                    goto bad;
                if (fmt[0] != 1 || fmt[1] != 0) {
                    hg__fail("hg_sound_load", "not PCM");
                    goto out;
                }
                if (fmt[2] != 1) {
                    hg__fail("hg_sound_load", "stereo: mono files only");
                    goto out;
                }
                rate = fmt[4] | (fmt[5] << 8);
                bits = fmt[14];
                if (bits != 8 && bits != 16) {
                    hg__fail("hg_sound_load", "8 or 16 bits only");
                    goto out;
                }
                size = (size + 1) & ~1UL;
                if (size > 16) {
                    unsigned char skip[32];
                    if (size - 16 > sizeof skip ||
                        rd(fh, (unsigned long)(void *)skip, size - 16))
                        goto bad;
                }
            } else if (!memcmp(ck, "data", 4))
                break;
            else {
                hz_seek(fh, (unsigned long)hz_seek(fh, 0) + ((size + 1) & ~1UL));
            }
        }
        if (n == 32)
            goto bad;
    } else {
        if (hz_stat_path(path, &st))
            goto bad;
        size = st.size;
    }
    if (!size)
        goto bad;
    a = hg__farmem(size);
    if (!a) {
        hg__fail("hg_sound_load", "no far memory (banks) left");
        goto out;
    }
    if (rd(fh, a, size))
        goto bad;
    if (bits == 8 && dot && (!strcmp(dot, ".WAV") || !strcmp(dot, ".wav")))
        flip(a, size);
    s = newsound(a, bits == 16 ? size / 2 : size, rate, bits);
    goto out;
bad:
    hg__fail("hg_sound_load", "not a WAV file this reads (PCM, mono, 8/16 bits)");
out:
    hz_close(fh);
    return s;
}

hg_sound *hg_sound_make(unsigned wave, unsigned hz, unsigned ms, unsigned fade)
{
    unsigned long n, i, fstart, a;
    unsigned ph = 0, step, amp, k, room, fn, fk = 0, acc = 0;
    int v;
    signed char __far *p;
    unsigned noise = 0x1234, hold = 0;
    signed char tab[256];

    if (wave > HG_NOISE_WAVE || hz == 0 || hz > 7999 || ms == 0 || ms > 4000 || fade > 100) {
        hg__fail("hg_sound_make", "a wave HG_SQUARE .. HG_NOISE_WAVE, 1-7999 Hz, 1-4000 ms,"
                 " fade 0-100");
        return 0;
    }
    n = 16UL * ms;
    a = hg__farmem(n);
    if (!a) {
        hg__fail("hg_sound_make", "no far memory (banks) left");
        return 0;
    }
    /* one period of the wave in a table (amplitude 100), then the samples from it: a
     * 16-bit phase step a sample, and a fade with a 16-bit step (no long arithmetic in
     * the loop: the 65816 makes it slow) */
    for (k = 0; k < 256; k++) {
        switch (wave) {
        case HG_SQUARE:   v = k < 128 ? 100 : -100; break;
        case HG_SINE:     v = (hg_sin(k) * 100) >> 8; break;
        case HG_TRIANGLE: v = k < 128 ? (int)k * 200 / 128 - 100 : 300 - (int)k * 200 / 128;
                          break;
        default:          v = ((int)k - 128) * 100 / 128; break;
        }
        tab[k] = (signed char)v;
    }
    step = (unsigned)(((unsigned long)hz << 16) / 16000UL);
    fstart = n - n * fade / 100;
    fn = (unsigned)(n - fstart);                /* samples of the fade (< 65536) */
    amp = 256;
    for (i = 0; i < n; ) {
        room = (unsigned)(0x10000UL - ((a + i) & 0xFFFF) > 0xFFFF ? 0xFFFF
                          : 0x10000UL - ((a + i) & 0xFFFF));
        p = (signed char __far *)HG__PTR(a + i);
        for (k = 0; k < room && i < n; k++, i++) {
            if (wave == HG_NOISE_WAVE) {         /* a new value every few samples */
                if ((hold += step) >= 0x4000) {
                    hold -= 0x4000;
                    noise ^= noise << 7;
                    noise ^= noise >> 9;
                    noise ^= noise << 8;
                }
                v = ((int)(noise & 0xFF) - 128) * 100 / 128;
            } else
                v = tab[ph >> 8];
            ph += step;
            if (i >= fstart) {                  /* amp: 256 down to 0 over fn samples */
                acc += 256;
                while (acc >= fn && amp) {
                    acc -= fn;
                    --amp;
                }
                v = (v * (int)amp) >> 8;
                ++fk;
            }
            p[k] = (signed char)v;
        }
    }
    return newsound(a, n, 16000, 8);
}

/* 2^(k/12) for k = 0..11, in 1.15 fixed point */
static const unsigned semi[12] = {
    32768, 34716, 36781, 38968, 41285, 43740, 46341, 49097, 52016, 55109, 58386, 61858
};

int hg_play_ex(const hg_sound *s, unsigned vol, int pan, int semitones)
{
    hz_sample b;
    unsigned long p;
    int oct, k, v;

    if (!s) {
        hg__fail("hg_play", "no sound (NULL)");
        return -1;
    }
    if (!hg_has_lau())
        return -1;
    hooks();
    /* the pitch: rate / 48000 in 2.14, times 2 ^ (semitones / 12) */
    p = ((unsigned long)s->rate << 14) / 48000UL;
    oct = semitones >= 0 ? semitones / 12 : -((11 - semitones) / 12);
    k = semitones - oct * 12;
    p = (p * semi[k]) >> 15;
    if (oct > 0)
        p <<= oct;
    else if (oct < 0)
        p >>= -oct;
    if (p > 0xFFFF)
        p = 0xFFFF;
    if (vol > 255)
        vol = 255;
    if (pan < -128)
        pan = -128;
    if (pan > 127)
        pan = 127;
    HZ_U24(b.addr, HG__PTR(s->addr));
    b.len.off = (unsigned short)s->len;
    b.len.bank = (unsigned char)(s->len >> 16);
    b.loop.off = 0;
    b.loop.bank = 0;
    b.pitch = (unsigned short)p;
    v = pan > 0 ? (int)((long)vol * (128 - pan) / 128) : (int)vol;
    b.voll = (unsigned char)v;
    v = pan < 0 ? (int)((long)vol * (128 + pan) / 128) : (int)vol;
    b.volr = (unsigned char)v;
    b.flags = (unsigned char)((s->bits == 16 ? SPF_16 : 0) | (s->loop ? SPF_LOOP : 0));
    b.voice = SP_ANY;
    b.zero = 0;
    v = hz_sample_play(&b);
    if (v < 0 && hz_errno != HZ_EAGAIN)
        hg__fail("hg_play", hz_errno == HZ_EFAULT ? "the sound is not the game's memory"
                 : "sample_play refused");
    return v;
}

int hg_play(const hg_sound *s, unsigned vol)
{
    return hg_play_ex(s, vol, 0, 0);
}

void hg_stop(int voice)
{
    if (hg_has_lau())
        hz_sample_stop(voice < 0 ? 0xFFFF : (unsigned)voice);
}

/* ---------------------------------------------------------------- music (MUSICD) */

#define MC_PATH 1
#define MC_LOAD 2
#define MCL_PLAY 1
#define MC_PLAY 3
#define MC_PAUSE 4
#define MC_STOP 5
#define MC_VOL 7
#define MC_LOOP 10
#define MC_QUIT 11
#define MS_STATUS 1
#define MS_HELLO 3

static int mport = -1, eport = -1, mstate;

static void msend(unsigned c, unsigned a)
{
    hz_msg m;
    memset(&m, 0, sizeof m);
    m.b[0] = (unsigned char)c;
    m.b[1] = (unsigned char)a;
    if (eport >= 0)
        hz_send((unsigned)eport, &m);
}

static int engine(void)
{
    char args[12];
    hz_msg m;
    unsigned i;
    if (eport >= 0)
        return 0;
    if (mport < 0) {
        mport = hz_port_create();
        if (mport < 0) {
            hg__fail("hg_music_play", "no message port");
            return -1;
        }
    }
    sprintf(args, "-p %d", mport);
    if (hz_spawn_path("/SYSTEM/MUSICD.PRG", args, 0) < 0) {
        hg__fail("hg_music_play", "cannot start /SYSTEM/MUSICD.PRG");
        return -1;
    }
    for (i = 0; i < 300; i++) {                 /* its hello, within 3 s */
        if (!hz_recv((unsigned)mport | RV_POLL, &m)) {
            if (m.b[0] == MS_HELLO) {
                eport = m.b[1];
                hooks();
                return 0;
            }
            continue;
        }
        hz_sleep(10);
    }
    hg__fail("hg_music_play", "the music engine did not answer");
    return -1;
}

int hg_music_play(const char *path, int loop)
{
    hz_msg m;
    unsigned off, k, n;
    unsigned long t0;
    if (!path) {
        hg__fail("hg_music_play", "no path");
        return -1;
    }
    n = strlen(path);
    if (n > 127) {
        hg__fail("hg_music_play", "the path is longer than 127 characters");
        return -1;
    }
    if (engine())
        return -1;
    for (off = 0; off <= n; off += 14) {        /* the path, 14 characters a message */
        memset(&m, 0, sizeof m);
        m.b[0] = MC_PATH;
        m.b[1] = (unsigned char)off;
        for (k = 0; k < 14 && off + k < n; k++)
            m.b[2 + k] = (unsigned char)path[off + k];
        hz_send((unsigned)eport, &m);
    }
    msend(MC_LOOP, loop ? 1 : 0);
    msend(MC_LOAD, MCL_PLAY);
    mstate = HG_MUSIC_LOADING;
    /* wait for the load (at most 5 s): the engine runs at priority 0 and would hold the
     * game up while it loads anyway; a game should start its music before play */
    t0 = hg_ms();
    while (hg_music_state() <= HG_MUSIC_LOADING && hg_ms() - t0 < 5000)
        hz_sleep(20);
    if (mstate == HG_MUSIC_ERROR) {
        hg__fail("hg_music_play", "the engine could not load it (no such file, not a MOD, WAV"
                 " or MIDI file, MIDI without the OPL2)");
        return -1;
    }
    return 0;
}

void hg_music_stop(void)
{
    msend(MC_STOP, 0);
}

void hg_music_pause(int on)
{
    if (on)
        msend(MC_PAUSE, 0);
    else
        msend(MC_PLAY, 0xFF);
}

void hg_music_volume(unsigned v)
{
    msend(MC_VOL, v > 64 ? 64 : v);
}

int hg_music_state(void)
{
    hz_msg m;
    if (mport < 0)
        return HG_MUSIC_NONE;
    while (!hz_recv((unsigned)mport | RV_POLL, &m))
        if (m.b[0] == MS_STATUS)
            mstate = m.b[1];
    return mstate;
}

/* ---------------------------------------------------------------- pause, the end */

static void pause_sound(int on)
{
    if (on) {
        hg_sound_off();
        music_paused_by_us = eport >= 0 && hg_music_state() == HG_MUSIC_PLAYING;
        if (music_paused_by_us)
            hg_music_pause(1);
    } else if (music_paused_by_us) {
        hg_music_pause(0);
        music_paused_by_us = 0;
    }
}

static void close_sound(void)
{
    hg_sound_off();
    if (eport >= 0) {
        msend(MC_QUIT, 0);
        eport = -1;
    }
    if (mport >= 0) {
        hz_port_close((unsigned)mport);
        mport = -1;
    }
}
