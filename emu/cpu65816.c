/* cpu65816 — cycle-counted 65C816 interpreter (see cpu65816.h). */
#include "cpu65816.h"
#include <stdio.h>
#include <string.h>

#define E8   (c->e)
#define M8   (c->p & P_M)
#define X8   (c->p & P_X)
#define DL   (c->d & 0xFF)
#define PROGADDR ((uint32_t)c->pbr << 16 | c->pc)

/* ── bus primitives: one call = one cycle ─────────────────────────────────── */
static inline uint8_t rd(Cpu65816 *c, uint32_t a, int f)
{
    c->cycles++;
    return c->read(c->ctx, a & 0xFFFFFF, f | c->intseq);
}
static inline void wr(Cpu65816 *c, uint32_t a, uint8_t v)
{
    c->cycles++;
    c->write(c->ctx, a & 0xFFFFFF, v, BUS_DATA | c->intseq);
}
static inline void io(Cpu65816 *c) { c->cycles++; }

static inline uint8_t fetch8(Cpu65816 *c)
{
    uint8_t v = rd(c, PROGADDR, BUS_PROG);
    c->pc++;
    return v;
}
static inline uint16_t fetch16(Cpu65816 *c)
{
    uint16_t v = fetch8(c);
    return v | fetch8(c) << 8;
}
static inline uint32_t fetch24(Cpu65816 *c)
{
    uint32_t v = fetch16(c);
    return v | (uint32_t)fetch8(c) << 16;
}

/* direct page: readDirect (emulation-mode page wrap when DL = 0) and the "new" form */
static inline uint32_t dpaddr(Cpu65816 *c, uint32_t off)
{
    if (E8 && !DL) return (c->d & 0xFF00) | (off & 0xFF);
    return (c->d + off) & 0xFFFF;
}
static inline uint32_t dpaddrn(Cpu65816 *c, uint32_t off) { return (c->d + off) & 0xFFFF; }

/* stack */
static inline void push8(Cpu65816 *c, uint8_t v)
{
    wr(c, c->s, v);
    if (E8) c->s = 0x0100 | ((c->s - 1) & 0xFF); else c->s--;
}
static inline uint8_t pull8(Cpu65816 *c)
{
    if (E8) c->s = 0x0100 | ((c->s + 1) & 0xFF); else c->s++;
    return rd(c, c->s, BUS_DATA);
}
static inline void pushN(Cpu65816 *c, uint8_t v) { wr(c, c->s, v); c->s--; }
static inline uint8_t pullN(Cpu65816 *c) { c->s++; return rd(c, c->s, BUS_DATA); }
static inline void fixS(Cpu65816 *c) { if (E8) c->s = 0x0100 | (c->s & 0xFF); }

/* flags */
static inline void nz8(Cpu65816 *c, uint8_t v)
{
    c->p = (c->p & ~(P_N | P_Z)) | (v & 0x80) | (v ? 0 : P_Z);
}
static inline void nz16(Cpu65816 *c, uint16_t v)
{
    c->p = (c->p & ~(P_N | P_Z)) | ((v >> 8) & 0x80) | (v ? 0 : P_Z);
}
static inline void setf(Cpu65816 *c, uint8_t f, int on) { if (on) c->p |= f; else c->p &= ~f; }

static void fixP(Cpu65816 *c)
{
    if (E8) c->p |= P_M | P_X;
    if (c->p & P_X) { c->x &= 0xFF; c->y &= 0xFF; }
}

/* ── effective addresses (set c->ea, c->eam) ──────────────────────────────── */
static inline void am_abs(Cpu65816 *c)
{
    c->ea = (uint32_t)c->dbr << 16 | fetch16(c);
    c->eam = 0xFFFFFF;
}
/* --log-bankwrap: an indexed access whose index carries it out of the data bank into the
 * next one (abs,X  abs,Y  (dp),Y  (sr,S),Y), in a program's bank: on a 65816 that is almost
 * always a negative index used unsigned (the bank after it differs from run to run) */
int cpu_log_bankwrap;
static unsigned bankwrap_n;
static void bankwrap(Cpu65816 *c, const char *mode, uint16_t base, uint16_t idx)
{
    if (c->dbr < 2 || c->pbr < 2 || bankwrap_n >= 400) return;
    ++bankwrap_n;
    fprintf(stderr, "bankwrap %02X:%04X %s base $%04X index $%04X -> %02X:%04X\n", c->pbr,
            (unsigned)c->pc, mode, base, idx, (c->dbr + 1) & 0xFF, (uint16_t)(base + idx));
}
#define BANKWRAP(mode, base, idx) \
    do { if (cpu_log_bankwrap && (uint32_t)(base) + (idx) > 0xFFFF) bankwrap(c, mode, base, idx); } while (0)

