# hgame: games in C (`hgame.h`)

Purpose: write a game in C on hgame, the SDK's game library: screen, frame loop, drawing,
images, sprites, maps, input, sound, files. The header `SDK/c/include/hgame.h` is the
authority (every function has its comment); the long guide is `SDK/docs/c/games.md`.

## Start here

| Start from | What it shows |
| --- | --- |
| `SDK/templates/c-game` (Gem Run, `GEMRUNC.PRG`) | a game **in a window**: background image, bobs, `hg_steps(50)`, menu, mouse, POKEY effects, `make test` |
| `SDK/c/examples/tutorial` (`step1.c` .. `step5.c`) | full screen in five steps: box, image, sound, scrolling map + sprites, title/play/game over |
| `SDK/c/examples/glimmer` | a finished full-screen scrolling game (map, 16 sprites, panel, music) |
| `SDK/c/examples/catch` | a game on `conio.h` only (cc65-style text console) |
| `SDK/c/game/tests/gt_*.c` | one test per area; what they test works (`make -C SDK/c/game test`) |

`#include <hgame.h>` is enough: hcc links the library by itself (also for `conio.h`,
`joystick.h`; `hcc --game` forces it). Both code models. Language rules: references/c-language.md;
the C library: references/c-library.md.

## A minimal game loop (built and run)

`main.c` (with `art/ship.txt` made into `art/ship.h`, and `ROCK.HGI` on the card next to the
program). Run in the emulator: 211 frames, 1 missed, 3.45 ms CPU a frame; the screenshot
showed the ship, six rocks and the score line.

```c
#include <stdio.h>
#include <string.h>
#include <hgame.h>
#include "art/ship.h"                   /* img2c.py art/ship.txt -o art/ship.h --key 0 */

#define NR 6
static int rx[NR], ry[NR];

int main(void)
{
    hg_image *shipimg, *rock;
    hg_sound *boom;
    char path[128];
    int x = 152, i, score = 0, hits = 0;
    unsigned j;

    if (hg_screen(HG_320X180 | HG_DOUBLE, "Dodge") < 0)    /* full screen, two pages */
        return 1;
    shipimg = hg_image_from(ship, SHIP_W, SHIP_H, SHIP_N, SHIP_KEY);
    if (hz_prog_dir(path, sizeof path) < 0)                 /* the program's own folder */
        path[0] = 0;
    strcat(path, "ROCK.HGI");
    rock = hg_image_load(path);                             /* NULL + "hgame: ..." if missing */
    if (!shipimg || !rock)
        return 1;
    boom = hg_sound_make(HG_NOISE_WAVE, 200, 200, 80);      /* a Lau sample, made here */
    for (i = 0; i < NR; i++) {
        rx[i] = (int)hg_rand_n(308);
        ry[i] = -(int)hg_rand_n(180);
    }
    while (hg_frame()) {                                    /* 60 a second; 0: closed */
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        j = hg_p1();                                        /* arrows, W A S D, joystick 1 */
        if (j & HG_LEFT)  x -= 3;
        if (j & HG_RIGHT) x += 3;
        x = HG_CLAMP(x, 0, 304);
        hg_clear(0);                                        /* HG_DOUBLE: redraw everything */
        for (i = 0; i < NR; i++) {
            ry[i] += 2;
            if (ry[i] > 180) {                              /* off the bottom: dodged */
                ry[i] = -12;
                rx[i] = (int)hg_rand_n(308);
                ++score;
            }
            if (hg_overlap(x + 2, 160, 12, 14, rx[i], ry[i], 12, 12)) {
                ry[i] = -12;
                ++hits;
                if (boom == 0 || hg_play(boom, 200) < 0)    /* no Lau: a POKEY effect */
                    hg_sfx(0, 40, 3, 12, 1, 11, HG_NOISE);
                printf("DODGE: hit %d\n", hits);
            }
            hg_draw(rock, 0, rx[i], ry[i]);
        }
        hg_draw(shipimg, 0, x, 160);
        hg_textf(4, 4, 1, "Score %d  hits %d", score, hits);
    }
    hg_stats("DODGE");                                      /* frames, missed, CPU a frame */
    return 0;                                               /* hg_close() runs at exit */
}
```

Makefile (the rules come from `SDK/c/c.mk`; `$(PYTHON)` is defined there):

```make
NAME     := dodge
# SDK: the sdk folder, relative to this one
SDK      ?= ../../sdk
RUNMODE  := desktop
SRCS     := main.c
RUNFLAGS := --file ROCK.HGI:/APPS/ROCK.HGI
include $(SDK)/c/c.mk

$(PRG): art/ship.h ROCK.HGI
art/ship.h: art/ship.txt
	$(PYTHON) $(SDK)/tools/img2c.py $< -o $@ --name ship --key 0
ROCK.HGI: art/rock.txt
	$(PYTHON) $(SDK)/tools/img2c.py $< -o $@ --key 0
```

