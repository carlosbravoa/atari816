/* horizon.h - Horizon (Atari816) for C programs: the parameter blocks, every syscall as a
 * C function (hzsys.h, generated from horizon.inc and ABI.md), and the SDK's helpers.
 *
 *   #include <horizon.h>
 *
 * Pointers. In the large model (hcc's default) a data pointer is 32 bits (offset, bank)
 * and reaches everything: the code bank (globals, strings), the window (bank 0: locals,
 * the stack) and banks from hz_far_alloc. In the tiny model (hcc --model tiny) it is 16
 * bits and points into the window, where all the program's data lives; other banks need
 * __far pointers. A syscall takes a pointer as X = offset, Y = bank: the stubs do that.
 *
 * Errors. Every hz_ function sets hz_errno: 0 when the call worked, else Horizon's error
 * code (HZ_EINVAL, HZ_ENOMEM, ..., HZ_EIO + n for the card: HZ_ENOFILE ...). It returns -1
 * (or $FFFF for unsigned results) on an error. The C library (stdio.h, ...) sets errno
 * (errno.h) instead; hz_strerror() says a Horizon code in words.
 *
 * The blocks below have the exact byte layout of ABI.md (vbcc packs structures: no
 * padding); each has a compile-time size check.
 */
#ifndef HORIZON_H
#define HORIZON_H

#ifndef __SIZE_T
#define __SIZE_T 1
#ifdef __SIZE_T_INT
typedef unsigned int size_t;
#else
typedef unsigned long size_t;
#endif
#endif

/* ---- basics */

/* a compile-time check: HZ_STATIC_ASSERT(sizeof(hz_io) == 6, io) */
#define HZ_STATIC_ASSERT(cond, name) typedef char hz_assert_##name[(cond) ? 1 : -1]

/* HZ_TINY: defined in the tiny model (vbcc defines __MNEAR there; its manual says
 * __MTINY, which hcc defines too) */
#if defined(__MTINY) || defined(__MNEAR)
#define HZ_TINY 1
#endif

/* the offset and the bank of a data pointer (any model, near or far) */
#define HZ_OFF(p)  ((unsigned)(unsigned long)(p))
#define HZ_BANK(p) ((unsigned char)((unsigned long)(p) >> 16))

/* a u24: the 3-byte pointer of the parameter blocks (offset low, offset high, bank) */
typedef struct {
    unsigned short off;
    unsigned char bank;
} hz_u24;
HZ_STATIC_ASSERT(sizeof(hz_u24) == 3, u24);

/* set a u24 from a C pointer: HZ_U24(blk.title, "My window") */
#define HZ_U24(f, p) ((f).off = HZ_OFF(p), (f).bank = HZ_BANK(p))
/* a u24 from a bank and an offset */
#define HZ_U24B(f, bank_, off_) ((f).off = (off_), (f).bank = (unsigned char)(bank_))

/* the error code of the last hz_ call (0 = it worked); hz_x, hz_y: the X and Y registers
 * the calls marked "out" in hzsys.h leave (con_size's rows, input_read's position, ...) */
extern unsigned hz_errno, hz_x, hz_y;

/* ---- parameter blocks (ABI.md) */

typedef struct {                /* read, write: {u8 handle, u24 buffer, u16 length} */
    unsigned char handle;
    hz_u24 buf;
    unsigned short len;
} hz_io;
HZ_STATIC_ASSERT(sizeof(hz_io) == 6, io);

typedef struct {                /* stat's answer: 9 bytes */
    unsigned long size;
    unsigned char attr;         /* HZ_ATTR_DIR, HZ_ATTR_RDONLY, $20 archive */
    unsigned long time;         /* FAT: date << 16 | time */
} hz_fileinfo;
HZ_STATIC_ASSERT(sizeof(hz_fileinfo) == 9, fileinfo);
#define HZ_ATTR_RDONLY 0x01
#define HZ_ATTR_DIR    0x10

typedef struct {                /* stat: {u24 path, u24 out} */
    hz_u24 path;
    hz_u24 out;
} hz_statblk;
HZ_STATIC_ASSERT(sizeof(hz_statblk) == 6, statblk);

typedef struct {                /* readdir: {u24 path, u24 buffer, u16 length, u16 skip} */
    hz_u24 path;
    hz_u24 buf;
    unsigned short len;
    unsigned short skip;
} hz_readdirblk;
HZ_STATIC_ASSERT(sizeof(hz_readdirblk) == 10, readdirblk);

typedef struct {                /* one readdir entry, packed: the name follows (no 0) */
    unsigned long size;
    unsigned char attr;
    unsigned char namelen;
    /* char name[namelen]; */
} hz_dirent;
HZ_STATIC_ASSERT(sizeof(hz_dirent) == 6, dirent);

typedef struct {                /* rename: {u24 old path, u24 new path} */
    hz_u24 from;
    hz_u24 to;
} hz_renameblk;
HZ_STATIC_ASSERT(sizeof(hz_renameblk) == 6, renameblk);

