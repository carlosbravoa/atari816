#!/usr/bin/env python3
"""mko65.py - turn three vlink raw-binary links of one program into a Horizon o65 file.

    mko65.py OUT.PRG MODEL IMG0 MAP0 IMGA MAPA IMGB MAPB [BANKS]

IMG0/IMGA/IMGB are the same program linked by vlink as raw binaries (rt/horizon.cmd or
rt/horizon-tiny.cmd) at banks $00, $5A and $A5 ($xx0100); MAPn their map files (-M).
MODEL is large or tiny (only for the messages and the limits). hcc calls it; it can also be
used by hand.

Horizon's loader always puts the text segment at offset $0100 of the program's code bank,
so offsets never move: only bank bytes do. The rule, checked for every byte:

  - a byte that is the same in the three links is copied as it is;
  - a byte that differs must be exactly the link's bank in each link ($00, $5A, $A5): it
    becomes an o65 SEG relocation, and the loader stores the code bank there;
  - anything else stops the conversion with the byte's address and its three values.

Why the second rule is strict: the loader *replaces* a SEG byte with the code bank. A byte
holding "bank + 1" (a far address one bank further, `^(label + $10000)`) differs by exactly
the bank delta in every link, but would silently become the code bank. Requiring the
bank-0 link's byte to be 0 rejects it. A value that is any other function of the bank (bank
* 2, a carry out of the low word) gives other differences for $5A and $A5 and is rejected
too.

BANKS (optional): a file of further bank-byte addresses, one hex number a line, for a block
included as is in all three links (an ld65-linked assembly library, phase 2). Each must be a
byte that is 0 in the bank-0 link.

The output: o65, 16-bit sizes, one text segment = everything loaded (text + rodata + data,
or in the tiny model text + the window's data image), bss after it (large model), no zp
segment, no undefined references, no exports.
"""
import re
import sys

BANKS = (0x00, 0x5A, 0xA5)
CODE_MAX = 0xFF00            # the loader: text + data + bss within $0100-$FFFF
FILE_MAX = 0x10000           # the loader: the file must be shorter than 64 KB


class O65Error(Exception):
    pass


def sections(mapfile):
    out = {}
    with open(mapfile, encoding="latin-1") as f:
        for line in f:
            m = re.match(r"^\s+([0-9a-f]{8}) (\.\w+)\s+\(size ([0-9a-f]+)", line)
            if m:
                out[m.group(2)] = (int(m.group(1), 16), int(m.group(3), 16))
    return out


def symbols(mapfile):
    out = {}
    with open(mapfile, encoding="latin-1") as f:
        for line in f:
            m = re.match(r"^\s+0x([0-9a-f]+) (\S+): global", line)
            if m:
                out[m.group(2)] = int(m.group(1), 16)
    return out


def kb(n):
    return f"{n:,} bytes"


