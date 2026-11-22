#!/usr/bin/env python3
"""genhui.py - the C binding of Horizon's controls library, generated so it cannot drift.

    genhui.py [--horizon DIR]            write include/huigen.h
    genhui.py --check [--horizon DIR]    fail (exit 1) when a public routine or variable of
                                         ui.inc or of ulib (horizon.inc) has no entry in
                                         ui/hui.tab (bound, or "unbound" with the reason),
                                         when hui.tab names something the library does not
                                         have, when include/huigen.h is not what the sources
                                         give now (constants, prototypes), or when hui.h's
                                         structures disagree with ui.inc's offsets (a
                                         compile of hui.h: its static asserts)
    genhui.py --shims DIR [--horizon D]  write the JSL->JSR shims (ca65, one file a routine:
                                         ld65 then links only the ones a program uses);
                                         hzc.build_ui does this (vbcc)
    genhui.py --shims816 DIR             write cc816's shims (ca65, one file a routine:
                                         ld65 links them, the library and ulib straight
                                         into the program); tools/hui816.py does this

Sources:
  HORIZON/user/ui.inc       the controls library's constants, offsets and .global names
  HORIZON/user/icons.inc    the ICO_* icon numbers (ui_prog, ui_ficon)
  HORIZON/user/horizon.inc  ulib's .global names (and the constants hzsys.h already has)
  ui/hui.tab                the C signature of each routine: which register carries which
                            argument, what comes back, carry = error (its header explains)
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
HEADER = os.path.join(SDKC, "include", "huigen.h")
TABLE = os.path.join(SDKC, "ui", "hui.tab")
UILIB = os.path.join(SDKC, "ui", "lib")
sys.path.insert(0, os.path.join(SDKC, "..", "tools"))

REGS = ("A", "X", "Y")
ZPDEST = ("ui_win", "ui_x", "ui_y", "ui_w", "ui_h", "ui_font", "ui_c2")
KINDS = ("val", "ptr", "str", "buf", "far", "long")
RETS = ("void", "A", "X", "AX", "Xptr", "ok", "err", "Aerr", "bool", "xoff")
WIDE_TYPES = ("ui_cpfn", "ui_rowfn")       # 32-bit typedefs (function pointers)
NSLOTS = 3                                 # str.s: scratch buffers


class GenError(Exception):
    pass


def default_horizon():
    return os.environ.get("HORIZON") or os.path.join(SDKC, "..", "..", "horizon")


# ---- hui.tab ---------------------------------------------------------------------------

def parse_proto(p, where):
    m = re.match(r"^(.*?)\b(\w+)\s*\((.*)\)\s*$", p)
    if not m:
        raise GenError(f"{where}: not a prototype: {p}")
    ret, name, args = m.group(1).strip(), m.group(2), m.group(3).strip()
    params = []
    if args and args != "void":
        for a in args.split(","):
            a = a.strip()
            pm = re.match(r"^(.*?)(\w+)$", a)
            if not pm:
                raise GenError(f"{where}: parameter without a name: {a}")
            ctype, pname = pm.group(1).strip(), pm.group(2)
            wide = "*" in ctype or "long" in ctype.split() or ctype in WIDE_TYPES
            params.append({"type": ctype, "name": pname, "size": 4 if wide else 2})
    return ret, name, params


def parse_table(path=TABLE):
    fns, vars_, unbound = [], [], {}
    global STRUCTS
    STRUCTS = []
    cur = None
    for no, ln in enumerate(open(path, encoding="utf-8"), 1):
        s = ln.rstrip("\n")
        if not s.strip() or s.lstrip().startswith("#"):
            continue
        key, _, rest = s.partition(" ")
        rest = rest.strip()
        where = f"hui.tab:{no}"
        if key == "fn":
            ret, name, params = parse_proto(rest, where)
            cur = {"proto": rest, "ret_c": ret, "c": name, "params": params, "asm": name,
                   "in": {}, "set": [], "out": [], "ret": "void", "flags": set(), "doc": [],
                   "line": no}
            fns.append(cur)
        elif key == "var":
            m = re.match(r"^(.*?)(\w+)(\[\d+\])?$", rest)
            if not m:
                raise GenError(f"{where}: var needs a C declaration")
            cur = {"decl": rest, "c": m.group(2), "doc": [], "line": no}
            vars_.append(cur)
        elif key == "struct":
            n, _, base = rest.partition(" ")
            cur = {"struct": n, "base": base.strip() or None, "fields": [], "size": None,
                   "doc": [], "line": no}
            STRUCTS.append(cur)
        elif key in ("field", "size") and cur is not None and "struct" in cur:
            if key == "size":
                cur["size"] = rest
            else:
                parts = [x.strip() for x in rest.split("|")]
                if len(parts) != 3:
                    raise GenError(f"{where}: field OFFSET | declaration | comment")
                fm = re.match(r"^(.*?)(\w+)(?:\[(\w+)\])?$", parts[1])
                if not fm:
                    raise GenError(f"{where}: field: not a declaration: {parts[1]}")
                cur["fields"].append({"off": parts[0], "type": fm.group(1).strip(),
                                      "name": fm.group(2), "n": fm.group(3),
                                      "decl": parts[1], "doc": parts[2], "line": no})
        elif key == "unbound":
            n, _, why = rest.partition(" ")
            if not why.strip():
                raise GenError(f"{where}: unbound {n} needs the reason")
            unbound[n] = why.strip()
            cur = None
        elif key == "doc":
            if cur is None:
                raise GenError(f"{where}: doc without an entry")
            cur["doc"].append(rest)
        elif cur is None or "proto" not in cur:
            raise GenError(f"{where}: '{key}' outside a fn entry")
        elif key == "asm":
            cur["asm"] = rest
        elif key == "ret":
            if rest not in RETS:
                raise GenError(f"{where}: unknown ret {rest}")
            cur["ret"] = rest
        elif key == "flags":
            cur["flags"] |= set(rest.split())
        elif key in ("in", "set", "out"):
            for item in rest.split():
                p, _, spec = item.partition("=")
                dest, _, kind = spec.partition(":")
                dests = dest.split(",")
                if key == "set":
                    cur["set"].append((p, spec))
                    continue
                if key == "out":
                    kind = kind or "val"
                    if dest not in ("A", "X") or kind not in ("val", "ptr"):
                        raise GenError(f"{where}: out {item}: SRC is A or X, kind val or ptr")
                    cur["out"].append((p, dest, kind))
                    continue
                kind = kind or "val"
                if kind not in KINDS:
                    raise GenError(f"{where}: unknown kind {kind}")
                for d in dests:
                    if d not in REGS + ZPDEST:
                        raise GenError(f"{where}: unknown destination {d}")
                if (len(dests) == 2) != (kind in ("far", "long")):
                    raise GenError(f"{where}: {item}: far and long take two destinations")
                cur["in"][p] = (dests, kind)
        else:
            raise GenError(f"{where}: unknown key {key}")
    for e in fns:
        names = [p["name"] for p in e["params"]]
        for p in e["params"]:
            if p["name"] not in e["in"] and p["name"] not in [o[0] for o in e["out"]]:
                raise GenError(f"hui.tab:{e['line']}: {e['c']}: parameter {p['name']} is "
                               f"neither in nor out")
            k = e["in"].get(p["name"], (None, None))[1]
            if k in ("ptr", "str", "buf", "far", "long") and p["size"] != 4:
                raise GenError(f"hui.tab:{e['line']}: {e['c']}: {p['name']} ({k}) must be "
                               f"a pointer or a long")
        for n in list(e["in"]) + [o[0] for o in e["out"]]:
            if n not in names:
                raise GenError(f"hui.tab:{e['line']}: {e['c']}: no parameter {n}")
        if sum(1 for d, k in e["in"].values() if k in ("str", "buf")) > NSLOTS:
            raise GenError(f"hui.tab:{e['line']}: more than {NSLOTS} str/buf parameters")
    return fns, vars_, unbound


def c_names(path=TABLE):
    """Every C name hui.tab defines (functions and variables): hcc's 'uses hui' test."""
    fns, vars_, _ = parse_table(path)
    return [e["c"] for e in fns] + [v["c"] for v in vars_]


