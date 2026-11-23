#!/usr/bin/env python3
"""hzapp.py - pack, list and check Horizon apps (.HZA archives).

    hzapp.py pack FOLDER [-o FILE.HZA] [--mtime N] [--needs-from-program]
                                           FOLDER -> NAME.HZA (NAME = the folder's name)
    hzapp.py list FILE.HZA                 what is in it, and its APP.INF
    hzapp.py check FOLDER|FILE.HZA         the checks only (exit 1 on an error), and
                                           what the program itself checks (its needs)
    hzapp.py icon IMAGE.png OUT.ICN [--no-shadow] [--preview FILE.png]
                                           any picture -> an app icon (needs Pillow)

An app is one folder: its program (NAME.PRG), its data, and APP.INF, a text file of
"key=value" lines (sdk/docs/apps.md). Its archive is a plain POSIX ustar file (no
compression, no pax or GNU headers) that holds that one folder. Horizon's Installer
(/BIN/INSTALL.PRG: a double click on the .HZA in Files, or "install FILE.HZA" in the shell)
unpacks it to /APPS/NAME.

pack checks the folder first (an error stops it, a warning does not):
  - APP.INF is there; its keys are known ones; name is at most 24 characters, category 15,
    version 15, description 63, types and needs 47, program 63.
  - the program: program=NAME.PRG, else FOLDER.PRG, else the folder's only .PRG; it must be
    a Horizon program (an o65 file). Its requirements block (HZ_NEEDS, hcc --needs) is read
    and compared with APP.INF's needs= line. When APP.INF has no needs= line, the APP.INF
    put into the archive gets one from the program's block (the folder's file is not
    changed); when both are there and differ, a warning, and --needs-from-program puts the
    program's into the archive's APP.INF instead.
  - icon= is one of Horizon's built-in icon names (BUILTIN_ICONS: the Desktop's list) or an
    icon file in the folder of exactly 1024 bytes.
  - every name is one the card's file system (FAT, long names) takes and the Installer
    accepts: printable ASCII without \\ : * ? " < > |, no part ending in '.' or ' ' or
    starting with ' '; the folder's name at most 32 characters, not starting with '.';
    every path inside it at most 112 characters, /APPS/NAME/path at most 127.
  - files and folders whose name starts with '.' are left out (.DS_Store, .git): a warning.
  - links are refused; files of 16 MB or more get a warning (the card takes them, but the
    machine has 8 MB of memory).
The archive's entries are sorted (the folder first), owner 0, modes 644 / 755, the files'
own modification times (--mtime N: all of them N, seconds since 1970, for reproducible
archives).

icon makes an icon file (APP.INF's icon=) from any picture Pillow reads (PNG, ...): 32 x 32
pixels, one byte each (an index of the Desktop's palette), 255 transparent. A picture larger
than the icon's room is scaled down (its proportions kept; whole-number steps for pixel art),
a smaller one is centred. Each pixel becomes the nearest colour of the palette (indices 0 to
254); alpha below 128 is transparent. Then the house style's drop shadow (colour 15, one
pixel right and down; --no-shadow: none). --preview: the icon 4 x on the desktop's colours.

Plain tar works too: `tar --format=ustar -cf DIGGER.HZA DIGGER` (GNU tar or bsdtar, from
the folder that holds DIGGER). Without --format=ustar GNU tar uses its own format, which
is fine while every name is at most 100 characters; pax headers (bsdtar's extended
attributes, Python's default format) are skipped by the Installer.
"""
import io
import os
import struct
import sys
import tarfile

KEYS = {"name": 24, "program": 63, "icon": 31, "types": 47, "category": 15,
        "version": 15, "description": 63, "needs": 47}
BAD = set('\\:*?"<>|')
NEEDS_MAGIC = b"HZNEEDS\x01"
NEED_FLAGS = [(0x01, "lau"), (0x02, "opl2"), (0x04, "sprites"), (0x08, "blitter"),
              (0x10, "joystick")]
BIG = 16 << 20
ICON_BYTES = 1024
# the Desktop's built-in icons by name (horizon/user/desk.s, "apinames"; the SDK's apps test
# checks this list against it and against sdk/docs/apps.md)
BUILTIN_ICONS = ["folder", "sd", "atari", "doc", "text", "writedoc", "sheetdoc", "picture",
                 "basdoc", "disk", "xex", "cart", "program", "edit", "write", "sheet", "paint",
                 "basic", "calc", "solitaire", "terminal", "files", "settings", "about", "pc",
                 "freecell", "music", "musicdoc"]
