#!/usr/bin/env python3
"""mkfcart.py OUT.inc [--png PREVIEW.png] - FreeCell's art (user/freecell.s includes OUT.inc).

Everything is made here from numbers and from the little drawings below (this game's own: no
font or picture of another program is used):
  - the game's colours (local 1 .. NCOLS: the program takes palette entries for them with
    pal_alloc and sets them; when none is free it uses the nearest colour of the system
    cube, fb_*), local 0 is the key (transparent corners);
  - two 40 x 56 templates: a blank card (ivory, a grey border, rounded corners) and an empty
    place (a light outline round a darker inside);
  - 1 bpp masks: the ranks (A 2-10 J Q K, 6 pixels wide, 9 high; "10" 11 wide), the four suits
    small (7 x 8, beside the rank), big (18 x 18, the middle of a card, the empty foundations)
    and very big (26 x 26, the aces), medium (10 x 10, the court cards), and the court letters
    doubled (12-14 x 18).
The program composes the 52 faces from these at its start (fc_draw.s, mkfaces). --png draws
every card as the program will, for a look before building."""
import sys

OUT = sys.argv[1]
PNG = sys.argv[sys.argv.index('--png') + 1] if '--png' in sys.argv else None
CW, CH = 40, 56

# ---------------------------------------------------------------- colours
# (name, rgb); local index = position + 1
COLS = [
    ('FELT',  (30, 72, 112)),     # the table: a deep blue
    ('FELTD', (20, 50, 82)),      # the inside of an empty place
    ('FELTL', (78, 122, 164)),    # outlines and hints of the empty places
    ('CARD',  (250, 248, 238)),   # the face of a card: ivory
    ('EDGE',  (96, 100, 116)),    # its border
    ('RED',   (206, 30, 44)),     # hearts, diamonds
    ('INK',   (26, 28, 40)),      # spades, clubs
    ('SEL',   (255, 196, 40)),    # the frame round a selected card or run
    ('STRIP', (14, 34, 58)),      # the status line
    ('STXT',  (196, 214, 236)),   # its text
    ('HINT',  (255, 226, 120)),   # its notes ("No more moves")
]
IDX = {n: i + 1 for i, (n, _) in enumerate(COLS)}
RGB = dict(COLS)

