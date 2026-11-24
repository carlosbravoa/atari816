#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Carlos Bravo (the Atari816 SDK: sdk/LICENSE)
"""host16.py - build a C program on the PC with the Atari816's integer sizes, to compare
its behaviour with the Atari816's (a port's "host twin").

    host16.py [options] CC [CC options and files ...]
    host16.py [options] -E FILE.c -o OUT.c [CC preprocessor options]

The first form is a compiler wrapper: every .c file among the arguments is preprocessed
with CC (-E -C, the same -I -D -U -include options), its types rewritten as cc816 sees
them, and CC then compiles the rewritten copies with the rest of the arguments:

    host16.py cc -O1 -I src -o build/game16 src/*.c

The second form only writes the rewritten, preprocessed source.

What is rewritten, in the program's own files (the C library's headers, CC's system
headers, are left as they are: their structures and functions keep the PC's types):

    int, signed, short, short int, signed int        -> short           (16 bits)
    unsigned, unsigned int, unsigned short [int]     -> unsigned short
    long, long int, signed long                      -> int             (32 bits)
    unsigned long [int]                              -> unsigned int
    long long, unsigned long long, char              -> as they are
    double, long double                              -> float  (cc816's double is the
                                                        32-bit float; --keep-double: no)
    a constant's L or l suffix (not LL)              -> none   (5L is a 32-bit int)

The source is preprocessed first, so a type word that a macro hides is seen as the
compiler sees it: `#define QUAD long` then `unsigned QUAD` is an `unsigned int`, not an
`unsigned short` followed by a stray word (the fault of the ports' textual rewriters).
CC also gets -funsigned-char (cc816's plain char is unsigned), -fsingle-precision-constant
(unless --keep-double), -fwrapv and -fno-strict-aliasing, and every structure of the
program is packed (as cc816 lays structures
out without padding: __attribute__((packed)) on each one the program defines; --no-pack:
not).

Kept as the PC has them: `main`'s return type and parameters, the type in va_arg(ap,
int) (a short is promoted to int through `...`), every function named with --native NAME
(a callback the C library calls: qsort's comparison, signal's handler; its return type
and parameters), and every token on a line with the comment `host16: native`.

What it cannot make 16 bits: the arithmetic. The PC computes a short + a short in 32
bits; a result stored is cut to 16 as on the Atari816, but a sum compared or passed
before it is stored can differ (cc816 computes in 16 bits). Pointers are 8 bytes on the
PC: a structure holding pointers has another size. printf's %ld with a long (now an int)
works for values that are not negative only. Comparing the two programs' output (a
port's test) shows where it matters.

Options (before CC):
  --native NAME     keep NAME's signature (repeatable)
  --keep-double     double stays double
  --no-pack         structures keep the PC's padding
  --keep DIR        keep the rewritten files in DIR (default: a temporary folder)
  -v                print the commands
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

TYPEWORDS = {'int', 'unsigned', 'signed', 'short', 'long', 'char', 'double', 'float'}

TOKEN = re.compile(r'''
    (?P<ws>[ \t\f\v]+|\n)
  | (?P<com>/\*.*?\*/|//[^\n]*)
  | (?P<str>(?:L|u8|u|U)?"(?:\\.|[^"\\\n])*"|(?:L|u|U)?'(?:\\.|[^'\\\n])*')
  | (?P<id>[A-Za-z_]\w*)
  | (?P<num>\.?[0-9](?:[eEpP][+-]|[\w.])*)
  | (?P<op>.)
''', re.S | re.X)

# a preprocessor line marker: # LINE "FILE" FLAGS (3: a system header)
MARKER = re.compile(r'^#\s*(?:line\s+)?(\d+)\s+"((?:\\.|[^"\\])*)"((?:\s+\d+)*)\s*$')


class Host16Error(Exception):
    pass


def canon(words, keep_double=False):
    """the type of a run of type words on the PC with the Atari816's sizes"""
    w = list(words)
    if 'double' in w and not keep_double:
        return 'float'
    if 'double' in w or 'float' in w or 'char' in w:
        return ' '.join(w)
    nlong = w.count('long')
    uns = 'unsigned' in w
    if nlong >= 2:
        return ('unsigned ' if uns else '') + 'long long'
    if nlong == 1:
        return ('unsigned ' if uns else '') + 'int'
    return ('unsigned ' if uns else '') + 'short'


