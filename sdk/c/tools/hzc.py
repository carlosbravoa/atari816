"""hzc.py - the machinery behind bin/hcc: compile, assemble, build the library, link.

Paths:
  SDKC                 sdk/c (this file's parent's parent)
  toolchain            $HZ_VBCC, else sdk/c/toolchain/vbcc (tools/get-toolchain.sh)
  library              sdk/c/build/lib/<model>/ (crt0.o, obj/*.o listed in "objects"),
                       rebuilt by build_lib() whenever a source is newer than it
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import mko65  # noqa: E402

MODELS = ("large", "tiny")
BANKS = (0x000000, 0x5A0000, 0xA50000)
# vbcc's -O levels as vc maps them (frontend/vc.c): -O0 0, -O1 991, -O2 1023, -O3 ~0
OPTS = {"0": ["-O=0"], "1": ["-O=991"], "2": ["-O=1023"], "3": ["-O=-1"],
        "s": ["-O=1023", "-size"]}
# -O1 (vbcc's local optimisations) by default: with the global ones (-O2, -O3) vbcc 65816
# does not see that a function called with &local writes the local, and moves or drops
# reads of it (its warning 171, "var used before defined", marks those places)
DEFAULT_OPT = "1"


class HccError(Exception):
    pass


def vbcc_dir():
    d = os.environ.get("HZ_VBCC") or os.path.join(SDKC, "toolchain", "vbcc")
    if not os.path.exists(os.path.join(d, "bin", "vbcc65816")):
        raise HccError(f"the vbcc toolchain is not installed (looked in {d}).\n"
                       f"Install it with: {os.path.join(SDKC, 'tools', 'get-toolchain.sh')}")
    return d


def tool(name):
    return os.path.join(vbcc_dir(), "bin", name)


def target_dir():
    return os.path.join(vbcc_dir(), "targets", "65816-sim")


def libdir(model):
    """$HZ_BUILD (default sdk/c/build) /lib/<model>"""
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"), "lib", model)


VERBOSE = False


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


# vbcc: 'error 20 in line 3 of "x.c": message' / 'warning 51 in line 4 of "x.c": ...'
# (or '... in function "f": ...'); turned into 'x.c:3: error 20: message'
_VB = re.compile(r'^(error|warning) (\d+) in line (\d+) of "([^"]+)": (.*)$')
_VBF = re.compile(r'^(error|warning) (\d+) in function "([^"]+)": (.*)$')


def vbcc_messages(out, src):
    lines = []
    for ln in out.splitlines():
        ln = ln.rstrip()
        if not ln or ln.startswith(">"):
            if ln.startswith(">") and lines:
                lines[-1] += "\n    " + ln[1:].strip()
            continue
        m = _VB.match(ln)
        m2 = _VBF.match(ln)
        if m:
            kind, num, line, f, msg = m.groups()
            lines.append(f"{f}:{line}: {kind}: {msg} (vbcc {num})")
        elif m2:
            kind, num, fn, msg = m2.groups()
            lines.append(f"{src}: in {fn}(): {kind}: {msg} (vbcc {num})")
        elif ln.startswith("aborting") or re.match(r"^\d+ errors? found", ln):
            continue
        else:
            lines.append(ln)
    return "\n".join(lines)


def compile_c(src, obj, model, opt=DEFAULT_OPT, incs=(), defs=(), asm_out=None, extra=()):
    """C -> vasm source -> vobj object. Warnings are printed; errors raise HccError."""
    vb = vbcc_dir()
    with tempfile.TemporaryDirectory(prefix="hcc") as tmp:
        asm = asm_out or os.path.join(tmp, "out.s")
        # -msfp4: floating point in the MS BASIC format (libms4), the faster of vbcc's two
        cmd = [tool("vbcc65816"), "-quiet", "-unsigned-char", "-msfp4",
               "-D__HORIZON__=1", "-D__ATARI816__=1"]
        if model == "tiny":
            # -nox: no variable in X. vbcc 65816 (r2 and the 2026-01 snapshot) loads a
            # 32-bit value through a pointer held in X as "lda 2,x / tax / lda 0,x",
            # which reads the low word through the high word (fix_asm's other case)
            # -D__MTINY: the manual's name for the tiny model (the compiler defines __MNEAR)
            cmd += ["-mtiny", "-nox", "-D__MTINY=1"]
        cmd += OPTS[opt]
        if opt == "3":
            cmd.append("-speed")
        cmd += list(extra)
        if os.environ.get("HZ_VBCCFLAGS"):
            cmd += os.environ["HZ_VBCCFLAGS"].split()
        for d in defs:
            cmd.append("-D" + d)
        for i in list(incs) + [os.path.join(SDKC, "include"), os.path.join(target_dir(), "include")]:
            cmd.append("-I" + i)
        cmd += [src, "-o=" + asm]
        if VERBOSE:
            print("  " + " ".join(cmd), file=sys.stderr)
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        msg = vbcc_messages(r.stdout.decode("latin-1"), src)
        if r.returncode != 0 or not os.path.exists(asm):
            raise HccError(msg or f"{src}: the compiler failed (exit {r.returncode})")
        if msg:
            if "(vbcc 171)" in msg and opt in ("2", "3", "s"):
                msg += ("\nhcc: warning 171 at -O" + opt + ": the optimiser does not see that a "
                        "function called with that variable's address writes it, and may read "
                        "it too early: the code is likely wrong. Compile this file with -O1 "
                        "(docs/c/reference.md, \"Compiler notes\").")
            print(msg, file=sys.stderr)
        n = fix_asm(asm, model)
        if n and VERBOSE:
            print(f"  hcc: {n} code-generator slip(s) repaired in {src}", file=sys.stderr)
        if obj:
            assemble(asm, obj, model, src_name=src)


# vbcc 65816 (r2 and the 2026-01 snapshot) loads a 32-bit value (long, far pointer) from
# a static array indexed by a variable into A/X as
#     lda >2+sym,x ;am(rN)    the high word into A
#     ldx rN                  the index again
#     lda >0+sym,x ;am(rN)    the low word into A: the high word is lost
# (X should get the high word). The first load is dead in this shape, so the pattern is
# unambiguous; the repair keeps the high word on the stack and pulls it into X.
_BADLOAD = re.compile(r"^\tlda\t(>?)(\d+)\+(\S+),x ;am\((r\d+)\)\n"
                      r"\tldx\t\4\n"
                      r"\tlda\t\1(\d+)\+\3,x ;am\(\4\)\n", re.M)


def fix_asm(path, model="large"):
    """Repair code-generator slips of vbcc 65816 in its assembly output (see the comments
    above _BADLOAD, fix_ysave, fix_nearoff and fix_neardw). Returns the number of places
    repaired."""
    txt = open(path, encoding="latin-1").read()
    n = 0

    def rep(m):
        nonlocal n
        if int(m.group(2)) != int(m.group(5)) + 2:
            return m.group(0)
        n += 1
        lng, hi, sym, r, lo = m.groups()
        return (f"\tlda\t{lng}{hi}+{sym},x ;am({r})\n\tpha\n\tldx\t{r}\n"
                f"\tlda\t{lng}{lo}+{sym},x ;am({r})\n\tplx\n")
    new = _BADLOAD.sub(rep, txt)
    new, k = fix_ysave(new)
    n += k
    new, k = fix_nearoff(new)
    n += k
    if model != "tiny":
        new, k = fix_neardw(new)
        n += k
    if n:
        with open(path, "w", encoding="latin-1") as f:
            f.write(new)
    return n


# vbcc 65816 keeps track of a constant in Y (an offset for "lda [rN],y") and skips the
# "ldy #k" when Y should still hold k. To reach a far array with X as the index while X
# holds a value, it saves X in Y ("txy / ldx rN / op ...,x / tyx") but does not forget
# the constant it believed Y held: a later "[rN],y" then indexes with X's old value (a
# 32-bit compare of two array elements read the wrong bank). After such a sequence the
# constant is loaded into Y again, flags kept (php / ldy #k / plp).
_INSN = re.compile(r"^\t([a-z]{3})(?:\t(.*?))?\s*(?:;.*)?$")


def fix_ysave(txt):
    out = []
    lines = txt.split("\n")
    yk = None           # the constant the compiler believes Y holds, if any
    saved = None        # in a save sequence: that constant
    insave = False
    n = 0
    i = 0
    while i < len(lines):
        ln = lines[i]
        out.append(ln)
        m = _INSN.match(ln)
        if not m:
            if ln and not ln.startswith("\t") and not ln.startswith(";"):
                yk = None                       # a label: anything may arrive here
            i += 1
            continue
        op, arg = m.group(1), (m.group(2) or "").strip()
        nxt = _INSN.match(lines[i + 1]) if i + 1 < len(lines) else None
        if op == "txy" and nxt and nxt.group(1) in ("ldx", "tax"):
            insave, saved = True, yk
        elif insave and op == "tyx":
            insave = False
            if nxt and nxt.group(1) == "plp":
                out.append(lines[i + 1])
                i += 1
            if saved is not None:
                out += ["\tphp", f"\tldy\t#{saved}", "\tplp"]
                n += 1
            yk = saved
        elif op == "ldy" and arg.startswith("#"):
            try:
                yk = int(arg[1:], 0)
            except ValueError:
                yk = None
        elif op == "iny" and yk is not None:
            yk += 1
        elif op == "dey" and yk is not None:
            yk -= 1
        elif op in ("ldy", "tay", "ply", "txy", "tsy", "jsl", "jsr", "jml", "rtl", "rts",
                    "mvn", "mvp", "cop", "brk"):
            yk = None
        i += 1
    return "\n".join(out), n


# vbcc 65816 (r2) reads or writes through a 16-bit (near) pointer held in a member of a
# static structure at offset K, at the pointer's offset 0, as
#     ldx K+sym              (or lda >K+sym / tax)
#     lda !K,x               the member's offset again: should be !0,x
# (s.label[0], s.next->first, in the tiny model every pointer member; in the large model
# __near ones, as the controls library's structures have). For any other offset it adds
# the offset to the pointer (adc #n / tax / !0,x), so "!K,x" with the K of the load is
# always this slip. The repair writes !0,x.
_XLOAD = re.compile(r"^\t(?:ldx\t|lda\t)>?(\d+)\+\S+\s*(?:;.*)?$")
_XUSE = re.compile(r"^(\t[a-z]{3}\t)!(\d+),x(\s*(?:;.*)?)$")
_XKEEP = re.compile(r"^\t(?:sep|rep|a8|a16|x8|x16|lda\t#|php|plp|clc|sec)\b")


def fix_nearoff(txt):
    lines = txt.split("\n")
    n = 0
    k = None            # X holds the near pointer loaded from member offset k
    pend = None         # lda K+sym seen: a tax makes it X's
    for i, ln in enumerate(lines):
        m = _XLOAD.match(ln)
        if m:
            if ln.startswith("\tldx"):
                k, pend = int(m.group(1)), None
            else:
                pend = int(m.group(1))
            continue
        if ln.startswith("\ttax") and pend is not None:
            k, pend = pend, None
            continue
        pend = None
        u = _XUSE.match(ln)
        if u and k and int(u.group(2)) == k:
            lines[i] = f"{u.group(1)}!0,x{u.group(3)}"
            n += 1
            continue
        if u or _XKEEP.match(ln):
            continue                    # X unchanged
        k = None
    return "\n".join(lines), n


# Large model: a __near pointer in initialised data is "dw label", a 16-bit field that
# vasm relocates with the full address and vlink then refuses in the links at banks $5A
# and $A5 ("doesn't fit into relocation type R_ABS ... size=16"). The offset is what is
# meant: "dw <label" (vasm's selector: the bits that fit the field). Instructions are not
# concerned (vasm masks their 16-bit operands already).
_NEARDW = re.compile(r"^\tdw\t([A-Za-z_.][^;\s]*)(\s*(?:;.*)?)$", re.M)


def fix_neardw(txt):
    return _NEARDW.subn(lambda m: f"\tdw\t<{m.group(1)}{m.group(2)}", txt)


def assemble(src, obj, model, defs=(), incs=(), src_name=None):
    cmd = [tool("vasm6502_oldstyle"), "-816", "-vobj3", "-quiet", "-nowarn=62", "-opt-branch",
           "-ldots", "-Fvobj"]
    if model == "tiny":
        cmd.append("-DTINY=1")
    else:
        cmd.append("-DTINY=0")
    for d in defs:
        cmd.append("-D" + d)
    for i in incs:
        cmd.append("-I" + i)
    cmd += [src, "-o", obj]
    run(cmd, f"assembling {src_name or src}")


# ---- the library -------------------------------------------------------------------

def lib_sources():
    """(kind, path) of everything in libhz.a, both models."""
    srcs = []
    for d, kind in (("lib", "c"), ("fastrt", "s")):
        p = os.path.join(SDKC, d)
        for f in sorted(os.listdir(p)):
            if f.endswith(".c") or f.endswith(".s"):
                srcs.append((f[-1], os.path.join(p, f)))
    return srcs


def lib_inputs():
    files = [p for _, p in lib_sources()]
    files += [os.path.join(SDKC, "rt", "crt0.s"), os.path.join(SDKC, "tools", "gensys.py"),
              os.path.join(SDKC, "tools", "syscalls.tab"), os.path.join(SDKC, "tools", "hzc.py")]
    inc = os.path.join(SDKC, "include")
    files += [os.path.join(inc, f) for f in os.listdir(inc)]
    return files


def lib_stale(model):
    d = libdir(model)
    targets = [os.path.join(d, "objects"), os.path.join(d, "crt0.o")]
    if not all(os.path.exists(t) for t in targets):
        return True
    t = min(os.path.getmtime(x) for x in targets)
    return any(os.path.getmtime(f) > t for f in lib_inputs())


def write_ar(path, members):
    """A plain 'ar' archive (vlink reads it), members = list of file paths."""
    with open(path + ".new", "wb") as o:
        o.write(b"!<arch>\n")
        for m in members:
            data = open(m, "rb").read()
            name = (os.path.basename(m) + "/").encode()
            if len(name) > 16:
                raise HccError(f"archive member name too long: {m}")
            hdr = (name.ljust(16) + b"0".ljust(12) + b"0".ljust(6) + b"0".ljust(6) +
                   b"100644".ljust(8) + str(len(data)).encode().ljust(10) + b"`\n")
            o.write(hdr)
            o.write(data)
            if len(data) % 2:
                o.write(b"\n")
    os.replace(path + ".new", path)


def build_lib(model, quiet=False):
    import gensys
    d = libdir(model)
    od = os.path.join(d, "obj")
    os.makedirs(od, exist_ok=True)
    if not quiet:
        print(f"hcc: building the C library for the {model} model ({d})", file=sys.stderr)
    objs = []
    stubs = os.path.join(d, "hzsys.s")
    gensys.write_stubs(stubs, model)
    o = os.path.join(od, "hzsys.o")
    assemble(stubs, o, model)
    objs.append(o)
    for kind, src in lib_sources():
        o = os.path.join(od, os.path.splitext(os.path.basename(src))[0] + ".o")
        if kind == "c":
            compile_c(src, o, model, opt="1")
        else:
            assemble(src, o, model)
        objs.append(o)
    assemble(os.path.join(SDKC, "rt", "crt0.s"), os.path.join(d, "crt0.o"), model)
    with open(os.path.join(d, "objects"), "w") as f:
        f.write("\n".join(objs) + "\n")


def lib_objects(model):
    with open(os.path.join(libdir(model), "objects")) as f:
        return [ln.strip() for ln in f if ln.strip()]


def ensure_lib(model):
    if lib_stale(model):
        build_lib(model)


# ---- the controls library (hui.h) ----------------------------------------------------
#
# Horizon's controls library (horizon/user/ui*.s) and ulib are ca65 code: hcc assembles
# them from the Horizon tree's sources with the generated JSL->JSR shims (tools/genhui.py,
# ui/hui.tab) and the SDK's helpers (ui/lib) into build/ui/hui.lib (an ar65 archive), once
# and again whenever a source changes. For a program that uses hui.h, ld65 links the
# shims it calls (and what they need) into one block at $0100 with the zero page at
# $50-$EF (vbcc's registers are $00-$4F, the float library's $F0-$FF); the block goes
# first in the program's text (rt/horizon.cmd's *_text.blob) and its bank bytes become
# relocations (mko65's BANKS file). sdk/docs/c/apps.md, "How the block is built".

UI_TINY = ("the controls library (hui.h) needs the large model: build without "
           "--model tiny (sdk/docs/c/apps.md, \"Limits\")")


def horizon_dir():
    return os.path.abspath(os.environ.get("HORIZON") or os.path.join(SDKC, "..", "..", "horizon"))


def ui_dir():
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"), "ui")


def cc65_tool(name):
    t = os.environ.get(name.upper()) or shutil.which(name)
    if not t:
        raise HccError(f"{name} (cc65) is not installed: the controls library (hui.h) is "
                       f"assembled and linked with ca65 / ld65 / ar65 (sdk/docs/c/apps.md)")
    return t


def ui_inputs():
    user = os.path.join(horizon_dir(), "user")
    files = [os.path.join(user, f) for f in os.listdir(user)
             if (f.startswith("ui") and f.endswith(".s")) or
             f in ("ui.inc", "horizon.inc", "version.inc", "icons.inc", "ulib.s")]
    lib = os.path.join(SDKC, "ui", "lib")
    files += [os.path.join(lib, f) for f in os.listdir(lib)]
    files += [os.path.join(SDKC, "ui", f) for f in ("hui.tab", "huirt.c", "blob.cfg")]
    files += [os.path.join(HERE, "genhui.py")]
    return files


def ui_stale():
    stamp = os.path.join(ui_dir(), "stamp")
    if not os.path.exists(stamp):
        return True
    t = os.path.getmtime(stamp)
    return any(os.path.getmtime(f) > t for f in ui_inputs())


def build_ui(quiet=False):
    import genhui
    hz = horizon_dir()
    user = os.path.join(hz, "user")
    if not os.path.exists(os.path.join(user, "ui.inc")):
        raise HccError(f"the Horizon tree is not at {hz} (set HORIZON): the controls library "
                       f"is built from its sources")
    ca65, ar65 = cc65_tool("ca65"), cc65_tool("ar65")
    d = ui_dir()
    od = os.path.join(d, "obj")
    if os.path.exists(od):
        shutil.rmtree(od)
    os.makedirs(od)
    if not quiet:
        print(f"hcc: building the controls library for C ({d}) from {user}", file=sys.stderr)
    fns, _, _ = genhui.parse_table()
    shims = genhui.write_shims(os.path.join(d, "shims"), fns)
    lib = os.path.join(SDKC, "ui", "lib")
    srcs = [os.path.join(user, f) for f in sorted(os.listdir(user))
            if f.startswith("ui") and f.endswith(".s")]
    srcs.append(os.path.join(user, "ulib.s"))
    srcs += [os.path.join(lib, f) for f in sorted(os.listdir(lib)) if f.endswith(".s")]
    srcs += shims
    members = []
    for src in srcs:
        o = os.path.join(od, os.path.splitext(os.path.basename(src))[0] + ".o")
        run([ca65, "--cpu", "65816", "-I", user, "-I", lib, "-o", o, src], f"assembling {src}")
        if os.path.basename(o) != "hdr.o":
            members.append(o)
    arc = os.path.join(d, "hui.lib")
    if os.path.exists(arc):
        os.remove(arc)
    run([ar65, "a", arc] + members, "ar65")
    shutil.copy(os.path.join(od, "hdr.o"), os.path.join(d, "hdr.o"))
    shutil.copy(os.path.join(SDKC, "ui", "blob.cfg"), os.path.join(d, "blob.cfg"))
    compile_c(os.path.join(SDKC, "ui", "huirt.c"), os.path.join(d, "huirt.o"), "large", opt="1")
    open(os.path.join(d, "stamp"), "w").write("ok\n")


def ensure_ui():
    if ui_stale():
        build_ui()


def ui_names():
    """The C names hui.h defines (functions, variables): a program using one gets the
    block."""
    import genhui
    return set(genhui.c_names())


def o65_block(path):
    """An ld65 o65 file linked at $0100 -> (image: text + data + bss as zeros, the
    addresses of its bank bytes, sizes)."""
    d = open(path, "rb").read()
    if d[:6] != b"\x01\x00o65\x00":
        raise HccError(f"{path}: not an o65 file")
    if int.from_bytes(d[6:8], "little") & 0x6000:
        raise HccError(f"{path}: 32-bit sizes or paged relocation")
    h = [int.from_bytes(d[8 + 2 * i:10 + 2 * i], "little") for i in range(9)]
    tbase, tlen, dbase, dlen, bbase, blen, zbase, zlen, _ = h
    if tbase != 0x100 or dbase != tbase + tlen or bbase != dbase + dlen:
        raise HccError(f"{path}: text, data and bss not one after the other from $0100")
    p = 26
    while d[p]:
        p += d[p]
    p += 1
    img = d[p:p + tlen + dlen] + bytes(blen)
    p += tlen + dlen
    if int.from_bytes(d[p:p + 2], "little"):
        raise HccError(f"{path}: undefined references in the block")
    p += 2
    banks = []
    for base in (tbase, dbase):
        pos = base - 1
        while True:
            b = d[p]
            p += 1
            if b == 0:
                break
            if b == 255:
                pos += 254
                continue
            pos += b
            t = d[p]
            p += 1
            typ, seg = t & 0xE0, t & 0x1F
            if typ == 0x40:                 # HIGH: one more byte
                p += 1
            elif typ == 0xA0:               # SEG: two more bytes
                p += 2
            if seg not in (2, 3, 4, 5):
                raise HccError(f"{path}: a relocation to segment {seg}")
            if typ == 0xA0 and seg != 5:
                banks.append(pos)           # a bank byte
            elif typ == 0xC0 and seg != 5:
                banks.append(pos + 2)       # SEGADR: its bank byte
    return img, banks, {"text": tlen, "data": dlen, "bss": blen, "zp": (zbase, zlen)}


def ui_block(names, tmp):
    """The block for the hui.h names a program uses: ld65 links the shims (and the library
    routines they need) at $0100; the wrapper (vasm) puts it first in the program's text,
    fills its header and gives the C names their addresses. -> dict: wrapper (object),
    rt (the C side: __hui_fatal), banks (file), sizes."""
    import genhui
    ensure_ui()
    d = ui_dir()
    fns, vars_, _ = genhui.parse_table()
    fnames = {e["c"] for e in fns}
    vnames = {v["c"] for v in vars_}
    names = sorted(set(names))
    force = []
    for n in names:
        if n in fnames:
            force.append("hc_" + n)
        elif n in vnames:
            force.append(n)
        else:
            raise HccError(f"{n}: not a name of hui.h")
    rows = "ui_init" in names           # a program with controls: lists may call back
    if rows:
        force.append("hui_rowtramp")
    o65 = os.path.join(tmp, "hui.o65")
    lbl = os.path.join(tmp, "hui.lbl")
    mp = os.path.join(tmp, "hui.map")
    cmd = [cc65_tool("ld65"), "-C", os.path.join(d, "blob.cfg"), "-o", o65, "-Ln", lbl,
           "-m", mp]
    for f in force:
        cmd += ["--force-import", f]
    cmd += [os.path.join(d, "hdr.o"), os.path.join(d, "hui.lib")]
    run(cmd, "linking the controls library (ld65)")
    img, banks, sz = o65_block(o65)
    addr = {}
    for ln in open(lbl):
        m = re.match(r"^al ([0-9A-Fa-f]+) \.(\w+)", ln)
        if m:
            addr[m.group(2)] = int(m.group(1), 16)
    binf = os.path.join(tmp, "hui.bin")
    with open(binf, "wb") as f:
        f.write(img)
    bankf = os.path.join(tmp, "hui.banks")
    with open(bankf, "w") as f:
        f.write("".join("%04X\n" % b for b in banks))
    if any(b < 0x100 + 12 for b in banks):
        raise HccError("the block's header holds a bank byte")
    w = ["; the controls library's block for this program: GENERATED by hcc (tools/hzc.py)",
         '\tsection\t"DONTMERGE_text.blob","acrx"',
         "\tglobal\t___hui_blob",
         "___hui_blob:",
         "\tjmp\t!_start\t\t\t; +0 the program's entry: the C startup",
         "\tjml\t>___hui_fatal\t\t; +3 the block's failure messages",
         "\tdw\t<_hz_errno\t\t; +7 hz_errno"]
    if rows:
        w.append(f"\tjmp\t!___hui_blob+${addr['hui_rowtramp'] - 0x100:X}\t; +9 HUI_ROWCB")
    else:
        w.append("\trts\t\t\t\t; +9 HUI_ROWCB: no lists\n\tnop\n\tnop")
    w.append(f'\tincbin\t"{binf}",12')
    for n in names:
        sym = "hc_" + n if n in fnames else n
        if sym not in addr:
            raise HccError(f"{n}: ld65 did not place {sym}")
        w += [f"\tglobal\t_{n}", f"_{n}\tequ\t___hui_blob+${addr[sym] - 0x100:X}"]
    ws = os.path.join(tmp, "huiblock.s")
    with open(ws, "w") as f:
        f.write("\n".join(w) + "\n")
    wo = os.path.join(tmp, "huiblock.o")
    assemble(ws, wo, "large")
    sz["block"] = len(img)
    sz["names"] = len(names)
    return {"wrapper": wo, "rt": os.path.join(d, "huirt.o"), "banks": bankf, "sizes": sz}


# ---- linking -------------------------------------------------------------------------

def float_lib(model):
    return "ms4s" if model == "tiny" else "ms4"


def link(objs, out, model, float_=False, wend=0x7000, debug=False, mapfile=None,
         extra_libs=(), keep=None, ui=None):
    """Three raw links + mko65 -> out. Returns the sizes dict. ui: None, or the set of
    hui.h names the program uses (the controls library's block is linked first)."""
    ensure_lib(model)
    d = libdir(model)
    script = os.path.join(SDKC, "rt", "horizon-tiny.cmd" if model == "tiny" else "horizon.cmd")
    clib = "vcs" if model == "tiny" else "vc"
    name = os.path.basename(out)
    tmp = keep or tempfile.mkdtemp(prefix="hcc")
    os.makedirs(tmp, exist_ok=True)
    try:
        banks = None
        objs = list(objs)
        if ui:
            if model == "tiny":
                raise HccError(UI_TINY)
            blk = ui_block(ui, tmp)
            banks = blk["banks"]
        else:
            ui = None                   # --ui with no hui.h name used: no block

        def links(objs):
            imgs, maps = [], []
            for k, base in enumerate(BANKS):
                img = os.path.join(tmp, f"{name}.{k}.bin")
                mp = os.path.join(tmp, f"{name}.{k}.map")
                cmd = [tool("vlink"), "-b", "rawbin1", "-nowarn=22", "-Cvbcc", "-gc-all",
                       "-T", script, f"-DBASE={base:#x}", f"-DHZ_PAINT={1 if debug else 0}",
                       "-L" + d, "-L" + os.path.join(target_dir(), "lib"),
                       "-M" + mp, "-o", img, os.path.join(d, "crt0.o")]
                if model == "tiny":
                    cmd.append(f"-DWEND={wend:#x}")
                # the SDK's objects are linked as objects, not as a library: they replace
                # objects of vbcc's C library (stdio's hooks, _main.o, the runtime), and
                # vlink's -gc-all drops the functions a program does not use
                cmd += list(objs) + lib_objects(model) + list(extra_libs)
                if float_:
                    cmd.append("-l" + float_lib(model))
                cmd.append("-l" + clib)
                out_txt = run(cmd, "linking", filter_out=_link_messages)
                if k == 0 and out_txt.strip():
                    print(out_txt.rstrip(), file=sys.stderr)
                imgs.append(img)
                maps.append(mp)
            return imgs, maps

        if ui is not None:
            imgs, maps = links([blk["wrapper"], blk["rt"]] + objs)
            at = mko65.symbols(maps[0]).get("___hui_blob")
            if at is None:
                # the names that wanted it were only in code -gc-all dropped: no block
                ui, banks = None, None
            elif at != 0x100:
                raise HccError(f"{name}: the controls library's block is not at the start "
                               f"of the program's text (the linker script's *_text.blob)")
        if ui is None:
            imgs, maps = links(objs)
        try:
            sizes = mko65.convert(out, model, imgs, maps, banksfile=banks, wend=wend,
                                  name=name)
        except mko65.O65Error as e:
            raise HccError(str(e))
        if ui is not None:
            sizes["ui"] = blk
        if mapfile:
            shutil.copy(maps[0], mapfile)
        sizes["heap"] = heap_size(maps[0], model, wend)
        return sizes
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)


