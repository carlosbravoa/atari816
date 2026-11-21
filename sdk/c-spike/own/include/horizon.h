/* horizon.h - Horizon syscalls for cc816 (spike subset of horizon.inc).
 *
 * cc816's model: every data pointer is a 16-bit offset in the program's code bank (DBR):
 * globals, string constants, locals whose address is taken, malloc blocks. A syscall
 * takes a pointer as X = offset, Y = bank: HZ_OFF(p) and HZ_BANK(p) (= the code bank).
 * __far pointers (32 bits: offset, bank) reach other banks.
 * The gate: hz_sys(n, a, x, y) -> A; hz_err = 0 or the error code; hz_x, hz_y = X, Y out.
 */
#ifndef HORIZON_H
#define HORIZON_H

extern unsigned hz_err, hz_x, hz_y;
unsigned hz_sys(unsigned n, unsigned a, unsigned x, unsigned y);
unsigned long hz_sysl(unsigned n, unsigned a, unsigned x, unsigned y);   /* A | X << 16 */

/* crt0.s: the argument string, copied into the code bank */
extern char hz_args[];
extern unsigned __hz_arglen;

#define HZ_OFF(p)  ((unsigned)(p))
#define HZ_BANK(p) __cbank()
#define HZ_FAROFF(p)  ((unsigned)(unsigned long)(p))
#define HZ_FARBANK(p) ((unsigned)((unsigned long)(p) >> 16))

/* syscall numbers (horizon.inc) */
#define SYS_EXIT     0x00
#define SYS_YIELD    0x01
#define SYS_SLEEP    0x02
#define SYS_GETPID   0x03
#define SYS_UPTIME   0x04
#define SYS_PUTC     0x05
#define SYS_PUTS     0x06
#define SYS_BALLOC   0x10
#define SYS_BFREE    0x11
#define SYS_SPAWN    0x30
#define SYS_WAIT     0x31
#define SYS_WSSTART  0x70
#define SYS_WSSTOP   0x71
#define SYS_WOPEN    0x72
#define SYS_WCLOSE   0x73
#define SYS_WDRAW    0x74
#define SYS_WEVENT   0x75

#define HZ_SYSP(n, a, p)  hz_sys((n), (a), HZ_OFF(p), HZ_BANK(p))

#define hz_exit(code)     hz_sys(SYS_EXIT, (code), 0, 0)
#define hz_sleep(ms)      hz_sys(SYS_SLEEP, (ms), 0, 0)
#define hz_putc(c)        __cop(SYS_PUTC, (unsigned char)(c), 0, 0)
#define hz_puts(s)        HZ_SYSP(SYS_PUTS, 0, s)
#define hz_uptime()       hz_sysl(SYS_UPTIME, 0, 0, 0)
#define hz_getpid()       __cop(SYS_GETPID, 0, 0, 0)
#define hz_balloc()       hz_sys(SYS_BALLOC, 0, 0, 0)

/* u24 pointer inside parameter blocks: offset + bank */
typedef struct { unsigned off; unsigned char bank; } hz_far;
#define HZ_FAR(f, p) ((f).off = HZ_OFF(p), (f).bank = (unsigned char)HZ_BANK(p))

/* window system */
#define WF_RESIZE 1
#define WF_PLAIN  2
#define WD_FILL   1
#define WD_FRAME  2
#define WD_LINE   3
#define WD_TEXT   4
#define WE_KEY    1
#define WE_BUTTON 2
#define WE_CLOSE  3
#define C_BLACK   0
#define C_WHITE   1
#define C_BODY    6
#define C_RED     11
#define C_YELLOW  12
#define C_GREEN   13

typedef struct {                /* win_open block */
    int x, y;
    unsigned w, h;
    hz_far title;
    unsigned char flags;
} hz_wopen_t;

typedef struct {                /* win_draw block (ops 1-9) */
    unsigned char op, c1, c2, font;
    int x, y, w, h;
    hz_far ptr;
} hz_wdraw_t;

typedef struct {                /* win_event record */
    unsigned char type, win;
    unsigned a, b, c;
} hz_event_t;

#define hz_ws_start()         hz_sys(SYS_WSSTART, 0, 0, 0)
#define hz_ws_stop()          hz_sys(SYS_WSSTOP, 0, 0, 0)
#define hz_win_open(blk)      HZ_SYSP(SYS_WOPEN, 0, blk)
#define hz_win_close(w)       hz_sys(SYS_WCLOSE, (w), 0, 0)
#define hz_win_draw(w, blk)   HZ_SYSP(SYS_WDRAW, (w), blk)
#define hz_win_event(poll, e) HZ_SYSP(SYS_WEVENT, (poll), e)

#endif
