#!/usr/bin/env python3
"""sizes.py MAP [PROGRAM_OBJ ...] - bytes per input object in a vlink map (-M), split into
the program's own objects (named on the command line) and the rest (startup, syscall
gate, C library / runtime). Loadable bytes (text, rodata, data) and bss separately."""
import re
import sys

prog = set(sys.argv[2:])
load = {}
bss = {}
with open(sys.argv[1], encoding="latin-1") as f:
    for line in f:
        m = re.match(r"^\s+([0-9a-f]{8}) - ([0-9a-f]{8}) (\S+)\((\S+)\)", line)
        if not m:
            continue
        n = int(m.group(2), 16) - int(m.group(1), 16)
        obj, sec = m.group(3), m.group(4)
        d = bss if "bss" in sec else load
        d[obj] = d.get(obj, 0) + n
P = sum(v for k, v in load.items() if k in prog)
R = sum(v for k, v in load.items() if k not in prog)
Pb = sum(v for k, v in bss.items() if k in prog)
Rb = sum(v for k, v in bss.items() if k not in prog)
print("program: %6d loadable + %6d bss" % (P, Pb))
print("runtime: %6d loadable + %6d bss  (%s)" % (R, Rb, ", ".join(
    "%s %d" % (k, v) for k, v in sorted(load.items(), key=lambda x: -x[1]) if k not in prog)))
