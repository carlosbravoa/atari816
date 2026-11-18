#!/usr/bin/env python3
"""Fetch a sample of the SingleStepTests/65816 suite (Tom Harte) and convert it to the
plain-text format read by tests/cputest.c.

    tests/fetch_sst.py [OUTDIR] [TESTS_PER_FILE]

Only the first ~TESTS_PER_FILE tests of each of the 512 files (256 opcodes x {e,n}) are
downloaded (HTTP range request, the truncated JSON is cut at the last complete test).
MVN/MVP files hold only 200 tests and are fetched whole.

Output, one file per opcode/mode, records separated by blank lines:
    T <name>
    I pc s p a x y dbr d pbr e          initial state
    R addr val addr val ...             initial RAM
    F pc s p a x y dbr d pbr e          final state
    M addr val ...                      final RAM
    C <cycles>                          total bus cycles
    B addr val rw addr val rw ...       valid bus cycles only (VDA, VPA or VPB), rw = r/w
"""
import json, os, sys, urllib.request, concurrent.futures

BASE = "https://raw.githubusercontent.com/SingleStepTests/65816/main/v1/"
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "sst")
per = int(sys.argv[2]) if len(sys.argv) > 2 else 200
os.makedirs(out, exist_ok=True)
REGS = ("pc", "s", "p", "a", "x", "y", "dbr", "d", "pbr", "e")


def parse_prefix(text):
    dec = json.JSONDecoder()
    i = text.index("[") + 1
    tests = []
    while True:
        while i < len(text) and text[i] in " \t\r\n,":
            i += 1
        if i >= len(text) or text[i] == "]":
            break
        try:
            obj, i = dec.raw_decode(text, i)
        except json.JSONDecodeError:
            break
        tests.append(obj)
    return tests


def fetch(name):
    dst = os.path.join(out, name.replace(".json", ".txt"))
    if os.path.exists(dst):
        return name, "cached"
    whole = name[:2] in ("44", "54")
    req = urllib.request.Request(BASE + name)
    if not whole:
        req.add_header("Range", "bytes=0-%d" % (per * 700 + 20000))
    data = urllib.request.urlopen(req, timeout=120).read().decode()
    tests = parse_prefix(data)[:per]
    lines = []
    for t in tests:
        ini, fin = t["initial"], t["final"]
        lines.append("T " + t["name"])
        lines.append("I " + " ".join(str(ini[r]) for r in REGS))
        lines.append("R " + " ".join("%d %d" % (a, v) for a, v in ini["ram"]))
        lines.append("F " + " ".join(str(fin[r]) for r in REGS))
        lines.append("M " + " ".join("%d %d" % (a, v) for a, v in fin["ram"]))
        lines.append("C %d" % len(t["cycles"]))
        bus = []
        for a, v, f in t["cycles"]:
            if f[0] == "d" or f[1] == "p" or f[2] == "v":
                bus.append("%d %d %s" % (a, -1 if v is None else v, f[3]))
        lines.append("B " + " ".join(bus))
        lines.append("")
    with open(dst + ".tmp", "w") as fh:
        fh.write("\n".join(lines))
    os.rename(dst + ".tmp", dst)
    return name, len(tests)


names = ["%02x.%s.json" % (op, m) for op in range(256) for m in "en"]
with concurrent.futures.ThreadPoolExecutor(16) as ex:
    for name, n in ex.map(fetch, names):
        print(name, n, flush=True)
