/* hg_opl.c - hgame: the OPL2 (REV $0C, Yamaha YM3812: nine FM voices) for games: its
 * registers, and an AdLib register stream played by the frame (id Software's IMF format,
 * the form most DOS games' AdLib music can be converted to: ports/xargon's CMF songs are).
 *
 * The stream: records of 4 bytes {u8 register, u8 value, u16 delay}: the value is written,
 * then the next record waits delay ticks (hz a second: 560 for Commander Keen, 700 for
 * Wolfenstein 3-D). hg_frame (or hg_poll) plays the records that came due since it last
 * did (the vertical blanks counted: 60.03 a second), so the timing is the frame's: within
 * 1/60 s.
 * A pause (the focus lost) silences the voices and the stream waits; it goes on from where
 * it was. */
#include "hg_int.h"

static unsigned char opl = 0xFF;        /* 0xFF: not asked yet */
static unsigned long sp, snext;         /* the stream's address, its next record's */
static unsigned long slen, sleft;       /* (a stream may run on across banks) */
static unsigned shz;
static unsigned char sloop, splay;
static unsigned swait;                  /* ticks before the next record */
static unsigned long sacc;              /* ticks due x 6003 (the frame is 100 / 6003 s) */
static unsigned slastf;
static unsigned char keyreg[9], rhythm; /* the key-on registers as written (B0-B8, BD) */

extern void (*hg__hook_opl)(void);
extern void (*hg__hook_opl_pause)(int on);
static void opl_pause(int on);

int hg_has_opl(void)
{
    if (opl == 0xFF) {
        hz_opl_write(0xFFFE, 0);            /* the probe: the status, takes nothing */
        opl = (unsigned char)(hz_errno == 0);
        if (opl)
            hg__hook_opl_pause = opl_pause;     /* (hg_close gives the chip up) */
    }
    return opl;
}

int hg_opl_write(unsigned reg, unsigned val)
{
    if (reg > 0xF5) {
        hg__fail("hg_opl_write", "registers $00-$F5");
        return -1;
    }
    if (!hg_has_opl())
        return -1;
    if (reg >= 0xB0 && reg <= 0xB8)
        keyreg[reg - 0xB0] = (unsigned char)val;
    else if (reg == 0xBD)
        rhythm = (unsigned char)val;
    hz_opl_write(reg, val & 0xFF);
    return hz_errno ? -1 : 0;
}

/* every voice's key off (the pitches and instruments stay) */
static void keys_off(void)
{
    unsigned i;
    for (i = 0; i < 9; i++)
        if (keyreg[i] & 0x20)
            hz_opl_write(0xB0 + i, keyreg[i] & 0xDF);
    if (rhythm & 0x1F)
        hz_opl_write(0xBD, rhythm & 0xE0);
}

int hg_opl_reset(void)
{
    unsigned i;
    if (!hg_has_opl())
        return -1;
    hz_opl_write(0xFFFF, 0);
    for (i = 0; i < 9; i++)
        keyreg[i] = 0;
    rhythm = 0;
    return hz_errno ? -1 : 0;
}

/* the records due now */
static void opl_tick(void)
{
    unsigned f = hz_frame(), n, ticks;  /* (the vertical blanks: hg_frame or hg_poll) */
    unsigned char r, v;

    if (!splay)
        return;
    n = f - slastf;
    slastf = f;
    if (n > 30)                         /* (a stall of half a second: no burst) */
        n = 30;
    sacc += (unsigned long)n * shz * 100UL;
    ticks = (unsigned)(sacc / 6003UL);
    sacc -= (unsigned long)ticks * 6003UL;
    while (splay) {
        if (swait > ticks) {
            swait -= ticks;
            return;
        }
        ticks -= swait;
        swait = 0;
        /* the records that follow without a delay, and the first one with one */
        do {
            if (sleft < 4) {
                if (!sloop) {
                    splay = 0;
                    keys_off();
                    return;
                }
                snext = sp;
                sleft = slen;
            }
            {
                const unsigned char __far *q = HG__PTR(snext);
                r = q[0];
                v = q[1];
                swait = q[2] | (unsigned)q[3] << 8;
            }
            snext += 4;
            sleft -= 4;
            if (r <= 0xF5 && (r | v)) {     /* (IMF pads with writes of 0 to register 0) */
                if (r >= 0xB0 && r <= 0xB8)
                    keyreg[r - 0xB0] = v;
                else if (r == 0xBD)
                    rhythm = v;
                hz_opl_write(r, v);
            }
        } while (swait == 0);
    }
}

static void opl_pause(int on)
{
    if (on == 2) {                      /* hg_close: the stream ends, the chip is given up */
        splay = 0;
        hz_opl_write(0xFFFD, 0);
        opl = 0xFF;
        return;
    }
    if (on && splay)
        keys_off();
    slastf = hz_frame();                /* (the pause is not time the stream plays) */
}

int hg_opl_play(const void __far *imf, unsigned long len, unsigned hz, int loop)
{
    if (!imf || len < 4 || hz == 0) {
        hg__fail("hg_opl_play", "no stream, or no rate");
        return -1;
    }
    if (!hg_has_opl())
        return -1;
    splay = 0;
    if (hg_opl_reset())
        return -1;
    hz_opl_write(0x01, 0x20);           /* (the waveform select on: most music needs it) */
    sp = snext = (unsigned long)imf;
    slen = sleft = len & ~3UL;
    shz = hz;
    sloop = (unsigned char)(loop != 0);
    swait = 0;
    sacc = 0;
    slastf = hz_frame();
    hg__hook_opl = opl_tick;
    hg__hook_opl_pause = opl_pause;
    splay = 1;
    opl_tick();                         /* (the first records now) */
    return 0;
}

void hg_opl_stop(void)
{
    if (!splay)
        return;
    splay = 0;
    keys_off();
}

int hg_opl_playing(void)
{
    return splay;
}
