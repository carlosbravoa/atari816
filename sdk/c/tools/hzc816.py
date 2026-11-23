"""hzc816.py - the machinery behind bin/hcc: compile (cc816, in this process), assemble
(ca65), build the C library, link (ld65) and check the sizes.

    build/lib/small/      crt0.o, libc816.lib (rt/*.s, the syscall stubs from
                          tools/gensys.py, lib/*.c), rebuilt whenever a source is newer
                          than it
    build/lib/large/      the same for the large code model (hcc --code large)
    rt/hzprog.cfg         the ld65 configuration: an o65 program at $0100 of its code bank
                          (the small code model; the large one's is made for each link:
                          tools/hzlarge.py)

One memory model: every data pointer is a 16-bit offset in the code bank (DBR), __far
pointers reach other banks; the software stack (arrays, structures, locals whose address
is taken) is the top of the code bank (--stack N bytes, default 8192), the hardware stack
the window (sdk/docs/c/reference.md).
$HZ_BUILD (default sdk/c/build) is where the libraries are built.
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
RT = os.path.join(SDKC, "rt")
CFG = os.path.join(RT, "hzprog.cfg")
sys.path.insert(0, HERE)
sys.path.insert(0, CC816)


class HccError(Exception):
    pass


VERBOSE = False
OPTS = ("0", "1", "2", "3", "s")        # -O levels hcc takes (3 and s are 2)


def run(cmd, what, filter_out=None, cwd=None):
    """Run a tool; on failure raise HccError with its (cleaned) output."""
    if VERBOSE:
        print("  " + " ".join(cmd), file=sys.stderr)
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=cwd)
    out = r.stdout.decode("latin-1")
    if filter_out:
        out = filter_out(out)
    if r.returncode != 0:
        raise HccError(out.rstrip() or f"{what} failed (exit {r.returncode})")
    return out


def horizon_dir():
    """the Horizon tree: $HORIZON, else the repository's"""
    return os.path.abspath(os.environ.get("HORIZON") or os.path.join(SDKC, "..", "..", "horizon"))


def cc65_tool(name):
    """ca65, ld65 or ar65 ($CA65, $LD65, $AR65, else on the PATH)"""
    t = os.environ.get(name.upper()) or shutil.which(name)
    if not t:
        raise HccError(f"{name} (cc65) is not installed: hcc assembles and links with cc65's "
                       f"ca65, ld65 and ar65 (sdk/docs/c/getting-started.md)")
    return t


def ui_names():
    """The C names hui.h defines (functions, variables): a program using one gets the
    controls library linked."""
    import genhui
    return set(genhui.c_names())


MATHFUNCS = set("""acos asin atan atan2 ceil cos cosh exp fabs floor fmod frexp ldexp log
log10 modf pow sin sinh sqrt tan tanh strtod atof cbrt exp2 log2 hypot round trunc fmin fmax
copysign nan expm1 log1p erf erfc lgamma tgamma rint lrint lround nearbyint remainder
acosh asinh atanh scalbn logb ilogb fdim fma""".split())


def undefined_names(msg):
    """The C names of a failed link's undefined symbols."""
    return set(re.findall(r"undefined: (\S+)", msg))


def is_float_name(s):
    return "flt" in s or s.rstrip("f") in MATHFUNCS or s in MATHFUNCS

SSTACK = 8192                   # the software stack's default size
# the code model: "small" (one bank, JSR/RTS) or "large" (hcc --code large: code in
# several banks, JSL/RTL; tools/hzlarge.py); $HZ_CODE sets the default (the tests use it)
CODE = os.environ.get("HZ_CODE") or "small"
CODES = ("small", "large")
# the data model: "near" (every data pointer an offset in the main bank) or "far" (hcc
# --data far, with --code large only: plain data pointers are 32-bit far pointers; the
# library's third build, build/lib/large-far); $HZ_DATA sets the default
DATA = os.environ.get("HZ_DATA") or "near"
DATAS = ("near", "far")
# the library's builds: a code model, or "large-far" (the large code model, far data)
LIBS = ("small", "large", "large-far")


def config(code=None, data=None):
    """the library build of a code model and a data model: small, large or large-far"""
    code = code or CODE
    if code.endswith("-far"):
        return code
    return "large-far" if code == "large" and (data or DATA) == "far" else code


