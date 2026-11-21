#!/usr/bin/env python3
"""volbars.py NAME - (0.27) Music Player's Volume and Stereo bars in the pictures of the session
tests/NAME.src (build/NAME1.ppm ...; tests/vol27.src): each bar must be filled to its value
from the left (C_SELECT) and white for the rest, nothing else inside its bevel. The values,
shot by shot, are the ones the session sets (its comment). Exit status 0 = all as expected.

The window's content is at (120, 71) (desktop pixels; the pictures are twice that). The bars
(user/music.s): Volume at x 226, 58 wide, Stereo at x 338, 54 wide, both at y 83, 12 high,
inside a one-pixel bevel; filled = value * (inside width) / 64, as mu_draw.s's vbar draws it."""
import os
import sys
from PIL import Image

CX, CY = 120, 71
BARS = (('volume', 226, 58), ('stereo', 338, 54))
Y = 83 + 2                              # a row inside (the pointer's tip stays below it)
SELECT, WHITE, DARK = (52, 100, 204), (255, 255, 255), (76, 80, 90)
# volume, stereo after each shot
WANT = [(64, 32), (48, 32), (44, 32), (15, 32), (0, 32), (0, 14), (12, 14)]

name = sys.argv[1]
bad = 0
for i, vals in enumerate(WANT, 1):
    f = f'build/{name}{i}.ppm'
    if not os.path.exists(f):
        f = f[:-4] + '.png'
    im = Image.open(f).convert('RGB')
    for (what, bx, bw), v in zip(BARS, vals):
        y = 2 * (CY + Y)
        x0 = 2 * (CX + bx + 1)
        inner = bw - 2
        if im.getpixel((x0 - 1, y)) != DARK:
            print(f'FAIL  {name} shot {i}: no {what} bar at ({CX + bx}, {CY + Y})')
            bad = 1
            continue
        row = [im.getpixel((x0 + 2 * k, y)) for k in range(inner)]
        fill = 0
        while fill < inner and row[fill] == SELECT:
            fill += 1
        want = v * inner // 64
        rest = all(p == WHITE for p in row[fill:])
        if fill != want or not rest:
            print(f'FAIL  {name} shot {i}: the {what} bar is filled {fill} of {inner} pixels'
                  f'{"" if rest else ", other colours after it"}; {what} {v} fills {want}')
            bad = 1
sys.exit(bad)
