# Game patterns

How to structure an action game on Horizon, with the costs from
[performance.md](performance.md). Complete, tested programs: `sdk/examples/deepdive` (full
screen: scrolling, sprites, one draw list a frame, Horizon 0.18), `sdk/templates/game` (Gem
Run: a window, a timer loop, dirty rectangles with win_draw) and `sdk/examples/lantern` (a
finished arcade game in a window).

## Capabilities and limits

- **Available** (Horizon 0.18 on REV $0B, the emulator's default):
  - a window (framed, or WF_PLAIN up to 640 x 344 under the menu bar), or **the whole screen**
    (`fs_enter`): 640 x 360 x 8, 640 x 360 x 4 or 320 x 180 x 8 from a framebuffer in your
    own memory, with **fine scrolling** (horizontal and vertical wrap, a split for a fixed
    panel), page flipping (`fs_enter` again with another buffer) and a **raster table** (up to
    16 palette changes at given lines);
  - **16 hardware sprites** (shared by all programs): 8 bpp 16 x 16 / 16 x 32, 4 bpp up to
    32 x 32, flips, 2x, behind the bitmap; in a window only while it has the focus and is not
    covered;
  - **frame sync**: `vsync` returns the frame counter (missed frames show), `frame`, WE_VBL;
  - **draw lists**: up to 128 fills / copies / keyed copies / 1 bpp expands / moves in one
    syscall, started by Ali in the vertical blank if requested (LS_VBL);
  - colours: the system palette, palette entries of your own (`pal_alloc`, `pal_set`; shown
    while you have the focus), all 256 in full-screen mode;
  - win_draw for a window's few operations; key down / up events, the mouse, the joysticks
    (`joystick`), a 10 ms window timer, focus events; POKEY, **Lau** (8 sample voices) and the OPL2 (REV $0C);
    64 KB banks of memory; files.
- **Not available**: other video modes than these three, raster code of your own (no
  interrupts in programs: the raster table is the kernel's), sprite collision detection,
  reading pixels back from a window (a full-screen framebuffer is your memory: read it after
  `list_wait`), scaling or rotation. Each syscall costs about 50 us and up (emulator; about
  double on the board), so: **few syscalls a frame, never redraw what did not change.**

What the calls need (ENODEV before): sprites and `fs_scroll` REV $0B; the frame counter,
command lists, the raster table and WE_VBL REV $09; Lau REV $0A. Full-screen mode, `pal_*` and
`draw_list` work on every revision (lists drawn more slowly without command lists or the
blitter).

## Game structures

Full screen (`examples/deepdive`):
- Screen: the whole screen, your framebuffer, your palette.
- Loop: `vsync`.
- Moving things: sprites (`spr_set` once a frame).
- Background: tiles drawn once; scrolling by Marga, new tiles by one list.
- Syscalls a frame: about 6.
- Requires REV $0B for sprites and scrolling.

Window with lists and sprites:
- Screen: your window, on the desktop.
- Loop: `vsync` (or WE_VBL).
- Moving things: sprites (shown while focused and not covered).
- Background: one list a frame.
- Syscalls a frame: about 5 + the events.
- Requires REV $0B for sprites.

Window with win_draw (`templates/game`):
- Screen: your window.
- Loop: WE_TICK every 20 ms.
- Moving things: erase + keyed blit per sprite.
- Background: WD_SBLIT from a picture in a bank.
- Syscalls a frame: 2 per moving sprite + the events.
- Runs on any revision.

### Full screen: vsync, one draw list, sprites

```asm
frame:  sys     SYS_VSYNC       ; a new frame (and the last list is done)
        jsr     handle          ; win_event polling: keys; WE_UNFOCUS: pause; WE_CLOSE: end
        jsr     step            ; input, rules, the camera
        jsr     draw            ; records: tiles that came into view, the panel's changes;
                                ; LS_VBL on the first; one draw_list
                                ; then fs_scroll (the camera) and one spr_set (all sprites)
        bra     frame
```

- **The framebuffer as a ring** (`examples/deepdive`): world tile (c, r) always goes to slot
  (c mod columns, r mod rows), with one column more than the screen shows and enough rows;
  the scroll registers (x2 = camx mod stride, y2 = camy mod vheight, FSC_HWRAP, vheight)
  show the slots in place. When the camera crosses a tile edge, draw the one column or row
  that comes into view: 12 or 21 records, every 8 frames at 2 pixels a frame.
- **A fixed panel** with the split: its rows below the ring (y >= vheight never wraps),
  shown by the first set of registers above the split line; the playfield by the second.
- **All in the same vertical blank**: the list with LS_VBL on its first record, `fs_scroll`
  and `spr_set` all take effect at the next blank, so a tile is never drawn into a slot that
  is still on the screen. Without LS_VBL the list would draw at once, into a column the
  current frame still shows.
- **Sprites in front of the background only**: SPR_BEHIND and colour 0 for the background
  (water, sky): sprites pass behind everything else, and behind a panel drawn in other
  colours, with no clipping code.
- **The palette**: black (`pal_set` of 256 zero entries) while the first screen is drawn, then
  your colours. Effects per line (a sky gradient, a panel in other colours): `fs_raster`.
- **Pause** on WE_UNFOCUS: the kernel has given the screen back to the desktop (Alt+Tab,
  Alt+Esc, F12, another window). Stop the samples, block on events (`win_event` with A = 0)
  until WE_FOCUS, read `frame` again. Esc / WE_CLOSE: `fs_leave`, exit.
- **Measured** (`deepdive`, emulator): about 1.8 ms of CPU a frame with every syscall, 0
  missed frames; (Horizon 0.19) 1.7 ms with its tiles as a sheet (`sheet_draw`, games.md).

### Window with draw lists and sprites

The same loop in a window: the background in your window (drawn once, by lists), sprites for
what moves. Sprites show only while your window has the focus and nothing covers its content,
and only those wholly inside it: pause on WE_UNFOCUS anyway, and keep the playfield inside
the content. Without sprites (or for more than you got), redraw the moving things with one
list a frame: for each, an LS_COPY of the background under its old place (from a picture in a
bank), then an LS_KEY at its new place, all in one list with LS_VBL on the first record: one
syscall instead of two per sprite, and no flicker (the list runs in the blank).

### Window with win_draw: dirty rectangles

What `templates/game` does, and what any revision can run. The rest of this page describes
it: a timer loop, one win_draw per erase and per draw.

## Timer loop: fixed steps

```asm
        lda     z:win
        ldx     #2              ; WE_TICK every 20 ms: 50 steps a second
        sys     SYS_WTIMER
loop:   lda     #0              ; wait for an event
        jsr     getev
        jsr     handle          ; WE_TICK: inc pending; keys: update the key mask; ...
@more:  lda     #1              ; take everything queued (poll)
        jsr     getev
        bcs     @run
        jsr     handle
        bra     @more
@run:   lda     z:pending       ; one logic step per tick that came
        beq     loop
@step:  jsr     step
        dec     z:pending
        bne     @step
        jsr     draw            ; then draw once
        bra     loop
```

- One logic step per tick keeps the game speed the same on the board and in the emulator,
  even when drawing is slow there (it then draws less often: frame skipping).
- Cap `pending` (the template takes at most 4): after a long stall (a file dialog, the
  window being dragged) the game should not run many steps at once.
- Do not use `SYS_SLEEP` for timing: events would queue up meanwhile.
- 10 ms is the tick; 2 ticks (50 Hz) or 3 (33 Hz) are good game rates. 60 Hz is not
  possible with the timer (and the video frame is 60.03 Hz, so motion always beats a little
  against it): for one step a frame use `vsync` or WE_VBL.

## Input

Keys come as events with a down flag. Keep the held keys as bits:

```asm
; WE_KEY: a = HID usage, b = modifiers | down << 8
onkey:  lda     ev+2
        ldx     #0
:       cmp     keytab,x        ; {u16 usage, u16 bit} pairs
        beq     @bit
        inx
        inx
        inx
        inx
        cpx     #KEYTABN * 4
        bcc     :-
        rts
@bit:   lda     ev+5            ; the down flag
        and     #$00FF
        beq     @up
        lda     keytab+2,x
        tsb     z:keys          ; set the bit
        rts
@up:    lda     keytab+2,x
        trb     z:keys          ; clear it
        rts
keytab: .word   $52, 1, $51, 2, $50, 4, $4F, 8, $2C, 16 ; up, down, left, right, space
KEYTABN = (* - keytab) / 4
```

- Use the joystick port's bit layout (1 up, 2 down, 4 left, 8 right, 16 fire), and OR
  joystick 1 into it in `read_joy` (SYS_JOY, Horizon 0.15: A bits 0-3 are port 1 in this
  very layout, X bit 0 its trigger). On WE_UNFOCUS clear the held keys (the kernel sends
  their releases first anyway).
- HID usages: arrows $4F right, $50 left, $51 down, $52 up; Space $2C; Enter $28; Esc $29;
  letters $04 (A) to $1D (Z); digits $1E (1) to $27 (0); left ctrl / shift / Alt are
  modifier bits, not keys (b's low byte: bit 0 ctrl, 1 shift, 2 Alt).
- Alt + a letter may open a menu and F10 opens the menu bar: do not use them as game keys.
- Held keys repeat (extra down events): harmless with a bit mask.
- Focus events (0.15): on WE_UNFOCUS the kernel has sent the held keys' releases already;
  clear the key mask anyway when the game pauses or a new round starts.
- The mouse: WE_BUTTON (a, b = position in your content, c bit 0 = left down); WE_MOTION
  while a button is held, or always with WF_HOVER on the window; `SYS_WMOUSE` reads the
  pointer at any time (a paddle that follows the mouse).

## Drawing: background picture and dirty rectangles

1. Keep the playfield's background (the tile map drawn once) in a bank of its own
   (`SYS_BALLOC`): a 320 x 192 picture is 61,440 bytes. Draw it with the CPU (tiles are
   rows of bytes: copy them with `lda [src],y` / `sta [dst],y` or MVN).
2. Show it once with one `WD_SBLIT` (source stride 320).
3. Each frame, for every sprite that moved or changed: put back the background where it
   was (`WD_SBLIT` of that 16 x 16 rectangle from the background picture), then, after
   all of them, draw every sprite at its new place (`WD_KBLIT`, the key colour skipped).
   Two calls per moving sprite.
4. When the background changes (a gem collected), change the picture in memory and blit
   that tile.

```asm
; put back the background under a sprite at playfield (x, y): t1, t2
        lda     #WD_SBLIT
        sta     blk
        lda     #320            ; the source stride (c1 | c2 << 8)
        sta     blk+1
        lda     z:t1
        sta     blk+4
        lda     z:t2
        sta     blk+6
        lda     #16
        sta     blk+8
        sta     blk+10
        lda     z:t2            ; source = background + y * 320 + x
        jsr     mul320
        clc
        adc     z:t1
        sta     blk+12
        lda     z:t0            ; the background's bank
        sta     blk+14
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
```

The erase and the draw are separate calls, so for a moment the screen shows the
background without the sprite. Keep that moment short: **erase and redraw each sprite in
consecutive calls** (and draw the overlapping ones in a fixed order). Erasing all sprites
first and drawing them all after leaves a gap in which the sprites are missing: emulator
screenshots of `examples/lantern` caught its paddle missing now and then (a frame between
the two), and on a monitor this is flicker. Where sprites overlap, erase both, then draw both. For no flicker at all, compose:

**Composing in memory (flicker-free).** Keep the scene in your bank, draw sprites into it
with the CPU (copy the background rectangle into a small buffer, put the sprite's
non-key pixels over it), and show the buffer with one `WD_BLIT`: one call per sprite,
every pixel final. Solitaire does this for dragged cards (`horizon/user/sol_draw.s`). It
costs CPU time (about 15 cycles a pixel: 0.3 ms for 16 x 16), which on the board is the
scarcer resource.

**Scrolling playfields.** `WD_COPY` moves the window's content (overlap-safe, one blitter
copy), then draw the strip that came into view. A 320 x 192 copy is about 8 ms: possible
every other frame, not every frame at 50 Hz on the board. In full-screen mode Marga scrolls
without CPU cost (`fs_scroll`): see above.

## Sprites and art

- Draw at 1:1 in screen pixels; the monitor shows every pixel as 2 x 2. 16 x 16 sprites
  look like 32 x 32 on the monitor, chunky and readable. Use a 1-pixel dark outline (C_BLACK
  or a dark cube colour) so sprites stand out on any background.
- Use the system palette: the 6 x 6 x 6 cube gives 216 colours (`cube r g b` in
  img2inc's text art), plus 24 greys. Colours of your own (Horizon 0.18): `pal_alloc` a run
  of entries and `pal_set` them; they show while your window has the focus, so other
  programs' colours are unaffected. In full-screen mode every entry is yours: name them by number
  in img2inc's text art (`a = 5`), as `examples/deepdive` does.
- Pick one key colour for transparency and never use it for a visible pixel. The SDK
  uses 231 (cube white; use `C_WHITE` = 1 for white pixels). Hardware sprites always take
  colour 0 as transparent (in their image, not on the screen).
- Frames of a sprite one after another in memory (img2inc.py writes them so): frame k is
  at `sprite + k * w * h`.
- `sdk/tools/img2inc.py` converts PNG or text art; `--preview` shows the result
  magnified, so you can look at it before building.

## Sound effects

Two `SYS_SNDW` calls per voice per tick (pitch and volume) for an envelope: rising blips,
falling tones, noise bursts that fade. Voice 0 (POKEY channel 1) is also the UI's beep
channel; a game that must keep its music free of UI beeps uses channels 2-4. Silence everything
before exit (`SYS_BEEP` with X = 0). See [sound.md](sound.md).

With Lau (Horizon 0.17) an effect is one `SYS_SPLAY` of a short sample in your own memory
(any free voice): no per-tick work. Call `SYS_SSTAT` once at the start; ENODEV: no Lau,
then use the POKEY envelopes above. See [sound.md](sound.md), "Samples". Samples can be made
at run time (`examples/deepdive`: a square wave and noise with falling loudness, a few dozen
lines); stop your voices when the game pauses. The user's sound volume (setting 4) applies
to all of them.

## Frame-synchronous loop (Horizon 0.15 and later)

`horizon/user/quabrick.s` (Quabricks) shows the other way to run a game: in play it calls
`SYS_VSYNC` (blocks until the vertical blank), then takes every queued event with
`win_event` polling (non-blocking), runs one step of the rules and draws only what changed,
early in the frame, so the picture is updated while the beam is still above it. Screens
that do not move (menus, the game-over table) block on events instead, so the program uses
no CPU there. Colour effects (a flash) change palette entries right after the vertical
blank. Quabricks measures itself with `quabrick -m`: 0.66 ms of CPU and 4.3 syscalls a
frame on average in the emulator.

## States

A state variable (title, play, game over) selects what a tick does and how keys are
handled. The title and game over screens are drawn once (a panel over the playfield, text
with the fixed font); the game then blocks until a key or a click.

## Testing

`run816.py` runs the game with an input script (`key right 500` holds a key, `click`,
`shot` takes a picture, `{alt-esc}` / `{alt-tab}` leave and re-enter a full-screen game).
`--log-sound` lists every POKEY write in `emu.err`, `--log-lau` every write to Lau. Check:
the title, a few seconds of play, a state change, the game over screen; look at every
picture (the emulator's screenshots show the full screen, the sprites, the scroll registers
and the raster table as the monitor would). Test with an older `--rev` too if those boards
matter to you: `--rev 10` has no sprites or scrolling, `--rev 8` no command lists, `--rev 7`
no blitter (it shows what is slow).
