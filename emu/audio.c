/* Lau, the sample player (REV $0A) — a model of core/src/a816/a816_snd.sv and register spec
 * "Lau (sample player)". Output sample k falls on CPU cycle floor(k * 11953 / 40) (48 kHz from the 71.72 MHz
 * pixel clock: 11953 / 8 pixel clocks, 5 pixel clocks per CPU cycle). The hardware computes up
 * to four samples ahead into a FIFO; the emulator computes each sample at its own time, so its
 * positions and KEYON run up to 4 samples (83 us) later than the hardware's. AU_LATE stays 0.
 * No interpolation: the output of a voice is its last sample read.
 * The per-voice 8-byte block is modelled: a voice plays the bytes of its block as they were
 * when it read them, like the hardware. Steps only happen while a voice plays (or --wav, or the
 * SDL build's live sound).
 * --wav and the live sound get the HDMI mix of tang_top.sv without its classic part: Lau's L / R
 * plus the OPL2's latest sample at this sample's cycle (opl.c; REV $0C), saturated. */
#include "machine.h"
#include <string.h>

#define A M.au

static uint64_t smp_cycle(uint64_t k) { return k * 11953 / 40; }

void audio_reset(void)
{
    FILE *w = A.wav;
    uint64_t wn = A.wav_n;
    int live = A.live;
    memset(&A, 0, sizeof A);
    A.wav = w;
    A.wav_n = wn;
    A.live = live;
    A.master = 0xC0;
    A.k = M.cpu.cycles * 40 / 11953 + 1;
    A.next = (A.wav || A.live) ? smp_cycle(A.k) : UINT64_MAX;
}

int audio_irq(void) { return M.sys.rev >= 10 && (A.end & A.irq_en) != 0; }

static uint32_t r24(const uint8_t *r) { return r[0] | r[1] << 8 | (uint32_t)r[2] << 16; }

static int16_t sat16(int64_t x) { return x > 32767 ? 32767 : x < -32768 ? -32768 : (int16_t)x; }

static void step(uint64_t at)
{
    int64_t acc_l = 0, acc_r = 0;
    for (int n = 0; n < 8; n++) {
        AVoice *p = &A.v[n];
        const uint8_t *r = &A.pram[n * 16];
        uint8_t bit = 1 << n;
        if (!(A.playing & bit)) continue;
        uint32_t pos = p->pos, frac = p->frac, c;
        int force;
        int16_t s_cur = p->s_cur;
        if (A.keyon & bit) {
            A.keyon &= ~bit;
            pos = 0; frac = 0; s_cur = 0; c = 0; force = 1;
        } else {
            uint32_t sum = frac + (r[9] | r[10] << 8);
            frac = sum & 0x3FFF; c = sum >> 14; force = 0;
        }
        uint8_t ctl = r[13] & 3;
        pos = (pos + c) & 0xFFFFFF;
        uint32_t len = r24(r + 3);
        if (pos >= len) {
            A.end |= bit;
            if (ctl & 1) pos = (pos - len + r24(r + 6)) & 0xFFFFFF;
            else { if (!(A.keyon & bit)) A.playing &= ~bit; continue; }   /* state not written back */
        }
        uint32_t addr = (r24(r) + ((ctl & 2) ? pos << 1 : pos)) & 0xFFFFFF;
        if (force || c) {
            uint32_t tag = (addr >> 3) & 0xFFFFF;
            if (force || p->tag != tag) {                  /* KEYON always reads its block */
                for (int i = 0; i < 8; i++) p->blk[i] = phys_rd(((addr & 0x7FFFF8) + i) & (RAM_SIZE - 1));
                p->tag = tag;
            }
            int16_t s = (ctl & 2) ? (int16_t)(p->blk[addr & 6] | p->blk[(addr & 6) + 1] << 8)
                                  : (int16_t)(p->blk[addr & 7] << 8);
            s_cur = s;
        }
        acc_l += ((int32_t)s_cur * r[11]) >> 9;              /* (arithmetic shifts, as the RTL) */
        acc_r += ((int32_t)s_cur * r[12]) >> 9;
        p->pos = pos; p->frac = frac; p->s_cur = s_cur;
        if (n == A.sel) A.pos_live = pos;
    }
    A.out_l = sat16((acc_l * A.master) >> 8);
    A.out_r = sat16((acc_r * A.master) >> 8);
    A.n_samples++;
    if (A.wav || A.live) {
        int16_t fm = opl_sample(at);                     /* both channels, full scale */
        /* (times 3 in the mix, as tang_top.sv's mix_sat) */
        int16_t l = sat16((int64_t)A.out_l + 3 * fm), r = sat16((int64_t)A.out_r + 3 * fm);
        if (A.wav) {
            uint8_t b[4] = { l & 0xFF, (uint16_t)l >> 8, r & 0xFF, (uint16_t)r >> 8 };
            fwrite(b, 1, 4, A.wav);
            A.wav_n++;
        }
        if (A.live && A.live_w - A.live_r < LIVE_N) {    /* (full: the host is not taking them) */
            A.live_buf[A.live_w % LIVE_N][0] = l;
            A.live_buf[A.live_w % LIVE_N][1] = r;
            A.live_w++;
        }
    }
}

