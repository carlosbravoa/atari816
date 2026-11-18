# Pixel art for the Atari816

## The display

- You draw at 640 x 360; the monitor shows every pixel as a 2 x 2 block (1280 x 720). A
  16 x 16 sprite is 32 x 32 on the monitor, chunky like an 8-bit game's. Design at 1:1 and
  look at it at 2 x or more (`img2inc.py --preview art.png --scale 8`, or a run816 shot).
- 8 bits per pixel from one shared 256-colour palette. No per-window palettes: use the
  fixed entries.

## The palette

| Entries | | In img2inc text art |
| --- | --- | --- |
| 0-15 | UI colours (C_BLACK 0, C_WHITE 1, C_RED 11, C_YELLOW 12, C_GREEN 13, C_ORANGE 14, ...) | `k = 0` |
| 16-231 | the 6 x 6 x 6 cube: 16 + 36 r + 6 g + b, each level 0, 51, 102, 153, 204, 255 | `r = cube 5 1 0` |
| 232-255 | 24 greys, 8 to 238 | `g = grey 12` |

- Ramps for shading run along the cube: a red ball `cube 5 1 1` (body), `cube 5 3 3`
  (highlight), `cube 3 0 0` (shade), `0` (outline).
- 231 (cube 5 5 5, white) is the SDK's transparent key colour: use `1` (C_WHITE) for white.
- `#RRGGBB` in the legend takes the nearest palette colour: fine for a start, but name the
  cube levels to control the result.

## What reads well at 2 x

- **Outline sprites** with a 1-pixel dark line (0, or a dark cube colour of the sprite's
  hue). Unoutlined sprites dissolve on busy backgrounds.
- **Big shapes, few details.** At 16 x 16: a head and two eyes, not a face. Eyes 2 x 2 with
  a 1-pixel pupil read at any size.
- **Light from the top left**: highlight on the top-left edge, shade bottom-right; the same
  for every sprite and tile.
- **Contrast between sprites and background**: dark, low-saturation backgrounds (cube 0 1 1,
  cube 0 0 1), bright saturated sprites. Keep the playfield background calm (a few
  speckles, not noise).
- **Tiles** of 16 x 16 (or 8 x 8) that repeat without a visible seam: bricks offset by half
  a brick each row, a mortar line on one edge only.
- **Animation**: 2 frames are enough for walking or wobbling at 4-8 steps per frame; move
  sprites 1-2 pixels per step (at 50 steps a second = 50-100 pixels a second).
- Text in games: the fixed font (8 x 12) for status lines; for a title, letters spaced
  ("G E M   R U N") or your own big 1 bpp font (SDK/tools/font2inc.py).
- Avoid 1-pixel checkerboards over large areas (they shimmer on some monitors at 2 x) and
  pure 0-255 full-saturation pairs next to each other (red on blue vibrates).

## img2inc text art

```
; player.txt - two 8 x 8 frames
. = key
k = 0
y = cube 5 4 0
w = 1

..kkkk..
.kyyyyk.
kywkywk.
kyyyyyyk
kyykkyyk
.kyyyyk.
..k..k..
.kk..kk.

..kkkk..
.kyyyyk.
kywkywk.
kyyyyyyk
kyyyyyyk
.kykkyk.
..k..k..
..kk.kk.
```
`python3 SDK/tools/img2inc.py player.txt -o player.inc --name player --preview p.png`
gives `player_W = 8`, `player_H = 8`, `player_N = 2`, `player_SIZE = 64` and the bytes at
`player` (frame k at `player + k * player_SIZE`). Blit with WD_KBLIT, c2 = 231.
Every row of a frame must have the same length; frames are separated by an empty line;
`;` starts a comment.

PNG art (from any paint program) works too: transparent pixels (alpha < 128) become the
key, colours the nearest palette entry; `--tile 16x16` cuts a sheet into frames.