def num_suffix(s):
    """5L -> 5, 7UL -> 7U, 0x10lu -> 0x10u (LL kept); floating constants as they are"""
    if re.fullmatch(r'(0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*', s):
        m = re.fullmatch(r'(0[xX][0-9a-fA-F]+|[0-9]+)([uUlL]*)', s)
        body, suf = m.group(1), m.group(2)
        if suf.lower().count('l') == 1:
            suf = suf.replace('l', '').replace('L', '')
        return body + suf
    return s


def rewrite(text, native=(), keep_double=False, pack=True):
    """a preprocessed source (CC -E -C) -> the same with the Atari816's types in the
    program's own lines (not the system headers')"""
    native = set(native) | {'main'}
    out = []
    user = True                     # the current line is the program's own
    lines = text.split('\n')
    # the program's tokens, line by line, with the system lines passed through as they are
    toks = []                       # [kind, text, line index]
    for k, ln in enumerate(lines):
        m = MARKER.match(ln)
        if m:
            flags = m.group(3).split()
            user = '3' not in flags
            toks.append(['marker', ln, k, user])
            continue
        if ln.lstrip().startswith('#'):
            toks.append(['pp', ln, k, user])
            continue
        pos = 0
        while pos < len(ln):
            mt = TOKEN.match(ln, pos)
            toks.append([mt.lastgroup, mt.group(), k, user])
            pos = mt.end()
        toks.append(['ws', '', k, user])        # (the line's end)
    native_lines = {t[2] for t in toks if t[0] == 'com' and 'host16: native' in t[1]}
    sig = [i for i, t in enumerate(toks) if t[0] in ('id', 'num', 'str', 'op')]
    keep = set()
    # native regions: main's and --native functions' parameters and return types,
    # va_arg's type
    for n, i in enumerate(sig):
        t = toks[i]
        if t[0] != 'id' or n + 1 >= len(sig) or toks[sig[n + 1]][1] != '(':
            continue
        if t[1] in native or t[1] in ('__builtin_va_arg', 'va_arg'):
            depth, m = 0, n + 1
            while m < len(sig):
                s = toks[sig[m]][1]
                depth += (s == '(') - (s == ')')
                keep.add(sig[m])
                if depth == 0:
                    break
                m += 1
            if t[1] in native:
                m = n - 1
                while m >= 0 and toks[sig[m]][0] == 'id' and \
                        toks[sig[m]][1] in TYPEWORDS | {'static', 'extern', 'const', 'inline'}:
                    keep.add(sig[m])
                    m -= 1
    n = 0
    while n < len(sig):
        i = sig[n]
        t = toks[i]
        if not t[3]:
            n += 1                      # (a system header's token, or its macro's)
            continue
        if t[0] == 'num' and i not in keep and t[2] not in native_lines:
            t[1] = num_suffix(t[1])
            n += 1
            continue
        if t[0] != 'id' or t[1] not in TYPEWORDS:
            n += 1
            continue
        m = n
        while m < len(sig) and toks[sig[m]][0] == 'id' and toks[sig[m]][1] in TYPEWORDS:
            m += 1
        run = sig[n:m]
        if not any(j in keep or toks[j][2] in native_lines or not toks[j][3] for j in run):
            words = [toks[j][1] for j in run]
            new = canon(words, keep_double)
            if new != ' '.join(words):
                toks[run[0]][1] = new
                for j in run[1:]:
                    toks[j][1] = ''
                    # (the space after a dropped word stays: harmless)
        n = m
    # the program's structures and unions packed (cc816 pads none): the attribute after
    # the keyword of each one defined here (struct [tag] {); a system header's keep
    # their layout
    if pack:
        for n, i in enumerate(sig):
            t = toks[i]
            if t[0] == 'id' and t[1] in ('struct', 'union') and t[3] and n + 1 < len(sig):
                nx = toks[sig[n + 1]]
                if nx[1] == '{' or (nx[0] == 'id' and n + 2 < len(sig) and
                                    toks[sig[n + 2]][1] == '{'):
                    t[1] += ' __attribute__((packed))'
    # put the lines back together
    cur = None
    buf = []
    for t in toks:
        if t[0] in ('marker', 'pp'):
            if cur is not None:
                out.append(''.join(buf))
                buf, cur = [], None
            out.append(t[1])
            continue
        if cur is not None and t[2] != cur:
            out.append(''.join(buf))
            buf = []
        cur = t[2]
        buf.append(t[1])
    if cur is not None:
        out.append(''.join(buf))
    return '\n'.join(out) + '\n'


