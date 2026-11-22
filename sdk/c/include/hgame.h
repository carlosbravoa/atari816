/* hgame.h - the game library of the Horizon C SDK (Atari816): a screen, drawing by the
 * blitter, images, hardware and blitter sprites, scrolling tile maps, input, sound.
 *
 *   #include <hgame.h>          hcc links the library by itself when a source includes it
 *
 *   int main(void)
 *   {
 *       int x = 150;
 *       if (hg_screen(HG_320X180, "Demo") < 0)
 *           return 1;
 *       while (hg_frame()) {                    // one frame: 60 a second
 *           if (hg_key(HG_KEY_ESC)) break;
 *           x += (hg_p1() & HG_RIGHT) ? 2 : (hg_p1() & HG_LEFT) ? -2 : 0;
 *           hg_clear(0);
 *           hg_fill(x, 80, 16, 16, 200);
 *           hg_text(8, 8, "Arrows move", 255);
 *       }
 *       return 0;                               // hg_close() runs at exit by itself
 *   }
 *
 * The guide and the reference: sdk/docs/c/games.md. Large model only (hcc's default).
 *
 * Conventions. Every name starts with hg_ (HG_ for constants). Coordinates are pixels,
 * (0, 0) the top left, x right, y down; ints may be negative (the blitter clips). Colours are
 * palette entries 0-255. A function that can fail returns -1 (or NULL) and, like any bad
 * argument, prints "hgame: <function>: <what>" on the console (the first 16 times) instead
 * of crashing.
 *
 * How a frame is drawn. Drawing calls do not draw at once: they add records to the frame's
 * draw list, and hg_end() (inside hg_frame()) hands the whole list to the blitter in one
 * system call, started in the vertical blank, together with the sprites and the scroll
 * registers. Sources (images, text) must stay unchanged until the next frame begins.
 * Pixels and diagonal lines are drawn by the CPU straight into the framebuffer (full screen
 * only); before them the records so far are drawn and waited for.
 */
#ifndef HGAME_H
#define HGAME_H

#include <horizon.h>

#ifdef HZ_TINY
#error "hgame.h: the game library is for the large model (hcc's default)"
#endif

/* ================================================================ the screen */

/* full-screen modes (hg_screen) */
#define HG_320X180   0x02       /* 320 x 180, 256 colours (each pixel 4 x 4 on the monitor) */
#define HG_640X360   0x00       /* 640 x 360, 256 colours */
#define HG_640X360X4 0x01       /* 640 x 360, 16 colours (entries 0-15): x and widths even */
#define HG_DOUBLE    0x100      /* two pages: draw the whole frame unseen, shown at hg_end
                                   (for programs that redraw everything every frame) */
#define HG_POINTER   0x200      /* show the mouse pointer (640 x 360 modes only) */

/* Full screen: a window (shown while the game is paused) and a framebuffer of the program's
 * own memory (banks are taken for it), cleared to colour 0. The palette starts as the system
 * palette. -1 if refused (no window system, memory, another full-screen program). */
int hg_screen(unsigned mode, const char *title);
/* A game in a window on the desktop: w x h content, centred, with that title. Drawing goes
 * into the window; hardware sprites show while it has the focus and is not covered. */
int hg_window(unsigned w, unsigned h, const char *title);
/* the window's menus, as win_menu takes them ("Game\0New\0-\0Quit\0\0\0"): hg_menu() */
int hg_window_menu(const char *menus);
/* Back to the desktop, sprites, sounds, banks and the window freed. Runs at exit by itself. */
void hg_close(void);

extern unsigned hg_w, hg_h;     /* the screen's (or window content's) size in pixels */
extern unsigned hg_win;         /* the window (for hz_ calls) */
extern unsigned hg_fb_bank;     /* full screen: the framebuffer's first bank (row 0 at 0) */
extern unsigned hg_fb_stride, hg_fb_rows;   /* its bytes a row and rows */

