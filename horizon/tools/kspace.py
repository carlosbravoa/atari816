#!/usr/bin/env python3
"""kspace.py MAP FILE - (0.18) the kernel's space, from ld65's map: prints what is used and
left in each part and fails when the file is too large for the I/O processor's loader
(it reads at most $FF00 bytes to $01:0000) or the bank $01 image and BSS reach $F000."""
import os
import re
import sys

mp, kfile = sys.argv[1], sys.argv[2]
seg = {}
for line in open(mp):
    m = re.match(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s', line)
    if m:
        seg[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16))
size = os.path.getsize(kfile)
bss_end = seg['BSS'][1] + 1 if 'BSS' in seg else 0
img = seg['CODE'][2] + seg.get('RODATA', (0, 0, 0))[2]
k2 = seg.get('K2CODE', (0, 0, 0))[2] + seg.get('K2DATA', (0, 0, 0))[2]
k0 = seg.get('K0BSS', (0, 0, 0))[2]
print("kernel: %d bytes (bank $01 image %d + k2.s %d; loader limit 65280)" % (size, img, k2))
print("kernel: bank $01 image and BSS end at $01:%04X: %d bytes left below $F000"
      % (bss_end & 0xFFFF, 0xF000 - (bss_end & 0xFFFF)))
print("kernel: k2.s %d of 7680 bytes in bank 0 ($E100-$FEFF): %d left; its bank 0 variables %d of 3328: %d left"
      % (k2, 7680 - k2, k0, 3328 - k0))
bad = []
if size > 0xFF00:
    bad.append("the file is larger than the loader reads ($FF00)")
if (bss_end & 0xFFFF) > 0xF000:
    bad.append("the bank $01 BSS runs into the video-state block")
if bad:
    for b in bad:
        print("kernel: " + b, file=sys.stderr)
    sys.exit(1)
