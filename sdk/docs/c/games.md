# Games in C: hgame

`hgame.h` is the C SDK's game library: a screen (full screen or a window), drawing by the
blitter, images, hardware sprites and blitter sprites, scrolling tile maps, input, sound and
music, and the helpers games use. A page of C puts a moving sprite with sound and input on
the screen. `conio.h` and `joystick.h` give cc65's console and joystick APIs on top of it, for
games written for cc65.

| | |
| --- | --- |
| Header | `sdk/c/include/hgame.h` (every function documented there); `conio.h`, `joystick.h` |
| Library | `sdk/c/game/` (C, and assembly for the hot paths: `game/*.s`); built into `sdk/c/build/game/small/libhgame.lib` and `sdk/c/build/game/large/libhgame.lib` (the two code models; one module a function: a game links what it uses) |
| Linking | by itself: hcc links the library when a C source includes `hgame.h`, `conio.h` or `joystick.h` (or with `hcc --game`), in either code model |
| Examples | the tutorial (`sdk/c/examples/tutorial`), Gem Run in C (`sdk/templates/c-game`), Glimmer (`sdk/c/examples/glimmer`, full screen, scrolling), Catch (`sdk/c/examples/catch`, conio only) |
| Tools | `sdk/tools/img2c.py` (pictures to C arrays or `.HGI` files) |
| Tests | `make -C sdk/c/game test` |

