/* horizon.h - Horizon syscalls for cc65 C (spike: a hand-written subset of horizon.inc).
 *
 * Every C pointer is a 16-bit offset in the program's code bank; hz_bank is that bank.
 * The gate: set hz_a / hz_x / hz_y, call hz_sys(n); hz_err = 0 or the error code.
 */
#ifndef HORIZON_H
#define HORIZON_H

extern unsigned hz_a, hz_x, hz_y, hz_err;
extern unsigned hz_bank;                  /* the code bank (pointer bank for syscalls) */
extern char hz_args[128];                 /* the argument string, copied from bank 0 */
unsigned __fastcall__ hz_sys(unsigned char n);
unsigned long __fastcall__ hz_sysl(unsigned char n);   /* A | X << 16 */

/* syscall numbers (horizon.inc) */
#define SYS_EXIT     0x00
#define SYS_YIELD    0x01
#define SYS_SLEEP    0x02
#define SYS_UPTIME   0x04
#define SYS_PUTC     0x05
#define SYS_PUTS     0x06
#define SYS_WSSTART  0x70
#define SYS_WSSTOP   0x71
#define SYS_WOPEN    0x72
#define SYS_WCLOSE   0x73
#define SYS_WDRAW    0x74
#define SYS_WEVENT   0x75

/* u24 pointer inside parameter blocks: offset + bank */
typedef struct { unsigned off; unsigned char bank; } hz_far;
#define HZ_FAR(f, p) ((f).off = (unsigned)(p), (f).bank = (unsigned char)hz_bank)

/* the calls with a pointer in X, Y */
#define HZ_SYSP(n, a, p) (hz_a = (a), hz_x = (unsigned)(p), hz_y = hz_bank, hz_sys(n))

#define hz_exit(code)     (hz_a = (code), hz_sys(SYS_EXIT))
#define hz_sleep(ms)      (hz_a = (ms), hz_sys(SYS_SLEEP))
#define hz_putc(c)        (hz_a = (unsigned char)(c), hz_sys(SYS_PUTC))
#define hz_puts(s)        HZ_SYSP(SYS_PUTS, 0, s)
#define hz_uptime()       hz_sysl(SYS_UPTIME)

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

#define hz_ws_start()         (hz_sys(SYS_WSSTART))
#define hz_ws_stop()          (hz_sys(SYS_WSSTOP))
#define hz_win_open(blk)      HZ_SYSP(SYS_WOPEN, 0, blk)
#define hz_win_close(w)       (hz_a = (w), hz_sys(SYS_WCLOSE))
#define hz_win_draw(w, blk)   HZ_SYSP(SYS_WDRAW, w, blk)
#define hz_win_event(poll, e) HZ_SYSP(SYS_WEVENT, poll, e)

#endif
