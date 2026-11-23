/* SPDX-License-Identifier: GPL-3.0-or-later */
/* MUSD.PRG: XCOM-XT's music on the Atari816, a task of its own.

   Horizon runs no program code in interrupts, and the engine computes for
   seconds without a look at the clock (an alien turn, a battle's redraw,
   file loads). So the AdLib driver (upstream's music.c, unchanged but for
   mus_play_mem: patches/src-0002-sound.patch) runs here, in a small task
   that XCOM.PRG spawns at priority 0 (horizon/hz_snd.c) and that owns the
   music timer and the OPL2: Horizon wakes it every 13,731 us (PIT 16384
   counts, 72.8 Hz, upstream's timer hook) and it runs the driver's ticks
   due (the timer's count follows the microsecond clock: a late wake-up
   catches up, at most 8 ticks at once). The game's own copy of music.c
   keeps running for its state and its LOG; its OPL2 writes go nowhere.

   A task cannot read another's memory (Horizon: the bank's owner), and the
   system has 4 file handles in all: so the task reads the whole MUSIC.PAK
   (83 KB, into two banks of its own) once, before it says hello and before
   the engine opens anything; a track to play is then copied from there.

   Started as "MUSD.PRG PORT": PORT the game's port, where it says hello
   {'H', its port, ok}. Its port takes the timer's messages ($FF) and the
   game's:
     {'P', track, loop, u16 bytes}  play the track (bytes: the game's size of it)
     {'S'} stop   {'F', sfx} an FM effect   {'O', on} sound on / off   {'Q'} quit
   It ends with its parent (looked for once a second), as MUSICD.PRG does.
   For XCOM.PRG's /M (horizon/hz_perf.c): {'M', 1} times the timer's wake-ups from then
   on, {'R'} answers {'R', u16 wake-ups, u16 late ones (more than one tick due), u8 most
   ticks due at once, u16 longest gap ms, u16 gaps over 30 ms, u16 over 100 ms} for the
   time since the last 'R', and starts again. */
#include <horizon.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include "musd.h"
#include "input.h"
#include "music.h"
#include "sound.h"
#include "timer.h"

#define PERIOD_US 13731UL       /* 16384 / 1,193,182 s */

int g_sound_on = 1;
static void (*hook)(void);
static unsigned long fake_clock;
static unsigned char opl_reg, opl_stat;
static unsigned char trkbuf[24576];     /* the longest track: 23,088 bytes */
static unsigned char __far *pak[2];     /* MUSIC.PAK: bytes 0-65535, the rest */
static unsigned long pak_len;

/* MUSIC.PAK (next to the program) into pak[]; 0 ok */
static int load_pak(void)
{
    char path[160];
    int fd, k, b;
    unsigned long at = 0;

    if (hz_prog_dir(path, 128) < 0)
        path[0] = 0;
    strcat(path, "MUSIC.PAK");
    fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    for (b = 0; b < 2; b++)
        if (!(pak[b] = (unsigned char __far *)hz_far_alloc()))
            break;
    while (b == 2 && (k = read(fd, trkbuf, 16384)) > 0 && at + (unsigned)k <= 0x20000UL) {
        unsigned o = (unsigned)at, n1 = (unsigned)k;
        if (!(at >> 16) && o + n1 < o) {        /* across the two banks */
            n1 = (unsigned)(0x10000UL - o);
            hz_far_copy(pak[1], trkbuf + n1, (unsigned)k - n1);
        }
        hz_far_copy(pak[(unsigned)(at >> 16)] + o, trkbuf, n1);
        at += (unsigned)k;
    }
    close(fd);
    pak_len = at;
    /* what lies after a track: zeros, then what earlier (longer) tracks left there, as in
       the game's UMB (the driver reads past the end of some tracks: GMTACTIC's
       instrument 10, a tempo of 1 from the bytes after it) */
    memset(trkbuf, 0, sizeof trkbuf);
    return b == 2 && at > 6 ? 0 : -1;
}

/* the track's bytes (off, len in MUSIC.PAK's index) into trkbuf */
static void track_out(unsigned long off, unsigned len)
{
    unsigned o = (unsigned)off, n1 = len;

    if (!(off >> 16) && o + n1 < o) {
        n1 = (unsigned)(0x10000UL - o);
        hz_far_copy(trkbuf + n1, pak[1], len - n1);
    }
    hz_far_copy(trkbuf, pak[(unsigned)(off >> 16)] + o, n1);
}

/* the driver's clock: only its calibration and detection read it (each
   reading 25 ms on: the fewest status reads between writes; hz_opl_write
   waits as the chip needs) */
unsigned long timer_read(void)
{
    return fake_clock += 30000UL;
}

void timer_hook(void (*fn)(void))
{
    hook = fn;
}

void log_printf(const char *fmt, ...)
{
    (void)fmt;
}

unsigned outp(unsigned port, unsigned v)
{
    v &= 0xFF;
    if (port == 0x388)
        opl_reg = (unsigned char)v;
    else if (port == 0x389) {
        if (opl_reg == 4)
            opl_stat = v & 0x80 ? 0 : (v & 1) && !(v & 0x40) ? 0xC0 : opl_stat;
        hz_opl_write(opl_reg, v);
    }
    return v;
}

