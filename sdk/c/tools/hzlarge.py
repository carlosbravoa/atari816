"""hzlarge.py - hcc's link for cc816's large code model (hcc --code large).

The program's data, constants, bss, heap and software stack stay in the main bank, which
Horizon loads as it loads any program (an o65 file, NAME.PRG). Its code may fill several
banks: cc816 puts each function that can move in a segment of its own (F_name, or
FS<tag>_name for a static one); hcc places them, and writes the banks other than the
main one after the o65 in the same file, where the startup reads them (lib/xload.c).
Horizon 0.28 and later load such a file and ignore what follows the o65. The libraries'
functions move as the program's (cc816 splits them, one segment a function; only the loader
of the banks, xload.c and misc.c, is resident). The program's __far objects (segment
FD_name) go to banks of far data after the code banks, loaded the same way.

The steps (ld65 runs four to six times; each is quick):
  1. the movable segments and their sizes: from the objects themselves (tools/ca65obj.py),
     since ld65's configuration must list every segment;
  2. a trial link with every movable segment in one large "pool" (a raw file nothing uses):
     the main bank's fixed part (startup, libraries, constants, data, bss) from the map,
     and the functions whose 16-bit address is used (__T_name: undefined there);
  3. the packing, first fit in the order of the objects: the main bank first (what is left
     after the fixed part, the heap's reserve --heap and the software stack), then banks of
     64 KB (--bank-room for the tests);
  4. the glue module (tools: written here, assembled): for each __T_name a thunk
     (JML name, 4 bytes in the main bank) when the function is in another bank, else an
     alias of the function itself; the loader's table (the number of banks, the build's
     stamp, the program's name for its messages, the banks' numbers);
  5. three links, A, B and C, with the other banks at different link-time banks (FAKE,
     OFFSET below): the main bank's bytes that differ are bank bytes of other banks (a
     JSL to a function there, a thunk's JML) and become the relocations (after the o65) of the main
     bank (the offset of such a far address may differ by one in link C; a 16-bit address
     of a function in another bank, which would be cut to 16 bits, is refused); in the
     other banks every bank byte is one the compiler recorded (segment XREL: the address of
     each JSL's, JML's and MVN's bank bytes), whose value in link A says which bank it
     names (0 the main bank, k bank k). A byte that differs and was not recorded stops the
     link (hand-written assembly naming a bank in a movable function).
  6. NAME.PRG is link A's o65 file (o65strip), then the block of the other banks' images and
     their relocations, then an 8-byte trailer: the block's offset (u32) and "HZPX"
     (lib/xload.c has the layout). The o65 must stay below 64 KB (Horizon's loader reads
     only the first 65,535 bytes of a larger file); the whole file has no such limit.
"""
import os
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hzc816  # noqa: E402
import ca65obj  # noqa: E402
from hzc816 import HccError  # noqa: E402

BANK = 0xFFFF                   # a bank's code at most (link C has the banks at offset 1)
# the link-time banks of bank k (1..64) in the three links: A k, B k + $40, C $80 + 2(k - 1).
# A byte that is a bank in all three is that bank; "a bank + 1" (an address one bank
# further) would be odd in link C, and is refused. In link C the other banks also start at
# offset 1: a 16-bit address of a function in another bank, written in the main bank (which
# would be wrong: it has no bank), differs there and is refused, while the offset of a far
# address (a JSL's, a thunk's JML) is followed by its bank byte
FAKE = {"A": lambda k: k, "B": lambda k: k + 0x40, "C": lambda k: 0x80 + 2 * (k - 1)}
OFFSET = {"A": 0, "B": 0, "C": 1}
MAX_BANKS = 64                  # (xload.c)
HEAP = 4096                     # the main bank's room kept for malloc (hcc --heap N)
MOVABLE = re.compile(r"^F(?:S[0-9a-f]{6})?_\w+$")
# a __far object of the program (cc816: segment FD_name, FD<tag>_name for a static one):
# placed in banks of far data after the code banks, loaded with them (offset 0 in every
# link: only their bank bytes differ)
FARDATA = re.compile(r"^FD(?:S[0-9a-f]{6})?_\w+$")
# the main bank's segments, in their order (STARTUP first: Horizon enters at $0100)
MAIN_RO = ("STARTUP", "CODE", "THUNK")
MAIN_RO2 = ("RODATA",)
MAIN_RW = ("DATA",)
MAIN_BSS = ("BSS", "HEAPSTART")