# the window system's palette (horizon/tools/mkpalette.py; checked by the apps test):
# 0-15 the UI colours, 16-231 the cube 16 + 36 r + 6 g + b (0, 51, ... 255), 232-255 greys
UI_COLOURS = [(0, 0, 0), (255, 255, 255), (36, 92, 112), (46, 104, 124), (28, 60, 132),
              (132, 138, 148), (228, 226, 216), (76, 80, 90), (160, 164, 172), (204, 206, 210),
              (52, 100, 204), (200, 52, 44), (240, 200, 64), (60, 156, 80), (232, 128, 40),
              (36, 40, 48)]
PALETTE = (UI_COLOURS + [(r * 51, g * 51, b * 51) for r in range(6) for g in range(6)
                         for b in range(6)] + [(8 + 10 * i,) * 3 for i in range(24)])
SHADOW = 15


class Report:
    def __init__(self):
        self.errors = 0
        self.warnings = 0

    def error(self, msg):
        print(f"hzapp: error: {msg}", file=sys.stderr)
        self.errors += 1

    def warn(self, msg):
        print(f"hzapp: warning: {msg}", file=sys.stderr)
        self.warnings += 1


def parse_inf(text):
    """APP.INF's text -> ({key: value}, [unknown keys]) as Horizon reads it"""
    d, unknown = {}, []
    for line in text.replace("\r", "").split("\n"):
        s = line.strip(" \t")
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        k = k.strip(" \t").lower()
        v = v.strip(" \t")
        if k in KEYS:
            d[k] = v
        else:
            unknown.append(k)
    return d, unknown


def check_part(part, rep, where):
    if not part:
        rep.error(f"{where}: an empty name part")
        return False
    if part in (".", ".."):
        rep.error(f"{where}: '{part}' is not allowed")
        return False
    bad = [c for c in part if ord(c) < 32 or ord(c) > 126 or c in BAD]
    if bad:
        rep.error(f"{where}: the character {bad[0]!r} is not allowed (printable ASCII "
                  f"without \\ : * ? \" < > |)")
        return False
    if part[-1] in ". ":
        rep.error(f"{where}: a name must not end in '.' or ' ' (FAT drops them)")
        return False
    if part[0] == " ":
        rep.error(f"{where}: a name must not start with ' '")
        return False
    return True


def check_root(root, rep):
    if not check_part(root, rep, f"the folder {root!r}"):
        return False
    if len(root) > 32:
        rep.error(f"the folder's name {root!r} is longer than 32 characters")
        return False
    if root.startswith("."):
        rep.error(f"the folder's name {root!r} must not start with '.'")
        return False
    return True


def check_path(root, rel, rep):
    ok = all(check_part(p, rep, rel) for p in rel.split("/"))
    if len(rel) > 112:
        rep.error(f"{rel}: the path inside the app is {len(rel)} characters (112 at most)")
        ok = False
    full = f"/APPS/{root}/{rel}"
    if len(full) > 127:
        rep.error(f"{full}: {len(full)} characters (127 at most)")
        ok = False
    return ok


def needs_of_prg(data):
    """the HZ_NEEDS block of a program file -> the needs= text, or None"""
    i = data.find(NEEDS_MAGIC)
    if i < 0 or i + 14 > len(data):
        return None
    vmin, vmaj, rev, flags = data[i + 8:i + 12]
    kb = struct.unpack("<H", data[i + 12:i + 14])[0]
    out = []
    if vmaj or vmin:
        out.append(f"horizon={vmaj}.{vmin}")
    for bit, name in NEED_FLAGS:
        if flags & bit:
            out.append(name)
    if rev:
        out.append(f"rev={rev}")
    if kb:
        out.append(f"mem={kb}K")
    return ",".join(out)


def norm_needs(s):
    return ",".join(sorted(t.strip().lower() for t in s.split(",") if t.strip()))


