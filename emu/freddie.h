/* FREDDIE II, native side: memory map, bank 0 window, mode stack, protection, ABORT.
 * Mirrors core/src/a816/a816_sys.sv. */
#ifndef FREDDIE_H
#define FREDDIE_H
#include <stdint.h>

typedef struct Freddie {
    uint8_t  prot_en, b0win_en, wp_vec;
    uint8_t  pt_index, b0win, cur_task, abort_cause;
    uint32_t abort_addr;
    uint8_t  mode_user;     /* current mode, 1 = user */
    uint8_t  mstack;        /* 8-deep mode stack, bit 0 = top = FR_CTRL.USER_ARM */
    uint8_t  rti_seen, in_pull, wr_block;
    uint8_t  nmi_hold;      /* NMI not presented: entered from user mode, FR_CTRL not yet written */
    uint8_t  pt[256];
    uint64_t n_refused;
} Freddie;

void    freddie_reset(void);
uint8_t bus_read(void *ctx, uint32_t a, int flags);
void    bus_write(void *ctx, uint32_t a, uint8_t v, int flags);
uint8_t bus_peek(uint32_t a);          /* side-effect free CPU view of RAM (trace) */
uint8_t freddie_io_read(uint32_t a);
void    freddie_io_write(uint32_t a, uint8_t v);

#endif
