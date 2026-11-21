#!/usr/bin/env python3
"""mko65.py - turn a vbcc/vlink program into a Horizon o65 file.

    mko65.py OUT.PRG IMG0 MAP0 IMGA MAPA IMGB MAPB [BANKS]

IMG0/IMGA/IMGB are the same program linked by vlink as raw binaries (hz/horizon.cmd)
at bank 0, bank $5A and bank $A5 ($xx0100), MAPn their map files (-M).

Horizon's loader always puts the text segment at offset $0100 of the program's code
bank, so the offsets in the program never change: only bank bytes do. Every byte that
differs between the links must differ by exactly the bank difference (else the program
does something this scheme cannot relocate, and we stop). Each such byte becomes an o65
SEG relocation (the loader stores the code bank there). This covers vbcc's 24-bit
addresses (JSL/JML/long addressing), the bank half of its 32-bit pointers in data, and
16-bit `#^label` immediates (the high byte of those is 0 and stays 0).
BANKS (optional): a file of further bank-byte addresses, one hex number a line, for a
block included as is in all three links (asmlib/: an ld65-linked library, o65blob.py).

The output: o65, 16-bit sizes, one text segment = text + rodata + data (the loader copies
text and data alike), bss after it, no zp segment (vbcc's registers are at fixed
direct-page addresses), no undefined references, no exports.
"""
import re
import sys

BANKS = (0x00, 0x5A, 0xA5)


def sections(mapfile):
    out = {}
    with open(mapfile, encoding="latin-1") as f:
        for line in f:
            m = re.match(r"^\s+([0-9a-f]{8}) (\.\w+)\s+\(size ([0-9a-f]+)", line)
            if m:
                out[m.group(2)] = (int(m.group(1), 16), int(m.group(3), 16))
    return out


def main():
    if len(sys.argv) not in (8, 9):
        sys.exit(__doc__)
    outname = sys.argv[1]
    imgs = [open(sys.argv[2 + 2 * k], "rb").read() for k in range(3)]
    maps = [sections(sys.argv[3 + 2 * k]) for k in range(3)]
    for k, bank in enumerate(BANKS):
        t = maps[k].get(".text")
        if not t or t[0] != (bank << 16) + 0x100:
            sys.exit("mko65: .text of link %d is not at $%02X:0100" % (k, bank))
    # large model: .text .data .bss in the code bank; tiny model: .text in the code bank,
    # .wdata loaded after it (copied to the window by the startup), .wbss in the window
    text, data, bss, wdata = (maps[0].get(s, (0, 0))
                              for s in (".text", ".data", ".bss", ".wdata"))
    imglen = len(imgs[0])
    if any(len(i) != imglen for i in imgs):
        sys.exit("mko65: the three links differ in size")
    if data[1] and data[0] != text[0] + text[1]:
        sys.exit("mko65: .data does not follow .text")
    if imglen != text[1] + data[1] + wdata[1]:
        sys.exit("mko65: image is %d bytes, map says text %d + data %d + wdata %d"
                 % (imglen, text[1], data[1], wdata[1]))
    blen = bss[1]
    if bss[1] and bss[0] != 0x100 + imglen:
        sys.exit("mko65: .bss does not follow .data")
    if 0x100 + imglen + blen > 0x10000:
        sys.exit("mko65: text + data + bss = %d bytes, more than $FF00" % (imglen + blen))

    relocs = []
    for i in range(imglen):
        b0, ba, bb = imgs[0][i], imgs[1][i], imgs[2][i]
        if b0 == ba == bb:
            continue
        if (ba - b0) & 0xFF != BANKS[1] or (bb - b0) & 0xFF != BANKS[2]:
            sys.exit("mko65: byte at $%04X changes but not as a bank byte (%02X %02X %02X)"
                     % (0x100 + i, b0, ba, bb))
        relocs.append(0x100 + i)
    if len(sys.argv) == 9:
        for line in open(sys.argv[8]):
            a = int(line, 16)
            if not 0x100 <= a < 0x100 + imglen or imgs[0][a - 0x100] != 0:
                sys.exit("mko65: bank byte $%04X from %s: not a bank-0 byte of the image"
                         % (a, sys.argv[8]))
            relocs.append(a)
        relocs = sorted(set(relocs))

    o = bytearray()
    o += bytes([1, 0, ord("o"), ord("6"), ord("5"), 0])
    o += (0x8000).to_bytes(2, "little")          # mode: 65816, 16-bit sizes, byte relocs
    for v in (0x100, imglen, 0x100 + imglen, 0, 0x100 + imglen, blen, 0, 0, 0):
        o += v.to_bytes(2, "little")             # tbase tlen dbase dlen bbase blen zbase zlen stack
    o += bytes([0])                              # no header options
    o += imgs[0]                                 # text (the bank-0 link)
    o += (0).to_bytes(2, "little")               # no undefined references
    pos = 0x100 - 1                              # text relocation table
    for r in relocs:
        d = r - pos
        while d > 254:
            o.append(255)
            d -= 254
        o.append(d)
        o.append(0xA0 | 2)                       # SEG, text segment
        o += bytes([0, 0])                       # low 16 bits of the value (unused by Horizon)
        pos = r
    o.append(0)                                  # end of text relocations
    o.append(0)                                  # data relocations: none
    o += (0).to_bytes(2, "little")               # no exported globals
    if len(o) >= 0x10000:
        sys.exit("mko65: the file is %d bytes; the loader takes less than 64 KB" % len(o))
    with open(outname, "wb") as f:
        f.write(o)
    print("%s: text+data %d, bss %d, %d bank relocations, file %d bytes"
          % (outname, imglen, blen, len(relocs), len(o)))


if __name__ == "__main__":
    main()
