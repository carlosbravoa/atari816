#!/usr/bin/env python3
"""gensys.py - the C binding of Horizon's syscalls, generated so it cannot drift.

    gensys.py [--horizon DIR]           write include/hzsys.h
    gensys.py --check [--horizon DIR]   fail (exit 1) if include/hzsys.h is not what
                                        horizon.inc + ABI.md + syscalls.tab give now, or
                                        if they disagree (count, numbers, names)
    gensys.py --stubs DIR [--large]     write the syscall stubs (ca65, one file a
                                        syscall; the library build does this)

Sources:
  HORIZON/user/horizon.inc  the SYS_* numbers and every other constant (read with
                            sdk/tools/abicheck.py's parser)
  HORIZON/ABI.md            the syscall table: which numbers exist and their names
  tools/syscalls.tab        the C signature of each syscall (register use, result)

include/hzsys.h holds: every constant of horizon.inc (error codes and open modes with an
HZ_ prefix: they would clash with errno.h), the SYS_ numbers, and one prototype with a
doc comment per syscall. The stubs (one small function per syscall, no self-modifying
code) are made from the header's markers, so the library can be built without the
Horizon tree.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
HEADER = os.path.join(SDKC, "include", "hzsys.h")
TABLE = os.path.join(HERE, "syscalls.tab")
sys.path.insert(0, os.path.join(SDKC, "..", "tools"))

# horizon.inc names that would clash with the C library: prefixed with HZ_
PREFIXED = re.compile(r"^(E[A-Z_]*|O_(READ|RDWR|CREATE|APPEND))$")
REGS = ("A", "X", "Y", "A.lo", "A.hi", "X.lo", "X.hi", "Y.lo", "Y.hi", "XY", "XY32", "AX32")
RETS = ("void", "ok", "int", "unsigned", "long", "noreturn")


class GenError(Exception):
    pass


def default_horizon():
    return os.environ.get("HORIZON") or os.path.join(SDKC, "..", "..", "horizon")


def parse_table(path=TABLE):
    entries = []
    for no, ln in enumerate(open(path, encoding="utf-8"), 1):
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        parts = [p.strip() for p in ln.rstrip("\n").split("|", 4)]
        if len(parts) < 5:
            raise GenError(f"syscalls.tab:{no}: needs 5 fields separated by |")
        name, ret, params_txt, outs, doc = parts
        abi, _, cname = name.partition(":")
        cname = cname or abi
        if ret not in RETS:
            raise GenError(f"syscalls.tab:{no}: unknown result kind {ret}")
        params, consts = [], []
        for p in [x.strip() for x in params_txt.split(",") if x.strip()]:
            if p.startswith("=") or p.startswith("+"):
                m = re.fullmatch(r"([=+])([AXY]):(0x[0-9A-Fa-f]+|\d+)", p)
                if not m:
                    raise GenError(f"syscalls.tab:{no}: bad constant {p}")
                consts.append((m.group(1), m.group(2), int(m.group(3), 0)))
                continue
            m = re.fullmatch(r"(.+?)\s*([A-Za-z_]\w*)\s*:\s*(\S+)", p)
            if not m or m.group(3) not in REGS:
                raise GenError(f"syscalls.tab:{no}: bad parameter '{p}'")
            ctype, pname, reg = m.group(1).strip(), m.group(2), m.group(3)
            params.append((ctype, pname, reg))
        out = set(outs.split())
        if out - {"x", "y"}:
            raise GenError(f"syscalls.tab:{no}: outs are x and/or y")
        entries.append({"abi": abi, "c": "hz_" + cname, "ret": ret, "params": params,
                        "consts": consts, "outs": out, "doc": doc, "line": no})
    return entries


def horizon_data(hz):
    import abicheck
    inc_path = os.path.join(hz, "user", "horizon.inc")
    abi_path = os.path.join(hz, "ABI.md")
    for p in (inc_path, abi_path):
        if not os.path.exists(p):
            raise GenError(f"{p} not found (set HORIZON or --horizon)")
    inc = abicheck.inc_constants(inc_path)
    abi = abicheck.abi_table(abi_path)
    order = [ln.split("=")[0].strip() for ln in open(inc_path, encoding="latin-1")
             if re.match(r"\s*[A-Z][A-Z0-9_]*\s*=", ln)]
    return inc, abi, order


def check_consistency(entries, inc, abi):
    """Every ABI.md syscall has exactly one main entry, numbers and names agree."""
    errs = []
    sysc = {v: k for k, v in inc.items() if k.startswith("SYS_")}
    byname = {v: k for k, v in abi.items()}
    mains = [e for e in entries if e["c"] == "hz_" + e["abi"]]
    seen = {}
    for e in mains:
        if e["abi"] in seen:
            errs.append(f"syscalls.tab:{e['line']}: {e['abi']} twice")
        seen[e["abi"]] = e
    for e in entries:
        if e["abi"] not in byname:
            errs.append(f"syscalls.tab:{e['line']}: {e['abi']} is not in ABI.md's syscall table")
    for n, name in sorted(abi.items()):
        if name not in seen:
            errs.append(f"ABI.md: ${n:02X} {name} has no line in syscalls.tab")
        if n not in sysc:
            errs.append(f"ABI.md: ${n:02X} {name} has no SYS_ constant in horizon.inc")
    for n, c in sorted(sysc.items()):
        if n not in abi:
            errs.append(f"horizon.inc: {c} = ${n:02X} is not in ABI.md's syscall table")
    return errs


def ctype_size(ctype):
    """a parameter's bytes on cc816's stack (a pointer: 2, an offset in the code bank,
    unless it is __far)"""
    t = ctype.replace("const", "").strip()
    if "*" in t:
        return 2 if "__far" not in t else 4
    if "long" in t:
        return 4
    return 2


def c_value(v):
    return str(v) if v < 10 else f"0x{v:X}"


def make_header(entries, inc, abi, order):
    sysc = {v: k for k, v in inc.items() if k.startswith("SYS_")}
    byname = {v: k for k, v in abi.items()}
    o = []
    o.append("/* hzsys.h - Horizon's constants and syscalls for C. GENERATED by tools/gensys.py")
    o.append(" * from horizon.inc, ABI.md and tools/syscalls.tab: do not edit (make -C sdk/c gen).")
    o.append(" * Included by horizon.h, which defines the parameter blocks (hz_io, hz_winopen, ...).")
    o.append(" *")
    o.append(f" * {len(abi)} syscalls, {sum(1 for e in entries)} C functions.")
    o.append(" * Each function: carry clear -> hz_errno = 0 and the result; carry set -> hz_errno =")
    o.append(" * the Horizon error code (HZ_E*) and -1 ($FFFF for unsigned results). */")
    o.append("#ifndef HZSYS_H")
    o.append("#define HZSYS_H")
    o.append("")
    o.append("/* ---- constants (horizon.inc) */")
    done = set()
    for name in order:
        if name in done or name not in inc or name.startswith("SYS_"):
            continue
        done.add(name)
        cname = ("HZ_" + name) if PREFIXED.match(name) else name
        o.append(f"#define {cname:<16} {c_value(inc[name])}")
    o.append("")
    o.append("/* ---- syscall numbers (horizon.inc): for hz_syscall() */")
    for n in sorted(sysc):
        o.append(f"#define {sysc[n]:<16} 0x{n:02X}")
    o.append(f"#define HZ_NSYSCALLS     {len(abi)}")
    o.append("")
    o.append("/* ---- the syscalls */")
    for e in entries:
        n = byname[e["abi"]]
        ctype = {"void": "void", "ok": "int", "int": "int", "unsigned": "unsigned",
                 "long": "long", "noreturn": "void"}[e["ret"]]
        params = ", ".join(f"{t}{'' if t.endswith('*') else ' '}{p}" for t, p, _ in e["params"]) or "void"
        regs = ", ".join(f"{p}: {r}" for _, p, r in e["params"])
        extra = ", ".join(f"{r} {'=' if k == '=' else '|='} ${v:X}" for k, r, v in e["consts"])
        regs = ", ".join(x for x in (regs, extra) if x)
        outs = " ".join(f"hz_{x}" for x in sorted(e["outs"]))
        o.append(f"/** {e['abi']} ({sysc[n]}, ${n:02X}): {e['doc']}")
        o.append(f" *  [{regs or 'no arguments'}{'; out: ' + outs if outs else ''}] */")
        o.append(f"{ctype} {e['c']}({params});")
    o.append("")
    o.append("#endif")
    return "\n".join(o) + "\n"


def header_markers(path=HEADER):
    """abi name -> (SYS_ name, number), from the generated header."""
    out = {}
    for ln in open(path, encoding="utf-8"):
        m = re.match(r"/\*\* (\w+) \((SYS_\w+), \$([0-9A-F]{2})\)", ln)
        if m:
            out[m.group(1)] = (m.group(2), int(m.group(3), 16))
    return out


# ---- the stubs (ca65): JSR, every argument on the stack from 3,s (pushed last first; a
# pointer is 2 bytes, an offset in the code bank, unless it is __far), the result in A
# (32 bits: A low, X high). A near pointer for a syscall is X = offset, Y = the code bank
# (__cbank). One file a syscall: ld65 links only the ones a program uses.

def stub816(e, n, large=False):
    """large: the large code model (hcc --code large): JSL/RTL, the arguments from 4,s"""
    name = "_" + e["c"]
    L = [f"; {e['c']}: GENERATED by tools/gensys.py from tools/syscalls.tab - do not edit",
         "\t.p816", "\t.smart\t-", "\t.a16", "\t.i16", "\t.importzp\t__cbank, __h0",
         "\t.import\t___hz_fail, _hz_errno" + (", _hz_x" if "x" in e["outs"] else "") +
         (", _hz_y" if "y" in e["outs"] else ""),
         f"\t.export\t{name}", '\t.segment\t"CODE"', f"{name}:"]
    locs = []
    off = 4 if large else 3
    for t, p, r in e["params"]:
        size = ctype_size(t)
        locs.append((off, size, t))
        off += size

    def word(loc, high=False):
        return f"{loc[0] + (2 if high else 0)},s"

    contrib = {"A": [], "X": [], "Y": []}
    for (t, p, r), loc in zip(e["params"], locs):
        if r in ("A", "X", "Y"):
            contrib[r].append(("w", loc))
        elif r.endswith(".lo") or r.endswith(".hi"):
            contrib[r[0]].append((r[2:], loc))
        elif r == "XY" and loc[1] == 2:
            contrib["X"].append(("w", loc))
            contrib["Y"].append(("cbank", None))
        elif r in ("XY", "XY32"):
            contrib["X"].append(("w", loc))
            contrib["Y"].append(("w2", loc))
        elif r == "AX32":
            contrib["A"].append(("w", loc))
            contrib["X"].append(("w2", loc))
    for k, r, v in e["consts"]:
        contrib[r].append(("set" if k == "=" else "or", v))

    def value(items):
        kinds = {k: v for k, v in items}
        code = []
        if "w" in kinds:
            code.append(f"\tlda\t{word(kinds['w'])}")
        elif "w2" in kinds:
            code.append(f"\tlda\t{word(kinds['w2'], True)}")
        elif "cbank" in kinds:
            code.append("\tlda\t__cbank")
        elif "set" in kinds:
            code.append(f"\tlda\t#${kinds['set']:X}")
        elif "hi" in kinds:
            code += [f"\tlda\t{word(kinds['hi'])}", "\txba", "\tand\t#$FF00"]
            if "lo" in kinds:
                code += ["\tsta\t__h0", f"\tlda\t{word(kinds['lo'])}", "\tand\t#$00FF",
                         "\tora\t__h0"]
        elif "lo" in kinds:
            code += [f"\tlda\t{word(kinds['lo'])}", "\tand\t#$00FF"]
        if "or" in kinds:
            code.append(f"\tora\t#${kinds['or']:X}")
        return code

    for reg in ("Y", "X", "A"):
        items = contrib[reg]
        if not items:
            continue
        kinds = [k for k, _ in items]
        if reg != "A" and kinds == ["cbank"]:
            L.append(f"\tld{reg.lower()}\t__cbank")
            continue
        L += value(items)
        if reg != "A":
            L.append(f"\tta{reg.lower()}")
    L.append(f"\tcop\t#${n:02X}")
    if e["ret"] == "noreturn":
        L.append(f"\tbra\t{name}")
        return "\n".join(L) + "\n"
    if "x" in e["outs"]:
        L.append("\tstx\t_hz_x")
    if "y" in e["outs"]:
        L.append("\tsty\t_hz_y")
    L.append("\tbcs\t@fail")
    L.append("\tstz\t_hz_errno")
    if e["ret"] in ("ok", "void"):
        L.append("\tlda\t#0")
    L.append("\trtl" if large else "\trts")
    L.append("@fail:\tjmp\t___hz_fail")
    return "\n".join(L) + "\n"


def write_stubs816(outdir, header=HEADER, table=TABLE, large=False):
    """the stubs: one ca65 file a syscall, plus hzsys.s (hz_errno, hz_x, hz_y, the
    failure path, hz_syscall). -> the files written. large: for the large code model"""
    ret = "\trtl" if large else "\trts"
    a0 = 1 if large else 0
    entries = parse_table(table)
    marks = header_markers(header)
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        if f.endswith(".s"):
            os.remove(os.path.join(outdir, f))
    files = []
    for e in entries:
        if e["abi"] not in marks:
            raise GenError(f"{header} has no {e['abi']}: run make -C sdk/c gen")
        p = os.path.join(outdir, e["c"] + ".s")
        with open(p, "w") as f:
            f.write(stub816(e, marks[e["abi"]][1], large))
        files.append(p)
    o = ["; hzsys.s - what cc816's syscall stubs share. GENERATED by tools/gensys.py.",
         "\t.p816", "\t.smart\t-", "\t.a16", "\t.i16", "\t.importzp\t__h0",
         "\t.export\t___hz_fail, _hz_errno, _hz_x, _hz_y, _hz_syscall",
         '\t.segment\t"CODE"',
         "; carry set: hz_errno = A (the error code), A = X = -1",
         "___hz_fail:",
         "\tsta\t_hz_errno",
         "\tlda\t#$FFFF",
         "\ttax",
         ret,
         "; unsigned hz_syscall(unsigned n, unsigned a, unsigned x, unsigned y): any syscall by",
         "; number, through a table of COP #n; RTS",
         "_hz_syscall:",
         f"\tlda\t{3 + a0},s",
         "\tand\t#$00FF",
         "\tsta\t__h0",
         "\tasl\ta",
         "\tadc\t__h0",
         "\tadc\t#tab - 1",
         "\tsta\t__h0",
         "\tpea\tback - 1",
         "\tpei\t(__h0)",
         f"\tlda\t{13 + a0},s",
         "\ttay",
         f"\tlda\t{11 + a0},s",
         "\ttax",
         f"\tlda\t{9 + a0},s",
         "\trts",
         "back:\tstx\t_hz_x",
         "\tsty\t_hz_y",
         "\tbcs\t___hz_fail",
         "\tstz\t_hz_errno",
         ret,
         "tab:"]
    for k in range(256):
        o.append(f"\tcop\t#${k:02X}\n\trts")
    o += ["", '\t.segment\t"BSS"', "_hz_errno:\t.res\t2", "_hz_x:\t.res\t2",
          "_hz_y:\t.res\t2", ""]
    p = os.path.join(outdir, "hzsys.s")
    with open(p, "w") as f:
        f.write("\n".join(o))
    files.append(p)
    return files


def main():
    a = sys.argv[1:]
    hz = default_horizon()
    check = False
    stubs = None
    large = False
    i = 0
    while i < len(a):
        if a[i] == "--horizon":
            hz = a[i + 1]; i += 2
        elif a[i] == "--check":
            check = True; i += 1
        elif a[i] == "--stubs":
            stubs = a[i + 1]; i += 2
        elif a[i] == "--large":
            large = True; i += 1
        else:
            sys.exit(__doc__)
    try:
        if stubs:
            write_stubs816(stubs, large=large)
            return 0
        entries = parse_table()
        inc, abi, order = horizon_data(hz)
        errs = check_consistency(entries, inc, abi)
        text = make_header(entries, inc, abi, order)
        if check:
            cur = open(HEADER, encoding="utf-8").read() if os.path.exists(HEADER) else ""
            if cur != text:
                errs.append("include/hzsys.h is not what horizon.inc, ABI.md and syscalls.tab "
                            "give now: run make -C sdk/c gen (and check the difference)")
            marks = header_markers() if os.path.exists(HEADER) else {}
            sysn = {k: v for k, v in inc.items() if k.startswith("SYS_")}
            for ab, (c, n) in marks.items():
                if sysn.get(c) != n:
                    want = sysn.get(c)
                    errs.append(f"include/hzsys.h: {ab} is {c} ${n:02X}, horizon.inc says "
                                + (f"${want:02X}" if want is not None else "nothing"))
            mains = {e["abi"] for e in entries if e["c"] == "hz_" + e["abi"]}
            if len(mains) != len(abi) or len(abi) != len(sysn):
                errs.append(f"counts: {len(abi)} syscalls in ABI.md, {len(sysn)} SYS_ constants "
                            f"in horizon.inc, {len(mains)} in syscalls.tab")
            for x in errs:
                print("FAIL:", x)
            print(f"gensys: {len(abi)} syscalls in ABI.md, {len(sysn)} SYS_ constants, "
                  f"{len(entries)} C functions: " + ("FAILED" if errs else "OK"))
            return 1 if errs else 0
        if errs:
            for x in errs:
                print("FAIL:", x)
            return 1
        with open(HEADER, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"gensys: wrote {HEADER} ({len(entries)} functions)")
        return 0
    except GenError as e:
        print("gensys:", e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