def cube(c):
    """the nearest colour of the system cube (16 + 36 r + 6 g + b, levels 0, 51 .. 255)"""
    q = [min(5, (v + 25) // 51) for v in c]
    return 16 + 36 * q[0] + 6 * q[1] + q[2]

# ---------------------------------------------------------------- templates
def rounded_card(fill, border, key=0):
    """40 x 56: a 1-pixel border, corners cut (two pixels on each edge at each corner)"""
    t = [[fill] * CW for _ in range(CH)]
    for x in range(CW):
        t[0][x] = t[CH - 1][x] = border
    for y in range(CH):
        t[y][0] = t[y][CW - 1] = border
    for (x, y) in ((0, 0), (1, 0), (0, 1)):
        for (xx, yy) in ((x, y), (CW - 1 - x, y), (x, CH - 1 - y), (CW - 1 - x, CH - 1 - y)):
            t[yy][xx] = key
    for (xx, yy) in ((1, 1), (CW - 2, 1), (1, CH - 2), (CW - 2, CH - 2)):
        t[yy][xx] = border
    return t

T_CARD = rounded_card(IDX['CARD'], IDX['EDGE'])
T_SLOT = rounded_card(IDX['FELTD'], IDX['FELTL'])

# ---------------------------------------------------------------- the ranks (6 x 9)
RANKS = {
'A': """
..##..
.####.
##..##
##..##
##..##
######
##..##
##..##
##..##""",
'2': """
.####.
##..##
....##
...##.
..##..
.##...
##....
##....
######""",
'3': """
.####.
##..##
....##
..###.
....##
....##
....##
##..##
.####.""",
'4': """
...##.
..###.
.####.
##.##.
##.##.
######
...##.
...##.
...##.""",
'5': """
######
##....
##....
#####.
....##
....##
....##
##..##
.####.""",
'6': """
..###.
.##...
##....
#####.
##..##
##..##
##..##
##..##
.####.""",
'7': """
######
....##
....##
...##.
...##.
..##..
..##..
.##...
.##...""",
'8': """
.####.
##..##
##..##
.####.
##..##
##..##
##..##
##..##
.####.""",
'9': """
.####.
##..##
##..##
##..##
.#####
....##
....##
...##.
.###..""",
'10': """
.##...####.
###..##..##
.##..##..##
.##..##..##
.##..##..##
.##..##..##
.##..##..##
.##..##..##
####..####.""",
'J': """
..####
....##
....##
....##
....##
....##
##..##
##..##
.####.""",
'Q': """
.####..
##..##.
##..##.
##..##.
##..##.
##.###.
##..##.
.####..
....##.""",
'K': """
##..##
##..##
##.##.
####..
###...
####..
##.##.
##..##
##..##""",
}
RANK_ORDER = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K']

def parse(s):
    rows = [r for r in s.strip('\n').split('\n')]
    w = max(len(r) for r in rows)
    return [[1 if (x < len(r) and r[x] == '#') else 0 for x in range(w)] for r in rows]

# ---------------------------------------------------------------- the suits
# order: clubs, diamonds, hearts, spades (card = suit * 13 + rank); red: diamonds, hearts
SUITS = ['clubs', 'diamonds', 'hearts', 'spades']
SMALL = {
'clubs': """
..###..
..###..
##.#.##
#######
#######
##.#.##
...#...
..###..""",
'diamonds': """
...#...
..###..
.#####.
#######
.#####.
..###..
...#...""",
'hearts': """
.##.##.
#######
#######
#######
.#####.
..###..
...#...""",
'spades': """
...#...
..###..
.#####.
#######
#######
##.#.##
...#...
..###..""",
}

def inside(suit, u, v):
    """is the point u, v (0..1, v down) inside the suit's shape"""
    def circ(cx, cy, r):
        return (u - cx) ** 2 + (v - cy) ** 2 <= r * r
    def tri(a, b, c):
        def s(p, q, r):
            return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
        p = (u, v)
        d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
        neg = d1 < 0 or d2 < 0 or d3 < 0
        pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (neg and pos)
    if suit == 'diamonds':
        return abs(u - 0.5) / 0.40 + abs(v - 0.5) / 0.5 <= 1
    if suit == 'hearts':
        return (circ(0.27, 0.31, 0.25) or circ(0.73, 0.31, 0.25)
                or tri((0.035, 0.40), (0.965, 0.40), (0.5, 0.97)))
    if suit == 'spades':
        return (circ(0.27, 0.56, 0.23) or circ(0.73, 0.56, 0.23)
                or tri((0.05, 0.50), (0.95, 0.50), (0.5, 0.02))
                or tri((0.5, 0.58), (0.30, 0.99), (0.70, 0.99)))
    if suit == 'clubs':
        return (circ(0.5, 0.25, 0.22) or circ(0.25, 0.57, 0.22) or circ(0.75, 0.57, 0.22)
                or circ(0.5, 0.52, 0.14) or tri((0.5, 0.45), (0.30, 0.99), (0.70, 0.99)))

def raster(suit, n):
    ss = 5
    m = []
    for y in range(n):
        row = []
        for x in range(n):
            k = sum(inside(suit, (x + (i + 0.5) / ss) / n, (y + (j + 0.5) / ss) / n)
                    for i in range(ss) for j in range(ss))
            row.append(1 if k * 2 >= ss * ss else 0)
        m.append(row)
    return m

def double(m):
    out = []
    for r in m:
        rr = []
        for p in r:
            rr += [p, p]
        out += [rr, rr[:]]
    return out

MASKS = []                      # (label, mask)
for r in RANK_ORDER:
    MASKS.append((f'r_{r}', parse(RANKS[r])))
for s in SUITS:
    MASKS.append((f'ss_{s}', parse(SMALL[s])))
for s in SUITS:
    MASKS.append((f'sb_{s}', raster(s, 18)))
for s in SUITS:
    MASKS.append((f'sa_{s}', raster(s, 26)))
for s in SUITS:
    MASKS.append((f'sm_{s}', raster(s, 10)))
for c in 'JQK':
    MASKS.append((f'cl_{c}', double(parse(RANKS[c]))))
M = dict(MASKS)

# ---------------------------------------------------------------- the faces (as the program
# composes them; the same numbers are in fc_draw.s, mkfaces)
IX, IY = 3, 3                   # the rank's corner
def face(card):
    s, r = SUITS[card // 13], card % 13
    col = IDX['RED'] if s in ('diamonds', 'hearts') else IDX['INK']
    t = [row[:] for row in T_CARD]
    def put(m, x0, y0):
        for y, row in enumerate(m):
            for x, p in enumerate(row):
                if p:
                    t[y0 + y][x0 + x] = col
    rm = M['r_' + RANK_ORDER[r]]
    put(rm, IX, IY)
    put(M['ss_' + s], IX + len(rm[0]) + 2, IY)
    if r == 0:
        put(M['sa_' + s], (CW - 26) // 2, 22)
    elif r >= 10:
        for x in range(5, CW - 5):
            t[16][x] = t[CH - 5][x] = col
        for y in range(16, CH - 4):
            t[y][5] = t[y][CW - 6] = col
        lm = M['cl_' + RANK_ORDER[r]]
        put(lm, (CW - len(lm[0])) // 2, 20)
        put(M['sm_' + s], (CW - 10) // 2, 41)
    else:
        put(M['sb_' + s], (CW - 18) // 2, 24)
    return t

# ---------------------------------------------------------------- write
def mbytes(m):
    w = len(m[0])
    out = []
    for row in m:
        for b in range(0, w, 8):
            out.append(sum(row[b + i] << (7 - i) for i in range(8) if b + i < w))
    return out

o = ['; generated by tools/mkfcart.py - do not edit']
for n, _ in COLS:
    o.append(f'FC_{n} = {IDX[n]}')
o.append(f'NCOLS = {len(COLS)}')
o.append('; local colours 1 .. NCOLS: red, green, blue; then the nearest system cube entry of each')
o.append('fc_rgb:')
for n, c in COLS:
    o.append(f'        .byte   {c[0]}, {c[1]}, {c[2]}')
o.append('fc_fb:  .byte   ' + ', '.join(str(cube(c)) for n, c in COLS))
for name, t in (('t_card', T_CARD), ('t_slot', T_SLOT)):
    o.append(f'{name}:')
    for row in t:
        o.append('        .byte   ' + ', '.join(str(v) for v in row))
o.append('; masks: u8 width, u8 height, then the rows (1 bpp, bit 7 leftmost, (width + 7) / 8 bytes)')
for name, m in MASKS:
    o.append(f'm_{name}: .byte {len(m[0])}, {len(m)}')
    bb = mbytes(m)
    for i in range(0, len(bb), 24):
        o.append('        .byte   ' + ', '.join(f'${b:02X}' for b in bb[i:i + 24]))
o.append('; the masks of each rank, each suit (clubs, diamonds, hearts, spades)')
o.append('mt_rank: .addr  ' + ', '.join('m_r_' + r for r in RANK_ORDER))
for k in ('ss', 'sb', 'sa', 'sm'):
    o.append(f'mt_{k}:   .addr  ' + ', '.join(f'm_{k}_{s}' for s in SUITS))
o.append('mt_cl:   .addr  m_cl_J, m_cl_Q, m_cl_K')
open(OUT, 'w').write('\n'.join(o) + '\n')

if PNG:
    from PIL import Image
    pal = {IDX[n]: c for n, c in COLS}
    pal[0] = RGB['FELT']
    im = Image.new('RGB', (13 * 44 + 4, 5 * 60 + 4), RGB['FELT'])
    for card in range(52):
        t = face(card)
        x0, y0 = 4 + (card % 13) * 44, 4 + (card // 13) * 60
        for y in range(CH):
            for x in range(CW):
                im.putpixel((x0 + x, y0 + y), pal[t[y][x]])
    for k, s in enumerate(SUITS):          # the empty places: a foundation each, a cell
        t = [row[:] for row in T_SLOT]
        for y, row in enumerate(M['sb_' + s]):
            for x, p in enumerate(row):
                if p:
                    t[24 + y][11 + x] = IDX['FELTL']
        for y in range(CH):
            for x in range(CW):
                im.putpixel((4 + k * 44 + x, 4 + 4 * 60 + y), pal[t[y][x]])
    im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(PNG)
