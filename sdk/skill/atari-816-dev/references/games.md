# Games on Horizon

Three starting points (all tested):
- `SDK/examples/deepdive` - **full screen** (Horizon 0.18): own framebuffer in two banks,
  fine scrolling with wrap and a split panel, one draw list a frame (LS_VBL), 15 hardware
  sprites with one spr_set a frame, own palette + raster table, Lau samples made at run
  time, pause on WE_UNFOCUS. Start here for a scrolling or full-screen game.
- `SDK/templates/game` (Gem Run) - a game **in a window** on any revision: tile map, keyed-blit
  sprites with dirty rectangles, timer loop, keys + mouse, POKEY sound, title / play / game over.
- `SDK/examples/lantern` - a finished arcade game in a window.
Long version: `SDK/docs/reference/game-patterns.md`; the calls: `SDK/docs/reference/games.md`.

## Constraints that shape the design

- Full screen (`fs_enter`): 640x360x8, 640x360x4 or 320x180x8 (each pixel 4x4 on the
  monitor: chunky, 16x16 sprites are big), the framebuffer in your own memory (one bank holds
  320x180; more needs consecutive banks: bank_alloc gives the lowest free one, check), your
  own 256-entry palette. Or a **window** (framed, or WF_PLAIN up to 640x344 at (0, 16)).