def check_program(name, data, inf, rep, fix=None):
    """the program's checks -> its needs block's text (None: no block). fix (pack): None,
    "missing" (APP.INF without needs= gets the block's), "all" (--needs-from-program: a
    different needs= is replaced too); then inf["needs"] is set and inf["_fixed"] says how"""
    if data[:6] != b"\x01\x00o65\x00":
        rep.error(f"{name} is not a Horizon program (no o65 header)")
        return None
    blk = needs_of_prg(data)
    declared = inf.get("needs")
    if len(data) >= 0x10000:
        if not blk or "horizon=" not in blk:
            rep.warn(f"{name} is {len(data):,} bytes: it needs Horizon 0.28 or later "
                     f"(a large C program checks that itself)")
    if blk:
        if declared is None:
            if fix:
                inf["needs"], inf["_fixed"] = blk, "added"
            else:
                rep.warn(f"{name} declares needs ({blk}); add the line needs={blk} to APP.INF "
                         f"so the Installer shows it (hzapp.py pack adds it to the archive's)")
        elif norm_needs(declared) != norm_needs(blk):
            if fix == "all":
                inf["needs"], inf["_fixed"] = blk, f"replaced (APP.INF said needs={declared})"
            else:
                rep.warn(f"APP.INF says needs={declared}, but {name} checks {blk}"
                         + (" (--needs-from-program puts the program's into the archive)"
                            if fix else ""))
    return blk


def check_icon(inf, files, rep):
    """APP.INF's icon=: a built-in name, or a file in the folder ({lower name: size})"""
    ic = inf.get("icon")
    if not ic or ic.lower() in BUILTIN_ICONS:
        return
    if ic.lower() not in files:
        rep.warn(f"APP.INF: icon={ic} is neither a built-in icon ({', '.join(BUILTIN_ICONS)}) "
                 f"nor a file in the folder: the shortcut shows the program icon")
    elif files[ic.lower()] != ICON_BYTES:
        rep.warn(f"APP.INF: icon={ic} is {files[ic.lower()]} bytes, not {ICON_BYTES} (32 x 32, "
                 f"8 bits a pixel): Horizon will not use it (hzapp.py icon makes one)")


def inf_with_needs(text, needs):
    """APP.INF's text with its needs= line(s) replaced by needs=NEEDS (added at the end when
    there is none), its line ends kept"""
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    out, done = [], False
    for ln in lines:
        s = ln.strip(" \t")
        if "=" in s and not s.startswith("#") and s.split("=", 1)[0].strip(" \t").lower() == "needs":
            if not done:
                out.append(f"needs={needs}")
                done = True
            continue
        out.append(ln)
    if not done:
        while out and out[-1] == "":
            out.pop()
        out += [f"needs={needs}", ""]
    return nl.join(out)


def pick_program(root, inf, prgs, rep):
    """the program's name inside the folder, or None"""
    if inf.get("program"):
        p = inf["program"]
        for q in prgs:
            if q.lower() == p.lower():
                return q
        rep.error(f"APP.INF names program={p}, which is not in the folder")
        return None
    for q in prgs:
        if q.lower() == root.lower() + ".prg":
            return q
    if len(prgs) == 1:
        return prgs[0]
    if not prgs:
        rep.error("the folder holds no .PRG")
    else:
        rep.error(f"the folder holds several .PRG files ({', '.join(prgs)}): name the "
                  f"program in APP.INF (program=NAME.PRG)")
    return None


def check_inf(text, rep):
    inf, unknown = parse_inf(text)
    for k in unknown:
        rep.warn(f"APP.INF: unknown key {k!r} (Horizon ignores it)")
    for k, v in inf.items():
        if len(v) > KEYS[k]:
            rep.warn(f"APP.INF: {k} is {len(v)} characters; Horizon keeps {KEYS[k]}")
    if "name" not in inf:
        rep.warn("APP.INF has no name=: the menu shows the folder's name")
    return inf


def summary(root, inf, nfiles, total, prg=None, blk=False):
    """(blk: the program's needs block's text, None for none; False: not shown)"""
    name = inf.get("name") or root
    s = name + (" " + inf["version"] if inf.get("version") else "")
    if inf.get("description"):
        s += " - " + inf["description"]
    print(s)
    if inf.get("category"):
        print(f"  category: {inf['category']}")
    if inf.get("types"):
        print(f"  opens: {inf['types']}")
    if inf.get("needs"):
        print(f"  needs: {inf['needs']}")
    print(f"  {nfiles} files, {(total + 1023) // 1024} KB, into /APPS/{root}")
    if prg and blk is not False:
        print(f"  {prg} checks: {blk}" if blk else
              f"  {prg} checks nothing at its start (no needs block: hcc --needs, HZ_NEEDS)")


