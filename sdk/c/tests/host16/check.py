#!/usr/bin/env python3
"""check.py - host16.py's test (make -C sdk/c test): h16test.c built on the PC through
tools/host16.py must find the Atari816's sizes (int 16 bits, long 32, an unsigned before
a macro type, structures packed, double the float) and pass every check; the same file
must compile with cc816 (its checks are what cc816's types give: sizes, wrapping, plain
char unsigned). Needs the PC's C compiler (CC, default cc)."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, '..', '..', 'tools', 'host16.py')


def main():
    cc = os.environ.get('CC', 'cc')
    with tempfile.TemporaryDirectory(prefix='h16') as t:
        exe = os.path.join(t, 'h16test')
        r = subprocess.run([sys.executable, TOOL, '--native', 'cmp', cc, '-O1', '-I', HERE,
                            '-o', exe, os.path.join(HERE, 'h16test.c')],
                           capture_output=True, text=True)
        if r.returncode:
            print(r.stdout + r.stderr)
            print('host16: FAIL (the build)')
            return 1
        r = subprocess.run([exe], capture_output=True, text=True)
        print(r.stdout.strip())
        if r.returncode or 'host16: 0 failures' not in r.stdout:
            print('host16: FAIL')
            return 1
        # -E: the rewritten source: unsigned QUAD (a macro) is an unsigned int
        out = os.path.join(t, 'x.c')
        r = subprocess.run([sys.executable, TOOL, '-E', os.path.join(HERE, 'h16test.c'),
                            '-o', out, '-I', HERE], capture_output=True, text=True)
        text = open(out, encoding='latin-1').read() if not r.returncode else ''
        if r.returncode or 'unsigned int mul(unsigned int a, unsigned short b)' not in \
                ' '.join(text.split()):
            print(r.stderr)
            print('host16: FAIL (-E: unsigned QUAD)')
            return 1
    if old_c(cc):
        return 1
    # cc816 takes the same files (the checks hold there by its types)
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'cc816'))
    from cc816 import driver
    for f, opts in (('h16test.c', None), ('h16old.C', {'implicit_int': True}),
                    ('h16lib.c', {'implicit_int': True})):
        try:
            driver.compile_c(os.path.join(HERE, f), [HERE], [], 2, opts=opts)
        except Exception as e:
            print(f'host16: FAIL (cc816 {f}: {e})')
            return 1
    print('host16: PASS')
    return 0


# what --report must say about h16old.C and h16lib.c: one of each kind of old C mended
OLD_C = [
    ("h16lib.c:10: 'twice' without a type: short (implicit int)"),
    ("h16lib.c:8: 'count' without a type: short (implicit int)"),
    ("h16lib.c:40: 'i' without a type: short (implicit int)"),
    ("h16lib.c:16: 'scale' without a type: short (implicit int)"),
    ("h16lib.c:17: K&R parameter(s) without a declaration: short v, k"),
    ("h16lib.c:22: 'widen': declared without a prototype elsewhere: a K&R definition"),
    ("h16old.h:8: 'box_area': its prototype names struct box before it is declared"),
    ("h16old.h:9: abs: the C library's declaration"),
    ("h16old.h:10: strcpy: the C library's declaration"),
    ("h16old.C:31: 'later' called before its declaration: 'short later();' above"),
    ("h16old.C:50: 'later': declared without a prototype elsewhere: a K&R definition"),
]


def old_c(cc):
    """h16old.C and h16lib.c (old C, a DOS program's) through host16.py: gcc builds them
    without -fpermissive, every check passes with the fix-ups (h16old.fix), two fail
    without them, a fix-up that is not in its file stops the build. -> 1 on a failure"""
    strict = ['-std=gnu99', '-O1', '-Werror=implicit-int',
              '-Werror=implicit-function-declaration', '-Werror=incompatible-pointer-types']
    srcs = [os.path.join(HERE, 'h16old.C'), os.path.join(HERE, 'h16lib.c')]
    with tempfile.TemporaryDirectory(prefix='h16') as t:
        exe = os.path.join(t, 'h16old')
        fix = os.path.join(HERE, 'h16old.fix')
        r = subprocess.run([sys.executable, TOOL, '--report', '--fixups', fix, cc] + strict +
                           ['-I', HERE, '-o', exe] + srcs, capture_output=True, text=True)
        if r.returncode:
            print(r.stdout + r.stderr)
            print('host16: FAIL (old C: the build)')
            return 1
        said = [ln.split('host16.py: ', 1)[-1] for ln in r.stderr.splitlines()]
        said = [os.path.basename(s) for s in said]
        missing = [m for m in OLD_C if not any(s.startswith(m) for s in said)]
        if missing:
            print(r.stderr)
            print(f'host16: FAIL (old C: --report did not say {missing})')
            return 1
        r = subprocess.run([exe], capture_output=True, text=True)
        print(r.stdout.strip())
        if r.returncode or 'host16 old C: 0 failures' not in r.stdout:
            print('host16: FAIL (old C)')
            return 1
        # without the fix-ups: the PC's 32-bit arithmetic, the two checks fail
        r = subprocess.run([sys.executable, TOOL, cc] + strict + ['-I', HERE, '-o', exe] +
                           srcs, capture_output=True, text=True)
        out = subprocess.run([exe], capture_output=True, text=True).stdout \
            if not r.returncode else r.stdout + r.stderr
        if 'host16 old C: 2 failures' not in out or out.count('FAIL line') != 2:
            print(out)
            print('host16: FAIL (old C without the fix-ups: not the two failures)')
            return 1
        # a fix-up no longer in its file: an error, not a silent build
        bad = os.path.join(t, 'bad.fix')
        with open(bad, 'w') as f:
            f.write('[h16old.C]\nif (u == -2) => if (u == (unsigned) -2)\n')
        r = subprocess.run([sys.executable, TOOL, '--fixups', bad, cc] + strict +
                           ['-I', HERE, '-o', exe] + srcs, capture_output=True, text=True)
        if r.returncode == 0 or 'is in h16old.C 0 times, not once' not in r.stderr:
            print(r.stdout + r.stderr)
            print('host16: FAIL (a stale fix-up was not refused)')
            return 1
    print('host16 old C: PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
