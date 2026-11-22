"""hzc816.py - hcc's cc816 back end: compile (cc816, in this process), assemble (ca65),
build the C library, link (ld65) and check the sizes.

    build/lib/cc816/      crt0.o, libc816.lib (rt/cc816/*.s, the syscall stubs from
                          tools/gensys.py, lib/*.c, lib/cc816/*.c), rebuilt whenever a
                          source is newer than it
    build/lib/cc816l/     the same for the large code model (hcc --code large)
    rt/cc816/hzprog.cfg   the ld65 configuration: an o65 program at $0100 of its code bank
                          (the small code model; the large one's is made for each link:
                          tools/hzlarge.py)

One memory model: every data pointer is a 16-bit offset in the code bank (DBR), __far
pointers reach other banks; the software stack (arrays, structures, locals whose address
is taken) is the top of the code bank (--stack N bytes, default 8192), the hardware stack
the window (sdk/docs/c/reference.md).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
CC816 = os.path.join(SDKC, "cc816")
RT = os.path.join(SDKC, "rt", "cc816")
CFG = os.path.join(RT, "hzprog.cfg")
sys.path.insert(0, HERE)
sys.path.insert(0, CC816)
import hzc  # noqa: E402
from hzc import HccError  # noqa: E402

SSTACK = 8192                   # the software stack's default size
# the code model: "small" (one bank, JSR/RTS) or "large" (hcc --code large: code in
# several banks, JSL/RTL; tools/hzlarge.py); $HZ_CODE sets the default (the tests use it)
CODE = os.environ.get("HZ_CODE") or "small"
CODES = ("small", "large")
SSTOP = 0xFFF0                  # its top
ZONE = 256                      # its guard zone
CODE_ROOM = SSTOP - 0x100       # the code bank from $0100 to the software stack's top
O65_MAGIC = b"\x01\x00o65"
CA65_MAGIC = b"\x55\x7a\x6e\x61"    # ca65's object files
VOBJ_MAGIC = b"VOBJ"                # vasm's (vbcc's)

_cc = None
ASM_OF = {}                     # an assembly file's name -> the C file it was made from


def cc():
    """the compiler (imported once)"""
    global _cc
    if _cc is None:
        from cc816 import driver
        _cc = driver
    return _cc


def libdir(code=None):
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"), "lib",
                        "cc816l" if (code or CODE) == "large" else "cc816")


def is_large(code=None):
    return (code or CODE) == "large"


def tool(name):
    return hzc.cc65_tool(name)


def includes(incs=()):
    return list(incs) + [os.path.join(CC816, "include"), os.path.join(SDKC, "include")]


def compile_c(src, obj, opt="2", incs=(), defs=(), asm_out=None, opts=None, code=None):
    """C -> ca65 assembly -> object. Warnings are printed; errors raise HccError
    ('file:line:col: error: ...', a line each). opts: cc816's options (driver.default_opts:
    -w, -Wall, -Werror, -fsigned-char, -U, -include). code: the code model"""
    from cc816.ctypes816 import CError
    level = {"0": 0, "1": 1}.get(opt, 2)
    opts = dict(opts or {})
    if is_large(code):
        opts["large"] = True
    if hzc.VERBOSE:
        print(f"  cc816 -O{level} {src}", file=sys.stderr)
    try:
        asm, warns = cc().compile_c(src, list(incs) + [os.path.join(SDKC, "include")], defs,
                                    level, opts=opts)
    except CError as e:
        raise HccError(_where(str(e), src))
    for w in warns:
        print(w, file=sys.stderr)
    with tempfile.TemporaryDirectory(prefix="hcc") as tmp:
        path = asm_out or os.path.join(tmp, os.path.splitext(os.path.basename(src))[0] + ".s")
        ASM_OF[os.path.basename(path)] = src     # (the link's messages name the C file)
        with open(path, "w") as f:
            f.write(asm)
        if obj:
            assemble(path, obj, src_name=src, code=code)


def compile_split(src, outdir, opt="2", incs=(), defs=(), code=None):
    """a library file: one object a function (ld65 links only those a program uses)
    -> the objects. In the large code model a library's code is in the main bank"""
    from cc816.ctypes816 import CError
    level = {"0": 0, "1": 1}.get(opt, 2)
    opts = {"large": True, "resident": True} if is_large(code) else None
    try:
        mods, warns = cc().compile_c(src, list(incs) + [os.path.join(SDKC, "include")], defs,
                                     level, split=True, opts=opts)
    except CError as e:
        raise HccError(_where(str(e), src))
    for w in warns:
        print(w, file=sys.stderr)
    base = os.path.splitext(os.path.basename(src))[0]
    objs = []
    for name, asm in mods:
        p = os.path.join(outdir, f"{base}-{name}.s")
        with open(p, "w") as f:
            f.write(asm)
        o = p[:-2] + ".o"
        assemble(p, o, src_name=src, code=code)
        objs.append(o)
    return objs


