# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""a816_screen.py — screenshot of the Atari816's native screen (Marga) over the PC link.

The framebuffer is read with PEEK816 (0x13). Marga's palette is write-only and its
registers are only on the 65C816's bus, so the video state (mode, base, stride, palette,
pointer) comes from the Horizon kernel.

Horizon 0.12 and later keep a video-state block at the fixed address $01:F000 (see
horizon/ABI.md, "Video state"): magic "HZVS", version, NV_CTRL, NV_BASE, NV_STRIDE, the
pointer (position, hot spot, image address, colours, shape) and the 256 palette entries
as written to Marga, all kept current by the kernel. When its magic is there, that is
used (exact, one short read; the pointer is drawn with its real image and hot spot).

Older kernels: the variables are found in the kernel's code, as follows (the fallback).

  - the kernel code ($01:0000-) is read once and the variables are found by the code
    that uses them (byte patterns of ws_desk_mode, scr_set_base, ptr_update ...), so no
    symbol file is needed and a rebuilt kernel works as long as those few instruction
    sequences keep their shape; the addresses are cached per kernel (by two checksums of
    its code) in ~/.cache/atari816/horizon_layout.json;
  - scr_ctrl (the NV_CTRL value while the desktop is shown) gives mode and pointer-on;
  - mode 0 (desktop): base = ws_sbank:0000, stride 1024, palette = ws_palette (the kernel's
    copy of all 256 entries, kept up to date by the ws_palette syscall);
  - mode 1 (text console): base = $7C0000 + scr_top * 3840, stride 320, palette entries
    0-5 = pal_tab, the rest as the desktop left them;
  - the pointer: ms_x / ms_y, image at $7F:F000 (the arrow: which shape is set is not
    kept in memory), colours as ws_desk_mode / ws_text_mode set them.

