#!/usr/bin/env python3
"""gensys.py - the C binding of Horizon's syscalls, generated so it cannot drift.

    gensys.py [--horizon DIR]           write include/hzsys.h
    gensys.py --check [--horizon DIR]   fail (exit 1) if include/hzsys.h is not what
                                        horizon.inc + ABI.md + syscalls.tab give now, or
                                        if they disagree (count, numbers, names)
    gensys.py --stubs FILE --model M    write the assembly stubs (the library build does)

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


def ctype_size(ctype, model):
    t = ctype.replace("const", "").strip()
    if "*" in t:
        return 2 if model == "tiny" and "__far" not in t else 4
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


def stub(e, n, model):
    """The assembly of one syscall function (vasm oldstyle)."""
    name = "_" + e["c"]
    L = [f'\tsection\t"DONTMERGE_text.far.{e["c"]}","acrx"', f"\tglobal\t{name}", f"{name}:"]
    # where each parameter is: the first in A (A/X when 32-bit), the others on the stack
    # above the 3-byte return address
    locs = []
    off = 4
    for k, (t, p, r) in enumerate(e["params"]):
        size = ctype_size(t, model)
        if k == 0:
            locs.append(("r0", size))
        else:
            locs.append((off, size))
            off += size
    if e["params"]:
        L.append("\tsta\tr0")
        if locs[0][1] == 4:
            L.append("\tstx\tr1")

    def word(loc, high=False):
        if loc[0] == "r0":
            return "r1" if high else "r0"
        return f"{loc[0] + (2 if high else 0)},s"

    contrib = {"A": [], "X": [], "Y": []}
    for (t, p, r), loc in zip(e["params"], locs):
        if r in ("A", "X", "Y"):
            contrib[r].append(("w", loc))
        elif r.endswith(".lo") or r.endswith(".hi"):
            contrib[r[0]].append((r[2:], loc))
        elif r == "XY" and model == "tiny" and "__far" not in t:
            contrib["X"].append(("w", loc))
            contrib["Y"].append(("zero", None))
        elif r in ("XY", "XY32"):
            contrib["X"].append(("w", loc))
            contrib["Y"].append(("w2", loc))
        elif r == "AX32":
            contrib["A"].append(("w", loc))
            contrib["X"].append(("w2", loc))
    for k, r, v in e["consts"]:
        contrib[r].append(("set" if k == "=" else "or", v))

    def value(items):
        """Code leaving the register's value in A."""
        kinds = {k: v for k, v in items}
        code = []
        if "w" in kinds:
            code.append(f"\tlda\t{word(kinds['w'])}")
        elif "w2" in kinds:
            code.append(f"\tlda\t{word(kinds['w2'], True)}")
        elif "set" in kinds:
            code.append(f"\tlda\t#${kinds['set']:X}")
        elif "hi" in kinds:
            code += [f"\tlda\t{word(kinds['hi'])}", "\txba", "\tand\t#$FF00"]
            if "lo" in kinds:
                code += ["\tsta\tr2", f"\tlda\t{word(kinds['lo'])}", "\tand\t#$00FF",
                         "\tora\tr2"]
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
        if reg != "A" and kinds == ["zero"]:
            L.append(f"\tld{reg.lower()}\t#0")
            continue
        if reg != "A" and len(items) == 1 and items[0][0] in ("w", "w2") and items[0][1][0] == "r0":
            L.append(f"\tld{reg.lower()}\t{word(items[0][1], items[0][0] == 'w2')}")
            continue
        L += value(items)
        if reg != "A":
            L.append(f"\tta{reg.lower()}")
    L.append(f"\tcop\t#${n:02X}")
    if e["ret"] == "noreturn":
        L.append(f"\tbra\t{name}")
        return "\n".join(L) + "\n"
    if "x" in e["outs"]:
        L.append("\tstx\t!_hz_x")
    if "y" in e["outs"]:
        L.append("\tsty\t!_hz_y")
    L.append("\tbcs\t.fail")
    if e["ret"] in ("ok", "void"):
        L += ["\tlda\t#0", "\tsta\t>_hz_errno"]
    else:
        L += ["\ttay", "\tlda\t#0", "\tsta\t>_hz_errno", "\ttya"]
    L.append("\trtl")
    L.append(".fail:\tjml\t>___hz_fail")
    return "\n".join(L) + "\n"


def write_stubs(path, model, header=HEADER, table=TABLE):
    entries = parse_table(table)
    marks = header_markers(header)
    o = [f"; hzsys.s - Horizon syscall stubs, {model} model. GENERATED by tools/gensys.py.",
         "; One function per syscall: the C arguments into A, X, Y, COP #n, the result;",
         "; carry set: hz_errno = A and -1 (___hz_fail).", "",
         "\tzpage\tr0,r1,r2", "\ta16", "\tx16", ""]
    for e in entries:
        if e["abi"] not in marks:
            raise GenError(f"{header} has no {e['abi']}: run make -C sdk/c gen")
        o.append(stub(e, marks[e["abi"]][1], model))
    # hz_syscall(n, a, x, y): any syscall by number, through a table of "COP #n; RTS"
    o += ['\tsection\t"DONTMERGE_text.far.hz_syscall","acrx"',
          "\tglobal\t_hz_syscall",
          "_hz_syscall:",
          "\tand\t#$00FF",
          "\tsta\tr0",
          "\tasl\ta",
          "\tadc\tr0",
          "\tadc\t#<(.tab-1)",
          "\tsta\tr0",
          "\tpea\t#<(.back-1)",
          "\tpei\t(r0)",
          "\tlda\t12,s",
          "\ttay",
          "\tlda\t10,s",
          "\ttax",
          "\tlda\t8,s",
          "\trts",
          ".back:\tstx\t!_hz_x",
          "\tsty\t!_hz_y",
          "\tbcs\t.fail",
          "\ttay",
          "\tlda\t#0",
          "\tsta\t>_hz_errno",
          "\ttya",
          "\trtl",
          ".fail:\tjml\t>___hz_fail",
          ".tab:"]
    for k in range(256):
        o.append(f"\tcop\t#${k:02X}\n\trts")
    o.append("")
    o += ['\tsection\t"DONTMERGE_text.far.hzfail","acrx"',
          "\tglobal\t___hz_fail",
          "___hz_fail:",
          "\tsta\t>_hz_errno",
          "\tlda\t#$FFFF",
          "\ttax",
          "\trtl",
          "",
          '\tsection\t"DONTMERGE_bss.near.hzsys","aurw"',
          "\tglobal\t_hz_errno", "\tglobal\t_hz_x", "\tglobal\t_hz_y",
          "_hz_errno:\treserve\t2", "_hz_x:\treserve\t2", "_hz_y:\treserve\t2", ""]
    with open(path, "w") as f:
        f.write("\n".join(o))


def main():
    a = sys.argv[1:]
    hz = default_horizon()
    check = False
    stubs = model = None
    i = 0
    while i < len(a):
        if a[i] == "--horizon":
            hz = a[i + 1]; i += 2
        elif a[i] == "--check":
            check = True; i += 1
        elif a[i] == "--stubs":
            stubs = a[i + 1]; i += 2
        elif a[i] == "--model":
            model = a[i + 1]; i += 2
        else:
            sys.exit(__doc__)
    try:
        if stubs:
            write_stubs(stubs, model or "large")
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