def is_far(code=None, data=None):
    return config(code, data) == "large-far"
SSTOP = 0xFFF0                  # its top
ZONE = 256                      # its guard zone
CODE_ROOM = SSTOP - 0x100       # the code bank from $0100 to the software stack's top
O65_MAGIC = b"\x01\x00o65"
CA65_MAGIC = b"\x55\x7a\x6e\x61"    # ca65's object files

_cc = None
ASM_OF = {}                     # an assembly file's name -> the C file it was made from


def cc():
    """the compiler (imported once)"""
    global _cc
    if _cc is None:
        from cc816 import driver
        _cc = driver
    return _cc


def libdir(code=None, data=None):
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"), "lib",
                        config(code, data))


def is_large(code=None):
    return (code or CODE) in ("large", "large-far")


def tool(name):
    return cc65_tool(name)


def includes(incs=()):
    return list(incs) + [os.path.join(CC816, "include"), os.path.join(SDKC, "include")]


def compile_c(src, obj, opt="2", incs=(), defs=(), asm_out=None, opts=None, code=None,
              data=None):
    """C -> ca65 assembly -> object. Warnings are printed; errors raise HccError
    ('file:line:col: error: ...', a line each). opts: cc816's options (driver.default_opts:
    -w, -Wall, -Werror, -fsigned-char, -U, -include). code: the code model; data: the data
    model (near, far)"""
    from cc816.ctypes816 import CError
    level = {"0": 0, "1": 1}.get(opt, 2)
    opts = dict(opts or {})
    if is_large(code):
        opts["large"] = True
    if is_far(code, data):
        opts["far_data"] = True
    if VERBOSE:
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
            assemble(path, obj, src_name=src, code=config(code, data))


# the library files whose code must stay in the main bank in the large code model: the
# loader of the other banks (it runs before they are there) and what it calls
RESIDENT = ("xload.c", "misc.c")


def compile_split(src, outdir, opt="2", incs=(), defs=(), code=None, resident=None):
    """a library file: one object a function (ld65 links only those a program uses)
    -> the objects. In the large code model a library's functions move to other banks as
    a program's do (hcc places them), except a resident file's (RESIDENT: the main bank)"""
    from cc816.ctypes816 import CError
    level = {"0": 0, "1": 1}.get(opt, 2)
    if resident is None:
        resident = os.path.basename(src) in RESIDENT
    opts = {"large": True, "resident": bool(resident)} if is_large(code) else None
    if is_far(code):
        opts["far_data"] = True
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
    """ca65; the large code model: -D __CC816_LARGE__ (rt/model.inc: ARGS, RET,
    CALL, LARGE, which any .s file may include)"""
    cmd = [tool("ca65"), "--cpu", "65816", "-g", "-I", os.path.join(horizon_dir(), "user")]
    for i in incs:
        cmd += ["-I", i]
    cmd += ["-I", RT]
    if is_large(code):
        cmd += ["-D", "__CC816_LARGE__=1"]
    if is_far(code):
        cmd += ["-D", "__CC816_FAR_DATA__=1"]
    for d in defs:
        cmd += ["-D", d]
    cmd += ["-o", obj, src]
    run(cmd, f"assembling {src_name or src}")


def object_kind(path):
    """'cc816' (a ca65 object), 'lib' (an ar65 library) or '?'"""
    try:
        with open(path, "rb") as f:
            head = f.read(8)
    except OSError:
        return "?"
    if head.startswith(CA65_MAGIC):
        return "cc816"
    if head[:4] == b"\x6e\x61\x55\x7a" or head[:4] == b"\x61\x55\x7a\x6e":
        return "lib"
    return "?"


# ---- the library -------------------------------------------------------------------