def _where(msg, src):
    """a message without a place gets the source's name"""
    return msg if re.match(r"^\S+:\d+", msg) or msg.startswith(src + ":") else f"{src}: {msg}"


def assemble(src, obj, incs=(), defs=(), src_name=None, code=None):
    """ca65; the large code model: -D __CC816_LARGE__ (rt/cc816/model.inc: ARGS, RET,
    CALL, LARGE, which any .s file may include)"""
    cmd = [tool("ca65"), "--cpu", "65816", "-g", "-I", os.path.join(hzc.horizon_dir(), "user")]
    for i in incs:
        cmd += ["-I", i]
    cmd += ["-I", RT]
    if is_large(code):
        cmd += ["-D", "__CC816_LARGE__=1"]
    for d in defs:
        cmd += ["-D", d]
    cmd += ["-o", obj, src]
    hzc.run(cmd, f"assembling {src_name or src}")


def object_kind(path):
    """'cc816' (ca65), 'vbcc' (vasm), 'lib' (an archive) or '?'"""
    try:
        with open(path, "rb") as f:
            head = f.read(8)
    except OSError:
        return "?"
    if head.startswith(CA65_MAGIC):
        return "cc816"
    if head.startswith(VOBJ_MAGIC):
        return "vbcc"
    if head.startswith(b"!<arch>"):
        return "vbcc"                   # hcc --cc vbcc's libraries are ar archives
    if head[:4] == b"\x6e\x61\x55\x7a" or head[:4] == b"\x61\x55\x7a\x6e":
        return "lib"
    return "?"


# ---- the library -------------------------------------------------------------------

def lib_sources():
    """(kind, path): rt/cc816/*.s (not the startup), lib/*.c, lib/cc816/*.c"""
    out = []
    for f in sorted(os.listdir(RT)):
        if f.endswith(".s") and f != "crt0.s":
            out.append(("s", os.path.join(RT, f)))
    for d in (os.path.join(SDKC, "lib"), os.path.join(SDKC, "lib", "cc816")):
        for f in sorted(os.listdir(d)):
            if f.endswith(".c"):
                out.append(("c", os.path.join(d, f)))
    return out


def compiler_files():
    d = os.path.join(CC816, "cc816")
    return [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".py")]


def lib_inputs():
    files = [p for _, p in lib_sources()]
    files += [os.path.join(RT, "crt0.s"), os.path.join(RT, "model.inc"),
              os.path.join(HERE, "gensys.py"),
              os.path.join(HERE, "syscalls.tab"), os.path.abspath(__file__)]
    files += compiler_files()
    for d in (os.path.join(SDKC, "include"), os.path.join(CC816, "include"),
              os.path.join(SDKC, "lib", "cc816")):
        files += [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".h")]
    return files


def lib_path(code=None):
    return os.path.join(libdir(code), "libc816.lib")


def lib_stale(code=None):
    targets = [lib_path(code), os.path.join(libdir(code), "crt0.o")]
    if not all(os.path.exists(t) for t in targets):
        return True
    t = min(os.path.getmtime(x) for x in targets)
    return any(os.path.getmtime(f) > t for f in lib_inputs())


