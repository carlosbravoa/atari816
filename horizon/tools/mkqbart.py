#!/usr/bin/env python3
"""mkqbart.py FONT.txt OUT.inc [--png PREVIEW.png] - Quabricks' art (user/qb_*.s include OUT.inc).

Everything is made here, at build time, from numbers: the game's colours (local entries 1 ..
NCOLS: the program takes that many palette entries with pal_alloc, wherever the kernel has
them, and translates the art and its drawing colours; 1.1), the beveled pastel
blocks with rounded corners as 8 bpp tiles (the corners show the background they are drawn
on: the well's empty cell, a panel, or transparent) (the well's 14 x 14, the previews' 12 x 12 and 10 x 10, dimmed ones for
a hold that cannot be used, the ghost's outline, the empty cell with its grid, the grey block
of the game-over sweep), the logo (QUABRICKS in little bricks, one pastel per letter, with a
drop shadow; 0 = transparent) and two bold big fonts (1 bpp, made from Horizon's console font
kernel/font8x12.txt, scaled 2x and 3x).

The colours follow the SDL2 Quabricks (graphics.c, tetris.c): the navy gradient, the panels,
the board, the seven pastels and their bevel (grout 0.42, highlight lightened 0.5, shadow
0.72, a 16 % gloss on the top third). Which pastel goes with which piece is this game's own."""
import sys

FONT, OUT = sys.argv[1], sys.argv[2]
PNG = sys.argv[sys.argv.index('--png') + 1] if '--png' in sys.argv else None

# ---------------------------------------------------------------- colours
def h(c):
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255)
def scale(c, f):
    return tuple(min(255, int(v * f)) for v in c)
def lighten(c, a):
    return tuple(int(v + (255 - v) * a) for v in c)
def blend(c, over, a):          # c at alpha a over 'over'
    return tuple(int(o + (v - o) * a) for v, o in zip(c, over))

BG_TOP, BG_BOT = h(0x1B1E3A), h(0x0A0B18)
BG_MID = blend(BG_TOP, BG_BOT, 0.5)
WHITE = (255, 255, 255)
BOARD = blend(h(0x05060F), BG_MID, 0xE0 / 255)
ACCENT = h(0x8FA0FF)
# the owner's seven pastels; piece order O, I, J, L, S, Z, T, each with its own pastel
PASTEL = {'gold': 0xF7D774, 'aqua': 0x76D6E3, 'peri': 0x7A93E8, 'orange': 0xF2A96B,
          'mint': 0x93DB84, 'coral': 0xEB8A8A, 'lavender': 0xC08BE0}
PIECE = ['mint', 'lavender', 'gold', 'aqua', 'coral', 'peri', 'orange']
LOGO = ['gold', 'aqua', 'peri', 'orange', 'mint', 'coral', 'lavender', 'gold', 'aqua']

cols = []                       # (name, rgb, dims with the pause)
def col(name, rgb, dim=True):
    cols.append((name, rgb, dim))
NGRAD = 8
for i in range(NGRAD):
    col(f'GRAD{i}', blend(BG_BOT, BG_TOP, i / (NGRAD - 1)))
col('PANEL', blend(WHITE, BG_MID, 0.075))
col('PANELB', blend(WHITE, BG_MID, 0.18))
col('BOARD', BOARD)
col('GRID', blend(WHITE, BOARD, 0.07))
col('GLOW', blend(ACCENT, BG_MID, 0.22))
col('TEXT', WHITE)
col('MUTED', h(0x9AA0C8))
col('ACCENT', ACCENT)
col('RED', h(0xFF5A5A))
col('SHADOW', blend((0, 0, 0), BG_MID, 0.55))
col('BTN', blend(ACCENT, BG_MID, 0.9))
col('OTEXT', WHITE, False)      # text over a dimmed screen (pause)
col('OMUTED', h(0x9AA0C8), False)
for i, p in enumerate(PIECE):
    b = h(PASTEL[p])
    col(f'P{i}GROUT', scale(b, 0.42))
    col(f'P{i}HI', lighten(b, 0.5))
    col(f'P{i}FACE', b)
    col(f'P{i}GLOSS', blend(WHITE, b, 0.16))
    col(f'P{i}LO', scale(b, 0.72))
    col(f'P{i}GHOST', blend(lighten(b, 0.1), BOARD, 110 / 255))
    col(f'P{i}GFILL', blend(b, BOARD, 26 / 255))
