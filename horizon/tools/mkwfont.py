#!/usr/bin/env python3
"""mkwfont.py FONT8x12.txt OUT.inc - the type faces of Write (user/write.s), all made at build
time from the console font's own (original) glyph art, ASCII 32-126:

  BODY  the proportional UI font: each glyph cut to its ink columns, rows 2-10 of the 8x12
        cell (9 rows: capitals 7, x-height 6, descenders 2), advance = ink width + 1
  BOLD  BODY made bold: every ink pixel doubled one pixel to the right; where that would
        close a one-pixel gap between two strokes (m, w, M, W, #, ...) a blank column is
        put in first, so the gap stays open (advance = the new ink width + 1)
  FIX   the 8x12 console font itself (cell rows 1-10; 7 pixels a character, as the
        glyphs are at most 6 wide): code
  H1    BODY scaled 2x with EPX smoothing (rounded diagonals, no staircase of 2x2 blocks),
        then made bold as above: 18 rows, letter spacing 2
  H2    BODY scaled 3x (Scale3x), halved with a 2-of-4 threshold (= 1.5x, 14 rows), bold
  (H3 is BOLD at the body size.)

For each face F the output has
  F_adv:  95 bytes, the advance of each glyph in pixels
  F_ish:  ROWS bytes: the italic shear of each row (pixels to the right, signed), so the
          row-wise shear leans the glyph about its baseline
and constants F_ROWS, F_BPR, F_BASE (the baseline row: the lowest row of a capital),
F_BMO: where its bitmaps start in the blob of all the faces' bitmaps (glyph k at F_BMO +
k * ROWS * BPR; ROWS rows of BPR bytes each, bit 7 of the first byte = the leftmost pixel;
BPR = 1 when every glyph is at most 8 pixels wide, else 2). The blob (WF_SIZE bytes) is
given LZSS-compressed (wf_lz, see lzss() below): Write unpacks it at its start into a
bank of its own, so the program file stays under the loader's 64 KB.
The toolbar's icons (16 x 14 pixel art, below: '#' the ink, '+' a second, grey ink) go
there too: tbi_bm, for each button in order 14 rows of 4 bytes (the ink's two bytes, then
the grey's; bit 7 of the first byte = the leftmost pixel)."""
import sys

def load(path):
    glyphs, cur = {}, None
    for ln in open(path):
        ln = ln.rstrip('\n')
        if ln.startswith(';') or not ln.strip():
            continue
        if ln.startswith('char '):
            cur = int(ln.split()[1], 16); glyphs[cur] = []
            continue
        glyphs[cur].append(ln)
    return glyphs

G = load(sys.argv[1])

def body(c):
    rows = (G[c] + ['......'] * 10)[:10][1:10]          # cell rows 2..10
    if c == 32:
        return [[0, 0] for _ in range(9)], 3
    cols = [i for i in range(6) if any(r[i] == '#' for r in rows)]
    lo, hi = min(cols), max(cols)
    return [[1 if r[i] == '#' else 0 for i in range(lo, hi + 1)] for r in rows], hi - lo + 2

def fix(c):
    rows = (G[c] + ['......'] * 10)[:10]                # cell rows 1..10
    return [[0] + [1 if p == '#' else 0 for p in r[:6]] + [0] for r in rows], 7

def epx(bm):
    h, w = len(bm), len(bm[0])
    g = lambda y, x: bm[y][x] if 0 <= y < h and 0 <= x < w else 0
    out = [[0] * (2 * w) for _ in range(2 * h)]
    for y in range(h):
        for x in range(w):
            P, A, B, C, D = g(y, x), g(y - 1, x), g(y, x + 1), g(y, x - 1), g(y + 1, x)
            o = [P] * 4
            if C == A and C != D and A != B: o[0] = A
            if A == B and A != C and B != D: o[1] = B
            if D == C and D != B and C != A: o[2] = C
            if B == D and B != A and D != C: o[3] = D
            out[2 * y][2 * x], out[2 * y][2 * x + 1] = o[0], o[1]
            out[2 * y + 1][2 * x], out[2 * y + 1][2 * x + 1] = o[2], o[3]
    return out

