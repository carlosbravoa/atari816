"""prog.py - build a test program with cc816 and the SDK's runtime (tools/hzc816.py), and
run programs in emu816: what conform.py and fuzz/divergence.py share."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CC816 = os.path.dirname(HERE)                         # sdk/c/cc816
SDKC = os.path.dirname(CC816)                         # sdk/c
SDK = os.path.dirname(SDKC)
sys.path.insert(0, CC816)
sys.path.insert(0, os.path.join(SDKC, 'tools'))
import hzc816                                         # noqa: E402
from cc816 import driver                              # noqa: E402
from cc816.ctypes816 import CError, Unsupported       # noqa: E402

RUN816 = os.path.join(SDK, 'tools', 'run816.py')
HORIZON = os.path.abspath(os.environ.get('HORIZON') or os.path.join(SDK, '..', 'horizon'))
# the code model ($HZ_CODE: check.py --code large sets it): the large one's results go to
# build/cc816l (the random programs' sources stay in build/cc816, SRCBUILD)
CODE = os.environ.get('HZ_CODE') or 'small'
BUILD = os.path.join(SDKC, 'build', 'cc816l' if CODE == 'large' else 'cc816')
SRCBUILD = os.path.join(SDKC, 'build', 'cc816')


class LinkError(Exception):
    pass


def flags_of(src):
    """a test's compiler options, from a '// FLAGS: ...' line near its start ->
    (include dirs, defines, opts)"""
    incs, defs, opts = [], [], driver.default_opts()
    try:
        head = open(src, encoding='latin-1').read(4000).splitlines()[:40]
    except OSError:
        return incs, defs, opts
    words = []
    for ln in head:
        ln = ln.strip()
        if ln.startswith('// FLAGS:'):
            words += ln[9:].split()
    i = 0
    while i < len(words):
        w = words[i]
        if w.startswith('-D'):
            defs.append(w[2:])
        elif w.startswith('-U'):
            defs.append(w)
        elif w.startswith('-I'):
            incs.append(os.path.join(os.path.dirname(src), w[2:]))
        elif w == '-include':
            i += 1
            opts['includes'].append(os.path.join(os.path.dirname(src), words[i]))
        elif w == '-fsigned-char':
            opts['signed_char'] = True
        else:
            driver.parse_warning_flag(w, opts)
        i += 1
    return incs, defs, opts


def compile_obj(src, obj, level=2):
    """C -> object (raises CError / Unsupported from the compiler, LinkError from ca65);
    a '// FLAGS: ...' line in the source gives the compiler's options"""
    incs, defs, opts = flags_of(src)
    if hzc816.CODE == 'large':
        opts['large'] = True
    asm, _ = driver.compile_c(src, incs, defs, level, opts=opts)
    s = obj[:-2] + '.s'
    with open(s, 'w') as fh:
        fh.write(asm)
    try:
        hzc816.assemble(s, obj)
    except hzc816.HccError as e:
        raise LinkError(str(e))


def link(objs, prg):
    try:
        hzc816.link(objs, prg)
    except hzc816.HccError as e:
        raise LinkError(str(e))


def build(src, prg, level=2):
    obj = prg[:-4] + '.o'
    compile_obj(src, obj, level)
    link([obj], prg)


def run(prg, out, seconds=20, args=None, files=()):
    """run prg in the text shell -> console.txt's text"""
    cmd = [sys.executable, RUN816, prg, '--horizon', HORIZON, '--mode', 'shell',
           '--seconds', str(seconds), '--out', out]
    if args:
        cmd += ['--args', args]
    for f in files:
        cmd += ['--file', f]
    subprocess.run(cmd, capture_output=True, text=True)
    p = os.path.join(out, 'console.txt')
    return open(p, encoding='latin-1').read() if os.path.exists(p) else ''
