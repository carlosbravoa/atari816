#!/usr/bin/env python3
"""img2inc.py - pictures to ca65 include files of 8 bpp pixels for Horizon's win_draw
blits (WD_BLIT, WD_KBLIT, WD_SBLIT): sprites, animation frames, tile sets.

    img2inc.py ART [-o OUT.inc] [--name NAME] [--tile WxH] [--key N]
               [--own-palette BASE] [--preview OUT.png] [--scale N]

ART is a PNG (needs Pillow) or a text-art file (no Pillow needed, see below).

Output (NAME defaults to the file name):
    NAME_W = 16         ; one frame's (tile's) width and height in pixels
    NAME_H = 16
    NAME_N = 4          ; frames
    NAME_SIZE = 256     ; bytes per frame (W * H)
    NAME:  .byte ...    ; frame 0 (H rows of W bytes), then frame 1, ...
Frame k starts at NAME + k * NAME_SIZE: blit it with WD_BLIT / WD_KBLIT, w = NAME_W,
h = NAME_H. Everything is one block: keep it under 64 KB (one bank; a blit's source must
not cross a bank boundary).

Colours: by default each pixel becomes the nearest colour of Horizon's system palette
(0-15 UI colours, 16-231 the 6x6x6 cube, 232-255 greys; tools/mkpalette.py in Horizon).
The key colour (--key, default 231) is never chosen for a visible pixel: transparent pixels
(alpha < 128 in a PNG, the "key" letter in text art) get it, so WD_KBLIT with c2 = the key
skips them. White becomes C_WHITE (1), as 231 is also white.
--own-palette BASE: the picture's own colours (at most 256 - BASE) get the entries BASE,
BASE + 1, ... and the output adds NAME_PALN (count) and NAME_PAL (r, g, b bytes) for
SYS_WSPAL. The palette is shared by every window on the screen: change only entries your
program owns by agreement, and put the system colours back before you exit.

Frames: a PNG is cut into tiles of --tile WxH, left to right, top to bottom. In text art,
frames are separated by blank lines (all the same size).

Text art: a legend, then the pixel rows. Lines starting with ';' are comments.
    ; a 4x3 example with two frames
    . = key            ; transparent
    k = 0              ; a palette index (0-255): C_BLACK
    y = #F0C840        ; an RGB colour: the nearest system colour
    r = cube 5 1 0     ; the cube colour 16 + 36 r + 6 g + b
    g = grey 12        ; grey ramp entry 232 + n (0-23)

    .kk.
    kyyk
    .kk.

    .rr.
    rggr
    .rr.
Every legend line is "letter = value"; the first non-legend, non-empty line starts the
pixels. Any character except space and ';' can be a pixel letter.

--preview OUT.png (needs Pillow): the frames side by side, magnified (--scale, default 4),
the key colour shown as a checkerboard: look at it before you build.
"""
import os
import re
import sys


def system_palette():
    ui = [(0, 0, 0), (255, 255, 255), (36, 92, 112), (46, 104, 124), (28, 60, 132),
          (132, 138, 148), (228, 226, 216), (76, 80, 90), (160, 164, 172), (204, 206, 210),
          (52, 100, 204), (200, 52, 44), (240, 200, 64), (60, 156, 80), (232, 128, 40),
          (36, 40, 48)]
    pal = list(ui)
    for r in range(6):
        for g in range(6):
            for b in range(6):
                pal.append((r * 51, g * 51, b * 51))
    for i in range(24):
        v = 8 + 10 * i
        pal.append((v, v, v))
    return pal


PAL = system_palette()


def nearest(rgb, key, avoid_ui=False):
    best, bi = None, 0
    for i, c in enumerate(PAL):
        if i == key or (avoid_ui and 2 <= i <= 15):
            continue
        d = (c[0] - rgb[0]) ** 2 * 3 + (c[1] - rgb[1]) ** 2 * 4 + (c[2] - rgb[2]) ** 2 * 2
        if best is None or d < best:
            best, bi = d, i
    return bi


class ArtError(Exception):
    pass


