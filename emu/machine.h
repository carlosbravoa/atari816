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
} Machine;

extern Machine M;

/* physical (DMA) access: no window, no protection, nothing above 8 MB */
static inline uint8_t phys_rd(uint32_t a) { return a < RAM_SIZE ? M.ram[a] : 0; }
static inline void phys_wr(uint32_t a, uint8_t v) { if (a < RAM_SIZE) M.ram[a] = v; }

/* bring every device up to the CPU's current cycle (cheap when nothing is due) */
void machine_sync_slow(void);
void emu_console_byte(uint8_t v);       /* (main.c) --shot-on: the console's lines watched */
static inline void machine_sync(void) { if (M.cpu.cycles >= M.next_event) machine_sync_slow(); }
void machine_reschedule(void);
void machine_update_irq(void);

#endif
