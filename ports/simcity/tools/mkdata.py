#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/mkdata.py ENGINE OUTDIR [--preview DIR] [--icon OUT.png]: the game's files from upstream's art and
sounds (ENGINE/images, ENGINE/res/sounds: GPL-3, engine/README), for the Atari816:

  OUTDIR/MICROPOL.GFX   the palette, the tiles (16 x 16 and 8 x 8 for the zoomed-out
                        view), the overview's 3 x 3 tiles, the moving things as 4 bpp
                        hardware sprites (full and half size); layout below and in
                        src/data.c
  OUTDIR/SND/*.WAV      the sounds the game plays: 8-bit mono 11,025 Hz PCM (upstream's
                        are 16-bit 22,050 Hz)

MICROPOL.GFX (little-endian):
  0      "MPGX", u16 version 1, u16 0
  8      u32 offsets: [0] palette, [1] big tiles, [2] small tiles, [3] mini tiles,
         [4] sprites, [5] the end
         palette: 240 x RGB, entries 16-255 (16-29 the tiles', 128 + 16 k the sprites'
                  of type k + 1, the rest 0: the game sets its own)
         big tiles: 4096 x 64 bytes, tile t at x = (t % 256) * 16, y = (t / 256) * 16
         small tiles: 4096 x 16 bytes, tile t at x = (t % 512) * 8, y = (t / 512) * 8
         mini tiles: 960 x 9 bytes, 3 x 3 each (the overview map)
         sprites: for each type 1-8: u8 frames, u8 size (32 or 48), then for each frame
                  the full-size images (32 x 32 x 4 bpp, 512 bytes: one for size 32,
                  four for 48 (2 x 2: top left, top right, bottom left, bottom right))
                  and one half-size image (32 x 32 x 4 bpp, its 16 or 24 pixels at the
                  top left)
Pillow is used only for --preview."""
import os
import struct
import sys
import wave

NTILES = 960


def read_xpm(path):
    """(w, h, pixels as rows of colour keys, {key: (r, g, b) or None})"""
    text = open(path, encoding='latin-1').read()
    strs = []
    i = 0
    while True:
        a = text.find('"', i)
        if a < 0:
            break
        b = text.find('"', a + 1)
        strs.append(text[a + 1:b])
        i = b + 1
    w, h, nc, cpp = (int(v) for v in strs[0].split()[:4])
    colors = {}
    for line in strs[1:1 + nc]:
        key = line[:cpp]
        rest = line[cpp:].split()
        val = rest[rest.index('c') + 1] if 'c' in rest else rest[-1]
        if val.lower() == 'none':
            colors[key] = None
        else:
            hx = val.lstrip('#')
            n = len(hx) // 3
            colors[key] = tuple(int(hx[k * n:(k + 1) * n], 16) >> (4 * n - 8) for k in range(3))
    rows = [[r[k:k + cpp] for k in range(0, w * cpp, cpp)] for r in strs[1 + nc:1 + nc + h]]
    return w, h, rows, colors


def main():
    engine, out = sys.argv[1], sys.argv[2]
    preview = sys.argv[sys.argv.index('--preview') + 1] if '--preview' in sys.argv else None
    img = os.path.join(engine, 'images')
    os.makedirs(out, exist_ok=True)
    pal = [(0, 0, 0)] * 256

    # ---------------------------------------------------------------- the tiles
    w, h, rows, cols = read_xpm(os.path.join(img, 'tiles.xpm'))
    assert w == 16 and h == 16 * NTILES, (w, h)
    tilecols = sorted(set(c for c in cols.values() if c))
    assert len(tilecols) <= 14, tilecols
    tindex = {c: 16 + k for k, c in enumerate(tilecols)}
    for c, k in tindex.items():
        pal[k] = c
    big = bytearray(4096 * 64)
    for t in range(NTILES):
        tx, ty = (t % 256) * 16, (t // 256) * 16
        for y in range(16):
            r = rows[t * 16 + y]
            o = (ty + y) * 4096 + tx
            for x in range(16):
                big[o + x] = tindex[cols[r[x]]]
    # 8 x 8: each 2 x 2 block's commonest colour (its top-left on a tie)
    small = bytearray(4096 * 16)
    for t in range(NTILES):
        sx, sy = (t % 512) * 8, (t // 512) * 8
        bx, by = (t % 256) * 16, (t // 256) * 16
        for y in range(8):
            for x in range(8):
                o = (by + 2 * y) * 4096 + bx + 2 * x
                q = [big[o], big[o + 1], big[o + 4096], big[o + 4097]]
                best = max(q, key=lambda v: (q.count(v), -q.index(v)))
                small[(sy + y) * 4096 + sx + x] = best
    # the overview's 3 x 3 tiles (upstream's tilessm.xpm: 4 x 3, the 4th column unused)
    w, h, rows, cols = read_xpm(os.path.join(img, 'tilessm.xpm'))
    assert w == 4 and h == 3 * NTILES, (w, h)
    mini = bytearray(NTILES * 9)
    for t in range(NTILES):
        for y in range(3):
            for x in range(3):
                c = cols[rows[t * 3 + y][x]]
                if c not in tindex:     # (a colour of tilessm not in tiles: the nearest)
                    c = min(tilecols, key=lambda d: sum((a - b) ** 2 for a, b in zip(c, d)))
                mini[t * 9 + y * 3 + x] = tindex[c]

    # ---------------------------------------------------------------- the sprites
    sprites = bytearray()
    for typ in range(1, 9):
        frames = []
        k = 0
        while os.path.exists(os.path.join(img, 'obj%d-%d.xpm' % (typ, k))):
            frames.append(read_xpm(os.path.join(img, 'obj%d-%d.xpm' % (typ, k))))
            k += 1
        size = frames[0][0]
        colset = []
        for fw, fh, rows, cols in frames:
            assert fw == size and fh == size
            for c in cols.values():
                if c and c not in colset:
                    colset.append(c)
        base = 128 + 16 * (typ - 1)
        use = colset[:15]
        for k, c in enumerate(use):
            pal[base + 1 + k] = c

        def idx(c):
            if c is None:
                return 0
            if c in use:
                return 1 + use.index(c)
            return 1 + min(range(len(use)), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, use[i])))
        sprites += struct.pack('<BB', len(frames), size)
        for fw, fh, rows, cols in frames:
            px = [[idx(cols[rows[y][x]]) for x in range(size)] for y in range(size)]

            def img32(x0, y0, src, n):
                b = bytearray(512)
                for y in range(32):
                    for x in range(0, 32, 2):
                        def p(xx, yy):
                            if xx < n and yy < n and 0 <= x0 + xx and 0 <= y0 + yy:
                                return src[y0 + yy][x0 + xx] if (y0 + yy < len(src) and x0 + xx < len(src)) else 0
                            return 0
                        b[y * 16 + x // 2] = (p(x, y) << 4) | p(x + 1, y)
                return b
            if size == 32:
                sprites += img32(0, 0, px, 32)
            else:
                for (x0, y0) in ((0, 0), (32, 0), (0, 32), (32, 32)):
                    sub = [[(px[y][x] if y < size and x < size else 0) for x in range(64)]
                           for y in range(64)]
                    sprites += img32(x0, y0, sub, 64)
            half = size // 2
            hp = [[0] * half for _ in range(half)]
            for y in range(half):
                for x in range(half):
                    q = [px[2 * y][2 * x], px[2 * y][2 * x + 1], px[2 * y + 1][2 * x],
                         px[2 * y + 1][2 * x + 1]]
                    nz = [v for v in q if v]
                    hp[y][x] = max(nz, key=nz.count) if len(nz) >= 2 else (nz[0] if nz else 0)
            sprites += img32(0, 0, hp, half)

    # ---------------------------------------------------------------- the file
    palb = bytearray()
    for k in range(16, 256):
        palb += bytes(pal[k])
    parts = [palb, big, small, mini, sprites]
    offs = []
    o = 8 + 4 * 6
    for p in parts:
        offs.append(o)
        o += len(p)
    offs.append(o)
    data = b'MPGX' + struct.pack('<HH', 1, 0) + struct.pack('<6I', *offs) + b''.join(parts)
    write(os.path.join(out, 'MICROPOL.GFX'), data)

    # ---------------------------------------------------------------- the sounds
    snd = os.path.join(engine, 'res', 'sounds')
    os.makedirs(os.path.join(out, 'SND'), exist_ok=True)
    for name in SOUNDS:
        convert(os.path.join(snd, name + '.wav'),
                os.path.join(out, 'SND', SOUNDS[name] + '.WAV'))

    if '--icon' in sys.argv:            # the app's icon: 2 x 2 tiles of a coal power plant
        from PIL import Image
        icon = Image.new('RGBA', (32, 32))
        for k, t in enumerate((745, 746, 749, 750)):
            bx, by = (t % 256) * 16, (t // 256) * 16
            for y in range(16):
                for x in range(16):
                    c = pal[big[(by + y) * 4096 + bx + x]]
                    icon.putpixel(((k & 1) * 16 + x, (k >> 1) * 16 + y), c + (255,))
        icon.save(sys.argv[sys.argv.index('--icon') + 1])

    if preview:
        from PIL import Image
        os.makedirs(preview, exist_ok=True)
        flat = []
        for k in range(256):
            flat += list(pal[k])
        im = Image.frombytes('P', (4096, 64), bytes(big))
        im.putpalette(flat)
        im.save(os.path.join(preview, 'tiles.png'))
        im = Image.frombytes('P', (4096, 16), bytes(small))
        im.putpalette(flat)
        im.save(os.path.join(preview, 'small.png'))


# upstream's sound name (res/sounds) -> the file's name here (8.3)
SOUNDS = {
    'explosion-high': 'EXPHI', 'explosion-low': 'EXPLO', 'heavytraffic': 'TRAFFIC',
    'honkhonk-high': 'HONKHI', 'honkhonk-med': 'HONKMED', 'honkhonk-low': 'HONKLO',
    'siren': 'SIREN', 'monster': 'MONSTER', 'rumble': 'RUMBLE', 'o': 'O', 'a': 'A',
    'e': 'E', 'uhuh': 'UHUH', 'sorry': 'SORRY', 'boing': 'BOING', 'oop': 'OOP',
    'aaah': 'AAAH', 'woosh': 'WOOSH', 'skid': 'SKID', 'quackquack': 'QUACK',
}


def convert(src, dst):
    with wave.open(src) as w:
        ch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw == 2:
        vals = list(struct.unpack('<%dh' % (len(raw) // 2), raw))
    else:
        vals = [(b - 128) << 8 for b in raw]
    if ch == 2:
        vals = [(vals[i] + vals[i + 1]) // 2 for i in range(0, len(vals) - 1, 2)]
    step = max(1, round(rate / 11025))
    out = bytearray()
    for i in range(0, len(vals) - step + 1, step):
        v = sum(vals[i:i + step]) // step
        out.append(max(0, min(255, (v >> 8) + 128)))
    with wave.open(dst + '.new', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(rate // step)
        w.writeframes(bytes(out))
    os.replace(dst + '.new', dst)


def write(path, data):
    try:
        if open(path, 'rb').read() == data:
            return
    except OSError:
        pass
    with open(path + '.new', 'wb') as f:
        f.write(data)
    os.replace(path + '.new', path)


if __name__ == '__main__':
    main()
