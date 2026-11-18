#!/usr/bin/env python3
"""contact.py - several screenshots on one sheet, to look at a whole run at once.

    contact.py OUT.png SHOT.png ... [--cols N] [--half | --full] [--crop X,Y,W,H]

Shots from run816.py are 1280 x 720 (the monitor picture: every pixel of the 640 x 360
screen is 2 x 2). --half (the default) shrinks them to 640 x 360: one pixel of the
sheet is one screen pixel, so coordinates read off the sheet are screen coordinates
(for 'move X Y' in an input script). --crop takes a part of each shot, in screen pixels.
Each shot is labelled in its top left corner with the number in its file name (shot7.png:
7), whatever order the shell listed them in. Needs Pillow.
"""
import os
import re
import sys

from PIL import Image, ImageDraw


def main():
    a = sys.argv[1:]
    if len(a) < 2 or a[0] in ('-h', '--help'):
        print(__doc__); return 0
    cols, scale, crop = 2, 0.5, None
    files = []
    i = 0
    while i < len(a):
        if a[i] == '--cols': cols = int(a[i + 1]); i += 2
        elif a[i] == '--half': scale = 0.5; i += 1
        elif a[i] == '--full': scale = 1.0; i += 1
        elif a[i] == '--crop': crop = [int(v) for v in a[i + 1].split(',')]; i += 2
        else: files.append(a[i]); i += 1
    out, shots = files[0], files[1:]
    # natural order: shot2 before shot10
    shots.sort(key=lambda f: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', f)])
    ims = []
    for f in shots:
        im = Image.open(f).convert('RGB')
        if crop:
            x, y, w, h = crop
            im = im.crop((x * 2, y * 2, (x + w) * 2, (y + h) * 2))
        im = im.resize((int(im.size[0] * scale), int(im.size[1] * scale)), Image.NEAREST)
        ims.append(im)
    w = max(im.size[0] for im in ims)
    h = max(im.size[1] for im in ims)
    cols = min(cols, len(ims))
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * (w + 4), rows * (h + 4)), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    for k, im in enumerate(ims):
        x, y = (k % cols) * (w + 4), (k // cols) * (h + 4)
        sheet.paste(im, (x, y))
        m = re.search(r'(\d+)\D*$', os.path.basename(shots[k]))
        label = m.group(1) if m else str(k + 1)
        d.rectangle((x, y, x + 6 + 6 * len(label), y + 11), fill=(255, 255, 0))
        d.text((x + 3, y), label, fill=(0, 0, 0))
    sheet.save(out)
    print(f'{out}: {len(ims)} shots')
    return 0


if __name__ == '__main__':
    sys.exit(main())