def build_lib(quiet=False, code=None):
    import gensys
    code = code or CODE
    d = libdir(code)
    od = os.path.join(d, "obj")
    if os.path.exists(od):
        shutil.rmtree(od)
    os.makedirs(od)
    if not quiet:
        print(f"hcc: building the C library for cc816"
              f"{' (large code model)' if is_large(code) else ''} ({d})", file=sys.stderr)
    objs = []
    for s in gensys.write_stubs816(os.path.join(d, "stubs"), large=is_large(code)):
        o = os.path.join(od, os.path.splitext(os.path.basename(s))[0] + ".o")
        assemble(s, o, code=code)
        objs.append(o)
    for kind, src in lib_sources():
        o = os.path.join(od, os.path.splitext(os.path.basename(src))[0] + ".o")
        if os.path.exists(o):
            raise HccError(f"{src}: two library sources named {os.path.basename(o)}")
        if kind == "c":
            objs += compile_split(src, od, "2", incs=[os.path.dirname(src)], code=code)
        else:
            assemble(src, o, code=code)
            objs.append(o)
    assemble(os.path.join(RT, "crt0.s"), os.path.join(d, "crt0.o"), code=code)
    lib = lib_path(code)
    if os.path.exists(lib):
        os.remove(lib)
    hzc.run([tool("ar65"), "a", lib] + objs, "ar65")


class locked:
    """an exclusive lock (a file in build/) around a library build: several hcc runs at
    once (make -j, tests in parallel) build it once"""
    def __init__(self, name):
        self.path = os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"),
                                 name + ".lock")

    def __enter__(self):
        import fcntl
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.f = open(self.path, "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        import fcntl
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def ensure_lib(code=None):
    code = code or CODE
    if lib_stale(code):
        with locked("libc816" + ("l" if is_large(code) else "")):
            if lib_stale(code):
                build_lib(code=code)


# ---- linking -----------------------------------------------------------------------------

_UNRES = re.compile(r"^(\S+?)(?:\((\d+)\))?:(\d+): Warning: Unresolved external [‘'`](\S+?)[’']")
_OVER = re.compile(r"Segment [‘'](\w+)[’'] overflows memory area [‘'](\w+)[’'] by (\d+) bytes")


def link(objs, out, sstack=SSTACK, debug=False, mapfile=None, extra_libs=(), keep=None,
         ui=False, code=None, heap=None, bank_room=None, main_room=None, spread=None):
    """ld65 -> out (an o65 program). Returns the sizes dict. ui: link Horizon's controls
    library (the hui.h binding: build/ui/cc816/). code: the code model; the large one
    (tools/hzlarge.py) also writes the other code banks after the o65, in the same file, when
    code goes to other banks: heap (the main bank's room kept for malloc), bank_room,
    main_room (the tests: how much code a bank, and the main bank, may take)"""
    code = code or CODE
    ensure_lib(code)
    for o in objs:
        k = object_kind(o)
        if k == "vbcc":
            raise HccError(f"{o}: an object or library made by vbcc (hcc --cc vbcc); this "
                           f"program is built with cc816: build every file with the same "
                           f"compiler (hcc --cc cc816)")
    if is_large(code):
        import hzlarge

        def env(name):
            v = os.environ.get(name)
            return int(v, 0) if v else None
        main_room = env("HZ_MAIN_ROOM") if main_room is None else main_room
        bank_room = bank_room or env("HZ_BANK_ROOM")
        spread = spread or env("HZ_SPREAD")
        libs = list(extra_libs)
        if ui:
            import hui816
            libs += hui816.link_inputs("large")
        try:
            return hzlarge.link(objs, out, sstack, debug=debug, mapfile=mapfile, libs=libs,
                                keep=keep, heap=hzlarge.HEAP if heap is None else heap,
                                bank_room=bank_room or hzlarge.BANK, main_room=main_room,
                                spread=spread)
        except HccError as e:
            raise HccError(model_error(str(e), "large"))
    d = libdir()
    tmp = keep or tempfile.mkdtemp(prefix="hcc")
    os.makedirs(tmp, exist_ok=True)
    name = os.path.basename(out)
    mp = os.path.join(tmp, name + ".map")
    lbl = os.path.join(tmp, name + ".lbl")
    try:
        libs = list(extra_libs)
        if ui:
            import hui816
            libs += hui816.link_inputs("small")
        cmd = [tool("ld65"), "-C", CFG, "-o", out, "-m", mp, "-Ln", lbl,
               "-D", f"__HZ_SSTACK__={sstack}", "-D", f"__HZ_PAINT__={1 if debug else 0}",
               os.path.join(d, "crt0.o")] + list(objs) + libs + [lib_path()]
        if hzc.VERBOSE:
            print("  " + " ".join(cmd), file=sys.stderr)
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        msg = r.stdout.decode("utf-8", "replace")
        if r.returncode:
            raise HccError(model_error(link_error(msg, name, sstack, objs, libs, tmp, mp),
                                       "small"))
        import o65strip
        try:
            o65strip.strip(out)         # the relocations that add 0 (the loader's $0100)
        except (o65strip.StripError, SystemExit) as e:
            raise HccError(f"{name}: {e}")
        sizes = map_sizes(mp)
        sizes["file"] = os.path.getsize(out)
        if sizes["file"] > 0xFFFF:
            raise HccError(f"{name}: the program file is {sizes['file']:,} bytes; Horizon's "
                           f"loader takes files below 64 KB")
        sizes["sstack"] = sstack
        sizes["heap"] = max(0, SSTOP - sstack - (0x100 + sizes["code"]))
        sizes["relocs"] = o65_relocs(out)
        if mapfile:
            shutil.copy(mp, mapfile)
            shutil.copy(lbl, os.path.splitext(mapfile)[0] + ".lbl")
        return sizes
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)