_UNDEF = re.compile(r"Reference to undefined symbol (\S+)\.")


def _link_messages(out):
    """vlink's messages, with the undefined symbols said in C terms."""
    res = []
    for ln in out.splitlines():
        m = _UNDEF.search(ln)
        if m:
            sym = m.group(1)
            c = sym[1:] if sym.startswith("_") else sym
            res.append(f"undefined: {c} (vlink: {ln.strip()})")
        elif ln.strip():
            res.append(ln)
    if any("___f" in r or "flt" in r.lower() for r in res if r.startswith("undefined")):
        res.append("(floating point: link with --float, see docs/c/reference.md)")
    return "\n".join(res)


def heap_size(mapfile, model, wend):
    syms = mko65.symbols(mapfile)
    h = syms.get("___heap")
    if h is None:
        return 0
    end = wend if model == "tiny" else 0xFFF0
    return max(0, end - (h & 0xFFFF))


MATHFUNCS = set("""acos asin atan atan2 ceil cos cosh exp fabs floor fmod frexp ldexp log
log10 modf pow sin sinh sqrt tan tanh strtod atof cbrt exp2 log2 hypot round trunc fmin fmax
copysign nan expm1 log1p erf erfc lgamma tgamma rint lrint lround nearbyint remainder
acosh asinh atanh scalbn logb ilogb fdim fma""".split())


