#!/usr/bin/env python3
"""maskshot.py MASK PREFIX N - (0.31) paint the parts of a session's pictures that move with
the clock and not with the session's state (a song's level meters, its row and position,
the menu bar's free memory and uptime) in one colour, before shots.sh takes their md5: the
rest of each picture is still compared, and the comparison no longer depends on how fast
the CPU or the kernel is.

MASK lines: "SHOTS X0 Y0 X1 Y1" (1280 x 720 pixels, X1 Y1 excluded), SHOTS "*" (all) or a
comma list of shot numbers; '#' starts a comment. The pictures PREFIX1.ppm .. PREFIXN.ppm
are changed in place (magenta)."""
import sys
from PIL import Image

mask, prefix, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
rects = []
for ln in open(mask):
    ln = ln.split('#')[0].split()
    if not ln:
        continue
    shots = range(1, n + 1) if ln[0] == '*' else [int(s) for s in ln[0].split(',')]
    rects.append((set(shots), tuple(int(v) for v in ln[1:5])))
for i in range(1, n + 1):
    rs = [r for s, r in rects if i in s]
    if not rs:
        continue
    p = '%s%d.ppm' % (prefix, i)
    im = Image.open(p).convert('RGB')
    for r in rs:
        im.paste((255, 0, 255), r)
    im.save(p)
