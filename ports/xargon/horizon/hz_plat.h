/* hz_plat.h - Xargon's platform layer for Horizon (the Atari816): what its files share.
 *
 * The screen. Upstream draws a 320 x 200 picture of 256 colours (VGA mode X, two pages
 * flipped): the playfield (gamevp, screen rows 2-159) and the status bar (rows 160-199).
 * Here one framebuffer (hgame's full screen, 320 x 180, entered again with this buffer)
 * of 512-byte rows holds both pages, one under the other, HZ_PAGE rows each:
 *
 *   rows 0-399 of a page   the playfield's rows: screen (X, Y) for Y < 160 is row oy + Y,
 *                          byte (ox + X) & 511 (Marga's horizontal wrap: a row is a ring).
 *                          Scrolling the playfield (upstream's scrollvp of the whole gamevp,
 *                          a copy of 50 KB on the VGA) moves the page's origin (ox, oy)
 *                          instead; when oy would leave the page, the rows shown move back
 *                          to its middle (one move by the blitter, every 120 rows or more)
 *   rows 400-439           screen rows 160-199 (the status bar), as they are
 *
 * The monitor shows 180 rows: while playing, screen rows 11-150 (140 of the playfield's
 * 158: 9 rows out of sight at the top and at the bottom; the game keeps the hero between
 * rows 32 and 120 of it, and its windows lie inside rows 16-144) and, from the split, the
 * 40 rows of the status bar; full-screen pictures (the title, the story: gamevp as big as
 * the screen) show rows 0-179.
 * Page flipping is the scroll registers' choice of rows. The drawing (hz_vga.c) is done by
 * the blitter from the shapes' atlas (hz_shm.c), the fonts by the CPU (hz_blit.s). */
#ifndef HZ_PLAT_H
#define HZ_PLAT_H

#define HZ_STRIDE   512
#define HZ_PAGEH    400         /* a page's playfield rows */
#define HZ_PANEL    400         /* a page's status bar: its first row in the page */
#define HZ_PAGE     440         /* a page's rows */
#define HZ_ROWS     880
#define HZ_FBANKS   7           /* the framebuffer's banks (128 rows each) */
#define HZ_OYMID    120         /* oy after a move back */
#define HZ_GAMEVP_Y 2           /* gamevp: screen rows 2-159 */
#define HZ_GAMEVP_H 158
#define HZ_VIEW_Y   11          /* the screen rows shown while playing: 11-150 */
#define HZ_VIEW_H   140

/* hz_blit.s: rectangles in the framebuffer (hzb_bank: its first bank) by the CPU */
extern unsigned hzb_bank;
void hzb_map(const unsigned char __far *src, unsigned sstride, unsigned w, unsigned h,
             unsigned row, unsigned x);       /* through hzb_maptab */
void hzb_fill(unsigned w, unsigned h, unsigned row, unsigned x, unsigned colour);
extern unsigned char hzb_maptab[256];   /* hzb_map's table: 255 = transparent */

/* hz_vga.c */
extern unsigned hzv_fbbank;             /* the framebuffer's first bank */
extern int hzv_ox[2], hzv_oy[2];        /* each page's origin */
void hzv_flush(void);                   /* the blitter's queue sent */
extern unsigned hzv_flip_frame;         /* a page flip sent at this frame ... */
extern unsigned char hzv_flip_wait;     /* ... whose blank has not been seen yet */
void hzv_sync(void);                    /* ... and drawn (before the CPU draws) */
extern unsigned char hzv_show;          /* the page shown (the CRTC's start address) */
extern unsigned char hzv_shown;         /* the page given to Marga (hzv_display) */
int hzv_init(void);                     /* the framebuffers, full screen: 0 or -1 */
void hzv_display(void);                 /* after each vertical blank: page, scroll, palette */
void hzv_dac_index(unsigned char i);    /* VGA DAC writes (outportb 3C8 / 3C9) */
void hzv_dac_data(unsigned char v);
void hzv_crtc(unsigned char reg, unsigned char v);  /* CRTC writes (outport 3D4) */

/* hz_frame.c: the vertical blank, the clock, input */
void hzf_pump(void);                    /* one frame: hgame's, then the display, the keys */
int *hzc_tick(void);                    /* upstream's myclock: BIOS ticks (18.2 a second) */
extern unsigned hzf_frames;             /* vertical blanks since the start */
unsigned char hzf_retrace(void);        /* inportb(0x3DA): 8 in the vertical retrace */
void hzf_flipped(void);                 /* a page flip (a game frame drawn) */
void hzf_report(void);                  /* the frame statistics on the console */
extern unsigned char hzf_stats;         /* /STATS: every 10 s too */
extern unsigned hzf_busy;               /* /BUSY:ms: that long more each game frame */
unsigned char hzf_gameport(void);       /* inportb(0x201) */
void hzf_gameport_fire(void);           /* outportb(0x201, x): the one-shots start */
int hzk_pressed(void);                  /* the BIOS keyboard (hz_kbd.c) */
int hzk_read(void);
void hzk_frame(void);                   /* after each frame: keys into the BIOS queue */
void hzs_frame(void);                   /* hz_snd.c: after each frame */

/* hz_shm.c: the shapes' atlas */
unsigned long hzshm_atlas(void);        /* its rows 0-1023 (512 bytes a row) */
unsigned long hzshm_atlas_b(void);      /* rows 1024- */
unsigned long hzshm_row(unsigned r);    /* row r's address */
extern unsigned hzshm_rows;
extern unsigned char hzshm_ok[];        /* table loaded and wanted */
extern unsigned hzshm_first[], hzshm_count[], hzshm_row0[];  /* its shapes, first row */
extern const unsigned char __far *hzshm_dir;    /* the shapes: {u16 x, y, u8 w, h, u16 0} */
const unsigned char __far *hzshm_shape(int nt, int ns);  /* {x, y, w, h} or NULL */

/* hz_snd.c: the music's and effects' data */
int hzs_init(const char *dir);

/* hz_main.c */
extern char hz_dir[128];                /* the program's folder (the data files') */
void hz_fatal(const char *msg);

#endif
