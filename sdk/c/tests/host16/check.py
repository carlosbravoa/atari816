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
    # cc816 takes the same file (the checks hold there by its types)
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'cc816'))
    from cc816 import driver
    try:
        driver.compile_c(os.path.join(HERE, 'h16test.c'), [HERE], [], 2)
    except Exception as e:
        print(f'host16: FAIL (cc816: {e})')
        return 1
    print('host16: PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
