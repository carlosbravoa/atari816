#!/usr/bin/env python3
"""tools/mkdata.py - SDLPoP's data (the DOS game's graphics, levels, sounds and music, in
data/sdlpop/data) converted into the port's four files:

  POP.GFX   every image of the game (and a mirrored copy of the ones drawn facing both
            ways) packed into one atlas, ATLAS_W pixels wide, a byte a pixel: the value of
            each pixel is the DOS game's VGA colour (palette row * 16 + its colour; 0 is
            transparent), so the Atari816's 256-colour palette works as the VGA's did
  POP.MSK   a 1-bit mask of each image (for the one-colour blits: text, masks, blood)
  POP.DAT   the directory: the images (size, place in the atlas, mask), the palettes, the
            levels and the other binary resources, by the DAT file and resource number the
            game asks for
  POP.SND   the sounds: digital effects as signed 8-bit samples (Lau), the MIDI music as
            IMF register streams for the OPL2 (tools/midi2imf, SDLPoP's own interpretation
            of the MIDI), PC speaker sounds as they are

  mkdata.py SDLPOP_DATA OUT_DIR --midi2imf PATH [--preview PNG]
"""
import argparse
import os
import struct
import subprocess
import sys
import tempfile

from PIL import Image

ATLAS_W = 2048
ATLAS_PART = 256        # rows: each part is a sheet of its own in 8 banks (no image crosses one)

# the DAT names the game opens (the platform's table in horizon/hz_data.c has the same order)
FOLDERS = ["PRINCE", "KID", "GUARD", "FAT", "SKEL", "VIZIER", "SHADOW", "GUARD1", "GUARD2",
           "VDUNGEON", "VPALACE", "PV", "TITLE", "LEVELS", "font", "IBM_SND1", "IBM_SND2",
           "DIGISND1", "DIGISND2", "DIGISND3", "MIDISND1", "MIDISND2"]
FOLDER = {n: i for i, n in enumerate(FOLDERS)}

KIND_PAL, KIND_IMG, KIND_BIN = 1, 2, 3

# the image sets (chtabs): folder, the .pal resource, palette row, drawn mirrored too
CHTABS = [("PRINCE", 700, 2, True), ("PRINCE", 150, 3, False), ("KID", 400, 7, True),
          ("GUARD", 750, 8, True), ("FAT", 750, 8, True), ("SKEL", 750, 8, True),
          ("VIZIER", 750, 8, True), ("SHADOW", 750, 8, True),
          ("VDUNGEON", 200, 5, False), ("VPALACE", 200, 5, False),
          ("VDUNGEON", 360, 6, False), ("VPALACE", 360, 6, False),
          ("PV", 800, 9, True), ("PV", 850, 10, True), ("PV", 900, 10, True),
          ("PV", 950, 13, False), ("PV", 980, 14, False),
          ("TITLE", 40, 11, False), ("TITLE", 50, 12, False), ("font", 1000, 1, False)]
# load_more_opt_graf: environment images 1201-1344 with palette 200
OPTGRAF = (1200, 0x90)
# sounds whose MIDI tempo SDLPoP adjusts (midi.c, midi_tempo_modifiers)
TEMPO = {53: -3, 54: 3}
OPL_ATT = 12            # the music 9 dB quieter: the board mixes the OPL2 loud (games.md)


def read_dat(path):
    """{resource: bytes} of a DOS DAT file"""
    b = open(path, "rb").read()
    toff, tsize = struct.unpack_from("<IH", b, 0)
    n = struct.unpack_from("<H", b, toff)[0]
    out = {}
    for i in range(n):
        rid, off, size = struct.unpack_from("<HIH", b, toff + 2 + 8 * i)
        out[rid] = b[off + 1:off + 1 + size]          # (a checksum byte first)
    return out


class Data:
    def __init__(self, root):
        self.root = root
        self.dats = {}

    def path(self, folder, res, ext):
        return os.path.join(self.root, folder, "res%d.%s" % (res, ext))

    def get(self, folder, res, ext):
        """a resource's bytes, from the folder or the DAT file of that name"""
        p = self.path(folder, res, ext)
        if os.path.exists(p):
            return open(p, "rb").read()
        d = os.path.join(self.root, folder + ".DAT")
        if os.path.exists(d):
            if d not in self.dats:
                self.dats[d] = read_dat(d)
            return self.dats[d].get(res)
        return None