- REV $0B (the emulator's default) for sprites and fs_scroll; REV $09 for the frame counter,
  command lists, raster table, WE_VBL; REV $0A for Lau. ENODEV tells you; decide what to do
  without (deepdive refuses to run without sprites; a window game can blit instead).
- One `draw_list` replaces many `win_draw` calls: 100 keyed blits cost 100 syscalls and 26.6
  ms CPU a frame as win_draw, one call and 14.4 ms as a list (about 2,000 cycles a record, in
  the call), Ali's blits running alongside. Still: draw only what changed.
- Sprites cost nothing per frame: one `spr_set` for all of them (or `spr_move`).
- CPU 14.3 MHz in the emulator, effectively ~half of that on the board for CPU-heavy code.
- Input: keys (down / up events), the mouse, the joysticks (SYS_JOY: A bits 0-3 port 1, 4-7
  port 2, X the triggers). Map the keys to the same joystick-style bit mask (1 up, 2 down,
  4 left, 8 right, 16 fire) and OR the stick in. On WE_UNFOCUS forget the held keys.
- Sound: Lau samples (`SYS_SPLAY`, verify with `--log-lau`), or POKEY 2 through `SYS_SNDW`
  (`--log-sound`); no audio in the emulator.

## The full-screen frame (deepdive)

`vsync` -> poll events (WE_UNFOCUS: pause, blocking on win_event until WE_FOCUS; Esc /
WE_CLOSE: fs_leave + exit) -> joystick -> rules -> camera -> records (tiles that came into
view, panel changes) -> one draw_list, LS_VBL on record 0 -> fs_scroll -> spr_set. List,
scroll and sprites all land in the same vertical blank. About 6 syscalls, 1.8 ms CPU a frame
(emulator).

- Framebuffer as a ring of tile slots: tile (c, r) -> slot (c mod COLS, r mod ROWS); scroll
  x2 = camx mod stride, y2 = camy mod vheight with FSC_HWRAP and vheight; one spare column.
- Panel: rows past vheight (never wrap), first scroll set above the split line.
- SPR_BEHIND + background colour 0: sprites go behind rock and the panel with no clipping.
- Palette black (pal_set 256 zeros) while the first screen is drawn, then the real one.

## Loop in a window (templates/game)

`SYS_WTIMER` with period 2 (20 ms) on the game window. Wait for an event; then poll the
rest; count WE_TICKs in `pending`; run one logic step per tick (cap at 4); draw once.
Logic speed stays constant, drawing skips frames when slow. Never `SYS_SLEEP` in a game.

## Drawing in a window (dirty rectangles with the blitter)

With sprites (REV $0B) a window game needs none of this for what moves: spr_alloc for the
window, spr_set once a frame (they show while the window is focused and uncovered, and only
those wholly inside the content). For blits, prefer one draw_list a frame (erase + keyed
copy records, LS_VBL first) over win_draw calls. The win_draw way:

1. `SYS_BALLOC` a bank for the background picture (320 x 192 = 61,440 bytes fits).
2. Render the tile map into it with the CPU (`lda [src],y` / `sta [dst],y`, two bytes a
   time; or MVN with patched banks).
3. Show it: one `WD_SBLIT` (stride = picture width, in c1 | c2 << 8).
4. Per frame, for each sprite that moved or animated: `WD_SBLIT` its old 16 x 16 from the
   background picture, then right away `WD_KBLIT` it at the new place (c2 = key 231).
   Erasing all first and drawing all after leaves sprites missing from some video frames
   (flicker). Where two sprites overlap, redraw the one an erase cut into (the game
   template's `draw`).
5. A changed tile: patch the picture in memory (CPU), `WD_SBLIT` that tile.
6. HUD text: `WD_TEXT` with paper (font 1, fixed 8 x 12) only when the value changes.

Flicker-free alternative (costs CPU): compose sprite + background in a small buffer with the
CPU and `WD_BLIT` the buffer (one call per sprite; what Solitaire does when dragging).

## Movement and collision

- Positions in pixels (16-bit), speeds of 1-3 pixels per step.
- Tile collision: test the sprite's box inset by 2 pixels (corners) against the map:
  index = (y / 16) * width + x / 16. Move each axis separately so the player slides
  along walls.
- Turning into corridors on a grid is fiddly at 2 pixels a step: when blocked on one axis
  and within 6 pixels of alignment on the other, nudge towards the tile boundary (the
  template's `nudge`).
- Sprite-sprite: |dx| < 12 and |dy| < 12 for 16 x 16 sprites.
- Random numbers: a 16-bit xorshift seeded from `SYS_UPTIME` (template's `random`).

## Input

```asm
; WE_KEY: usage at ev+2, down flag at ev+5 (byte); keytab: {usage, bit} words
        lda     ev+5
        and     #$00FF
        beq     @up
        lda     bit
        tsb     z:keys
        ...
@up:    lda     bit
        trb     z:keys
```
Mouse: WE_BUTTON (`ev+2` x, `ev+4` y, `ev+6` bit 0 = left pressed); for a paddle that
follows the pointer, open the window with WF_HOVER and use WE_MOTION, or poll
`SYS_WMOUSE` once per step. Avoid Alt / F10 / F12 / ctrl+W as game keys.

## Sound effects

Per voice: pitch, pitch step, volume, volume step, ticks left; each tick write AUDF
(register 2 v) and AUDC (2 v + 1 = distortion << 4 | volume: $A0 pure tone, $80 noise).
f = 63921 / (2 (AUDF + 1)) Hz. The kernel silences a program's channels when it ends
(Horizon 0.15). The UI's chime takes a channel no program uses.

## States and screens

title -> play -> game over -> title. Draw a panel (WD_FILL + WD_FRAME) over the playfield
with centred text (`SYS_WTWIDTH` for the width). Space or a click starts; Esc goes back
(on the title: quits). Keep a game menu: `Game: New game / - / Quit`.

## Checklist before calling it done

- Plays from the title through a round to game over, by script (`key right 800`,
  `click`), with shots of each state; looked at every shot.
- No `[kill]`, no blitter warnings in emu.err, sound writes in emu.err (`--log-sound`,
  `--log-lau`).
- Full screen: Alt+Esc / Alt+Tab in the script (`{alt-esc}`, `{alt-tab}`): the desktop comes
  back, the game pauses, then returns as it was.
- Exit (Esc on the title, close box) leaves no sound playing and stops the window system
  only if it started it.
