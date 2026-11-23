#!/usr/bin/env python3
"""shot816.py RAM SHOT.ppm [--no-scroll] - check the PC link's screenshot (core/tools/
a816_screen.py, what `atari.py shot816` uses on the board) against emu816's own picture.

RAM is emu816's --dump-ram of a run, SHOT.ppm its --shot at exit (the same moment). The
tool reads the RAM as it would read the board's memory over the link (the kernel's
video-state block, its full-screen scroll set, the framebuffer) and makes its picture;
each of its pixels must be the colour of emu816's (1280 x 720: 2 x 2 or 4 x 4 pixels a
screen pixel), the mouse pointer included. Prints PASS or FAIL and exits 1 on a
difference.
shot816.py --fs RAM: (Horizon 0.30) the video-state block's scroll set (version 2) must be
the kernel's own variables, as the code search finds them (a full-screen program's RAM).
Example (Xargon's game, scrolled and split; make -C ports/xargon first):
    emu816 ... --shot x.ppm --dump-ram x.ram HORIZON.SYS; shot816.py x.ram x.ppm
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "core", "tools"))
import a816_screen  # noqa: E402


class RamLink:
    """peek816 / sum816 of atari_link.AtariLink over a RAM image"""
    def __init__(self, ram):
        self.ram = ram

    def peek816(self, addr, length=None, width=None, rows=1, stride=0, rle=True, xor2=False):
        if width is None:
            width, rows, stride = length, 1, 0
        out = bytearray()
        for r in range(rows):
            a = (addr + r * stride) & 0xFFFFFF
            chunk = self.ram[a:a + width] if a < len(self.ram) else b""
            out += chunk + bytes(width - len(chunk))
        return bytes(out)

    def sum816(self, addr, length):
        return sum(self.peek816(addr, length)) & 0xFFFF


def read_ppm(path):
    d = open(path, "rb").read()
    parts, i = [], 0
    while len(parts) < 4:
        while d[i:i + 1].isspace():
            i += 1
        j = i
        while not d[j:j + 1].isspace():
            j += 1
        parts.append(d[i:j])
        i = j
    w, h = int(parts[1]), int(parts[2])
    return w, h, d[i + 1:i + 1 + w * h * 3]


def fs_compare(ram):
    """(Horizon 0.30) the video-state block's full-screen scroll set (version 2) against the
    kernel's own variables found by the code search (version 1's way)"""
    link = RamLink(ram)
    vs = a816_screen.video_state(link)
    old = a816_screen.scroll_state(link)
    new = vs and vs["fs"]
    if not new or not old or any(new[k] != old[k] for k in old):
        print(f"FAIL  shot816 --fs: the block (version {vs and vs['version']}) {new}, the code {old}")
        return 1
    print(f"PASS  shot816 --fs: the block's scroll set (version {vs['version']}) is the kernel's: {new}")
    return 0


def main():
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "--fs":
        return fs_compare(open(a[1], "rb").read())
    if len(a) < 2 or a[0] in ("-h", "--help"):
        sys.exit(__doc__)
    ram = open(a[0], "rb").read()
    ew, eh, erg = read_ppm(a[1])
    shot = a816_screen.capture(RamLink(ram), scroll="--no-scroll" not in a)
    s = ew // shot.width
    bad, first = 0, None
    for y in range(shot.height):
        for x in range(shot.width):
            o = (y * shot.width + x) * 3
            e = ((y * s) * ew + x * s) * 3
            if shot.rgb[o:o + 3] != erg[e:e + 3]:
                bad += 1
                first = first or (x, y)
    info = " ".join(f"{k}={v:#x}" if k == "base" else f"{k}={v}" for k, v in shot.info.items())
    if bad:
        print(f"FAIL  shot816: {bad} of {shot.width * shot.height} pixels differ from emu816's "
              f"picture (the first at {first}) ({info})")
        return 1
    print(f"PASS  shot816: the PC tool's picture is emu816's, {shot.width}x{shot.height} ({info})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