def scan_folder(folder, rep, fix=None):
    """-> (root, [(relative path, full path, is folder)], APP.INF dict, program name, the
    program's needs block, APP.INF's text)"""
    folder = os.path.abspath(folder)
    root = os.path.basename(folder.rstrip("/"))
    if not os.path.isdir(folder):
        rep.error(f"{folder}: not a folder")
        return root, [], {}, None, None, None
    check_root(root, rep)
    entries, prgs = [], []
    for dirpath, dirnames, filenames in os.walk(folder):
        dirnames.sort()
        rel0 = os.path.relpath(dirpath, folder)
        rel0 = "" if rel0 == "." else rel0.replace(os.sep, "/")
        for d in list(dirnames):
            if d.startswith("."):
                rep.warn(f"{os.path.join(rel0, d)}: left out (a name starting with '.')")
                dirnames.remove(d)
        for d in dirnames:
            full = os.path.join(dirpath, d)
            rel = f"{rel0}/{d}" if rel0 else d
            if os.path.islink(full):
                rep.error(f"{rel}: a link (only files and folders)")
                continue
            check_path(root, rel, rep)
            entries.append((rel, full, True))
        for f in sorted(filenames):
            full = os.path.join(dirpath, f)
            rel = f"{rel0}/{f}" if rel0 else f
            if f.startswith("."):
                rep.warn(f"{rel}: left out (a name starting with '.')")
                continue
            if os.path.islink(full) or not os.path.isfile(full):
                rep.error(f"{rel}: a link or a special file (only files and folders)")
                continue
            check_path(root, rel, rep)
            if os.path.getsize(full) >= BIG:
                rep.warn(f"{rel}: {os.path.getsize(full):,} bytes (the machine has 8 MB of "
                         f"memory)")
            entries.append((rel, full, False))
            if not rel0 and f.lower().endswith(".prg"):
                prgs.append(f)
    entries.sort(key=lambda e: e[0])
    inf_path = None
    for rel, full, isdir in entries:
        if not isdir and rel.lower() == "app.inf":
            inf_path = full
    if inf_path is None:
        rep.error("the folder has no APP.INF")
        return root, entries, {}, None, None, None
    text = open(inf_path, "rb").read().decode("latin-1")
    inf = check_inf(text, rep)
    check_icon(inf, {rel.lower(): os.path.getsize(full) for rel, full, isdir in entries
                     if not isdir and "/" not in rel}, rep)
    prg = pick_program(root, inf, prgs, rep)
    blk = None
    if prg:
        blk = check_program(prg, open(os.path.join(folder, prg), "rb").read(), inf, rep, fix)
    return root, entries, inf, prg, blk, text


def cmd_pack(args):
    out, mtime, folder, fix = None, None, None, "missing"
    i = 0
    while i < len(args):
        if args[i] == "--needs-from-program":
            fix = "all"
            i += 1
        elif args[i] == "-o" and i + 1 < len(args):
            out = args[i + 1]
            i += 2
        elif args[i] == "--mtime" and i + 1 < len(args):
            mtime = int(args[i + 1])
            i += 2
        elif folder is None:
            folder = args[i]
            i += 1
        else:
            sys.exit(f"hzapp: pack takes one folder ({args[i]}?)")
    if folder is None:
        sys.exit("hzapp: pack FOLDER [-o FILE.HZA] [--mtime N] [--needs-from-program]")
    rep = Report()
    root, entries, inf, prg, blk, text = scan_folder(folder, rep, fix)
    newinf = None
    if inf.get("_fixed"):
        newinf = inf_with_needs(text, inf["needs"]).encode("latin-1")
        print(f"hzapp: the archive's APP.INF: needs={inf['needs']} {inf['_fixed']}, from {prg} "
              f"(the folder's APP.INF is not changed)")
        if len(newinf) > 1023:
            rep.warn(f"the archive's APP.INF is {len(newinf)} bytes: Horizon reads 1023")
    if rep.errors:
        print(f"hzapp: {rep.errors} error(s): no archive made", file=sys.stderr)
        return 1
    out = out or root.upper() + ".HZA"

    def add(tf, arc, full, isdir, data=None):
        ti = tarfile.TarInfo(arc)
        st = os.stat(full)
        ti.mtime = mtime if mtime is not None else int(st.st_mtime)
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = ""
        if isdir:
            ti.type = tarfile.DIRTYPE
            ti.mode = 0o755
            tf.addfile(ti)
        elif data is not None:
            ti.size = len(data)
            ti.mode = 0o644
            tf.addfile(ti, io.BytesIO(data))
        else:
            ti.size = st.st_size
            ti.mode = 0o644
            with open(full, "rb") as f:
                tf.addfile(ti, f)

    total = 0
    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as tf:
        add(tf, root + "/", os.path.abspath(folder), True)
        for rel, full, isdir in entries:
            data = newinf if not isdir and rel.lower() == "app.inf" else None
            add(tf, f"{root}/{rel}" + ("/" if isdir else ""), full, isdir, data)
            if not isdir:
                total += len(data) if data is not None else os.path.getsize(full)
    nfiles = sum(1 for e in entries if not e[2])
    summary(root, inf, nfiles, total)
    print(f"hzapp: {out}: {os.path.getsize(out):,} bytes"
          + (f" ({rep.warnings} warning(s))" if rep.warnings else ""))
    return 0


