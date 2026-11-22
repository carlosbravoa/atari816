#!/usr/bin/env python3
"""oplwav.py FILE.wav - checks emu816 --wav's recording of tests/asm/opltone.bin (REV $0C):
a 440 Hz sine on OPL2 channel 0 for 1 s, then released. Both sides equal (the OPL2 is mono);
the pitch over the held part (zero crossings, +-0.5 Hz); its peak (one operator at total level
0, channel 0 at 0 dB in JTOPL's sum, times 3 in the mix: 12,000 to 12,300); the note sounds 1.0 to 1.1 s (above 200:
the release, rate 8, is quick); then silence (the last 0.5 s within +-6: a silent operator still
gives -1 in the negative half of its phase). Prints the measures; exit 1 on a failure."""
import struct
import sys

raw = open(sys.argv[1], 'rb').read()
d = raw[44:]
s = struct.unpack('<%dh' % (len(d) // 2), d)
L, R = s[0::2], s[1::2]
loud = [i for i, v in enumerate(L) if abs(v) > 200]
if not loud:
    print('silent')
    sys.exit(1)
a, b = loud[0], loud[-1]
x = L[a + 4800:a + 43200]
z = [i for i in range(1, len(x)) if x[i - 1] < 0 <= x[i]]
f = (len(z) - 1) * 48000 / (z[-1] - z[0]) if len(z) > 2 else 0
peak = max(abs(v) for v in L[a:a + 43200])
tail = max(abs(v) for v in L[-24000:])
dur = (b - a) / 48000
ok = L == R and abs(f - 440) < 0.5 and 12000 <= peak <= 12300 and 1.0 <= dur <= 1.1 and tail <= 6 and \
    len(L) > b + 24000
print('%.2f Hz, peak %d, %.3f s, then %d at most%s' % (f, peak, dur, tail, '' if L == R else ', sides differ'))
sys.exit(0 if ok else 1)
