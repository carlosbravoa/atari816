#!/usr/bin/env python3
"""mkdata.py - Xargon's data files (an episode's, from the user's own copy of the game) to
what the Horizon port loads. Plain Python 3, no other modules.

    mkdata.py SRCDIR -o OUTDIR [--episode 1|2|3|all]

SRCDIR holds the game's files as released (GRAPHICS.XR1, BOARD_01.XR1, ...; the names in
any case). OUTDIR gets, in capitals (what goes into the port's folder on the card):

  XSHAPES.XRn  GRAPHICS.XRn's shape tables, translated as upstream's shapeman.c
               (xlate_table) translates them for VGA, every shape as plain rows of 8-bit
               pixels (no mode X planes), placed in an atlas of 512-byte rows: the
               blitter's sheets (each table's rows together, loaded when the game wants
               the table); a directory of each shape's place. A table with the 64 x 12
               palette shape is marked
  XSOUND.XRn   AUDIO.XRn's 50 sound effects as signed 8-bit samples for Lau (upstream
               plays them on the Sound Blaster as unsigned 8-bit at 6,250 Hz; a sound that
               starts with a stray piece of a VOC file's header has it cut off)
  SONG_*.OPn   the CMF songs (Creative Music Files, the Sound Blaster's FM music) as AdLib
               register streams for the OPL2 (id Software's IMF format: 4-byte records
               {register, value, u16 delay}, the delay in 1/560 s), as Creative's SBFMDRV
               driver plays them: instruments, the nine voices allocated by note, rhythm
               mode, transposition (the rules of AdPlug's CMF player)
  the rest     copied as they are: the boards, TILES, AUDIO (its texts), the demo's
               recording, the end sequence

Formats: XSHAPES: "XSH2", u16 64, u16 512 (the atlas's row), 64 x {u16 first shape, u16
shapes, u32 its rows' place in the file, u16 rows, u16 flags (1 a font, 0x100 has the
palette shape), u16 the palette shape}, the shapes {u16 x, u16 y (in the table's rows),
u8 w, u8 h, u16 0}, then the rows (write_shapes). XSOUND: "XSN1", u16 count, then count x {u32 offset, u16 length, u16 rate},
then the samples.
"""
import argparse
import math
import os
import struct
import sys

# ---------------------------------------------------------------- the files

def find(srcdir):
    """name in capitals -> its path"""
    out = {}
    for n in os.listdir(srcdir):
        out[n.upper()] = os.path.join(srcdir, n)
    return out


def read(files, name):
    with open(files[name], 'rb') as f:
        return f.read()

# ---------------------------------------------------------------- shapes

SHM_FONTF = 1
SHM_BLFLAG = 4


ATLAS = 512                                     # the atlas's row: bytes (= pixels)


def xlate_table(b):
    """one table of GRAPHICS.XRn -> ([(w, h, pixels)], flags, the palette shape or -1), as
    upstream's xlate_table translates it (its colour table applied; no mode X planes)"""
    numshapes = b[0]
    numrots, len_cga, len_ega, len_vga, ncb, flags = struct.unpack_from('<HHHHBH', b, 1)
    p = 12
    colortab = list(range(256))
    if flags & SHM_FONTF:
        pass                                    # (identity)
    elif ncb == 8:
        pass
    else:
        for c in range(1 << ncb):
            lc, = struct.unpack_from('<l', b, p)
            p += 4
            colortab[c] = (lc >> 16) & 255
    shapes = []
    palshape = -1
    for s in range(numshapes):
        xs, ys, st = b[p], b[p + 1], b[p + 2]
        p += 3
        if st != 0:
            raise SystemExit('mkdata: shape storage type %d not supported' % st)
        px = b[p:p + xs * ys]
        p += xs * ys
        if ncb == 8 and xs == 64 and ys == 12:
            palshape = s
        shapes.append((xs, ys, bytes(colortab[v] for v in px)))
    return shapes, flags, palshape


def place(shapes):
    """shelves in rows of ATLAS bytes, the tallest shapes first -> ([(x, y)], rows)"""
    out = [None] * len(shapes)
    x = y = shelf = 0
    for i in sorted(range(len(shapes)), key=lambda k: -shapes[k][1]):
        w, h, _ = shapes[i]
        if x + w > ATLAS:
            x = 0
            y += shelf
            shelf = 0
        out[i] = (x, y)
        x += w
        shelf = max(shelf, h)
    return out, y + shelf