static inline void am_absi(Cpu65816 *c, uint16_t idx, int wr)
{
    uint16_t w = fetch16(c);
    BANKWRAP("abs,i", w, idx);
    c->ea = (((uint32_t)c->dbr << 16 | w) + idx) & 0xFFFFFF;
    c->eam = 0xFFFFFF;
    if (wr || !X8 || ((w & 0xFF) + (idx & 0xFF)) > 0xFF) io(c);
}
static inline void am_long(Cpu65816 *c) { c->ea = fetch24(c); c->eam = 0xFFFFFF; }
static inline void am_longx(Cpu65816 *c) { c->ea = (fetch24(c) + c->x) & 0xFFFFFF; c->eam = 0xFFFFFF; }
static inline void am_dp(Cpu65816 *c)
{
    uint8_t o = fetch8(c);
    if (DL) io(c);
    c->ea = (c->d + o) & 0xFFFF;
    c->eam = 0xFFFF;
}
static inline void am_dpi(Cpu65816 *c, uint16_t idx)
{
    uint8_t o = fetch8(c);
    if (DL) io(c);
    io(c);
    c->ea = dpaddr(c, (uint32_t)o + idx);
    c->eam = 0xFFFF;
}
static inline void am_dpind(Cpu65816 *c)
{
    uint8_t o = fetch8(c);
    if (DL) io(c);
    uint16_t p = rd(c, dpaddr(c, o), BUS_DATA);
    p |= rd(c, dpaddr(c, o + 1u), BUS_DATA) << 8;
    c->ea = (uint32_t)c->dbr << 16 | p;
    c->eam = 0xFFFFFF;
}
static inline void am_dpindx(Cpu65816 *c)
{
    uint8_t o = fetch8(c);
    if (DL) io(c);
    io(c);
    uint16_t p = rd(c, dpaddr(c, (uint32_t)o + c->x), BUS_DATA);
    p |= rd(c, dpaddr(c, (uint32_t)o + c->x + 1), BUS_DATA) << 8;
    c->ea = (uint32_t)c->dbr << 16 | p;
    c->eam = 0xFFFFFF;
}
static inline void am_dpindy(Cpu65816 *c, int wr)
{
    uint8_t o = fetch8(c);
    if (DL) io(c);
    uint16_t p = rd(c, dpaddr(c, o), BUS_DATA);
    p |= rd(c, dpaddr(c, o + 1u), BUS_DATA) << 8;
    if (wr || !X8 || ((p & 0xFF) + (c->y & 0xFF)) > 0xFF) io(c);
    BANKWRAP("(dp),y", p, c->y);
    c->ea = (((uint32_t)c->dbr << 16 | p) + c->y) & 0xFFFFFF;
    c->eam = 0xFFFFFF;
}
static inline void am_dpindl(Cpu65816 *c, uint16_t idx)
{
    uint8_t o = fetch8(c);
    if (DL) io(c);
    uint32_t p = rd(c, dpaddrn(c, o), BUS_DATA);
    p |= rd(c, dpaddrn(c, o + 1u), BUS_DATA) << 8;
    p |= (uint32_t)rd(c, dpaddrn(c, o + 2u), BUS_DATA) << 16;
    c->ea = (p + idx) & 0xFFFFFF;
    c->eam = 0xFFFFFF;
}
static inline void am_sr(Cpu65816 *c)
{
    uint8_t o = fetch8(c);
    io(c);
    c->ea = (c->s + o) & 0xFFFF;
    c->eam = 0xFFFF;
}
static inline void am_sriy(Cpu65816 *c)
{
    uint8_t o = fetch8(c);
    io(c);
    uint16_t p = rd(c, (c->s + o) & 0xFFFF, BUS_DATA);
    p |= rd(c, (c->s + o + 1) & 0xFFFF, BUS_DATA) << 8;
    io(c);
    BANKWRAP("(sr,s),y", p, c->y);
    c->ea = (((uint32_t)c->dbr << 16 | p) + c->y) & 0xFFFFFF;
    c->eam = 0xFFFFFF;
}

static inline uint16_t rdM(Cpu65816 *c, int sz8)
{
    uint16_t v = rd(c, c->ea, BUS_DATA);
    if (!sz8) v |= rd(c, (c->ea + 1) & c->eam, BUS_DATA) << 8;
    return v;
}
static inline void wrM(Cpu65816 *c, uint16_t v, int sz8)
{
    wr(c, c->ea, v & 0xFF);
    if (!sz8) wr(c, (c->ea + 1) & c->eam, v >> 8);
}

/* ── ALU ──────────────────────────────────────────────────────────────────── */
static void adc(Cpu65816 *c, uint16_t data)
{
    int C = c->p & P_C, D = c->p & P_D, r;
    if (M8) {
        int A = c->a & 0xFF;
        if (!D) r = A + data + C;
        else {
            r = (A & 0x0F) + (data & 0x0F) + C;
            if (r > 0x09) r += 0x06;
            C = r > 0x0F;
            r = (A & 0xF0) + (data & 0xF0) + (C << 4) + (r & 0x0F);
        }
        setf(c, P_V, ~(A ^ data) & (A ^ r) & 0x80);
        if (D && r > 0x9F) r += 0x60;
        setf(c, P_C, r > 0xFF);
        c->a = (c->a & 0xFF00) | (r & 0xFF);
        nz8(c, r);
    } else {
        int A = c->a;
        if (!D) r = A + data + C;
        else {
            r = (A & 0x000F) + (data & 0x000F) + C;
            if (r > 0x0009) r += 0x0006;
            C = r > 0x000F;
            r = (A & 0x00F0) + (data & 0x00F0) + (C << 4) + (r & 0x000F);
            if (r > 0x009F) r += 0x0060;
            C = r > 0x00FF;
            r = (A & 0x0F00) + (data & 0x0F00) + (C << 8) + (r & 0x00FF);
            if (r > 0x09FF) r += 0x0600;
            C = r > 0x0FFF;
            r = (A & 0xF000) + (data & 0xF000) + (C << 12) + (r & 0x0FFF);
        }
        setf(c, P_V, ~(A ^ data) & (A ^ r) & 0x8000);
        if (D && r > 0x9FFF) r += 0x6000;
        setf(c, P_C, r > 0xFFFF);
        c->a = r;
        nz16(c, r);
    }
}
static void sbc(Cpu65816 *c, uint16_t data)
{
    int C = c->p & P_C, D = c->p & P_D, r;
    if (M8) {
        int A = c->a & 0xFF;
        data = ~data & 0xFF;
        if (!D) r = A + data + C;
        else {
            r = (A & 0x0F) + (data & 0x0F) + C;
            if (r <= 0x0F) r -= 0x06;
            C = r > 0x0F;
            r = (A & 0xF0) + (data & 0xF0) + (C << 4) + (r & 0x0F);
        }
        setf(c, P_V, ~(A ^ data) & (A ^ r) & 0x80);
        if (D && r <= 0xFF) r -= 0x60;
        setf(c, P_C, r > 0xFF);
        c->a = (c->a & 0xFF00) | (r & 0xFF);
        nz8(c, r);
    } else {
        int A = c->a;
        data = ~data;
        if (!D) r = A + data + C;
        else {
            r = (A & 0x000F) + (data & 0x000F) + C;
            if (r <= 0x000F) r -= 0x0006;
            C = r > 0x000F;
            r = (A & 0x00F0) + (data & 0x00F0) + (C << 4) + (r & 0x000F);
            if (r <= 0x00FF) r -= 0x0060;
            C = r > 0x00FF;
            r = (A & 0x0F00) + (data & 0x0F00) + (C << 8) + (r & 0x00FF);
            if (r <= 0x0FFF) r -= 0x0600;
            C = r > 0x0FFF;
            r = (A & 0xF000) + (data & 0xF000) + (C << 12) + (r & 0x0FFF);
        }
        setf(c, P_V, ~(A ^ data) & (A ^ r) & 0x8000);
        if (D && r <= 0xFFFF) r -= 0x6000;
        setf(c, P_C, r > 0xFFFF);
        c->a = r;
        nz16(c, r);
    }
}
static void cmp(Cpu65816 *c, uint16_t reg, uint16_t data, int sz8)
{
    if (sz8) {
        int r = (reg & 0xFF) - (data & 0xFF);
        setf(c, P_C, r >= 0);
        nz8(c, r);
    } else {
        int r = reg - data;
        setf(c, P_C, r >= 0);
        nz16(c, r);
    }
}
static void bit(Cpu65816 *c, uint16_t data, int imm)
{
    if (M8) {
        if (!imm) c->p = (c->p & 0x3F) | (data & 0xC0);
        setf(c, P_Z, !(data & c->a & 0xFF));
    } else {
        if (!imm) c->p = (c->p & 0x3F) | ((data >> 8) & 0xC0);
        setf(c, P_Z, !(data & c->a));
    }
}