def parse_value(v, key):
    v = v.strip()
    if v == 'key':
        return ('key', None)
    m = re.fullmatch(r'#([0-9a-fA-F]{6})', v)
    if m:
        h = m.group(1)
        return ('rgb', (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    m = re.fullmatch(r'cube\s+([0-5])\s+([0-5])\s+([0-5])', v)
    if m:
        r, g, b = map(int, m.groups())
        return ('idx', 16 + 36 * r + 6 * g + b)
    m = re.fullmatch(r'grey\s+(\d+)', v)
    if m and int(m.group(1)) < 24:
        return ('idx', 232 + int(m.group(1)))
    m = re.fullmatch(r'(\$[0-9a-fA-F]+|\d+)', v)
    if m:
        n = int(v[1:], 16) if v.startswith('$') else int(v)
        if 0 <= n <= 255:
            return ('idx', n)
    raise ArtError(f'bad colour value {v!r}')


def load_text(path, key):
    legend, frames, cur = {}, [], []
    started = False
    for no, raw in enumerate(open(path), 1):
        ln = raw.rstrip('\n')
        if ln.lstrip().startswith(';'):
            continue                    # a comment line (not a frame separator)
        s = ln.split(';', 1)[0].rstrip()
        if not started:
            if not s.strip():
                continue
            m = re.fullmatch(r'\s*(\S)\s*=\s*(.+?)\s*', s)
            if m:
                legend[m.group(1)] = parse_value(m.group(2), key)
                continue
            started = True
        if not s.strip():
            if cur:
                frames.append(cur); cur = []
            continue
        row = s.strip()
        for c in row:
            if c not in legend:
                raise ArtError(f'{path}:{no}: letter {c!r} is not in the legend')
        cur.append(row)
    if cur:
        frames.append(cur)
    if not frames:
        raise ArtError(f'{path}: no pixels')
    w, h = len(frames[0][0]), len(frames[0])
    for k, f in enumerate(frames):
        if len(f) != h or any(len(r) != w for r in f):
            raise ArtError(f'{path}: frame {k} is not {w}x{h} like frame 0')
    out = []
    for f in frames:
        px = []
        for r in f:
            for c in r:
                kind, v = legend[c]
                px.append(None if kind == 'key' else v if kind == 'rgb' else ('idx', v))
        out.append(px)
    return w, h, out


def load_png(path, tile):
    try:
        from PIL import Image
    except ImportError:
        raise ArtError('PNG input needs Pillow (pip install pillow); text art does not')
    im = Image.open(path).convert('RGBA')
    W, H = im.size
    tw, th = tile or (W, H)
    if W % tw or H % th:
        raise ArtError(f'{path}: {W}x{H} is not a whole number of {tw}x{th} tiles')
    frames = []
    for ty in range(0, H, th):
        for tx in range(0, W, tw):
            px = []
            for y in range(ty, ty + th):
                for x in range(tx, tx + tw):
                    r, g, b, a = im.getpixel((x, y))
                    px.append(None if a < 128 else (r, g, b))
            frames.append(px)
    return tw, th, frames


def main():
    a = sys.argv[1:]
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); return 0
    src, out, name, tile, key, own, prev, scale = None, None, None, None, 231, None, None, 4
    i = 0
    while i < len(a):
        w = a[i]
        if w == '-o': out = a[i + 1]; i += 2
        elif w == '--name': name = a[i + 1]; i += 2
        elif w == '--tile':
            tw, th = a[i + 1].lower().split('x'); tile = (int(tw), int(th)); i += 2
        elif w == '--key': key = int(a[i + 1], 0); i += 2
        elif w == '--own-palette': own = int(a[i + 1], 0); i += 2
        elif w == '--preview': prev = a[i + 1]; i += 2
        elif w == '--scale': scale = int(a[i + 1]); i += 2
        elif w.startswith('-'): sys.exit(f'img2inc: unknown option {w}')
        else: src = w; i += 1
    if not src:
        sys.exit('img2inc: no input')
    name = name or re.sub(r'\W', '_', os.path.splitext(os.path.basename(src))[0]).lower()
    try:
        if src.lower().endswith('.png'):
            w, h, frames = load_png(src, tile)
        else:
            w, h, frames = load_text(src, key)
    except (ArtError, OSError) as e:
        sys.exit(f'img2inc: {e}')

    # colours -> indices
    owncols = []
    idx_frames = []
    for f in frames:
        q = []
        for p in f:
            if p is None:
                q.append(key)
            elif isinstance(p, tuple) and p and p[0] == 'idx':
                q.append(p[1])
            elif own is not None:
                if p not in owncols:
                    owncols.append(p)
                q.append(own + owncols.index(p))
            else:
                q.append(1 if p == (255, 255, 255) else nearest(p, key))
        idx_frames.append(q)
    if own is not None and own + len(owncols) > 256:
        sys.exit(f'img2inc: {len(owncols)} colours do not fit from entry {own}')
    total = w * h * len(frames)
    if total > 65536:
        sys.exit(f'img2inc: {total} bytes: more than one bank (64 KB)')

    lines = [f'; generated by img2inc.py from {os.path.basename(src)} - do not edit',
             f'{name}_W = {w}', f'{name}_H = {h}', f'{name}_N = {len(frames)}',
             f'{name}_SIZE = {w * h}', f'{name}_KEY = {key}']
    if own is not None:
        lines += [f'{name}_PALN = {len(owncols)}', f'{name}_PALBASE = {own}', f'{name}_PAL:']
        for c in owncols:
            lines.append(f'        .byte   {c[0]}, {c[1]}, {c[2]}')
    lines.append(f'{name}:')
    for k, q in enumerate(idx_frames):
        lines.append(f'; frame {k}')
        for y in range(h):
            row = q[y * w:(y + 1) * w]
            for j in range(0, w, 16):
                lines.append('        .byte   ' + ', '.join(f'${v:02X}' for v in row[j:j + 16]))
    text = '\n'.join(lines) + '\n'
    if out:
        open(out, 'w').write(text)
    else:
        sys.stdout.write(text)

    if prev:
        try:
            from PIL import Image
        except ImportError:
            sys.exit('img2inc: --preview needs Pillow')
        n = len(idx_frames)
        im = Image.new('RGB', ((w + 1) * n * scale, h * scale), (255, 0, 255))
        palx = list(PAL)
        if own is not None:
            for j, c in enumerate(owncols):
                palx[own + j] = c
        for k, q in enumerate(idx_frames):
            for y in range(h):
                for x in range(w):
                    v = q[y * w + x]
                    c = palx[v] if v != key else ((200, 200, 200) if (x + y) & 1 else (150, 150, 150))
                    x0 = (k * (w + 1) + x) * scale
                    for yy in range(scale):
                        for xx in range(scale):
                            im.putpixel((x0 + xx, y * scale + yy), c)
        im.save(prev)
    return 0


if __name__ == '__main__':
    sys.exit(main())
