#!/usr/bin/env python3
"""sizes.py PROG.map... - bytes in the file (text + data, no bss) per part: the program's
own objects, crt0, and the runtime library split into compiler helpers (libsrc/runtime),
libc (libsrc/common) and the Horizon glue (hzsys, write)."""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = {os.path.splitext(f)[0] for f in os.listdir(os.path.join(HERE, "../cc65-libsrc/runtime"))}
GLUE = {"hzsys", "write"}

for mp in sys.argv[1:]:
    parts = {}
    mod = None
    for line in open(mp):
        if line.startswith("Segment list"): break
        m = re.match(r"^(\S+):$", line)
        if m:
            mod = m.group(1); continue
        m = re.match(r"^\s+(\w+)\s+Offs=\w+\s+Size=(\w+)", line)
        if m and mod and m.group(1) != "BSS" and m.group(1) != "ZEROPAGE":
            lm = re.match(r".*\.lib\((\w+)\.o\)", mod)
            if "ui.lib" in mod or mod.endswith("ulib.o") or "uibind" in mod:
                k = "ui.lib+ulib"
            elif lm:
                n = lm.group(1)
                k = "glue" if n in GLUE else ("runtime" if n in RUNTIME else "libc")
            elif mod.startswith("crt0"):
                k = "crt0"
            else:
                k = "program"
            parts[k] = parts.get(k, 0) + int(m.group(2), 16)
    prg = mp[:-4] + ".PRG"
    print("%-28s file %5d  program %5d  crt0 %4d  runtime %5d  libc %5d  glue %4d%s" % (
        prg, os.path.getsize(prg), parts.get("program", 0), parts.get("crt0", 0),
        parts.get("runtime", 0), parts.get("libc", 0), parts.get("glue", 0),
        "  ui.lib+ulib+binding %d" % parts["ui.lib+ulib"] if "ui.lib+ulib" in parts else ""))
