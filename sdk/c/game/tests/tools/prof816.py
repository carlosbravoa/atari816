#!/usr/bin/env python3
"""prof816.py - a profile of a Horizon program: where the CPU time of a stretch of emulated
time goes (the program's functions, each syscall, the kernel's interrupts, idle), by
cycles, from emu816's counts (--prof) or its instruction trace (--trace).

    prof816.py --counts PROF.txt --map PROG.map [--prg PROG.PRG] [--top N] [--out FILE]
    prof816.py --map PROG.map --from SECONDS --to SECONDS [--out FILE] < trace

The counts (fast: the emulator adds the cycles up itself) come from emu816 --prof FILE,
or run816.py --prof FILE [--prof-from S --prof-to S]. The trace (one line per instruction:
slow, for short stretches) from emu816 --trace on stderr; emu-prof.sh runs it through
this.

The functions' addresses:
  cc816 (hcc --map: NAME.map, ld65's map, and NAME.lbl beside it, every label): both code
        models. The large one's other code banks are matched with the banks the program
        got when it ran by their bytes (the program file, NAME.PRG beside the map, or
        --prg: the o65 for the main bank, the banks after it for the others)
  vbcc  (hcc --cc vbcc --map: vlink's map, NNN_text.name addr(size)): the code bank is
        the user-mode bank seen most
Rows: a function (or an assembly routine: the label before the address), "syscall $NN"
(the kernel's cycles for the program's COP #NN, with the calls), "kernel" (interrupts,
other tasks), "idle (WAI)", "(user bank $BB)" (code of no image: Horizon's ulib, ...).
"""
import bisect
import collections
import os
import re
import struct
import sys

CPS = 14_343_750            # emu816's cycles a second (machine.h CPU_HZ)


# ---- the functions' addresses ---------------------------------------------------------

def load_vbcc_map(path):
    funcs = []
    pat = re.compile(r"\d+_text\.(?:far\.|near\.)?([A-Za-z_][\w.]*?)(?:\.\d+)? "
                     r"([0-9a-f]+)\(([0-9a-f]+)\)")
    for ln in open(path, encoding="latin-1"):
        for m in pat.finditer(ln):
            name, start, size = m.group(1), int(m.group(2), 16), int(m.group(3), 16)
            funcs.append((start, start + size, name))
    funcs.sort()
    return funcs


def is_ld65_map(path):
    try:
        with open(path, encoding="latin-1") as f:
            return any(ln.startswith("Exports list") or ln.startswith("Modules list")
                       for ln in f)
    except OSError:
        return False


# labels inside a function: cc816's (L<function>_<n>, _b<n>, _x<n>; the peephole's Lpi<n>),
# thunks' and aliases' __T names, cheap locals
_SKIP = re.compile(r"^(?:L\w*\d|__T_\w+|@.*|\w*@.*)$")


def clean(name):
    """a label as the reader knows it: _main -> main, a library static's file tag off"""
    name = name.lstrip(".")
    m = re.match(r"^S[0-9a-f]{6}_(_\w+)$", name)
    if m:
        name = m.group(1) + " (static)"
    if name.startswith("_") and not name.startswith("__"):
        name = name[1:]
    return name


def map_exports(path):
    out = set()
    on = False
    for ln in open(path, encoding="latin-1"):
        if ln.startswith("Exports list by name"):
            on = True
            continue
        if on:
            if ln.startswith("Exports list by value") or ln.startswith("Imports list"):
                break
            for m in re.finditer(r"(\S+)\s+[0-9A-F]{6}\s+\w+", ln):
                out.add(m.group(1))
    return out


def load_ld65(mappath, lblpath):
    """{bank: (starts, names)} from the label file (bank 0: the main bank; k: code bank k
    of the large model's link). A function starts at a C function's label (_name, a
    library's static S<tag>__name) or at an exported one (an assembly routine); another
    assembly label (a loop, a patched instruction, a routine of its own file) counts as
    part of the function before it"""
    exported = map_exports(mappath)
    labels = collections.defaultdict(dict)
    for ln in open(lblpath, encoding="latin-1"):
        p = ln.split()
        if len(p) != 3 or p[0] != "al":
            continue
        a = int(p[1], 16)
        name = p[2].lstrip(".")
        if _SKIP.match(name) or name.startswith("__T"):
            continue
        if not (name in exported or (name.startswith("_") and not name.startswith("__"))
                or re.match(r"^S[0-9a-f]{6}__", name)):
            continue
        b, off = a >> 16, a & 0xFFFF
        old = labels[b].get(off)
        # (several names at one address: a function's own name before an alias)
        if old is None or (old.startswith("_") and not name.startswith("_")) or \
                (len(name) < len(old) and old.startswith("__")):
            labels[b][off] = name
    out = {}
    for b, d in labels.items():
        starts = sorted(d)
        out[b] = (starts, [clean(d[s]) for s in starts])
    return out


