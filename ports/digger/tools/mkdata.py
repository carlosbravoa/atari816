#!/usr/bin/env python3
"""mkdata.py - Digger's pictures for the Atari816: DIGGER.DAT, from the upstream C files.

    mkdata.py SRCDIR -o DIGGER.DAT --c alpha_ok.c [--preview DIR]

SRCDIR holds upstream's vgagrafx.c (the VGA sprites: 640 x 400 pixels at 8 bits, 0xFF
transparent, each with a mask), alpha.c (the VGA font, 24 x 24) and title_gz.c (the title
picture, 640 x 400 at 8 bits, zlib-compressed). They are read as they are (the arrays are
parsed out of the C), so the game's data stays upstream's.

DIGGER.DAT is what the game loads into far memory (horizon/hz_data.c): bank images (each at
most 64 KB, each object inside one) and a table of where each thing is. Everything is
packed to 4 bits a pixel (the left pixel in the high nibble), the framebuffer's format
(FS_640X4):

  sprite ch (vgatable[2ch], vgatable[2ch + 1]): n/2 bytes of pixels S, then n/2 of mask M,
      drawn as screen = (screen & M) | S, nibble by nibble (upstream's vgaputim:
      a pixel 0xFF leaves the screen alone: M = F, S = 0; else M = mask & F, S = pixel)
  font char c in colour k (0-3): 12 x 24 bytes, upstream's colour change (vgawrite) done
  title: 640 x 400 in two halves of 200 rows (320 bytes a row)

Layout: "DIGHZ1\\0\\0", u16 nbanks, u16 nspr, u16 nchars (95), u16 0, nbanks x u32 the
images' lengths, nspr x (u8 bank, u16 off, u16 bytes), nchars x 4 x (u8 bank, u16 off),
2 x (u8 bank, u16 off), then the images (bank 0xFF: none).

alpha_ok.c: upstream's ascii2vga[] for the game's isvalchar(): a pointer for each
character that has a picture (the pictures themselves are in DIGGER.DAT).
"""
import re
import struct
import sys
import os
import zlib

BANK = 65536


def arrays(text):
    out = {}
    for m in re.finditer(r'(?:static\s+)?const\s+uint8_t\s+(\w+)\s*\[\s*\w*\s*\]\s*=\s*\{(.*?)\};',
                         text, re.S):
        out[m.group(1)] = [int(x, 0) for x in re.findall(r'0x[0-9a-fA-F]+|\b\d+\b', m.group(2))]
    return out


def table(text, name):
    m = re.search(r'\b' + name + r'\s*\[[^\]]*\]\s*=\s*\{(.*?)\};', text, re.S)
    body = re.sub(r'/\*.*?\*/', '', m.group(1), flags=re.S)
    return [w.strip() for w in body.split(',') if w.strip()]


def pack(pix, mask=None):
    """8-bit pixels -> 4-bit (S, M)"""
    s = bytearray()
    m = bytearray()
    for i in range(0, len(pix), 2):
        sb = mb = 0
        for k in (0, 1):
            p = pix[i + k]
            if mask is None:
                sn, mn = p & 15, 0
            elif p == 0xFF:
                sn, mn = 0, 15
            else:
                sn, mn = p & 15, mask[i + k] & 15
            sb = sb << 4 | sn
            mb = mb << 4 | mn
        s.append(sb)
        m.append(mb)
    return bytes(s), bytes(m)


class Banks:
    def __init__(self):
        self.imgs = [bytearray()]

    def put(self, data):
        if len(data) > BANK:
            raise SystemExit('mkdata: an object larger than a bank')
        if len(self.imgs[-1]) + len(data) > BANK:
            self.imgs.append(bytearray())
        b = len(self.imgs) - 1
        off = len(self.imgs[b])
        self.imgs[b] += data
        return b, off