def movable_segments(paths, rx=MOVABLE):
    """[(segment, size)] of the movable functions (rx: of the far objects, FARDATA), in
    the objects' order (a segment met twice: its sizes added; ld65 joins them)"""
    order, size = [], {}
    for p in paths:
        try:
            segs = ca65obj.segments(p)
        except (ca65obj.ObjError, OSError, IndexError, struct.error) as e:
            raise HccError(f"{p}: cannot read the object's segments ({e})")
        for n, s in segs:
            if rx.match(n):
                if n not in size:
                    order.append(n)
                    size[n] = 0
                size[n] += s
    return [(n, size[n]) for n in order]


def config(place, nbanks, tmp, room, trial=False, fake=FAKE["A"], off=0, dplace=(),
           ndata=0):
    """the ld65 configuration: place maps each movable segment to 'MAIN', 'POOL' or a bank
    number (1..); dplace each far object's segment to 'POOL' or a far-data bank (1..),
    which follow the nbanks code banks"""
    mem = ["    ZP:   start = $0000, size = $0100, type = rw;",
           f"    MAIN: start = $0100, size = ${room:X}, file = %O;",
           f'    XR:   start = $0000, size = $1000000, file = "{tmp}/xrel.bin";']
    files = ["    %O: format = o65;", f'    "{tmp}/xrel.bin": format = bin;']
    if trial:
        mem.append(f'    POOL: start = $010000, size = $FF0000, file = "{tmp}/pool.bin";')
        files.append(f'    "{tmp}/pool.bin": format = bin;')
    for k in range(1, nbanks + 1):
        b = fake(k)
        mem.append(f'    B{k}: start = ${b:02X}{off:04X}, size = ${0x10000 - off:X}, '
                   f'file = "{tmp}/bank{k}.bin";')
        files.append(f'    "{tmp}/bank{k}.bin": format = bin;')
    for j in range(1, ndata + 1):
        k = nbanks + j
        mem.append(f'    B{k}: start = ${fake(k):02X}0000, size = $10000, '
                   f'file = "{tmp}/bank{k}.bin";')
        files.append(f'    "{tmp}/bank{k}.bin": format = bin;')
    seg = ["    ZEROPAGE: load = ZP, type = zp;",
           "    ZPEND:    load = ZP, type = zp, optional = yes;",
           "    STARTUP:  load = MAIN, type = ro;",
           "    CODE:     load = MAIN, type = ro;",
           "    THUNK:    load = MAIN, type = ro, optional = yes;"]
    for n, area in place:
        if area == "MAIN":
            seg.append(f"    {n}: load = MAIN, type = ro;")
    seg += ["    RODATA:   load = MAIN, type = ro;",
            "    DATA:     load = MAIN, type = rw;",
            "    BSS:      load = MAIN, type = bss, define = yes;",
            "    HEAPSTART: load = MAIN, type = bss;",
            "    XREL:     load = XR, type = ro, optional = yes;"]
    for n, area in place:
        if area != "MAIN":
            seg.append(f"    {n}: load = {'POOL' if area == 'POOL' else 'B%d' % area}, "
                       f"type = ro{', optional = yes' if trial else ''};")
    for n, area in dplace:
        seg.append(f"    {n}: load = {'POOL' if area == 'POOL' else 'B%d' % (nbanks + area)}, "
                   f"type = rw{', optional = yes' if trial else ''};")
    return "\n".join([
        "# made by hcc (tools/hzlarge.py): the large code model's link",
        "SYMBOLS {", "    __HZ_SSTACK__: type = weak, value = $2000;",
        "    __HZ_PAINT__:  type = weak, value = 0;", "}",
        "MEMORY {"] + mem + ["}", "FILES {"] + files + ["}", "SEGMENTS {"] + seg + ["}",
        "FEATURES {",
        "    CONDES: type = constructor, label = __CONSTRUCTOR_TABLE__,",
        "            count = __CONSTRUCTOR_COUNT__, segment = RODATA;",
        "    CONDES: type = destructor, label = __DESTRUCTOR_TABLE__,",
        "            count = __DESTRUCTOR_COUNT__, segment = RODATA;", "}",
        "FORMATS {", "    o65: os = cc65, type = small;", "}", ""])


