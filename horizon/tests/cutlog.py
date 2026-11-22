#!/usr/bin/env python3
"""cutlog.py OUT MARK - (0.29) a session's console from the first line holding MARK on (the
line starting at MARK), to stdout: what tests/compare.py compares (the boot and the file
browser before it are left out)."""
import sys

lines = open(sys.argv[1], encoding="latin-1").read().split("\n")
mark = sys.argv[2]
i = next((k for k, l in enumerate(lines) if mark in l), None)
if i is None:
    sys.exit(f"cutlog: {mark!r} is not in {sys.argv[1]}")
lines = [lines[i][lines[i].index(mark):]] + lines[i + 1:]
sys.stdout.write("\n".join(lines) + "\n")