/* the SDL build: up to max samples (L, R) made since the last call */
int audio_live_take(int16_t *buf, int max)
{
    int n = 0;
    for (; n < max && A.live_r != A.live_w; n++, A.live_r++) {
        buf[2 * n] = A.live_buf[A.live_r % LIVE_N][0];
        buf[2 * n + 1] = A.live_buf[A.live_r % LIVE_N][1];
    }
    return n;
}

void audio_live_on(void)
{
    A.live = 1;
    if (A.next == UINT64_MAX) { A.k = M.cpu.cycles * 40 / 11953 + 1; A.next = smp_cycle(A.k); }
}

void audio_update(uint64_t now)
{
    while (A.next <= now) {
        step(A.next);
        A.k++;
        A.next = (A.playing || A.wav || A.live) ? smp_cycle(A.k) : UINT64_MAX;
    }
}

uint64_t audio_next_event(void) { return A.next; }

uint8_t audio_read(uint32_t a)
{
    if (M.sys.rev < 10) return 0;
    if (M.sys.rev >= 12 && (a & 0xFC) == 0x30) return opl_read(a);   /* REV $0C OPL2 */
    switch (a & 0xFF) {
    case 0x22: return A.playing;
    case 0x23: return A.end;
    case 0x24: return A.irq_en;
    case 0x25: return A.master;
    case 0x26: return A.late;
    case 0x27: return A.sel;
    case 0x28: return A.pos_live & 0xFF;                 /* not latched */
    case 0x29: return (A.pos_live >> 8) & 0xFF;
    case 0x2A: return A.pos_live >> 16;
    case 0x2C: return A.out_l & 0xFF;
    case 0x2D: return (uint16_t)A.out_l >> 8;
    case 0x2E: return A.out_r & 0xFF;
    case 0x2F: return (uint16_t)A.out_r >> 8;
    }
    return 0;
}

void audio_write(uint32_t a, uint8_t v)
{
    int i = a & 0xFF;
    if (M.sys.rev < 10) return;
    if (M.sys.snd_log & 4)                               /* --log-lau-us: with the emulated time */
        fprintf(stderr, "lau %llu $%04X = $%02X\n", (unsigned long long)(M.cpu.cycles * 1e6 / CPU_HZ), 0xDB00 + i, v);
    else if (M.sys.snd_log & 2) fprintf(stderr, "lau $%04X = $%02X\n", 0xDB00 + i, v);
    if (i >= 0x80) { A.pram[i - 0x80] = v; return; }
    switch (i) {
    case 0x20:
        A.playing |= v; A.keyon |= v; A.n_keyon++;
        if (A.next == UINT64_MAX && v) { A.k = M.cpu.cycles * 40 / 11953 + 1; A.next = smp_cycle(A.k); }
        machine_reschedule();
        if (v) emu_lau_keyon();                         /* (main.c) a script's sound wait */
        break;
    case 0x21: A.playing &= ~v; A.keyon &= ~v; break;
    case 0x23: A.end &= ~v; break;
    case 0x24: A.irq_en = v; break;
    case 0x25: A.master = v; break;
    case 0x26: A.late = 0; break;
    case 0x27: A.sel = v & 7; break;
    }
}

static void put32(FILE *f, uint32_t x) { uint8_t b[4] = { x, x >> 8, x >> 16, x >> 24 }; fwrite(b, 1, 4, f); }

int audio_wav_open(const char *path)
{
    A.wav = fopen(path, "wb");
    if (!A.wav) return -1;
    fwrite("RIFF\0\0\0\0WAVEfmt ", 1, 16, A.wav);
    put32(A.wav, 16);
    uint8_t fmt[4] = { 1, 0, 2, 0 };                    /* PCM, stereo */
    fwrite(fmt, 1, 4, A.wav);
    put32(A.wav, 48000);
    put32(A.wav, 48000 * 4);
    uint8_t al[4] = { 4, 0, 16, 0 };
    fwrite(al, 1, 4, A.wav);
    fwrite("data\0\0\0\0", 1, 8, A.wav);
    return 0;
}

void audio_wav_close(void)
{
    if (!A.wav) return;
    uint32_t n = (uint32_t)(A.wav_n * 4);
    fseek(A.wav, 4, SEEK_SET); put32(A.wav, 36 + n);
    fseek(A.wav, 40, SEEK_SET); put32(A.wav, n);
    fclose(A.wav);
    A.wav = NULL;
}