/* palette: count entries from first, 3 bytes (red, green, blue) each. In full screen all
 * 256 are the game's; in a window entries 16-255 that no other program holds (they show
 * while the window has the focus). hg_color: one entry. */
void hg_palette(unsigned first, unsigned count, const unsigned char *rgb);
void hg_color(unsigned index, unsigned r, unsigned g, unsigned b);
/* all 256 entries black (count 0 = 256): while a first screen is drawn */
void hg_palette_black(void);
/* raster table (full screen): count changes {line, entry, r, g, b}; 0 = off (hz_fs_raster) */
int hg_raster(unsigned count, const hz_raster *changes);

/* n consecutive 64 KB banks (for a buffer larger than a bank) -> the first, or 0 */
unsigned hg_banks(unsigned n);

/* ================================================================ the frame */

/* End the frame begun before (if any: hg_end) and begin the next one (hg_begin): wait for
 * the vertical blank, read the input. 0 once the player closed the game (Alt+F4, the close
 * box): leave the loop. Lost focus in full screen: the game is paused inside (sound off)
 * until the window has the focus again. */
int hg_frame(void);
void hg_begin(void);
void hg_end(void);
/* logic steps due at hz steps a second (fixed time step, independent of the frame rate;
 * at most 4 after a stall): n = hg_steps(50); while (n--) step(); */
unsigned hg_steps(unsigned hz);
/* ask hg_frame to return 0 */
void hg_quit(void);
/* full screen: pause by itself when the focus goes (default 1) */
void hg_autopause(int on);
/* counters: frames begun, frames missed (more than one vertical blank between two), the CPU
 * time between hg_begin and hg_end in all (milliseconds, from 10 ms clock ticks: an average
 * over many frames is right) */
extern unsigned hg_frames, hg_missed;
extern unsigned hg_pauses;      /* times the game was paused (lost the focus) */
extern unsigned long hg_cpu_ms;
/* "NAME: N frames, M missed, CPU X.XX ms a frame" on the console */
void hg_stats(const char *name);

/* ================================================================ drawing */

/* the visible screen (all pages, all of it), in one colour */
void hg_clear(unsigned c);
void hg_fill(int x, int y, unsigned w, unsigned h, unsigned c);
void hg_rect(int x, int y, unsigned w, unsigned h, unsigned c);    /* an outline */
void hg_hline(int x, int y, unsigned w, unsigned c);
void hg_vline(int x, int y, unsigned h, unsigned c);
/* any line: horizontal and vertical ones by the blitter, others pixel by pixel (CPU in full
 * screen; in a window one record per run of pixels: keep them short) */
void hg_line(int x0, int y0, int x1, int y1, unsigned c);
void hg_pixel(int x, int y, unsigned c);
/* full screen: the pixel's colour (after the frame's records are drawn), 0 outside */
unsigned hg_peek(int x, int y);
/* move a rectangle of the screen (overlap-safe; full screen and windows) */
void hg_move(int sx, int sy, unsigned w, unsigned h, int x, int y);

/* text in the built-in 8 x 10 font (ASCII 32-126; others are blank). hg_text: ink only;
 * hg_text_bg: on paper. hg_textf: printf-style (links the printf code). */
#define HG_FONT_W 8
#define HG_FONT_H 10
#define HG_NONE 0xFFFF          /* "no colour": hg_text_bg paper, an image without a key */
void hg_text(int x, int y, const char *s, unsigned ink);
void hg_text_bg(int x, int y, const char *s, unsigned ink, unsigned paper);
void hg_textf(int x, int y, unsigned ink, const char *fmt, ...);
unsigned hg_text_width(const char *s);         /* 8 x its length */

/* every drawing call's coordinates get (x, y) added (the framebuffer position of the
 * screen's (0, 0); the scrolling map's panel: hg_origin(0, hg_panel_y)) */