def run_ld65(cfg_text, tmp, name, inputs, defs, out, mp, lbl=None):
    cfg = os.path.join(tmp, name + ".cfg")
    with open(cfg, "w") as f:
        f.write(cfg_text)
    cmd = [hzc816.tool("ld65"), "-C", cfg, "-o", out, "-m", mp] + (["-Ln", lbl] if lbl else [])
    for d in defs:
        cmd += ["-D", d]
    cmd += inputs
    if hzc816.VERBOSE:
        print("  " + " ".join(cmd), file=sys.stderr)
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.returncode, r.stdout.decode("utf-8", "replace")


def seg_sizes(mp):
    out = {}
    on = False
    for ln in open(mp, encoding="latin-1"):
        if ln.startswith("Segment list:"):
            on = True
            continue
        if on:
            m = re.match(r"^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})", ln)
            if m:
                out[m.group(1)] = (int(m.group(2), 16), int(m.group(4), 16))
            elif ln.startswith("Exports list") or ln.startswith("Imports list"):
                break
    return out


def map_exports(mp):
    """{name: address} from ld65's map ("Exports list by name")"""
    out = {}
    on = False
    for ln in open(mp, encoding="latin-1"):
        if ln.startswith("Exports list by name"):
            on = True
            continue
        if on:
            if ln.startswith("Exports list by value") or ln.startswith("Imports list"):
                break
            for m in re.finditer(r"(\S+)\s+([0-9A-F]{6})\s+\w+", ln):
                out[m.group(1)] = int(m.group(2), 16)
    return out


def glue(tmp, thunks, aliases, nbanks, stamp, progname, code, noload=False):
    """the glue module -> its object. noload: every function is in the main bank: no
    loader (its own ___hz_xload returns at once)"""
    L = ["; made by hcc (tools/hzlarge.py): the large code model's glue", "\t.p816",
         "\t.smart -", "\t.a16", "\t.i16"]
    ex = ["___hz_xbanks", "___hz_xstamp", "___hz_xname", "___hz_xbank"]
    if noload:
        ex.append("___hz_xload")
        L += ['\t.segment "CODE"', "___hz_xload:", "\trtl"]
    im = sorted(set(thunks) | set(aliases))
    if im:
        L.append("\t.import " + ", ".join(im))
    ex += ["__T" + n for n in sorted(set(thunks) | set(aliases))]
    L.append("\t.export " + ", ".join(ex))
    for n in sorted(aliases):
        L.append(f"__T{n} = {n}")
    if thunks:
        L.append('\t.segment "THUNK"')
        for n in sorted(thunks):
            L += [f"__T{n}:", f"\tjml\t{n}"]
    L += ['\t.segment "RODATA"', f"___hz_xbanks:\t.word\t{nbanks}",
          f"___hz_xstamp:\t.dword\t${stamp:08X}",
          "___hz_xname:\t.byte\t" + ", ".join(f"${ord(c):02X}" for c in progname) + ", 0",
          '\t.segment "BSS"', f"___hz_xbank:\t.res\t{nbanks + 1}", ""]
    s = os.path.join(tmp, "hzglue.s")
    with open(s, "w") as f:
        f.write("\n".join(L))
    o = os.path.join(tmp, "hzglue.o")
    hzc816.assemble(s, o, code="large")
    return o


def _undefined(msg):
    out = set()
    for ln in msg.splitlines():
        m = hzc816._UNRES.match(ln.strip())
        if m:
            out.add(m.group(4))
    return out


