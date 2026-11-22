#!/usr/bin/env python3
"""wavcheck.py WAV: the emulator's recording of the scripted game (Lau and the OPL2, 48 kHz
stereo): the title's music must be heard (seconds 2-8: the OPL2 alone), the game's sound
loud enough and hardly ever clipped (the music's level: tools/mkdata.py, OPL_ATT)."""
import array
import math
import sys
import wave

w = wave.open(sys.argv[1])
rate, ch = w.getframerate(), w.getnchannels()
a = array.array('h', w.readframes(w.getnframes()))
step = rate * ch


def rms(lo, hi):
    seg = a[lo * step:hi * step]
    return math.sqrt(sum(x * x for x in seg) / max(1, len(seg)))


title = rms(2, 8)
game = rms(30, 45)
clipped = sum(1 for x in a if x >= 32700 or x <= -32700)
frac = clipped / max(1, len(a))
ok = title > 500 and game > 500 and frac < 0.0005
print(('PASS' if ok else 'FAIL') + '  sound recorded: the title\'s music %d rms, the game %d rms, '
      '%d samples clipped (%.3f %%)' % (title, game, clipped, frac * 100))
sys.exit(0 if ok else 1)
