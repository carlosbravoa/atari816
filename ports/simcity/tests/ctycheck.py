#!/usr/bin/env python3
"""tests/ctycheck.py FILE.CTY DUMP: a saved city (upstream's format: 27,120 bytes, big-endian
16-bit words: six histories of 240, MiscHis's 120, the map's 12,000 by columns) against
simtest's dump of the state it was saved from: the map, the funds (MiscHis 50-51) and the
time (MiscHis 8-9)."""
import struct
import sys
data = open(sys.argv[1], 'rb').read()
dump = open(sys.argv[2]).read().split('\n')
assert len(data) == 27120, len(data)
w = struct.unpack('>13560h', data)
misc = w[6 * 240:6 * 240 + 120]
mp = w[6 * 240 + 120:]
time_, funds = (int(v) for v in dump[0].split()[1:4:2])
ok = True
for y in range(100):
    row = dump[1 + y]
    for x in range(120):
        if int(row[4 * x:4 * x + 4], 16) != (mp[x * 100 + y] & 0xFFFF):
            print('map (%d, %d) differs' % (x, y))
            ok = False
            break
f = ((misc[50] & 0xFFFF) << 16) | (misc[51] & 0xFFFF)
t = ((misc[8] & 0xFFFF) << 16) | (misc[9] & 0xFFFF)
if f != funds or t != time_:
    print('funds %d / %d, time %d / %d' % (f, funds, t, time_))
    ok = False
sys.exit(0 if ok else 1)