g = h(0x3A3F5A)
col('SWGROUT', scale(g, 0.42)); col('SWHI', lighten(g, 0.5)); col('SWFACE', g)
col('SWGLOSS', blend(WHITE, g, 0.16)); col('SWLO', scale(g, 0.72))
# (1.1) local indices 1 .. NCOLS (0: transparent / none, $FF: no paper): the program takes
# NCOLS palette entries with pal_alloc wherever the kernel has them and translates (cmap):
# the art in place at its start (qb_art0 .. qb_art1), the colours of its drawing calls
assert len(cols) <= 254, len(cols)
IDX = {n: i + 1 for i, (n, _, _) in enumerate(cols)}
RGB = {n: c for n, c, _ in cols}

def piece_shades(i):
    return {k: IDX[f'P{i}{k}'] for k in ('GROUT', 'HI', 'FACE', 'GLOSS', 'LO')}
SWEEP = {k: IDX['SW' + k] for k in ('GROUT', 'HI', 'FACE', 'GLOSS', 'LO')}

# ---------------------------------------------------------------- tiles
def rounded(x, y, w, hh, r):
    """the pixels of a rounded rectangle"""
    px = set()
    for yy in range(y, y + hh):
        for xx in range(x, x + w):
            dx = max(x + r - 1 - xx, xx - (x + w - r), 0)
            dy = max(y + r - 1 - yy, yy - (y + hh - r), 0)
            if dx * dx + dy * dy <= (r - 0.5) ** 2 + 0.6 or dx == 0 or dy == 0:
                px.add((xx, yy))
    return px

