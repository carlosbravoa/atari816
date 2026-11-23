/* I/O processor mailbox $00:DD00-$DD0A, served against a host directory (--sd).
 * Mirrors a816_mailbox() in core/firmware/firmware.c. */
#ifndef MAILBOX_H
#define MAILBOX_H
#include <stdint.h>
#include <stdio.h>

#define MB_FILES    4
#define MB_POLL     512             /* CPU cycles between I/O processor polls (~36 us) */
#define MB_KQ       64              /* key changes not yet reported, in order */
#define MB_MSEG     16              /* mouse: runs of motion with the same buttons */

typedef struct Mailbox {
    uint32_t req_base, rsp_base;
    uint8_t  req_head, req_tail, rsp_head, rsp_tail;
    uint8_t  ready, error;
    uint64_t next_poll;
    FILE    *f[MB_FILES];
    uint8_t  fmode[MB_FILES];       /* bit 0 readable, bit 1 writable */
    uint8_t  fdirty[MB_FILES];      /* created or written: its date is set at close (SYS_TIME) */
    char    *fhost[MB_FILES];       /* its host path */
    uint8_t  fpc[MB_FILES];         /* on the PC volume (/PC:, --pc-folder) */
    uint8_t  fsess[MB_FILES];       /* the PC link session it was opened in */
    char    *ftmp[MB_FILES];        /* a PC file opened with mode 2: the temporary host file it
                                     * is written to (moved onto fhost at CLOSE; NULL: none, or
                                     * deleted when the link dropped) */
    uint8_t  fprn[MB_FILES];        /* (Horizon 0.23) a print job (/PRN:NAME): ftmp is its name
                                     * with a '.' in front, moved onto fhost at CLOSE */
    const char *root;               /* --sd directory, or NULL */
    uint64_t n_req, n_keyev, n_mouseev;
    uint64_t n_op[32], op_bytes[32];  /* (--stats) requests by kind, bytes asked (READ/WRITE/LOAD) */
    /* keyboard: what the USB side holds now (4 usages + modifier bitmap), and what the
     * I/O processor has reported so far (firmware "Keyboard events" block) */
    uint8_t  kb_now[4], kb_now_mods;
    uint8_t  kb_held[4], kb_mods;
    /* every key change since the last event, in order (a press and its release are never
     * merged): usage, 1 down / 0 up */
    uint8_t  kq_usage[MB_KQ], kq_down[MB_KQ];
    uint8_t  kq_head, kq_n;
    /* mouse: the buttons now, and runs of motion not yet sent, oldest first: motion with
     * unchanged buttons is added to the last run; a button change starts a new run that is
     * always sent (force), so a quick click is never lost */
    uint8_t  ms_btn;
    struct { int32_t dx, dy, wheel; uint8_t btn, force; } ms_seg[MB_MSEG];
    uint8_t  ms_head, ms_n;
    /* the request in progress (--card-kbps, --pc-kbps: its answer comes at busy_until) */
    uint8_t  busy, busy_pc, busy_sess;
    uint64_t busy_until;
    uint8_t  busy_msg[16];
    /* classic software ops $18-$1A (stub): what is mounted */
    uint8_t  cl_disk[4], cl_xex, cl_cart;
    /* SYS_RESTART ($1B, stub): 1 + ARG0 once answered; main.c then restarts the machine */
    int      restart;
} Mailbox;

void    mailbox_reset(void);
extern const char *mailbox_boot_cart;   /* --boot-cart PATH (FAT path on --sd) */
#include <time.h>
extern time_t mailbox_card_date;        /* --card-date: STAT's date of the files this run did not write */
/* the PC volume (PC link step 1): /PC: paths served from a host folder */
extern const char *mailbox_pc_root;     /* --pc-folder DIR (NULL: no PC link, $87) */
extern time_t mailbox_pc_time;          /* --pc-time: the PC's clock at power-on (0: the host clock) */
extern double mailbox_pc_drop;          /* --pc-drop-at: emulated second the link drops (< 0 never) */
extern double mailbox_pc_back;          /* --pc-back-at: emulated second it comes back (< 0 never) */
/* --card-kbps R:W, --pc-kbps R:W: slow transfers (KB/s for READ / LOAD and WRITE; 0 = instant).
 * Given (either rate not 0): every request on that volume also costs a fixed time */
extern double mailbox_card_kbps[2], mailbox_pc_kbps[2];
/* --card-board: the board's card request by request (mailbox.c); the costs, --card-costs */
enum { CC_OPEN, CC_STAT, CC_CLOSE, CC_CLOSEW, CC_SEEK, CC_OTHER, CC_READ, CC_WRITE, CC_RKBPS, CC_WKBPS, CC_N };
extern int mailbox_card_board;
extern double mailbox_card_board_at;
extern double mailbox_card_cost[CC_N];
extern long long mailbox_card_free;     /* --card-free BYTES (-1: no limit) */
/* (Horizon 0.23) printing: --no-pc-print (the gateway cannot make PDFs: STAT /PC: without
 * bit 4), --classic-print FILE@SECONDS (a print job of the classic Atari's printer, P:) */
extern int     mailbox_no_pc_print;
int     mailbox_classic_print(const char *arg);    /* 0 OK, -1 a bad argument */
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
