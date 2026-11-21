#!/usr/bin/env python3
"""prof816.py - a profile of a Horizon program from emu816's instruction trace: where the
CPU time of a stretch of emulated time goes (the program's functions, each syscall, the
kernel's interrupts, idle), by cycles.

    prof816.py --map PROG.map --from SECONDS --to SECONDS [--out FILE] < trace

The trace comes from emu816 --trace on stderr (one line per instruction, with the cycle
count); run816.py runs it through this with --emu tests/tools/emu-prof.sh (see there).
PROG.map is hcc --map's link map (the functions' addresses in the code bank). The
program's code bank is found by itself (the user-mode bank seen most).
"""
import collections
import re
import sys

CPS = 14_343_000            # emu816's cycles a second (197.94 M in 13.8 s)


def load_map(path):
    funcs = []
    pat = re.compile(r"\d+_text\.(?:far\.|near\.)?([A-Za-z_][\w.]*?)(?:\.\d+)? "
                     r"([0-9a-f]+)\(([0-9a-f]+)\)")
    for ln in open(path, encoding="latin-1"):
        for m in pat.finditer(ln):
            name, start, size = m.group(1), int(m.group(2), 16), int(m.group(3), 16)
            funcs.append((start, start + size, name))
    funcs.sort()
    return funcs


def main():
    a = sys.argv[1:]
    opt = {"--from": 0.0, "--to": 1e9, "--map": None, "--out": None}
    i = 0
    while i < len(a):
        opt[a[i]] = a[i + 1]
        i += 2
    t0 = int(float(opt["--from"]) * CPS)
    t1 = int(float(opt["--to"]) * CPS)
    funcs = load_map(opt["--map"]) if opt["--map"] else []
    starts = [f[0] for f in funcs]

    upc = collections.Counter()         # (bank, pc) -> cycles in user mode
    sysc = collections.Counter()        # syscall number -> kernel cycles
    sysn = collections.Counter()        # syscall number -> calls
    other = collections.Counter()
    prev = None                         # (cycles, bank, pc, mode, wai)
    insys = None                        # the syscall the kernel works for
    lastcop = None
    for ln in sys.stdin:
        try:
            cyc = int(ln[0:10])
        except ValueError:
            continue
        if cyc > t1:
            break
        bank = ln[11:13]
        pc = ln[14:18]
        tail = ln.rstrip("\n")
        wai = tail.endswith(" WAI")
        mode = tail[-5] if wai else tail[-1]
        if prev and prev[0] >= t0:
            d = cyc - prev[0]
            if prev[4]:
                other["idle (WAI)"] += d
            elif prev[3] == "U":
                upc[(prev[1], prev[2])] += d
            elif insys is not None:
                sysc[insys] += d
            else:
                other["kernel: interrupts, other tasks"] += d
        if mode == "U":
            if prev and prev[3] == "S":
                insys = None
            op = ln[20:22]
            if op == "02":                  # COP #n: a syscall
                lastcop = ln[23:25]
                insys = lastcop
                if cyc >= t0:
                    sysn[lastcop] += 1
        prev = (cyc, bank, pc, mode, wai)
    total = sum(upc.values()) + sum(sysc.values()) + sum(other.values())
    if not total:
        sys.exit("prof816: no cycles in the window")
    banks = collections.Counter()
    for (b, p), c in upc.items():
        banks[b] += c
    prog = banks.most_common(1)[0][0] if banks else None
    byf = collections.Counter()
    import bisect
    for (b, p), c in upc.items():
        if b != prog:
            byf[f"(user bank {b})"] += c
            continue
        pcv = int(p, 16)
        k = bisect.bisect_right(starts, pcv) - 1
        name = funcs[k][2] if k >= 0 and funcs[k][0] <= pcv < funcs[k][1] else f"?{p}"
        byf[name] += c
    out = open(opt["--out"], "w") if opt["--out"] else sys.stdout
    secs = (t1 - t0) / CPS if t1 < 1e15 else total / CPS
    print(f"prof816: {secs:.2f} s of emulated time, {total} cycles; the program in bank "
          f"${prog}", file=out)
    print(f"{'cycles':>12} {'%':>6}  where", file=out)
    rows = [(c, n) for n, c in byf.items()]
    rows += [(c, f"syscall ${n} ({sysn[n]} calls, {c // max(1, sysn[n])} cycles each)")
             for n, c in sysc.items()]
    rows += [(c, n) for n, c in other.items()]
    for c, n in sorted(rows, reverse=True)[:60]:
        print(f"{c:12d} {100.0 * c / total:6.2f}  {n}", file=out)


if __name__ == "__main__":
    main()