typedef struct {                /* spawn: {u24 path, u24 args (0 = none), u8 priority} */
    hz_u24 path;
    hz_u24 args;
    unsigned char prio;         /* 0 (highest) - 3; | SP_DETACH */
} hz_spawnblk;
HZ_STATIC_ASSERT(sizeof(hz_spawnblk) == 7, spawnblk);

typedef struct {                /* task_info's record */
    unsigned char id, state, prio, banks, parent;
    char name[8];               /* space padded */
    unsigned char flags;        /* TI_* */
    unsigned char windows;
    unsigned char spare;
} hz_taskinfo;
HZ_STATIC_ASSERT(sizeof(hz_taskinfo) == 16, taskinfo);

typedef struct {                /* a port message: 16 bytes, free form */
    unsigned char b[16];
} hz_msg;
HZ_STATIC_ASSERT(sizeof(hz_msg) == 16, msg);

typedef struct {                /* clip_put / clip_get: {u24 data, u16 length} */
    hz_u24 data;
    unsigned short len;
} hz_clipblk;
HZ_STATIC_ASSERT(sizeof(hz_clipblk) == 5, clipblk);

typedef struct {                /* win_open */
    short x, y;                 /* outer top left */
    unsigned short w, h;        /* content size */
    hz_u24 title;
    unsigned char flags;        /* WF_* */
} hz_winopen;
HZ_STATIC_ASSERT(sizeof(hz_winopen) == 12, winopen);

typedef struct {                /* win_draw (ops 10 and 11 read the stride too) */
    unsigned char op;           /* WD_* */
    unsigned char c1, c2, font;
    short x, y, w, h;
    hz_u24 ptr;
    unsigned short stride;
} hz_windraw;
HZ_STATIC_ASSERT(sizeof(hz_windraw) == 17, windraw);

typedef struct {                /* win_event */
    unsigned char type;         /* WE_* */
    unsigned char win;
    unsigned short a, b, c;
} hz_event;
HZ_STATIC_ASSERT(sizeof(hz_event) == 8, event);

typedef struct {                /* win_info, win_geom */
    short x, y;
    unsigned short w, h;
} hz_rect;
HZ_STATIC_ASSERT(sizeof(hz_rect) == 8, rect);

typedef struct {                /* ws_mouse */
    short sx, sy;               /* on the screen */
    short cx, cy;               /* relative to the window's content */
    unsigned short buttons;
} hz_mouse;
HZ_STATIC_ASSERT(sizeof(hz_mouse) == 10, mouse);

typedef struct {                /* win_popup */
    hz_u24 items;
    short x, y;                 /* x = POP_HERE: at the pointer */
    unsigned char flags;        /* POP_KEY */
} hz_popup;
HZ_STATIC_ASSERT(sizeof(hz_popup) == 8, popup);

typedef struct {                /* sample_play: 16 bytes */
    hz_u24 addr;                /* the first sample (16-bit samples: even) */
    hz_u24 len;                 /* samples (a u24 count) */
    hz_u24 loop;                /* loop start in samples */
    unsigned short pitch;       /* 2.14 step per 48 kHz sample: $4000 = 48 kHz */
    unsigned char voll, volr;
    unsigned char flags;        /* SPF_* */
    unsigned char voice;        /* 0-7, SP_ANY */
    unsigned char zero;
} hz_sample;
HZ_STATIC_ASSERT(sizeof(hz_sample) == 16, sample);

typedef struct {                /* spr_set entry: 10 bytes */
    unsigned char sprite;
    unsigned char ctrl;         /* SPR_* */
    short x, y;
    hz_u24 image;               /* 16-byte aligned */
    unsigned char pal;          /* 4 bpp: the palette bank */
} hz_sprite;
HZ_STATIC_ASSERT(sizeof(hz_sprite) == 10, sprite);

typedef struct {                /* hz_spr_move_many entry: 6 bytes */
    unsigned char sprite;
    unsigned char zero;
    short x, y;
} hz_sprmove;
HZ_STATIC_ASSERT(sizeof(hz_sprmove) == 6, sprmove);

typedef struct {                /* fs_enter: 10 bytes */
    unsigned char mode;         /* FS_640X8, FS_640X4, FS_320X8 */
    unsigned char flags;        /* FS_PTR */
    unsigned short stride;      /* a multiple of 16 */
    unsigned short rows;
    hz_u24 base;                /* 256-byte aligned */
    unsigned char zero;
} hz_fsenter;
HZ_STATIC_ASSERT(sizeof(hz_fsenter) == 10, fsenter);

typedef struct {                /* fs_scroll: 14 bytes */
    unsigned short x, y;        /* the first set */
    unsigned short x2, y2;      /* the second set (from the split line) */
    unsigned short vheight;     /* 0 = no vertical wrap */
    unsigned short split;       /* split line 1-359 */
    unsigned char ctrl;         /* FSC_HWRAP, FSC_SPLIT */
    unsigned char zero;
} hz_fsscroll;
HZ_STATIC_ASSERT(sizeof(hz_fsscroll) == 14, fsscroll);

typedef struct {                /* fs_raster entry: 6 bytes */
    unsigned short line;
    unsigned char index, r, g, b;
} hz_raster;
HZ_STATIC_ASSERT(sizeof(hz_raster) == 6, raster);