void hg_origin(int x, int y);
/* draw the records so far now (and wait: hg_flush(1)) */
void hg_flush(int wait);

/* ================================================================ images */

/* An image: n frames of w x h pixels (8 bpp: a byte each), frames one under the other in
 * far memory (frame k at addr + k * w * h). Made by sdk/tools/img2c.py from a PNG or text
 * art (a C array or an .HGI file), cut into frames (sprite sheets, tile sets) there. */
typedef struct hg_image {
    unsigned w, h;              /* a frame's size */
    unsigned n;                 /* frames */
    unsigned stride;            /* bytes a row (w at 8 bpp, w / 2 at 4 bpp) */
    unsigned long addr;         /* frame 0's first pixel (24-bit, 256-byte aligned) */
    unsigned key;               /* the transparent colour, or HG_NONE (opaque) */
    unsigned char sheet;        /* its sheet (cheaper blits), 0 if none */
    unsigned char bpp;          /* 8 or 4 */
    unsigned palbase, paln;     /* its own colours (from the file), 0 if none */
    unsigned char *pal;         /* paln x 3 bytes */
} hg_image;

/* the pixels of a C array (img2c.py), copied into far memory: n frames of w x h bytes */
hg_image *hg_image_from(const unsigned char *pixels, unsigned w, unsigned h, unsigned n,
                        unsigned key);
/* an .HGI file from the card (img2c.py -o NAME.HGI): frames, key and its palette */
hg_image *hg_image_load(const char *path);
/* a blank image (contents undefined), e.g. a background composed with hg_image_draw */
hg_image *hg_image_new(unsigned w, unsigned h, unsigned n);
void hg_image_free(hg_image *img);
/* its palette (hg_palette(img->palbase, img->paln, img->pal)), if it has one */
void hg_image_palette(const hg_image *img);
/* a pointer to frame k's pixels (rows of img->stride bytes; mind: a pointer's arithmetic
 * stays in its bank, see hg_image_addr) and its 24-bit address */
unsigned char __far *hg_image_pixels(const hg_image *img, unsigned frame);
unsigned long hg_image_addr(const hg_image *img, unsigned frame);

/* blit frame k of img to (x, y): keyed (its key colour skipped) if it has a key */
void hg_draw(const hg_image *img, unsigned frame, int x, int y);
/* a part: (sx, sy) w x h of the whole image (frames one under the other: frame k's top is
 * row k * img->h) */
void hg_draw_part(const hg_image *img, unsigned sx, unsigned sy, unsigned w, unsigned h,
                  int x, int y);
/* the CPU, image to image (composing a background): frame k of src into dst's frame 0 at
 * (x, y), keyed if src has a key; clipped to dst */
void hg_image_draw(hg_image *dst, const hg_image *src, unsigned frame, int x, int y);
void hg_image_fill(hg_image *dst, int x, int y, unsigned w, unsigned h, unsigned c);

/* ================================================================ hardware sprites */

/* Marga's sprites: 16 in all (shared with other programs), drawn over the screen with no
 * CPU time and no blits. Images 16 x 16 or 16 x 32 at 8 bpp (4 bpp: up to 32 x 32), colour 0
 * transparent (img2c.py --key 0), in images from hg_image_* (aligned as Marga needs).
 * Positions in screen pixels. Changes are made at hg_end, all in the same vertical blank.
 * There is no collision report in the hardware: hg_sprite_hit compares boxes. */
#define HG_HFLIP  SPR_HFLIP
#define HG_VFLIP  SPR_VFLIP
#define HG_MAG    SPR_MAG       /* twice as large */
#define HG_BEHIND SPR_BEHIND    /* hidden by bitmap pixels other than colour 0 */
#define HG_HIDE   0x8000        /* hg_sprite_set: set the image, keep it hidden */