Without Horizon (or with overrides) mode / base / stride / palette can be given by hand;
the fallback palette is Marga's reset palette (core/src/nvc_palette.hex).
"""
import json
import os
import re
import struct
import zlib

KBASE = 0x010000
KLEN = 0xFF00
PTR_IMG_AT = 0x7FF000

_HERE = os.path.dirname(os.path.abspath(__file__))
_RESET_PAL = os.path.join(_HERE, "..", "src", "nvc_palette.hex")


def reset_palette():
    try:
        pal = []
        for line in open(_RESET_PAL):
            line = line.strip()
            if line:
                v = int(line, 16)
                pal.append(((v >> 16) & 255, (v >> 8) & 255, v & 255))
        if len(pal) == 256:
            return pal
    except OSError:
        pass
    return [(i, i, i) for i in range(256)]


def _w(img, a):
    return img[a] | img[a + 1] << 8


def _one(img, pat, what, sites=None):
    m = [x for x in re.finditer(pat, img, re.S)]
    if len(m) != 1:
        raise ValueError(f"{what}: {len(m)} matches")
    if sites is not None:
        sites.append([KBASE + m[0].start(), m[0].group(0).hex()])
    return m[0]


def horizon_layout(img):
    """Where Horizon keeps its video state, from the kernel code (bytes of $01:0000-...):
    a dict of 24-bit addresses (+ the desktop pointer colours). Raises ValueError if the
    code patterns are not found."""
    lay = {}
    # $01:0000 starts with JMP boot. Another program (run816) loaded over it leaves the old
    # kernel's code behind it in memory: the start tells the two apart.
    if img[0] != 0x4C:
        raise ValueError("no JMP at $01:0000")
    sites = lay["sites"] = [[KBASE, img[:32].hex()]]   # the matched code, to recognise it
    # palette copy loops: lda tab,x / sta f:PAL_R ; +1 / PAL_G ; +2 / PAL_B, then cpx #n
    for m in re.finditer(rb"\xBD(..)\x8F\x11\xD9\x00\xBD..\x8F\x12\xD9\x00\xBD..\x8F\x13\xD9\x00",
                         img, re.S):
        tail = img[m.end():m.end() + 12]
        sites.append([KBASE + m.start(), m.group(0).hex()])
        if b"\xE0\x00\x03" in tail:
            lay["ws_palette"] = KBASE | _w(m.group(1), 0)
        elif b"\xE0\x12\x00" in tail:
            lay["pal_tab"] = KBASE | _w(m.group(1), 0)
    if "ws_palette" not in lay or "pal_tab" not in lay:
        raise ValueError("palette tables not found")
    # lda ws_sbank / xba / sta f:NV_BASE+1
    m = _one(img, rb"\xAD(..)\xEB\x8F\x02\xD9\x00", "ws_sbank", sites)
    lay["ws_sbank"] = KBASE | _w(m.group(1), 0)
    # scr_set_base: lda scr_top / jsr row_pages / clc / adc #$7C00 / sta f:NV_BASE+1
    m = _one(img, rb"\xAD(..)\x20..\x18\x69\x00\x7C\x8F\x02\xD9\x00", "scr_top", sites)
    lay["scr_top"] = KBASE | _w(m.group(1), 0)
    # ws_desk_mode: lda #WS_CTRL / sta scr_ctrl / a8 / sta f:NV_CTRL / then the pointer
    # colours: lda #c / sta f:PTR_C1 (C2, C3)
    m = _one(img, rb"\xA9\x09\x00\x8D(..)\xE2\x20\x8F\x00\xD9\x00"
                  rb"\xA9(.)\x8F\x28\xD9\x00\xA9(.)\x8F\x29\xD9\x00\xA9(.)\x8F\x2A\xD9\x00",
             "scr_ctrl", sites)
    lay["scr_ctrl"] = KBASE | _w(m.group(1), 0)
    lay["ptr_c_desk"] = [m.group(2)[0], m.group(3)[0], m.group(4)[0]]
    # ptr_update: lda ms_x / sta f:PTR_X / lda ms_y / sta f:PTR_Y
    m = _one(img, rb"\xAD(..)\x8F\x20\xD9\x00\xAD(..)\x8F\x22\xD9\x00", "ms_x/ms_y", sites)
    lay["ms_x"] = KBASE | _w(m.group(1), 0)
    lay["ms_y"] = KBASE | _w(m.group(2), 0)
    # classic_show @back: stz cls_on / jsr classic_freeze / a8 / lda scr_ctrl / sta f:NV_CTRL
    m = _one(img, rb"\x9C(..)\x20..\xE2\x20\xAD..\x8F\x00\xD9\x00", "cls_on", sites)
    lay["cls_on"] = KBASE | _w(m.group(1), 0)
    return lay


_VARS = ("ws_sbank", "scr_top", "scr_ctrl", "ms_x", "ms_y", "cls_on")
_CACHE = os.path.join(os.path.expanduser("~"), ".cache", "atari816", "horizon_layout.json")
_mem_cache = {}


def find_layout(link):
    """horizon_layout() of the running kernel. A layout found before (kept in
    ~/.cache/atari816, keyed by a checksum of the first 8 KB of kernel code) is used when
    the code it was found in is still there (one short read per pattern, ~0.5 s);
    otherwise the kernel code is read (~4 s) and searched."""
    key = "%04x" % link.sum816(KBASE, 0x2000)
    try:
        with open(_CACHE) as f:
            disk = json.load(f)
    except (OSError, ValueError):
        disk = {}
    for lay in [_mem_cache.get(key)] + list(disk.get(key, [])):
        if lay and all(link.peek816(a, len(h) // 2).hex() == h for a, h in lay["sites"]):
            _mem_cache[key] = lay
            return lay
    img = b""
    err = None
    for n in (0x8000, KLEN):                       # the code so far fits 32 KB
        img += link.peek816(KBASE + len(img), n - len(img), xor2=True)
        try:
            lay = horizon_layout(img)
            break
        except ValueError as e:
            err = e
    else:
        raise ValueError(f"Horizon kernel not recognised ({err})")
    _mem_cache[key] = lay
    disk[key] = [lay] + [x for x in disk.get(key, []) if x != lay][:3]
    try:
        os.makedirs(os.path.dirname(_CACHE), exist_ok=True)
        with open(_CACHE, "w") as f:
            json.dump(disk, f)
    except OSError:
        pass
    return lay


def horizon_state(link, lay):
    """The current values: the variables in one read (they sit together in the kernel's
    BSS), the palettes from the kernel's copies."""
    lo = min(lay[v] for v in _VARS)
    hi = max(lay[v] for v in _VARS) + 2
    if hi - lo <= 0x1000:
        blk = link.peek816(lo, hi - lo)
        val = {v: _w(blk, lay[v] - lo) for v in _VARS}
    else:
        val = {v: _w(link.peek816(lay[v], 2), 0) for v in _VARS}
    st = dict(val, ptr_c_desk=tuple(lay["ptr_c_desk"]))
    st["ws_sbank"] &= 0xFF
    st["scr_ctrl"] &= 0xFF
    p = link.peek816(lay["ws_palette"], 768)
    st["ws_palette"] = [tuple(p[3 * i:3 * i + 3]) for i in range(256)]
    p = link.peek816(lay["pal_tab"], 18)
    st["pal_tab"] = [tuple(p[3 * i:3 * i + 3]) for i in range(6)]
    return st