`make && make test` with a `test.script` (`1000 shot`, `+0 key left 2000`, `+2100 shot`,
`+500 {esc}`). run816 puts the program at `/APPS/DODGE.PRG`, so `hz_prog_dir` gives `/APPS/`.

## Screen modes

| Call | Screen |
| --- | --- |
| `hg_screen(HG_320X180, title)` | full screen 320 x 180, 256 colours, each pixel 4 x 4 on the monitor |
| `hg_screen(HG_640X360, title)` | full screen 640 x 360, 256 colours |
| `hg_screen(HG_640X360X4, title)` | 640 x 360, 16 colours (0-15); x and widths even; images only from `.HGI` (`img2c.py --bpp 4`); text and pixels drawn by the CPU |
| `| HG_DOUBLE` | two pages: the frame is drawn unseen, shown at `hg_end`. Needed when you `hg_clear` and redraw everything each frame. Not with `hg_map` or `hg_screen_fb` |
| `| HG_POINTER` | show the mouse pointer (640 x 360 modes only) |
| `hg_screen_fb(mode, title, stride, rows)` | a framebuffer of another shape: `stride` a multiple of 16 (0 = the line's; 512 or 1024 keeps rows inside one bank), `rows` up to 1024 (a 320 x 200 game at 320 x 180). Not with `HG_DOUBLE` |
| `hg_window(w, h, title)` | a game in a centred desktop window; `hg_window_menu("Game\0New\0-\0Quit\0\0\0")`, picks via `hg_menu()` (menu << 8 \| item, or -1) |

All return -1 when refused (no window system, no memory, another full-screen program).
Full screen shows the game's own framebuffer (banks taken for it, cleared to 0) and a small
window shown while paused. `hg_w`, `hg_h` are the size; `hg_win` the window (for `hz_` calls);
`hg_fb_bank`, `hg_fb_stride`, `hg_fb_rows` the framebuffer. `hg_close()` runs at exit.

Palette: `hg_palette(first, count, rgb)` (3 bytes each), `hg_color(i, r, g, b)`,
`hg_palette_black()`. Full screen: all 256 entries are the game's (start: the system
palette; its cube is `16 + 36 r + 6 g + b`, r g b 0-5; 1 white). In a window: entries 16-255
that no other program holds, shown only while the window has the focus.
`hg_raster(count, changes)`: up to 16 palette changes at screen lines (`hz_raster` records).

## The frame

```
while (hg_frame()) { input; logic; draw; }
```

- `hg_frame()` = `hg_end()` (send this frame's records, sprite changes and scroll to the
  kernel: drawn by the blitter in the vertical blank) + `hg_begin()` (wait for the vertical
  blank, read keys, mouse, joystick, window events). It returns 0 when the game was closed
  (Alt+F4, close box, `hg_quit()`): leave the loop.
- Full screen, focus lost (Alt+Tab, Alt+Esc, F12): `hg_frame` pauses inside (sound off)
  until the focus returns; `hg_pauses` counts; `hg_autopause(0)` turns it off.
- Fixed-rate logic: `n = hg_steps(50); while (n--) step();` (at most 4 after a stall).
- Frames running late: `hg_missed` counts frames that took more than one blank. A game with
  its own clock (a DOS port) calls `hg_poll()` between frames: events, POKEY envelopes and
  the OPL2 stream without waiting; 0 once closed. Outside a frame (no `hg_begin` open: a
  program that never calls `hg_frame`) `hg_poll` also sends a changed view (`hg_scroll`,
  `hg_split`); `hg_view_send()` sends it at once (taken at the next vertical blank).
- Timers: `hg_ms()` (milliseconds, 10 ms steps); `hg_frames` (frames begun). No delay call:
  wait by looping on `hg_frame()` (`while (hg_ms() - t < ms && hg_frame()) ;`).
- `hg_stats("NAME")` prints `NAME: N frames, M missed, CPU X.XX ms a frame` (CPU from
  `hg_begin` to the send; `hg_cpu_ms` the total).

## Rules of the library

- **Drawing calls queue records**; nothing is drawn until `hg_end`. Images and text a frame
  uses must stay unchanged until the next frame begins.
- **One page** (default): the screen keeps what was drawn. Draw only what changes; use
  sprites or bobs for what moves. **`HG_DOUBLE`**: clear and redraw all of it each frame.