def scale3x(bm):
    h, w = len(bm), len(bm[0])
    g = lambda y, x: bm[y][x] if 0 <= y < h and 0 <= x < w else 0
    out = [[0] * (3 * w) for _ in range(3 * h)]
    for y in range(h):
        for x in range(w):
            A, B, C = g(y - 1, x - 1), g(y - 1, x), g(y - 1, x + 1)
            D, E, F = g(y, x - 1), g(y, x), g(y, x + 1)
            Gg, H, I = g(y + 1, x - 1), g(y + 1, x), g(y + 1, x + 1)
            e = [E] * 9
            if B != H and D != F:
                e[0] = D if D == B else E
                e[1] = B if (D == B and E != C) or (B == F and E != A) else E
                e[2] = F if B == F else E
                e[3] = D if (D == B and E != Gg) or (D == H and E != A) else E
                e[5] = F if (B == F and E != I) or (H == F and E != C) else E
                e[6] = D if D == H else E
                e[7] = H if (D == H and E != I) or (H == F and E != Gg) else E
                e[8] = F if H == F else E
            for k in range(9):
                out[3 * y + k // 3][3 * x + k % 3] = e[k]
    return out

def half(bm):
    bm = bm + [[0] * len(bm[0])] * (len(bm) % 2)
    w = len(bm[0]) + len(bm[0]) % 2
    g = lambda y, x: bm[y][x] if x < len(bm[0]) else 0
    return [[1 if g(y, x) + g(y, x + 1) + g(y + 1, x) + g(y + 1, x + 1) >= 2 else 0
             for x in range(0, w, 2)] for y in range(0, len(bm), 2)]

def trim(bm):
    """cut empty columns at both sides"""
    cols = [i for i in range(len(bm[0])) if any(r[i] for r in bm)]
    if not cols:
        return bm
    return [r[min(cols):max(cols) + 1] for r in bm]

def bold(bm):
    w = len(bm[0])
    crit = [k for k in range(1, w - 1) if any(r[k - 1] and not r[k] and r[k + 1] for r in bm)]
    cols = []
    for k in range(w):
        cols.append(k)
        if k in crit:
            cols.append(None)
    nb = [[(r[k] if k is not None else 0) for k in cols] for r in bm]
    return [[1 if (row[i] or (i > 0 and row[i - 1])) else 0 for i in range(len(row))] + [row[-1]]
            for row in nb]

# the toolbar's icons, in the order of its buttons
ICONS = {
'undo': """
................
................
....#...........
...##...........
..###########...
.############+..
..###.......+##.
...##........##.
....#........##.
.............##.
............+##.
......+#######..
......#######...
................""",
'redo': None,
'bold': """
................
..########......
..###...###.....
..###...###.....
..###...###.....
..###..###......
..#######.......
..###...###.....
..###....###....
..###....###....
..###...###.....
..#########.....
................
................""",
'ital': """
................
......#######...
.........##.....
.........##.....
........##......
........##......
.......##.......
.......##.......
......##........
......##........
.....##.........
...#######......
................
................""",
'code': """
................
.........##.....
.........##.....
...##...##.##...
..##....##..##..
.##....##....##.
##.....##.....##
.##...##.....##.
..##..##....##..
...####....##...
.....##.........
....##..........
....##..........
................""",
'h1': """
................
.##....##.......
.##....##.......
.##....##.......
.##....##.......
.#########......
.#########...#..
.##....##...##..
.##....##....#..
.##....##....#..
.##....##....#..
.##....##...###.
................
................""",
'h2': """
................
.##....##.......
.##....##.......
.##....##.......
.##....##.......
.#########......
.#########..##..
.##....##..#..#.
.##....##....#..
.##....##...#...
.##....##..#....
.##....##..####.
................
................""",
'h3': """
................
.##....##.......
.##....##.......
.##....##.......
.##....##.......
.#########......
.#########.###..
.##....##.....#.
.##....##...##..
.##....##.....#.
.##....##.....#.
.##....##..###..
................
................""",
'norm': """
................
....########....
..######.#.#....
.#######.#.#....
.#######.#.#....
.#######.#.#....
..######.#.#....
....####.#.#....
.......#.#.#....
.......#.#.#....
.......#.#.#....
.......#.#.#....
................
................""",
'bul': """
................
.##.............
####.++++++++++.
####.++++++++++.
.##.............
................
.##.............
####.++++++++++.
####.++++++++++.
.##.............
................
.##.............
####.++++++++++.
####.++++++++++.""",
'num': """
.#..............
##...++++++++++.
.#...++++++++++.
.#..............
###.............
###.............
..#..++++++++++.
.#...++++++++++.
#...............
###.............
###.............
.##..++++++++++.
..#..++++++++++.
###.............""",
'quote': """
................
.###..###.......
####.####.......
####.####.......
.###..###.......
..##...##.......
.##...##........
##...##.........
................
...++++++++++++.
................
...++++++++++++.
................
...++++++++.....""",
'rule': """
................
.++++++++++++++.
................
.++++++++++.....
................
................
################
################
................
................
.++++++++++++++.
................
.+++++++++......
................""",
}
ICONS['redo'] = '\n'.join(r[::-1] for r in ICONS['undo'].split('\n'))
ORDER = ['undo', 'redo', 'bold', 'ital', 'code', 'h1', 'h2', 'h3', 'norm', 'bul', 'num', 'quote', 'rule']
def icon_rows(name):
    r = [l for l in ICONS[name].split('\n') if l != '']
    assert len(r) == 14 and all(len(x) == 16 for x in r), (name, [len(x) for x in r], len(r))
    return r

faces = {}
B, BB, F, H1, H2 = [], [], [], [], []
for c in range(32, 127):
    bm, adv = body(c)
    B.append((bm, adv))
    if c == 32:
        BB.append((bm, 4))
        H1.append(([[0, 0] for _ in range(18)], 7))
        H2.append(([[0, 0] for _ in range(14)], 6))
    else:
        b = bold(bm)
        BB.append((b, len(b[0]) + 1))
        e = bold(epx(bm))
        H1.append((e, len(e[0]) + 2))
        s = bold(trim(half(scale3x(bm) + [[0] * (3 * len(bm[0]))])))
        H2.append((s, len(s[0]) + 2))
    F.append(fix(c))

def shear(rows, base, step):
    return [max(-1, (base - r) // step) if r <= base else -1 for r in range(rows)]

def lzss(data):
    """LZSS: groups of a flag byte (bit 0 first: 1 a literal byte, 0 a match) and 8 items;
    a match is 2 bytes: the distance back (1-4095, 12 bits), the length - 3 (4 bits) on top"""
    out, i, n = bytearray(), 0, len(data)
    while i < n:
        flags, items = 0, bytearray()
        for bit in range(8):
            if i >= n:
                break
            best, dist = 0, 0
            for o in range(max(0, i - 4095), i):
                l = 0
                while i + l < n and l < 18 and data[o + l] == data[i + l]:
                    l += 1
                if l > best:
                    best, dist = l, i - o
            if best >= 3:
                items += bytes([dist & 255, (dist >> 8) | ((best - 3) << 4)])
                i += best
            else:
                flags |= 1 << bit
                items.append(data[i])
                i += 1
        out.append(flags)
        out += items
    return bytes(out)

def unlzss(data, size):
    out, i = bytearray(), 0
    while len(out) < size:
        flags = data[i]; i += 1
        for bit in range(8):
            if len(out) >= size:
                break
            if flags >> bit & 1:
                out.append(data[i]); i += 1
            else:
                dist = data[i] | (data[i + 1] & 15) << 8
                ln = (data[i + 1] >> 4) + 3
                i += 2
                for _ in range(ln):
                    out.append(out[-dist])
    return bytes(out)

BLOB = bytearray()

def emit(name, glyphs, rows, base, step, out):
    bpr = 1 if all(len(g[0][0]) <= 8 for g in glyphs) else 2
    assert all(len(g[0]) == rows for g in glyphs), name
    assert all(len(g[0][0]) <= 8 * bpr for g in glyphs), name
    out.append(f'{name}_ROWS = {rows}')
    out.append(f'{name}_BPR = {bpr}')
    out.append(f'{name}_BASE = {base}')
    out.append(f'{name}_BMO = {len(BLOB)}')
    out.append(f'{name}_adv:')
    for i in range(0, 95, 19):
        out.append('        .byte   ' + ', '.join(str(g[1]) for g in glyphs[i:i + 19]))
    out.append(f'{name}_ish:')
    out.append('        .byte   ' + ', '.join(str(v & 255) for v in shear(rows, base, step)))
    for k, (bm, _) in enumerate(glyphs):
        for r in bm:
            v = 0
            for i, p in enumerate(r):
                if p:
                    v |= 1 << (8 * bpr - 1 - i)
            BLOB.extend([v >> 8, v & 255] if bpr == 2 else [v])

out = ['; generated by tools/mkwfont.py from kernel/font8x12.txt - do not edit']
emit('FB', B, 9, 6, 3, out)
emit('FBB', BB, 9, 6, 3, out)
emit('FF', F, 10, 7, 3, out)
emit('FH1', H1, 18, 13, 5, out)
emit('FH2', H2, 14, 10, 4, out)
# the bitmaps of all the faces (glyph k of face F at F_BMO + k * F_ROWS * F_BPR),
# compressed: Write unpacks them at its start (a program file must stay under 64 KB)
z = lzss(bytes(BLOB))
assert unlzss(z, len(BLOB)) == bytes(BLOB)
out.append(f'WF_SIZE = {len(BLOB)}')
out.append('wf_lz:')
for k in range(0, len(z), 24):
    out.append('        .byte   ' + ', '.join(f'${x:02X}' for x in z[k:k + 24]))
# the toolbar's icons
out.append('TBI_ROWS = 14')
out.append('tbi_bm:')
for name in ORDER:
    by = []
    for r in icon_rows(name):
        a = sum(1 << (15 - i) for i, ch in enumerate(r) if ch == '#')
        b = sum(1 << (15 - i) for i, ch in enumerate(r) if ch == '+')
        by += [a >> 8, a & 255, b >> 8, b & 255]
    for k in range(0, len(by), 28):
        out.append('        .byte   ' + ', '.join(f'${x:02X}' for x in by[k:k + 28]) + (f'   ; {name}' if k == 0 else ''))
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
