/* hz_plat.h - the Atari816 platform of the Prince of Persia port: what the files of
 * horizon/ share. The game's files (src/) see only SDLPoP's own interface (proto.h), which
 * horizon/ implements in place of upstream's seg009.c (the SDL layer). */
#ifndef HZ_PLAT_H
#define HZ_PLAT_H

#include <horizon.h>

/* ---------------------------------------------------------------- the framebuffer
 * 512-byte rows: rows 0-199 the screen the game sees (onscreen_surface_), 200-399 its
 * offscreen buffer, 400-767 the peels (save-unders) and the dialog's copy. The screen
 * shows 172 rows of the room and, below a split, the status line (rows 192-199). */
#define HZ_STRIDE   512
#define HZ_ROWS     768
#define HZ_FBANKS   6               /* 768 x 512 bytes */
#define HZ_ON_Y     0
#define HZ_OFF_Y    200
#define HZ_PEEL_Y   400

#define HZS_IMAGE   0xFFFF          /* SDL_Surface.b: an image of the atlas */
#define HZS_MIRROR  0xFFFE          /* ... its mirrored copy */

extern unsigned char hzv_fb_sheet, hzv_part_sheet[];
extern unsigned hzv_fbbank;         /* the framebuffer's first bank */
extern unsigned hzv_frames;         /* (statistics) */

int hzv_init(void);
void hzv_flush(void);               /* send the blitter's queue */
void hzv_sync(void);                /* ... and wait until it is drawn */
void hzv_show(void);                /* palette and view for the next vertical blank */
void hzv_pal_dirty(unsigned first, unsigned n);
void hzv_xor(const SDL_Surface *img, int x, int y);
extern unsigned char hzv_view_game; /* 1: a room (follow the kid, the status line split) */
extern unsigned char hzv_snap;
extern int hzv_view_y;              /* the framebuffer row at the screen's top */

/* ---------------------------------------------------------------- data (hz_data.c) */
int hzd_init(void);                 /* POP.DAT, POP.GFX, POP.MSK into memory */
#define HZD_PARTS   8                  /* the atlas in parts of hzd_part rows (a sheet each) */
extern unsigned long hzd_part_addr[HZD_PARTS];
extern unsigned hzd_atlas_w, hzd_atlas_h, hzd_part, hzd_nparts;
extern unsigned long hzd_masks;
extern unsigned char __far *hzd_dir; /* POP.DAT */
extern unsigned char hzd_buf[512];  /* a buffer for file reads */

/* ---------------------------------------------------------------- sound (hz_sound.c) */
int hzs_init(void);
void hzs_poll(void);
void hzs_play(int id);
void hzs_stop(void);
int hzs_playing(void);

/* ---------------------------------------------------------------- time and input */
unsigned hzt_frame(void);           /* vertical blanks since the start */
void hzt_wait_frames(unsigned n);
void hz_events(void);               /* SDLPoP's process_events */
extern char hz_prog[128];           /* the program's folder, ending in '/' */
extern unsigned char hz_busy_ms;    /* /BUSY:ms - slower machine for the tests */

/* ---------------------------------------------------------------- tests (hz_ref.c) */
void ref_hook(void);
void ref_print_state(void);
extern unsigned char hz_test_shots; /* SHOTS.TXT: frames to stop at */

/* ---------------------------------------------------------------- upstream seg009's data */
extern dat_type *dat_chain_ptr;
extern word chtab_palette_bits;
extern int wait_time[];
extern int fps;
extern char last_text_input;
extern rgb_type palette[256];
void load_font(void);
image_type *hz_hflip(image_type *image);

#endif
