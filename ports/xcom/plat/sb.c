/* SPDX-License-Identifier: GPL-3.0-or-later */
/* A Sound Blaster 2.0 at 220h, IRQ 7, DMA 1 (BLASTER "A220 I7 D1 T3", xd_getenv)
   for upstream's sound.c, at port level: the DSP (reset, version, speaker,
   the time constant, 8-bit PCM 14h and 4-bit ADPCM 75h/74h single-cycle
   transfers, halt), the 8237's channel registers and pages, and the IRQ:
   when a block's time is over on the model's clock (the virtual clock in
   tests), the handler the engine set with _dos_setvect is called from the
   next clock reading (plat/timer.c), as the interrupt would have come
   between two of its instructions. The samples are read in place (the DMA
   address in the arena) and handed to the back end (plat_sfx: the host logs
   it, the Atari816 plays it on Lau).

   xd_sound_umb: the sound's upper memory block (the patch's store_init):
   segment C000, 64 KB (the arena's bank 12, outside the DOS memory), so
   SOUNDS.PAK's effects and the tracks stay out of the game's memory. */
#include "xcompat.h"
#include "plat.h"
#include "sb.h"

#define SB_PORT 0x220
#define SB_IRQ  7

static unsigned char rq[4], nrq;        /* bytes for the DSP's read port */
static unsigned char cmd, need, nargs, args[2], tc = 0x83;
static unsigned char dma_ff;            /* the 8237's flip-flop */
static unsigned dma_a[4], dma_n[4];
static unsigned char dma_pg[4];
static unsigned long irq_at;            /* the block's end on the model's clock, 0 none */
static unsigned char irq_now, in_irq;
static unsigned char adpcm_ref, adpcm_step;
unsigned g_sfx_count;

unsigned xd_sound_umb(unsigned *paras)
{
    /* zeros (the Atari816's banks come as they are): the music driver reads past the
       end of some tracks (mus/musd.c), the same bytes on both builds */
    memset(MK_FP(0xC000u, 0), 0, 0xFFF0u);
    *paras = 0x0FFF;
    return 0xC000u;
}

/* ---------------------------------------------------------------- ADPCM */

/* Creative 4-bit ADPCM, as the DSP decodes it (upstream's tools/sound.py, the
   tables of DOSBox and 86Box): out gets signed samples (the unsigned ones - 128) */
static const signed char scale4[64] = {
    0, 1, 2, 3, 4, 5, 6, 7, 0, -1, -2, -3, -4, -5, -6, -7,
    1, 3, 5, 7, 9, 11, 13, 15, -1, -3, -5, -7, -9, -11, -13, -15,
    2, 6, 10, 14, 18, 22, 26, 30, -2, -6, -10, -14, -18, -22, -26, -30,
    4, 12, 20, 28, 36, 44, 52, 60, -4, -12, -20, -28, -36, -44, -52, -60 };
static const signed char adjust4[64] = {
    0, 0, 0, 0, 0, 16, 16, 16, 0, 0, 0, 0, 0, 16, 16, 16,
    -16, 0, 0, 0, 0, 16, 16, 16, -16, 0, 0, 0, 0, 16, 16, 16,
    -16, 0, 0, 0, 0, 16, 16, 16, -16, 0, 0, 0, 0, 16, 16, 16,
    -16, 0, 0, 0, 0, 0, 0, 0, -16, 0, 0, 0, 0, 0, 0, 0 };

static void adpcm_nib(unsigned nib, signed char far **o)
{
    int i = nib + adpcm_step, r;

    if (i > 63)
        i = 63;
    r = adpcm_ref + scale4[i];
    adpcm_ref = (unsigned char)(r < 0 ? 0 : r > 255 ? 255 : r);
    adpcm_step = (unsigned char)(adpcm_step + adjust4[i]);
    *(*o)++ = (signed char)(adpcm_ref - 128);
}

/* the samples of a block (kind as plat_sfx's) into out: their number */
unsigned sb_decode(const unsigned char far *src, unsigned bytes, int kind, signed char far *out)
{
    signed char far *o = out;
    unsigned i = 0;

    if (kind == 0) {
        for (; i < bytes; i++)
            *o++ = (signed char)(src[i] - 128);
        return bytes;
    }
    if (kind == 1) {
        adpcm_ref = src[0];
        adpcm_step = 0;
        *o++ = (signed char)(adpcm_ref - 128);
        i = 1;
    }
    for (; i < bytes; i++) {
        adpcm_nib(src[i] >> 4, &o);
        adpcm_nib(src[i] & 15, &o);
    }
    return (unsigned)(o - out);
}

/* ---------------------------------------------------------------- the DSP */