/* take count sprites (numbered 0 .. count - 1 here) -> count, or -1 (none free, REV < $0B) */
int hg_sprites(unsigned count);
/* image frame and flags (HG_HFLIP | HG_VFLIP | HG_MAG | HG_BEHIND | HG_HIDE); shows it */
void hg_sprite_set(unsigned n, const hg_image *img, unsigned frame, unsigned flags);
void hg_sprite_pos(unsigned n, int x, int y);
void hg_sprite_show(unsigned n, int on);
/* the boxes of two shown sprites overlap (inset by margin pixels on every side) */
int hg_sprite_hit(unsigned a, unsigned b, unsigned margin);

/* ================================================================ blitter sprites (bobs) */

/* Bobs: images drawn by the blitter over a background image, which puts back what was
 * under them when they move. hg_end draws, in the frame's list: the old places of the bobs
 * that changed (from the background), then every bob shown, in number order (0 below).
 * bg is shown at (x, y) of the screen; a bob outside it is erased with colour 0. */
#define HG_BOBS 32
void hg_bob_background(const hg_image *bg, int x, int y);
void hg_bob(unsigned n, const hg_image *img, unsigned frame, int x, int y);
void hg_bob_hide(unsigned n);
/* draw every shown bob again this frame (after drawing over them) */
void hg_bob_redraw(void);

/* ================================================================ tile maps */

/* A map: mw x mh bytes (row after row), each a frame of the tile set (tiles of tw x th:
 * the image's frame size). Not scrolling: hg_map_draw puts it on the screen (one record a
 * tile), hg_map_image into an image (CPU). */
void hg_map_draw(const unsigned char *map, unsigned mw, unsigned mh, const hg_image *tiles,
                 int x, int y);
void hg_map_image(hg_image *dst, const unsigned char *map, unsigned mw, unsigned mh,
                  const hg_image *tiles);

/* Scrolling (full screen, not HG_DOUBLE; REV $0B): the world is the map, the screen shows
 * hg_w x (hg_h - panel) of it from the camera, Marga scrolls (fine scrolling with wrap) and
 * only the tiles that come into view are drawn. panel > 0: that many rows of a fixed panel
 * at the top, < 0 at the bottom (320 x 180: even), 0 none. The map stays the caller's (the
 * library reads it; change tiles with hg_map_set). Makes the framebuffer anew. */
int hg_map(const unsigned char *map, unsigned mw, unsigned mh, const hg_image *tiles,
           int panel);
/* the camera: the world's pixel at the playfield's top left (kept inside the world) */
void hg_camera(int x, int y);
void hg_map_set(unsigned c, unsigned r, unsigned t);
unsigned hg_map_get(unsigned c, unsigned r);     /* outside: the border tile */
void hg_map_border(unsigned t);                  /* the tile outside the world (0) */
extern int hg_cam_x, hg_cam_y;  /* the camera (after the clamp) */
extern int hg_play_y;           /* the playfield's top on the screen (the panel above it) */
extern int hg_panel_y;          /* the panel's first row in the framebuffer: hg_origin(0,
                                   hg_panel_y) draws into it, (0, 0) its top left */
/* a world position on the screen (for sprites) */
#define hg_screen_x(wx) ((int)(wx) - hg_cam_x)
#define hg_screen_y(wy) ((int)(wy) - hg_cam_y + hg_play_y)

/* ================================================================ input */

