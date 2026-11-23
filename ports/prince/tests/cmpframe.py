#!/usr/bin/env python3
"""tests/cmpframe.py - the Atari816's screen at a replay tick against the reference build's
(upstream SDLPoP on a PC, host/refhook.c's POP_REF_SHOTS) at the same tick.

  cmpframe.py SHOT816.png HOST.png VIEW_Y GAME [--diff OUT.png] [--max N]

The 816 shows 320 x 180 (each pixel 4 x 4 in emu816's 1280 x 720 picture): in a room the
rows VIEW_Y .. VIEW_Y + 171 of the game's 320 x 200 screen, then the status line (rows 192 to
199); a whole-screen picture (GAME 0) rows VIEW_Y .. VIEW_Y + 179. Colours are compared
exactly (the palette is the DOS game's, 6 bits a component). Prints the differing pixels;
exit 1 when more than N (default 0)."""
import argparse
import sys

from PIL import Image


def screen816(path):
    im = Image.open(path).convert("RGB")
    if im.size != (1280, 720):
        raise SystemExit("cmpframe: %s is not 1280 x 720" % path)
    return im.resize((320, 180), Image.NEAREST)


def expected(path, view_y, game):
    h = Image.open(path).convert("RGB")
    out = Image.new("RGB", (320, 180))
    if game:
        out.paste(h.crop((0, view_y, 320, view_y + 172)), (0, 0))
        out.paste(h.crop((0, 192, 320, 200)), (0, 172))
    else:
        out.paste(h.crop((0, view_y, 320, view_y + 180)), (0, 0))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument("host")
    ap.add_argument("view_y", type=int)
    ap.add_argument("game", type=int)
    ap.add_argument("--diff")
    ap.add_argument("--max", type=int, default=0)
    a = ap.parse_args()
    s = screen816(a.shot)
    e = expected(a.host, a.view_y, a.game)
    sp, ep = s.load(), e.load()
    bad = 0
    d = Image.new("RGB", (320, 180))
    dp = d.load()
    for y in range(180):
        for x in range(320):
            if sp[x, y] != ep[x, y]:
                bad += 1
                dp[x, y] = (255, 0, 255)
            else:
                r, g, b = sp[x, y]
                dp[x, y] = (r // 3, g // 3, b // 3)
    if a.diff:
        w = Image.new("RGB", (960, 180))
        w.paste(e, (0, 0))
        w.paste(s, (320, 0))
        w.paste(d, (640, 0))
        w.resize((1920, 360), Image.NEAREST).save(a.diff)
    print("cmpframe: %s: %d pixels differ" % (a.shot, bad))
    sys.exit(1 if bad > a.max else 0)


if __name__ == "__main__":
    main()