def o65_text(data):
    """the o65 file's text and data, as loaded (at its text base, $0100)"""
    if data[0:2] != b"\x01\x00" or data[2:5] != b"o65":
        return None, 0
    tbase, tlen, dbase, dlen = struct.unpack_from("<4H", data, 8)
    p = 26
    while data[p]:
        p += data[p]
    p += 1
    return data[p:p + tlen + dlen], tbase


def prg_images(path):
    """{bank of the link: (bytes, base)}: 0 the main bank (the o65), k the large model's
    code bank k (the block after the o65)"""
    out = {}
    try:
        d = open(path, "rb").read()
    except OSError:
        return out
    t, base = o65_text(d)
    if t is not None:
        out[0] = (t, base)
    if len(d) > 16 and d[-4:] == b"HZPX":
        at = struct.unpack_from("<I", d, len(d) - 8)[0]
        if d[at:at + 4] == b"HZPX":
            n = d[at + 5]
            sizes = struct.unpack_from(f"<{n}I", d, at + 12)
            p = at + 12 + 4 * n
            for k in range(n):
                out[k + 1] = (d[p:p + sizes[k]], 0)
                p += sizes[k]
    return out


def match_banks(ops, images):
    """{runtime bank: bank of the link}: each user bank that ran matched with the image
    whose bytes agree with the opcodes seen there (relocated operands never are opcodes)"""
    seen = collections.defaultdict(list)
    for a, op in ops.items():
        seen[a >> 16].append((a & 0xFFFF, op))
    out = {}
    for rb, lst in seen.items():
        best, score = None, 0.0
        for k, (img, base) in images.items():
            good = 0
            for off, op in lst:
                i = off - base
                if 0 <= i < len(img) and img[i] == op:
                    good += 1
            s = good / len(lst)
            if s > score:
                best, score = k, s
        if best is not None and score >= 0.9:
            out[rb] = best
    return out


# ---- the counts -------------------------------------------------------------------------

def read_counts(path):
    upc, ops, sysc, sysn, other = collections.Counter(), {}, collections.Counter(), \
        collections.Counter(), collections.Counter()
    span = None
    for ln in open(path):
        p = ln.split()
        if not p:
            continue
        if p[0] == "u":
            a = int(p[1], 16)
            upc[a] += int(p[2])
            ops[a] = int(p[3], 16)
        elif p[0] == "s":
            sysc[p[1]] += int(p[2])
            sysn[p[1]] += int(p[3])
        elif p[0] == "k":
            other["kernel: interrupts, other tasks"] += int(p[1])
        elif p[0] == "i":
            other["idle (WAI)"] += int(p[1])
        elif ln.startswith("#"):
            m = re.search(r"([\d.]+) to (-?[\d.]+) s", ln)
            if m and float(m.group(2)) >= 0:
                span = float(m.group(2)) - float(m.group(1))
    return upc, ops, sysc, sysn, other, span


def read_trace(stream, t0, t1):
    upc, sysc, sysn, other = collections.Counter(), collections.Counter(), \
        collections.Counter(), collections.Counter()
    prev = None
    insys = None
    for ln in stream:
        try:
            cyc = int(ln[0:10])
        except ValueError:
            continue
        if cyc > t1:
            break
        bank = int(ln[11:13], 16)
        pc = int(ln[14:18], 16)
        tail = ln.rstrip("\n")
        wai = tail.endswith(" WAI")
        mode = tail[-5] if wai else tail[-1]
        if prev and prev[0] >= t0:
            d = cyc - prev[0]
            if prev[4]:
                other["idle (WAI)"] += d
            elif prev[3] == "U":
                upc[prev[1] << 16 | prev[2]] += d
            elif insys is not None:
                sysc[insys] += d
            else:
                other["kernel: interrupts, other tasks"] += d
        if mode == "U":
            if prev and prev[3] == "S":
                insys = None
            if ln[20:22] == "02":
                insys = ln[23:25]
                if cyc >= t0:
                    sysn[insys] += 1
        prev = (cyc, bank, pc, mode, wai)
    return upc, sysc, sysn, other


