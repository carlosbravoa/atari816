#!/usr/bin/env python3
"""diag.py - cc816's diagnostics test set: tests/diag/*.c, each with the messages it must
give, written in the file:

    x = y + 1;      // EXPECT: error: 'y' undeclared    after code: an error on that line
    // EXPECT: 12: error: ...                   on its own line: line 12 of this file
    // EXPECT: inc.h:3: warning: ...            a line of another file (an included one)
    // EXPECT: *: error: ...                    on any line, or without a line
    // FLAGS: -Wall -Werror                     the compiler's options for this file
    // HCC: -o X.PRG                            build the program with hcc (link too); then
    // EXPECT-HCC: undefined: foo               a text hcc must print (and fail)

Then --robust N (default 400) programs of tests/lang and tests/regress, each with one
random change, must give messages (or compile), never an internal compiler error.

A test passes when every EXPECT is said (the text is a part of the message), nothing else
is said (no other error or warning), the compile fails exactly when an error is expected,
and no Python traceback appears. Runs in a few seconds (no emulator).

    diag.py [--robust N] [FILE.c ...]   (default: every tests/diag/*.c, and 400 changed
                                         programs; --robust 0: none)
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CC816 = os.path.dirname(HERE)
sys.path.insert(0, CC816)
from cc816 import driver                                  # noqa: E402
from cc816.ctypes816 import CError, ICE                   # noqa: E402

HCC = os.path.join(os.path.dirname(CC816), 'bin', 'hcc')
_EXP = re.compile(r'^(?:([^\s:]+\.\w+):)?(?:(\d+|\*):)?\s*(error|warning|internal compiler error):\s*(.*?)\s*$')


def parse(path):
    exp, flags, hcc, hexp = [], [], None, []
    for n, ln in enumerate(open(path, encoding='latin-1'), 1):
        k = ln.find('// EXPECT:')
        if k >= 0:
            m = _EXP.match(ln[k + 10:].strip())
            if not m:
                raise SystemExit(f'{path}:{n}: a bad EXPECT')
            fname, lno = m.group(1), m.group(2)
            if lno is None and fname is None and ln[:k].strip():
                lno = n                 # after code: that line
            exp.append((fname, None if lno in (None, '*') else int(lno), m.group(3),
                        m.group(4)))
            continue
        m = re.match(r'^\s*//\s*FLAGS:\s*(.*)$', ln)
        if m:
            flags += m.group(1).split()
        m = re.match(r'^\s*//\s*HCC:\s*(.*)$', ln)
        if m:
            hcc = m.group(1).split()
        m = re.match(r'^\s*//\s*EXPECT-HCC:\s*(.*?)\s*$', ln)
        if m:
            hexp.append(m.group(1))
    return exp, flags, hcc, hexp


def compile_messages(path, flags):
    """-> (the messages, failed, traceback text or None)"""
    opts = driver.default_opts()
    incs, defs = [os.path.dirname(path)], []
    k = 0
    while k < len(flags):
        f = flags[k]
        if f.startswith('-I'):
            incs.append(f[2:])
        elif f.startswith('-D'):
            defs.append(f[2:])
        elif f.startswith('-U'):
            defs.append(f)
        elif f == '-include':
            k += 1
            opts['includes'].append(os.path.join(os.path.dirname(path), flags[k]))
        elif f == '-fsigned-char':
            opts['signed_char'] = True
        elif not driver.parse_warning_flag(f, opts):
            raise SystemExit(f'{path}: unknown FLAGS option {f}')
        k += 1
    try:
        _, warns = driver.compile_c(path, incs, defs, 2, opts=opts)
        return list(warns), False, None
    except ICE as e:
        return str(e).splitlines(), True, None
    except CError as e:
        return str(e).splitlines(), True, None
    except Exception:
        import traceback
        return [], True, traceback.format_exc()


def matches(line, path, e):
    fname, lno, kind, text = e
    m = re.match(r'^(.*?):(\d+)(?::\d+)?: (error|warning): (.*)$', line)
    if kind == 'internal compiler error':
        return 'internal compiler error' in line and text in line
    if not m:
        m2 = re.match(r'^(.*?): (error|warning): (.*)$', line)
        if not m2 or lno is not None:
            return False
        return m2.group(2) == kind and text in m2.group(3)
    if fname is None and lno is None:
        return k_ok(m, kind, text)
    f, n, k, msg = m.group(1), int(m.group(2)), m.group(3), m.group(4)
    want_file = fname or os.path.basename(path)
    if os.path.basename(f) != want_file:
        return False
    if lno is not None and n != lno:
        return False
    return k == kind and text in msg


def k_ok(m, kind, text):
    return m.group(3) == kind and text in m.group(4)


def run_one(path):
    """-> None (passed) or the reason"""
    exp, flags, hcc, hexp = parse(path)
    if hcc is not None:
        with tempfile.TemporaryDirectory(prefix='diag') as tmp:
            args = [a.replace('X.PRG', os.path.join(tmp, 'X.PRG')) for a in hcc]
            r = subprocess.run([sys.executable, HCC] + args + [path], capture_output=True,
                               text=True, cwd=os.path.dirname(path))
        out = r.stdout + r.stderr
        if 'Traceback' in out:
            return 'a Python traceback:\n' + out
        missing = [h for h in hexp if h not in out]
        if missing:
            return f'hcc did not say {missing!r}; it said:\n{out}'
        if hexp and r.returncode == 0:
            return 'hcc did not fail'
        return None
    lines, failed, tb = compile_messages(path, flags)
    if tb:
        return 'a Python traceback:\n' + tb
    if any('Traceback' in ln for ln in lines):
        return 'a Python traceback in the messages'
    bad = []
    for e in exp:
        if not any(matches(ln, path, e) for ln in lines):
            bad.append('not said: ' + (f'{e[0]}:' if e[0] else '') +
                       (f'{e[1]}: ' if e[1] else '') + f'{e[2]}: {e[3]}')
    for ln in lines:
        if not any(matches(ln, path, e) for e in exp):
            bad.append('not expected: ' + ln)
    want_fail = any(e[2] in ('error', 'internal compiler error') for e in exp)
    if failed != want_fail:
        bad.append('the compile ' + ('failed' if failed else 'did not fail'))
    return '\n    '.join(bad) if bad else None


def robust(count, seed=1):
    """the compiler on broken programs: tests/lang/*.c and tests/regress/*.c with one change
    each (a token taken out, doubled, replaced, a line copied): every result must be
    messages or a program, never an internal compiler error -> the failures"""
    import random
    srcs = sorted(glob.glob(os.path.join(HERE, 'lang', '*.c')) +
                  glob.glob(os.path.join(HERE, 'regress', '*.c')))
    rnd = random.Random(seed)
    tok = re.compile(r'[A-Za-z_]\w*|\d+|"(?:\\.|[^"\\])*"|\S')
    words = ['int', '*', '(', ')', '{', '}', ';', ',', '&', 'struct', 'x', '0', '"s"', 'void',
             '[', ']', '->', '.', 'long', 'char *', '=', 'return', 'if', 'case 1:', 'goto L;',
             'float', 'const', 'static', 'extern', 'typedef', 'sizeof', '++', 'unsigned',
             '#if', '#define', '#undef', '#endif', '__far', '...', '{0}', '"\\x"']
    bad = []
    with tempfile.TemporaryDirectory(prefix='robust') as tmp:
        for n in range(count):
            src = rnd.choice(srcs)
            text = open(src, encoding='latin-1').read()
            toks = list(tok.finditer(text))
            m = rnd.choice(toks)
            k = rnd.random()
            if k < 0.3:
                new = text[:m.start()] + text[m.end():]
            elif k < 0.5:
                new = text[:m.start()] + rnd.choice(toks).group(0) + text[m.end():]
            elif k < 0.75:
                new = text[:m.start()] + rnd.choice(words) + ' ' + text[m.end():]
            else:
                lines = text.split('\n')
                lines.insert(rnd.randrange(len(lines)), rnd.choice(lines))
                new = '\n'.join(lines)
            p = os.path.join(tmp, f'm{n}.c')
            open(p, 'w', encoding='latin-1').write(new)
            opts = driver.default_opts()
            try:
                driver.compile_c(p, [os.path.dirname(src)], [], 2, opts=opts)
            except ICE as e:
                bad.append(f'{os.path.basename(src)} changed ({n}): {e}'[:300])
            except CError:
                pass
            except Exception as e:      # (compile_c turns these into ICE: never here)
                bad.append(f'{os.path.basename(src)} changed ({n}): {type(e).__name__}: {e}')
    return bad


def main():
    args = sys.argv[1:]
    count = 400
    if '--robust' in args:
        k = args.index('--robust')
        count = int(args[k + 1])
        del args[k:k + 2]
    files = args or sorted(glob.glob(os.path.join(HERE, 'diag', '*.c')))
    bad = 0
    for f in files:
        why = run_one(f)
        if why:
            bad += 1
            print(f'  {os.path.basename(f)}: FAIL\n    {why}')
    print(f'diag: {len(files) - bad} of {len(files)} pass')
    if count and not args:
        fails = robust(count)
        for f in fails:
            print('  ' + f)
        print(f'robust: {count - len(fails)} of {count} changed programs without an internal '
              f'compiler error')
        bad += len(fails)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
