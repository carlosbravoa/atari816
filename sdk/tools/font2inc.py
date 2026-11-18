#!/usr/bin/env python3
"""font2inc.py - 1 bpp glyphs (a font, icons) to a ca65 include file.

    font2inc.py GLYPHS [-o OUT.inc] [--name NAME] [--cell WxH] [--first N]
                [--prop] [--preview OUT.png]

Horizon's win_draw has two built-in fonts (WD_TEXT: font 0 the proportional UI font,
font 1 the fixed 8x12 font). For anything else (big score digits, a title, a game font)
keep the glyphs as 1 bpp bitmaps and expand them to 8 bpp yourself before a WD_KBLIT
(see examples/lantern: bigtext.s). 1 bpp keeps them small: 8 bytes for an 8x8 glyph.

GLYPHS is a text file (no Pillow needed) or a PNG grid (needs Pillow).

Text file: one block per glyph:
    char 41            ; the character code in hex (here 'A'), or: char 'A'
    ..XXXX..           ; rows: '.' or ' ' = 0, any other character = 1
    .XX..XX.
    ...
All glyphs have the same height (the rows of the first one); widths may differ with
--prop (each glyph's own width, an advance table is written), else every glyph is as
wide as the widest. Lines starting with ';' are comments.

PNG grid: --cell WxH cells, 16 per row, left to right, top to bottom, starting at
character --first (default 32); a pixel darker than 50 % (or opaque, for a PNG with
alpha) is a 1.

Output:
    NAME_H = 12          ; rows
    NAME_W = 8           ; the widest glyph (= every glyph without --prop)
    NAME_BPR = 1         ; bytes per row (bit 7 of the first byte = the leftmost pixel)
    NAME_FIRST = 32      ; the first character code
    NAME_COUNT = 59      ; glyphs (codes FIRST .. FIRST + COUNT - 1; missing ones blank)
    NAME_GSIZE = 12      ; bytes per glyph (H * BPR): glyph c at NAME + (c - FIRST) * GSIZE
    NAME_ADV:            ; (--prop) COUNT bytes, the advance of each glyph (width + 1)
    NAME:                ; the bitmaps
"""
import os
import re
import sys


def load_text(path):
    glyphs, cur, code = {}, None, None
    for no, raw in enumerate(open(path), 1):
        ln = raw.rstrip('\n')
        if ln.lstrip().startswith(';'):
            continue
        m = re.match(r"\s*char\s+(?:'(.)'|([0-9a-fA-F]+))\s*(;.*)?$", ln)
        if m:
            code = ord(m.group(1)) if m.group(1) else int(m.group(2), 16)
            cur = glyphs.setdefault(code, [])
            continue
        if cur is None:
            if ln.strip():
                raise SystemExit(f'font2inc: {path}:{no}: pixels before the first "char" line')
            continue
        s = ln.split(';', 1)[0].rstrip()
        if not s:
            continue
        cur.append([0 if c in '. ' else 1 for c in s])
    return glyphs


def load_png(path, cell, first):
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit('font2inc: PNG input needs Pillow; a text file does not')
    im = Image.open(path).convert('RGBA')
    cw, ch = cell
    glyphs = {}
    cols, rows = im.size[0] // cw, im.size[1] // ch
    for gy in range(rows):
        for gx in range(cols):
            code = first + gy * cols + gx
            g = []
            for y in range(ch):
                row = []
                for x in range(cw):
                    r, gg, b, a = im.getpixel((gx * cw + x, gy * ch + y))
                    row.append(1 if a >= 128 and (r + gg + b) < 384 else 0)
                g.append(row)
            glyphs[code] = g
    return glyphs


def main():
    a = sys.argv[1:]
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); return 0
    src, out, name, cell, first, prop, prev = None, None, None, None, 32, False, None
    i = 0
    while i < len(a):
        w = a[i]
        if w == '-o': out = a[i + 1]; i += 2
        elif w == '--name': name = a[i + 1]; i += 2
        elif w == '--cell':
            cw, chh = a[i + 1].lower().split('x'); cell = (int(cw), int(chh)); i += 2
        elif w == '--first': first = int(a[i + 1], 0); i += 2
        elif w == '--prop': prop = True; i += 1
        elif w == '--preview': prev = a[i + 1]; i += 2
        elif w.startswith('-'): sys.exit(f'font2inc: unknown option {w}')
        else: src = w; i += 1
    if not src:
        sys.exit('font2inc: no input')
    name = name or re.sub(r'\W', '_', os.path.splitext(os.path.basename(src))[0]).lower()
    if src.lower().endswith('.png'):
        if not cell:
            sys.exit('font2inc: a PNG needs --cell WxH')
        glyphs = load_png(src, cell, first)
    else:
        glyphs = load_text(src)
    if not glyphs:
        sys.exit('font2inc: no glyphs')
    h = max(len(g) for g in glyphs.values())
    widths = {c: (max((len(r) for r in g), default=0)) for c, g in glyphs.items()}
    if prop:
        # a glyph's own width: its rightmost ink column + 1 (a space keeps its drawn width)
        for c, g in glyphs.items():
            ink = [x for r in g for x, v in enumerate(r) if v]
            widths[c] = (max(ink) + 1) if ink else widths[c]
    wmax = max(widths.values())
    bpr = (wmax + 7) // 8
    lo, hi = min(glyphs), max(glyphs)
    if src.lower().endswith('.png'):
        lo = min(lo, first)
    count = hi - lo + 1
    lines = [f'; generated by font2inc.py from {os.path.basename(src)} - do not edit',
             f'{name}_H = {h}', f'{name}_W = {wmax}', f'{name}_BPR = {bpr}',
             f'{name}_FIRST = {lo}', f'{name}_COUNT = {count}', f'{name}_GSIZE = {h * bpr}']
    if prop:
        lines.append(f'{name}_ADV:')
        adv = [widths.get(c, wmax) + 1 if c in glyphs else wmax + 1 for c in range(lo, hi + 1)]
        for j in range(0, count, 16):
            lines.append('        .byte   ' + ', '.join(str(v) for v in adv[j:j + 16]))
    lines.append(f'{name}:')
    for c in range(lo, hi + 1):
        g = glyphs.get(c, [])
        ch = chr(c) if 32 < c < 127 and chr(c) not in '\\;' else f'${c:02X}'
        bytes_ = []
        for y in range(h):
            row = g[y] if y < len(g) else []
            v = 0
            for x in range(bpr * 8):
                v = (v << 1) | (row[x] if x < len(row) else 0)
            bytes_ += list(v.to_bytes(bpr, 'big'))
        lines.append('        .byte   ' + ', '.join(f'${b:02X}' for b in bytes_) + f'   ; {ch}')
    text = '\n'.join(lines) + '\n'
    if out:
        open(out, 'w').write(text)
    else:
        sys.stdout.write(text)
    if prev:
        from PIL import Image
        s = 3
        im = Image.new('RGB', ((wmax + 1) * 16 * s, (h + 1) * ((count + 15) // 16) * s), (230, 230, 230))
        for k, c in enumerate(range(lo, hi + 1)):
            g = glyphs.get(c, [])
            for y, row in enumerate(g):
                for x, v in enumerate(row):
                    if v:
                        for yy in range(s):
                            for xx in range(s):
                                im.putpixel((((k % 16) * (wmax + 1) + x) * s + xx,
                                             ((k // 16) * (h + 1) + y) * s + yy), (0, 0, 0))
        im.save(prev)
    return 0


if __name__ == '__main__':
    sys.exit(main())