def link(objs, out, sstack, debug=False, mapfile=None, libs=(), keep=None, heap=HEAP,
         bank_room=BANK, main_room=None, spread=None):
    """-> the sizes dict (as hzc816.link's, and 'banks', 'xblock', 'o65', 'moved', 'thunks')"""
    d = hzc816.libdir("large")
    name = os.path.basename(out)
    base = os.path.splitext(out)[0]
    # (before: the other banks were in a second file, NAME.PRX; one left from such a build
    # is removed)
    prx = base + ".PRX" if out.endswith(".PRG") else base + ".prx"
    progname = name[:64]
    tmp = keep or __import__("tempfile").mkdtemp(prefix="hcc")
    os.makedirs(tmp, exist_ok=True)
    room = hzc816.CODE_ROOM - sstack
    defs = [f"__HZ_SSTACK__={sstack}", f"__HZ_PAINT__={1 if debug else 0}"]
    head = [os.path.join(d, "crt0.o")] + list(objs)
    tail = list(libs) + [hzc816.lib_path("large")]
    # (the glue goes before the libraries: its ___hz_xload must win over the library's)
    try:
        # (the libraries' functions too: the C library's, hgame's, the controls
        # library's C part; only those the program links are placed, below)
        moved = movable_segments([o for o in objs if os.path.exists(o)] +
                                 [x for x in tail if os.path.exists(x)])
        fardata = movable_segments([o for o in objs if os.path.exists(o)] +
                                   [x for x in tail if os.path.exists(x)], FARDATA)
        # 2. the trial link (twice when __T_ names are missing: then with thunks for them)
        pool = [(n, "POOL") for n, _ in moved]
        tmo = os.path.join(tmp, "trial.o65")
        tmp_map = os.path.join(tmp, "trial.map")
        need = set()
        for attempt in range(12):
            g = glue(tmp, need, (), 0, 0, progname, "large")
            rc, msg = run_ld65(config(pool, 0, tmp, 0xFF00, trial=True,
                                      dplace=[(n, "POOL") for n, _ in fardata]), tmp, "trial",
                               head + [g] + tail, defs, tmo, tmp_map)
            if rc == 0:
                break
            und = _undefined(msg)
            t = {n[3:] for n in und if n.startswith("__T_")}
            if und and und <= {"__T" + x for x in t} and not t <= need:
                need |= t
                continue
            # (a name really missing: the thunks still wanted (__T_x of functions that are
            # defined, their address taken) are not the fault: say only the missing ones)
            if any(not n.startswith("__T_") for n in und):
                msg = "\n".join(ln for ln in msg.splitlines()
                                if not re.search(r"Unresolved external [‘'`]__T_", ln))
            # (a function's 16-bit address __T_x missing: it is x that is missing)
            msg = re.sub(r"([‘'`])__T(_\w+)([’'])", r"\1\2\3", msg)
            raise HccError(link_error(msg, name, sstack, tmp_map))
        else:
            raise HccError(msg.strip())
        sizes = seg_sizes(tmp_map)
        # only the segments linked (a library's modules the program does not use are not)
        moved = [(n, s) for n, s in moved if n in sizes]
        fardata = [(n, s) for n, s in fardata if n in sizes]
        # the far objects: first fit in banks of 64 KB
        dplace, dbanks = [], []
        for n, sz in fardata:
            if sz > 0x10000:
                raise HccError(f"{name}: the far object in segment {n} is {sz:,} bytes: more "
                               f"than a bank")
            for k, used in enumerate(dbanks):
                if used + sz <= 0x10000:
                    dbanks[k] += sz
                    dplace.append((n, k + 1))
                    break
            else:
                dbanks.append(sz)
                dplace.append((n, len(dbanks)))
        nd = len(dbanks)
        fixed = sum(sizes.get(s, (0, 0))[1] for s in MAIN_RO + MAIN_RO2 + MAIN_RW + MAIN_BSS)
        # each global function's segment, when it is a movable one (from the trial's map: a
        # segment may hold several functions), and the thunks that may be needed: one for
        # each movable function named by __T
        ranges = [(sizes[n][0], sizes[n][0] + sizes[n][1], n) for n, _ in moved if n in sizes]
        seg_of = {}
        for sym, a in map_exports(tmp_map).items():
            if a >= 0x10000:
                for lo, hi, n in ranges:
                    if lo <= a < hi:
                        seg_of[sym] = n
                        break
        thunk_max = 4 * sum(1 for x in need if x in seg_of)
        main_free = room - fixed - heap
        if main_free < 0:
            raise HccError(
                f"{name} does not fit in its code bank (the main bank), even with every "
                f"function in another bank: startup, libraries, constants, data and bss "
                f"take {fixed:,} bytes, the "
                f"heap's reserve {heap:,} (hcc --heap N) and the software stack {sstack:,} "
                f"(hcc --stack N), of {hzc816.CODE_ROOM:,}. With --code large only code "
                f"moves: put big arrays in banks of their own (hz_far_alloc and __far "
                f"pointers, docs/c/porting.md)")
        cap = None              # (the main bank's code, smaller when the file was too big)
        for _round in range(4):
            main_left = main_free - thunk_max
            if main_room is not None:
                main_left = min(main_left, main_room)
            if cap is not None:
                main_left = min(main_left, cap)
            # 3. the packing: first fit, the main bank first
            place = []
            banks = []              # bytes used in each bank
            turn = 0
            for n, s in moved:
                if spread and s > main_left:
                    # (--spread N, a test's: the functions in turn in N banks, so that even a
                    # small program's functions call each other across banks)
                    for t in range(spread):
                        k = (turn + t) % spread
                        while len(banks) <= k:
                            banks.append(0)
                        if banks[k] + s <= BANK:
                            banks[k] += s
                            place.append((n, k + 1))
                            break
                    else:
                        banks.append(s)
                        place.append((n, len(banks)))
                    turn += 1
                    continue
                if s <= main_left:
                    place.append((n, "MAIN"))
                    main_left -= s
                    continue
                if s > BANK:
                    raise HccError(f"{name}: the function in segment {n} is {s:,} bytes: larger "
                                   f"than a bank (65,535); split it")
                if s > bank_room:           # (--bank-room, a test's: a bank of its own)
                    banks.append(s)
                    place.append((n, len(banks)))
                    continue
                for k, used in enumerate(banks):
                    if used + s <= bank_room:
                        banks[k] += s
                        place.append((n, k + 1))
                        break
                else:
                    banks.append(s)
                    place.append((n, len(banks)))
            nb = len(banks)
            if nb + nd > MAX_BANKS:
                raise HccError(f"{name}: {nb} code banks and {nd} of far data: more than "
                               f"{MAX_BANKS}")
            where = dict(place)
            thunks = {x for x in need if x in seg_of and where[seg_of[x]] != "MAIN"}
            aliases = need - thunks
            # the build's stamp: from what was linked and where (the same build, the same
            # stamp; another build, almost surely another)
            import hashlib
            hs = hashlib.md5(repr(place).encode())
            for p in head + tail:
                if os.path.exists(p):
                    hs.update(open(p, "rb").read())
            stamp = int.from_bytes(hs.digest()[:4], "little") | 1
            g = glue(tmp, thunks, aliases, nb + nd, stamp, progname, "large",
                     noload=nb + nd == 0)
            # 5. links A and B
            res = {}
            for tag in ("A", "B", "C"):
                o65 = os.path.join(tmp, f"link{tag}.o65")
                mp = os.path.join(tmp, f"link{tag}.map")
                sub = os.path.join(tmp, tag)
                os.makedirs(sub, exist_ok=True)
                rc, msg = run_ld65(config(place, nb, sub, room, fake=FAKE[tag], off=OFFSET[tag],
                                          dplace=dplace, ndata=nd),
                                   tmp, "link" + tag, head + [g] + tail, defs, o65, mp,
                                   os.path.join(tmp, "linkA.lbl") if tag == "A" else None)
                if rc:
                    raise HccError(link_error(msg, name, sstack, mp))
                imgs = []
                for k in range(1, nb + nd + 1):
                    p = os.path.join(sub, f"bank{k}.bin")
                    imgs.append(open(p, "rb").read() if os.path.exists(p) else b"")
                xr = os.path.join(sub, "xrel.bin")
                res[tag] = (open(o65, "rb").read(), imgs,
                            open(xr, "rb").read() if os.path.exists(xr) else b"", mp)
            relocs = relocations(res, nb + nd, name)
            # (every function's 16-bit address in the main bank: a thunk or the function)
            bad = [x for x, a in map_exports(res["A"][3]).items() if x.startswith("__T_") and
                   a > 0xFFFF]
            if bad:
                raise HccError(f"{name}: hcc placed {bad[0][3:]} in another bank without a "
                               f"thunk (an hcc fault: please report)")
            # 6. the files
            shutil.copy(os.path.join(tmp, "linkA.o65"), out)
            import o65strip
            try:
                o65strip.strip(out)
            except (o65strip.StripError, SystemExit) as e:
                raise HccError(f"{name}: {e}")
            inmain = sum(sz for n, sz in moved if where[n] == "MAIN")
            fsize = os.path.getsize(out)
            if fsize > 0xFFFF and inmain:
                # the o65's relocations (one for each JSL in the main bank) made it too
                # big for Horizon's loader: less code in the main bank, and again
                cap = max(0, inmain - 2 * (fsize - 0xFFFF) - 1024)
                continue
            xblock = 0
            if fsize <= 0xFFFF and nb + nd:
                xblock = append_banks(out, res["A"][1], relocs, stamp)
            if os.path.exists(prx):
                os.remove(prx)
            break
        mp = res["A"][3]
        s = hzc816.map_sizes(mp)
        s["file"] = os.path.getsize(out)
        s["o65"] = fsize
        if fsize > 0xFFFF:
            raise HccError(f"{name}: its main bank's o65 is {fsize:,} bytes; Horizon's "
                           f"loader takes it only below 64 KB")
        s["sstack"] = sstack
        s["heap"] = max(0, hzc816.SSTOP - sstack - (0x100 + s["code"]))
        s["relocs"] = hzc816.o65_relocs(out)
        s["banks"] = [len(x) for x in res["A"][1][:nb]]
        s["fardata"] = [len(x) for x in res["A"][1][nb:]]
        s["xblock"] = xblock
        s["moved"] = sum(sz for n, sz in moved if where[n] != "MAIN")
        s["text"] -= s["moved"]                 # (the main bank's own)
        s["code"] = s["text"] + s["data"] + s["bss"]
        s["heap"] = max(0, hzc816.SSTOP - sstack - (0x100 + s["code"]))
        s["inmain"] = sum(sz for n, sz in moved if where[n] == "MAIN")
        s["thunks"] = len(thunks)
        s["xrelocs"] = sum(len(v) for v in relocs.values())
        if mapfile:
            # (the map, and every label: the main bank's at bank 0, code bank k's at bank
            # k: prof816.py reads them)
            shutil.copy(mp, mapfile)
            shutil.copy(os.path.join(tmp, "linkA.lbl"), os.path.splitext(mapfile)[0] + ".lbl")
        return s
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)