- **CPU drawing is slow**: `hg_pixel`, diagonal `hg_line`, `hg_peek` first draw and wait
  for the queued records, then work on the framebuffer by the CPU. Measured: `hg_pixel`
  136 us each, a 100-pixel diagonal line 12.7 ms. Use fills, images, or compose into an
  image once. In a window, pixels and diagonals become one record per run of pixels.
- Keep records of one kind together: images and fills (sheet records) vs text and moves
  (draw_list records); each switch is one more send (about 0.5 ms).
- `hg_origin(x, y)` is added to every drawing call's coordinates. `hg_flush(wait)` sends the
  records now.
- **Errors**: a call that can fail returns -1 or NULL; any bad argument (no image, a sprite
  not taken, frame past the last, colour > 255, drawing before a screen) prints
  `hgame: <function>: <what>` on the console (the first 16 times) and does nothing. Example
  seen: `hgame: hg_image_load: no such file`. Read `console.txt` after every run.

## Drawing

| Call | |
| --- | --- |
| `hg_clear(c)` | the whole visible screen (all pages) |
| `hg_fill(x, y, w, h, c)`, `hg_rect` (outline), `hg_hline`, `hg_vline` | blitter |
| `hg_line(x0, y0, x1, y1, c)`, `hg_pixel(x, y, c)`, `hg_peek(x, y)` | CPU (see rules); `hg_peek` full screen only |
| `hg_move(sx, sy, w, h, x, y)` | move a screen rectangle (overlap-safe) |
| `hg_text(x, y, s, ink)`, `hg_text_bg(x, y, s, ink, paper)`, `hg_textf(x, y, ink, fmt, ...)` | built-in 8 x 10 font (`HG_FONT_W`, `HG_FONT_H`), ASCII 32-126; `hg_text_width(s)` = 8 x length. `hg_textf` links printf |

Coordinates may be negative or off screen: the library clips. `HG_NONE` = no colour (no
paper, no key).