def pal_of(data, folder, res):
    b = data.get(folder, res, "pal")
    if b is None and folder == "GUARD":
        b = data.get("GUARD1", res, "pal")
    if b is None:
        raise SystemExit("mkdata: no %s/res%d.pal" % (folder, res))
    n = b[0]
    vga = [tuple(b[4 + 3 * i + k] for k in range(3)) for i in range(16)]     # 6 bits
    return n, vga


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--midi2imf", required=True)
    ap.add_argument("--preview")
    a = ap.parse_args()
    data = Data(a.src)
    os.makedirs(a.out, exist_ok=True)

    dirents = []            # (folder, kind, res, payload bytes)
    images = []             # dicts
    warnings = []

    # ---------------------------------------------------------------- the images
    for folder, res, row, flips in CHTABS:
        n, vga = pal_of(data, folder, res)
        ids = list(range(res + 1, res + n + 1))
        if res == 200:
            ids += [OPTGRAF[0] + k + 1 for k in range(OPTGRAF[1])]
        # the row's colours as the images show them (their PNG palettes); for GUARD the .pal
        # is black (the guard's colours come later from set_chtab_palette): the PNG's
        rowpal = [tuple(c * 4 for c in v) for v in vga]
        if folder == "GUARD":
            for i in ids:
                p = data.path(folder, i, "png")
                if os.path.exists(p):
                    im = Image.open(p)
                    pp = im.getpalette()
                    if len(pp) >= 48:
                        rowpal = [tuple(pp[3 * k:3 * k + 3]) for k in range(16)]
                        break
        for rid in ids:
            p = data.path(folder, rid, "png")
            if not os.path.exists(p):
                continue
            im = Image.open(p)
            if im.mode != "P":
                raise SystemExit("mkdata: %s is not paletted" % p)
            w, h = im.size
            pp = im.getpalette()
            px = list(im.getdata()) if not hasattr(im, "get_flattened_data") else list(im.get_flattened_data())
            used = sorted(set(px))
            mono = len(pp) // 3 <= 2
            remap = {0: 0}
            for k in used:
                if k == 0:
                    continue
                c = tuple(pp[3 * k:3 * k + 3])
                if k < 16 and rowpal[k] == c:
                    j = k
                elif c in rowpal:
                    j = rowpal.index(c)
                else:
                    # nearest colour of the row (only the one-colour masks: never drawn so)
                    j = min(range(16), key=lambda q: sum((rowpal[q][t] - c[t]) ** 2 for t in range(3)))
                    if not mono:
                        warnings.append("%s/res%d: colour %d %s not in row %d: %d" % (folder, rid, k, c, row, j))
                remap[k] = row * 16 + j
            pix = bytes(remap[v] for v in px)
            mask = bytearray()
            stride = (w + 7) // 8
            for y in range(h):
                line = bytearray(stride)
                for x in range(w):
                    if px[y * w + x]:
                        line[x >> 3] |= 0x80 >> (x & 7)
                mask += line
            img = dict(folder=folder, res=rid, w=w, h=h, pix=pix, mask=bytes(mask), flip=flips)
            images.append(img)
        rowbytes = bytes(c // 4 for col in rowpal for c in col)
        dirents.append((FOLDER[folder], KIND_PAL, res, bytes([n, row]) + rowbytes + bytes(sum(vga, ()))))

    # pack: shelves, tallest first
    items = []
    for img in images:
        items.append((img, False))
        if img["flip"]:
            items.append((img, True))
    items.sort(key=lambda t: (-t[0]["h"], -t[0]["w"]))
    x = y = shelf = 0
    for img, fl in items:
        if x + img["w"] > ATLAS_W:
            y += shelf
            x = shelf = 0
        if x == 0 and y // ATLAS_PART != (y + img["h"] - 1) // ATLAS_PART:
            y = (y // ATLAS_PART + 1) * ATLAS_PART      # (the shelf starts a new part)
        if img["h"] > ATLAS_PART:
            raise SystemExit("mkdata: an image taller than an atlas part")
        img["fx" if fl else "sx"] = x
        img["fy" if fl else "sy"] = y
        x += img["w"]
        shelf = max(shelf, img["h"])
    atlas_h = y + shelf
    atlas = bytearray(ATLAS_W * atlas_h)
    masks = bytearray()
    for img in images:
        w, h = img["w"], img["h"]
        for yy in range(h):
            row = img["pix"][yy * w:(yy + 1) * w]
            o = (img["sy"] + yy) * ATLAS_W + img["sx"]
            atlas[o:o + w] = row
            if img["flip"]:
                o = (img["fy"] + yy) * ATLAS_W + img["fx"]
                atlas[o:o + w] = row[::-1]
        # a mask must not cross a bank (the blitter reads it as one range): pad
        mo = len(masks)
        if (mo & 0xFFFF) + len(img["mask"]) > 0x10000:
            masks += bytes(0x10000 - (mo & 0xFFFF))
            mo = len(masks)
        img["mo"] = mo
        masks += img["mask"]
        fx = img.get("fx", 0xFFFF)
        fy = img.get("fy", 0xFFFF)
        rec = struct.pack("<HHHHHHI", w, h, img["sx"], img["sy"], fx, fy, mo)
        dirents.append((FOLDER[img["folder"]], KIND_IMG, img["res"], rec))
    open(os.path.join(a.out, "POP.GFX"), "wb").write(atlas)
    open(os.path.join(a.out, "POP.MSK"), "wb").write(masks)
    if a.preview:
        Image.frombytes("L", (ATLAS_W, atlas_h), bytes(atlas)).save(a.preview)

    # ---------------------------------------------------------------- binary resources
    for folder, res in [("PRINCE", 1), ("PRINCE", 10)] + [("LEVELS", 2000 + k) for k in range(16)]:
        b = data.get(folder, res, "bin")
        if b is None:
            raise SystemExit("mkdata: no %s/res%d.bin" % (folder, res))
        dirents.append((FOLDER[folder], KIND_BIN, res, b))

    # ---------------------------------------------------------------- sounds
    # SDLPoP's lookup (load_sounds / load_opt_sounds: the DAT opened last is searched first)
    snd_dir = []
    snd_data = bytearray()
    kinds = {}
    inst = data.get("PRINCE", 1, "bin")
    tmp = tempfile.mkdtemp()
    open(os.path.join(tmp, "inst.bin"), "wb").write(inst)
    for sid in range(58):
        chain = (["MIDISND1", "DIGISND3", "DIGISND1", "IBM_SND1"] if sid <= 43 else []) + \
                (["MIDISND2", "DIGISND2", "IBM_SND2"] if sid >= 43 else [])
        b = None
        for f in chain:
            b = data.get(f, 10000 + sid, "bin")
            if b is not None:
                src = f
                break
        if b is None:
            snd_dir.append(struct.pack("<BBHIII", 0, 0, 0, 0, 0, 0))
            continue
        typ = b[0] & 7
        while len(snd_data) % 4:
            snd_data.append(0)
        off = len(snd_data)
        if typ == 1:            # digi
            # SDLPoP's determine_wave_version: 1.0 {rate, count, ?, size = 8, samples},
            # 1.3 {rate, size = 8, count, ?, ?, samples} (after the type byte)
            if b[7] == 8:
                rate, count = struct.unpack_from("<HH", b, 1)
                samples = b[8:8 + count]
            elif b[3] == 8:
                rate, count = struct.unpack_from("<H", b, 1)[0], struct.unpack_from("<H", b, 4)[0]
                samples = b[10:10 + count]
            else:
                raise SystemExit("mkdata: sound %d: unknown wave layout" % sid)
            snd_data += bytes((s - 128) & 0xFF for s in samples)
            ms = count * 1000 // rate
            snd_dir.append(struct.pack("<BBHIII", 1, 0, rate, off, count, ms))
            kinds[sid] = "digi %s %d Hz %d ms" % (src, rate, ms)
        elif typ == 2:          # midi
            sp = os.path.join(tmp, "s.bin")
            ip = os.path.join(tmp, "s.imf")
            open(sp, "wb").write(b)
            cmd = [a.midi2imf, os.path.join(tmp, "inst.bin"), sp, ip, "-h", "700", "-a", str(OPL_ATT)]
            if sid in TEMPO:
                cmd += ["-t", str(TEMPO[sid])]
            ms = int(subprocess.check_output(cmd).decode().strip())
            imf = open(ip, "rb").read()
            snd_data += imf
            snd_dir.append(struct.pack("<BBHIII", 2, 0, 700, off, len(imf), ms))
            kinds[sid] = "midi %s %d ms" % (src, ms)
        elif typ == 0:          # PC speaker
            snd_data += b[1:]
            snd_dir.append(struct.pack("<BBHIII", 0x10, 0, 0, off, len(b) - 1, 0))
            kinds[sid] = "speaker %s" % src
        else:
            warnings.append("sound %d: type %d" % (sid, typ))
            snd_dir.append(struct.pack("<BBHIII", 0, 0, 0, 0, 0, 0))
    hdr = b"POPS" + struct.pack("<H", 58)
    base = len(hdr) + 16 * 58
    base = (base + 3) & ~3
    out = bytearray(hdr + b"".join(snd_dir))
    out += bytes(base - len(out))
    # offsets from the file's start
    for k in range(58):
        o = 6 + 16 * k
        typ = out[o]
        if typ:
            off = struct.unpack_from("<I", out, o + 4)[0]
            struct.pack_into("<I", out, o + 4, off + base)
    out += snd_data
    open(os.path.join(a.out, "POP.SND"), "wb").write(out)

    # ---------------------------------------------------------------- the directory
    dirents.sort(key=lambda d: (d[0], d[2], d[1]))
    n = len(dirents)
    head = b"POPD" + struct.pack("<HHH", 1, n, ATLAS_W) + struct.pack("<HH", atlas_h, ATLAS_PART)
    table = bytearray()
    blob = bytearray()
    start = len(head) + 8 * n
    assert len(head) == 14
    for folder, kind, res, payload in dirents:
        table += struct.pack("<BBHI", folder, kind, res, start + len(blob))
        if kind == KIND_BIN:
            blob += struct.pack("<H", len(payload))
        blob += payload
    open(os.path.join(a.out, "POP.DAT"), "wb").write(head + table + blob)

    print("mkdata: %d images (%d mirrored) in an atlas of %d x %d (%d KB), masks %d KB, "
          "directory %d entries (%d KB), sounds %d KB" %
          (len(images), sum(1 for i in images if i["flip"]), ATLAS_W, atlas_h,
           len(atlas) // 1024, len(masks) // 1024, n, (len(head) + len(table) + len(blob)) // 1024,
           len(out) // 1024))
    for sid in sorted(kinds):
        print("  sound %2d: %s" % (sid, kinds[sid]))
    for w in warnings:
        print("mkdata: warning:", w)


if __name__ == "__main__":
    main()