def undefined_names(msg):
    """The C names of a failed link's undefined symbols."""
    return set(re.findall(r"undefined: (\S+)", msg))


def is_float_name(s):
    return "flt" in s or s.rstrip("f") in MATHFUNCS or s in MATHFUNCS


def needs_float(msg):
    """True when the undefined symbols of a failed link are all floating-point ones."""
    syms = re.findall(r"undefined: (\S+)", msg)
    return bool(syms) and all("flt" in s or s.rstrip("f") in MATHFUNCS or s in MATHFUNCS
                              for s in syms)


def size_report(out, model, s, wend):
    lines = [f"{out}: {s['file']:,} bytes on the card, {s['relocs']} bank relocations"]
    if model == "tiny":
        lines.append(f"  code bank: code {s['text']:,} + data image {s['wdata']:,} "
                     f"(of 65,280)")
        lines.append(f"  window:    data {s['wdata']:,} + bss {s['wbss']:,} = "
                     f"{s['window_data']:,} of {s['window_room']:,}; heap {s['heap']:,}; "
                     f"stack {0x7F80 - wend:,} at least")
    else:
        lines.append(f"  code bank: code+constants {s['text']:,} + data {s['data']:,} + "
                     f"bss {s['bss']:,} = {s['code']:,} of 65,280; heap {s['heap']:,}")
        lines.append("  window:    stack about 32,000 (from $7F7F down to $0100)")
    if "ui" in s:
        u = s["ui"]["sizes"]
        lines.append(f"  controls library block: {u['block']:,} bytes (code+constants "
                     f"{u['text']:,} + data {u['data']:,} + bss {u['bss']:,}) for "
                     f"{u['names']} hui.h names; direct page $50+{u['zp'][1]}")
    return "\n".join(lines)
