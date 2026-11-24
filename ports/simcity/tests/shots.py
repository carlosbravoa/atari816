#!/usr/bin/env python3
"""tests/shots.py SUMS PNG... [--update]: each picture's MD5 (of its RGB pixels) against
SUMS ("name md5" lines, the picture's file name); --update writes SUMS. Prints a summary."""
import hashlib
import os
import sys
from PIL import Image
args = [a for a in sys.argv[1:] if a != '--update']
sums, pngs = args[0], args[1:]
got = {os.path.basename(p): hashlib.md5(Image.open(p).convert('RGB').tobytes()).hexdigest()
       for p in pngs}
if '--update' in sys.argv:
    with open(sums, 'w') as f:
        for k in sorted(got):
            f.write('%s %s\n' % (k, got[k]))
    print('%d checksums written to %s' % (len(got), sums))
    sys.exit(0)
want = dict(l.split() for l in open(sums) if l.strip()) if os.path.exists(sums) else {}
bad = [k for k in want if got.get(k) != want[k]]
if not want or bad:
    print('%d of %d pictures differ (%s)' % (len(bad), len(want), ' '.join(bad) or 'no checksums'))
    sys.exit(1)
print('%d pictures as their checksums' % len(want))