# ---- the Horizon sources ---------------------------------------------------------------

def inc_globals(path, start=None, stop=None):
    """The names of .global / .globalzp lines (between the start and stop markers)."""
    out, on = [], start is None
    for ln in open(path, encoding="latin-1"):
        if start and start in ln:
            on = True
        if stop and stop in ln:
            on = False
        if not on:
            continue
        m = re.match(r"^\s*\.global(?:zp)?\s+([^;]+)", ln)
        if m:
            out += [n.strip() for n in m.group(1).split(",") if n.strip()]
    return out


def inc_order(path):
    return [ln.split("=")[0].strip() for ln in open(path, encoding="latin-1")
            if re.match(r"\s*[A-Z][A-Z0-9_]*\s*=", ln)]


def horizon_data(hz):
    import abicheck
    user = os.path.join(hz, "user")
    paths = {k: os.path.join(user, f) for k, f in
             (("ui", "ui.inc"), ("icons", "icons.inc"), ("horizon", "horizon.inc"))}
    for p in paths.values():
        if not os.path.exists(p):
            raise GenError(f"{p} not found (set HORIZON or --horizon)")
    d = {}
    d["uic"] = abicheck.inc_constants(paths["ui"])
    d["uiorder"] = inc_order(paths["ui"])
    d["ico"] = abicheck.inc_constants(paths["icons"])
    d["icoorder"] = inc_order(paths["icons"])
    d["hzc"] = abicheck.inc_constants(paths["horizon"])
    d["uiglobals"] = inc_globals(paths["ui"], stop="(internal: shared")
    d["ulibglobals"] = inc_globals(paths["horizon"], start="user library")
    return d


