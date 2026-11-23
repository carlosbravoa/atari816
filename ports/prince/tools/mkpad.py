#!/usr/bin/env python3
"""mkpad.py N OUT.c - a test-only object that shifts the program's layout (make PAD=N).

About N / 4 bytes each of constants, initialised data and bss (in the main bank, before
the game's own: the object is linked first; the main bank has about 400 bytes to spare,
so N up to about 500) and a function of about 4 N bytes of code (in a code bank). Nothing
calls or reads them; only the addresses of everything after them move."""
import sys

n = int(sys.argv[1])
out = sys.argv[2]
m = n // 4 + 1
lines = [f"/* made by tools/mkpad.py {n}: make PAD={n} (tests/layouts.sh) */",
         f"const char hz_pad_rodata[{m}] = {{1}};",
         f"char hz_pad_data[{m + n % 3}] = {{1}};",
         f"char hz_pad_bss[{m + n % 5}];",
         "unsigned hz_pad_code(unsigned v)", "{"]
# each statement is a few bytes of 65816 code (about 8): N / 2 of them
for i in range(max(1, n // 2)):
    lines.append(f"    v = (v ^ {i * 7 + 1}u) + hz_pad_data[{i % m}];")
lines += ["    return v;", "}", ""]
open(out, "w").write("\n".join(lines))
