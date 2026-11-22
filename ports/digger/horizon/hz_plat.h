/* hz_plat.h - Digger's platform layer for Horizon (the Atari816): what its files share.
 *
 * The screen: hgame's full screen at 640 x 360, 16 colours (HG_640X360X4), with a
 * framebuffer of 512 rows of 512 bytes (hg_screen_fb): upstream's VGA picture, 640 x 400,
 * drawn by the CPU as upstream's DOS VGA code drew it, at 4 bits a pixel, into a buffer of
 * the same shape; the rectangles drawn are copied to the shown one after each vertical
 * blank (hzv_show), so no half-drawn sprite is ever seen. Row r is in bank
 * hzb_fbbank + r / 128 at offset (r % 128) * 512: a row never crosses a bank. A game
 * coordinate (x, y) of upstream's 320 x 200 is byte x of rows 2y and 2y + 1.
 * The screen shows 360 of the 400 rows: rows 0-27 (the score line) always, above a split;
 * below it 332 of rows 28-399, following the digger (hz_timer.c, the camera). */
#ifndef HZ_PLAT_H
#define HZ_PLAT_H

#include <stdint.h>
#include <stdbool.h>

#define HZ_FB_STRIDE 512
#define HZ_FB_ROWS   512        /* 4 banks; 400 are the picture, the rest catches overruns */
#define HZ_PANEL     28         /* the score line's rows (upstream y 0-13) */
#define HZ_PIC_ROWS  400
#define HZ_VIEW_MAX  (HZ_PIC_ROWS - 360)    /* how far the playfield's view moves: 40 */

/* hz_blit.s: x is the byte in the row (upstream's x), row the framebuffer row,
 * bw bytes a row (even), rows rows */
extern unsigned hzb_fbbank;             /* the buffer the game draws into and reads */
extern unsigned hzb_showbank;           /* the framebuffer shown */
void hzb_show(unsigned x, unsigned row, unsigned bw, unsigned rows);   /* fb -> shown */
void hzb_put(unsigned x, unsigned row, const uint8_t __far *buf, unsigned bw,
             unsigned rows);
void hzb_get(unsigned x, unsigned row, uint8_t __far *buf, unsigned bw, unsigned rows);
void hzb_putm(unsigned x, unsigned row, unsigned long src, unsigned bw, unsigned rows);
void hzb_copy(unsigned x, unsigned row, unsigned long src, unsigned bw, unsigned rows);
void hzb_fill(unsigned x, unsigned row, unsigned bw, unsigned rows, unsigned word);

/* hz_vid.c */
void hzv_show(void);                    /* what was drawn since, to the screen */

/* hz_data.c: DIGGER.DAT in far memory */
int hzd_load(void);                     /* 0, or -1 (a message printed) */
unsigned long hzd_sprite(unsigned ch, unsigned *bytes);  /* S's address (M follows), 0 */
unsigned long hzd_char(unsigned ch, unsigned colour);    /* a character's 12 x 24, or 0 */
unsigned long hzd_title(unsigned half);                   /* 200 rows of 320 bytes */

/* hz_timer.c */
void hzt_pump(void);                    /* the sound's steps due, a vertical blank's work */
void hzt_work(unsigned bytes);          /* (drawing calls) their work: the clock looked at */
void hzt_camera(void);                  /* the view, one step */
extern bool hzt_fast;                   /* /S:0: no waiting */
struct hzt_stats {
    unsigned long frames, late, busy_us, busy_max;      /* game frames, CPU a frame */
    unsigned long beat_n, beat_us, beat_max, beat_far;  /* frame starts off the 80 ms beat */
    unsigned long snd_n, snd_late_us, snd_late_max;     /* sound steps, their delay */
    unsigned long view_need, view_moves;                /* blanks the view was off / moved */
    unsigned long key_n, key_frame_us, key_show_us, key_show_max;   /* key to frame, screen */
};
extern struct hzt_stats hzt_st;

/* hz_kbd.c */
void hzk_poll(void);                    /* after each hgame frame: the keys pressed */

/* hz_main.c */
extern char hz_progdir[128];

#endif