/* the eight accumulator ALU operations, group = op >> 5 */
static void alu(Cpu65816 *c, int grp, uint16_t v)
{
    switch (grp) {
    case 0: if (M8) { c->a |= v & 0xFF; nz8(c, c->a); } else { c->a |= v; nz16(c, c->a); } break;
    case 1: if (M8) { c->a &= v | 0xFF00; nz8(c, c->a); } else { c->a &= v; nz16(c, c->a); } break;
    case 2: if (M8) { c->a ^= v & 0xFF; nz8(c, c->a); } else { c->a ^= v; nz16(c, c->a); } break;
    case 3: adc(c, v); break;
    case 5: if (M8) { c->a = (c->a & 0xFF00) | (v & 0xFF); nz8(c, v); } else { c->a = v; nz16(c, v); } break;
    case 6: cmp(c, c->a, v, M8); break;
    case 7: sbc(c, v); break;
    }
}

/* read-modify-write operations */
static uint16_t rmw(Cpu65816 *c, int op, uint16_t v, int sz8)
{
    uint16_t msb = sz8 ? 0x80 : 0x8000, mask = sz8 ? 0xFF : 0xFFFF;
    switch (op) {
    case 0: setf(c, P_C, v & msb); v = (v << 1) & mask; break;                      /* ASL */
    case 1: { int ci = c->p & P_C; setf(c, P_C, v & msb); v = ((v << 1) | ci) & mask; break; } /* ROL */
    case 2: setf(c, P_C, v & 1); v >>= 1; break;                                     /* LSR */
    case 3: { int ci = c->p & P_C; setf(c, P_C, v & 1); v = (v >> 1) | (ci ? msb : 0); break; } /* ROR */
    case 6: v = (v - 1) & mask; break;                                               /* DEC */
    case 7: v = (v + 1) & mask; break;                                               /* INC */
    }
    if (sz8) nz8(c, v); else nz16(c, v);
    return v;
}

/* ── interrupt entry (hardware: IRQ, NMI, ABORT) ──────────────────────────── */
enum { V_COP = 0x4, V_BRK = 0x6, V_ABORT = 0x8, V_NMI = 0xA, V_IRQ = 0xE, V_RESET = 0xC };

static void vector_pull(Cpu65816 *c, int v)
{
    uint32_t va = 0xFFE0 | (c->e ? 0x10 : 0) | v;
    if (c->e && v == V_BRK) va = 0xFFFE;
    uint16_t pc = rd(c, va, BUS_VECTOR);
    pc |= rd(c, va + 1, BUS_VECTOR) << 8;
    c->pc = pc;
}

static void interrupt(Cpu65816 *c, int v)
{
    c->intseq = BUS_INTSEQ;
    rd(c, PROGADDR, BUS_SYNC);        /* discarded opcode fetch */
    io(c);                            /* second discarded cycle */
    if (!c->e) push8(c, c->pbr);
    push8(c, c->pc >> 8);
    push8(c, c->pc & 0xFF);
    uint8_t p = c->p;
    if (c->e) p &= ~P_X;              /* emulation mode: B = 0 for IRQ/NMI/ABORT */
    push8(c, p);
    c->p = (c->p | P_I) & ~P_D;
    c->pbr = 0;
    vector_pull(c, v);
    c->intseq = 0;
    c->abort = 0;                     /* refusals in the sequence never raise ABORT */
    c->just_int = 1;
}

void cpu_init(Cpu65816 *c, void *ctx, cpu_read_fn rdf, cpu_write_fn wrf)
{
    memset(c, 0, sizeof *c);
    c->ctx = ctx;
    c->read = rdf;
    c->write = wrf;
}

void cpu_reset(Cpu65816 *c)
{
    c->e = 1;
    c->p = P_M | P_X | P_I;
    c->d = 0; c->dbr = 0; c->pbr = 0;
    c->x &= 0xFF; c->y &= 0xFF;
    c->s = 0x01FD;                    /* $0100 at reset, three dummy pulls */
    c->stopped = c->waiting = c->abort = 0;
    c->nmi = 0;
    c->intseq = BUS_INTSEQ;
    c->cycles += 5;                   /* reset sequence: 2 fetches + 3 stack cycles */
    vector_pull(c, V_RESET);
    c->intseq = 0;
    c->just_int = 1;
    c->poll_i = 1;
}