def lib_sources():
    """(kind, path): rt/*.s (not the startup), lib/*.c"""
    out = []
    for f in sorted(os.listdir(RT)):
        if f.endswith(".s") and f != "crt0.s":
            out.append(("s", os.path.join(RT, f)))
    d = os.path.join(SDKC, "lib")
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
              os.path.join(SDKC, "lib")):
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
    code = config(code)
    d = libdir(code)
    od = os.path.join(d, "obj")
    if os.path.exists(od):
        shutil.rmtree(od)
    os.makedirs(od)
    if not quiet:
        print(f"hcc: building the C library for the {'large' if is_large(code) else 'small'} "
              f"code model{' with far data' if is_far(code) else ''} ({d})", file=sys.stderr)
    objs = []
    for s in gensys.write_stubs816(os.path.join(d, "stubs"), large=is_large(code),
                                   far=is_far(code)):
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
    run([tool("ar65"), "a", lib] + objs, "ar65")


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
    code = config(code)
    if lib_stale(code):
        with locked("lib-" + code):
            if lib_stale(code):
                build_lib(code=code)


# ---- linking -----------------------------------------------------------------------------

_UNRES = re.compile(r"^(\S+?)(?:\((\d+)\))?:(\d+): Warning: Unresolved external [‘'`](\S+?)[’']")
_OVER = re.compile(r"Segment [‘'](\w+)[’'] overflows memory area [‘'](\w+)[’'] by (\d+) bytes")


def link(objs, out, sstack=SSTACK, debug=False, mapfile=None, extra_libs=(), keep=None,
         ui=False, code=None, heap=None, bank_room=None, main_room=None, spread=None):
    """ld65 -> out (an o65 program). Returns the sizes dict. ui: link Horizon's controls
    library (the hui.h binding: build/ui/<code model>/). code: the code model; the large one
    (tools/hzlarge.py) also writes the other code banks after the o65, in the same file, when
    code goes to other banks: heap (the main bank's room kept for malloc), bank_room,
    main_room (the tests: how much code a bank, and the main bank, may take)"""
    code = config(code)
    ensure_lib(code)
    for o in objs:
        if object_kind(o) == "?":
            raise HccError(f"{o}: not an object (.o) or library (.lib, .a) made by hcc, "
                           f"ca65 or ar65")
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
            if is_far(code):
                raise HccError("the controls library (hui.h, --ui) is not built for the far "
                               "data model (hcc --data far): build a window application "
                               "with near data")
            import hui816
            libs += hui816.link_inputs("large")
        try:
            return hzlarge.link(objs, out, sstack, debug=debug, mapfile=mapfile, libs=libs,
                                keep=keep, heap=(hzlarge.HEAP_FAR if is_far(code) else
                                                 hzlarge.HEAP) if heap is None else heap,
                                bank_room=bank_room or hzlarge.BANK, main_room=main_room,
                                spread=spread, lib=code)
        except HccError as e:
            raise HccError(model_error(str(e), code))
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
        if VERBOSE:
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
        sizes["mapfile"], sizes["lblfile"], sizes["ncode"] = mp, lbl, 0
        if mapfile:
            shutil.copy(mp, mapfile)
            shutil.copy(lbl, os.path.splitext(mapfile)[0] + ".lbl")
        return sizes
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)


