#!/usr/bin/env python3
"""mksaver.py ICONS.txt FONT.txt OUT.inc [--png PREVIEW.png] - (0.24) the screen saver's art
(user/saver.s includes OUT.inc).

Everything is 4 bpp sprite images for Marga (two pixels a byte, the left one in the high nibble,
0 = transparent), made at build time from the system's own pictures:
  - six desktop icons (sdfiles/icons.txt, 32 x 32): each icon's colours (at most 15) become the
    entries 1-15 of its own palette bank;
  - the About box's eight rainbow stripes (user/about.s), 16 x 32: colours 1-8;
  - the word "Atari816" in the console font (kernel/font8x12.txt), made bold, as two 32 x 16
    images: a pixel's colour is 1 + its row (1-12), so the program colours it row by row;
  - a star, 16 x 16: 1 the rays' tips, 2 the rays, 3 the centre (the program makes it twinkle),
    three times: colours 1-3, 4-6 and 7-9 (three phases in one palette bank).
OUT.inc: the labels sv_icons (6 x 512 bytes), sv_stripes (256), sv_word (2 x 256), sv_star
(3 x 128), and sv_pal: the palette banks 2-8 (stripes, then the six icons), 7 x 16 x 3 bytes red,
green, blue, for one pal_set at entry 32; sv_hue: 64 colours (red, green, blue) around a soft
colour wheel for the word; sv_twk: 32 brightness levels of the star's three colours (9 bytes
each); sv_fb: the stripes again at 8 bpp (16 x 32, 0 = black; entries 33-40: bank 2), for the
version without sprites."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ICONS = ['SD', 'ATARI', 'FILES', 'PC', 'DISK', 'CART']
# About's stripes (user/about.s): eight colours of the cube, top to bottom
STRIPES = [16 + 36 * 5, 16 + 36 * 5 + 6 * 2, 16 + 36 * 5 + 6 * 4, 16 + 36 * 3 + 6 * 5,
           16 + 6 * 5 + 2, 16 + 6 * 3 + 5, 16 + 36 * 1 + 5, 16 + 36 * 3 + 4]
WORD = 'Atari816'
OUTLINE = (64, 70, 88)


def die(msg):
    sys.exit('mksaver: ' + msg)


def icons_and_palette(path):
    import importlib.util
    spec = importlib.util.spec_from_file_location('mkicons', os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'mkicons.py'))
    src = open(spec.origin).read().replace('\nmain()\n', '\n')     # (the module without its run)
    mod = {'__file__': spec.origin}
    exec(compile(src, spec.origin, 'exec'), mod)
    return mod['parse'](path), mod['palette']()


def font(path):
    glyphs, cur = {}, None
    for line in open(path):
        line = line.rstrip('\n')
        if line.startswith(';'):
            continue
        if line.startswith('char '):
            cur = int(line.split()[1], 16)
            glyphs[cur] = []
        elif cur is not None and line and set(line) <= set('.#') and len(glyphs[cur]) < 10:
            glyphs[cur].append(line)
    return glyphs


def pack4(rows):
    out = []
    for r in rows:
        for x in range(0, len(r), 2):
            out.append((r[x] << 4) | r[x + 1])
    return out


def main():
    a = sys.argv[1:]
    png = None
    if '--png' in a:
        k = a.index('--png')
        png = a[k + 1]
        del a[k:k + 2]
    if len(a) != 3:
        sys.exit(__doc__)
    icf, fontf, out = a
    icons, pal = icons_and_palette(icf)
    byname = {i['name']: i for i in icons}
    banks = []                                  # palette banks 2-8: 16 colours each
    banks.append([(0, 0, 0)] + [pal[c] for c in STRIPES] + [(0, 0, 0)] * 7)
    stripes = [[0] * 16 for _ in range(32)]
    for i in range(8):
        for y in range(3):
            stripes[4 * i + y] = [1 + i] * 16
    icon_imgs = []
    for name in ICONS:
        ic = byname.get(name) or die('no icon ' + name)
        cols = []
        for row in ic['rows']:
            for v in row:
                if v != 255 and v not in cols:
                    cols.append(v)
        if len(cols) > 15:
            die('icon %s has %d colours (15 at most)' % (name, len(cols)))
        # (black, the outline, would vanish on the black screen: a dark blue-grey instead)
        banks.append([(0, 0, 0)] + [OUTLINE if c == 0 else pal[c] for c in cols]
                     + [(0, 0, 0)] * (15 - len(cols)))
        icon_imgs.append([[0 if v == 255 else 1 + cols.index(v) for v in row] for row in ic['rows']])
    g = font(fontf)
    word = [[0] * 64 for _ in range(16)]
    for n, ch in enumerate(WORD):
        rows = g.get(ord(ch)) or die('no glyph ' + ch)
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == '#':
                    for dx in (0, 1):           # bold: the pixel and the one to its right
                        word[2 + y][n * 8 + 1 + x + dx] = 1 + y
    star = [[0] * 16 for _ in range(16)]
    for d in range(1, 8):                       # four rays from the centre (7, 7)
        v = 1 if d >= 5 else 2
        for x, y in ((7 + d, 7), (7 - d, 7), (7, 7 + d), (7, 7 - d)):
            star[y][x] = v
    for x, y in ((6, 6), (8, 6), (6, 8), (8, 8), (7, 6), (7, 8), (6, 7), (8, 7), (7, 7)):
        star[y][x] = 3 if (x, y) == (7, 7) or (x == 7 or y == 7) else 2
    data = []

    def emit(label, b):
        data.append(label + ':')
        for i in range(0, len(b), 16):
            data.append('        .byte   ' + ', '.join('$%02X' % v for v in b[i:i + 16]))
    emit('sv_icons', [v for img in icon_imgs for v in pack4(img)])
    emit('sv_stripes', pack4(stripes))
    emit('sv_word', pack4([r[:32] for r in word]) + pack4([r[32:] for r in word]))
    # three copies of the star: colours 1-3, 4-6, 7-9 (one palette bank, three phases)
    emit('sv_star', [v for k in range(3) for v in pack4([[c + 3 * k if c else 0 for c in r] for r in star])])
    emit('sv_pal', [c for b in banks for rgb in b for c in rgb])
    # the word's colours: 64 steps around a soft colour wheel (the program shows 12 of them,
    # one a row, moving on every few frames)
    import colorsys
    hue = []
    for i in range(64):
        r, g_, b = colorsys.hsv_to_rgb(i / 64, 0.55, 1.0)
        hue += [int(r * 255), int(g_ * 255), int(b * 255)]
    emit('sv_hue', hue)
    # the stars' twinkle: 32 levels of the three colours (tips, rays, centre)
    twk = []
    for lv in range(32):
        f = 0.25 + 0.75 * lv / 31
        for base in ((90, 100, 150), (170, 180, 230), (255, 255, 255)):
            twk += [int(c * f) for c in base]
    emit('sv_twk', twk)
    emit('sv_fb', [0 if v == 0 else 32 + v for r in stripes for v in r])
    hdr = ['; generated by tools/mksaver.py - do not edit (the screen saver\'s art, user/saver.s)',
           'SV_NICON = %d' % len(ICONS)]
    open(out, 'w').write('\n'.join(hdr + data) + '\n')
    if png:
        from PIL import Image
        img = Image.new('RGB', (320, 120))
        px = img.load()

        def put(rows, ox, oy, colours):
            for y, r in enumerate(rows):
                for x, v in enumerate(r):
                    if v:
                        px[ox + x, oy + y] = colours[v]
        for n, im in enumerate(icon_imgs):
            put(im, 4 + 36 * n, 4, banks[1 + n])
        put(stripes, 4, 44, banks[0])
        put(word, 30, 44, [(0, 0, 0)] + [(255, 200 - 10 * i, 60 + 15 * i) for i in range(15)])
        put(star, 100, 44, [(0, 0, 0), (120, 120, 160), (200, 200, 255), (255, 255, 255)])
        img.resize((1280, 480), Image.NEAREST).save(png)


main()
