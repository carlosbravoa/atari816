#!/usr/bin/env python3
"""tests/shots.py - checksums of the screen in emu816's pictures (the 320 x 180 screen out of
the 1280 x 720 picture: MD5 of its RGB pixels), against a list (the pictures show the game's
art, which is not in the repository: only their checksums are).

  shots.py LIST PICTURE... [--update]     LIST lines: "NAME MD5"; NAME = the picture's file
                                          name (auto3.png), or NAME@Y0-Y1: only the screen's
                                          rows Y0 to Y1 - 1 (shot2.png@172-180: the status
                                          line); --update writes LIST anew (keeping each
                                          name's rows)

Before --update, look at the pictures, and where the PC's reference build can draw the
same frame, compare them with it (tests/cmpframe.py: the replays' frames were equal pixel
for pixel when these lists were made)."""
import hashlib
import os
import sys

from PIL import Image


def md5(path, rows=None):
    im = Image.open(path).convert("RGB").resize((320, 180), Image.NEAREST)
    if rows:
        im = im.crop((0, rows[0], 320, rows[1]))
    return hashlib.md5(im.tobytes()).hexdigest()


def split(key):
    """NAME@Y0-Y1 -> (NAME, (Y0, Y1)); NAME -> (NAME, None)"""
    if "@" not in key:
        return key, None
    name, r = key.split("@")
    y0, y1 = r.split("-")
    return name, (int(y0), int(y1))


def main():
    args = [a for a in sys.argv[1:] if a != "--update"]
    update = "--update" in sys.argv
    lst, pics = args[0], args[1:]
    paths = {os.path.basename(p): p for p in pics}
    keys = [l.split()[0] for l in open(lst) if l.strip()] if os.path.exists(lst) else []
    rows = {split(k)[0]: k for k in keys}
    got = {}
    for name, p in paths.items():
        k = rows.get(name, name)
        got[k] = md5(p, split(k)[1])
    if update:
        with open(lst, "w") as f:
            for k in sorted(got):
                f.write("%s %s\n" % (k, got[k]))
        print("shots: %s: %d checksums written" % (lst, len(got)))
        return 0
    want = dict(l.split() for l in open(lst) if l.strip())
    bad = 0
    for k in sorted(want):
        if k not in got:
            print("FAIL  picture %s: not taken" % k)
            bad += 1
        elif got[k] != want[k]:
            print("FAIL  picture %s: not as %s" % (k, lst))
            bad += 1
    if not bad:
        print("PASS  %d pictures as %s" % (len(want), lst))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