/* ── one instruction ──────────────────────────────────────────────────────── */
static void branch(Cpu65816 *c, int take)
{
    int8_t off = fetch8(c);
    if (!take) return;
    uint16_t t = c->pc + off;
    io(c);
    if (c->e && ((t ^ c->pc) & 0xFF00)) io(c);
    c->pc = t;
}

static void exec_op(Cpu65816 *c, uint8_t op)
{
    uint16_t v;
    switch (op) {
    /* ── accumulator ALU group: ORA AND EOR ADC STA LDA CMP SBC ── */
    case 0x01: case 0x21: case 0x41: case 0x61: case 0x81: case 0xA1: case 0xC1: case 0xE1:
        am_dpindx(c); goto alu_mem;
    case 0x03: case 0x23: case 0x43: case 0x63: case 0x83: case 0xA3: case 0xC3: case 0xE3:
        am_sr(c); goto alu_mem;
    case 0x05: case 0x25: case 0x45: case 0x65: case 0x85: case 0xA5: case 0xC5: case 0xE5:
        am_dp(c); goto alu_mem;
    case 0x07: case 0x27: case 0x47: case 0x67: case 0x87: case 0xA7: case 0xC7: case 0xE7:
        am_dpindl(c, 0); goto alu_mem;
    case 0x0D: case 0x2D: case 0x4D: case 0x6D: case 0x8D: case 0xAD: case 0xCD: case 0xED:
        am_abs(c); goto alu_mem;
    case 0x0F: case 0x2F: case 0x4F: case 0x6F: case 0x8F: case 0xAF: case 0xCF: case 0xEF:
        am_long(c); goto alu_mem;
    case 0x11: case 0x31: case 0x51: case 0x71: case 0x91: case 0xB1: case 0xD1: case 0xF1:
        am_dpindy(c, op == 0x91); goto alu_mem;
    case 0x12: case 0x32: case 0x52: case 0x72: case 0x92: case 0xB2: case 0xD2: case 0xF2:
        am_dpind(c); goto alu_mem;
    case 0x13: case 0x33: case 0x53: case 0x73: case 0x93: case 0xB3: case 0xD3: case 0xF3:
        am_sriy(c); goto alu_mem;
    case 0x15: case 0x35: case 0x55: case 0x75: case 0x95: case 0xB5: case 0xD5: case 0xF5:
        am_dpi(c, c->x); goto alu_mem;
    case 0x17: case 0x37: case 0x57: case 0x77: case 0x97: case 0xB7: case 0xD7: case 0xF7:
        am_dpindl(c, c->y); goto alu_mem;
    case 0x19: case 0x39: case 0x59: case 0x79: case 0x99: case 0xB9: case 0xD9: case 0xF9:
        am_absi(c, c->y, op == 0x99); goto alu_mem;
    case 0x1D: case 0x3D: case 0x5D: case 0x7D: case 0x9D: case 0xBD: case 0xDD: case 0xFD:
        am_absi(c, c->x, op == 0x9D); goto alu_mem;
    case 0x1F: case 0x3F: case 0x5F: case 0x7F: case 0x9F: case 0xBF: case 0xDF: case 0xFF:
        am_longx(c); goto alu_mem;
    alu_mem:
        if ((op >> 5) == 4) wrM(c, c->a, M8);
        else alu(c, op >> 5, rdM(c, M8));
        break;
    case 0x09: case 0x29: case 0x49: case 0x69: case 0xA9: case 0xC9: case 0xE9:
        v = M8 ? fetch8(c) : fetch16(c);
        alu(c, op >> 5, v);
        break;

    /* ── read-modify-write: ASL ROL LSR ROR DEC INC ── */
    case 0x06: case 0x26: case 0x46: case 0x66: case 0xC6: case 0xE6:
        am_dp(c); goto rmw_mem;
    case 0x0E: case 0x2E: case 0x4E: case 0x6E: case 0xCE: case 0xEE:
        am_abs(c); goto rmw_mem;
    case 0x16: case 0x36: case 0x56: case 0x76: case 0xD6: case 0xF6:
        am_dpi(c, c->x); goto rmw_mem;
    case 0x1E: case 0x3E: case 0x5E: case 0x7E: case 0xDE: case 0xFE:
        am_absi(c, c->x, 1); goto rmw_mem;
    rmw_mem:
        v = rdM(c, M8);
        io(c);
        v = rmw(c, op >> 5, v, M8);
        if (!M8) wr(c, (c->ea + 1) & c->eam, v >> 8);
        wr(c, c->ea, v & 0xFF);
        break;
    case 0x04: case 0x0C: case 0x14: case 0x1C:     /* TSB / TRB */
        if (op & 0x08) am_abs(c); else am_dp(c);
        v = rdM(c, M8);
        io(c);
        setf(c, P_Z, !(v & (M8 ? (c->a & 0xFF) : c->a)));
        if (op & 0x10) v &= ~c->a; else v |= c->a;
        if (!M8) wr(c, (c->ea + 1) & c->eam, v >> 8);
        wr(c, c->ea, v & 0xFF);
        break;
    case 0x0A: case 0x2A: case 0x4A: case 0x6A:     /* accumulator shifts */
        io(c);
        if (M8) c->a = (c->a & 0xFF00) | rmw(c, op >> 5, c->a & 0xFF, 1);
        else c->a = rmw(c, op >> 5, c->a, 0);
        break;
    case 0x1A: case 0x3A:                           /* INC A / DEC A */
        io(c);
        if (M8) c->a = (c->a & 0xFF00) | rmw(c, op == 0x1A ? 7 : 6, c->a & 0xFF, 1);
        else c->a = rmw(c, op == 0x1A ? 7 : 6, c->a, 0);
        break;

    /* ── BIT ── */
    case 0x89: v = M8 ? fetch8(c) : fetch16(c); bit(c, v, 1); break;
    case 0x24: am_dp(c); bit(c, rdM(c, M8), 0); break;
    case 0x2C: am_abs(c); bit(c, rdM(c, M8), 0); break;
    case 0x34: am_dpi(c, c->x); bit(c, rdM(c, M8), 0); break;
    case 0x3C: am_absi(c, c->x, 0); bit(c, rdM(c, M8), 0); break;

    /* ── X / Y loads, stores, compares ── */
    case 0xA2: v = X8 ? fetch8(c) : fetch16(c); goto ldx;
    case 0xA6: am_dp(c); goto ldxm;
    case 0xAE: am_abs(c); goto ldxm;
    case 0xB6: am_dpi(c, c->y); goto ldxm;
    case 0xBE: am_absi(c, c->y, 0); goto ldxm;
    ldxm: v = rdM(c, X8);
    ldx: c->x = v; if (X8) nz8(c, v); else nz16(c, v); break;
    case 0xA0: v = X8 ? fetch8(c) : fetch16(c); goto ldy;
    case 0xA4: am_dp(c); goto ldym;
    case 0xAC: am_abs(c); goto ldym;
    case 0xB4: am_dpi(c, c->x); goto ldym;
    case 0xBC: am_absi(c, c->x, 0); goto ldym;
    ldym: v = rdM(c, X8);
    ldy: c->y = v; if (X8) nz8(c, v); else nz16(c, v); break;
    case 0x86: am_dp(c); wrM(c, c->x, X8); break;
    case 0x8E: am_abs(c); wrM(c, c->x, X8); break;
    case 0x96: am_dpi(c, c->y); wrM(c, c->x, X8); break;
    case 0x84: am_dp(c); wrM(c, c->y, X8); break;
    case 0x8C: am_abs(c); wrM(c, c->y, X8); break;
    case 0x94: am_dpi(c, c->x); wrM(c, c->y, X8); break;
    case 0x64: am_dp(c); wrM(c, 0, M8); break;
    case 0x74: am_dpi(c, c->x); wrM(c, 0, M8); break;
    case 0x9C: am_abs(c); wrM(c, 0, M8); break;
    case 0x9E: am_absi(c, c->x, 1); wrM(c, 0, M8); break;
    case 0xE0: v = X8 ? fetch8(c) : fetch16(c); cmp(c, c->x, v, X8); break;
    case 0xE4: am_dp(c); cmp(c, c->x, rdM(c, X8), X8); break;
    case 0xEC: am_abs(c); cmp(c, c->x, rdM(c, X8), X8); break;
    case 0xC0: v = X8 ? fetch8(c) : fetch16(c); cmp(c, c->y, v, X8); break;
    case 0xC4: am_dp(c); cmp(c, c->y, rdM(c, X8), X8); break;
    case 0xCC: am_abs(c); cmp(c, c->y, rdM(c, X8), X8); break;

    /* ── register increments and transfers ── */
    case 0xE8: io(c); c->x = X8 ? (uint8_t)(c->x + 1) : (uint16_t)(c->x + 1); goto nzx;
    case 0xCA: io(c); c->x = X8 ? (uint8_t)(c->x - 1) : (uint16_t)(c->x - 1); goto nzx;
    case 0xC8: io(c); c->y = X8 ? (uint8_t)(c->y + 1) : (uint16_t)(c->y + 1); goto nzy;
    case 0x88: io(c); c->y = X8 ? (uint8_t)(c->y - 1) : (uint16_t)(c->y - 1); goto nzy;
    case 0xAA: io(c); c->x = X8 ? (c->a & 0xFF) : c->a; goto nzx;
    case 0xA8: io(c); c->y = X8 ? (c->a & 0xFF) : c->a; goto nzy;
    case 0xBA: io(c); c->x = X8 ? (c->s & 0xFF) : c->s; goto nzx;
    case 0x9B: io(c); c->y = c->x; goto nzy;
    case 0xBB: io(c); c->x = c->y; goto nzx;
    nzx: if (X8) nz8(c, c->x); else nz16(c, c->x); break;
    nzy: if (X8) nz8(c, c->y); else nz16(c, c->y); break;
    case 0x8A: io(c); v = c->x; goto toa;
    case 0x98: io(c); v = c->y; goto toa;
    toa: if (M8) { c->a = (c->a & 0xFF00) | (v & 0xFF); nz8(c, v); } else { c->a = v; nz16(c, v); } break;
    case 0x9A: io(c); c->s = c->e ? (0x0100 | (c->x & 0xFF)) : c->x; break;
    case 0x1B: io(c); c->s = c->e ? (0x0100 | (c->a & 0xFF)) : c->a; break;     /* TCS */
    case 0x3B: io(c); c->a = c->s; nz16(c, c->a); break;                        /* TSC */
    case 0x5B: io(c); c->d = c->a; nz16(c, c->d); break;                        /* TCD */
    case 0x7B: io(c); c->a = c->d; nz16(c, c->a); break;                        /* TDC */
    case 0xEB: io(c); io(c); c->a = (c->a >> 8) | (c->a << 8); nz8(c, c->a); break; /* XBA */

    /* ── flags ── */
    case 0x18: io(c); c->p &= ~P_C; break;
    case 0x38: io(c); c->p |= P_C; break;
    case 0x58: io(c); c->p &= ~P_I; break;
    case 0x78: io(c); c->p |= P_I; break;
    case 0xB8: io(c); c->p &= ~P_V; break;
    case 0xD8: io(c); c->p &= ~P_D; break;
    case 0xF8: io(c); c->p |= P_D; break;
    case 0xC2: v = fetch8(c); io(c); c->p &= ~v; fixP(c); break;
    case 0xE2: v = fetch8(c); io(c); c->p |= v; fixP(c); break;
    case 0xFB: {                                                                /* XCE */
        io(c);
        int oc = c->p & P_C;
        setf(c, P_C, c->e);
        c->e = oc ? 1 : 0;
        if (c->e) { c->p |= P_M | P_X; c->s = 0x0100 | (c->s & 0xFF); }
        fixP(c);
        break;
    }

    /* ── stack ── */
    case 0x48: io(c); if (!M8) push8(c, c->a >> 8); push8(c, c->a & 0xFF); break;
    case 0xDA: io(c); if (!X8) push8(c, c->x >> 8); push8(c, c->x & 0xFF); break;
    case 0x5A: io(c); if (!X8) push8(c, c->y >> 8); push8(c, c->y & 0xFF); break;
    case 0x08: io(c); push8(c, c->p); break;
    case 0x8B: io(c); push8(c, c->dbr); break;
    case 0x4B: io(c); push8(c, c->pbr); break;
    case 0x0B: io(c); pushN(c, c->d >> 8); pushN(c, c->d & 0xFF); fixS(c); break;
    case 0x68: io(c); io(c);
        if (M8) { v = pull8(c); c->a = (c->a & 0xFF00) | v; nz8(c, v); }
        else { v = pull8(c); v |= pull8(c) << 8; c->a = v; nz16(c, v); }
        break;
    case 0xFA: io(c); io(c);
        if (X8) { c->x = pull8(c); nz8(c, c->x); }
        else { v = pull8(c); v |= pull8(c) << 8; c->x = v; nz16(c, v); }
        break;
    case 0x7A: io(c); io(c);
        if (X8) { c->y = pull8(c); nz8(c, c->y); }
        else { v = pull8(c); v |= pull8(c) << 8; c->y = v; nz16(c, v); }
        break;
    case 0x28: io(c); io(c); c->p = pull8(c); fixP(c); break;
    case 0xAB: io(c); io(c); c->dbr = pullN(c); nz8(c, c->dbr); fixS(c); break;
    case 0x2B: io(c); io(c); v = pullN(c); v |= pullN(c) << 8; c->d = v; nz16(c, v); fixS(c); break;
    case 0xF4: v = fetch16(c); pushN(c, v >> 8); pushN(c, v & 0xFF); fixS(c); break;     /* PEA */
    case 0xD4: {                                                                         /* PEI */
        uint8_t o = fetch8(c);
        if (DL) io(c);
        v = rd(c, dpaddrn(c, o), BUS_DATA);
        v |= rd(c, dpaddrn(c, o + 1u), BUS_DATA) << 8;
        pushN(c, v >> 8); pushN(c, v & 0xFF); fixS(c);
        break;
    }
    case 0x62: v = fetch16(c); io(c); v += c->pc;                                        /* PER */
        pushN(c, v >> 8); pushN(c, v & 0xFF); fixS(c); break;

    /* ── jumps, calls, returns ── */
    case 0x4C: c->pc = fetch16(c); break;
    case 0x5C: { uint32_t t = fetch24(c); c->pc = t; c->pbr = t >> 16; break; }
    case 0x6C: { uint16_t p = fetch16(c); v = rd(c, p, BUS_DATA); v |= rd(c, (uint16_t)(p + 1), BUS_DATA) << 8; c->pc = v; break; }
    case 0x7C: { uint16_t p = fetch16(c); io(c); p += c->x;
        v = rd(c, (uint32_t)c->pbr << 16 | p, BUS_DATA);
        v |= rd(c, (uint32_t)c->pbr << 16 | (uint16_t)(p + 1), BUS_DATA) << 8;
        c->pc = v; break; }
    case 0xDC: { uint16_t p = fetch16(c);
        uint32_t t = rd(c, p, BUS_DATA);
        t |= rd(c, (uint16_t)(p + 1), BUS_DATA) << 8;
        t |= (uint32_t)rd(c, (uint16_t)(p + 2), BUS_DATA) << 16;
        c->pc = t; c->pbr = t >> 16; break; }
    case 0x20: v = fetch16(c); io(c); c->pc--; push8(c, c->pc >> 8); push8(c, c->pc & 0xFF); c->pc = v; break;
    case 0x22: {                                                                         /* JSL */
        uint16_t t = fetch16(c);
        pushN(c, c->pbr);
        io(c);
        uint8_t b = fetch8(c);
        c->pc--;
        pushN(c, c->pc >> 8); pushN(c, c->pc & 0xFF);
        c->pc = t; c->pbr = b; fixS(c);
        break;
    }
    case 0xFC: {                                                                         /* JSR (abs,X) */
        uint16_t p = fetch8(c);
        pushN(c, c->pc >> 8); pushN(c, c->pc & 0xFF);
        p |= fetch8(c) << 8;
        io(c);
        p += c->x;
        v = rd(c, (uint32_t)c->pbr << 16 | p, BUS_DATA);
        v |= rd(c, (uint32_t)c->pbr << 16 | (uint16_t)(p + 1), BUS_DATA) << 8;
        c->pc = v; fixS(c);
        break;
    }
    case 0x60: io(c); io(c); v = pull8(c); v |= pull8(c) << 8; io(c); c->pc = v + 1; break;
    case 0x6B: io(c); io(c); v = pullN(c); v |= pullN(c) << 8; c->pbr = pullN(c); c->pc = v + 1; fixS(c); break;
    case 0x40:                                                                           /* RTI */
        io(c); io(c);
        c->p = pull8(c); fixP(c);
        v = pull8(c); v |= pull8(c) << 8; c->pc = v;
        if (!c->e) c->pbr = pull8(c);
        break;
    case 0x00: case 0x02: {                                                              /* BRK / COP */
        fetch8(c);
        if (!c->e) push8(c, c->pbr);
        push8(c, c->pc >> 8);
        push8(c, c->pc & 0xFF);
        push8(c, c->p);
        c->p = (c->p | P_I) & ~P_D;
        c->pbr = 0;
        vector_pull(c, op == 0 ? V_BRK : V_COP);
        break;
    }

    /* ── branches ── */
    case 0x10: branch(c, !(c->p & P_N)); break;
    case 0x30: branch(c, c->p & P_N); break;
    case 0x50: branch(c, !(c->p & P_V)); break;
    case 0x70: branch(c, c->p & P_V); break;
    case 0x90: branch(c, !(c->p & P_C)); break;
    case 0xB0: branch(c, c->p & P_C); break;
    case 0xD0: branch(c, !(c->p & P_Z)); break;
    case 0xF0: branch(c, c->p & P_Z); break;
    case 0x80: branch(c, 1); break;
    case 0x82: v = fetch16(c); io(c); c->pc += v; break;                                /* BRL */

    /* ── block moves: one byte per execution, the opcode is fetched again ── */
    case 0x44: case 0x54: {
        uint8_t db = fetch8(c), sb = fetch8(c);
        c->dbr = db;
        uint8_t b = rd(c, (uint32_t)sb << 16 | c->x, BUS_DATA);
        wr(c, (uint32_t)db << 16 | c->y, b);
        io(c);
        int d = (op == 0x54) ? 1 : -1;
        if (X8) { c->x = (uint8_t)(c->x + d); c->y = (uint8_t)(c->y + d); }
        else { c->x += d; c->y += d; }
        io(c);
        if (c->a-- != 0) c->pc -= 3;
        break;
    }

    /* ── misc ── */
    case 0x42: io(c); c->pc++; break;                    /* WDM: the 2nd byte is skipped, not a VPA cycle */
    case 0xEA: io(c); break;
    case 0xCB: io(c); io(c); c->waiting = 1; break;
    case 0xDB: io(c); io(c); c->stopped = 1; break;
    }
}