def write_shapes(src, out):
    """the shapes in an atlas of 512-byte rows (the blitter's sheets; each table's rows
    together, loaded when the game wants the table)"""
    offs = struct.unpack_from('<128l', src, 0)
    lens = struct.unpack_from('<128H', src, 512)
    hdr = bytearray(b'XSH2' + struct.pack('<HH', 64, ATLAS))
    dirs = bytearray()
    pix = bytearray()
    tabs = []
    for t in range(64):
        if lens[t] == 0:
            tabs.append(None)
            continue
        shapes, flags, pal = xlate_table(src[offs[t]:offs[t] + lens[t]])
        pos, rows = place(shapes)
        img = bytearray(ATLAS * rows)
        for (w, h, px), (x, y) in zip(shapes, pos):
            for r in range(h):
                img[(y + r) * ATLAS + x:(y + r) * ATLAS + x + w] = px[r * w:(r + 1) * w]
        tabs.append((len(dirs), len(shapes), len(pix), rows, flags, pal))
        for (w, h, _), (x, y) in zip(shapes, pos):
            dirs += struct.pack('<HHBBH', x, y, w, h, 0)
        pix += img
    # directory: 64 x {u16 first entry (x 8 bytes), u16 shapes, u32 pixels' offset in the
    # file (row-aligned), u16 rows, u16 flags (1 font, 0x100 palette), u16 palette shape}
    base = 8 + 64 * 14
    dbase = base
    pbase = dbase + len(dirs)
    for t in tabs:
        if t is None:
            hdr += bytes(14)
            continue
        d, n, p, rows, flags, pal = t
        f = flags & SHM_FONTF
        if pal >= 0:
            f |= 0x100
        hdr += struct.pack('<HHLHHH', d // 8, n, pbase + p, rows, f, max(pal, 0))
    data = bytes(hdr) + bytes(dirs) + bytes(pix)
    with open(out, 'wb') as f:
        f.write(data)
    return len(data), sum(t[3] for t in tabs if t), len(dirs) // 8

# ---------------------------------------------------------------- sounds

NUM_SAMPS = 50
VOCRATE = 6250                                  # music.c: the VOC header's speed byte 96


def write_sounds(src, out):
    vocposn = struct.unpack_from('<50l', src, 0)
    voclen = struct.unpack_from('<50h', src, 200)
    hdr = bytearray(b'XSN1' + struct.pack('<H', NUM_SAMPS))
    body = bytearray()
    base = 6 + NUM_SAMPS * 8
    cut = 0
    for i in range(NUM_SAMPS):
        n = voclen[i] & 0xFFFF
        if n == 0 or vocposn[i] < 0:
            hdr += struct.pack('<LHH', 0, 0, 0)
            continue
        s = src[vocposn[i]:vocposn[i] + n]
        # some sounds start inside a VOC file's header ("...Voice File\x1a\x1a\0\x0a\x01
        # \x29\x11", then a data block: type 1, a 24-bit length, rate, packing): the
        # Sound Blaster played those bytes as a click; they are cut here
        k = s.find(b'\x1a\x1a\x00')
        if 0 <= k < 24 and s[k + 7:k + 8] == b'\x01':
            s = s[k + 13:]
            cut += 1
        smp = bytes(((v - 128) & 255) for v in s)
        hdr += struct.pack('<LHH', base + len(body), len(smp), VOCRATE)
        body += smp
        if len(body) & 1:
            body += b'\0'
    with open(out, 'wb') as f:
        f.write(hdr + body)
    return len(hdr) + len(body), cut

# ---------------------------------------------------------------- music: CMF -> IMF

IMF_HZ = 560
# The board mixes the OPL2 three times louder than a Lau voice at full volume (the effects):
# the songs as SBFMDRV plays them clip often there (1-2 % of the samples). The operators
# that sound (the carriers; both in additive mode; the drums' single ones) are made
# quieter by OPL_ATT steps of 0.75 dB: 18, 13.5 dB
OPL_ATT = 18


def oploff(ch):
    return (ch // 3) * 8 + ch % 3


class CMF:
    """Creative's SBFMDRV playing a CMF file, as register writes (AdPlug's rules)"""

    def __init__(self, data):
        if data[:4] != b'CTMF':
            raise ValueError('not a CMF file')
        (self.ver, ioff, moff, self.tpq, self.tps, _, _, _) = struct.unpack_from('<8H', data, 4)
        ninst, = struct.unpack_from('<H', data, 36)
        self.inst = [data[ioff + 16 * i:ioff + 16 * i + 16] for i in range(ninst)]
        self.data = data
        self.moff = moff
        self.regs = [0] * 256
        self.out = []                           # (tick, reg, val)
        self.tick = 0
        self.perc = False
        self.patch = list(range(16))
        self.transpose = [0] * 16
        self.bend = [8192] * 16
        self.oplstart = [0] * 9
        self.oplmidi = [-1] * 9
        self.oplnote = [-1] * 9
        self.oplpatch = [-1] * 9
        self.count = 0

    def w(self, reg, val):
        self.regs[reg] = val & 255
        self.out.append((self.tick, reg, val & 255))

    def inst_ops(self, ch, src, dst, k, sounds=None):
        i = self.inst[k] if k < len(self.inst) else bytes(16)
        o = oploff(ch) + (3 if dst else 0)
        if sounds is None:                      # (a carrier, or a modulator added in)
            sounds = dst == 1 or (i[10] & 1)
        lv = i[2 + src]
        if sounds:
            lv = (lv & 0xC0) | min(63, (lv & 0x3F) + OPL_ATT)
        self.w(0x20 + o, i[0 + src])
        self.w(0x40 + o, lv)
        self.w(0x60 + o, i[4 + src])
        self.w(0x80 + o, i[6 + src])
        self.w(0xE0 + o, i[8 + src])
        self.w(0xC0 + ch, i[10])

    def change_inst(self, oplch, midich, k):
        if midich > 10 and self.perc:
            if midich == 11:
                oplch = 6
                self.inst_ops(6, 0, 0, k)
                self.inst_ops(6, 1, 1, k)
            elif midich == 12:
                oplch = 7
                self.inst_ops(7, 0, 1, k, True)
            elif midich == 13:
                oplch = 8
                self.inst_ops(8, 0, 0, k, True)
            elif midich == 14:
                oplch = 8
                self.inst_ops(8, 0, 1, k, True)
            elif midich == 15:
                oplch = 7
                self.inst_ops(7, 0, 0, k, True)
            self.oplpatch[oplch] = k
        else:
            self.inst_ops(oplch, 0, 0, k)
            self.inst_ops(oplch, 1, 1, k)
            self.oplpatch[oplch] = k

    def fnum(self, ch, note):
        block = note // 12
        if block > 1:
            block -= 1
        d = math.pow(2, (note + (self.bend[ch] - 8192) / 8192.0 + self.transpose[ch] / 128.0
                         - 9) / 12.0 - (block - 20)) * 440.0 / 32.0 / 50000.0
        f = int(d + 0.5)
        if f > 1023:
            f = 1023
        return block & 7, f

    @staticmethod
    def percch(ch):
        return {11: 6, 12: 7, 13: 8, 14: 8, 15: 7}[ch]

    def note_on(self, ch, note, vel):
        block, f = self.fnum(ch, note)
        if ch > 10 and self.perc:
            pc = self.percch(ch)
            self.change_inst(pc, ch, self.patch[ch])
            lvl = int(0x25 - math.sqrt(vel * 16)) + OPL_ATT
            lvl = max(0, min(0x3F, lvl))
            o = 0x40 + oploff(pc)
            if ch == 11:
                o += 3
            self.w(o, (self.regs[o] & ~0x3F) | lvl)
            self.w(0xA0 + pc, f & 0xFF)
            self.w(0xB0 + pc, (block << 2) | ((f >> 8) & 3))
            bit = 1 << (15 - ch)
            if self.regs[0xBD] & bit:
                self.w(0xBD, self.regs[0xBD] & ~bit)
            self.w(0xBD, self.regs[0xBD] | bit)
            self.count += 1
            self.oplstart[pc] = self.count
            self.oplmidi[pc] = ch
            self.oplnote[pc] = note
            return
        nch = 6 if self.perc else 9
        oc = -1
        for i in range(nch - 1, -1, -1):
            if self.oplstart[i] == 0:
                oc = i
                if self.oplpatch[i] == self.patch[ch]:
                    break
        if oc < 0:
            oc = 0
            early = self.oplstart[0]
            for i in range(1, nch):
                if self.oplstart[i] < early:
                    oc, early = i, self.oplstart[i]
        if self.oplpatch[oc] != self.patch[ch]:
            self.change_inst(oc, ch, self.patch[ch])
        self.count += 1
        self.oplstart[oc] = self.count
        self.oplmidi[oc] = ch
        self.oplnote[oc] = note
        self.w(0xA0 + oc, f & 0xFF)
        self.w(0xB0 + oc, 0x20 | (block << 2) | ((f >> 8) & 3))

    def note_off(self, ch, note):
        if ch > 10 and self.perc:
            bit = 1 << (15 - ch)
            self.w(0xBD, self.regs[0xBD] & ~bit)
            pc = self.percch(ch)
            self.oplstart[pc] = 0
            return
        nch = 6 if self.perc else 9
        for i in range(nch):
            if self.oplmidi[i] == ch and self.oplnote[i] == note and self.oplstart[i]:
                self.oplstart[i] = 0
                self.w(0xB0 + i, self.regs[0xB0 + i] & ~0x20)
                break

    def controller(self, ch, c, v):
        if c == 0x63:                           # AM / vibrato depth
            self.w(0xBD, (self.regs[0xBD] | 0xC0) if v else (self.regs[0xBD] & ~0xC0))
        elif c == 0x67:                         # rhythm mode
            self.perc = v != 0
            self.w(0xBD, (self.regs[0xBD] | 0x20) if self.perc else (self.regs[0xBD] & ~0x20))
        elif c == 0x68:                         # transpose up, 1/128 semitones
            self.transpose[ch] = v
        elif c == 0x69:                         # transpose down
            self.transpose[ch] = -v
        # 0x66: a marker for the game; others: nothing

    def run(self):
        self.w(0x01, 0x20)
        self.w(0x08, 0x00)
        self.w(0xA8, 514 & 0xFF)
        self.w(0xB8, (1 << 2) | (514 >> 8))
        c = self.data
        p = self.moff
        rs = 0

        def varlen():
            nonlocal p
            v = 0
            while True:
                b = c[p]
                p += 1
                v = (v << 7) | (b & 0x7F)
                if not b & 0x80:
                    return v
        while p < len(c):
            self.tick += varlen()
            s = c[p]
            if s & 0x80:
                p += 1
                if s < 0xF0:
                    rs = s
            else:
                s = rs
            if s == 0xFF:
                ty = c[p]
                p += 1
                n = varlen()
                p += n
                if ty == 0x2F:
                    break
                continue
            if s in (0xF0, 0xF7):
                p += varlen()
                continue
            t, ch = s & 0xF0, s & 15
            if t in (0xC0, 0xD0):
                a = c[p]
                p += 1
                if t == 0xC0:
                    self.patch[ch] = a
                continue
            a, b = c[p], c[p + 1]
            p += 2
            if t == 0x90 and b:
                self.note_on(ch, a, b)
            elif t == 0x80 or t == 0x90:
                self.note_off(ch, a)
            elif t == 0xB0:
                self.controller(ch, a, b)
            elif t == 0xE0:
                self.bend[ch] = a | (b << 7)
        return self.tick


def cmf_to_imf(data):
    m = CMF(data)
    end = m.run()
    recs = bytearray()
    ev = m.out
    # ticks (tps a second) -> 1/560 s, rounded on the running total
    def at(t):
        return (t * IMF_HZ + m.tps // 2) // m.tps
    for i, (t, reg, val) in enumerate(ev):
        nxt = ev[i + 1][0] if i + 1 < len(ev) else end
        d = at(nxt) - at(t)
        while d > 0xFFFF:                       # (a long rest: padded with writes of 0 to reg 0)
            recs += struct.pack('<BBH', reg, val, 0xFFFF)
            reg, val = 0, 0
            d -= 0xFFFF
        recs += struct.pack('<BBH', reg, val, d)
    return bytes(recs), end / m.tps

# ---------------------------------------------------------------- the episode

COPY_PREFIX = ('BOARD_', 'DEMO', 'INTRO.', 'MAP.', 'STORY.', 'TILES.', 'AUDIO.', 'END_MAC.')


def episode(files, ep, outdir, log):
    x = '.XR%d' % ep
    if 'GRAPHICS' + x not in files:
        return False
    n, rows, nsh = write_shapes(read(files, 'GRAPHICS' + x), os.path.join(outdir, 'XSHAPES' + x))
    log('XSHAPES%s: %d bytes, %d shapes in %d atlas rows' % (x, n, nsh, rows))
    n, cut = write_sounds(read(files, 'AUDIO' + x), os.path.join(outdir, 'XSOUND' + x))
    log('XSOUND%s: %d bytes (%d sounds without their VOC header piece)' % (x, n, cut))
    for name in sorted(files):
        if name.startswith('SONG_') and (name.endswith(x) or name.endswith('.XR0')):
            d = read(files, name)
            if d[:4] != b'CTMF':
                continue
            imf, secs = cmf_to_imf(d)
            on = name[:-4] + '.OP' + name[-1]
            with open(os.path.join(outdir, on), 'wb') as f:
                f.write(imf)
            log('%s: %d records, %.1f s' % (on, len(imf) // 4, secs))
        elif name.startswith(COPY_PREFIX) and (name.endswith(x) or name.endswith('.XR0')):
            with open(os.path.join(outdir, name), 'wb') as f:
                f.write(read(files, name))
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('src')
    ap.add_argument('-o', dest='out', required=True)
    ap.add_argument('--episode', default='all')
    ap.add_argument('-q', action='store_true')
    a = ap.parse_args()
    files = find(a.src)
    os.makedirs(a.out, exist_ok=True)
    eps = [1, 2, 3] if a.episode == 'all' else [int(a.episode)]
    log = (lambda s: None) if a.q else print
    done = [e for e in eps if episode(files, e, a.out, log)]
    if not done:
        sys.exit('mkdata: no GRAPHICS.XRn in %s (the game\'s files: tools/getdata.sh)' % a.src)


if __name__ == '__main__':
    main()
