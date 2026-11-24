#!/usr/bin/env python3
"""fcback.py BUILD - (0.31) FreeCell's colours in the tests/fcback.keys session: its table and
a card (screen points 520, 300 and 510, 150; the shots are 1280 x 720) must show FreeCell's own
colours in all three shots: in front (1), behind Files (2) and behind Settings (3). Before 0.31
its palette entries showed the system cube's greens while it was not in front."""
import sys
from PIL import Image
want = {(1040, 600): (30, 72, 112), (1020, 300): (250, 248, 238)}   # table, card (fc_rgb)
bad = []
for n in (1, 2, 3):
    im = Image.open('%s/fcback%d.ppm' % (sys.argv[1], n)).convert('RGB')
    for p, c in want.items():
        if im.getpixel(p) != c:
            bad.append('shot %d at %d, %d: %s, not %s' % (n, p[0] // 2, p[1] // 2, im.getpixel(p), c))
print('\n'.join(bad))
sys.exit(1 if bad else 0)