void cpu_exec(Cpu65816 *c)
{
    uint8_t op = rd(c, PROGADDR, BUS_SYNC);
    c->pc++;
    exec_op(c, op);
}

int cpu_step(Cpu65816 *c)
{
    uint64_t start = c->cycles;
    if (c->stopped) return 0;
    if (c->waiting) {
        if (!c->nmi && !c->irq) return 0;
        c->waiting = 0;
    }
    if (!c->just_int) {
        if (c->nmi) {
            c->nmi = 0;
            c->n_nmi++;
            interrupt(c, V_NMI);
            return (int)(c->cycles - start);
        }
        if (c->irq && !c->poll_i) {
            c->n_irq++;
            interrupt(c, V_IRQ);
            return (int)(c->cycles - start);
        }
    }
    c->just_int = 0;

    /* snapshot for ABORT */
    uint16_t sa = c->a, sx = c->x, sy = c->y, ss = c->s, sd = c->d, spc = c->pc;
    uint8_t spbr = c->pbr, sdbr = c->dbr, sp = c->p, se = c->e;
    c->abort = 0;

    uint8_t op = rd(c, PROGADDR, BUS_SYNC);
    c->pc++;
    exec_op(c, op);
    c->n_insn++;

    if (c->abort) {
        c->a = sa; c->x = sx; c->y = sy; c->s = ss; c->d = sd; c->pc = spc;
        c->pbr = spbr; c->dbr = sdbr; c->p = sp; c->e = se;
        c->waiting = 0; c->stopped = 0;
        c->abort = 0;
        c->n_abort++;
        interrupt(c, V_ABORT);
    } else {
        /* the IRQ poll happens before CLI/SEI/PLP/REP/SEP change I (as on the 6502 family) */
        if (op == 0x58 || op == 0x78 || op == 0x28 || op == 0xC2 || op == 0xE2)
            c->poll_i = sp & P_I;
        else
            c->poll_i = c->p & P_I;
    }
    return (int)(c->cycles - start);
}