def read_archive(path, rep):
    """the Installer's rules on an archive -> (root, [(rel, size, is folder)], APP.INF text)"""
    data = open(path, "rb").read()
    off, root, items, inf_text = 0, None, [], None
    while True:
        h = data[off:off + 512]
        if len(h) < 512:
            rep.error("the archive is cut short (no end record)")
            break
        if h == b"\0" * 512:
            break
        s = sum(h[:148]) + 8 * 32 + sum(h[156:])
        try:
            want = int(h[148:156].replace(b"\0", b" ").strip() or b"x", 8)
        except ValueError:
            want = -1
        if s != want:
            rep.error(f"a header's checksum is wrong (at byte {off}): damaged")
            break
        if h[124] & 0x80:
            rep.error("a base-256 size (a file over 8 GB?)")
            break
        size = int(h[124:136].replace(b"\0", b" ").strip() or b"0", 8)
        typ = chr(h[156]) if h[156] else "0"
        name = h[:100].split(b"\0")[0].decode("latin-1")
        if h[257:262] == b"ustar" and h[345]:
            name = h[345:500].split(b"\0")[0].decode("latin-1") + "/" + name
        dsz = (size + 511) // 512 * 512
        while name.startswith("./"):
            name = name[2:]
        if typ in "xg":
            rep.warn(f"a pax header ({typ}) at byte {off}: the Installer skips it")
        elif typ in "LK":
            rep.error("GNU tar long names ('L'/'K' headers): pack with hzapp.py or "
                      "tar --format=ustar")
            break
        elif name in ("", "."):
            pass
        elif typ not in "057":
            rep.error(f"{name}: a link or a device (type {typ!r})")
        else:
            isdir = typ == "5" or name.endswith("/")
            name = name.rstrip("/")
            parts = name.split("/")
            if root is None:
                if check_root(parts[0], rep):
                    root = parts[0]
            if root is not None and parts[0].lower() != root.lower():
                rep.error(f"{name}: outside the app's folder {root}/")
            elif len(parts) == 1 and not isdir:
                rep.error(f"{name}: a file beside the app's folder")
            elif len(parts) > 1:
                rel = "/".join(parts[1:])
                check_path(root or parts[0], rel, rep)
                items.append((rel, 0 if isdir else size, isdir))
                if not isdir and rel.lower() == "app.inf":
                    inf_text = data[off + 512:off + 512 + min(size, 1023)].decode("latin-1")
                if not isdir and len(parts) == 2 and rel.lower().endswith(".prg"):
                    items[-1] = items[-1] + (data[off + 512:off + 512 + size],)
        off += 512 + (0 if typ == "5" else dsz)
    return root, items, inf_text