**Many small fills (Horizon 0.30).** Spans, scan lines, a road of hundreds of runs: never
one `hg_fill` each (3,400 cycles a run with the kernel's part). Fill an array of `hg_run`
{`ofs` = y * `hg_fb_stride` + x from the page's start, `color`, `w` 0-255} (`HG_RUN(&r[k],
ofs, w, c)`) and send it with one `hg_fill_runs(y0, runs, n)` (full screen; the page starts at
screen row y0): about 140 cycles a run whatever its width, Ali fills while the game goes on
(read the framebuffer after `hg_flush(1)`). Spans the game keeps in its own layout (a
shape's, prepared once): `hg_fill_groups` with `HG_RUNGROUP(&g, elems, n, colour, stride,
ofs_at, w_at)`, read where they are (elements in one bank, below its offset $FF00). Before
REV $09 hgame fills them with the CPU (the same pixels). Page flipping with three pages in a
taller framebuffer (`hg_screen_fb`), never waiting for the blank: `hg_flip_pages(3, rows)`,
`p = hg_flip_free()` to draw into, `hg_flip(p, dy)` to show it (REV $0B). `hg_us()`:
microseconds (`hg_ms` has 10 ms steps).

## Images and image files

`hg_image`: `n` frames of `w` x `h`, one under the other, in far memory; `key` the transparent
colour or `HG_NONE`; `pal`/`palbase`/`paln` its own colours if any.

| Call | |
| --- | --- |
| `hg_image_from(pixels, w, h, n, key)` | from a C array (img2c header); copied to far memory and made a sheet |
| `hg_image_load(path)` | from an `.HGI` file on the card (frames, key, palette) |
| `hg_image_new(w, h, n)` | blank (undefined contents): a background to compose into |
| `hg_draw(img, k, x, y)`, `hg_draw_part(img, sx, sy, w, h, x, y)` | blit frame k / any part (frame k's top is row k x h); keyed if the image has a key |
| `hg_image_draw(dst, src, k, x, y)`, `hg_image_fill(dst, x, y, w, h, c)` | CPU, image into image (compose a level once) |
| `hg_image_palette(img)` | set the image's own colours |
| `hg_image_pixels(img, k)` (`unsigned char __far *`), `hg_image_addr(img, k)` | raw pixels |
| `hg_image_free(img)` | frees the sheet; far memory comes back only at `hg_close` |

Making images: `SDK/tools/img2c.py` (PNG via Pillow, or img2inc text art: a legend
`x = N` / `x = cube r g b`, then rows, a blank line between frames):

```
img2c.py art/ship.txt -o art/ship.h --name ship --key 0   # C header: ship[], SHIP_W/H/N/KEY
img2c.py art/rock.txt -o ROCK.HGI --key 0                  # a file for hg_image_load
img2c.py art/hero.png -o hero.h --tile 16x16 --key 0       # sheet cut into frames
img2c.py art/title.png -o TITLE.HGI --own-palette 16       # its own colours from entry 16
```

`--key` defaults to 231; hardware sprites need `--key 0`; `--key none` = opaque. `--bpp 4` for
16-colour mode. `--preview OUT.png --scale 8` draws the art magnified. Header arrays live in
the 64 KB code bank: keep big pictures in `.HGI` files.

## Hardware sprites

16 in all (shared by every program), no CPU or blitter time. Images 16 x 16 or 16 x 32 at
8 bpp (4 bpp up to 32 x 32), colour 0 transparent, made by `hg_image_*`.

```c
if (hg_sprites(NSTARS + 1) < 0)          /* take n: numbered 0 .. n-1; -1: none free */
    return 1;
hg_sprite_set(0, shipimg, frame, 0);     /* | HG_HFLIP HG_VFLIP HG_MAG HG_BEHIND HG_HIDE */
hg_sprite_pos(0, hg_screen_x(x), hg_screen_y(y));
```

`hg_sprite_show(n, on)`; `hg_sprite_hit(a, b, margin)` compares boxes (no hardware collision).
Changes go out together at `hg_end`. Lower numbers are in front. In a window, sprites show only
while it has the focus and nothing covers it.

## Bobs (blitter sprites)

Up to `HG_BOBS` (32) images drawn over a background image, which restores what was under them:
`hg_bob_background(bg, x, y)`, `hg_bob(n, img, frame, x, y)`, `hg_bob_hide(n)`,
`hg_bob_redraw()` (after drawing over them). Drawn last each frame, in number order. Works in
windows (Gem Run in C does it).

## Tile maps and scrolling

- Not scrolling: `hg_map_draw(map, mw, mh, tiles, x, y)` (one record a tile);
  `hg_map_image(dst, map, mw, mh, tiles)` (CPU, into an image: about 112 ms for 20 x 12
  tiles: do it between levels).
- Scrolling (full screen, one page): `hg_map(map, mw, mh, tiles, panel)` (map bytes are frame
  numbers of `tiles`; `panel` > 0 rows of a fixed panel at the top, < 0 at the bottom, 0
  none), then each frame `hg_camera(x, y)`: Marga scrolls, only the tiles coming into view
  are drawn. `hg_map_set(c, r, t)`, `hg_map_get(c, r)`, `hg_map_border(t)`; `hg_cam_x`,
  `hg_cam_y`, `hg_play_y`; world to screen `hg_screen_x(wx)`, `hg_screen_y(wy)`.
  Draw into the panel with `hg_origin(0, hg_panel_y)` and back with `hg_origin(0, 0)`.
  The tutorial's `step4.c` does exactly this (13 sprites, panel: 4.2 ms CPU a frame).
- A taller framebuffer with a fixed panel (no map), as in `gt_view.c`:
  `hg_screen_fb(HG_320X180, "Game", 512, 400)`, then `hg_scroll(x, y)` and
  `hg_split(line, x2, y2)` (from screen `line` on, show from (x2, y2)). Views must stay
  inside the framebuffer (else refused). ports/digger uses this for its 320 x 200 screen.
  The view is sent at `hg_end` (shown after the frame's drawing); without frames by
  `hg_poll` or `hg_view_send()` (`gt_poll.c`).

## Input

| Call | |
| --- | --- |
| `hg_key(k)`, `hg_key_pressed(k)`, `hg_key_released(k)` | held now / since last frame; `k` = HID usage: `HG_KEY_A` + n, `HG_KEY_1`..`HG_KEY_0`, `HG_KEY_ENTER`, `ESC`, `BKSP`, `TAB`, `SPACE`, `F1` (+ n to F11), `UP`, `DOWN`, `LEFT`, `RIGHT`, `W`, `S`, `D`, `P` |
| `hg_mods` | `HG_MOD_CTRL`, `HG_MOD_SHIFT`, `HG_MOD_ALT` held now (as at the last event read) |
| `hg_getchar()` | next typed character (ASCII), 0 if none |
| `hg_key_next()`, `hg_key_mods` | next key press in order: usage in bits 0-7, character in 8-15 (16 kept); it sets `hg_key_mods` to the modifiers held at that press (0 when none left). Shortcuts (Ctrl+G) read `hg_key_mods`: `hg_mods` may already have Ctrl up when Ctrl and G went up in the same frame |
| `hg_p1()`, `hg_p1_pressed()` | player 1: arrows + W A S D + joystick 1 as `HG_UP` `HG_DOWN` `HG_LEFT` `HG_RIGHT` `HG_FIRE` (Space, Enter, trigger) |
| `hg_joy(1 or 2)` | joystick port; reads 0 in the emulator (no joystick) |
| `hg_mouse_x`, `hg_mouse_y`, `hg_mouse_b` (1 left, 2 right, 4 middle), `hg_mouse_clicked()` | screen pixels (window: its content; 320 x 180: halved), updated by `hg_frame` / `hg_poll` whenever the mouse moves, a button held or not. Absolute only: no relative motion (the pointer stops at the screen's edges; a program cannot move it) |

F10 opens the menu bar and F12 leaves: do not bind them. Test with `key right 700` lines in
run816 scripts (references/testing.md).

## Sound

| Chip | Calls |
| --- | --- |
| POKEY (every board) | `hg_tone(v, pitch, vol, ticks)`, `hg_sfx(v, pitch, dpitch, vol, dvol, ticks, dist)` (voices 0-3, 20 ms ticks, `HG_TONE`, `HG_NOISE`, `HG_BUZZ`), `hg_pitch(hz)` (AUDF; `hg_pitch(440)` = 71), `hg_note(v, hz, vol)` (two exact 16-bit voices, v 0-1; a PC speaker: hz = 1193182 / divisor) |
| Lau samples (REV $0A+) | `hg_has_lau()`, `hg_sound_make(HG_SQUARE / HG_SINE / HG_TRIANGLE / HG_SAW / HG_NOISE_WAVE, hz, ms, fade%)` (16 kHz 8-bit), `hg_sound_from(far data, len, rate, bits)` (not copied: keep it), `hg_sound_load("X.WAV")` (PCM mono 8/16, or raw signed 8-bit 16 kHz), `hg_play(s, vol 0-255)` -> voice or -1, `hg_play_ex(s, vol, pan, semitones)`, `hg_stop(voice)` (-1 all), `hg_sound_free` |
| Music engine | `hg_music_play("/Music/LAU.MOD", loop)` (MOD, WAV, MIDI on the OPL2), `hg_music_stop`, `hg_music_pause(on)`, `hg_music_volume(0-64)`, `hg_music_state()` (`HG_MUSIC_*`). Loads at start (blocks ~0.2 s): start it before play. Uses Lau's highest voices |
| OPL2 (REV $0C) | `hg_has_opl()`, `hg_opl_write(reg, val)`, `hg_opl_reset()`, `hg_opl_play(imf, len, hz, loop)` (IMF records {u8 reg, u8 val, u16 delay}, 4-byte aligned, not copied; played by `hg_frame`/`hg_poll`), `hg_opl_stop()`, `hg_opl_playing()`. One owner at a time: -1 while another program or the music engine has it |

`hg_sound_off()` silences POKEY and samples. Sound is never audible in the emulator: check with
`run816.py --log-sound` (POKEY: `DB0x` writes in `emu.err`), `--log-lau`, or `--wav FILE`.
Always fall back when a chip is missing (`hg_play` < 0 -> `hg_sfx`).

## Files of a game

- Find data next to the program: `hz_prog_dir(buf, 128)` (Horizon 0.28+: `/APPS/GAME/`),
  then `strcat` the name. Never rely on the current folder. Fall back to `""` on -1.
- Load levels, images and sounds at the start or between levels, never during play.
- Tests: `--file SRC:DEST` on run816 (or `RUNFLAGS` in the Makefile) puts the data on the
  card. An app folder with `APP.INF` and an `.HZA`: references/packaging.md.

## Helpers

`HG_FIX8(n)`, `HG_FIX8_INT`, `HG_FIX8_MUL`, `HG_FIX8_DIV` (8.8 in an int); `HG_FIX16(n)`,
`HG_FIX16_INT`, `hg_fix16_mul`, `hg_fix16_div` (16.16 in a long); `hg_rand()`, `hg_rand_n(n)`,
`hg_srand(seed)` (seeded from the clock: the same at every emulator run); `hg_sin(a)`,
`hg_cos(a)` (a in 256ths of a turn, result 8.8), `hg_atan2(dy, dx)`; `hg_overlap(...)`;
`hg_banks(n)` (n consecutive banks); `HG_MIN`, `HG_MAX`, `HG_ABS`, `HG_CLAMP`.

## Limits

32 bobs, 16 sprites, 32 sheets shared system-wide (4,096 rows together), 128 records a send
(split by hgame), 2 KB of text a frame, images at most 4096 wide and 1024 rows in all. No
scaling, rotation, blending, or hardware collisions. Cost tables: references/performance.md.