/* ── disassembly for --trace ──────────────────────────────────────────────── */
enum { IMP, IMM, IMMX, IMM8, ABS, ABSX, ABSY, LONG, LONGX, DP, DPX, DPY, DPI, DPIX, DPIY, DPIL, DPILY,
       SR, SRIY, REL, RELL, ABSI, ABSIX, ABSIL, BLK, ACC };
static const char *const mn[256] = {
"BRK","ORA","COP","ORA","TSB","ORA","ASL","ORA","PHP","ORA","ASL","PHD","TSB","ORA","ASL","ORA",
"BPL","ORA","ORA","ORA","TRB","ORA","ASL","ORA","CLC","ORA","INC","TCS","TRB","ORA","ASL","ORA",
"JSR","AND","JSL","AND","BIT","AND","ROL","AND","PLP","AND","ROL","PLD","BIT","AND","ROL","AND",
"BMI","AND","AND","AND","BIT","AND","ROL","AND","SEC","AND","DEC","TSC","BIT","AND","ROL","AND",
"RTI","EOR","WDM","EOR","MVP","EOR","LSR","EOR","PHA","EOR","LSR","PHK","JMP","EOR","LSR","EOR",
"BVC","EOR","EOR","EOR","MVN","EOR","LSR","EOR","CLI","EOR","PHY","TCD","JML","EOR","LSR","EOR",
"RTS","ADC","PER","ADC","STZ","ADC","ROR","ADC","PLA","ADC","ROR","RTL","JMP","ADC","ROR","ADC",
"BVS","ADC","ADC","ADC","STZ","ADC","ROR","ADC","SEI","ADC","PLY","TDC","JMP","ADC","ROR","ADC",
"BRA","STA","BRL","STA","STY","STA","STX","STA","DEY","BIT","TXA","PHB","STY","STA","STX","STA",
"BCC","STA","STA","STA","STY","STA","STX","STA","TYA","STA","TXS","TXY","STZ","STA","STZ","STA",
"LDY","LDA","LDX","LDA","LDY","LDA","LDX","LDA","TAY","LDA","TAX","PLB","LDY","LDA","LDX","LDA",
"BCS","LDA","LDA","LDA","LDY","LDA","LDX","LDA","CLV","LDA","TSX","TYX","LDY","LDA","LDX","LDA",
"CPY","CMP","REP","CMP","CPY","CMP","DEC","CMP","INY","CMP","DEX","WAI","CPY","CMP","DEC","CMP",
"BNE","CMP","CMP","CMP","PEI","CMP","DEC","CMP","CLD","CMP","PHX","STP","JML","CMP","DEC","CMP",
"CPX","SBC","SEP","SBC","CPX","SBC","INC","SBC","INX","SBC","NOP","XBA","CPX","SBC","INC","SBC",
"BEQ","SBC","SBC","SBC","PEA","SBC","INC","SBC","SED","SBC","PLX","XCE","JSR","SBC","INC","SBC" };