def model_error(msg, code):
    """an object made for the other code model: say so (cc816's objects import
    __cc816_small, __cc816_large or __cc816_largefar, which only that model's crt0.o
    defines)"""
    names = {"small": "the small code model", "large": "the large code model",
             "largefar": "the large code model with far data (hcc --data far)"}
    mine = code.replace("-", "")
    for other in names:
        if other == mine:
            continue
        if re.search(r"(undefined: _|Unresolved external\W+__)cc816_" + other + r"\b", msg):
            if other != "largefar" and mine != "largefar":
                return (f"an object made for the {other} code model; this program is linked "
                        f"for the {code} one: build every file with the same --code (hcc "
                        f"--code {code}; a library too)")
            return (f"an object made for {names[other]}; this program is linked for "
                    f"{names[mine]}: build every file with the same --code and --data (a "
                    f"library too)")
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
        if any(is_float_name(n) for n in names):
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
               and (s in ("STARTUP", "CODE", "RODATA", "THUNK") or s.startswith("F"))
               and not re.match(r"^FD(?:S[0-9a-f]{6})?_", s))       # (far data: its banks)
    s = {"text": text, "data": seg.get("DATA", 0), "bss": seg.get("BSS", 0),
         "rodata": seg.get("RODATA", 0),
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


def object_sizes(out, s, top=None):
    """hcc --sizes: every object and function of the link, its size and where it went
    (the main bank, code bank k, far data bank k), biggest first, from the link's map
    (its segments) and labels (each label's size: to the next label of its segment). The
    compiler's internal labels (branches, ...) are left out; a static's name has its
    file's tag (S......_)."""
    mp, lbl = s.get("mapfile"), s.get("lblfile")
    if not mp or not lbl or not os.path.exists(mp) or not os.path.exists(lbl):
        return f"{out}: no map for --sizes"
    segs = []
    on = False
    for ln in open(mp, encoding="latin-1"):
        if ln.startswith("Segment list:"):
            on = True
            continue
        if on:
            m = re.match(r"^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})", ln)
            if m:
                if int(m.group(4), 16):
                    segs.append((int(m.group(2), 16), int(m.group(3), 16) + 1, m.group(1)))
            elif ln.startswith("Exports list") or ln.startswith("Imports list"):
                break
    labels = {}
    for ln in open(lbl, encoding="latin-1"):
        p = ln.split()
        if len(p) >= 3 and p[0] == "al":
            labels.setdefault(int(p[1], 16), p[2].lstrip("."))
    addrs = sorted(labels)
    nb = s.get("ncode", 0)
    rows = []
    import bisect
    for lo, hi, seg in segs:
        if seg in ("ZEROPAGE", "ZPEND", "XREL", "HEAPSTART"):
            continue
        i = bisect.bisect_left(addrs, lo)
        inside = []
        while i < len(addrs) and addrs[i] < hi:
            inside.append(addrs[i])
            i += 1
        bank = lo >> 16
        if seg.startswith("FD"):
            kind, where = "far data", f"far data bank {bank - nb}" if bank else "main bank"
        elif seg in ("RODATA",):
            kind, where = "constants", "main bank"
        elif seg == "DATA":
            kind, where = "data", "main bank"
        elif seg == "BSS":
            kind, where = "bss", "main bank"
        else:
            kind, where = "code", f"code bank {bank}" if bank else "main bank"
        keep = []
        for a in inside:
            n = labels[a]
            if re.match(r"^(_\w|L_S\d|L_lit\d|S[0-9a-f]{6}_)", n) and not n.startswith("__T") \
                    and not re.match(r"^S[0-9a-f]{6}_L\w*_(b|x|asm)?\d+$", n):
                keep.append(a)
        for k, a in enumerate(keep):
            end = keep[k + 1] if k + 1 < len(keep) else hi
            n = labels[a]
            n = re.sub(r"^S[0-9a-f]{6}_", "", n)
            n = n[1:] if n.startswith("_") else n
            rows.append((end - a, n, kind, where))
    rows.sort(key=lambda r: (-r[0], r[1]))
    tot = {}
    for size, _, kind, where in rows:
        key = "main bank" if where == "main bank" else where.rsplit(" ", 1)[0]
        tot[(key, kind)] = tot.get((key, kind), 0) + size
    lines = [f"{out}: every object and function, its size and where it went (hcc --sizes)",
             f"{'bytes':>9}  {'what':<10} {'where':<18} name"]
    for size, n, kind, where in rows[:top] if top else rows:
        lines.append(f"{size:>9,}  {kind:<10} {where:<18} {n}")
    lines.append("totals: " + ", ".join(f"{k[0]} {k[1]} {v:,}" for k, v in sorted(tot.items())))
    return "\n".join(lines)


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
        if s["banks"] or s.get("fardata") else
        "  one file: everything is in the main bank, no other banks to load"]
        + ([f"  far data: {sum(s['fardata']):,} bytes of __far objects in "
            f"{len(s['fardata'])} bank(s) of their own"
            + (f" ({', '.join(f'{b:,}' for b in s['fardata'])}): string literals, "
               f"constants and __far objects (hcc --data far)" if s.get("far_model") else "")]
           if s.get("fardata") else [])
        + ([f"  the main bank without its movable code: {s['code'] - s['inmain']:,} bytes "
            f"(code that must stay {s['text'] - s['inmain'] - s.get('rodata', 0):,}, "
            f"constants {s.get('rodata', 0):,}, data {s['data']:,}, bss {s['bss']:,})"]
           if "inmain" in s else [])))