def convert(outname, model, imgfiles, mapfiles, banksfile=None, wend=0x7000, name=None):
    """Returns a dict of sizes; raises O65Error with a plain-words message."""
    name = name or outname
    imgs = [open(f, "rb").read() for f in imgfiles]
    maps = [sections(f) for f in mapfiles]
    for k, bank in enumerate(BANKS):
        t = maps[k].get(".text")
        if not t or t[0] != (bank << 16) + 0x100:
            raise O65Error(f"{name}: the program's text does not start at ${bank:02X}:0100 "
                           f"in link {k} (the startup must be linked first)")
    text, data, bss, wdata, wbss = (maps[0].get(s, (0, 0))
                                    for s in (".text", ".data", ".bss", ".wdata", ".wbss"))
    imglen = len(imgs[0])
    if any(len(i) != imglen for i in imgs):
        raise O65Error(f"{name}: the three links differ in size ({[len(i) for i in imgs]})")
    sizes = {"text": text[1], "data": data[1], "bss": bss[1], "wdata": wdata[1],
             "wbss": wbss[1], "image": imglen}
    if model == "tiny":
        sizes["code"] = text[1]
        wused = wdata[1] + wbss[1]
        wroom = wend - 0x100
        sizes["window_data"] = wused
        sizes["window_room"] = wroom
        if 0x100 + text[1] + wdata[1] > 0x10000:
            raise O65Error(
                f"{name} does not fit in its code bank: code {kb(text[1])} + the data image "
                f"{kb(wdata[1])} = {kb(text[1] + wdata[1])}; a code bank holds "
                f"{kb(CODE_MAX)}.")
        if wused > wroom:
            raise O65Error(
                f"{name}: the tiny model's data does not fit in the window: constant and "
                f"initialised data {kb(wdata[1])} + zeroed data (bss) {kb(wbss[1])} = "
                f"{kb(wused)}, the window has {kb(wroom)} below the stack "
                f"(WEND = ${wend:04X}). Use the large model (the default), make the arrays "
                f"smaller, or put big arrays in a bank (hz_far_alloc).")
        if wbss[1] and wbss[0] != 0x100 + wdata[1]:
            raise O65Error(f"{name}: window bss at ${wbss[0]:04X}, not after the data")
    else:
        if data[1] and data[0] != text[0] + text[1]:
            raise O65Error(f"{name}: .data does not follow .text")
        if bss[1] and bss[0] != 0x100 + imglen:
            raise O65Error(f"{name}: .bss does not follow .data")
        total = imglen + bss[1]
        sizes["code"] = total
        if total > CODE_MAX:
            raise O65Error(
                f"{name} does not fit in its code bank: code and constants {kb(text[1])} + "
                f"initialised data {kb(data[1])} + zeroed data (bss) {kb(bss[1])} = "
                f"{kb(total)}; a code bank holds {kb(CODE_MAX)} ($0100-$FFFF). Put big "
                f"arrays in a bank of their own (hz_far_alloc, docs/c/reference.md) or "
                f"make them smaller.")
    if imglen != text[1] + data[1] + wdata[1]:
        raise O65Error(f"{name}: the image is {imglen} bytes, the map says text {text[1]} + "
                       f"data {data[1]} + window data {wdata[1]}")

    relocs = []
    for i in range(imglen):
        b0, ba, bb = imgs[0][i], imgs[1][i], imgs[2][i]
        if b0 == ba == bb:
            continue
        if (b0, ba, bb) != BANKS:
            raise O65Error(
                f"{name}: the byte at code bank offset ${0x100 + i:04X} changes with the "
                f"bank but is not the bank itself (${b0:02X} ${ba:02X} ${bb:02X} in the links "
                f"at banks $00 $5A $A5): Horizon's loader can only store the code bank. "
                f"Look for an address computed from a label at that place (the map: "
                f"{mapfiles[0]}).")
        relocs.append(0x100 + i)
    if banksfile:
        for line in open(banksfile):
            if not line.strip():
                continue
            a = int(line, 16)
            if not 0x100 <= a < 0x100 + imglen or imgs[0][a - 0x100] != 0:
                raise O65Error(f"{name}: bank byte ${a:04X} from {banksfile}: not a bank-0 "
                               f"byte of the image")
            relocs.append(a)
        relocs = sorted(set(relocs))

    blen = bss[1] if model != "tiny" else 0
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
    if len(o) >= FILE_MAX:
        raise O65Error(f"{name}: the program file would be {kb(len(o))}; Horizon's loader "
                       f"takes files shorter than 65,536 bytes")
    with open(outname, "wb") as f:
        f.write(o)
    sizes["relocs"] = len(relocs)
    sizes["file"] = len(o)
    return sizes


def main():
    a = sys.argv[1:]
    if len(a) not in (8, 9):
        sys.exit(__doc__)
    try:
        s = convert(a[0], a[1], a[2:8:2], a[3:8:2], a[8] if len(a) == 9 else None)
    except O65Error as e:
        sys.exit(f"mko65: {e}")
    print(f"{a[0]}: {s['file']} bytes, {s['relocs']} bank relocations")


if __name__ == "__main__":
    main()
