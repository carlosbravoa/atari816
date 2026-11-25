/* horizon.h - Horizon (Atari816) for C programs: the parameter blocks, every syscall as a
 * C function (hzsys.h, generated from horizon.inc and ABI.md), and the SDK's helpers.
 *
 *   #include <horizon.h>
 *
 * Pointers. A data pointer is 16 bits: an offset in the program's code bank (the main
 * bank), where its globals, strings, locals and malloc's heap all are. Memory in other
 * banks (hz_far_alloc, __far objects) needs __far pointers (32 bits). A syscall takes a
 * pointer as X = offset, Y = bank: the stubs do that (the code bank for a near pointer).
 * With far data (hcc --data far) every plain data pointer is a far one, and every
 * function here takes it as it is: any bank the program owns.
 *
 * Errors. Every hz_ function sets hz_errno: 0 when the call worked, else Horizon's error
 * code (HZ_EINVAL, HZ_ENOMEM, ..., HZ_EIO + n for the card: HZ_ENOFILE ...). It returns -1
 * (or $FFFF for unsigned results) on an error. The C library (stdio.h, ...) sets errno
 * (errno.h) instead; hz_strerror() says a Horizon code in words.
 *
 * The blocks below have the exact byte layout of ABI.md (cc816 packs structures: no
 * padding); each has a compile-time size check.
 */
#ifndef HORIZON_H
#define HORIZON_H

#ifndef __SIZE_T
#define __SIZE_T 1
typedef unsigned int size_t;
#endif

/* ---- basics */

/* a compile-time check: HZ_STATIC_ASSERT(sizeof(hz_io) == 6, io) */
#define HZ_STATIC_ASSERT(cond, name) typedef char hz_assert_##name[(cond) ? 1 : -1]

/* the offset and the bank of a data pointer (near or far) */
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
    unsigned char op;           /* SH_FILL, SH_COPY, SH_KEY, SH_TABLE, + SH_REMAP, SH_VBL */
    unsigned char c;            /* fill colour or key colour */
    unsigned char zero;
    unsigned short sx, sy, w, h;
    short x, y;
} hz_sheetrec;
HZ_STATIC_ASSERT(sizeof(hz_sheetrec) == 16, sheetrec);

typedef struct {                /* (0.30) fill_runs' block: 10 bytes */
    hz_u24 page;                /* offset 0 of the page (own memory) */
    unsigned char flags;        /* 0, or FR_GROUPS: runs points at hz_rungroup records */
    unsigned short size;        /* its bytes (0: 65,536): every run ends inside it */
    hz_u24 runs;                /* the first run */
    unsigned char zero;
} hz_fillruns;
HZ_STATIC_ASSERT(sizeof(hz_fillruns) == 10, fillruns);

typedef struct {                /* (0.30) a fill_runs run: 4 bytes */
    unsigned short ofs;         /* its first byte: page + ofs */
    unsigned char c;            /* the colour */
    unsigned char w;            /* the width, 0-255 */
} hz_run;
HZ_STATIC_ASSERT(sizeof(hz_run) == 4, run);

typedef struct {                /* (0.30) a fill_runs group (FR_GROUPS): 8 bytes */
    hz_u24 elems;               /* its elements: below offset $FF00 of their bank */
    unsigned char c;            /* the colour of all its runs */
    unsigned short n;           /* elements, 0-1024 */
    unsigned char stride;       /* bytes from one element to the next, 1-255 */
    unsigned char fields;       /* bits 0-3: an element's u16 offset's place, 4-7: its width's */
} hz_rungroup;
HZ_STATIC_ASSERT(sizeof(hz_rungroup) == 8, rungroup);

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
/* (Horizon 0.28) the folder of the program's own file, ending in '/' ("/GAMES/MINE/"), into
 * buf -> its length, or -1 (hz_errno: HZ_EINVAL buf too small, HZ_ENOSYS Horizon before
 * 0.28). 128 bytes always fit. For data files next to the program: strcat(buf, "LEVELS.DAT").
 * hz_task_path gives the whole path */
int hz_prog_dir(char *buf, unsigned size);

/* ---- memory in other banks (64 KB each), through __far pointers. Objects must not
 * cross a bank. */
void __far *hz_far_alloc(void);             /* a fresh bank (its offset 0), NULL if none */
void hz_far_free(void __far *bank);         /* give it back */
/* copies of n bytes (n <= 65535) between any banks, with MVN (about 12 cycles a byte) */
void hz_far_copy(void __far *dst, const void __far *src, unsigned n);
void hz_far_set(void __far *dst, int c, unsigned n);
/* a far pointer to bank:offset */
void __far *hz_farptr(unsigned bank, unsigned off);
#define HZ_FARPTR(bank, off) hz_farptr((bank), (off))

/* the stack: how many bytes are free below S now */
unsigned hz_stack_free(void);
/* 0 if both stacks' guard zones are intact, -1 if a stack overflowed */
int hz_stack_check(void);
/* the software stack (arrays, structures, locals whose address is taken): how many
 * bytes are free below its pointer now */
unsigned hz_sstack_free(void);
/* the heap (malloc: the main bank from the end of bss to the software stack): its free
 * bytes now, the biggest block malloc can give now, and the most bytes in use at once
 * since the program started (block headers counted). hcc --debug prints the heap's use
 * at exit, with the stacks' */
#ifdef __CC816_FAR_DATA__
/* (the far data model, hcc --data far: the heap is the main bank's room, then banks of
 * 64 KB taken from Horizon as needed: the counts are long; largest counts a bank Horizon
 * still has free) */
unsigned long hz_heap_free(void);
unsigned hz_heap_largest(void);
unsigned long hz_heap_peak(void);
#else
unsigned hz_heap_free(void);
unsigned hz_heap_largest(void);
unsigned hz_heap_peak(void);
#endif

/* ---- console */
/* read a line from the keyboard with echo and editing (Backspace, Left, Right): at most
 * size - 1 characters, zero-terminated, no newline -> its length; -1 on ctrl-C, -2 on
 * ctrl-D at the start of the line (stdin's end of input). A line longer than the room
 * right of the prompt scrolls sideways (it never wraps); the prompt's end is the column
 * stdout and stderr counted (a prompt sent with hz_puts directly is not counted). stdin
 * reads lines of up to 255 characters */
int hz_getline(char *buf, unsigned size);
/* a key event (input_read's A, X) as ASCII (US layout; KEY_* for arrows), 0 for none */
unsigned hz_key_ascii(unsigned usage, unsigned mods);

#endif