def helpers():
    """hui_* routines of ui/lib/*.s (the SDK's own)."""
    out = set()
    for f in os.listdir(UILIB):
        if f.endswith(".s"):
            for ln in open(os.path.join(UILIB, f), encoding="latin-1"):
                m = re.match(r"^(hui_\w+):", ln)
                if m:
                    out.add(m.group(1))
    return out


def check_coverage(fns, vars_, unbound, d):
    errs = []
    public = d["uiglobals"] + d["ulibglobals"]
    bound = {e["asm"] for e in fns} | {v["c"] for v in vars_}
    for n in public:
        if n not in bound and n not in unbound:
            errs.append(f"{n}: a public name of the library with no binding in ui/hui.tab "
                        f"(add an fn / var entry, or 'unbound {n} <why>')")
    hl = helpers()
    for e in fns:
        if e["asm"] not in public and e["asm"] not in hl:
            errs.append(f"hui.tab:{e['line']}: {e['c']} calls {e['asm']}, which neither the "
                        f"library nor ui/lib has")
    for v in vars_:
        if v["c"] not in public:
            errs.append(f"hui.tab:{v['line']}: variable {v['c']} is not a public name of the "
                        f"library")
    for n in unbound:
        if n not in public:
            errs.append(f"hui.tab: 'unbound {n}': not a public name of the library")
    for n, v in d["uic"].items():
        if n in d["hzc"] and d["hzc"][n] != v:
            errs.append(f"{n}: ui.inc says {v}, horizon.inc {d['hzc'][n]}")
    return errs


# ---- huigen.h ----------------------------------------------------------------------------

STRUCTS = []


def ctype_size(t, sizes, where):
    if "*" in t:
        return 2 if "__near" in t else 4
    w = t.replace("const", "").replace("volatile", "").split()
    if w and w[-1] == "char":
        return 1
    if w and w[-1] in ("short", "int", "unsigned", "signed") and "long" not in w:
        return 2
    if "long" in w:
        return 4
    if t in WIDE_TYPES:
        return 4
    if t in sizes:
        return sizes[t]
    raise GenError(f"{where}: the size of {t} is not known")


