#!/usr/bin/env python3
"""mk23.py [DIR] - the test card's additions for the 0.23 sessions (run in a copy of the card,
by tests/shots.sh's PREP): a clock (/SYSTEM/CLOCK: print jobs get running times), /Atari for
the folder disk (8.3 names, names Atari DOS cannot show, a 20,000-byte file, a folder inside),
a BASIC listing in /Desktop (PROG.BAS: Run in Atari from its icon) and an Atari listing with
$9B line ends (/HELLO.LST: Run in Atari from Files). The folder disk's numbers for /Atari: 5
files shown (A.B, BIG.DAT, GAME.XEX, HELLO.BAS, NOTES.TXT), 4 left out (long name.txt,
TOOLONGNAME.TXT, 1ABC.TXT, X.ABCD), 707 - 164 = 543 free sectors."""
import os
import sys

d = sys.argv[1] if len(sys.argv) > 1 else '.'
os.makedirs(os.path.join(d, 'SYSTEM'), exist_ok=True)
with open(os.path.join(d, 'SYSTEM', 'CLOCK'), 'w') as f:
    f.write('2026-11-18 15:30:00\n')
a = os.path.join(d, 'Atari')
os.makedirs(os.path.join(a, 'sub'), exist_ok=True)
for n in ('HELLO.BAS', 'GAME.XEX', 'notes.txt', 'long name.txt', 'TOOLONGNAME.TXT', 'A.B',
          '1ABC.TXT', 'X.ABCD', 'sub/INSIDE.TXT'):
    with open(os.path.join(a, n), 'w') as f:
        f.write('hi\n')
with open(os.path.join(a, 'BIG.DAT'), 'wb') as f:
    f.write(bytes(i & 0xFF for i in range(20000)))
os.makedirs(os.path.join(d, 'Desktop'), exist_ok=True)
with open(os.path.join(d, 'Desktop', 'PROG.BAS'), 'w') as f:
    f.write('10 PRINT "HELLO FROM HORIZON"\n20 GOTO 10\n')
with open(os.path.join(d, 'HELLO.LST'), 'wb') as f:
    f.write(b'10 PRINT "HELLO"\x9b20 END\x9b')
