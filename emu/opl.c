/* OPL2 (YM3812, REV $0C) — the part of core/src/a816/a816_opl.sv that software can see:
 *
 *   $DB30  W  register select          R  status {IRQ, T1, T2, 0 0 1 1 0} ($06 idle)
 *   $DB31  W  data for the selected register
 *   $DB32  R  output sample, low byte  $DB33  R  high byte (here always 0: no FM synthesis)
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
 */
#include "machine.h"
#include <string.h>

#define O M.opl

static const uint64_t step_cycles[2] = { 1152, 4608 };     /* timer A, timer B */

void opl_reset(void)
{
    uint64_t n = O.n_writes;
    memset(&O, 0, sizeof O);
    O.flagen[0] = O.flagen[1] = 1;
    O.t0 = M.cpu.cycles;
    O.n_writes = n;
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
    return 0;                                          /* $DB31; $DB32/$DB33: no synthesis */
}

void opl_write(uint32_t a, uint8_t v)
{
    opl_update(M.cpu.cycles);
    if ((a & 0xFF) == 0x30) { O.sel = v; return; }
    if ((a & 0xFF) != 0x31) return;
    if (M.sys.snd_log & 16)                            /* --log-opl-us: with the emulated time */
        fprintf(stderr, "opl %llu $%02X = $%02X\n", (unsigned long long)(M.cpu.cycles * 1e6 / CPU_HZ), O.sel, v);
    else if (M.sys.snd_log & 8) fprintf(stderr, "opl $%02X = $%02X\n", O.sel, v);
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
