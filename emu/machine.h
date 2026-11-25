/* emu816 — the whole machine in one global, so device code is short and fast. */
#ifndef MACHINE_H
#define MACHINE_H
#include <stdint.h>
#include <stdio.h>
#include "cpu65816.h"
#include "freddie.h"
#include "sysblock.h"
#include "mailbox.h"
#include "nvc.h"
#include "blitter.h"
#include "audio.h"
#include "opl.h"

#define RAM_SIZE   0x800000u            /* 8 MB: AW = 23 */
#define CPU_HZ     14343750.0           /* 28.6875 MHz / 2 */

typedef struct Machine {
    Cpu65816 cpu;
    uint8_t *ram;
    Freddie  fr;
    SysBlock sys;
    Mailbox  mb;
    Nvc      nvc;
    Blitter  bl;
    Audio    au;
    Opl      opl;
    uint64_t next_event;                /* earliest cycle at which some device needs to run */
    int      trace;
    uint32_t ipc;                       /* PBR:PC of the instruction being executed (--watch) */
    int      nwatch;                    /* --watch: physical ranges [lo, hi) logged when written */
    uint32_t watch_lo[16], watch_hi[16];
} Machine;

extern Machine M;

/* --watch (main.c): log a write of v at physical address a (dma: not the CPU's) */
void watch_hit(uint32_t a, uint8_t v, int dma);
static inline void watch_check(uint32_t a, uint8_t v, int dma)
{
    for (int i = 0; i < M.nwatch; i++)
        if (a >= M.watch_lo[i] && a < M.watch_hi[i]) { watch_hit(a, v, dma); return; }
}

/* physical (DMA) access: no window, no protection, nothing above 8 MB */
static inline uint8_t phys_rd(uint32_t a) { return a < RAM_SIZE ? M.ram[a] : 0; }
static inline void phys_wr(uint32_t a, uint8_t v)
{
    if (a < RAM_SIZE) {
        if (M.nwatch) watch_check(a, v, 1);
        M.ram[a] = v;
    }
}

/* bring every device up to the CPU's current cycle (cheap when nothing is due) */
void machine_sync_slow(void);
void emu_console_byte(uint8_t v);       /* (main.c) DBG_OUT: stdout, the console's lines watched */
void emu_lau_keyon(void);               /* (main.c) a Lau voice started: a script's sound wait */
static inline void machine_sync(void) { if (M.cpu.cycles >= M.next_event) machine_sync_slow(); }
void machine_reschedule(void);
void machine_update_irq(void);

#endif