def block(size, s):
    """the owner's beveled block (graphics.c draw_block_direct) in shades s"""
    t = [[s['GROUT']] * size for _ in range(size)]
    r = max(3, size // 8) if size >= 12 else 2
    ins = max(1, size // 16)
    bev = max(2, size // 9) if size >= 12 else 1
    fx = fy = ins
    fw = fh = size - 2 * ins
    for (x, y) in rounded(fx, fy, fw, fh, r):
        t[y][x] = s['FACE']
    for x in range(fx + r, fx + fw - r):            # bottom, right: shadow
        for k in range(bev):
            t[fy + fh - 1 - k][x] = s['LO']
    for y in range(fy + r, fy + fh - r):
        for k in range(bev):
            t[y][fx + fw - 1 - k] = s['LO']
    for x in range(fx + r, fx + fw - r):            # top, left: highlight
        for k in range(bev):
            t[fy + k][x] = s['HI']
    for y in range(fy + r, fy + fh - r):
        for k in range(bev):
            t[y][fx + k] = s['HI']
    for (x, y) in rounded(fx + bev, fy + bev, fw - 2 * bev, max(1, fh // 3), max(1, r - 1)):
        if t[y][x] == s['FACE']:
            t[y][x] = s['GLOSS']
    return t

def empty(size):
    t = [[IDX['BOARD']] * size for _ in range(size)]
    for i in range(size):
        t[0][i] = IDX['GRID']
        t[i][0] = IDX['GRID']
    return t

def ghost(size, i):
    """the outline of a block (its rounded silhouette, 1 pixel in), 2 pixels wide, and a
    faint fill"""
    t = empty(size)
    inner = rounded(2, 2, size - 3, size - 3, 2)
    outer = rounded(1, 1, size - 2, size - 2, 4)
    ring = outer - rounded(3, 3, size - 6, size - 6, 2)
    for (x, y) in inner:
        t[y][x] = IDX[f'P{i}GFILL']
    for (x, y) in ring:
        t[y][x] = IDX[f'P{i}GHOST']
    return t

# (1.1) rounded corners: the pixels cut off each corner of a block (R = 2: the corner pixel
# and its two neighbours, R = 1: the corner pixel) show what lies behind the tile there: the
# well's empty cell (its grid line on the top and left), a panel, or nothing (0: keyed blits)
R = 2
def corners(size, r=R):
    cut = set()
    pat = [(0, 0)] if r == 1 else [(0, 0), (1, 0), (0, 1)]
    for (x, y) in pat:
        cut |= {(x, y), (size - 1 - x, y), (x, size - 1 - y), (size - 1 - x, size - 1 - y)}
    return cut

def over(t, back, r=R):
    """tile t with its corners showing back (a tile of the same size, or a colour)"""
    size = len(t)
    t = [row[:] for row in t]
    for (x, y) in corners(size, r):
        t[y][x] = back[y][x] if isinstance(back, list) else back
    return t

def dimmed(s):
    return {'GROUT': s['GROUT'], 'HI': s['FACE'], 'FACE': s['LO'], 'GLOSS': s['LO'], 'LO': s['GROUT']}

tiles = []                      # (name, size, rows)
E14 = empty(14)
for i in range(7):              # the well's: corners over the empty cell
    tiles.append((f'b14_{i}', 14, over(block(14, piece_shades(i)), E14)))
for i in range(7):
    tiles.append((f'g14_{i}', 14, ghost(14, i)))
tiles.append(('e14', 14, E14))
tiles.append(('s14', 14, over(block(14, SWEEP), E14)))
for i in range(7):              # hold and next: over the panel
    tiles.append((f'b12_{i}', 12, over(block(12, piece_shades(i)), IDX['PANEL'])))
for i in range(7):
    tiles.append((f'd12_{i}', 12, over(block(12, dimmed(piece_shades(i))), IDX['PANEL'])))
for i in range(7):
    tiles.append((f'b10_{i}', 10, over(block(10, piece_shades(i)), IDX['PANEL'])))
# a small decorative block for the title screen (over the gradient: keyed, 0 transparent)
tiles.append(('t10', 10, over(block(10, SWEEP), 0)))

# ---------------------------------------------------------------- font
glyphs, cur = {}, None
for ln in open(FONT):
    ln = ln.rstrip('\n')
    if ln.startswith(';') or not ln.strip():
        continue
    if ln.startswith('char '):
        cur = int(ln.split()[1], 16); glyphs[cur] = []
        continue
    glyphs[cur].append(ln.ljust(6, '.')[:6])

def glyph_rows(c):
    """art rows 1-7 (the capitals' height) of character c, 6 wide, as lists of 0 / 1"""
    g = glyphs[ord(c)]
    return [[1 if p == '#' else 0 for p in g[r]] for r in range(1, 8)]

def bold(rows):
    return [[(r[x] if x < 6 else 0) | (r[x - 1] if x else 0) for x in range(7)] for r in rows]

BIGCH = ' 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ!\'.:-/?,'
def bigfont(k):
    """k x scaled bold glyphs: 7 * k pixels wide in a cell of 8 * k (k bytes), 7 * k rows"""
    out = []
    for c in BIGCH:
        rows = bold(glyph_rows(c))
        data = []
        for r in rows:
            line = []
            for p in r:
                line += [p] * k
            line += [0] * (8 * k - len(line))
            bts = [sum(line[b * 8 + i] << (7 - i) for i in range(8)) for b in range(k)]
            for _ in range(k):
                data += bts
        out.append((c, data))
    return out

# ---------------------------------------------------------------- the logo
# (1.1) the logo's 4 x 4 bricks keep their square corners: cut, the letters read as beads
LOGOR = False
def logo():
    k = 4
    word = 'QUABRICKS'
    gap = 4
    W = len(word) * 7 * k + (len(word) - 1) * gap + 3
    H = 7 * k + 3
    img = [[0] * W for _ in range(H)]
    shadow = IDX['SHADOW']
    for pas in (0, 1):
        x0 = 0
        for n, c in enumerate(word):
            s = {kk: IDX[f'P{PIECE.index(LOGO[n])}{kk}'] for kk in ('HI', 'FACE', 'LO')}
            rows = bold(glyph_rows(c))
            for gy, r in enumerate(rows):
                for gx, p in enumerate(r):
                    if not p:
                        continue
                    for yy in range(k):
                        for xx in range(k):
                            if pas == 1 and LOGOR and xx in (0, k - 1) and yy in (0, k - 1):
                                continue        # (rounded bricks: the corners left out)
                            if pas == 0:
                                img[gy * k + yy + 3][x0 + gx * k + xx + 3] = shadow
                            else:
                                v = s['FACE']
                                if yy == 0 or xx == 0:
                                    v = s['HI']
                                if yy == k - 1 or xx == k - 1:
                                    v = s['LO']
                                img[gy * k + yy][x0 + gx * k + xx] = v
            x0 += 7 * k + gap
    return W, H, img

LW, LH, LIMG = logo()

# ---------------------------------------------------------------- write
o = ['; generated by tools/mkqbart.py - do not edit']
for n, _, _ in cols:
    o.append(f'Q_{n} = {IDX[n]}')
o.append(f'NCOLS = {len(cols)}')
o.append('; the colours of local entries 1 .. NCOLS: red, green, blue')
o.append('qb_rgb:')
for n, c, d in cols:
    o.append(f'        .byte   {c[0]}, {c[1]}, {c[2]}')
o.append('; and whether each dims with the pause (1)')
o.append('qb_dims: .byte  ' + ', '.join(str(1 if d else 0) for n, c, d in cols))
o.append('; the art (tiles, then the logo): local entries, translated in place at the start')
o.append('qb_art0:')
for name, size, rows in tiles:
    o.append(f't_{name}:')
    for r in rows:
        o.append('        .byte   ' + ', '.join(str(v) for v in r))
o.append(f'LOGO_W = {LW}')
o.append(f'LOGO_H = {LH}')
o.append('t_logo:')
for r in LIMG:
    for i in range(0, LW, 32):
        o.append('        .byte   ' + ', '.join(str(v) for v in r[i:i + 32]))
o.append('qb_art1:')
o.append('; the tiles of each piece: well 14, ghost 14, preview 12, dimmed 12, preview 10')
for pre in ('b14', 'g14', 'b12', 'd12', 'b10'):
    o.append(f'tt_{pre}: .addr  ' + ', '.join(f't_{pre}_{i}' for i in range(7)))
o.append(f'BIGCH = {len(BIGCH)}')
o.append('big_chars: .byte ' + ', '.join(str(ord(c)) for c in BIGCH))
for k in (2, 3):
    o.append(f'; font {k}x: {7 * k} rows of {k} bytes per character (BIGCH order)')
    o.append(f'big{k}:')
    for c, data in bigfont(k):
        o.append('        .byte   ' + ', '.join(f'${b:02X}' for b in data) + f'   ; {c!r}')
open(OUT, 'w').write('\n'.join(o) + '\n')

if PNG:
    from PIL import Image
    pal = {IDX[n]: c for n, c, _ in cols}
    pal[0] = (40, 40, 60)
    im = Image.new('RGB', (400, 200), BG_MID)
    x, y = 4, 4
    for name, size, rows in tiles:
        for yy, r in enumerate(rows):
            for xx, v in enumerate(r):
                im.putpixel((x + xx, y + yy), pal[v])
        x += size + 4
        if x > 330:
            x, y = 4, y + 18
    for yy, r in enumerate(LIMG):
        for xx, v in enumerate(r):
            if v:
                im.putpixel((4 + xx, 120 + yy), pal[v])
    im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(PNG)