typedef struct {                /* draw_list record: 20 bytes */
    unsigned char op;           /* LS_* */
    unsigned char flags;        /* LS_VBL; bits 4-6 expand's first source bit */
    unsigned char c1, c2;
    short x, y;                 /* the destination */
    unsigned short w, h;
    union {
        struct { hz_u24 src; unsigned char pad; } s;   /* copy, keyed copy, expand */
        struct { short sx, sy; } m;                    /* LS_MOVE */
    } u;
    unsigned short stride;      /* 0: the width (expand: the bytes a row needs) */
    unsigned short zero;
} hz_drawrec;
HZ_STATIC_ASSERT(sizeof(hz_drawrec) == 20, drawrec);

typedef struct {                /* sheet_new: 10 bytes */
    hz_u24 addr;
    unsigned char zero;
    unsigned short stride, w, h;
} hz_sheetnew;
HZ_STATIC_ASSERT(sizeof(hz_sheetnew) == 10, sheetnew);

typedef struct {                /* sheet_draw record: 16 bytes */
    unsigned char sheet;        /* 1-32 (a fill: 0) */
    unsigned char op;           /* SH_FILL, SH_COPY, SH_KEY, + SH_VBL */
    unsigned char c;            /* fill colour or key colour */
    unsigned char zero;
    unsigned short sx, sy, w, h;
    short x, y;
} hz_sheetrec;
HZ_STATIC_ASSERT(sizeof(hz_sheetrec) == 16, sheetrec);

typedef struct {                /* the music timer's message (sample_timer) */
    unsigned char ff;           /* $FF */
    unsigned char gen;          /* the generation */
    unsigned short count;       /* periods since the start */
    unsigned char zero[12];
} hz_timermsg;
HZ_STATIC_ASSERT(sizeof(hz_timermsg) == 16, timermsg);

#include "hzsys.h"

/* card (FatFs) errors: HZ_EIO + n */
#define HZ_ENOFILE  (HZ_EIO + 4)        /* no such file */
#define HZ_ENOPATH  (HZ_EIO + 5)        /* no such folder */
#define HZ_EBADNAME (HZ_EIO + 6)        /* invalid name */
#define HZ_EDENIED  (HZ_EIO + 7)        /* denied (read-only, a folder not empty) */
#define HZ_EEXIST   (HZ_EIO + 8)        /* exists */
#define HZ_ENFILE   (HZ_EIO + 18)       /* the 4 file handles (whole system) are in use */
#define HZ_EBADH    (HZ_EIO + 0x80)     /* bad handle */

/* ---- the SDK's helpers (lib/) */

/* the raw gate: any syscall by number, A, X, Y in, A out (hz_x, hz_y, hz_errno set) */
unsigned hz_syscall(unsigned n, unsigned a, unsigned x, unsigned y);

/* the Horizon error code in words ("no such file", ...) */
const char *hz_strerror(unsigned code);
/* errno (errno.h) for a Horizon error code */
int hz_errno_to_errno(unsigned code);

/* the argument string the program was started with (window, bank 0) and its length */
extern unsigned __hz_arglen, __hz_argoff;

/* milliseconds since reset (= hz_uptime) */
#define hz_ms() ((unsigned long)hz_uptime())

/* spawn path with an argument string (0 = none) at a priority (0-3, | SP_DETACH) */
int hz_spawn_path(const char *path, const char *args, unsigned prio);
/* stat path -> 0 and *st filled, or -1 */
int hz_stat_path(const char *path, hz_fileinfo *st);

/* ---- memory in other banks (64 KB each). The large model's pointers reach them as
 * they are; in the tiny model use __far pointers. Objects must not cross a bank. */
void __far *hz_far_alloc(void);             /* a fresh bank (its offset 0), NULL if none */
void hz_far_free(void __far *bank);         /* give it back */
/* copies of n bytes (n <= 65535) between any banks, with MVN (about 7 cycles a byte) */
void hz_far_copy(void __far *dst, const void __far *src, unsigned n);
void hz_far_set(void __far *dst, int c, unsigned n);
/* a far pointer to bank:offset (a function: vbcc would turn a cast integer into a
 * pointer in the data bank) */
void __far *hz_farptr(unsigned bank, unsigned off);
#define HZ_FARPTR(bank, off) hz_farptr((bank), (off))

/* the stack: its lowest address and how many bytes are free below S now */
unsigned hz_stack_free(void);
/* 0 if the stack's guard word is intact, -1 if the stack overflowed */
int hz_stack_check(void);

/* ---- console */
/* read a line from the keyboard with echo and editing (Backspace, Left, Right): at most
 * size - 1 characters, zero-terminated, no newline -> its length; -1 on ctrl-C, -2 on
 * ctrl-D at the start of the line (stdin's end of input) */
int hz_getline(char *buf, unsigned size);
/* a key event (input_read's A, X) as ASCII (US layout; KEY_* for arrows), 0 for none */
unsigned hz_key_ascii(unsigned usage, unsigned mods);

#endif
