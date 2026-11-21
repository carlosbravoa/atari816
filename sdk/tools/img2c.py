#!/usr/bin/env python3
"""img2c.py - pictures to hgame images (the C SDK's game library): a C header with the
pixels as an array, or an .HGI file to load from the card with hg_image_load().

    img2c.py ART -o OUT.h   [--name NAME] [--tile WxH] [--key N|none] [--own-palette BASE]
                            [--bpp 4] [--preview OUT.png] [--scale N]
    img2c.py ART -o OUT.HGI [the same options]

ART is a PNG (needs Pillow) or img2inc.py's text art (sdk/tools/img2inc.py describes it:
a legend of letters, then the pixel rows; frames separated by blank lines).

Frames: --tile WxH cuts a PNG into tiles, left to right, top to bottom (a sprite sheet, a
tile set): frame k of the image is tile k. hgame keeps frames one under the other.

Colours: as img2inc.py: each pixel becomes the nearest entry of Horizon's system palette,
or with --own-palette BASE the picture's own colours get entries BASE, BASE + 1, ... and
the output carries them (hg_image_palette(), or NAME_pal with hg_palette()). Text art can
name entries by number ("a = 5"), as full-screen games with a palette of their own do.

Transparency: --key N (default 231, as img2inc) is the colour transparent pixels get and
hg_draw skips; hardware sprites need --key 0 (Marga's transparent colour). --key none: an
opaque image (hg_draw copies it whole; a transparent pixel is then an error).

--bpp 4: 16 colours, two pixels a byte (the left one in the high nibble), for the
640 x 360 x 4 screen and 4 bpp sprites; every index must be 0-15.

A C header (OUT.h, OUT.c or anything not .HGI):
    #define NAME_W 16 / NAME_H 16 / NAME_N 3 / NAME_KEY 231 / NAME_BPP 8
    static const unsigned char NAME[] = { ... };          the frames, one after another
    #define NAME_PALBASE 16 / NAME_PALN 5                  (--own-palette)
    static const unsigned char NAME_pal[] = { r, g, b, ... };
Include it in one .c file and make the image at the start:
    hg_image *img = hg_image_from(NAME, NAME_W, NAME_H, NAME_N, NAME_KEY);
(it is copied into far memory: the array is in the program's 64 KB code bank, so keep
big pictures in .HGI files instead.)

An .HGI file: 32 bytes of header {"HGI1", u16 w, h, frames, key ($FFFF none), u8 bpp, 0,
u16 palette base, palette count, 14 x 0}, the palette (count x 3 bytes), the pixels.
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import img2inc  # noqa: E402


def die(msg):
    sys.exit(f"img2c: {msg}")


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    src = out = name = tile = prev = None
    key, own, bpp, scale = 231, None, 8, 4
    i = 0
    while i < len(a):
        w = a[i]
        if w in ("-o", "--name", "--tile", "--key", "--own-palette", "--bpp", "--preview",
                 "--scale") and i + 1 >= len(a):
            die(f"{w} needs a value")
        if w == "-o":
            out = a[i + 1]; i += 2
        elif w == "--name":
            name = a[i + 1]; i += 2
        elif w == "--tile":
            try:
                tw, th = a[i + 1].lower().split("x"); tile = (int(tw), int(th))
            except ValueError:
                die("--tile WxH, e.g. --tile 16x16")
            i += 2
        elif w == "--key":
            key = None if a[i + 1] == "none" else int(a[i + 1], 0); i += 2
        elif w == "--own-palette":
            own = int(a[i + 1], 0); i += 2
        elif w == "--bpp":
            bpp = int(a[i + 1]); i += 2
        elif w == "--preview":
            prev = a[i + 1]; i += 2
        elif w == "--scale":
            scale = int(a[i + 1]); i += 2
        elif w.startswith("-"):
            die(f"unknown option {w} (img2c.py -h)")
        else:
            src = w; i += 1
    if not src:
        die("no input")
    if bpp not in (4, 8):
        die("--bpp 4 or 8")
    if key is not None and not 0 <= key <= 255:
        die("--key 0-255 or none")
    name = name or re.sub(r"\W", "_", os.path.splitext(os.path.basename(src))[0]).lower()
    try:
        if src.lower().endswith(".png"):
            w, h, frames = img2inc.load_png(src, tile)
        else:
            w, h, frames = img2inc.load_text(src, 231 if key is None else key)
    except (img2inc.ArtError, OSError) as e:
        die(str(e))

    owncols, idx = [], []
    for k, f in enumerate(frames):
        q = []
        for p in f:
            if p is None:
                if key is None:
                    die(f"frame {k}: a transparent pixel in an opaque image (--key none)")
                q.append(key)
            elif isinstance(p, tuple) and p and p[0] == "idx":
                q.append(p[1])
            elif own is not None:
                if p not in owncols:
                    owncols.append(p)
                q.append(own + owncols.index(p))
            else:
                q.append(1 if p == (255, 255, 255) else
                         img2inc.nearest(p, 231 if key is None else key))
        idx.append(q)
    if own is not None and own + len(owncols) > 256:
        die(f"{len(owncols)} colours do not fit from entry {own}")
    if bpp == 4:
        if w % 2:
            die("--bpp 4: the width must be even")
        bad = [v for q in idx for v in q if v > 15]
        if bad:
            die(f"--bpp 4: colour {bad[0]} is not 0-15 (use --own-palette 0 or entries 0-15)")
    data = bytearray()
    for q in idx:
        if bpp == 8:
            data += bytes(q)
        else:
            for j in range(0, len(q), 2):
                data.append(q[j] << 4 | q[j + 1])
    if len(frames) * h > 1024 or w > 4096:
        die(f"{w} x {h * len(frames)}: at most 4096 wide and 1024 rows (frames x height)")
    pal = bytearray()
    for c in owncols:
        pal += bytes(c)
    keyv = 0xFFFF if key is None else key
    up = name.upper()

    if out and out.upper().endswith(".HGI"):
        hdr = b"HGI1" + struct.pack("<HHHHBBHH", w, h, len(frames), keyv, bpp, 0,
                                    own or 0, len(owncols)) + bytes(14)
        assert len(hdr) == 32
        open(out, "wb").write(hdr + pal + data)
    else:
        L = [f"/* generated by img2c.py from {os.path.basename(src)} - do not edit */",
             f"#define {up}_W {w}", f"#define {up}_H {h}", f"#define {up}_N {len(frames)}",
             f"#define {up}_KEY {keyv:#x}" if key is None else f"#define {up}_KEY {key}",
             f"#define {up}_BPP {bpp}"]
        if own is not None:
            L += [f"#define {up}_PALBASE {own}", f"#define {up}_PALN {len(owncols)}",
                  f"static const unsigned char {name}_pal[{max(1, len(pal))}] = {{"]
            for j in range(0, len(pal), 12):
                L.append("    " + ", ".join(str(v) for v in pal[j:j + 12]) + ",")
            L.append("};")
        per = (w * h) if bpp == 8 else (w * h // 2)
        L.append(f"static const unsigned char {name}[{len(data)}] = {{")
        for k in range(len(frames)):
            L.append(f"    /* frame {k} */")
            fr = data[k * per:(k + 1) * per]
            for j in range(0, len(fr), 16):
                L.append("    " + ", ".join(f"0x{v:02X}" for v in fr[j:j + 16]) + ",")
        L.append("};")
        text = "\n".join(L) + "\n"
        if out:
            open(out, "w").write(text)
        else:
            sys.stdout.write(text)

    if prev:
        try:
            from PIL import Image
        except ImportError:
            die("--preview needs Pillow")
        n = len(idx)
        im = Image.new("RGB", ((w + 1) * n * scale, h * scale), (255, 0, 255))
        palx = list(img2inc.PAL)
        for j, c in enumerate(owncols):
            palx[own + j] = c
        for k, q in enumerate(idx):
            for y in range(h):
                for x in range(w):
                    v = q[y * w + x]
                    c = palx[v] if v != keyv else ((200, 200, 200) if (x + y) & 1
                                                   else (150, 150, 150))
                    x0 = (k * (w + 1) + x) * scale
                    for yy in range(scale):
                        for xx in range(scale):
                            im.putpixel((x0 + xx, y * scale + yy), c)
        im.save(prev)
    return 0


if __name__ == "__main__":
    sys.exit(main())
