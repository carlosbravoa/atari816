#!/usr/bin/env python3
"""tests/oplcheck.py - the OPL2 register writes the Atari816 made (emu816 --log-opl-us, in
emu.err) against a song's IMF stream in POP.SND (tools/midi2imf.c: SDLPoP's own MIDI
interpretation; host/ checks that one against upstream itself).

  oplcheck.py POP.SND SOUND EMU.ERR [--seconds S] [--slack MS]

From the first write of the song's stream on, the emulator's writes must be the stream's
(register and value) in order for its first S seconds (default 10), each no more than
--slack ms (default 40: the stream is played once a vertical blank) away from its own time
relative to the first write. Prints the count and the worst timing; exit 1 on a mismatch."""
import argparse
import re
import struct
import sys


def imf_of(path, sid):
    b = open(path, "rb").read()
    typ, _, hz, off, n, ms = struct.unpack_from("<BBHIII", b, 6 + 16 * sid)
    if typ != 2:
        raise SystemExit("oplcheck: sound %d is not music" % sid)
    out, t = [], 0.0
    for k in range(0, n, 4):
        reg, val, delay = struct.unpack_from("<BBH", b, off + k)
        out.append((t, reg, val))
        t += delay * 1e6 / hz
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snd")
    ap.add_argument("sound", type=int)
    ap.add_argument("emu")
    ap.add_argument("--seconds", type=float, default=10)
    ap.add_argument("--slack", type=float, default=40)
    a = ap.parse_args()
    want = [w for w in imf_of(a.snd, a.sound) if w[0] <= a.seconds * 1e6]
    got = []
    for ln in open(a.emu, errors="replace"):
        m = re.match(r"opl (\d+) \$([0-9A-Fa-f]+) = \$([0-9A-Fa-f]+)", ln)
        if m:
            got.append((int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16)))
    # the stream's start: the first place its first 8 writes appear in order
    head = [(r, v) for _, r, v in want[:8]]
    start = None
    for i in range(len(got) - 8):
        if [(r, v) for _, r, v in got[i:i + 8]] == head:
            start = i
            break
    if start is None:
        print("oplcheck: FAIL: the song's first writes are not in the log (%d OPL writes)" % len(got))
        return 1
    t0 = got[start][0]
    worst = 0.0
    for k, (t, r, v) in enumerate(want):
        if start + k >= len(got):
            print("oplcheck: FAIL: the log ends after %d of %d writes" % (k, len(want)))
            return 1
        gt, gr, gv = got[start + k]
        if (gr, gv) != (r, v):
            print("oplcheck: FAIL: write %d is $%02X = $%02X, the stream has $%02X = $%02X"
                  % (k, gr, gv, r, v))
            return 1
        d = abs((gt - t0) - t) / 1000.0
        worst = max(worst, d)
        if d > a.slack:
            print("oplcheck: FAIL: write %d is %.1f ms from its time" % (k, d))
            return 1
    print("oplcheck: %d writes of sound %d (%.0f s) as the stream, at most %.1f ms off"
          % (len(want), a.sound, a.seconds, worst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