Contents: [the tutorial](#the-tutorial) · [how a frame works](#how-a-frame-works) ·
[reference](#reference) · [assets](#assets) · [performance](#performance) ·
[porting a game](#porting-a-game) · [limits and known faults](#limits-and-known-faults) ·
[tests](#tests)

## The tutorial

Five steps from an empty file to a small game. Each step is a complete program in
`sdk/c/examples/tutorial` (`stepN.c`); `make -C sdk/c/examples/tutorial` builds them all, `make
run N=3` runs step 3 in the emulator, `make test` runs every step with a short script (each
was built and run so). In the emulator the Desktop starts the program; on the board copy the
`.PRG` to the card and start it from the Desktop.

### Step 1: a screen and a box

```c
/* step1.c - a screen and a box that moves */
#include <hgame.h>

int main(void)
{
    int x = 152, y = 82;
    unsigned j;

    if (hg_screen(HG_320X180 | HG_DOUBLE, "Step 1") < 0)    /* full screen, two pages */
        return 1;
    while (hg_frame()) {                    /* 60 times a second */
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        j = hg_p1();                        /* arrows, W A S D, joystick 1 */
        if (j & HG_LEFT)  x -= 2;
        if (j & HG_RIGHT) x += 2;
        if (j & HG_UP)    y -= 2;
        if (j & HG_DOWN)  y += 2;
        hg_clear(0);                        /* the whole frame, drawn unseen */
        hg_fill(x, y, 16, 16, 196);
        hg_text(8, 8, "Step 1: the arrows move the box", 1);
    }
    return 0;
}
```

```
sdk/c/bin/hcc -o STEP1.PRG step1.c
```

- `hg_screen` takes the whole screen: 320 x 180 pixels of 256 colours (each pixel 4 x 4 on
  the monitor), a framebuffer in the program's own memory, a small window that the desktop
  shows when the game is paused. `HG_DOUBLE` gives two pages: the frame is drawn into the
  hidden one and shown whole at its end. A program that redraws everything every frame (as
  this one does, `hg_clear` first) needs it; without it the blitter would clear the screen
  while the monitor shows it.
- `hg_frame()` ends the frame before (the drawing goes out) and begins the next: it waits for
  the vertical blank (60 a second) and reads the keyboard, mouse and window events. It
  returns 0 when the player closed the game (Alt+F4); the loop ends and `main` returns.
  Everything is given back at exit (`hg_close` runs by itself).
- Colours are palette entries: the system palette until the game sets its own (`hg_palette`).
  196 is the colour cube's red (16 + 36 r + 6 g + b), 1 white.
- Alt+Tab, Alt+Esc and F12 bring the desktop back; the game is paused inside `hg_frame`
  (sound off) until its window has the focus again.

### Step 2: an image

Pictures are drawn as text (or PNG) and turned into C arrays by `sdk/tools/img2c.py`:

```
; art/ship.txt: the legend, then the rows; a blank line between frames
. = 0                 ; transparent: colour 0
w = 1                 ; white
b = cube 1 3 5        ; blue
...
.......ww.......
......wbbw......
```

```
python3 sdk/tools/img2c.py art/ship.txt -o art/ship.h --name ship --key 0
```

`art/ship.h` has `ship[]` (both frames' pixels) and `SHIP_W`, `SHIP_H`, `SHIP_N`, `SHIP_KEY`.
Step 2 (`step2.c`) makes an image of it and draws a frame of it each frame:

```c
#include "art/ship.h"
...
    shipimg = hg_image_from(ship, SHIP_W, SHIP_H, SHIP_N, SHIP_KEY);
...
        x = HG_CLAMP(x, 0, 304);            /* stay on the screen */
        hg_clear(0);
        hg_draw(shipimg, (t >> 2) & 1, x, y);   /* frame 0 or 1: the flame flickers */
        sprintf(line, "Step 2: x %3d  y %3d", x, y);
        hg_text(8, 4, line, 1);
```

`hg_image_from` copies the pixels into far memory and registers them with the kernel as a
*sheet*, which makes each blit of it cheap. `hg_draw` skips the key colour (here 0): the
ship's corners show the background.

### Step 3: things to collect, a score, sound

`step3.c` adds stars at random places (`hg_rand_n`), a box test (`hg_overlap`) and a sound:

```c
    ding = hg_sound_make(HG_SINE, 1320, 150, 60);   /* a sample, made here */
...
        for (i = 0; i < NSTARS; i++)
            if (hg_overlap(x + 3, y + 3, 10, 10, sx[i] + 3, sy[i] + 3, 10, 10)) {
                ++score;
                place(i);                   /* somewhere else */
                if (hg_play(ding, 200) < 0) /* no Lau (older boards): POKEY */
                    hg_sfx(0, 60, -4, 12, 1, 8, HG_TONE);
            }
```

`hg_sound_make` writes a 16 kHz sample (a sine at 1320 Hz, 150 ms, fading over its last
60 %) into far memory; `hg_play` plays it on any free voice of Lau, the sample player. On a
board without Lau `hg_play` returns -1 and the game uses a POKEY effect instead: `hg_sfx`
(voice 0, pitch 60 rising by 4 every 20 ms, volume 12 falling by 1, 8 ticks).

### Step 4: a world larger than the screen

`step4.c` is the full-screen path the hardware was built for: the world is a tile map of 60 x
30 tiles, Marga scrolls it (no redrawing), the ship and the stars are hardware sprites (no
blits at all), and a panel stays at the top.

```c
    if (hg_screen(HG_320X180, "Step 4") < 0)       /* one page: Marga scrolls */
        return 1;
    tiles = hg_image_from(tilepx, 16, 16, 3, HG_NONE);  /* three tiles, opaque */
    ...
    if (hg_map(map, MW, MH, tiles, 16) < 0)        /* 16 rows of panel at the top */
        return 1;
    if (hg_sprites(NSTARS + 1) < 0)                 /* the ship and the stars */
        return 1;
    while (hg_frame()) {
        ...
        hg_camera(x - 152, y - 74);                 /* the ship in the middle */
        for (i = 0; i < NSTARS; i++) {
            scx = hg_screen_x(sx[i]);               /* world -> screen */
            scy = hg_screen_y(sy[i]);
            hg_sprite_set(1 + i, starimg, ((t >> 4) + i) & 1,
                          scx > -16 && scx < 320 && scy > 0 && scy < 180 ? 0 : HG_HIDE);
            hg_sprite_pos(1 + i, scx, scy);
        }
        hg_sprite_set(0, shipimg, (t >> 2) & 1, 0);
        hg_sprite_pos(0, hg_screen_x(x), hg_screen_y(y));
        if (panel) {                                /* the panel only when it changes */
            hg_origin(0, hg_panel_y);
            hg_fill(0, 0, 320, 16, 16 + 1);
            hg_text(8, 3, line, 1);
            hg_origin(0, 0);
        }
    }
```

- `hg_map` makes the framebuffer a ring of tile slots and draws every slot; `hg_camera` moves
  the view: it draws only the column or row of tiles that comes into view and sets Marga's
  scroll registers, all in the same vertical blank.
- The sprites' images must use colour 0 for transparency (`img2c.py --key 0`); positions
  are on the screen, so world positions go through `hg_screen_x` / `hg_screen_y`.
- No `HG_DOUBLE` and no `hg_clear`: nothing is redrawn each frame, the frame is a camera
  move, sprite moves and, now and then, a panel update. Measured: 4.4 ms of CPU a frame
  (`hg_stats` at the end of its test.script run: "STEP4: 335 frames, 6 missed, CPU 4.41 ms
  a frame").

### Step 5: a small game

`step5.c` puts states around step 4: a title ("Space: 30 seconds, go!"), half a minute of
play with a timer in the panel, game over with the best score, and music:

```c
    hg_music_play("/Music/LAU.MOD", 1);            /* (no file: no music, the game goes on) */
    ...
        if (state != PLAY) {                        /* the title and game over: wait */
            if (hg_p1_pressed() & HG_FIRE) {        /* Space, Enter or the trigger */
                state = PLAY;
                ...
            }
            continue;
        }
        secs = (unsigned)((hg_ms() - start) / 1000);
        if (secs >= 30) {
            state = OVER;
            ...
        }
```

`hg_music_play` starts Horizon's music engine (`/SYSTEM/MUSICD.PRG`), which plays the module
on Lau's highest voices while the game uses the lowest for its effects. From here, Gem Run in
C (`sdk/templates/c-game`) and Glimmer (`sdk/c/examples/glimmer`) are complete games to read
and copy.

## How a frame works

- **Records, not pixels.** Drawing calls (`hg_fill`, `hg_draw`, `hg_text`, ...) do not draw:
  they add records to the frame's list, cut to the screen. `hg_end` (inside `hg_frame`) sends
  the list to the kernel, which has Ali, the blitter, draw it **in the vertical blank**,
  together with the sprite changes and the scroll registers. The CPU goes on meanwhile. So
  the images and the text a frame uses must not change until the next frame begins.
- **Runs.** Records from sheets (images made by hgame) and fills go out as `sheet_draw`
  records (cheaper for the kernel), text and moves as `draw_list` records; a frame's records
  are sent in order, one call per run of one kind. A call after the first waits for the one
  before it, which starts in the vertical blank: a frame of several runs ends in `hg_end`
  just after the blank instead of in `hg_frame`'s wait. That costs no frame time; it is
  why `hg_stats` measures the CPU time up to the sending.
- **One page or two.** With one page (the default) the screen is what was drawn: draw only
  what changes (a panel, the tiles coming into view, the places of moving things) and use
  sprites or bobs for what moves. With `HG_DOUBLE` the frame is drawn into the hidden page
  and shown at its end (page flipping by Marga's scroll registers): for programs that clear
  and redraw everything. Two pages and a scrolling map do not go together.
- **The CPU.** Pixels (`hg_pixel`), diagonal lines and `hg_peek` work on the framebuffer
  directly: the records so far are drawn and waited for first. Group them, or draw them
  before the frame's blits. In a window there is no framebuffer: pixels and lines are
  records.
- **Bobs** (blitter sprites) need a background image: at the start of each frame the old
  places of the bobs are put back from it (records reserved at `hg_begin`), the game's
  records follow, and the bobs are drawn last, over everything. Nothing flickers: it all
  runs in the vertical blank.
- **Pause.** In full screen, when the window loses the focus (Alt+Tab, Alt+Esc, F12, another
  window), `hg_frame` stops the sound, waits for the focus and returns as if nothing
  happened (`hg_pauses` counts). `hg_autopause(0)` turns that off.

## Reference

Every function is described in `hgame.h`. In short:

| Screen | |
| --- | --- |
| `hg_screen(mode, title)` | full screen: `HG_320X180`, `HG_640X360`, `HG_640X360X4` (16 colours), `| HG_DOUBLE` (two pages), `| HG_POINTER` (the mouse pointer, 640 modes). The framebuffer's banks are found and taken (consecutive banks, as `examples/deepdive` does) |
| `hg_screen_fb(mode, title, stride, rows)` | full screen on a framebuffer of another shape: taller than the screen (a 320 x 200 game at 320 x 180, 640 x 400 at 640 x 360), or with a stride of 512 / 1024 so that no row crosses a bank (drawing by the CPU) |
| `hg_scroll(x, y)`, `hg_split(line, x2, y2)` | the view on such a framebuffer: from (x, y); from screen line `line` on from (x2, y2): a fixed panel above a part that scrolls (full screen, one page, not with `hg_map`). Sent at `hg_end`, shown from the blank after the frame's drawing; a program without frames (it keeps its own time and calls only `hg_poll`) has it sent by `hg_poll` |
| `hg_view_send()` | the view set by `hg_scroll` / `hg_split` to the screen now, without a frame (taken at the next vertical blank): a DOS port that draws straight into the framebuffer moves its view at once |
| `hg_window(w, h, title)`, `hg_window_menu(menus)` | a game in a window on the desktop (centred); its menus (`hg_menu()` reports picks) |
| `hg_close()` | back to the desktop, everything freed (also at exit) |
| `hg_w`, `hg_h`, `hg_win`, `hg_fb_bank`, `hg_fb_stride`, `hg_fb_rows` | the screen's size, the window, the framebuffer |
| `hg_palette(first, count, rgb)`, `hg_color(i, r, g, b)`, `hg_palette_black()` | colours; in a window entries 16-255 that no other program holds |
| `hg_raster(count, changes)` | the raster table (full screen): up to 16 palette changes at given lines |
| `hg_banks(n)` | n consecutive 64 KB banks |

| The frame | |
| --- | --- |
| `hg_frame()` | end the frame, begin the next (wait, input); 0 when the game was closed |
| `hg_begin()`, `hg_end()` | the two halves, for programs that want them apart |
| `hg_steps(hz)` | logic steps due at hz a second (fixed time step; at most 4 after a stall) |
| `hg_quit()`, `hg_autopause(on)` | make `hg_frame` return 0; the pause on lost focus |
| `hg_poll()` | the events, the POKEY envelopes and the OPL2 stream now, without waiting for the blank: for a game whose frames run late or that keeps its own time (a DOS port's clock: ports/xargon); outside a frame (no `hg_begin` open) also a changed view (`hg_scroll`, `hg_split`); 0 once closed |
| `hg_frames`, `hg_missed`, `hg_pauses`, `hg_cpu_ms`, `hg_stats(name)` | counters; "NAME: N frames, M missed, CPU X ms a frame" on the console |

| Drawing | |
| --- | --- |
| `hg_clear(c)`, `hg_fill`, `hg_rect`, `hg_hline`, `hg_vline` | fills and outlines (the blitter) |
| `hg_line`, `hg_pixel`, `hg_peek` | lines (straight ones by the blitter), pixels, reading back (full screen) |
| `hg_move(sx, sy, w, h, x, y)` | a rectangle of the screen moved (overlap-safe) |
| `hg_text(x, y, s, ink)`, `hg_text_bg(..., ink, paper)`, `hg_textf(x, y, ink, fmt, ...)`, `hg_text_width(s)` | the built-in 8 x 10 font (Horizon's console font), one record a string |
| `hg_origin(x, y)` | added to every drawing call's coordinates (`hg_origin(0, hg_panel_y)`: the panel) |
| `hg_flush(wait)` | send the records now (and wait for them) |

| Runs and page flipping (Horizon 0.30) | |
| --- | --- |
| `hg_fill_runs(y, runs, n)`, `hg_fill_runs_at(page, size, runs, n)` | many horizontal runs, each of one colour (`hg_run` {offset, colour, width 0-255}, `HG_RUN(r, ofs, w, c)`), filled by the blitter in one system call (`fill_runs`): about 140 CPU cycles a run whatever its width, against 600 and more for the CPU and 3,400 for an `hg_fill` record. The page: the framebuffer from screen row y (to its end or 64 KB), or any memory of the game's own; offsets are y * `hg_fb_stride` + x from its start. Full screen only. Before REV $09 or with the blitter off hgame fills them with the CPU (the same pixels) |
| `hg_fill_groups(y, g, n)`, `hg_fill_groups_at(...)`, `HG_RUNGROUP(g, elems, n, colour, stride, ofs_at, w_at)` | groups: the game's own arrays of spans in any layout (n elements of stride bytes, each with a u16 offset at byte ofs_at and a u8 width at byte w_at), each group in one colour, read where they are (a shape's spans prepared once, drawn each frame); about 300 cycles a group and 150 an element: worth it for long groups |
| `hg_flip_pages(n, rows)`, `hg_flip(page, dy)`, `hg_flip_free()`, `hg_flip_shown` | page flipping without waiting for the blank, in a framebuffer taller than the screen (`hg_screen_fb`, REV $0B): n pages (2-4) at framebuffer rows rows[k]; `hg_flip` waits for the drawing sent, shows the page from the next blank on and returns at once; with three pages the game never waits for the blank (ports/skyroads) |
| `hg_us()` | microseconds since the machine started (`uptime_us`; `hg_ms` has 10 ms steps) |

| Images | |
| --- | --- |
| `hg_image_from(pixels, w, h, n, key)`, `hg_image_load(path)`, `hg_image_new(w, h, n)`, `hg_image_free` | from a C array (copied into far memory), from an `.HGI` file, blank |
| `hg_draw(img, frame, x, y)`, `hg_draw_part(img, sx, sy, w, h, x, y)` | blits; keyed when the image has a key colour |
| `hg_image_draw(dst, src, frame, x, y)`, `hg_image_fill`, `hg_map_image` | the CPU, image to image (composing a background) |
| `hg_image_palette(img)`, `hg_image_pixels(img, k)`, `hg_image_addr(img, k)` | the image's own colours; its pixels (`unsigned char __far *`: they are in far memory) |

| Sprites | |
| --- | --- |
| `hg_sprites(n)` | take n of Marga's 16 sprites |
| `hg_sprite_set(n, img, frame, flags)`, `hg_sprite_pos`, `hg_sprite_show` | image and flags (`HG_HFLIP`, `HG_VFLIP`, `HG_MAG`, `HG_BEHIND`, `HG_HIDE`), place; sent together at `hg_end` (one `spr_set`, one `spr_move` of many) |
| `hg_sprite_hit(a, b, margin)` | the boxes overlap (the hardware reports no collisions) |
| `hg_bob_background(img, x, y)`, `hg_bob(n, img, frame, x, y)`, `hg_bob_hide`, `hg_bob_redraw` | blitter sprites (32), over a background image |

| Tile maps | |
| --- | --- |
| `hg_map_draw(map, mw, mh, tiles, x, y)` | a map drawn whole (a record a tile) |
| `hg_map(map, mw, mh, tiles, panel)`, `hg_camera(x, y)` | scrolling (full screen): the ring of slots, the camera; panel > 0 rows at the top, < 0 at the bottom |
| `hg_map_set(c, r, t)`, `hg_map_get`, `hg_map_border(t)` | change a tile (drawn if in view); the tile outside the world |
| `hg_cam_x`, `hg_cam_y`, `hg_play_y`, `hg_panel_y`, `hg_screen_x(wx)`, `hg_screen_y(wy)` | the camera, the playfield's top, the panel's rows, world to screen |

| Input | |
| --- | --- |
| `hg_key(k)`, `hg_key_pressed(k)`, `hg_key_released(k)`, `hg_mods` | the key table (HID usages: `HG_KEY_ESC`, `HG_KEY_A` + n, arrows, ...); `hg_mods`: the modifiers (`HG_MOD_CTRL`, `_SHIFT`, `_ALT`) held now, as at the last event read |
| `hg_getchar()` | typed characters (ASCII, `KEY_*` for arrows) |
| `hg_key_next()`, `hg_key_mods` | the keys pressed, in order (SDL_KEYDOWN's events): the HID usage in bits 0-7, the character in bits 8-15; each call sets `hg_key_mods` to the modifiers held when that key went down (SDL's `event.key.keysym.mod`). Read shortcuts from it: when Ctrl and G go up in the same frame (typed quickly, or a keyboard adapter that reports both at once), `hg_mods` already says Ctrl is up |
| `hg_joy(port)`, `hg_p1()`, `hg_p1_pressed()` | the joysticks; player 1: arrows + W A S D + joystick 1, fire Space / Enter / trigger |
| `hg_mouse_x`, `hg_mouse_y`, `hg_mouse_b`, `hg_mouse_clicked()` | the mouse in screen pixels (halved in 320 x 180), updated by `hg_frame` / `hg_poll` whenever it moves, a button held or not (full screen and window). Absolute only: there is no relative motion (the pointer stops at the screen's edges and a program cannot move it), so a mouse-look game gets no deltas past an edge |
| `hg_mouse_wheel()` | the wheel's steps since the last call (positive: up / away from you), then 0; full screen and window, collected by `hg_frame` / `hg_poll` |

| Sound | |
| --- | --- |
| `hg_tone(v, pitch, vol, ticks)`, `hg_sfx(v, pitch, dpitch, vol, dvol, ticks, dist)`, `hg_pitch(hz)` | POKEY, voices 0-3, envelopes stepped every 20 ms (by the clock) |
| `hg_note(v, hz, vol)` | POKEY's two 16-bit voices (channels joined in pairs at 1.79 MHz): a square tone at any pitch from 14 Hz, exact (music; a PC speaker's tones, hz = 1193182 / the PIT divisor), until changed |
| `hg_has_lau()`, `hg_sound_make(wave, hz, ms, fade)`, `hg_sound_from(data, len, rate, bits)`, `hg_sound_load(path)` | samples: made here, from memory (a C array, or far memory: a `__far` pointer into a bank of `hz_far_alloc` / `hg_banks`), from a `.WAV` (PCM 8/16-bit mono) or raw file |
| `hg_play(s, vol)`, `hg_play_ex(s, vol, pan, semitones)`, `hg_stop(voice)`, `hg_sound_off()` | on Lau's free voices |
| `hg_music_play(path, loop)`, `hg_music_stop`, `hg_music_pause`, `hg_music_volume`, `hg_music_state` | MOD, WAV or (REV $0C) MIDI files by Horizon's music engine; `hg_music_play` returns once it plays |
| `hg_has_opl()`, `hg_opl_write(reg, val)`, `hg_opl_reset()` | the OPL2 (REV $0C, a YM3812: AdLib and Sound Blaster FM) by the game itself: its registers (one owner at a time; `hg_close` gives it up) |
| `hg_opl_play(imf, len, hz, loop)`, `hg_opl_stop()`, `hg_opl_playing()` | an AdLib register stream from memory (any bank, on across consecutive banks): id Software's IMF records {register, value, u16 delay in 1/hz s}, played by `hg_frame` / `hg_poll` as they come due (to the frame: within 1/60 s); a pause keys the voices off. Most DOS games' AdLib music converts to it (ports/xargon's CMF songs: `tools/mkdata.py`) |

| Helpers | |
| --- | --- |
| `HG_FIX8(n)`, `HG_FIX8_MUL`, `HG_FIX8_DIV`, `HG_FIX16(n)`, `hg_fix16_mul`, `hg_fix16_div` | 8.8 and 16.16 fixed point (no 64-bit type here: the 16.16 multiply and divide are functions) |
| `hg_rand()`, `hg_rand_n(n)`, `hg_srand(seed)` | xorshift, 16 bits (seeded from the clock) |
| `hg_sin(a)`, `hg_cos(a)`, `hg_atan2(dy, dx)` | angles in 256ths of a turn, results in 8.8 |
| `hg_overlap(...)`, `hg_ms()`, `HG_MIN`, `HG_MAX`, `HG_ABS`, `HG_CLAMP` | rectangles, milliseconds (10 ms steps) |

**Misuse.** A bad argument (no image, a sprite not taken, a frame past the last, a colour
past 255, drawing before a screen) prints `hgame: function: what` on the console, the first
16 times, and the call does nothing. The library is always built so (the checks cost little
beside the calls they guard).

## Assets

**Pictures.** `sdk/tools/img2c.py` reads a PNG (Pillow) or img2inc's text art and writes
either a C header (pixels as a `static const` array: include it in one `.c`) or an `.HGI`
file for `hg_image_load`:

```
img2c.py art/hero.png -o hero.h --tile 16x16 --key 0      # a sprite sheet: frame k = tile k
img2c.py art/tiles.png -o TILES.HGI --key none             # opaque tiles, loaded from the card
img2c.py art/title.png -o TITLE.HGI --own-palette 16       # its own colours from entry 16
img2c.py art/font.txt -o font.h --bpp 4                    # 16 colours, two pixels a byte
```

- `--tile WxH` cuts a picture into frames (left to right, top to bottom): sprite sheets and
  tile sets; `hg_draw(img, k, ...)` draws frame k, `hg_draw_part` any rectangle.
- Colours become the nearest system palette entry, or with `--own-palette BASE` the
  picture's own (in the file: `hg_image_palette(img)`; in the header: `NAME_pal`,
  `NAME_PALBASE`, `NAME_PALN`). Text art can name entries by number (`a = 5`), which a
  full-screen game with its own palette does.
- The key colour (`--key N`, default 231 as img2inc) marks transparent pixels; hardware
  sprites need 0 (`--key 0`); `--key none` makes an opaque image.
- Arrays live in the program's 64 KB code bank (with the code and globals): keep big
  pictures in `.HGI` files. `hg_image_from` copies the array into far memory (any image is
  in far memory, 256-byte aligned, as sprites need).
- `make preview` in the templates draws the art magnified (`--preview OUT.png`).

**Sounds.** `hg_sound_make` makes square, sine, triangle, saw and noise effects at run time
(as `examples/deepdive` does in assembly): no files. `hg_sound_load` reads a `.WAV` file (PCM,
mono, 8 or 16 bits, any rate) or raw signed 8-bit samples at 16 kHz into far memory. A
sample in a C array (signed bytes) plays as it is with `hg_sound_from`. 16 kHz 8-bit is a
good size for effects (16 KB a second).

**Music.** `hg_music_play("/Music/X.MOD", 1)` starts the music engine with a module, a WAV
file or (REV $0C: the OPL2) a MIDI file. The replayer library (`horizon/build/modplay.o`) is
a ca65 object, and hgame has no binding for it: the engine is the way from C. It loads the file at priority 0, which holds the game up while
it loads (about 0.2 s for a 31 KB module in the emulator): start the music before play.

**AdLib music.** A DOS game's FM music (AdLib, Sound Blaster: IMF, DRO, CMF, ROL, ...) is
register writes to the OPL2 at given times. Convert it on the PC to an IMF stream (records
of {register, value, delay}) and play it with `hg_opl_play`: the game keeps the chip, no
engine is started, the timing is the frame's. `ports/xargon/tools/mkdata.py` converts
Creative's CMF songs so (SBFMDRV's voice allocation, rhythm mode and transposition, after
AdPlug's CMF player). The board mixes the OPL2 three times louder than a Lau voice at full
volume: music written for a Sound Blaster may clip there (Xargon's songs did, 1-2 % of the
samples: the converter makes their carriers 10.5 dB quieter).

**Fonts.** The built-in font is Horizon's console font (8 x 10 cells here, ASCII 32-126;
`make -C sdk/c/game font` makes `hg_font.c` from it). For another font, draw it as images.

## Performance

The figures were measured in the emulator, which models the board's speed within about 5 %
(emu816's memory timing; reference.md, "Speed"). Plan with them as they are.

**What things cost** (one 16 x 16 record unless said; the library's CPU time to queue it,
then the kernel's when the frame is sent; Ali's drawing runs alongside the CPU):

| | Library (queue) | Kernel (send) |
| --- | --- | --- |
| `hg_draw` from a sheet (any image made by hgame), keyed or not | 80 us | 62 us |
| the same as a `draw_list` record (an image without a sheet: all 32 taken) | 80 us | 170 us |
| `hg_fill` (any size; a fill is the kernel's slow record) | 66 us | 200 us |
| `hg_text`, 20 characters | 700 us | about 200 us |
| `hg_text`, 5 characters | 350 us | about 200 us |
| one send (each run of records), and waiting for a list | | 500 us, 160 us |
| a syscall: `hz_frame`, `hz_joystick`, `hz_uptime` | | 80-90 us |
| `hz_spr_move` of one sprite | | 98 us (16 of them: 1.6 ms; hgame sends them in one call) |
| `hg_image_draw` (the CPU), a 16 x 16 tile; `hg_map_image` of 20 x 12 tiles | 650 us; 112 ms | |
| Ali (the blitter): clearing 320 x 180; copying a 320 x 192 image | | 5.6 ms; 7.8 ms (while the CPU goes on) |
| (0.30) `hg_fill_runs`: a run of any width up to 255 (2,000 a call) | | 9.7 us (140 cycles); a call about 0.35 ms |
| (0.30) the same 23-pixel runs filled by the CPU: hgame's assembly, a C loop | 42 us, 119 us | |

**What a frame can afford** (16.7 ms at 60 frames a second, leaving the game's own logic
some room):

- about **50 blits** from sheets (about 7 ms: 50 x (80 + 62) us), or about 25 fills;
- a few **lines of text** (each line about 0.9 ms): redraw text only when it changes;
- **sprites**: all 16 moved for well under 1 ms (one call);
- **scrolling**: a camera move is one `fs_scroll` and, every 8 frames at 2 pixels a frame, a
  column of 12 tiles (about 2 ms in that frame);
- a frame's fixed cost (`hg_frame`: the wait, one event poll, the joystick when asked, the
  sound envelopes, the send) is about 1 ms;
- with `HG_DOUBLE` the blitter's own time counts too: the page is shown only when it is
  drawn, so a frame that clears the whole 320 x 180 screen (5.6 ms of Ali) has about 11 ms
  left for everything else; at 640 x 360 a full clear takes four times as long. Clear only
  the part that changes, or use one page and sprites.

Measured programs (emulator, the scripted runs of their tests; "hg_stats"
is the program's own line at the end, "busy" emu816 --stats over the whole run against
13.5 % for an idle desktop over the same time):

| | |
| --- | --- |
| Glimmer (full screen 320 x 180, scrolling, 16 sprites, panel, music playing; 17.1 s run) | 429 frames, 3 missed; hg_stats 4.53 ms a frame; busy 37.3 %; 37,900 bytes on the card |
| Gem Run in C (a window, 2 bobs, a background image; 50 steps a second, 60 frames; 13.8 s run) | 354 frames, 19 missed; 1.73 ms a frame; busy 29.8 %; 28,935 bytes |
| Tutorial step 4 (full screen, scrolling, 13 sprites; test.script) | 335 frames, 6 missed; 4.41 ms a frame; 27,262 bytes |

Gem Run's missed frames come mostly while a level is composed (240 tiles by the CPU, about
112 ms, three times in the test; the assembly Gem Run does the same), Glimmer's at a
pick-up or a hit (a sample started, the panel redrawn, a console line). For comparison,
Gem Run in assembly (`sdk/templates/game`, 50 Hz, win_draw) was measured at 23.4 % busy
over the same run (it is not built with a C compiler).


`hg_stats` prints the CPU time from `hg_begin` to the sending (10 ms clock steps, averaged
over the frames; the kernel's sending is not in it): 4.5 ms a frame for Glimmer, 1.7 ms for
Gem Run (whose title screen frames do nothing).

Gem Run in C against the assembly original: the same rules, art, sounds and test; the C one
draws 60 frames a second (the assembly one at most 50) with bobs in the vertical blank (no
flicker; the assembly one erases and draws each sprite with two `win_draw` calls); it keeps
the CPU busier (29.8 % against 23.4 % over the test); its program is 28,935 bytes against
7,636 (hgame, printf and the C library), and its source 404 lines against 1,332.

**Advice.**

- Use sprites for what moves and a scrolling map for the world: neither costs blits.
- (0.30) Many small fills (spans, scan lines, a road): `hg_fill_runs` or `hg_fill_groups`,
  one call for all of them, not `hg_fill` (a run costs the kernel 140 cycles, an `hg_fill`
  record 3,400 with the library's part). The CPU still pays for every run: for runs of a few
  pixels a tight assembly loop costs about as much, for wide ones far more.
- Make every image with hgame (a sheet each, while the kernel has sheets: 32 in all, shared
  by all programs, 4,096 rows together); a blit from a sheet costs the kernel a third of a
  `draw_list` record.
- Draw only what changed. With one page, a panel or a score is redrawn when its value
  changes, not every frame.
- Keep a frame's records of one kind together: each change between sheet records (images,
  fills) and list records (text, moves) is one more send (0.5 ms).
- `int` and `unsigned` in game logic; no `long` multiplies in the frame (about 100 us each in
  the C runtime), no `float`. A multiply by a constant is inlined (shifts and adds); a divide by a
  constant that is not a power of two is a call (`__udiv16`).
- Console output is slow (`printf`: about 2 ms a line on the debug console): no `printf` in
  the frame loop of a finished game.
- Profile: `run816.py --prof FILE` makes the emulator count the CPU's cycles by
  instruction address, syscall, kernel and idle (`--prof-from S --prof-to S`: only that
  stretch, in seconds after the program's start, as `--shot`'s); `sdk/tools/prof816.py`
  turns the counts into a table of the program's functions. It reads hcc
  `--map`'s map and the label file beside it, in both code models (the large model's code
  banks are matched by their bytes with the banks the program got):

```
cd ports/digger && make          # (hcc --map: DIGGER.map and DIGGER.lbl)
python3 ../../sdk/tools/run816.py DIGGER.PRG --mode shell --args "/Q /S:0 /E:THEVOIDS.DRF" \
  --file DIGGER.DAT:/APPS/DIGGER.DAT --file tests/drf/thevoids.drf:/APPS/THEVOIDS.DRF \
  --seconds 120 --prof prof.txt --prof-from 20 --prof-to 120 --out build/prof
python3 ../../sdk/tools/prof816.py --counts prof.txt --map DIGGER.map --top 20
```

  100 s of play take about 10 s. The table: cycles and share for each function (an
  assembly routine by its label), each syscall (with its calls), the kernel and idle.
  (`sdk/tools/emu-prof.sh` still pipes `emu816 --trace` through it, for a short stretch.)

**What is in assembly inside the library** (`sdk/c/game/hg_fast.s` and `hg_fimg.s`, ca65 syntax; a game never
sees it): the record builder (clipping, the queue, the runs), `hg_fill`, `hg_draw` and
`hg_draw_part` from sheets, the text strip (a string's 1 bpp picture), the CPU's memory blit
and fill, and a 16 x 16 multiply. In C one `hg_fill` or `hg_draw` took 190-270 us; the
assembly takes 66-80 us, of which about 15 us is the C call itself.

## Porting a game

### From cc65 (conio, joystick)

`conio.h` and `joystick.h` follow cc65's: `clrscr`, `gotoxy`, `wherex`, `cputc`, `cputs`,
`cprintf`, `cgetc`, `kbhit`, `textcolor`, `bgcolor`, `revers`, `cursor`, `chline`, `cvline`,
`cclear` (and their `xy` forms), `screensize`, `waitvsync`; `joy_install`, `joy_read`, the
`JOY_*` macros. `sdk/c/examples/catch` is a game written against `conio.h` alone. The
differences:

- The screen is a window of 40 x 25 cells (8 x 10 pixels each) unless `conio_screen(cols,
  rows, full)` says otherwise before the first call (full screen: 40 x 18 or 80 x 36).
- Output shows at the next `kbhit`, `cgetc` or `waitvsync` (and every 64 characters when a
  frame has passed). A busy loop that prints and never looks at the keyboard should call
  `waitvsync()`; it also paces the game at 60 frames a second, as on the 8-bit machines.
- Colours are the C64's 16 names; the line characters `CH_HLINE`, `CH_VLINE`, corners and
  tees are drawn as `-`, `|`, `+`; there is no PETSCII or ATASCII graphics set.
- `cgetc` returns ASCII, `\n` for Enter, `CH_CURS_*` for the arrows, 8 for Backspace.
  Closing the window ends the program.
- `int` is 16 bits and `char` unsigned: game arithmetic ports as it is.
  Remove `__fastcall__` (`#define __fastcall__`), zero-page pragmas and `<peekpoke.h>`
  writes to hardware (not allowed: use hgame's calls).
- `joy_read` reads the DB9 ports; there is no keyboard joystick driver: a game that should
  also run on keys reads them (`kbhit`/`cgetc`, or hgame's `hg_p1`).

### From SDL-style code

| SDL (or similar) | hgame |
| --- | --- |
| `SDL_Init`, `SDL_CreateWindow`, `SDL_CreateRenderer` | `hg_screen(HG_320X180 | HG_DOUBLE, title)` or `hg_window(w, h, title)` |
| the main loop: `SDL_PollEvent` ... `SDL_RenderPresent` | `while (hg_frame()) { ... }`: events are read by `hg_frame`; the frame is shown at its end |
| `SDL_QUIT` | `hg_frame()` returns 0 |
| `SDL_GetKeyboardState`, `SDL_SCANCODE_*` | `hg_key(HG_KEY_*)` (the same HID usages as SDL's scancodes: `SDL_SCANCODE_A` = 4 = `HG_KEY_A`) |
| `SDL_KEYDOWN` events | `hg_key_next()` (in order: usage and character; its `keysym.mod`: `hg_key_mods`), `hg_key_pressed(k)`, `hg_getchar()` |
| `SDL_GetMouseState` | `hg_mouse_x`, `hg_mouse_y`, `hg_mouse_b`, `hg_mouse_clicked()` |
| `SDL_JoystickGetAxis` / buttons | `hg_joy(1)`, `hg_p1()` (digital) |
| `SDL_RenderClear` | `hg_clear(c)` (with `HG_DOUBLE`) |
| `SDL_RenderFillRect`, `SDL_RenderDrawRect`, `SDL_RenderDrawLine`, `SDL_RenderDrawPoint` | `hg_fill`, `hg_rect`, `hg_line`, `hg_pixel` |
| textures from files (`IMG_Load`, `SDL_CreateTextureFromSurface`) | `hg_image_load("X.HGI")` (made by img2c.py) or `hg_image_from(array, ...)` |
| `SDL_RenderCopy` with a source rectangle | `hg_draw(img, frame, x, y)`, `hg_draw_part(img, sx, sy, w, h, x, y)` |
| colour keys, alpha | a key colour (one transparent entry); no blending, scaling or rotation (`hg_sprite_set` flips and doubles hardware sprites) |
| RGB colours | palette entries: `hg_palette` sets them; the system palette's 6 x 6 x 6 cube is 16 + 36 r + 6 g + b |
| `SDL_GetTicks`, `SDL_Delay` | `hg_ms()` (10 ms steps); no delays: `hg_frame` paces, `hg_steps(hz)` gives fixed steps |
| `Mix_LoadWAV`, `Mix_PlayChannel` | `hg_sound_load("X.WAV")`, `hg_play(s, vol)`, `hg_play_ex` (pan, pitch) |
| `Mix_LoadMUS`, `Mix_PlayMusic` | `hg_music_play("X.MOD", loop)` (MOD, WAV, MIDI) |
| `float` positions and speeds | 8.8 fixed point in an `int` (`HG_FIX8`) or 16.16 in a `long` |
| a 640 x 480 game | 640 x 360 (`HG_640X360`), or a window up to 636 x 330; 320 x 180 for chunky games |
| a 320 x 200 (or 640 x 400) game | `hg_screen_fb` with 200 (400) rows and `hg_split`: the score line fixed at the top, the rest of the picture scrolled to follow the player (20 / 40 rows out of sight at a time); Digger does so (`ports/digger`) |
| a PC speaker (`outb` to the PIT) | `hg_note(v, 1193182 / divisor, vol)`: POKEY's square wave at the very same pitch |

Typical work, in this order: make it build (16-bit `int`: sizes, products and times in
`long`; porting.md), replace the platform layer with the table above, turn the art into
`.HGI` files, then make it fast: the full-redraw loop of an SDL game becomes `HG_DOUBLE` with
`hg_clear` first (simple, about 50 blits a frame), and later sprites and a scrolling map
where the game allows.

## Limits and known faults

- A game whose code does not fit in one bank builds with `hcc --code large` (the
  code fills several banks, still one file GAME.PRG; hgame is built for it too and its tests
  run in it): reference.md, "The two code models". The images, sounds and big tables
  belong in files and far memory anyway, since constants and data stay in the main bank.
- At most 32 bobs, 16 hardware sprites, 128 records a send (more are sent
  in pieces), 460,800 pixels a send (the kernel's limit; hgame splits), 2 KB of text a frame
  before it is sent early.
- Images are frames one under the other, at most 4096 wide and 1024 rows in all (the sheet
  limit); far memory for images and sounds is given back by `hg_close` (exit), not by
  `hg_image_free` (which frees the sheet).
- 16-colour images (`HG_640X360X4`) come only from `.HGI` files (`img2c.py --bpp 4`); text and
  pixels in that mode are drawn by the CPU.
- No collision report from the hardware (boxes only), no scaling, rotation or blending.
- The emulator has no joystick; `hg_joy` reads 0 there.

## Tests

```
make -C sdk/c/game test
```

runs `sdk/c/game/tests/run.py` in both code models (`small`, `large`), then the scripted
tests of Glimmer, Catch, the tutorial and Gem Run in C. run.py
builds eleven test programs (`tests/gt_*.c`: drawing, the screen modes and the pause,
a framebuffer taller than the screen with a split view, the key queue and the 16-bit voices,
a window with bobs and its menu, hardware sprites, scrolling maps, input, sound and music,
the helpers and `.HGI` files with bad arguments, (0.30) runs and groups by the blitter
against the CPU's, page flipping with three pages and `hg_us`, and `gt_runbench`, the
measurement of a run by every way of filling it, its table in console.txt) and runs each in
the emulator with a script;
it checks the program's own PASS / FAIL lines (each reads the framebuffer back), the
screenshots against `tests/ref/` (the same pictures for both code models: every shot is
taken while nothing moves, or of what the program draws for a given frame), the POKEY and Lau writes
the emulator logs and the sound it records (Lau and the OPL2). `make -C sdk/c/game refs`
writes new reference pictures after a change that is meant to show.
