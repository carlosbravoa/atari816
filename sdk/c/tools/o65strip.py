#!/usr/bin/env python3
"""o65strip.py FILE.PRG - drop the relocation entries that change nothing.

(The SDK's copy of horizon/tools/o65strip.py: hcc runs it on every program cc816 builds.)

A Horizon program is linked by user/prog.cfg at $0100 of its code bank, and the loader
(kernel/loader.s) always puts text + data + bss at $0100: the offset deltas of the text,
data and bss segments are 0, and so is the zero page's (linked at 0, loaded at 0). So the
WORD, LOW and HIGH entries of those segments add 0: only the bank bytes (SEG, SEGADR) need
the loader. ld65 writes them all; the loader reads the whole file into one 64 KB scratch
bank, so a program over 64 KB cannot load. This tool rewrites the relocation tables
keeping only the entries that do something, then checks the result: the image the loader
would build from the old and the new file must be the same for every code bank.

Horizon uses it for BASIC.PRG; hcc (tools/hzc816.py) for every cc816 program, whose
relocation tables would otherwise be about a quarter of the file.
"""
import struct
import sys


def parse(b):
    """-> header fields, the option bytes' end, text/data offsets, reloc table offsets"""
    if b[0:2] != b'\x01\x00' or b[2:5] != b'o65' or b[5] != 0:
        raise SystemExit('o65strip: not an o65 file')
    mode = struct.unpack_from('<H', b, 6)[0]
    if mode & 0x6000:
        raise SystemExit('o65strip: 32-bit sizes or page relocation: not supported')
    tbase, tlen, dbase, dlen, bbase, blen, zbase, zlen, stack = struct.unpack_from('<9H', b, 8)
    p = 26
    while b[p]:
        p += b[p]
    p += 1
    toff = p
    p += tlen + dlen
    nund = struct.unpack_from('<H', b, p)[0]
    if nund:
        raise SystemExit('o65strip: undefined references')
    p += 2
    return dict(tbase=tbase, tlen=tlen, dbase=dbase, dlen=dlen, bbase=bbase, zbase=zbase,
                toff=toff, roff=p)


def read_table(b, p, start):
    """the entries of one relocation table at p -> [(position, type byte, extra bytes)], end"""
    out = []
    pos = start
    while True:
        o = b[p]
        p += 1
        if o == 0:
            return out, p
        if o == 255:
            pos += 254
            continue
        pos += o
        t = b[p]
        p += 1
        kind = t & 0xE0
        extra = b''
        if kind == 0x40:            # HIGH: the low byte of the value
            extra = b[p:p + 1]
            p += 1
        elif kind == 0xA0:          # SEG: the low 16 bits of the value
            extra = b[p:p + 2]
            p += 2
        elif kind not in (0x80, 0x20, 0xC0):
            raise SystemExit('o65strip: unknown relocation type $%02X' % t)
        if (t & 0x1F) == 0:
            raise SystemExit('o65strip: an undefined reference')
        out.append((pos, t, extra))


def write_table(entries, start):
    out = bytearray()
    pos = start
    for e_pos, t, extra in entries:
        d = e_pos - pos
        while d > 254:
            out.append(255)
            d -= 254
        out.append(d)
        out.append(t)
        out += extra
        pos = e_pos
    out.append(0)
    return bytes(out)


def load(b, bank):
    """the code bank as kernel/loader.s builds it (text + data from $0100), patched"""
    h = parse(b)
    img = bytearray(0x10000)
    img[0x100:0x100 + h['tlen'] + h['dlen']] = b[h['toff']:h['toff'] + h['tlen'] + h['dlen']]
    deltas = {2: 0x100 - h['tbase'], 3: 0x100 + h['tlen'] - h['dbase'],
              4: 0x100 + h['tlen'] + h['dlen'] - h['bbase'], 5: -h['zbase']}
    p = h['roff']
    for start in (0xFF, h['tlen'] + 0xFF):
        ents, p = read_table(b, p, start)
        for pos, t, extra in ents:
            d = deltas[t & 0x1F]
            k = t & 0xE0
            if k == 0x80:
                v = (img[pos] | img[pos + 1] << 8) + d
                img[pos], img[pos + 1] = v & 0xFF, v >> 8 & 0xFF
            elif k == 0x20:
                img[pos] = (img[pos] + d) & 0xFF
            elif k == 0x40:
                v = (img[pos] << 8 | extra[0]) + d
                img[pos] = v >> 8 & 0xFF
            elif k == 0xC0:
                v = (img[pos] | img[pos + 1] << 8) + d
                img[pos], img[pos + 1] = v & 0xFF, v >> 8 & 0xFF
                img[pos + 2] = 0 if (t & 0x1F) == 5 else bank
            else:
                img[pos] = 0 if (t & 0x1F) == 5 else bank
    return bytes(img), p


class StripError(Exception):
    pass


def strip(path):
    """rewrite path without the no-op entries -> (old size, new size, kept, all)"""
    b = open(path, 'rb').read()
    h = parse(b)
    deltas = {2: 0x100 - h['tbase'], 3: 0x100 + h['tlen'] - h['dbase'],
              4: 0x100 + h['tlen'] + h['dlen'] - h['bbase'], 5: -h['zbase']}
    p = h['roff']
    tables = []
    for start in (0xFF, h['tlen'] + 0xFF):
        ents, p = read_table(b, p, start)
        keep = [e for e in ents if (e[1] & 0xE0) in (0xA0, 0xC0) or deltas[e[1] & 0x1F] != 0]
        tables.append((start, ents, keep))
    rest = b[p:]                    # the exported globals (the loader does not read them)
    new = bytearray(b[:h['roff']])
    for start, ents, keep in tables:
        new += write_table(keep, start)
    new += rest
    new = bytes(new)
    for bank in (0x02, 0x5A, 0xC3):
        if load(b, bank)[0] != load(new, bank)[0]:
            raise StripError('o65strip: the stripped file would load differently')
    open(path, 'wb').write(new)
    n0 = sum(len(t[1]) for t in tables)
    n1 = sum(len(t[2]) for t in tables)
    return len(b), len(new), n1, n0


def main():
    path = sys.argv[1]
    try:
        old, new, n1, n0 = strip(path)
    except (StripError, SystemExit) as e:
        print(e)
        return 1
    print('o65strip: %s %d -> %d bytes (%d of %d relocations kept)' % (path, old, new, n1, n0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
