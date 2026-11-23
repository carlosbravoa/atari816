#!/usr/bin/env python3
"""check.py - cc816's regression set, run in emu816 under Horizon (make -C sdk/c/cc816 check).

    check.py [--cts DIR] [--fuzz N] [--seeds S1,S2,...] [--features LIST] [--quick]
             [--code small|large|large-far]

--code large: every program built with hcc's large code model (--code large), every
function that can move placed in another bank, in turn in three banks (--main-room 0
--spread 3: the same programs, results in build/cc816-large). --code large-far: the same
with far data (hcc --data far: every data pointer 32 bits, string literals and constants
in far data; results in build/cc816-largefar).

  diag      tests/diag/*.c: the compiler's error and warning messages (tests/diag.py: each
            file says the messages it must give; no emulator)
  regress   tests/regress/*.c: one small program per compiler bug found (each returns 0
            when the bug is not there), plus programs for the parts the random programs
            do not reach; those that say LEVELS: 0 1 2 also at -O0 and -O1
  lang      tests/lang/*.c: a program for each part of C the front end has (K&R
            definitions, designators, compound literals, bit-fields, switches, goto,
            wide strings, the preprocessor, ...), each returns 0
  fuzz      random programs from fuzz/genfuzz.py checked against the host's gcc (seeds 1
            and 2, 200 and 400 programs; --fuzz N programs a seed, --seeds to choose;
            --features: genfuzz.py's shapes, all by default, basic for the original ones)
  fuzzfp    random floating-point programs (genfuzz.py --features basic,float: 100 x seed
            programs a seed, --fuzz N too) checked bit for bit against gcc's SSE single
            precision; --no-float leaves them out
  cts       the c-testsuite (git clone https://github.com/c-testsuite/c-testsuite), when
            --cts DIR (or $CTS) points at a checkout: its single-exec tests

Prints a summary line for each part and every program that did not pass; exit code 1 when
a diag, regress, lang or fuzz program failed, or a c-testsuite program that is not
explained in tests/cts-known.txt (what cc816 does not support is listed there, with the
reason) did not pass.
"""
import os
import subprocess
import sys
import glob
import json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import prog  # noqa: E402

CONFORM = os.path.join(HERE, 'conform', 'conform.py')


