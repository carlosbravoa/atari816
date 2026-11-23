#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/host16.py IN OUT [NAME]: the host build's copy of a C source or header with DOS's
16-bit `int` (PORTING-NOTES.md, "The host build"). gcc has no 16-bit int, so the host's
copies of the engine's files (upstream's, plat/, compat/, host/) say `short` where the
DOS code says `int`:

    int, signed, signed int, short int      -> short
    unsigned, unsigned int                  -> unsigned short
    unsigned short int                      -> unsigned short
    long int, unsigned long int, ...        -> long, unsigned long (32 bits: xcompat.h)
    char, long, long long and their forms   -> as they are

Strings, character constants, comments and #include lines are left alone. Kept native
(`int`): `main` and `xcom_main` with their parameters (the C library calls main), the type
in `va_arg(ap, int)` (a short is promoted through `...`), and any line with the comment
`host16: native`. `#pragma pack(...)` becomes `#pragma pack(1)` (cc816 packs every
structure; xcompat.h packs from its end on), and an `#include <...>` is wrapped in the
default packing so that the C library's structures keep their layout. `#line` keeps
gcc's messages (and __FILE__) on NAME, the original file (default: IN).

Only the host build uses this; the Atari816's cc816 has a 16-bit int already."""
import os
import re
import sys

TYPEWORDS = {'int', 'unsigned', 'signed', 'short', 'long', 'char'}
NATIVE_FUNCS = {'main', 'xcom_main'}

TOKEN = re.compile(r'''
    (?P<ws>[ \t\f\v]+|\\\n|\n)
  | (?P<com>/\*.*?\*/|//[^\n]*)
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<id>[A-Za-z_]\w*)
  | (?P<num>\.?[0-9](?:[eEpP][+-]|[\w.])*)
  | (?P<op>.)
''', re.S | re.X)


def tokens(text):
    """(kind, text, line) of every token; a preprocessor line's # starts kind 'pp'"""
    out, line, pos, bol = [], 1, 0, True
    while pos < len(text):
        m = TOKEN.match(text, pos)
        kind, s = m.lastgroup, m.group()
        if kind == 'op' and s == '#' and bol:
            kind = 'pp'
        out.append([kind, s, line])
        if kind == 'ws' and '\n' in s and s != '\\\n':
            bol = True
        elif kind not in ('ws', 'com'):
            bol = False
        line += s.count('\n')
        pos = m.end()
    return out


def directive(toks, i):
    """the directive's name after the pp token at i, and the index of its line's end"""
    j, name = i + 1, None
    while j < len(toks) and toks[j][0] in ('ws', 'com') and toks[j][1] != '\n':
        j += 1
    if j < len(toks) and toks[j][0] == 'id':
        name = toks[j][1]
    k = j
    while k < len(toks) and toks[k][1] != '\n':
        k += 1
    return name, k


def canon(words):
    """the type of a run of type words, in short words"""
    if 'char' in words or 'long' in words:
        w = [x for x in words if x != 'int']
        return ' '.join(w) if w else 'int'
    sign = 'unsigned ' if 'unsigned' in words else ''
    return sign + 'short'


def rewrite(text, name):
    toks = tokens(text)
    native_lines = {t[2] for t in toks if t[0] == 'com' and 'host16: native' in t[1]}
    sig = [i for i, t in enumerate(toks) if t[0] not in ('ws', 'com')]
    native = set()                      # token indices kept as written
    before, after = {}, {}              # extra text around a token
    # preprocessor lines: #include and #pragma pack
    skip = set()
    for i, t in enumerate(toks):
        if t[0] != 'pp':
            continue
        d, end = directive(toks, i)
        if d == 'include':
            skip.update(range(i, end))
            line = ''.join(x[1] for x in toks[i:end])
            if '<' in line.split('include', 1)[1].lstrip()[:1]:
                before[i] = '#pragma pack(push)\n#pragma pack()\n'
                nl = toks[end][2] + 1 if end < len(toks) else t[2] + 1
                after[end - 1] = f'\n#pragma pack(pop)\n#line {nl} "{name}"'
        elif d in ('if', 'ifdef', 'ifndef', 'elif', 'else', 'endif') and end > i:
            # a #line in a group left out is ignored: say the line again after each
            # conditional (the wrapped includes add lines)
            nl = toks[end][2] + 1 if end < len(toks) else t[2] + 1
            after[end - 1] = after.get(end - 1, '') + f'\n#line {nl} "{name}"'
        elif d == 'pragma':
            line = ''.join(x[1] for x in toks[i:end])
            if re.match(r'#\s*pragma\s+pack\b', line):
                skip.update(range(i + 1, end))
                toks[i][1] = '#pragma pack(1)'
                for j in range(i + 1, end):
                    toks[j][1] = ''
    # native regions: main's declarator and parameters, va_arg's type
    for n, i in enumerate(sig):
        t = toks[i]
        if t[0] == 'id' and (t[1] in NATIVE_FUNCS or t[1] == 'va_arg') \
                and n + 1 < len(sig) and toks[sig[n + 1]][1] == '(':
            depth, m = 0, n + 1
            while m < len(sig):
                s = toks[sig[m]][1]
                depth += (s == '(') - (s == ')')
                native.add(sig[m])
                if depth == 0:
                    break
                m += 1
            if t[1] in NATIVE_FUNCS:      # its return type: the type words before it
                m = n - 1
                while m >= 0 and toks[sig[m]][0] == 'id' and toks[sig[m]][1] in TYPEWORDS:
                    native.add(sig[m])
                    m -= 1
    # the runs of type words
    n = 0
    while n < len(sig):
        i = sig[n]
        t = toks[i]
        if t[0] != 'id' or t[1] not in TYPEWORDS or i in skip:
            n += 1
            continue
        m = n
        while m < len(sig) and toks[sig[m]][0] == 'id' and toks[sig[m]][1] in TYPEWORDS:
            m += 1
        run = sig[n:m]
        if not any(j in native or toks[j][2] in native_lines for j in run):
            words = [toks[j][1] for j in run]
            new = canon(words)
            if new != ' '.join(words):
                toks[run[0]][1] = new
                for j in run[1:]:
                    toks[j][1] = ''
        n = m
    out = [f'#line 1 "{name}"\n']
    for i, t in enumerate(toks):
        out.append(before.get(i, '') + t[1] + after.get(i, ''))
    return ''.join(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else src
    with open(src, encoding='latin-1') as f:
        text = f.read()
    out = rewrite(text, name)
    try:
        with open(dst, encoding='latin-1') as f:
            if f.read() == out:
                return                  # unchanged: keep its time (no rebuild)
    except OSError:
        pass
    tmp = dst + '.new'
    with open(tmp, 'w', encoding='latin-1') as f:
        f.write(out)
    os.replace(tmp, dst)


if __name__ == '__main__':
    main()