def model_error(msg, code):
    """an object made for the other code model: say so (cc816's objects import
    __cc816_small or __cc816_large, which only that model's crt0.o defines)"""
    other = "large" if code == "small" else "small"
    if re.search(r"(undefined: _|Unresolved external\W+__)cc816_" + other + r"\b", msg):
        return (f"an object made for the {other} code model; this program is linked for "
                f"the {code} one: build every file with the same --code (hcc --code {code}; "
                f"a library too)")
    return msg


def link_error(msg, name, sstack, objs, libs, tmp, mapfile=None):
    """ld65's complaint in plain words"""
    undef = []
    for ln in msg.splitlines():
        m = _UNRES.match(ln.strip())
        if m:
            sym = m.group(4)
            c = sym[1:] if sym.startswith("_") else sym
            where = os.path.basename(m.group(1))
            where = os.path.basename(ASM_OF.get(where, where))
            undef.append(f"undefined: {c} (used in {where})")
    if undef:
        lines = sorted(set(undef))
        names = {u.split()[1] for u in lines}
        if any(hzc.is_float_name(n) for n in names):
            lines.append("(cc816's math.h has the functions docs/c/reference.md lists, "
                         "\"Floating point\"; not this one)")
        lines.append("(no file of the program defines " + ("these" if len(names) > 1 else "it")
                     + ": a .c or .s file missing from the hcc command, a library (-l), a "
                       "misspelt name, or a function declared but never written)")
        return "\n".join(lines)
    over = [int(m.group(3)) for m in _OVER.finditer(msg) if m.group(2) == "MAIN"]
    if over:
        room = CODE_ROOM - sstack
        total = room + max(over)
        sizes = None
        try:
            sizes = map_sizes(mapfile) if mapfile and os.path.exists(mapfile) else None
        except (OSError, ValueError):
            sizes = None
        codeonly = None
        if sizes and sizes["code"] > room:
            total = sizes["code"]
            codeonly = sizes.get("codeonly")
            seg = (f"code and constants {sizes['text']:,} + data {sizes['data']:,} + bss "
                   f"{sizes['bss']:,} = {total:,} bytes")
            big = max((("code and constants", sizes["text"]), ("initialised data (data)",
                       sizes["data"]), ("zeroed globals and statics (bss)", sizes["bss"])),
                      key=lambda x: x[1])[0]
            seg += f"; the biggest part: {big}"
        else:
            seg = f"code, constants, data and bss = {total:,} bytes"
        if codeonly is not None and total - codeonly > room:
            how = (f"Its data, constants and bss alone ({total - codeonly:,} bytes) do not fit "
                   f"either, so hcc --code large (code in other banks) is not enough: put big "
                   f"arrays in a bank of their own (hz_far_alloc and a __far pointer, "
                   f"docs/c/porting.md), make them smaller, or give the software stack less.")
        else:
            how = (f"Build it with hcc --code large: its code then goes in several banks "
                   f"(docs/c/porting.md). Or put big arrays in a bank of their own "
                   f"(hz_far_alloc and a __far pointer, docs/c/reference.md), make them "
                   f"smaller, or give the software stack less.")
        head = (f"{name}: program too big by {total - room:,} bytes"
                + (": build with --code large. " if codeonly is None or total - codeonly <= room
                   else ". "))
        return (f"{head}It does not fit in its code bank: {seg}. A code bank holds {CODE_ROOM:,} "
                f"bytes ($0100-$FFF0) and the software stack takes {sstack:,} of them (hcc "
                f"--stack N), so {room:,} are left. {how}")
    return msg.strip() or "the link failed (ld65)"


