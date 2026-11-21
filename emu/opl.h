/* OPL2 (YM3812), $00:DB30-$DB33 (REV $0C): the registers, the status byte and timers A and B
 * of core/src/a816/a816_opl.sv (JTOPL: jtopl_mmr.v, jtopl_timers.v), and its sound (Nuked OPL3 in OPL2 mode). */
#ifndef OPL_H
#define OPL_H
#include <stdint.h>

typedef struct Opl {
    uint8_t  sel;                   /* the register selected at $DB30 */
    uint8_t  reg[256];              /* registers $01-$F5 as written (the shadow) */
    uint8_t  load[2];               /* $04 bits 0/1: timer A / B running */
    uint8_t  flagen[2];             /* !$04 bits 6/5: the flag reaches the status and the IRQ */
    uint8_t  flag[2];               /* overflow flags, before the masks */
    uint8_t  cnt[2];                /* the timers' counters (they overflow after 255) */
    uint64_t t0;                    /* CPU cycle of the chip's last reset */
    uint64_t done[2];               /* timer steps accounted for since t0 */
    uint64_t n_writes;              /* data writes ($DB31) */
} Opl;

void     opl_reset(void);           /* power-on, and whenever the 65C816 is held in reset */
void     opl_update(uint64_t now);
uint64_t opl_next_event(void);
uint8_t  opl_read(uint32_t a);
void     opl_write(uint32_t a, uint8_t v);
int      opl_irq(void);             /* timer A or B flag, unmasked: IRQ_STATUS bit 5 */
int16_t  opl_sample(uint64_t at);   /* the output at CPU cycle `at` (0 before REV $0C) */

#endif
