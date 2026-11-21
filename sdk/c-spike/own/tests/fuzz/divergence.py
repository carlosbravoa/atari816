#!/usr/bin/env python3
"""divergence.py - find the first statement where a failing genfuzz program differs
between the host (gcc) and the target (cc816 in emu816).

    divergence.py FUZZDIR N [FUNC]

FUNC defaults to the first function whose checksum differs (from the target run). Every
statement of that function is followed by a trace line of all its variables; the first
trace line that differs names the statement."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OWN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, OWN)
from cc816 import driver   # noqa: E402

RUN = os.path.join(OWN, 'tests', 'run.sh')


def instrument(src, fn):
    lines = src.split('\n')
    out = []
    inside = False
    vars_ = []
    n = 0
    started = False
    for l in lines:
        if inside and l.startswith('        la[i] ='):
            started = True
        if l.startswith(f'static uint32_t f{fn}(void)'):
            inside = True
        if inside:
            m = re.match(r'    (\w+) (v\d+) = ', l)
            if m:
                vars_.append(m.group(2))
        out.append(l)
        if inside and l.startswith('    ') and (not l.startswith('     ') or l.startswith('        la[i] =')) and l.rstrip().endswith((';', '}')) \
                and not re.match(r'    (int|uint|struct|\w+_t) ', l) and 'return' not in l and vars_ and started:
            n += 1
            vv = vars_ + [f'la[{k}]' for k in range(8)]
            fmt = ' '.join('%lx' for _ in vv)
            args = ', '.join(f'(unsigned long)(uint32_t){v}' for v in vv)
            out.append(f'    printf("T{n}: {fmt} | %lx\\n", {args}, (unsigned long)H);')
        if inside and l == '}':
            inside = False
    return '\n'.join(out), n


def main():
    d, num = sys.argv[1], int(sys.argv[2])
    tsrc = open(os.path.join(d, f'fz{num:04d}.c')).read()
    hsrc = open(os.path.join(d, 'host', f'h{num:04d}.c')).read()
    work = os.path.join(OWN, 'build', 'div')
    os.makedirs(work, exist_ok=True)
    fn = int(sys.argv[3]) if len(sys.argv) > 3 else None
    if fn is None:
        # build and run the target as is to learn which function fails
        open(os.path.join(work, 't.c'), 'w').write(tsrc)
        fn = run_target(work, os.path.join(work, 't.c'))
        m = re.search(r'f(\d+): \d+, want', fn)
        if not m:
            print('no failing function found:', fn[-300:])
            return 1
        fn = int(m.group(1))
    hi, n = instrument(hsrc, fn)
    ti, _ = instrument(tsrc, fn)
    open(os.path.join(work, 'h.c'), 'w').write(hi)
    open(os.path.join(work, 'ti.c'), 'w').write(ti)
    subprocess.run(['gcc', '-fwrapv', '-w', '-o', os.path.join(work, 'h'), os.path.join(work, 'h.c')], check=True)
    hout = subprocess.run([os.path.join(work, 'h')], capture_output=True, text=True).stdout
    tout = run_target(work, os.path.join(work, 'ti.c'))
    ht = re.findall(r'T\d+: .*', hout)
    tt = re.findall(r'T\d+: .*', tout)
    fsrc = [l for l in hi.split('\n')]
    for a, b in zip(ht, tt):
        if a != b:
            k = int(a[1:a.index(':')])
            print(f'f{fn}: first difference after statement {k}')
            print('  host  ', a)
            print('  target', b)
            prev = ht[ht.index(a) - 1] if ht.index(a) else '(start)'
            print('  before', prev)
            # print the statement
            cnt = 0
            for i, l in enumerate(fsrc):
                if l.startswith('    printf("T'):
                    cnt += 1
                    if cnt == k:
                        j = i - 1
                        print('  stmt  ', fsrc[j].strip()[:2000])
                        break
            return 0
    print('traces agree', len(ht), len(tt))
    print(tout[-500:])
    return 0


def run_target(work, c):
    prg = os.path.join(work, 'T.PRG')
    asm, _ = driver.compile_c(c)
    open(c[:-2] + '.s', 'w').write(asm)
    driver.assemble(c[:-2] + '.s', c[:-2] + '.o')
    driver.link([c[:-2] + '.o'], prg)
    subprocess.run([RUN, 'div', prg, '--mode', 'shell', '--seconds', '20'], capture_output=True)
    return open(os.path.join(OWN, 'build', 'run-div', 'console.txt'), encoding='latin-1').read()


if __name__ == '__main__':
    sys.exit(main())
