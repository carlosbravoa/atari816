/* hg_int.h - hgame's internals, shared by the library's files (not for games). */
#ifndef HG_INT_H
#define HG_INT_H

#include <hgame.h>

/* what the screen is */
#define HG__NONE   0
#define HG__WINDOW 1
#define HG__FULL   2
extern unsigned char hg__kind;
extern unsigned char hg__mode;          /* FS_* in full screen */
extern unsigned char hg__double;        /* HG_DOUBLE: two pages */
extern unsigned char hg__page;          /* the page being drawn (0 or 1) */
extern unsigned hg__pagey;              /* its first row: 0 or hg_h */
extern int hg__ox, hg__oy;              /* hg_origin */
extern unsigned char hg__scroll;        /* hg_map's scrolling ring in use */
extern unsigned char hg__began;         /* inside a frame (between hg_begin and hg_end) */

/* errors: "hgame: fn: msg" on the console, the first 16 times */
void hg__fail(const char *fn, const char *msg);

/* the frame's draw records, in order: draw_list records (hg__dq) and sheet records
 * (hg__sq) at the same indexes; runs of one kind (hg__runs: first index | 0x8000 for a
 * sheet run) are sent with one call each */
#define HG__Q 128
extern hz_drawrec hg__dq[HG__Q];
extern hz_sheetrec hg__sq[HG__Q];
extern unsigned hg__runs[HG__Q], hg__nruns, hg__runkind;
extern unsigned hg__qn;
/* a new record (in screen coordinates: the origin and the page are added here) -> NULL if
 * it is wholly outside the target */
hz_drawrec *hg__rec(unsigned op, int x, int y, unsigned w, unsigned h);   /* hg_fast.s */
extern int hg__cutx, hg__cuty;          /* what hg__rec cut at the left and the top */
extern unsigned long hg__qpix;          /* the pixels of the records queued (a bound) */
/* the clip rectangle and offset of hg__rec, after the screen, page or origin changed */
void hg__clip_update(void);
/* hg_draw's C part (no sheet, 16 colours, bad arguments) */
void hg__draw_c(const hg_image *img, unsigned frame, int x, int y);
void hg__draw_part_c(const hg_image *img, unsigned sx, unsigned sy, unsigned w, unsigned h,
                     int x, int y);
extern unsigned long hg__sheet_addr[33];
extern unsigned hg__sheet_stride[33];
/* send the records (vbl: start them in the vertical blank) */
void hg__submit(int vbl);
/* the records so far drawn and done, before the CPU touches the framebuffer */
void hg__cpu_sync(void);
extern unsigned char hg__listrun;       /* a list of ours may be running */
extern unsigned char hg__vblsent;       /* the frame's first records went (with LS_VBL) */
/* bytes for a frame's sources (text): valid until the next frame begins */
void *hg__arena(unsigned n);
void hg__arena_reset(void);

/* the framebuffer: the address of (x, y) in it (framebuffer coordinates) */
unsigned long hg__fbaddr(unsigned x, unsigned y);
extern unsigned long hg__fbbase;

/* far memory: n bytes, 256-byte aligned (whole banks for n > 65280) -> address, or 0 */
unsigned long hg__farmem(unsigned long n);
void hg__farmem_reset(void);
/* (a far pointer: with cc816 a plain pointer reaches only the code bank) */
#define HG__PTR(a) ((unsigned char __far *)(a))

/* a * b in 32 bits (hg_fast.s: cheaper than the runtime's long multiply) */
unsigned long hg__umul(unsigned a, unsigned b);

/* the built-in font */
extern const unsigned char hg__font[95 * 10];

/* the frame's parts the other files hook into hg_end / hg_begin / hg_close */
void hg__sprites_end(void);
void hg__sprites_close(void);
void hg__bobs_end(void);
void hg__scroll_end(void);
void hg__sound_tick(void);
void hg__sound_close(void);
void hg__images_close(void);
void hg__map_close(void);
/* (the frame calls them through pointers set when the part is first used, so a game that
 * does not use a part does not link it) */
extern void (*hg__hook_sprites)(void);
extern void (*hg__hook_bobs)(void);
extern void (*hg__hook_bobs_begin)(void);
extern unsigned hg__flushes;          /* calls of hg__submit that sent records */
extern void (*hg__hook_scroll)(void);
extern void (*hg__hook_sound)(void);
extern void (*hg__hook_close_sprites)(void);
extern void (*hg__hook_close_sound)(void);
extern void (*hg__hook_close_images)(void);
extern void (*hg__hook_close_map)(void);
extern void (*hg__hook_pause)(int on);

/* full screen: (re)enter with a framebuffer of stride x rows (bytes), first bank fbb */
int hg__fs_enter(unsigned stride, unsigned rows, unsigned fbb);
/* the scroll registers to send at hg_end (hg_map's, or the page of HG_DOUBLE) */
extern hz_fsscroll hg__scr;
extern unsigned char hg__scr_dirty;

/* (conio.c) the events now, without a frame -> 1 once the window was closed */
int hg__poll(void);
unsigned hg__chars(void);

/* the event loop's pause (full screen, focus lost) */
void hg__pause(void);

#endif