static int mode_of(uint8_t op)
{
    switch (op) {
    case 0x00: case 0x02: case 0x42: case 0xC2: case 0xE2: return IMM8;
    case 0x20: case 0x4C: case 0xF4: return ABS;
    case 0x22: case 0x5C: return LONG;
    case 0x6C: return ABSI;
    case 0x7C: case 0xFC: return ABSIX;
    case 0xDC: return ABSIL;
    case 0x44: case 0x54: return BLK;
    case 0x62: case 0x82: return RELL;
    case 0xD4: return DPI;
    case 0x0A: case 0x2A: case 0x4A: case 0x6A: case 0x1A: case 0x3A: return ACC;
    case 0xA0: case 0xA2: case 0xC0: case 0xE0: return IMMX;
    case 0x89: return IMM;
    case 0x96: case 0xB6: return DPY;
    case 0xBE: return ABSY;
    }
    if ((op & 0x1F) == 0x10) return REL;
    if (op == 0x80) return REL;
    int lo = op & 0x1F;
    if ((op & 3) == 1 || (op & 3) == 3 || lo == 0x12) {
        switch (lo) {
        case 0x01: return DPIX; case 0x03: return SR; case 0x05: return DP; case 0x07: return DPIL;
        case 0x09: return IMM; case 0x0D: return ABS; case 0x0F: return LONG; case 0x11: return DPIY;
        case 0x12: return DPI; case 0x13: return SRIY; case 0x15: return DPX; case 0x17: return DPILY;
        case 0x19: return ABSY; case 0x1D: return ABSX; case 0x1F: return LONGX;
        }
    }
    switch (lo) {
    case 0x04: case 0x06: return DP;
    case 0x0C: case 0x0E: return ABS;
    case 0x14: case 0x16: return DPX;
    case 0x1C: case 0x1E: return ABSX;
    }
    return IMP;
}