unsigned inp(unsigned port)
{
    return port == 0x388 ? opl_stat : 0;
}

int intdos(union REGS *in, union REGS *out)
{
    (void)in;
    out->x.ax = 8;
    out->x.bx = 0;
    out->x.cflag = 1;
    return 8;
}

unsigned _dos_freemem(unsigned seg)
{
    (void)seg;
    return 0;
}

/* ---------------------------------------------------------------- the parent */

static unsigned parent;

static void find_parent(void)
{
    hz_taskinfo t;
    unsigned i, me = hz_getpid();

    for (i = 0; i < 16; i++)
        if (!hz_task_info(i, &t) && t.id == me) {
            parent = t.parent;
            return;
        }
}

static int parent_alive(void)
{
    hz_taskinfo t;
    unsigned i;

    if (!parent)
        return 0;
    for (i = 0; i < 16; i++)
        if (!hz_task_info(i, &t) && t.id == parent)
            return t.state != 4;        /* a zombie has ended */
    return 0;
}

/* ---------------------------------------------------------------- the task */

int main(int argc, char **argv)
{
    hz_msg m;
    unsigned rport, gen, last = 0, n, chk = 0;
    int port;
    unsigned char timing = 0;
    unsigned st_wakes = 0, st_late = 0, st_maxn = 0, st_gap = 0, st_g30 = 0, st_g100 = 0;
    long st_t = 0;

    if (argc < 2)
        return 1;
    rport = (unsigned)atoi(argv[1]);
    find_parent();
    port = hz_port_create();
    if (port < 0)
        return 1;
    mus_init(0);                        /* the OPL2 detected and set up; no file */
    gen = hz_sample_timer((unsigned)port, PERIOD_US);
    memset(&m, 0, sizeof m);
    m.b[0] = 'H';
    m.b[1] = (unsigned char)port;
    m.b[2] = hz_errno ? 0 : 1;          /* 0: no music timer (no Lau) */
    if (load_pak())
        m.b[2] = 0;
    if (hz_send(rport, &m) || !m.b[2])
        return 1;
    for (;;) {
        if (hz_recv((unsigned)port, &m))
            break;                      /* (killed) */
        switch (m.b[0]) {
        case 0xFF: {
            unsigned c = m.b[2] | (unsigned)m.b[3] << 8;
            if (m.b[1] != (unsigned char)gen)
                break;
            n = c - last;
            last = c;
            if (timing) {
                long t = hz_uptime_us();
                unsigned g = (unsigned)((t - st_t) / 1000L);
                if (st_t) {
                    if (g > st_gap)
                        st_gap = g;
                    if (g > 30)
                        st_g30++;
                    if (g > 100)
                        st_g100++;
                }
                st_t = t;
                st_wakes++;
                if (n > 1)
                    st_late++;
                if (n > st_maxn)
                    st_maxn = n;
            }
            if (n > 8)
                n = 8;                  /* far behind: no more catching up */
            while (n--)
                if (hook)
                    hook();
            if (++chk >= 73) {
                chk = 0;
                if (!parent_alive())
                    goto quit;
            }
            break;
        }
        case 'P': {                     /* MUSIC.PAK's index: "XMU1", u16 n, n x (u32, u16) */
            unsigned t = m.b[1], len = m.b[3] | (unsigned)m.b[4] << 8, n;
            unsigned char __far *e = pak[0] + 6 + 6 * t;
            unsigned long off;
            n = pak[0][4] | (unsigned)pak[0][5] << 8;
            off = e[0] | (unsigned long)e[1] << 8 | (unsigned long)e[2] << 16;
            if (t >= n || (e[4] | (unsigned)e[5] << 8) != len || len > sizeof trkbuf
                || off + len > pak_len)
                break;                  /* (not the game's track: nothing) */
            track_out(off, len);
            mus_play_mem(trkbuf, len, m.b[2]);
            break;
        }
        case 'S':
            mus_stop();
            break;
        case 'F':
            mus_fx(m.b[1]);
            break;
        case 'O':
            g_sound_on = m.b[1];
            break;
        case 'M':
            timing = m.b[1];
            break;
        case 'R':
            memset(&m, 0, sizeof m);
            m.b[0] = 'R';
            m.b[1] = (unsigned char)st_wakes;
            m.b[2] = (unsigned char)(st_wakes >> 8);
            m.b[3] = (unsigned char)st_late;
            m.b[4] = (unsigned char)(st_late >> 8);
            m.b[5] = (unsigned char)(st_maxn > 255 ? 255 : st_maxn);
            m.b[6] = (unsigned char)st_gap;
            m.b[7] = (unsigned char)(st_gap >> 8);
            m.b[8] = (unsigned char)st_g30;
            m.b[9] = (unsigned char)(st_g30 >> 8);
            m.b[10] = (unsigned char)st_g100;
            m.b[11] = (unsigned char)(st_g100 >> 8);
            hz_send(rport, &m);
            st_wakes = st_late = st_maxn = st_gap = st_g30 = st_g100 = 0;
            break;
        case 'Q':
            goto quit;
        }
    }
quit:
    mus_shutdown();                     /* silence */
    hz_sample_timer(0xFFFFu, 0);
    return 0;
}