def main():
    a = sys.argv[1:]
    src = a[0]
    out = a[a.index('-o') + 1]
    cout = a[a.index('--c') + 1]
    prev = a[a.index('--preview') + 1] if '--preview' in a else None

    vga = open(os.path.join(src, 'vgagrafx.c')).read()
    va = arrays(vga)
    vt = table(vga, 'vgatable')
    assert len(vt) % 2 == 0
    nspr = len(vt) // 2

    al = open(os.path.join(src, 'alpha.c')).read()
    aa = arrays(al)
    at = table(al, 'ascii2vga')
    assert len(at) == 0x5F, len(at)

    tg = open(os.path.join(src, 'title_gz.c')).read()
    tz = arrays(tg)['title_gz']
    title = zlib.decompress(bytes(tz))
    assert len(title) == 256000, len(title)

    banks = Banks()
    sprtab = []
    done = {}
    for ch in range(nspr):
        pn, mn = vt[2 * ch], vt[2 * ch + 1]
        key = (pn, mn)
        if key not in done:
            pix, msk = va[pn], va[mn]
            n = min(len(pix), len(msk))
            s, m = pack(pix[:n], msk[:n])
            b, off = banks.put(s + m)
            done[key] = (b, off, len(s))
        sprtab.append(done[key])

    # the font: upstream's vgawrite changes colour 10 and 12 by the ink c
    def recolour(p, c):
        if p == 10:
            return 12 if c == 2 else 14 if c == 3 else 10
        if p == 12:
            return {1: 2, 2: 4, 3: 6}.get(c, 12)
        return p

    fonttab = []
    for i, nm in enumerate(at):
        row = []
        for c in range(4):
            if nm == '0':
                row.append((0xFF, 0))
                continue
            pix = aa[nm]
            assert len(pix) == 576, (nm, len(pix))
            s, _ = pack([recolour(p, c) for p in pix])
            row.append(banks.put(s))
        fonttab.append(row)

    # the title: two halves of 200 rows of 320 bytes
    ts, _ = pack(list(title))
    tt = [banks.put(ts[:64000]), banks.put(ts[64000:])]

    hdr = bytearray(b'DIGHZ1\0\0')
    hdr += struct.pack('<HHHH', len(banks.imgs), nspr, 0x5F, 0)
    for im in banks.imgs:
        hdr += struct.pack('<I', len(im))
    for b, off, n in sprtab:
        hdr += struct.pack('<BHH', b, off, n)
    for row in fonttab:
        for b, off in row:
            hdr += struct.pack('<BH', b, off)
    for b, off in tt:
        hdr += struct.pack('<BH', b, off)
    with open(out, 'wb') as fh:
        fh.write(hdr)
        for im in banks.imgs:
            fh.write(im)
    print(f'mkdata: {out}: {nspr} sprites, {sum(1 for r in fonttab if r[0][0] != 0xFF)} '
          f'characters, the title; {len(banks.imgs)} banks, {len(hdr) + sum(map(len, banks.imgs)):,} bytes')

    with open(cout, 'w') as fh:
        fh.write('/* alpha_ok.c - made by tools/mkdata.py from upstream alpha.c: ascii2vga[] for\n'
                 ' * isvalchar() (non-NULL for a character that has a picture in DIGGER.DAT) */\n'
                 '#include <stdint.h>\n#include "alpha.h"\n\n'
                 'static const uint8_t have = 1;\n\n'
                 'const uint8_t * const ascii2vga[0x5f] = {\n')
        for i in range(0, 0x5F, 8):
            fh.write('  ' + ', '.join('0' if nm == '0' else '&have' for nm in at[i:i + 8]) +
                     ',\n')
        fh.write('};\n')

    if prev:
        try:
            from PIL import Image
        except ImportError:
            return
        os.makedirs(prev, exist_ok=True)
        pal = [0, 0, 0, 0, 0, 128, 0, 128, 0, 0, 128, 128, 128, 0, 0, 128, 0, 128, 128, 64, 0,
               128, 128, 128, 64, 64, 64, 0, 0, 255, 0, 255, 0, 0, 255, 255, 255, 0, 0, 255, 0,
               255, 255, 255, 0, 255, 255, 255]
        im = Image.frombytes('P', (640, 400), bytes(title))
        im.putpalette(pal + [0] * (768 - len(pal)))
        im.save(os.path.join(prev, 'title.png'))


if __name__ == '__main__':
    main()
