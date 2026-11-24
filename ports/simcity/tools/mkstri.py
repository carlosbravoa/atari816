#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/mkstri.py OUT.c engine/res/stri.NNN ... : upstream's string lists (the Mac's STR#
resources: one string a line) as C, for GetIndString (src/hooks.c). The strings stay in
the program's main bank (about 2 KB)."""
import os
import sys


def cstr(s):
    out = []
    for ch in s:
        if ch in '\\"':
            out.append('\\' + ch)
        elif 32 <= ord(ch) < 127:
            out.append(ch)
        else:
            out.append('\\%03o' % ord(ch))
    return '"' + ''.join(out) + '"'


def main():
    out, files = sys.argv[1], sys.argv[2:]
    lines = ['/* made by tools/mkstri.py from upstream\'s res/stri.* (GPL-3, engine/README) */',
             '#include <stddef.h>', '']
    tables = []
    for f in sorted(files):
        ident = int(os.path.basename(f).split('.')[1])
        with open(f, encoding='latin-1') as fh:
            text = fh.read()
        strings = text.split('\n')
        if strings and strings[-1] == '':
            strings.pop()           # upstream counts lines ending in '\n'
        lines.append('static const char *const stri_%d[] = {' % ident)
        for s in strings:
            lines.append('    %s,' % cstr(s))
        lines.append('};')
        tables.append((ident, len(strings)))
    lines.append('')
    lines.append('struct stri_table { int id; int n; const char *const *s; };')
    lines.append('const struct stri_table stri_tables[] = {')
    for ident, n in tables:
        lines.append('    { %d, %d, stri_%d },' % (ident, n, ident))
    lines.append('    { 0, 0, NULL }')
    lines.append('};')
    text = '\n'.join(lines) + '\n'
    try:
        with open(out) as fh:
            if fh.read() == text:
                return
    except OSError:
        pass
    with open(out, 'w') as fh:
        fh.write(text)


if __name__ == '__main__':
    main()
