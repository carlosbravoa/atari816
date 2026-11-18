#!/usr/bin/env python3
"""compare.py EXPECTED ACTUAL - compare console output with an expected file.

Lines must match exactly and in order, except inside blocks marked
    @@ any order
    ...
    @@ end
where the actual output must contain the same lines (as a multiset) in any order. Such
blocks cover stages where several tasks print at once: each line is printed atomically
(one puts), but which task's line comes first depends on timing (console speed).
An expected line starting with "~ " is a pattern (* any text, ? one character; [ is literal),
used where a value depends on timing, e.g. the code bank a task happened to get.
Exit status 0 = match. On a mismatch a short report is printed."""
import sys
from fnmatch import fnmatchcase

def match(exp, got):
    if exp.startswith('~ '):
        return fnmatchcase(got, exp[2:].replace('[', '[[]'))   # '[' is literal
    return exp == got

def segments(lines):
    seg, block = [], None
    for ln in lines:
        if ln == '@@ any order':
            block = []
        elif ln == '@@ end':
            seg.append(('any', block)); block = None
        elif block is not None:
            block.append(ln)
        else:
            seg.append(('one', ln))
    return seg

def main():
    exp = open(sys.argv[1], encoding='latin-1').read().split('\n')
    act = open(sys.argv[2], encoding='latin-1').read().split('\n')
    pos = 0
    for kind, val in segments(exp):
        if kind == 'one':
            got = act[pos] if pos < len(act) else '<end of output>'
            if not match(val, got):
                print(f'line {pos + 1}: expected {val!r}\n         got      {got!r}')
                return 1
            pos += 1
        else:
            got = act[pos:pos + len(val)]
            left = list(got)
            missing = []
            for e in sorted(val, key=lambda e: e.startswith('~ ')):   # exact lines first
                for i, g in enumerate(left):
                    if match(e, g):
                        del left[i]
                        break
                else:
                    missing.append(e)
            if missing or left:
                print(f'unordered block at line {pos + 1} differs')
                for l in missing: print(f'  missing {l!r}')
                for l in left: print(f'  extra   {l!r}')
                return 1
            pos += len(val)
    if pos != len(act):
        print(f'extra output from line {pos + 1}: {act[pos]!r}')
        return 1
    return 0

sys.exit(main())