def conform(files, out, spt=1.0, slow=(), level=2):
    r = subprocess.run([sys.executable, CONFORM, '--out', out, '--seconds-per-test', str(spt),
                        f'-O{level}']
                       + [x for s in slow for x in ('--slow', s)] + files,
                       capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode:
        print(r.stderr[-2000:])
    res = json.load(open(os.path.join(out, 'results.json')))
    return res


def gen_tag():
    """a tag of the random programs' generator (genfuzz.py, genfeat.py): a changed
    generator makes its programs again (the folders are kept between runs)"""
    import hashlib
    h = hashlib.md5()
    for f in ('genfuzz.py', 'genfeat.py'):
        h.update(open(os.path.join(HERE, 'fuzz', f), 'rb').read())
    return h.hexdigest()[:6]


def drop_old(prefix, keep):
    """the folders of earlier generators' programs (prefix*), but keep"""
    import shutil
    for d in glob.glob(os.path.join(prog.SRCBUILD, prefix + '*')):
        if d != keep and os.path.isdir(d):
            shutil.rmtree(d, ignore_errors=True)


def main():
    a = sys.argv[1:]
    cts = os.environ.get('CTS')
    count, seeds, feats = None, [1, 2], 'all'
    flt = True
    code = 'small'
    i = 0
    while i < len(a):
        if a[i] == '--cts':
            cts = a[i + 1]; i += 2
        elif a[i] == '--fuzz':
            count = int(a[i + 1]); i += 2
        elif a[i] == '--seeds':
            seeds = [int(x) for x in a[i + 1].split(',')]; i += 2
        elif a[i] == '--features':
            feats = a[i + 1]; i += 2
        elif a[i] == '--quick':
            count = 50; i += 1
        elif a[i] == '--no-float':
            flt = False; i += 1
        elif a[i] == '--code':
            code = a[i + 1]; i += 2
        else:
            sys.exit(__doc__)
    if code not in ('small', 'large', 'large-far'):
        sys.exit('check.py: --code is small, large or large-far')
    if code == 'large-far':
        # the far data model (hcc --code large --data far): every data pointer far, string
        # literals and constants in far data; the functions spread as in the large model
        os.environ.update(HZ_CODE='large', HZ_DATA='far', HZ_MAIN_ROOM='0', HZ_SPREAD='3')
        prog.CODE = prog.hzc816.CODE = 'large'
        prog.hzc816.DATA = 'far'
        prog.BUILD = os.path.join(prog.SDKC, 'build', 'cc816-largefar')
        print('(the far data model: hcc --code large --data far --main-room 0 --spread 3)')
    elif code == 'large':
        # every program in the large code model, every function that can move in another
        # bank, in turn in three banks: calls, pointers, helpers, switch tables and setjmp
        # cross banks even in small programs (each one file: its other banks after the o65)
        os.environ.update(HZ_CODE='large', HZ_MAIN_ROOM='0', HZ_SPREAD='3')
        prog.CODE = prog.hzc816.CODE = 'large'
        prog.BUILD = os.path.join(prog.SDKC, 'build', 'cc816-large')
        print('(the large code model: hcc --code large --main-room 0 --spread 3)')
    bad = 0
    print('== diag')
    r = subprocess.run([sys.executable, os.path.join(HERE, 'diag.py')], capture_output=True,
                       text=True)
    print(r.stdout.strip())
    if r.returncode:
        print(r.stderr[-2000:])
        bad += 1
    for part in ('regress', 'lang'):
        print(f'== {part}')
        files = sorted(glob.glob(os.path.join(HERE, part, '*.c')))
        res = conform(files, os.path.join(prog.BUILD, part))
        bad += sum(1 for r in res.values() if r['status'] != 'pass')
    # the programs that say "LEVELS: 0 1 2" (code whose shape differs between the levels:
    # division by constants, shifts, compares) at -O0 and -O1 too
    lv = [f for f in sorted(glob.glob(os.path.join(HERE, 'regress', '*.c')))
          if 'LEVELS: 0 1 2' in open(f, encoding='latin-1').read()]
    for level in (0, 1):
        print(f'== regress -O{level} (LEVELS)')
        res = conform(lv, os.path.join(prog.BUILD, f'regress-O{level}'), level=level)
        bad += sum(1 for r in res.values() if r['status'] != 'pass')
    for seed in seeds:
        n = count or 200 * seed
        print(f'== fuzz, seed {seed}: {n} programs')
        src = os.path.join(prog.SRCBUILD, f'fuzzsrc{seed}-{n}-{feats.replace(",", "+")}-{gen_tag()}')
        if len(glob.glob(os.path.join(src, 'fz*.c'))) < n * 9 // 10:
            # (a run stopped half-way leaves a partial folder: made again; genfuzz skips the
            # few programs gcc's run rejects, so a full folder may hold a little less than n)
            import shutil
            shutil.rmtree(src, ignore_errors=True)
            drop_old(f'fuzzsrc{seed}-{n}-{feats.replace(",", "+")}', src)
            subprocess.run([sys.executable, os.path.join(HERE, 'fuzz', 'genfuzz.py'), src, str(n),
                            str(seed), '--features', feats], check=True, capture_output=True)
        res = conform(sorted(glob.glob(os.path.join(src, 'fz*.c'))),
                      os.path.join(prog.BUILD, f'fuzz{seed}'), 2)
        bad += sum(1 for r in res.values() if r['status'] != 'pass')
    for seed in seeds if flt else ():
        n = (count // 2 if count else 100 * seed)
        print(f'== fuzz float, seed {seed}: {n} programs')
        src = os.path.join(prog.SRCBUILD, f'fuzzfpsrc{seed}-{n}-{gen_tag()}')
        if len(glob.glob(os.path.join(src, 'fz*.c'))) < n * 9 // 10:
            import shutil
            shutil.rmtree(src, ignore_errors=True)
            drop_old(f'fuzzfpsrc{seed}-{n}', src)
            subprocess.run([sys.executable, os.path.join(HERE, 'fuzz', 'genfuzz.py'), src, str(n),
                            str(seed), '--features', 'basic,float'], check=True,
                           capture_output=True)
        res = conform(sorted(glob.glob(os.path.join(src, 'fz*.c'))),
                      os.path.join(prog.BUILD, f'fuzzfp{seed}'), 4)
        bad += sum(1 for r in res.values() if r['status'] != 'pass')
    if cts:
        print('== c-testsuite')
        # (00040.c, 8 queens by brute force, is right but needs about 260 emulated
        # seconds: 1.5 million calls of its check function)
        # (with far data its int * board costs more: 00040.c needs more than 400 seconds)
        res = conform(sorted(glob.glob(os.path.join(cts, 'tests', 'single-exec', '*.c'))),
                      os.path.join(prog.BUILD, 'cts'),
                      slow=['00040.c=' + ('900' if code == 'large-far' else '400')])
        known = {}
        for ln in open(os.path.join(HERE, 'cts-known.txt')):
            if ln.strip() and not ln.startswith('#'):
                f, why = ln.split(None, 1)
                known[f] = why.strip()
        counted = [r for r in res.values() if r['status'] != 'pass'
                   and os.path.basename(r['test']) not in known]
        passed_known = sorted(os.path.basename(r['test']) for r in res.values()
                              if r['status'] == 'pass' and os.path.basename(r['test']) in known)
        print(f'(not counted, explained in tests/cts-known.txt: '
              f'{", ".join(sorted(known))})')
        if passed_known:
            print(f'(listed in tests/cts-known.txt but passed: {", ".join(passed_known)})')
        print(f'c-testsuite: {sum(1 for r in res.values() if r["status"] == "pass")} of '
              f'{len(res)} pass; {len(counted)} wrong, crashed or hung')
        bad += len(counted)
    print('CC816 CHECK ' + ('PASSED' if not bad else f'FAILED ({bad})'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
