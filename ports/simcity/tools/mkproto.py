#!/usr/bin/env python3
"""tools/mkproto.py FILE.c ... : the declarations of the functions the files define (at
column 0: the return type on the line before, the name and an ANSI parameter list), for
src/proto.h. Used once to write proto.h's engine part; kept to renew it after a change."""
import re
import sys


def strip(l):
    s = re.sub(r'"(\\.|[^"\\])*"', '""', l)
    s = re.sub(r"'(\\.|[^'\\])*'", "''", s)
    s = re.sub(r'/\*.*?\*/', '', s)
    return re.sub(r'//.*', '', s)


def port_lines(L):
    """the lines a build with MICROPOLIS_PORT defined compiles (that macro's #if groups
    only; other groups are kept)"""
    out, stack = [], []          # stack: (is_port_group, keep_now)
    for l in L:
        m = re.match(r'^\s*#\s*(if|ifdef|ifndef|else|elif|endif)\b(.*)', l)
        if m:
            d, rest = m.group(1), m.group(2)
            if d in ('if', 'ifdef', 'ifndef'):
                if 'MICROPOLIS_PORT' in rest:
                    neg = d == 'ifndef' or '!' in rest
                    stack.append((True, not neg))
                else:
                    stack.append((False, True))
            elif d == 'else' and stack and stack[-1][0]:
                stack[-1] = (True, not stack[-1][1])
            elif d == 'endif' and stack:
                stack.pop()
            out.append('')
            continue
        out.append(l if all(k for _, k in stack) else '')
    return out


for f in sys.argv[1:]:
    L = port_lines(open(f, encoding='latin-1').read().split('\n'))
    print('/* %s */' % f.split('/')[-1])
    for i, l in enumerate(L):
        m = re.match(r'^([A-Za-z_]\w*)\s*\(', l)
        one = re.match(r'^((?:void|int|short|unsigned|char|QUAD)\b[\w\s\*]*?)\s*\b([A-Za-z_]\w*)\s*\(', l)
        if one and not l.rstrip().endswith(';') and one.group(1).strip() not in ('return',):
            prev = one.group(1).strip()
            m = re.match(r'(.*)', one.group(2))
            l = l[one.start(2):]
        elif not m or l.rstrip().endswith(';') or i == 0:
            continue
        else:
            prev = strip(L[i - 1]).strip()
        if not re.match(r'^(static\s+)?(void|int|short|char|QUAD|SimSprite|float|unsigned)\b.*$', prev):
            continue
        if prev.startswith('static') or m.group(1).startswith('_'):
            continue
        j, txt = i, l
        while ')' not in txt:
            j += 1
            txt += ' ' + L[j].strip()
        txt = strip(txt)
        params = txt[txt.index('(') + 1:txt.rindex(')')]
        if params.strip() == '':
            params = 'void'
        if not re.search(r'\b(void|int|short|char|QUAD|float|double|SimView|SimSprite|SimGraph|unsigned|Ink)\b', params):
            continue    # K&R or a macro: by hand
        rt = prev.replace('SimSprite', 'struct SimSprite')
        params = re.sub(r'\bSimView\b', 'struct SimView', params)
        params = re.sub(r'\bSimSprite\b', 'struct SimSprite', params)
        params = re.sub(r'\s+', ' ', params)
        print('%s %s(%s);' % (rt, m.group(1), params))