const char *cpu_mnemonic(uint8_t op) { return mn[op]; }

static int mode_len(const Cpu65816 *c, int m)
{
    switch (m) {
    case IMP: case ACC: return 1;
    case IMM: return (c->p & P_M) ? 2 : 3;
    case IMMX: return (c->p & P_X) ? 2 : 3;
    case IMM8: case DP: case DPX: case DPY: case DPI: case DPIX: case DPIY: case DPIL: case DPILY:
    case SR: case SRIY: case REL: return 2;
    case ABS: case ABSX: case ABSY: case ABSI: case ABSIX: case ABSIL: case RELL: case BLK: return 3;
    case LONG: case LONGX: return 4;
    }
    return 1;
}

int cpu_insn_len(const Cpu65816 *c, uint8_t op) { return mode_len(c, mode_of(op)); }

int cpu_format(const Cpu65816 *c, uint8_t op, const uint8_t *o, char *buf, int n)
{
    int m = mode_of(op), len = mode_len(c, m);
    unsigned w = o[0] | o[1] << 8, l = w | (unsigned)o[2] << 16;
    const char *s = mn[op];
    switch (m) {
    case IMP: return snprintf(buf, n, "%s", s);
    case ACC: return snprintf(buf, n, "%s A", s);
    case IMM: case IMMX: return len == 2 ? snprintf(buf, n, "%s #$%02X", s, o[0]) : snprintf(buf, n, "%s #$%04X", s, w);
    case IMM8: return snprintf(buf, n, "%s #$%02X", s, o[0]);
    case ABS: return snprintf(buf, n, "%s $%04X", s, w);
    case ABSX: return snprintf(buf, n, "%s $%04X,X", s, w);
    case ABSY: return snprintf(buf, n, "%s $%04X,Y", s, w);
    case LONG: return snprintf(buf, n, "%s $%06X", s, l);
    case LONGX: return snprintf(buf, n, "%s $%06X,X", s, l);
    case DP: return snprintf(buf, n, "%s $%02X", s, o[0]);
    case DPX: return snprintf(buf, n, "%s $%02X,X", s, o[0]);
    case DPY: return snprintf(buf, n, "%s $%02X,Y", s, o[0]);
    case DPI: return snprintf(buf, n, "%s ($%02X)", s, o[0]);
    case DPIX: return snprintf(buf, n, "%s ($%02X,X)", s, o[0]);
    case DPIY: return snprintf(buf, n, "%s ($%02X),Y", s, o[0]);
    case DPIL: return snprintf(buf, n, "%s [$%02X]", s, o[0]);
    case DPILY: return snprintf(buf, n, "%s [$%02X],Y", s, o[0]);
    case SR: return snprintf(buf, n, "%s $%02X,S", s, o[0]);
    case SRIY: return snprintf(buf, n, "%s ($%02X,S),Y", s, o[0]);
    case REL: return snprintf(buf, n, "%s $%04X", s, (uint16_t)(c->pc + 2 + (int8_t)o[0]));
    case RELL: return snprintf(buf, n, "%s $%04X", s, (uint16_t)(c->pc + 3 + w));
    case ABSI: return snprintf(buf, n, "%s ($%04X)", s, w);
    case ABSIX: return snprintf(buf, n, "%s ($%04X,X)", s, w);
    case ABSIL: return snprintf(buf, n, "%s [$%04X]", s, w);
    case BLK: return snprintf(buf, n, "%s $%02X,$%02X", s, o[1], o[0]);
    }
    return snprintf(buf, n, "%s", s);
}