PP_ARG = ('-I', '-D', '-U', '-include', '-isystem', '-iquote', '-imacros')


def pp_options(args):
    """the preprocessor's options among CC's arguments"""
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if a in PP_ARG and i + 1 < len(args):
            out += [a, args[i + 1]]
            i += 2
            continue
        if any(a.startswith(p) and len(a) > len(p) for p in ('-I', '-D', '-U')) or \
                a.startswith('-std=') or a in ('-ansi', '-funsigned-char', '-fsigned-char'):
            out.append(a)
        i += 1
    return out


def preprocess(cc, src, ppopts, verbose=False):
    cmd = [cc, '-E', '-C', '-funsigned-char'] + ppopts + [src]
    if verbose:
        print(' '.join(cmd), file=sys.stderr)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='latin-1')
    if r.returncode:
        raise Host16Error(r.stderr.strip() or f'{cc} -E {src} failed')
    return r.stdout


def main(argv):
    native, keep_double, pack, keepdir, verbose = [], False, True, None, False
    i = 0
    while i < len(argv) and argv[i].startswith('-') and argv[i] != '-E':
        a = argv[i]
        if a == '--native' and i + 1 < len(argv):
            native.append(argv[i + 1])
            i += 2
            continue
        if a == '--keep-double':
            keep_double = True
        elif a == '--no-pack':
            pack = False
        elif a == '--keep' and i + 1 < len(argv):
            keepdir = argv[i + 1]
            i += 1
        elif a == '-v':
            verbose = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            print(f'host16.py: unknown option {a}', file=sys.stderr)
            return 2
        i += 1
    rest = argv[i:]
    try:
        if rest[:1] == ['-E']:
            # host16.py -E FILE.c -o OUT.c [options]
            src = out = None
            opts = []
            k = 1
            while k < len(rest):
                if rest[k] == '-o' and k + 1 < len(rest):
                    out = rest[k + 1]
                    k += 2
                    continue
                if rest[k].endswith('.c') and src is None:
                    src = rest[k]
                else:
                    opts.append(rest[k])
                k += 1
            if not src or not out:
                print(__doc__)
                return 2
            cc = os.environ.get('CC', 'cc')
            text = rewrite(preprocess(cc, src, pp_options(opts), verbose), native,
                           keep_double, pack)
            with open(out, 'w', encoding='latin-1') as f:
                f.write(text)
            return 0
        if not rest:
            print(__doc__)
            return 2
        cc, args = rest[0], rest[1:]
        ppopts = pp_options(args)
        tmp = keepdir or tempfile.mkdtemp(prefix='host16')
        os.makedirs(tmp, exist_ok=True)
        try:
            new = []
            seen = {}
            for a in args:
                if a.endswith('.c') and os.path.exists(a):
                    base = os.path.splitext(os.path.basename(a))[0]
                    seen[base] = seen.get(base, 0) + 1
                    name = base if seen[base] == 1 else f'{base}_{seen[base]}'
                    dst = os.path.join(tmp, name + '.i')
                    text = rewrite(preprocess(cc, a, ppopts, verbose), native, keep_double,
                                   pack)
                    with open(dst, 'w', encoding='latin-1') as f:
                        f.write(text)
                    new.append(dst)
                else:
                    new.append(a)
            # (an object named after its source when -c gives no -o: the original name)
            if '-c' in new and '-o' not in new:
                cmds = []
                for a, b in zip(args, new):
                    if a.endswith('.c') and b != a:
                        o = os.path.splitext(os.path.basename(a))[0] + '.o'
                        cmds.append([cc] + EXTRA(keep_double) +
                                    [x for x in new if not x.endswith('.i')] + [b, '-o', o])
            else:
                cmds = [[cc] + EXTRA(keep_double) + new]
            for cmd in cmds:
                if verbose:
                    print(' '.join(cmd), file=sys.stderr)
                r = subprocess.run(cmd)
                if r.returncode:
                    return r.returncode
            return 0
        finally:
            if not keepdir:
                shutil.rmtree(tmp, ignore_errors=True)
    except Host16Error as e:
        print(f'host16.py: {e}', file=sys.stderr)
        return 1


def EXTRA(keep_double):
    return ['-funsigned-char', '-fwrapv', '-fno-strict-aliasing'] + \
        ([] if keep_double else ['-fsingle-precision-constant'])


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