def relocations(res, nb, name):
    """{(where, to): [offsets]}: where/to 0 = the main bank, k = bank k (res: the three
    links' (o65 file, bank images, XREL, map))"""
    import o65strip
    rel = {}
    texts, imgs = {}, {}
    xa = res["A"][2]
    for t, (o65, im, _x, _m) in res.items():
        p = o65strip.parse(o65)
        n = p["tlen"] + p["dlen"]
        texts[t] = o65[p["toff"]:p["toff"] + n]
        imgs[t] = im
    ta, tb, tc = texts["A"], texts["B"], texts["C"]
    if not len(ta) == len(tb) == len(tc):
        raise HccError(f"{name}: the three links differ in size (an ld65 surprise)")

    def bank_of(a, b, c):
        """the bank k the three bytes name, 0 for none (the same in all), None for
        something else"""
        if a == b == c:
            return 0
        if 1 <= a <= nb and b == FAKE["B"](a) and c == FAKE["C"](a):
            return a
        return None
    n = len(ta)
    skip = set()
    for i in range(n):
        if i in skip or (ta[i] == tb[i] == tc[i]):
            continue
        k = bank_of(ta[i], tb[i], tc[i])
        if k:
            rel.setdefault((0, k), []).append(0x100 + i)
            continue
        # the offset of a far address in another bank: two bytes, the same in links A and
        # B, one more in link C, then its bank byte
        if i + 2 < n and ta[i:i + 2] == tb[i:i + 2] and \
                (ta[i] | ta[i + 1] << 8) + 1 == (tc[i] | tc[i + 1] << 8) and \
                bank_of(ta[i + 2], tb[i + 2], tc[i + 2]):
            skip |= {i + 1}
            continue
        raise HccError(f"{name}: main bank ${0x100 + i:04X}: a value that depends on where "
                       f"code is ({ta[i]:#x} / {tb[i]:#x} / {tc[i]:#x}): only a far address "
                       f"(JSL, .faraddr, ^name) of a function in another bank may; its 16-bit "
                       f"address is __T_name (docs/c/reference.md, \"The two code models\")")
    # the other banks: the recorded bank bytes
    sites = {}
    for j in range(0, len(xa) - 2, 3):
        a = xa[j] | xa[j + 1] << 8 | xa[j + 2] << 16
        bk, off = a >> 16, a & 0xFFFF
        if 1 <= bk <= nb:
            sites.setdefault(bk, set()).add(off)
    for k in range(1, nb + 1):
        a, b, c = imgs["A"][k - 1], imgs["B"][k - 1], imgs["C"][k - 1]
        if not len(a) == len(b) == len(c):
            raise HccError(f"{name}: bank {k}: the three links differ in size")
        rec = sites.get(k, set())
        for off in rec:
            v = bank_of(a[off], b[off], c[off])
            if v == 0 and a[off] == 0:
                rel.setdefault((k, 0), []).append(off)      # the main bank
            elif v:
                rel.setdefault((k, v), []).append(off)
            else:
                raise HccError(f"{name}: bank {k} ${off:04X}: a recorded bank byte that is "
                               f"not one ({a[off]:#x} / {b[off]:#x} / {c[off]:#x})")
        for i in range(len(a)):
            if a[i] != b[i] and i not in rec:
                raise HccError(
                    f"{name}: bank {k} ${i:04X}: a bank byte the compiler did not record "
                    f"(assembly in a function that is not in the main bank names a bank: "
                    f"^name, .faraddr, JSL)")
    for v in rel.values():
        v.sort()
    return rel


