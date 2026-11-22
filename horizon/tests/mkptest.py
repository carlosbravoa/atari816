#!/usr/bin/env python3
"""mkptest.py PTEST.PRG CARD - (0.28) the program files of make test-28, made from PTEST.PRG
(user/ptest.s) in CARD/BIG:

  PTEST.PRG     PTEST itself (also put in CARD/SYSTEM/TESTS, where the shell finds "ptest")
  SMALLT.PRG    PTEST + data: 4,000 bytes in all, ending in "PTESTEND" (below 64 KB: loaded
                whole, as before 0.28)
  UNDER.PRG     the same, 65,535 bytes: the largest file loaded whole
  EDGE.PRG      the same, 65,536 bytes: the smallest file read in part (0.28)
  PTESTBIG.PRG  the same, 100,000 bytes
  JUNK.PRG      70,000 bytes that are not an o65 file: refused (EINVAL)
  FAR.PRG       PTEST with 300 header options of 255 bytes before its text, 100,000 bytes: its
                o65 does not end in the first 65,535 bytes: refused (EINVAL)

The data after the o65 is pseudo-random bytes (the same each time), never zero for long:
if the loader copied it into the program's memory, PTEST's bss would not be clear."""
import os
import random
import sys

prg, card = sys.argv[1], sys.argv[2]
code = open(prg, "rb").read()
d = os.path.join(card, "BIG")
os.makedirs(d, exist_ok=True)
rnd = random.Random(28)


def filler(n):
    return bytes(rnd.randrange(1, 256) for _ in range(n))


def put(name, data):
    with open(os.path.join(d, name), "wb") as f:
        f.write(data)


def tailed(total):
    assert total >= len(code) + 8
    return code + filler(total - len(code) - 8) + b"PTESTEND"


put("PTEST.PRG", code)
with open(os.path.join(card, "SYSTEM", "TESTS", "PTEST.PRG"), "wb") as f:
    f.write(code)
put("SMALLT.PRG", tailed(4000))
put("UNDER.PRG", tailed(65535))
put("EDGE.PRG", tailed(65536))
put("PTESTBIG.PRG", tailed(100000))
put("JUNK.PRG", filler(70000))
# the header (26 bytes) ends with the options: 300 of 255 bytes go in before ld65's own
opts = b"".join(bytes([255, 0x7F]) + filler(253) for _ in range(300))
far = code[:26] + opts + code[26:]
put("FAR.PRG", far + filler(100000 - len(far)))
