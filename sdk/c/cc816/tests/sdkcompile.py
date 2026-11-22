#!/usr/bin/env python3
"""sdkcompile.py - try to compile (not run) every C file of the SDK (sdk/c: lib, ui, game,
tests, examples) with cc816, with the SDK's own headers, and say
what stops the files that do not compile. Assembles the output too (ca65), so a file
counts as compiled only if cc816's assembly is accepted."""
import os
import sys
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import prog                                           # noqa: E402
from prog import driver, CError, Unsupported          # noqa: E402

SDK = prog.SDKC
HOST_ONLY = {'tests/fpu/mathacc.c'}         # programs for the host (gcc), not for Horizon


def main():
    files = []
    for d in ('lib', 'ui', 'game', 'tests', 'examples'):
        for root, _, names in os.walk(os.path.join(SDK, d)):
            files += [os.path.join(root, n) for n in names if n.endswith('.c') and
                      os.path.relpath(os.path.join(root, n), SDK) not in HOST_ONLY]
    files.sort()
    out = os.path.join(prog.BUILD, 'sdkcompile')
    os.makedirs(out, exist_ok=True)
    res = collections.OrderedDict()
    for f in files:
        rel = os.path.relpath(f, SDK)
        incs = [os.path.dirname(f), os.path.join(SDK, 'include')]
        try:
            asm, warns = driver.compile_c(f, incs, [])
            for w in warns:
                print('  warning      ' + w.replace(SDK + '/', ''))
            sp = os.path.join(out, rel.replace('/', '_')[:-2] + '.s')
            open(sp, 'w').write(asm)
            prog.hzc816.assemble(sp, sp[:-2] + '.o')
            res[rel] = ('ok', '')
        except Unsupported as e:
            res[rel] = ('unsupported', e.msg)
        except CError as e:
            res[rel] = ('error', str(e).replace(SDK + '/', '').splitlines()[0][:150])
        except Exception as e:
            res[rel] = ('crash', f'{type(e).__name__}: {e}'[:150])
    n = collections.Counter(s for s, _ in res.values())
    print(f'{len(res)} files: ' + ', '.join(f'{v} {k}' for k, v in n.items()))
    for rel, (s, m) in res.items():
        print(f'  {s:12s} {rel}' + (f': {m}' if m else ''))


if __name__ == '__main__':
    main()