static void dsp_put(unsigned char v)
{
    if (nrq < sizeof rq)
        rq[nrq++] = v;
}

static void transfer(int kind)
{
    static const unsigned char page_of[4] = { 0x87, 0x83, 0x81, 0x82 };
    unsigned n = (args[0] | (unsigned)args[1] << 8) + 1u, d = 1, rate;
    unsigned long lin, samples;
    const unsigned char far *src;
    unsigned i, sum = 0;

    (void)page_of;
    lin = ((unsigned long)dma_pg[d] << 16) | dma_a[d];
    if (n > dma_n[d] + 1u)
        n = dma_n[d] + 1u;
    rate = (unsigned)(1000000UL / (256u - tc));
    samples = kind == 0 ? n : kind == 1 ? 1UL + 2UL * (n - 1) : 2UL * n;
    src = (const unsigned char far *)MK_FP((unsigned)(lin >> 4), (unsigned)(lin & 15));
    for (i = 0; i < n; i++)
        sum = (unsigned)((sum << 1 | sum >> 15) + src[i]);
    irq_at = plat_now() + samples * 1193182UL / rate;
    if (!irq_at)
        irq_at = 1;
    g_sfx_count++;
    plat_sfx(src, n, rate, kind, lin, sum);
}

static void dsp_cmd(unsigned char v)
{
    if (need) {
        args[nargs++] = v;
        if (--need)
            return;
        switch (cmd) {
        case 0x40: tc = args[0]; break;
        case 0x14: transfer(0); break;
        case 0x75: transfer(1); break;
        case 0x74: transfer(2); break;
        }
        return;
    }
    cmd = v;
    nargs = 0;
    switch (v) {
    case 0x40: need = 1; break;
    case 0x14: case 0x74: case 0x75: case 0x16: case 0x17: case 0x76: case 0x77:
        need = 2;
        break;
    case 0xE1: dsp_put(2); dsp_put(1); break;      /* DSP 2.01 */
    case 0xD0:                                      /* halt */
        if (irq_at) {
            irq_at = 0;
            plat_sfx_stop();
        }
        break;
    case 0xF2: irq_now = 1; break;
    }
}

/* the ports of the card (2x0h-2xFh), the DMA controller (00h-0Fh, pages 80h-8Fh);
   -1: not ours */
int sb_outp(unsigned port, unsigned v)
{
    unsigned c;

    if (port >= SB_PORT && port < SB_PORT + 16) {
        switch (port - SB_PORT) {
        case 6:
            if (!v) {                   /* the reset's end: ready, AAh */
                nrq = 0;
                need = 0;
                irq_at = 0;
                dsp_put(0xAA);
            }
            break;
        case 0xC:
            dsp_cmd((unsigned char)v);
            break;
        }
        return 0;
    }
    if (port < 8) {
        c = port >> 1;
        if (port & 1) {
            dma_n[c] = dma_ff ? (dma_n[c] & 0xFF) | v << 8 : (dma_n[c] & 0xFF00) | v;
        } else {
            dma_a[c] = dma_ff ? (dma_a[c] & 0xFF) | v << 8 : (dma_a[c] & 0xFF00) | v;
        }
        dma_ff ^= 1;
        return 0;
    }
    if (port == 0x0C) {
        dma_ff = 0;
        return 0;
    }
    if (port < 0x10)
        return 0;
    if (port >= 0x80 && port < 0x90) {
        switch (port) {
        case 0x87: dma_pg[0] = (unsigned char)v; break;
        case 0x83: dma_pg[1] = (unsigned char)v; break;
        case 0x81: dma_pg[2] = (unsigned char)v; break;
        case 0x82: dma_pg[3] = (unsigned char)v; break;
        }
        return 0;
    }
    return -1;
}

int sb_inp(unsigned port)
{
    unsigned v;

    if (port < SB_PORT || port >= SB_PORT + 16)
        return -1;
    switch (port - SB_PORT) {
    case 0xA:                           /* read data */
        if (!nrq)
            return 0xFF;
        v = rq[0];
        memmove(rq, rq + 1, --nrq);
        return (int)v;
    case 0xC:                           /* write status: ready */
        return 0x7F;
    case 0xE:                           /* read status (and the IRQ's acknowledge) */
        return nrq ? 0xFF : 0x7F;
    }
    return 0xFF;
}

/* the clock read (plat/timer.c): the block's IRQ when its time is over */
void sb_poll(unsigned long now)
{
    xd_isr f;

    if (in_irq || !(irq_now || (irq_at && (long)(now - irq_at) >= 0)))
        return;
    irq_now = 0;
    irq_at = 0;
    f = _dos_getvect(8 + SB_IRQ);
    if (!f)
        return;
    in_irq = 1;
    f();
    in_irq = 0;
}
