/* OPL2 (YM3812, REV $0C) — the part of core/src/a816/a816_opl.sv that software can see:
 *
 *   $DB30  W  register select          R  status {IRQ, T1, T2, 0 0 1 1 0} ($06 idle)
 *   $DB31  W  data for the selected register
 *   $DB32  R  output sample, low byte  $DB33  R  high byte (signed 16-bit, changes at 49.8 kHz)
 *
 * The chip runs on clk_core / 8 (3.5859 MHz). JTOPL's slot counter passes "zero" once every
 * 72 of those clocks, i.e. every 288 CPU cycles from the chip's reset; timer A counts at every
 * 4th zero (288 chip clocks, 1152 CPU cycles, 80.3 us), timer B at every 16th (1152 chip
 * clocks, 4608 CPU cycles, 321 us), both from free-running prescalers that only a reset
 * restarts (jtopl_timers.v). A running timer's counter starts at its value ($02 / $03) on the
 * rising edge of its load bit and steps up; the step after 255 sets its flag and reloads the
 * value as it is then. Register $04 (jtopl_mmr.v): bit 7 clears both flags and changes
 * nothing else; otherwise bit 6 / bit 5 clear the flag of A / B and mask it (a masked flag
 * still sets, it is only hidden from the status and the IRQ), and bits 0 / 1 are load A / B.
 * The IRQ (status bit 7) is an unmasked flag of A or B; it is ORed with Lau's into IRQ_STATUS
 * bit 5 (AUDIO). These registers work whether or not the classic machine is frozen. The chip
 * is reset at power-on and whenever the 65C816 is held in reset (SYS_RESTART).
 *
 * Not modelled: the write and read registers of a816_opl.sv (1 clk_core each) and the flag
 * clear pulse lasting until JTOPL's next operator clock (at most 16 CPU cycles).
 *
 * The sound: Nuked OPL3 (nuked-opl3/, unmodified, LGPL-2.1+) in OPL2 mode makes one sample per
 * 72 chip clocks, sample n (n >= 1) at CPU cycle t0 + 288 n, from the registers as written up to
 * that cycle; before sample 1 the output is 0. The timers above stay this file's own model (the
 * core has none). Around the core, as on the board: register $01 bit 5 (WSE) masks the
 * waveforms of $E0-$F5 (the OPL3 has no such bit: the core is sent 0 while it is clear), and
 * the output is JTOPL's sum (jtopl_acc.v): every operator that reaches the output at full scale,
 * except the carriers of channels 0 to 3, which JTOPL scales by 256 / 181 / 203 / 203 over 256
 * (0, -3, -2, -2 dB, rounding down); summed in 17 bits and saturated to 16. The core runs
 * lazily, up to the cycle someone needs: a data write, a read of $DB32/$DB33, a 48 kHz output
 * sample (audio.c).
 */
#include "machine.h"
#include "nuked-opl3/opl3.h"
#include <string.h>

#define O M.opl

static const uint64_t step_cycles[2] = { 1152, 4608 };     /* timer A, timer B */

#define SMP_CYCLES 288                                     /* 72 chip clocks */
#define HIST 16                                            /* the last samples, for late askers */

static opl3_chip fm;
static uint64_t fm_n;                                      /* samples made since the reset */
static int16_t  fm_hist[HIST];                             /* sample n in fm_hist[n % HIST] */

void opl_reset(void)
{
    uint64_t n = O.n_writes;
    memset(&O, 0, sizeof O);
    O.flagen[0] = O.flagen[1] = 1;
    O.t0 = M.cpu.cycles;
    O.n_writes = n;
    OPL3_Reset(&fm, 49716);
    fm_n = 0;
    memset(fm_hist, 0, sizeof fm_hist);
}

static int16_t sat16(int32_t x) { return x > 32767 ? 32767 : x < -32768 ? -32768 : (int16_t)x; }

/* one sample: the core's step, then JTOPL's sum of the operators that reach the output */
static void fm_step(void)
{
    static const int32_t vol[4] = { 256, 181, 203, 203 };
    int16_t b4[4];
    OPL3_Generate4Ch(&fm, b4);
    int32_t mix = 0;
    for (int c = 0; c < 9; c++) {
        opl3_channel *ch = &fm.channel[c];
        for (int i = 0; i < 4; i++) {
            int32_t o = *ch->out[i];
            if (c < 4 && ch->out[i] == &ch->slotz[1]->out) o = (o * vol[c]) >> 8;   /* the carrier */
            mix += o;
        }
    }
    mix = (int32_t)((uint32_t)mix << 15) >> 15;           /* the 17-bit accumulator wraps */
    fm_n++;
    fm_hist[fm_n % HIST] = sat16(mix);
}