/* keys: HID usages. hg_key: held now; hg_key_pressed / _released: since the last frame */
int hg_key(unsigned k);
int hg_key_pressed(unsigned k);
int hg_key_released(unsigned k);
/* the next character typed (ASCII; HG_KEY_ arrows as hz_key_ascii gives them), 0 if none */
unsigned hg_getchar(void);
#define HG_KEY_A      0x04      /* .. HG_KEY_A + 25 = Z */
#define HG_KEY_1      0x1E      /* .. HG_KEY_1 + 8 = 9, then 0 */
#define HG_KEY_0      0x27
#define HG_KEY_ENTER  0x28
#define HG_KEY_ESC    0x29
#define HG_KEY_BKSP   0x2A
#define HG_KEY_TAB    0x2B
#define HG_KEY_SPACE  0x2C
#define HG_KEY_F1     0x3A      /* .. F11 0x44 (F10 opens the menu bar, F12 leaves) */
#define HG_KEY_RIGHT  0x4F
#define HG_KEY_LEFT   0x50
#define HG_KEY_DOWN   0x51
#define HG_KEY_UP     0x52
#define HG_KEY_W      0x1A
#define HG_KEY_S      0x16
#define HG_KEY_D      0x07
#define HG_KEY_P      0x13
/* modifier keys: held now (the bits of the last key event) */
#define HG_MOD_CTRL   1
#define HG_MOD_SHIFT  2
#define HG_MOD_ALT    4
extern unsigned hg_mods;

/* directions and buttons, the joystick's layout */
#define HG_UP     1
#define HG_DOWN   2
#define HG_LEFT   4
#define HG_RIGHT  8
#define HG_FIRE   16
/* joystick port 1 or 2: HG_UP .. HG_FIRE (read once a frame) */
unsigned hg_joy(unsigned port);
/* player 1: arrows, W A S D and joystick 1; fire: Space, Enter, the trigger.
 * hg_p1_pressed: the bits that came on since the last frame */
unsigned hg_p1(void);
unsigned hg_p1_pressed(void);

/* the mouse, in screen pixels (in a window: its content; 320 x 180: halved) */
extern int hg_mouse_x, hg_mouse_y;
extern unsigned hg_mouse_b;     /* buttons held: 1 left, 2 right, 4 middle */
unsigned hg_mouse_clicked(void);   /* buttons pressed since the last frame */
/* the menu item picked since the last frame: menu << 8 | item, or -1 */
int hg_menu(void);

/* ================================================================ sound */

/* POKEY (four square / noise voices, every board): a tone on voice 0-3 (POKEY channel
 * v + 1; 0 is also the system's beep), pitch = AUDF (higher = lower note; hg_pitch(hz)),
 * volume 0-15, for ticks of 20 ms. hg_sfx: with an envelope: each tick the pitch moves by
 * dpitch and the volume falls by dvol; dist: HG_TONE, HG_NOISE, HG_BUZZ. */
#define HG_TONE  0xA0
#define HG_NOISE 0x80
#define HG_BUZZ  0xC0
void hg_tone(unsigned v, unsigned pitch, unsigned vol, unsigned ticks);
void hg_sfx(unsigned v, unsigned pitch, int dpitch, unsigned vol, unsigned dvol,
            unsigned ticks, unsigned dist);
unsigned hg_pitch(unsigned hz);         /* AUDF for a frequency (125-15980 Hz) */
void hg_sound_off(void);                /* every POKEY voice and every sample off */

/* Lau, the sample player (REV $0A and later): 8 voices of signed 8- or 16-bit samples
 * from memory, any rate. hg_has_lau(): 0 on older boards (the calls then do nothing). */
typedef struct hg_sound {
    unsigned long addr;         /* the first sample (24-bit) */
    unsigned long len;          /* samples */
    unsigned rate;              /* samples a second */
    unsigned char bits;         /* 8 or 16 */
    unsigned char loop;         /* 1: plays again and again (hg_stop ends it) */
} hg_sound;
int hg_has_lau(void);
/* signed samples in memory (a C array, any bank: not copied, keep it) */
hg_sound *hg_sound_from(const void *data, unsigned long len, unsigned rate, unsigned bits);
/* a .WAV file (PCM, 8 or 16 bits, mono) or raw signed 8-bit at 16 kHz (any other name) */
hg_sound *hg_sound_load(const char *path);
/* made here: HG_SQUARE, HG_SINE, HG_TRIANGLE, HG_SAW, HG_NOISE_WAVE at hz for ms
 * milliseconds, fading out over the last fade per cent (16 kHz, 8 bits) */