VS_ADDR = 0x01F000
VS_MAGIC = b"HZVS"


def video_state(link, tries=3):
    """The kernel's video-state block at $01:F000 as a dict, or None (no magic: an older
    kernel, or no Horizon). Read again when the change counter moved during the read."""
    for _ in range(tries):
        hdr = link.peek816(VS_ADDR, 32)
        if hdr[:4] != VS_MAGIC or hdr[4] < 1 or hdr[5] < 32:
            return None
        pal = link.peek816(VS_ADDR + hdr[5], 768)
        again = link.peek816(VS_ADDR, 8)
        if again[6:8] == hdr[6:8]:
            break
    w = lambda o: hdr[o] | hdr[o + 1] << 8
    return dict(version=hdr[4], seq=w(6), ctrl=hdr[8],
                base=hdr[9] | hdr[10] << 8 | hdr[11] << 16, stride=w(12),
                classic=bool(hdr[14] & 1), desktop=bool(hdr[14] & 2), dctrl=hdr[15],
                ptr_x=w(16), ptr_y=w(18), ptr_hot=hdr[20],
                ptr_img=hdr[21] | hdr[22] << 8 | hdr[23] << 16, ptr_c=tuple(hdr[24:27]),
                ptr_shape=hdr[27], buttons=w(28),
                palette=[tuple(pal[3 * i:3 * i + 3]) for i in range(256)])


def draw_pointer(link, idx, w, h, mode, x, y, hot, img_addr, colours):
    """The NVC's 32x32 2 bpp pointer into the index buffer, its hot spot at (x, y)."""
    img = link.peek816(img_addr, 256)
    x0 = x - (hot & 15) * 2
    y0 = y - (hot >> 4) * 2
    for r in range(32):
        yy = y0 + r
        if not 0 <= yy < h:
            continue
        for c in range(32):
            code = (img[r * 8 + (c >> 2)] >> (6 - 2 * (c & 3))) & 3
            xx = x0 + c
            if code and 0 <= xx < w:
                v = colours[code - 1]
                idx[yy * w + xx] = v & 15 if mode == 1 else v


class Shot:
    def __init__(self, width, height, rgb, info):
        self.width, self.height, self.rgb, self.info = width, height, rgb, info

    def png_bytes(self):
        raw = bytearray()
        row = self.width * 3
        for y in range(self.height):
            raw.append(0)
            raw += self.rgb[y * row:(y + 1) * row]

        def chunk(t, d):
            c = t + d
            return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return (b"\x89PNG\r\n\x1a\n" +
                chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))

    def save_png(self, path):
        with open(path, "wb") as f:
            f.write(self.png_bytes())