# ---- the report -----------------------------------------------------------------------------

def main():
    a = sys.argv[1:]
    opt = {"--from": "0", "--to": "1e9", "--map": None, "--out": None, "--counts": None,
           "--prg": None, "--lbl": None, "--top": "40"}
    i = 0
    while i < len(a):
        if a[i] not in opt or i + 1 >= len(a):
            sys.exit(__doc__)
        opt[a[i]] = a[i + 1]
        i += 2
    mp = opt["--map"]
    ops = {}
    span = None
    if opt["--counts"]:
        upc, ops, sysc, sysn, other, span = read_counts(opt["--counts"])
    else:
        t0 = int(float(opt["--from"]) * CPS)
        t1 = int(float(opt["--to"]) * CPS)
        upc, sysc, sysn, other = read_trace(sys.stdin, t0, t1)
        span = (t1 - t0) / CPS if t1 < 1e15 else None
    total = sum(upc.values()) + sum(sysc.values()) + sum(other.values())
    if not total:
        sys.exit("prof816: no cycles in the window")

    # which runtime bank is which part of the program
    banks = collections.Counter()
    for addr, c in upc.items():
        banks[addr >> 16] += c
    tables = {}             # runtime bank -> (starts, names)
    note = ""
    if mp and is_ld65_map(mp):
        lbl = opt["--lbl"] or os.path.splitext(mp)[0] + ".lbl"
        prg = opt["--prg"] or os.path.splitext(mp)[0] + ".PRG"
        if not os.path.exists(lbl):
            sys.exit(f"prof816: no label file {lbl} (hcc --map writes it beside the map)")
        fn = load_ld65(mp, lbl)
        images = prg_images(prg)
        if ops and images:
            where = match_banks(ops, images)
        else:
            # (the trace has no opcodes: the bank seen most is the main bank)
            where = {banks.most_common(1)[0][0]: 0} if banks else {}
        for rb, k in where.items():
            if k in fn:
                tables[rb] = fn[k]
        note = ", ".join(f"${rb:02X} = " + ("the main bank" if k == 0 else f"code bank {k}")
                         for rb, k in sorted(where.items()))
    elif mp:
        funcs = load_vbcc_map(mp)
        if banks:
            rb = banks.most_common(1)[0][0]
            tables[rb] = ([f[0] for f in funcs], [f[2] for f in funcs])
            ends = {f[0]: f[1] for f in funcs}
            note = f"${rb:02X} = the code bank"
    byf = collections.Counter()
    for addr, c in upc.items():
        rb, pc = addr >> 16, addr & 0xFFFF
        t = tables.get(rb)
        if not t:
            byf[f"(user bank ${rb:02X})"] += c
            continue
        k = bisect.bisect_right(t[0], pc) - 1
        byf[t[1][k] if k >= 0 else f"?{rb:02X}:{pc:04X}"] += c
    out = open(opt["--out"], "w") if opt["--out"] else sys.stdout
    secs = span if span else total / CPS
    print(f"prof816: {secs:.2f} s of emulated time, {total:,} cycles"
          + (f"; banks: {note}" if note else ""), file=out)
    prog = sum(c for n, c in byf.items() if not n.startswith("(user bank"))
    print(f"the program's own code {100.0 * prog / total:.1f} %, syscalls "
          f"{100.0 * sum(sysc.values()) / total:.1f} %, kernel and idle "
          f"{100.0 * sum(other.values()) / total:.1f} %", file=out)
    print(f"{'cycles':>13} {'%':>6}  where", file=out)
    rows = [(c, n) for n, c in byf.items()]
    rows += [(c, f"syscall ${n} ({sysn[n]} calls, {c // max(1, sysn[n])} cycles each)")
             for n, c in sysc.items()]
    rows += [(c, n) for n, c in other.items()]
    for c, n in sorted(rows, reverse=True)[:int(opt["--top"])]:
        print(f"{c:13,d} {100.0 * c / total:6.2f}  {n}", file=out)


if __name__ == "__main__":
    main()