#define HG_SQUARE     0
#define HG_SINE       1
#define HG_TRIANGLE   2
#define HG_SAW        3
#define HG_NOISE_WAVE 4
hg_sound *hg_sound_make(unsigned wave, unsigned hz, unsigned ms, unsigned fade);
void hg_sound_free(hg_sound *s);
/* play on a free voice: volume 0-255 -> the voice, or -1. hg_play_ex: pan -128 (left) ..
 * 127, semitones up (+) or down (-) from the sound's own pitch */
int hg_play(const hg_sound *s, unsigned vol);
int hg_play_ex(const hg_sound *s, unsigned vol, int pan, int semitones);
void hg_stop(int voice);                /* -1: all of the game's voices */

/* Music by Horizon's music engine (/SYSTEM/MUSICD.PRG, started for you): a MOD module, a
 * WAV file or (REV $0C, on the OPL2) a MIDI file, from the card. It plays on Lau's highest
 * voices (a 4-channel module leaves 0-3 to hg_play). */
int hg_music_play(const char *path, int loop);
void hg_music_stop(void);
void hg_music_pause(int on);
void hg_music_volume(unsigned v);       /* 0-64 */
/* HG_MUSIC_*: what the engine said last */
#define HG_MUSIC_NONE    0
#define HG_MUSIC_LOADING 1
#define HG_MUSIC_STOPPED 2
#define HG_MUSIC_PLAYING 3
#define HG_MUSIC_PAUSED  4
#define HG_MUSIC_ENDED   5
#define HG_MUSIC_ERROR   6
int hg_music_state(void);

/* ================================================================ helpers */

/* fixed point. 8.8 in an int (-128.0 .. 127.99), 16.16 in a long (-32768.0 .. 32767.99) */
typedef int hg_fix8;
typedef long hg_fix16;
#define HG_FIX8(n)      ((hg_fix8)((n) * 256))
#define HG_FIX8_INT(f)  ((f) >> 8)
#define HG_FIX8_MUL(a, b) ((hg_fix8)(((long)(a) * (b)) >> 8))
#define HG_FIX8_DIV(a, b) ((hg_fix8)(((long)(a) << 8) / (b)))
#define HG_FIX16(n)     ((hg_fix16)(n) << 16)
#define HG_FIX16_INT(f) ((int)((f) >> 16))
hg_fix16 hg_fix16_mul(hg_fix16 a, hg_fix16 b);
hg_fix16 hg_fix16_div(hg_fix16 a, hg_fix16 b);

/* random numbers (xorshift, 16 bits): hg_rand 0-65535, hg_rand_n 0 .. n - 1 */
unsigned hg_rand(void);
unsigned hg_rand_n(unsigned n);
void hg_srand(unsigned seed);           /* (seeded from the clock at hg_screen/hg_window) */

/* sine and cosine of an angle in 256ths of a turn, in 8.8 (-256 .. 256) */
hg_fix8 hg_sin(unsigned angle);
hg_fix8 hg_cos(unsigned angle);
/* the angle (0-255) of the vector (dx, dy) */
unsigned hg_atan2(int dy, int dx);

/* two rectangles overlap */
int hg_overlap(int x1, int y1, unsigned w1, unsigned h1, int x2, int y2, unsigned w2,
               unsigned h2);
/* milliseconds since the machine started (10 ms steps) */
unsigned long hg_ms(void);

#define HG_MIN(a, b) ((a) < (b) ? (a) : (b))
#define HG_MAX(a, b) ((a) > (b) ? (a) : (b))
#define HG_ABS(a) ((a) < 0 ? -(a) : (a))
#define HG_CLAMP(v, lo, hi) ((v) < (lo) ? (lo) : (v) > (hi) ? (hi) : (v))

#endif