def capture(link, mode=None, base=None, stride=None, palette=None, pointer=True,
            scale=1, horizon=True):
    """Read the screen. Overrides: mode (0/1/2), base (24-bit), stride, palette (256 RGB
    tuples). horizon=False skips reading the kernel (then mode/base/stride are needed)."""
    info = {}
    st = None
    vs = None
    if horizon:
        vs = video_state(link)
        if vs is None:
            try:
                st = horizon_state(link, find_layout(link))
                info["source"] = "kernel code patterns"
            except ValueError as e:
                info["horizon"] = f"not found ({e})"
    pal = reset_palette()
    ptr = None
    if vs:
        info.update(source="video-state block v%d" % vs["version"], nv_ctrl=vs["ctrl"])
        ctrl = vs["ctrl"]
        if vs["classic"]:
            info["note"] = "the classic machine has the screen; showing the desktop memory"
            ctrl = vs["dctrl"]
        if mode is None:
            if not ctrl & 1:
                raise ValueError("the native screen is off (NV_CTRL = 0): nothing to capture")
            mode = (ctrl >> 1) & 3
        pal = list(vs["palette"])
        if base is None:
            base = vs["base"]
        if stride is None:
            stride = vs["stride"]
        if pointer and ctrl & 8:
            ptr = (vs["ptr_x"], vs["ptr_y"], vs["ptr_c"], vs["ptr_hot"], vs["ptr_img"])
            info.update(ptr_shape=("arrow", "drag", "crosshair")[vs["ptr_shape"]]
                        if vs["ptr_shape"] < 3 else vs["ptr_shape"])
    elif st:
        ctrl = st["scr_ctrl"]
        info.update(scr_ctrl=ctrl, cls_on=st["cls_on"])
        if st["cls_on"]:
            info["note"] = "the classic machine has the screen; showing the desktop memory"
        if mode is None:
            if not ctrl & 1:
                raise ValueError("the native screen is off (scr_ctrl = 0): nothing to capture")
            mode = (ctrl >> 1) & 3
        if mode == 0:
            pal = list(st["ws_palette"])
            if base is None:
                base = st["ws_sbank"] << 16
            if stride is None:
                stride = 1024
            pc = st["ptr_c_desk"]
        else:
            pal = list(st["ws_palette"])
            pal[0:6] = st["pal_tab"]
            if base is None:
                base = 0x7C0000 + st["scr_top"] * 3840
            if stride is None:
                stride = 320
            pc = (4, 5, st["ptr_c_desk"][2])
        if pointer and ctrl & 8:
            ptr = (st["ms_x"], st["ms_y"], pc, 0, PTR_IMG_AT)
    if mode is None or base is None:
        raise ValueError("video state unknown: give --mode and --base (Horizon kernel %s)"
                         % info.get("horizon", "not read"))
    if palette is not None:
        pal = palette
    w, h, wb = {0: (640, 360, 640), 1: (640, 360, 320), 2: (320, 180, 320)}[mode]
    if stride is None:
        stride = 640 if mode == 0 else 320
    fb = link.peek816(base & 0xFFFF00, width=wb, rows=h, stride=stride, xor2=True)
    idx = bytearray(w * h)
    if mode == 1:
        for y in range(h):
            line = fb[y * wb:(y + 1) * wb]
            o = y * w
            for x, b in enumerate(line):
                idx[o + 2 * x] = b >> 4
                idx[o + 2 * x + 1] = b & 15
    else:
        idx[:] = fb
    if ptr:
        px, py, pc, hot, img_addr = ptr
        draw_pointer(link, idx, w, h, mode, px, py, hot, img_addr, pc)
        info.update(ptr_x=px, ptr_y=py)
    lut = [bytes(pal[i]) for i in range(256)]
    rgb = b"".join(lut[i] for i in idx)
    if scale > 1:
        out = bytearray()
        for y in range(h):
            row = b"".join(rgb[(y * w + x) * 3:(y * w + x) * 3 + 3] * scale for x in range(w))
            out += row * scale
        rgb, w, h = bytes(out), w * scale, h * scale
    info.update(mode=mode, base=base, stride=stride)
    return Shot(w, h, rgb, info)
