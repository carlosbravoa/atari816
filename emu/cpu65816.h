/* cpu65816 — cycle-counted 65C816 interpreter for emu816.
 *
 * Every bus access goes through the read/write callbacks; one callback = one bus cycle.
 * Internal (VDA = VPA = 0) cycles are only counted. The cycle counts follow the WDC
 * data sheet (m/x/DL/page-cross/emulation adjustments), validated against the
 * SingleStepTests 65816 suite.
 *
 * ABORT (Atari816 RTL semantics): the bus sets cpu->abort when it refuses an access.
 * The instruction runs to its end, then every register is restored to its value at the
 * opcode fetch and the ABORT vector is taken (the stacked PC is the aborted instruction).
 * Refusals inside an interrupt entry sequence are ignored by the CPU.
 */
#ifndef CPU65816_H
#define CPU65816_H
#include <stdint.h>

enum {
    BUS_SYNC   = 0x01,   /* opcode fetch (VPA & VDA) */
    BUS_PROG   = 0x02,   /* operand fetch (VPA) */
    BUS_DATA   = 0x04,   /* data access (VDA) */
    BUS_VECTOR = 0x08,   /* vector pull (VPB low) */
    BUS_INTSEQ = 0x10,   /* inside an interrupt / abort / reset entry sequence */
};

enum { P_C = 0x01, P_Z = 0x02, P_I = 0x04, P_D = 0x08, P_X = 0x10, P_M = 0x20, P_V = 0x40, P_N = 0x80 };

typedef uint8_t (*cpu_read_fn)(void *ctx, uint32_t addr, int flags);
typedef void    (*cpu_write_fn)(void *ctx, uint32_t addr, uint8_t val, int flags);

typedef struct Cpu65816 {
    uint16_t a, x, y, s, d, pc;
    uint8_t  pbr, dbr, p, e;

    uint64_t cycles;        /* CPU cycles since reset */
    uint8_t  stopped;       /* STP executed */
    uint8_t  waiting;       /* WAI executed, waiting for IRQ/NMI */
    uint8_t  irq;           /* IRQ line level, driven by the system (1 = asserted) */
    uint8_t  nmi;           /* NMI edge latch, set by the system, cleared when taken */
    uint8_t  abort;         /* set by the bus: an access of this instruction was refused */
    uint8_t  just_int;      /* an entry sequence just ran: next step executes an instruction */
    uint8_t  poll_i;        /* I flag the IRQ poll at the end of the last instruction saw */
    uint8_t  intseq;        /* BUS_INTSEQ while in an entry sequence, else 0 */

    uint32_t ea, eam;       /* effective address scratch (eam: wrap mask for the 2nd byte) */

    void        *ctx;
    cpu_read_fn  read;
    cpu_write_fn write;

    uint64_t n_insn, n_irq, n_nmi, n_abort;
} Cpu65816;

void cpu_init(Cpu65816 *c, void *ctx, cpu_read_fn rd, cpu_write_fn wr);
void cpu_reset(Cpu65816 *c);
/* One step: an interrupt entry, or one instruction (one MVN/MVP byte). Does nothing when
 * stopped or waiting with no interrupt. Returns the number of cycles used. */
int  cpu_step(Cpu65816 *c);
/* Execute exactly one instruction, ignoring interrupts (test harness). */
void cpu_exec(Cpu65816 *c);

/* Disassembly helpers for --trace: mnemonic and instruction length for opcode op. */
const char *cpu_mnemonic(uint8_t op);
int  cpu_insn_len(const Cpu65816 *c, uint8_t op);
int  cpu_format(const Cpu65816 *c, uint8_t op, const uint8_t *opnd, char *buf, int n);

#endif
