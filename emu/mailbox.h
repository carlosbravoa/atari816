/* I/O processor mailbox $00:DD00-$DD0A, served against a host directory (--sd).
 * Mirrors a816_mailbox() in core/firmware/firmware.c. */
#ifndef MAILBOX_H
#define MAILBOX_H
#include <stdint.h>
#include <stdio.h>

#define MB_FILES    4
#define MB_POLL     512             /* CPU cycles between I/O processor polls (~36 us) */

typedef struct Mailbox {
    uint32_t req_base, rsp_base;
    uint8_t  req_head, req_tail, rsp_head, rsp_tail;
    uint8_t  ready, error;
    uint64_t next_poll;
    FILE    *f[MB_FILES];
    uint8_t  fmode[MB_FILES];       /* bit 0 readable, bit 1 writable */
    uint8_t  fdirty[MB_FILES];      /* created or written: its date is set at close (SYS_TIME) */
    char    *fhost[MB_FILES];       /* its host path */
    const char *root;               /* --sd directory, or NULL */
    uint64_t n_req, n_keyev, n_mouseev;
    /* keyboard: what the USB side holds now (4 usages + modifier bitmap), and what the
     * I/O processor has reported so far (firmware "Keyboard events" block) */
    uint8_t  kb_now[4], kb_now_mods;
    uint8_t  kb_held[4], kb_mods;
    /* mouse (firmware ms_*): accumulated motion, current and last reported buttons */
    int16_t  ms_dx, ms_dy, ms_wheel;
    uint8_t  ms_btn, ms_btn_sent;
    /* classic software ops $18-$1A (stub): what is mounted */
    uint8_t  cl_disk[4], cl_xex, cl_cart;
    /* SYS_RESTART ($1B, stub): 1 + ARG0 once answered; main.c then restarts the machine */
    int      restart;
} Mailbox;

void    mailbox_reset(void);
extern const char *mailbox_boot_cart;   /* --boot-cart PATH (FAT path on --sd) */
#include <time.h>
extern time_t mailbox_card_date;        /* --card-date: STAT's date of the files this run did not write */
void    mailbox_poll(uint64_t now);
uint8_t mailbox_read(uint32_t a);
void    mailbox_write(uint32_t a, uint8_t v);
int     mailbox_pending(void);
/* the host keyboard changed: HID usage (modifiers $E0-$E7 go to the bitmap), 1 = down */
void    mailbox_key(uint8_t usage, int down);
/* the host mouse moved (counts = desktop pixels) and/or its buttons are now btn
 * (bit 0 left, 1 right, 2 middle): firmware a816_mouse() */
void    mailbox_mouse(int btn, int dx, int dy, int wheel);      /* MB_RSP_HEAD != MB_RSP_TAIL */

#endif
