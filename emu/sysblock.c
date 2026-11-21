/* System block — mirrors the system part of a816_sys.sv.
 *
 * Microsecond clock: the RTL adds 16 per 28.6875 MHz clock and ticks at 459, i.e. after
 * N clocks UPTIME = floor(16 N / 459). The CPU runs one cycle per 2 clocks, so tick k
 * falls on CPU cycle ceil(459 k / 32).
 */
#include "machine.h"
#include <string.h>

static inline uint64_t tick_cycle(uint64_t k) { return (459 * k + 31) / 32; }

void sys_reset(void)
{
    SysBlock *s = &M.sys;
    uint64_t con = s->console_cycles;
    uint8_t rev = s->rev;
    int slog = s->snd_log;
    memset(s, 0, sizeof *s);
    s->console_cycles = con;
    s->rev = rev ? rev : SYS_REV_VAL;
    s->snd_log = slog;
    s->kb_route = 1;                                  /* the RTL resets it to 1 (spec: 0) */
    s->next_tick = tick_cycle(1);
}

/* a816_sys.sv: nmi_n = ~(|nmi_status && !nmi_hold); the CPU latches the falling edge */
void sys_nmi_line(void)
{
    SysBlock *s = &M.sys;
    uint8_t line = s->nmi_status && !M.fr.nmi_hold;
    if (line && !s->nmi_line) M.cpu.nmi = 1;
    s->nmi_line = line;
}

void sys_raise_nmi(uint8_t bits)
{
    M.sys.nmi_status |= bits & 3;
    sys_nmi_line();
}

void sys_raise_irq(uint8_t bits) { M.sys.irq_status |= bits; machine_update_irq(); }

uint8_t sys_irq_now(void) { return M.sys.irq_status | (mailbox_pending() ? IRQ_IOP : 0) | (audio_irq() || opl_irq() ? IRQ_AUDIO : 0); }

static void tick(SysBlock *s)
{
    for (int t = 0; t < 2; t++) {
        if (!s->tm_run[t]) continue;
        if (s->tm_count[t] <= 1) {
            s->irq_status |= IRQ_TIMER0 << t;
            s->tm_count[t] = s->tm_reload[t];
            if (!s->tm_rep[t]) s->tm_run[t] = 0;
        } else s->tm_count[t]--;
    }
    if (s->wd_armed) {
        if (s->wd_count == 0) {
            sys_raise_nmi(2);
            s->wd_armed = 0;
        } else s->wd_count--;
    }
}

/* ticks from now until the next tick that does something (timer fire, watchdog expiry) */
uint64_t sys_ticks_to_event(void)
{
    SysBlock *s = &M.sys;
    uint64_t e = UINT64_MAX;
    for (int t = 0; t < 2; t++)
        if (s->tm_run[t]) { uint64_t c = s->tm_count[t] <= 1 ? 1 : s->tm_count[t]; if (c < e) e = c; }
    if (s->wd_armed && (uint64_t)s->wd_count + 1 < e) e = (uint64_t)s->wd_count + 1;
    return e;
}

uint64_t sys_next_event(void)
{
    uint64_t e = sys_ticks_to_event();
    return e == UINT64_MAX ? UINT64_MAX : tick_cycle(M.sys.us + e);
}

void sys_update(uint64_t now)
{
    SysBlock *s = &M.sys;
    if (now < s->next_tick) return;
    uint64_t k = (32 * now) / 459;                    /* last tick due: tick_cycle(k) <= now */
    while (tick_cycle(k + 1) <= now) k++;
    while (k && tick_cycle(k) > now) k--;
    while (s->us < k) {
        uint64_t n = k - s->us, e = sys_ticks_to_event();
        if (e > n) e = n + 1;                         /* no event inside: bulk-advance n */
        uint64_t bulk = e - 1;                        /* ticks that only count down */
        for (int t = 0; t < 2; t++) if (s->tm_run[t]) s->tm_count[t] -= bulk;
        if (s->wd_armed) s->wd_count -= bulk;
        s->us += bulk;
        if (s->us < k) { s->us++; tick(s); }
    }
    s->next_tick = tick_cycle(s->us + 1);
}