def make_structs(consts):
    """C structures laid out from ui.inc's offsets: each field at its constant, gaps
    padded; an overlap or a size that disagrees is an error."""
    o, sizes, layouts = [], {}, {}
    for st in STRUCTS:
        fields = list(layouts.get(st["base"], [])) if st["base"] else []
        if st["base"] and st["base"] not in layouts:
            raise GenError(f"hui.tab:{st['line']}: base {st['base']} not defined before")
        for f in st["fields"]:
            if f["off"] not in consts:
                raise GenError(f"hui.tab:{f['line']}: {f['off']} is not a constant of ui.inc")
            where = f"hui.tab:{f['line']}"
            n = 1
            if f["n"]:
                n = int(consts.get(f["n"], f["n"]))
            size = ctype_size(f["type"], sizes, where) * n
            fields.append(dict(f, at=consts[f["off"]], bytes=size))
        layouts[st["struct"]] = fields
        o += comment(st["doc"])
        o.append(f"struct {st['struct']}_s {{")
        pos = 0
        for f in fields:
            if f["at"] < pos:
                raise GenError(f"hui.tab:{f['line']}: {st['struct']}.{f['name']} at "
                               f"{f['off']} = {f['at']} overlaps the field before (ends at {pos})")
            if f["at"] > pos:
                o.append(f"    unsigned char pad{pos}_[{f['at'] - pos}];")
            decl = f["decl"] + ";"
            cmt = f"/* {f['off']}" + (f": {f['doc']}" if f["doc"] else "") + " */"
            if f["type"] in WIDE_TYPES:
                # a function pointer: 32 bits in vbcc, 16 in cc816 (padded to the same size)
                o.append("#ifdef __CC816__")
                o.append(f"    {decl:<34} {cmt}")
                o.append(f"    unsigned short {f['name']}_hi_;")
                o.append("#else")
                o.append(f"    {decl:<34} {cmt}")
                o.append("#endif")
                pos = f["at"] + f["bytes"]
                continue
            o.append(f"    {decl:<34} {cmt}")
            pos = f["at"] + f["bytes"]
        if st["size"]:
            if st["size"] not in consts:
                raise GenError(f"hui.tab:{st['line']}: size {st['size']} is not a constant")
            if consts[st["size"]] != pos:
                raise GenError(f"hui.tab:{st['line']}: {st['struct']} is {pos} bytes, ui.inc's "
                               f"{st['size']} says {consts[st['size']]}")
        o.append("};")
        o.append(f"HZ_STATIC_ASSERT(sizeof({st['struct']}) == {pos}, {st['struct']});")
        o.append("")
        sizes[st["struct"]] = pos
    return o

def c_value(v):
    return str(v) if v < 10 else f"{v:#X}".replace("0X", "0x")


def comment(lines, indent=""):
    txt = " ".join(lines)
    out, cur = [], ""
    for w in txt.split():
        if len(cur) + len(w) + 1 > 84:
            out.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    if cur:
        out.append(cur)
    if not out:
        return []
    if len(out) == 1:
        return [f"{indent}/** {out[0]} */"]
    return [f"{indent}/** {out[0]}"] + [f"{indent} *  {x}" for x in out[1:]] + [f"{indent} */"]


def make_header(fns, vars_, unbound, d):
    o = ["/* huigen.h - the controls library's constants and routines for C. GENERATED by",
         " * tools/genhui.py from horizon/user/ui.inc, icons.inc, horizon.inc (ulib) and",
         " * ui/hui.tab: do not edit (make -C sdk/c gen). Included by hui.h, which has the",
         " * structures and the rules (sdk/docs/c/apps.md).",
         " *",
         f" * {len(fns)} functions, {len(vars_)} variables; {len(unbound)} names of the "
         "library are not bound",
         " * (hui.tab says why: C has its own way).",
         " * hui.h includes it three times: the constants, the structure names, then (after its\n * own types) the structures and the prototypes. */",
         "#ifndef HUIGEN_CONSTANTS", "#define HUIGEN_CONSTANTS", "",
         "/* ---- constants (ui.inc) */"]
    seen = set()
    for n in d["uiorder"]:
        if n in seen or n not in d["uic"] or n in d["hzc"]:
            continue
        seen.add(n)
        o.append(f"#define {n:<16} {c_value(d['uic'][n])}")
    o += ["", "/* ---- icons (icons.inc): ui_prog, ui_ficon */"]
    for n in d["icoorder"]:
        if n in d["ico"] and n not in seen:
            seen.add(n)
            o.append(f"#define {n:<16} {c_value(d['ico'][n])}")
    o += ["", "#endif", "", "#if defined(HUI_FORWARD) && !defined(HUIGEN_FORWARD)",
          "#define HUIGEN_FORWARD"]
    for st in STRUCTS:
        o.append(f"typedef struct {st['struct']}_s {st['struct']};")
    o += ["#endif", "", "#if defined(HUI_TYPES) && !defined(HUIGEN_PROTOTYPES)",
          "#define HUIGEN_PROTOTYPES", "", "/* ---- structures (ui.inc's offsets, ui/hui.tab) */"]
    o += make_structs(dict(d["uic"]))
    o += ["/* ---- functions (ui/hui.tab) */"]
    for e in fns:
        o += comment(e["doc"])
        o.append(e["proto"] + ";")
    o += ["", "/* ---- variables of the library */"]
    for v in vars_:
        o += comment(v["doc"])
        o.append("extern " + v["decl"] + ";")
    o += ["", "#endif", ""]
    return "\n".join(o)


