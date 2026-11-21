#!/usr/bin/env python3
"""o65blob.py IN.o65 OUT.bin OUT.banks - an ld65 o65 file (linked at $0100, zp at a fixed
address) as a raw block for the start of a vbcc program's text: text + data + bss (as
zeros), and the link addresses of its bank bytes (SEG entries, the bank byte of SEGADR
entries), one hex number a line, which hz/mko65.py adds to the program's relocations.
The block is loaded at the address it was linked at, so offsets (WORD, LOW, HIGH) need
no relocation; zp references stay as linked (no zp segment in the final program)."""
import sys

d = open(sys.argv[1], "rb").read()
if d[:6] != b"\x01\x00o65\x00":
    sys.exit("o65blob: not an o65 file")
mode = int.from_bytes(d[6:8], "little")
if mode & 0x6000:
    sys.exit("o65blob: 32-bit sizes or paged relocation")
h = [int.from_bytes(d[8 + 2 * i:10 + 2 * i], "little") for i in range(9)]
tbase, tlen, dbase, dlen, bbase, blen, zbase, zlen, _ = h
if tbase != 0x100 or dbase != tbase + tlen or bbase != dbase + dlen:
    sys.exit("o65blob: text/data/bss not contiguous from $0100")
p = 26
while d[p]:
    p += d[p]
p += 1
img = d[p:p + tlen + dlen] + bytes(blen)
p += tlen + dlen
if int.from_bytes(d[p:p + 2], "little"):
    sys.exit("o65blob: undefined references")
p += 2
banks = []
for base in (tbase, dbase):
    pos = base - 1
    while True:
        b = d[p]; p += 1
        if b == 0:
            break
        if b == 255:
            pos += 254
            continue
        pos += b
        t = d[p]; p += 1
        typ, seg = t & 0xE0, t & 0x1F
        if typ == 0x40:            # HIGH: one more byte
            p += 1
        elif typ == 0xA0:          # SEG: two more bytes
            p += 2
        if seg not in (2, 3, 4, 5):
            sys.exit("o65blob: relocation to segment %d" % seg)
        if typ == 0xA0 and seg != 5:
            banks.append(pos)
        elif typ == 0xC0 and seg != 5:
            banks.append(pos + 2)
open(sys.argv[2], "wb").write(img)
open(sys.argv[3], "w").write("".join("%04X\n" % b for b in banks))
print("%s: %d bytes (text %d, data %d, bss %d), zp $%02X+%d, %d bank bytes"
      % (sys.argv[2], len(img), tlen, dlen, blen, zbase, zlen, len(banks)))