uint8_t sys_read(uint32_t a)
{
    SysBlock *s = &M.sys;
    uint32_t up = (uint32_t)s->us;
    switch (a & 0xFF) {
    case 0x00: return 0x81;
    case 0x01: return s->rev;
    case 0x08: return sys_irq_now();
    case 0x09: return s->irq_en;
    case 0x0A: return s->nmi_status;
    case 0x10: case 0x11: case 0x12: return (s->tm_reload[0] >> (8 * (a & 3))) & 0xFF;
    case 0x13: return s->tm_rep[0] << 1 | s->tm_run[0];
    case 0x14: case 0x15: case 0x16: return (s->tm_reload[1] >> (8 * ((a - 0x14) & 3))) & 0xFF;
    case 0x17: return s->tm_rep[1] << 1 | s->tm_run[1];
    case 0x18: s->uptime_lat = up >> 8; return up & 0xFF;
    case 0x19: return s->uptime_lat & 0xFF;
    case 0x1A: return (s->uptime_lat >> 8) & 0xFF;
    case 0x1B: return (s->uptime_lat >> 16) & 0xFF;
    case 0x20: return s->kb_route;
    case 0x21: case 0x22: return 0;                   /* JOY_PORT, JOY_TRIG: nothing pressed */
    case 0xF1: return M.cpu.cycles < s->dbg_busy_until ? 0x80 : 0;   /* DBG_STAT bit 7 = busy */
    }
    return 0;
}

static void set_byte(uint32_t *r, int i, uint8_t v) { *r = (*r & ~(0xFFu << (8 * i))) | (uint32_t)v << (8 * i); }

void sys_write(uint32_t a, uint8_t v)
{
    SysBlock *s = &M.sys;
    int t;
    switch (a & 0xFF) {
    case 0x08: s->irq_status &= ~v; break;
    case 0x09: s->irq_en = v; break;
    case 0x0A: s->nmi_status &= ~v & 3; sys_nmi_line(); break;
    case 0x10: case 0x11: case 0x12: set_byte(&s->tm_reload[0], (a & 0xFF) - 0x10, v); break;
    case 0x14: case 0x15: case 0x16: set_byte(&s->tm_reload[1], (a & 0xFF) - 0x14, v); break;
    case 0x13: case 0x17:
        t = (a & 0xFF) == 0x17;
        s->tm_rep[t] = (v >> 1) & 1;
        if ((v & 1) && !s->tm_run[t]) s->tm_count[t] = s->tm_reload[t];
        s->tm_run[t] = v & 1;
        break;
    case 0x1C:
        if (v == 0x5A) s->wd_armed = 1;
        if (v == 0x5A || (v == 0xA5 && s->wd_armed)) s->wd_count = WDOG_US - 1;
        break;
    case 0x20: s->kb_route = v & 1; break;
    case 0xF0:
        if (M.cpu.cycles < s->dbg_busy_until) { s->dbg_dropped++; break; }   /* dropped, as on hardware */
        putchar(v);
        if (v == 10) fflush(stdout);
        if (s->console_cycles) s->dbg_busy_until = M.cpu.cycles + s->console_cycles;
        break;
    }
    machine_reschedule();
}

/* ── classic supervisor, the part Horizon uses: freeze request and status ── */
uint8_t sv_read(uint32_t a)
{
    switch (a & 0xFF) {
    case 0x00: return (M.sys.sv_ctrl & 0x04) | 0x01;
    case 0x01: return (M.sys.sv_ctrl >> 2) & 1;
    }
    return 0;
}

void sv_write(uint32_t a, uint8_t v)
{
    if ((a & 0xFF) == 0x00) M.sys.sv_ctrl = v & 0x04;
}

/* ── REV $07 sound: no audio is produced; writes are kept and counted (and logged).
 * REV $0C: $DB00-$DB0F go to POKEY 1's native register bank (as POKEY 2's did: only while
 * frozen) and the DACs $DB10-$DB13 are gone: writes there do nothing ── */
void sound_write(uint32_t a, uint8_t v)
{
    SysBlock *s = &M.sys;
    int i = a & 0xFF;
    if (s->rev >= 12 && (i == 0x30 || i == 0x31)) { opl_write(a, v); return; }   /* REV $0C OPL2 */
    if (i >= 0x20) { audio_write(a, v); return; }          /* REV $0A sample player */
    if (s->rev < 7 || i >= 0x14) return;
    if (s->rev >= 12 && i >= 0x10) return;                 /* REV $0C: no DACs */
    if (!(s->sv_ctrl & 0x04)) { s->snd_ignored++; return; }   /* only while FREEZE_REQ */
    s->snd[i] = v;
    s->snd_writes++;
    if (s->snd_log & 1) fprintf(stderr, "sound $%04X = $%02X\n", 0xDB00 + i, v);
}
