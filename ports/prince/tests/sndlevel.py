#!/usr/bin/env python3
"""tests/sndlevel.py WAV CONSOLE - the loudness of every sound of "PRINCE.PRG sndtest" (each
sound once, "prince: sound N" printed as it starts, recorded with run816 --wav: the board's
mix of Lau and the OPL2), the digital effects against the songs: the median rms (100 ms
windows above the noise) of each group must be within 3 dB of the other's, no sample may
clip and the loudest peak must leave 3 dB of headroom. POP.SND's kinds: songs 24-30, 32,
33, 35-37, 39-41, 43, 50, 52-56; PC-speaker sounds (POKEY: not in the recording) 31, 34,
38, 42; the rest digital."""
import re
import sys
import wave

import numpy as np

SONGS = {24, 25, 26, 27, 28, 29, 30, 32, 33, 35, 36, 37, 39, 40, 41, 43, 50, 52, 53, 54, 55, 56}
SPEAKER = {31, 34, 38, 42}


def db(x):
    return 20 * np.log10(max(x, 1e-9) / 32768)


def main():
    w = wave.open(sys.argv[1])
    sr, n = w.getframerate(), w.getnframes()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).reshape(-1, w.getnchannels()).astype(float)
    m = a.mean(axis=1)
    ev = []
    for line in open(sys.argv[2], errors="replace"):
        g = re.match(r"\[\s*([\d.]+)\] prince: sound (\w+)", line)
        if g:
            ev.append((float(g.group(1)), g.group(2)))
    lev = {"digi": [], "song": []}
    for (t, s), (t2, _) in zip(ev, ev[1:]):
        if not s.isdigit() or int(s) in SPEAKER:
            continue
        seg = m[int(t * sr):int(t2 * sr)]
        win = sr // 10
        k = len(seg) // win
        r = np.sqrt((seg[:k * win].reshape(k, win) ** 2).mean(axis=1)) if k else np.zeros(0)
        act = r[r > 30]
        if len(act):
            lev["song" if int(s) in SONGS else "digi"].append(db(np.sqrt((act ** 2).mean())))
    peak = db(np.abs(a).max())
    clip = int((np.abs(a) >= 32767).sum())
    md, ms = float(np.median(lev["digi"])), float(np.median(lev["song"]))
    print("sndlevel: %d effects, median rms %.1f dBFS; %d songs, median rms %.1f dBFS; "
          "peak %.1f dBFS, %d clipped samples" % (len(lev["digi"]), md, len(lev["song"]), ms, peak, clip))
    ok = len(lev["digi"]) >= 25 and len(lev["song"]) >= 20 and abs(md - ms) <= 3 and clip == 0 and peak <= -3
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