def cmd_list_check(args, listing):
    if len(args) != 1:
        sys.exit(f"hzapp: {'list' if listing else 'check'} FILE.HZA")
    rep = Report()
    if os.path.isdir(args[0]):
        if listing:
            sys.exit("hzapp: list takes an archive (check takes a folder too)")
        root, entries, inf, prg, blk, _ = scan_folder(args[0], rep)
        total = sum(os.path.getsize(e[1]) for e in entries if not e[2])
        if not rep.errors:
            summary(root, inf, sum(1 for e in entries if not e[2]), total, prg,
                    False if listing else blk)
    else:
        root, items, inf_text = read_archive(args[0], rep)
        if root is None and not rep.errors:
            rep.error("the archive is empty")
        inf, prg, blk = {}, None, None
        if inf_text is None:
            if root is not None:
                rep.error("no APP.INF in the app's folder")
        else:
            inf = check_inf(inf_text, rep)
            check_icon(inf, {it[0].lower(): it[1] for it in items
                             if not it[2] and "/" not in it[0]}, rep)
            prgs = [it[0] for it in items if len(it) == 4]
            prg = pick_program(root, inf, prgs, rep)
            for it in items:
                if len(it) == 4 and it[0] == prg:
                    blk = check_program(prg, it[3], inf, rep)
        if listing:
            for it in items:
                print(f"  {it[0]}{'/' if it[2] else ''}" + ("" if it[2] else f"  {it[1]:,}"))
        if root is not None:
            summary(root, inf, sum(1 for it in items if not it[2]),
                    sum(it[1] for it in items if not it[2]), prg, False if listing else blk)
    if rep.errors:
        print(f"hzapp: {rep.errors} error(s)", file=sys.stderr)
        return 1
    print("hzapp: OK" + (f" ({rep.warnings} warning(s))" if rep.warnings else ""))
    return 0


def nearest(rgb):
    """the nearest colour of the palette (0-254: 255 is transparent)"""
    r, g, b = rgb
    best, bi = None, 0
    for i, (pr, pg, pb) in enumerate(PALETTE[:255]):
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if best is None or d < best:
            best, bi = d, i
    return bi


def make_icon(im, shadow=True):
    """a Pillow picture -> the icon's 1024 bytes"""
    from PIL import Image
    im = im.convert("RGBA")
    room = 31 if shadow else 32
    w, h = im.size
    if w > room or h > room:
        k = -(-max(w, h) // room)                  # pixel art: a whole-number step
        if w % k == 0 and h % k == 0:
            im = im.resize((w // k, h // k), Image.NEAREST)
        else:
            s = room / max(w, h)
            im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    w, h = im.size
    ox, oy = (room - w) // 2, (room - h) // 2
    ic = [[255] * 32 for _ in range(32)]
    px = im.load()
    cache = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 128:
                if (r, g, b) not in cache:
                    cache[(r, g, b)] = nearest((r, g, b))
                ic[oy + y][ox + x] = cache[(r, g, b)]
    if shadow:                                     # one pixel right and down, colour 15
        for y in range(31, 0, -1):
            for x in range(31, 0, -1):
                if ic[y][x] == 255 and ic[y - 1][x - 1] not in (255, SHADOW):
                    ic[y][x] = SHADOW
    return bytes(v for row in ic for v in row)


def cmd_icon(args):
    shadow, prev, files = True, None, []
    i = 0
    while i < len(args):
        if args[i] == "--no-shadow":
            shadow = False
            i += 1
        elif args[i] == "--preview" and i + 1 < len(args):
            prev = args[i + 1]
            i += 2
        else:
            files.append(args[i])
            i += 1
    if len(files) != 2:
        sys.exit("hzapp: icon IMAGE.png OUT.ICN [--no-shadow] [--preview FILE.png]")
    try:
        from PIL import Image
    except ImportError:
        sys.exit("hzapp: icon needs Pillow (pip install pillow)")
    try:
        im = Image.open(files[0])
        im.load()
    except OSError as e:
        sys.exit(f"hzapp: {files[0]}: {e}")
    data = make_icon(im, shadow)
    open(files[1], "wb").write(data)
    used = sum(1 for v in data if v != 255)
    print(f"hzapp: {files[1]}: an icon of {ICON_BYTES} bytes from {files[0]} "
          f"({im.size[0]} x {im.size[1]}): {used} pixels drawn, {len(set(data) - {255})} colours")
    if prev:
        s = 4
        pv = Image.new("RGB", (32 * s, 32 * s))
        pp = pv.load()
        for y in range(32 * s):
            for x in range(32 * s):
                v = data[(y // s) * 32 + x // s]
                pp[x, y] = PALETTE[v] if v != 255 else PALETTE[2 if (x // s + y // s) % 2 == 0 else 3]
        pv.save(prev)
        print(f"hzapp: {prev}: the icon {s} x on the desktop")
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "pack":
        return cmd_pack(rest)
    if cmd == "list":
        return cmd_list_check(rest, True)
    if cmd == "check":
        return cmd_list_check(rest, False)
    if cmd == "icon":
        return cmd_icon(rest)
    sys.exit(f"hzapp: unknown command {cmd!r} (pack, list, check, icon)")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