def map_sizes(mp):
    """text (code and constants), data, bss, zp from ld65's map ('Segment list')"""
    seg = {}
    on = False
    for ln in open(mp, encoding="latin-1"):
        if ln.startswith("Segment list:"):
            on = True
            continue
        if on:
            m = re.match(r"^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})", ln)
            if m:
                seg[m.group(1)] = int(m.group(4), 16)
            elif ln.startswith("Exports list") or ln.startswith("Imports list"):
                break
    text = sum(seg.get(s, 0) for s in seg if s not in ("DATA", "BSS", "ZEROPAGE", "ZPEND",
                                                       "HEAPSTART", "XREL")
               and (s in ("STARTUP", "CODE", "RODATA", "THUNK") or s.startswith("F")))
    s = {"text": text, "data": seg.get("DATA", 0), "bss": seg.get("BSS", 0),
         "zp": seg.get("ZEROPAGE", 0), "codeonly": seg.get("STARTUP", 0) + seg.get("CODE", 0)}
    s["code"] = s["text"] + s["data"] + s["bss"]
    return s


def o65_relocs(path):
    """the number of relocation entries in an o65 file (text and data)"""
    d = open(path, "rb").read()
    if not d.startswith(O65_MAGIC):
        return 0
    h = [int.from_bytes(d[8 + 2 * i:10 + 2 * i], "little") for i in range(9)]
    tlen, dlen = h[1], h[3]
    p = 26
    while d[p]:
        p += d[p]
    p += 1 + tlen + dlen
    n = int.from_bytes(d[p:p + 2], "little")        # undefined references
    p += 2
    for _ in range(n):
        while d[p]:
            p += 1
        p += 1
    count = 0
    for _ in range(2):
        while True:
            b = d[p]
            p += 1
            if b == 0:
                break
            if b == 255:
                continue
            t = d[p]
            p += 1
            if t & 0xE0 == 0x40:
                p += 1
            elif t & 0xE0 == 0xA0:
                p += 2
            count += 1
    return count


def size_report(out, s):
    return "\n".join([
        f"{out}: {s['file']:,} bytes on the card, {s['relocs']} relocations",
        f"  code bank: code+constants {s['text']:,} + data {s['data']:,} + bss {s['bss']:,} = "
        f"{s['code']:,} of {CODE_ROOM - s['sstack']:,}; heap {s['heap']:,}; software stack "
        f"{s['sstack']:,}",
        f"  window:    stack about 32,000 (from $7F7F down to $0100); direct page "
        f"{s['zp']} bytes"] + ([] if "banks" not in s else [
        f"  code model large: {s['inmain']:,} bytes of movable code in the main bank, "
        f"{s['moved']:,} in {len(s['banks'])} other bank(s)"
        + (f" ({', '.join(f'{b:,}' for b in s['banks'])})" if s["banks"] else "")
        + f"; {s['thunks']} thunks",
        f"  one file: the o65 {s['o65']:,} bytes, then the other banks {s['xblock']:,} bytes; "
        f"{s['xrelocs']} bank bytes patched at the start"
        if s["banks"] else "  one file: everything is in the main bank, no other banks to load"]))
