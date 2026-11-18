/* Ali, the blitter, $00:DA00-$DA13 (REV $08): five rectangle operations on 8 bpp surfaces. The pixels
 * are written at START; BUSY then reads 1 for a modelled time and the IRQ comes at its end.
 * REV $09: command lists ($DA14-$DA18, BL_CTRL bits 2-5). */
#ifndef BLITTER_H
#define BLITTER_H
#include <stdint.h>

typedef struct Blitter {
    uint8_t  r[0x19];               /* register file as written ($DA14-$DA18: REV $09 list) */
    uint64_t n_blits, n_pixels;
    uint64_t busy_until;            /* CPU cycle at which BUSY drops */
    uint8_t  irq_due;               /* raise BLITTER at busy_until */
    uint64_t busy_cycles;           /* sum of modelled blit times */
    uint64_t n_busy_starts;         /* START written while BUSY: ignored (a driver bug) */
    uint64_t n_busy_writes;         /* other register writes while BUSY (illegal) */
    uint64_t n_stale_reads;         /* CPU reads of blitter-written memory with no CACHE_FLUSH since */
    uint8_t *stale;                 /* one bit per 8-byte line written by the blitter since the flush */
    /* REV $09: command lists, DONE / ABORTED */
    uint8_t  list;                  /* a list is running */
    uint8_t  lphase;                /* 0: the next record is read at list_next; 1: it starts then */
    uint8_t  lwait;                 /* the started record waits for VBLANK (BL_CTRL.WAITING) */
    uint64_t list_next;             /* CPU cycle of the list's next step */
    uint8_t  done, aborted;         /* DONE (reported once BUSY is 0), ABORTED */
    uint64_t n_lists, n_records;
} Blitter;

void    blitter_reset(void);
uint8_t blitter_read(uint32_t a);
void    blitter_write(uint32_t a, uint8_t v);
void    blitter_update(uint64_t now);   /* the end-of-blit interrupt */
void    blitter_flush(void);            /* CACHE_FLUSH (or the mailbox's own sweep) */
void    blitter_stale_read(uint32_t a); /* a CPU read of RAM at physical a: counts stale lines */
uint64_t blitter_next_event(void);

#endif