/* the output as it is at CPU cycle `at` (the latest sample made by then) */
int16_t opl_sample(uint64_t at)
{
    if (M.sys.rev < 12 || at < O.t0 + SMP_CYCLES) return 0;
    uint64_t n = (at - O.t0) / SMP_CYCLES;
    while (fm_n < n) fm_step();
    if (fm_n - n >= HIST) return fm_hist[fm_n % HIST];  /* (not reached: askers are at most an instruction late) */
    return fm_hist[n % HIST];
}

/* a data write reaches the core (after the samples due before it) */
static void fm_write(uint8_t r, uint8_t v)
{
    opl_sample(M.cpu.cycles);
    if (r == 0x01 && ((v ^ O.reg[1]) & 0x20)) {           /* WSE changes: the waveforms again */
        for (int i = 0xE0; i <= 0xF5; i++) OPL3_WriteReg(&fm, i, (v & 0x20) ? O.reg[i] & 3 : 0);
        return;
    }
    if (r >= 0xE0 && !(O.reg[1] & 0x20)) v = 0;
    OPL3_WriteReg(&fm, r, v);
}

/* n steps of running timer t */
static void steps(int t, uint64_t n)
{
    uint64_t k = 256 - O.cnt[t];                       /* steps to the next overflow */
    if (n < k) { O.cnt[t] += n; return; }
    n -= k;
    O.flag[t] = 1;
    O.cnt[t] = O.reg[2 + t];                           /* reload with the value as it is now */
    n %= 256 - O.cnt[t];
    O.cnt[t] += n;
}

void opl_update(uint64_t now)
{
    if (now < O.t0) return;
    for (int t = 0; t < 2; t++) {
        uint64_t due = (now - O.t0) / step_cycles[t];
        if (due <= O.done[t]) continue;
        if (O.load[t]) steps(t, due - O.done[t]);       /* a stopped timer keeps its count */
        O.done[t] = due;
    }
}

/* the next overflow that sets a flag (once set, nothing changes until software clears it) */
uint64_t opl_next_event(void)
{
    uint64_t e = UINT64_MAX;
    for (int t = 0; t < 2; t++) {
        if (!O.load[t] || O.flag[t]) continue;
        uint64_t c = O.t0 + step_cycles[t] * (O.done[t] + 256 - O.cnt[t]);
        if (c < e) e = c;
    }
    return e;
}

static uint8_t status(void)
{
    uint8_t a = O.flag[0] && O.flagen[0], b = O.flag[1] && O.flagen[1];
    return (a || b) << 7 | a << 6 | b << 5 | 0x06;
}

int opl_irq(void) { return M.sys.rev >= 12 && (status() & 0x80); }

uint8_t opl_read(uint32_t a)
{
    opl_update(M.cpu.cycles);
    if ((a & 0xFF) == 0x30) return status();
    if ((a & 0xFF) == 0x32) return (uint16_t)opl_sample(M.cpu.cycles) & 0xFF;
    if ((a & 0xFF) == 0x33) return (uint16_t)opl_sample(M.cpu.cycles) >> 8;
    return 0;                                          /* $DB31 */
}

void opl_write(uint32_t a, uint8_t v)
{
    opl_update(M.cpu.cycles);
    if ((a & 0xFF) == 0x30) { O.sel = v; return; }
    if ((a & 0xFF) != 0x31) return;
    if (M.sys.snd_log & 16)                            /* --log-opl-us: with the emulated time */
        fprintf(stderr, "opl %llu $%02X = $%02X\n", (unsigned long long)(M.cpu.cycles * 1e6 / CPU_HZ), O.sel, v);
    else if (M.sys.snd_log & 8) fprintf(stderr, "opl $%02X = $%02X\n", O.sel, v);
    fm_write(O.sel, v);
    O.reg[O.sel] = v;
    O.n_writes++;
    if (O.sel == 0x04) {
        if (v & 0x80) { O.flag[0] = O.flag[1] = 0; }   /* IRQ reset: nothing else */
        else {
            if (v & 0x40) O.flag[0] = 0;
            if (v & 0x20) O.flag[1] = 0;
            O.flagen[0] = !(v & 0x40);
            O.flagen[1] = !(v & 0x20);
            for (int t = 0; t < 2; t++) {
                int ld = (v >> t) & 1;
                if (ld && !O.load[t]) O.cnt[t] = O.reg[2 + t];   /* rising edge: start at the value */
                O.load[t] = ld;
            }
        }
    }
    machine_reschedule();
    machine_update_irq();
}
