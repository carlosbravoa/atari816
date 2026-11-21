#!/usr/bin/env python3
"""conform.py - compile C test programs with cc816 and run them under Horizon in emu816,
in batches (one emulator run per batch: runner.c spawns each test and reports its exit
code).

    conform.py [--batch N] [--out DIR] [--jobs J] [--seconds-per-test S] FILE.c ...

A test passes when it exits with 0 and, if FILE.c.expected exists, its console output
equals that file. Results: OUT/results.json and a summary on stdout.
Statuses: pass, fail (wrong exit code or output), unsupported (cc816 says a feature is
not supported), compile-error (cc816 rejects the program), crash (cc816 raised an
internal error), asm-error (ca65/ld65 rejected cc816's output), killed (the kernel killed
the test), timeout (no end marker: hung)."""
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
OWN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, OWN)
from cc816 import driver                              # noqa: E402
from cc816.ctypes816 import CError, Unsupported      # noqa: E402

RUN816 = os.path.join(OWN, '..', '..', 'tools', 'run816.py')
HORIZON = os.path.join(OWN, '..', '..', '..', 'horizon')


def compile_one(args):
    k, src, out = args
    base = os.path.join(out, f'T{k:03d}')
    try:
        asm, _ = driver.compile_c(src)
    except Unsupported as e:
        return k, 'unsupported', str(e.msg)
    except CError as e:
        return k, 'compile-error', str(e).splitlines()[0][:200]
    except RecursionError:
        return k, 'crash', 'RecursionError'
    except Exception as e:
        tb = traceback.extract_tb(e.__traceback__)[-1]
        return k, 'crash', f'{type(e).__name__}: {e} ({os.path.basename(tb.filename)}:{tb.lineno})'[:200]
    with open(base + '.s', 'w') as fh:
        fh.write(asm)
    try:
        driver.assemble(base + '.s', base + '.o')
        driver.link([base + '.o'], base + '.PRG')
    except CError as e:
        msg = [x for x in str(e).splitlines()[1:] if x.strip()]
        return k, 'asm-error', (msg[0] if msg else str(e))[:200]
    return k, 'built', ''


def run_batch(out, ks, runner, seconds):
    first = ks[0]
    cmd = [sys.executable, RUN816, runner, '--horizon', HORIZON, '--mode', 'shell',
           '--args', f'{first} {len(ks)}', '--seconds', str(seconds),
           '--out', os.path.join(out, f'run-{first}')]
    for k in ks:
        cmd += ['--file', os.path.join(out, f'T{k:03d}.PRG') + f':/T/T{k:03d}.PRG']
    subprocess.run(cmd, capture_output=True, text=True)
    con = open(os.path.join(out, f'run-{first}', 'console.txt'), encoding='latin-1').read()
    res = {}
    for k in ks:
        m = re.search(rf'@@BEGIN {k}\n(.*?)\n@@END {k} (exit|spawn-error) (\d+)', con, re.S)
        if not m:
            if f'@@BEGIN {k}\n' in con:
                res[k] = ('timeout', None, con.split(f'@@BEGIN {k}\n', 1)[1][-300:])
                return res
            return res
        res[k] = (m.group(2), int(m.group(3)), m.group(1))
    return res


def main():
    argv = sys.argv[1:]
    batch, jobs, spt = 40, os.cpu_count() or 4, 1.0
    out = os.path.join(OWN, 'build', 'conform')
    files = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--batch':
            batch = int(argv[i + 1]); i += 1
        elif a == '--out':
            out = argv[i + 1]; i += 1
        elif a == '--jobs':
            jobs = int(argv[i + 1]); i += 1
        elif a == '--seconds-per-test':
            spt = float(argv[i + 1]); i += 1
        else:
            files.append(a)
        i += 1
    os.makedirs(out, exist_ok=True)
    files = sorted(files)
    driver.runtime_lib()
    runner = os.path.join(out, 'RUNNER.PRG')
    asm, _ = driver.compile_c(os.path.join(HERE, 'runner.c'))
    open(os.path.join(out, 'runner.s'), 'w').write(asm)
    driver.assemble(os.path.join(out, 'runner.s'), os.path.join(out, 'runner.o'))
    driver.link([os.path.join(out, 'runner.o')], runner)

    results = {}
    with cf.ProcessPoolExecutor(jobs) as ex:
        for k, st, msg in ex.map(compile_one, [(k, f, out) for k, f in enumerate(files)]):
            results[k] = {'test': files[k], 'status': st, 'msg': msg}
    todo = [k for k in results if results[k]['status'] == 'built']
    while todo:
        ks = todo[:batch]
        r = run_batch(out, ks, runner, int(6 + spt * len(ks)))
        done = 0
        for k in ks:
            if k not in r:
                break
            how, code, text = r[k]
            done += 1
            exp_f = files[k] + '.expected'
            if how == 'timeout':
                results[k].update(status='timeout', msg=text[-120:])
                break
            if how == 'spawn-error':
                results[k].update(status='killed', msg=f'spawn error {code}')
                continue
            if '[kill]' in text:
                results[k].update(status='killed', msg=text[text.index('[kill]'):][:120])
                continue
            want = open(exp_f, encoding='latin-1').read() if os.path.exists(exp_f) else None
            got_ok = want is None or text.strip() == want.strip()
            if code == 0 and got_ok:
                results[k].update(status='pass', msg='')
            else:
                results[k].update(status='fail', msg=(f'exit {code}' if code else '') +
                                  ('' if got_ok else ' output differs: ' + repr(text[:100])))
        if done == 0:
            for k in ks:
                results[k].update(status='timeout', msg='batch produced nothing')
            done = len(ks)
        todo = todo[done:]
    summ = {}
    for r in results.values():
        summ[r['status']] = summ.get(r['status'], 0) + 1
    json.dump(results, open(os.path.join(out, 'results.json'), 'w'), indent=1)
    print(f'{len(files)} tests: ' + ', '.join(f'{v} {k}' for k, v in sorted(summ.items())))
    for k in sorted(results):
        r = results[k]
        if r['status'] != 'pass':
            print(f'  {os.path.basename(r["test"])}: {r["status"]}: {r["msg"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