def append_banks(path, imgs, rel, stamp):
    """the other banks' block and the trailer after the o65 at path -> the bytes added"""
    at = os.path.getsize(path)
    out = bytearray(b"HZPX" + bytes([1, len(imgs), 0, 0]) + struct.pack("<I", stamp))
    for im in imgs:
        out += struct.pack("<I", len(im))
    for im in imgs:
        out += im
    groups = []
    for (w, t), offs in sorted(rel.items()):
        for k in range(0, len(offs), 0xFFFF):
            groups.append((w, t, offs[k:k + 0xFFFF]))
    out += struct.pack("<H", len(groups))
    for w, t, offs in groups:
        out += struct.pack("<BBH", w, t, len(offs))
        for o in offs:
            out += struct.pack("<H", o)
    out += struct.pack("<I", at) + b"HZPX"
    with open(path, "ab") as f:
        f.write(out)
    return len(out)


def link_error(msg, name, sstack, mp):
    """ld65's complaint in plain words (hzc816's, with the large code model's sizes)"""
    m = re.search(r"Range error in module [‘'`](\S+?)[’'], line (\d+)", msg)
    if m and "Range" in msg:
        return (f"{msg.strip()}\n(in the large code model a function in another bank has "
                f"a 24-bit address: its 16-bit one, a function pointer, is __T<name> "
                f"(docs/c/reference.md, \"The two code models\"))")
    over = re.findall(r"Segment [‘'](\w+)[’'] overflows memory area [‘'](\w+)[’'] by (\d+) bytes",
                      msg)
    for seg, area, by in over:
        if area == "MAIN":
            return (f"{name} does not fit in its code bank (the main bank), by {int(by):,} "
                    f"bytes: data, constants, bss, the libraries and the software stack "
                    f"({sstack:,}) must fit in it even with --code large; put big arrays in "
                    f"banks of their own (docs/c/porting.md)")
    return hzc816.link_error(msg, name, sstack, [], [], None, None).replace(
        "(used in hzglue.s)", "(its address is used: a function pointer)")