# ---- the shims -----------------------------------------------------------------------------

def stage(dest):
    if dest == "A":
        return "        sta     z:hui_ra"
    if dest == "X":
        return "        sta     z:hui_rx"
    if dest == "Y":
        return "        sta     z:hui_ry"
    return f"        sta     z:{dest}"


def shim(e):
    """ca65 source of one JSL->JSR shim: C calls hc_NAME with JSL (first argument in A or
    A/X, the others on the stack), the shim loads the registers and the library's zero
    page, JSRs the routine, and turns its registers and carry into the C result."""
    c = e["c"]
    L = [f"; {c}: GENERATED by tools/genhui.py from ui/hui.tab - {e['proto']}",
         "        .p816", "        .smart  off",
         '        .include "horizon.inc"', '        .include "ui.inc"',
         '        .include "huidefs.inc"',
         f"        .export hc_{c}", "",
         '        .segment "CODE"', "        .a16", "        .i16",
         f"hc_{c}:"]
    msgs = []
    params = e["params"]
    frame = 0
    off = {}
    if params:
        p0 = params[0]
        if p0["size"] == 4:
            L += ["        phx", "        pha"]
        else:
            L += ["        pha"]
        frame = p0["size"]
        off[p0["name"]] = 1
        pos = frame + 4                 # above the 3-byte return address
        for p in params[1:]:
            off[p["name"]] = pos
            pos += p["size"]
    if "ctl" in e["flags"]:
        msgs.append(c)
        L += ["        lda     hui_incb", "        beq     @go", "        ldy     #1",
              f"        lda     #.loword(m{len(msgs) - 1})", "        jmp     hui_fail", "@go:"]
    used = set()
    slot = 0
    slots = {}
    for p in params:
        if p["name"] not in e["in"]:
            continue
        dests, kind = e["in"][p["name"]]
        o = off[p["name"]]
        for dd in dests:
            if dd in REGS:
                used.add(dd)
        if kind == "val":
            L += [f"        lda     {o},s", stage(dests[0])]
        elif kind in ("long", "far"):
            L += [f"        lda     {o},s", stage(dests[0]),
                  f"        lda     {o + 2},s", stage(dests[1])]
        elif kind == "ptr":
            msgs.append(f"{c}: {p['name']}")
            L += [f"        lda     {o + 2},s", "        cmp     #^hui_fail",
                  f"        beq     @p{p['name']}", "        ldy     #0",
                  f"        lda     #.loword(m{len(msgs) - 1})", "        jmp     hui_fail",
                  f"@p{p['name']}:", f"        lda     {o},s", stage(dests[0])]
        else:                           # str, buf
            slots[p["name"]] = slot
            L += [f"        lda     {o},s", "        sta     z:hui_s",
                  f"        lda     {o + 2},s", "        sta     z:hui_s+2",
                  f"        ldx     #{slot}", "        jsr     hui_instr", stage(dests[0])]
            slot += 1
    for dest, val in e["set"]:
        if dest in REGS:
            used.add(dest)
        L += [f"        lda     #{val}", stage(dest)]
    for r, z in (("Y", "hui_ry"), ("X", "hui_rx"), ("A", "hui_ra")):
        if r in used:
            L.append(f"        ld{r.lower()}     z:{z}")
    L.append(f"        jsr     {e['asm']}")
    ret = e["ret"]
    needcy = ret in ("ok", "err", "Aerr", "bool", "xoff")
    if ret == "xoff":
        L += ["        stx     z:hui_d"]
    elif ret in ("X", "AX", "Xptr") or any(o[1] == "X" for o in e["out"]):
        L += ["        stx     z:hui_rx"]
    if ret in ("A", "AX", "err", "Aerr") or any(o[1] == "A" for o in e["out"]):
        L += ["        sta     z:hui_ra"]            # (sta, stx keep the carry)
    if needcy:
        L += ["        lda     #0", "        rol     a", "        sta     z:hui_cy"]
    for n, (p, src, kind) in enumerate(e["out"]):
        o = off[p]
        r = "z:hui_ra" if src == "A" else "z:hui_rx"
        L += [f"        lda     {o},s", "        sta     z:hui_s", f"        lda     {o + 2},s",
              "        sta     z:hui_s+2", "        ora     z:hui_s", f"        beq     @o{n}",
              f"        lda     {r}", "        sta     [hui_s]"]
        if kind == "ptr":
            L += ["        ldy     #2", f"        lda     {r}", f"        beq     @z{n}",
                  "        lda     #^hui_fail", f"@z{n}:   sta     [hui_s],y"]
        L.append(f"@o{n}:")
    for p in params:
        if p["name"] in slots and e["in"][p["name"]][1] == "buf":
            o = off[p["name"]]
            L += [f"        lda     {o},s", "        sta     z:hui_s",
                  f"        lda     {o + 2},s", "        sta     z:hui_s+2",
                  f"        ldx     #{slots[p['name']]}", "        jsr     hui_outstr"]
    if ret == "A":
        L.append("        lda     z:hui_ra")
    elif ret == "X":
        L.append("        lda     z:hui_rx")
    elif ret == "AX":
        L += ["        lda     z:hui_ra", "        ldx     z:hui_rx"]
    elif ret == "Xptr":
        L += ["        ldx     #0", "        lda     z:hui_rx", "        beq     @r",
              "        ldx     #^hui_fail", "@r:"]
    elif ret == "ok":
        L += ["        lda     z:hui_cy", "        beq     @r", "        lda     #$FFFF", "@r:"]
    elif ret in ("err", "Aerr"):
        L += ["        lda     z:hui_cy", "        beq     @e0", "        lda     z:hui_ra",
              "        jsr     hui_seterr", "        lda     #$FFFF", "        bra     @r",
              "@e0:    lda     #0", "        jsr     hui_seterr"]
        if ret == "Aerr":
            L.append("        lda     z:hui_ra")
        L.append("@r:")
    elif ret == "bool":
        L.append("        lda     z:hui_cy")
    elif ret == "xoff":
        L += ["        lda     z:hui_cy", "        beq     @no", "        lda     z:hui_d",
              "        sec", "        sbc     z:hui_rx", "        bra     @r",
              "@no:    lda     #$FFFF", "@r:"]
    L += ["        ply"] * (frame // 2)
    L.append("        rtl")
    if msgs:
        L += ["", '        .segment "RODATA"']
        for i, m in enumerate(msgs):
            L.append(f'm{i}:     .byte   "{m}", 0')
    return "\n".join(L) + "\n"


def write_shims(outdir, fns):
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        if f.startswith("hc_") and f.endswith(".s"):
            os.remove(os.path.join(outdir, f))
    names = []
    for e in fns:
        p = os.path.join(outdir, f"hc_{e['c']}.s")
        with open(p, "w") as f:
            f.write(shim(e))
        names.append(p)
    return names


# ---- cc816's shims ---------------------------------------------------------------------------
#
# cc816 calls _NAME with JSR, every argument on the stack from 3,s (2 bytes; 4 for long and
# __far pointers), and wants the result in A (A/X for 32 bits). Every cc816 data pointer is
# an offset in the code bank, where the library reads its structures and strings (DBR):
# ptr, str and buf need no check and no copy; a far pair gets the code bank as its bank.

def c816_size(ctype):
    t = ctype.replace("const", "").strip()
    if "*" in t:
        return 4 if "__far" in t else 2
    if "long" in t.split():
        return 4
    return 2


def shim816(e, large=False):
    """large: the large code model (JSL/RTL: the arguments from 4,s)"""
    c = e["c"]
    L = [f"; {c}: GENERATED by tools/genhui.py from ui/hui.tab (cc816) - {e['proto']}",
         "        .p816", "        .smart  off",
         '        .include "horizon.inc"', '        .include "ui.inc"',
         '        .include "hui816.inc"',
         "        .importzp __cbank",
         f"        .export _{c}", "",
         '        .segment "CODE"', "        .a16", "        .i16",
         f"_{c}:"]
    msgs = []
    off = {}
    pos = 4 if large else 3
    for p in e["params"]:
        off[p["name"]] = (pos, c816_size(p["type"]))
        pos += c816_size(p["type"])
    if "ctl" in e["flags"]:
        msgs.append(c)
        L += ["        lda     hui_incb", "        beq     @go", "        ldy     #1",
              f"        lda     #m{len(msgs) - 1}", "        jmp     hui_fail", "@go:"]
    used = set()
    for p in e["params"]:
        if p["name"] not in e["in"]:
            continue
        dests, kind = e["in"][p["name"]]
        o, size = off[p["name"]]
        for dd in dests:
            if dd in REGS:
                used.add(dd)
        if kind in ("long", "far") and len(dests) == 2:
            L += [f"        lda     {o},s", stage(dests[0])]
            if size == 4:
                L += [f"        lda     {o + 2},s", stage(dests[1])]
            elif kind == "far":
                L += ["        lda     z:__cbank", stage(dests[1])]
            else:
                L += ["        lda     #0", stage(dests[1])]
        else:                           # val, ptr, str, buf: one word (a near pointer)
            L += [f"        lda     {o},s", stage(dests[0])]
    for dest, val in e["set"]:
        if dest in REGS:
            used.add(dest)
        L += [f"        lda     #{val}", stage(dest)]
    for r, z in (("Y", "hui_ry"), ("X", "hui_rx"), ("A", "hui_ra")):
        if r in used:
            L.append(f"        ld{r.lower()}     z:{z}")
    L.append(f"        jsr     {e['asm']}")
    ret = e["ret"]
    needcy = ret in ("ok", "err", "Aerr", "bool", "xoff")
    if ret == "xoff":
        L += ["        stx     z:hui_d"]
    elif ret in ("X", "AX", "Xptr") or any(o_[1] == "X" for o_ in e["out"]):
        L += ["        stx     z:hui_rx"]
    if ret in ("A", "AX", "err", "Aerr") or any(o_[1] == "A" for o_ in e["out"]):
        L += ["        sta     z:hui_ra"]            # (sta, stx keep the carry)
    if needcy:
        L += ["        lda     #0", "        rol     a", "        sta     z:hui_cy"]
    for n, (p, src, kind) in enumerate(e["out"]):
        o, size = off[p]
        r = "z:hui_ra" if src == "A" else "z:hui_rx"
        L += [f"        lda     {o},s", f"        beq     @o{n}", "        tax",
              f"        lda     {r}", "        sta     a:0,x"]
        if size == 4:                   # (a far pointer to the result: not in hui.tab)
            raise GenError(f"hui.tab:{e['line']}: {c}: out through a far pointer")
        L.append(f"@o{n}:")
    if ret == "A":
        L.append("        lda     z:hui_ra")
    elif ret in ("X", "Xptr"):
        L.append("        lda     z:hui_rx")
    elif ret == "AX":
        L += ["        lda     z:hui_ra", "        ldx     z:hui_rx"]
    elif ret == "ok":
        L += ["        lda     z:hui_cy", "        beq     @r", "        lda     #$FFFF", "@r:"]
    elif ret in ("err", "Aerr"):
        L += ["        lda     z:hui_cy", "        beq     @e0", "        lda     z:hui_ra",
              "        jsr     hui_seterr", "        lda     #$FFFF", "        bra     @r",
              "@e0:    lda     #0", "        jsr     hui_seterr"]
        if ret == "Aerr":
            L.append("        lda     z:hui_ra")
        L.append("@r:")
    elif ret == "bool":
        L.append("        lda     z:hui_cy")
    elif ret == "xoff":
        L += ["        lda     z:hui_cy", "        beq     @no", "        lda     z:hui_d",
              "        sec", "        sbc     z:hui_rx", "        bra     @r",
              "@no:    lda     #$FFFF", "@r:"]
    L.append("        rtl" if large else "        rts")
    if msgs:
        L += ["", '        .segment "RODATA"']
        for i, m in enumerate(msgs):
            L.append(f'm{i}:     .byte   "{m}", 0')
    return "\n".join(L) + "\n"


def write_shims816(outdir, fns, vars_=(), large=False):
    """the shims, and for each library variable of hui.tab its C name (_name = name)"""
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        if f.endswith(".s"):
            os.remove(os.path.join(outdir, f))
    names = []
    for e in fns:
        p = os.path.join(outdir, f"hc_{e['c']}.s")
        with open(p, "w") as f:
            f.write(shim816(e, large))
        names.append(p)
    for v in vars_:
        p = os.path.join(outdir, f"hv_{v['c']}.s")
        with open(p, "w") as f:
            f.write(f"; {v['c']}: GENERATED by tools/genhui.py (cc816): the C name of the "
                    f"library's variable\n        .import {v['c']}\n        .export _{v['c']}\n"
                    f"_{v['c']} = {v['c']}\n")
        names.append(p)
    return names


# ---- main ----------------------------------------------------------------------------------

def compile_probe():
    """Compile a file including hui.h with each compiler: its static asserts check the
    structures against the offsets of huigen.h (ui.inc). vbcc is skipped (with a note)
    when its toolchain is not installed."""
    import tempfile
    import hzc
    import hzc816
    errs = []
    with tempfile.TemporaryDirectory(prefix="hui") as tmp:
        src = os.path.join(tmp, "probe.c")
        with open(src, "w") as f:
            f.write("#include <horizon.h>\n#include <hui.h>\nint main(void) { return 0; }\n")
        try:
            hzc816.compile_c(src, None)
        except hzc.HccError as e:
            errs.append(f"hui.h does not compile with cc816 against huigen.h (a structure "
                        f"disagrees with ui.inc?):\n{e}")
        try:
            hzc.vbcc_dir()
        except hzc.HccError:
            print("genhui: the vbcc toolchain is not installed: hui.h not compiled with vbcc")
            return errs
        try:
            hzc.compile_c(src, os.path.join(tmp, "probe.o"), "large")
        except hzc.HccError as e:
            errs.append(f"hui.h does not compile with vbcc against huigen.h (a structure "
                        f"disagrees with ui.inc?):\n{e}")
    return errs


def main():
    a = sys.argv[1:]
    hz = default_horizon()
    mode, outdir = "gen", None
    i = 0
    while i < len(a):
        if a[i] == "--horizon":
            hz = a[i + 1]
            i += 2
        elif a[i] == "--check":
            mode = "check"
            i += 1
        elif a[i] == "--shims":
            mode, outdir = "shims", a[i + 1]
            i += 2
        elif a[i] == "--shims816":
            mode, outdir = "shims816", a[i + 1]
            i += 2
        else:
            sys.exit(__doc__)
    try:
        fns, vars_, unbound = parse_table()
        if mode == "shims":
            write_shims(outdir, fns)
            return 0
        if mode == "shims816":
            write_shims816(outdir, fns, vars_)
            return 0
        d = horizon_data(hz)
        errs = check_coverage(fns, vars_, unbound, d)
        hdr = make_header(fns, vars_, unbound, d)
        if mode == "gen":
            if errs:
                raise GenError("\n".join(errs))
            with open(HEADER, "w") as f:
                f.write(hdr)
            print(f"genhui: {HEADER}: {len(fns)} functions, {len(vars_)} variables")
            return 0
        cur = open(HEADER).read() if os.path.exists(HEADER) else ""
        if cur != hdr:
            errs.append("include/huigen.h is not what ui.inc, icons.inc and ui/hui.tab give "
                        "now: make -C sdk/c gen")
        if not errs:
            errs += compile_probe()
        if errs:
            for e in errs:
                print("genhui: " + e, file=sys.stderr)
            return 1
        npub = len(d["uiglobals"]) + len(d["ulibglobals"])
        print(f"genhui: OK, {len(fns)} functions and {len(vars_)} variables; {npub} public "
              f"names of ui.inc and ulib, {len(unbound)} of them unbound (C has its own)")
        return 0
    except GenError as e:
        print(f"genhui: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
