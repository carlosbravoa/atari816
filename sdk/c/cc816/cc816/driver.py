"""cc816 driver: C -> ca65 assembly (-> objects with ca65). Programs are linked by hcc
(sdk/c/bin/hcc, tools/hzc816.py: the C library, the startup, ld65).

    cc816.py [options] file.c ...         compile each file to FILE.s (default) or FILE.o
      -S        the assembly (.s), the default
      -c        the object (.o: ca65)
      -o FILE   the output (one source)
      -I DIR    include directory      -D NAME[=VAL]  define a macro
      -O0 / -O1 / -O2 (default)        optimisation level
      --ir      print the IR after optimisation (stderr)
      --time    print the time each phase took (stderr)

A whole program: hcc -o PROG.PRG main.c (hcc --cc cc816 is the default).
"""
import io
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                          # sdk/c/cc816
SDKC = os.path.dirname(ROOT)                          # sdk/c
sys.path.insert(0, os.path.join(ROOT, 'vendor'))

from pycparser import c_parser                     # noqa: E402
from pcpp.preprocessor import Preprocessor         # noqa: E402

from .ctypes816 import CError                     # noqa: E402
from .front import Front                           # noqa: E402
from . import opt as optmod                        # noqa: E402
from .regalloc import allocate                     # noqa: E402
from .gen import Gen, DP_NAMES                     # noqa: E402
from .peep import peephole, text                   # noqa: E402

# the standard headers (cc816/include), then the SDK's (horizon.h, hgame.h, ...)
INCLUDE = [os.path.join(ROOT, 'include'), os.path.join(SDKC, 'include')]
HORIZON = os.path.abspath(os.environ.get('HORIZON') or os.path.join(SDKC, '..', '..', 'horizon'))

PREDEF = ['__CC816__ 1', '__65816__ 1', '__HORIZON__ 1', '__ATARI816__ 1', '__far _Atomic',
          '__STDC__ 1', '__STDC_VERSION__ 199901L', '__CHAR_UNSIGNED__ 1', '__SIZE_T_INT 1',
          '__attribute__(x) ', '__near ', '__builtin_expect(x, y) (x)', '__extension__ ']

TIMES = {}


def _tick(what, t0):
    TIMES[what] = TIMES.get(what, 0.0) + time.time() - t0
    return time.time()


class PP(Preprocessor):
    def on_error(self, file, line, msg):
        raise CError(f'{file}:{line}: error: {msg}')

    def on_include_not_found(self, is_malformed, is_system_include, curdir, includepath):
        raise CError(f'include file not found: {includepath}')

    def on_unknown_macro_in_defined_expr(self, tok):
        return False

    def on_directive_unknown(self, directive, toks, ifpassthru, precedingtoks):
        if directive.value in ('warning', 'ident', 'sccs'):
            return None
        if directive.value == 'error':
            src = getattr(directive, 'source', None) or '?'
            msg = ''.join(t.value for t in toks).strip()
            e = CError(msg)
            e.args = (f'{src}:{directive.lineno}: error: #error {msg}',)
            raise e
        return None


def preprocess(path, incs, defs):
    p = PP()
    p.auto_pragma_once_enabled = False      # its guess is wrong for multi-pass headers
    p.line_directive = '#line'
    p.compress = 1
    for d in PREDEF + list(defs):
        p.define(d.replace('=', ' ', 1) if '=' in d and ' ' not in d else
                 (d if ' ' in d else d + ' 1'))
    for i in list(incs) + INCLUDE:
        p.add_path(i)
    with open(path, encoding='latin-1') as fh:
        src = fh.read()
    p.parse(src, source=path)
    out = io.StringIO()
    p.write(out)
    return out.getvalue()


_PARSE = re.compile(r'^(.*?):(\d+):(\d+): (.*)$', re.S)


def compile_c(path, incs=(), defs=(), level=2, dump_ir=False, split=False):
    """C file -> (assembly text, warnings); raises CError ('file:line: error: ...').
    split: -> ([(module name, assembly text)], warnings): one module a function (ld65
    then links only the functions a program uses: for libraries)"""
    t0 = time.time()
    src = preprocess(path, list(incs), list(defs))
    t0 = _tick('preprocess', t0)
    src = _strip_gnu(src)
    try:
        ast = c_parser.CParser().parse(src, path)
    except Exception as e:      # pycparser ParseError: 'file:line:col: before: X'
        m = _PARSE.match(str(e))
        if m:
            raise CError(f'{m.group(1)}:{m.group(2)}: error: syntax error, {m.group(4)}')
        raise CError(f'{path}: error: syntax error: {str(e).split(": ", 1)[-1]}')
    t0 = _tick('parse', t0)
    fr = Front(path)
    unit = fr.translate(ast)
    t0 = _tick('front', t0)
    lines_all = []
    helpers = set()
    for f in unit.funcs:
        optmod.optimise(f, level)
        t0 = _tick('optimise', t0)
        if dump_ir:
            print(f.dump(), file=sys.stderr)
        allocate(f)
        t0 = _tick('regalloc', t0)
        g = Gen(f, unit, {'level': level})
        lines = g.gen()
        t0 = _tick('codegen', t0)
        lines = peephole(lines, level >= 1)
        t0 = _tick('peephole', t0)
        helpers |= g.helpers
        lines_all.append((f, lines, g.helpers))
    if split:
        return emit_split(unit, lines_all, path), unit.warnings
    return emit(unit, [(f, l) for f, l, _ in lines_all], helpers), unit.warnings


def _strip_gnu(src):
    # tolerate a few GNU spellings pycparser does not know
    for a, b in (('__inline__', 'inline'), ('__inline', 'inline'), ('__restrict', 'restrict'),
                 ('__const', 'const'), ('__signed__', 'signed'), ('__volatile__', 'volatile')):
        src = src.replace(a, b)
    return src


# a function named _INIT_<n>_name / _EXIT_<n>_name (vbcc's convention) is a constructor
# (run before main) / destructor (run at exit, after the atexit functions): ld65 lists them
# for the startup (rt/cc816/crt0.s); n is the order (smaller first)
_CONDES = re.compile(r'^_(INIT|EXIT)_(\d+)_')


def emit(unit, funcs, helpers):
    out = ['; generated by cc816', '\t.p816', '\t.smart +', '\t.a16', '\t.i16',
           '\t.importzp ' + ', '.join(DP_NAMES)]
    body = []
    exports = set()
    body.append('\t.segment "CODE"')
    for f, lines in funcs:
        if not f.static:
            exports.add(f.name)
            m = _CONDES.match(getattr(f, 'cname', ''))
            if m:
                kind = 'constructor' if m.group(1) == 'INIT' else 'destructor'
                body.append(f'\t.{kind} {f.name}, {min(max(int(m.group(2)), 1), 31)}')
        body.append('')
        body.append(text(lines))
    segs = {'RODATA': [], 'DATA': [], 'BSS': []}
    for d in unit.data:
        lines = segs[d.section]
        lines.append(f'{d.name}:')
        if d.export:
            exports.add(d.name)
        if d.section == 'BSS':
            lines.append(f'\t.res {d.size}')
            continue
        for it in d.items:
            if it[0] == 'b':
                b = it[1]
                for k in range(0, len(b), 16):
                    lines.append('\t.byte ' + ','.join(f'${x:02X}' for x in b[k:k + 16]))
            elif it[0] == 'w':
                lines.append(f'\t.addr {_so(it[1], it[2])}')
            elif it[0] == 'f':
                lines.append(f'\t.faraddr {_so(it[1], it[2])}')
                lines.append('\t.byte 0')
    for s, l in segs.items():
        if l:
            body.append(f'\t.segment "{s}"')
            body.extend(l)
    text_all = '\n'.join(body)
    # imports: every extern or helper the text mentions
    words = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text_all))
    defined = {f.name for f, _ in funcs} | {d.name for d in unit.data}
    imports = sorted((set(unit.externs) | helpers | {'__fpt', '__abs0'}) & words - defined)
    if imports:
        out.append('\t.import ' + ', '.join(imports))
    if exports:
        out.append('\t.export ' + ', '.join(sorted(exports)))
    # a unit with floating point that calls a printf (or gives a float to any variadic
    # function: a printf wrapper) links printf's float conversions, one that calls a scanf
    # scanf's (rt/cc816/fp_hookp.s, fp_hooks.s: a constructor installs them); the
    # library's own units (split) do not
    if getattr(unit, 'float_printf', False):
        out.append('\t.forceimport __cc816_fmtf')
    if getattr(unit, 'float_scanf', False):
        out.append('\t.forceimport __cc816_scanf')
    return '\n'.join(out) + '\n' + text_all + '\n'


_WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')


def emit_split(unit, funcs, path):
    """the unit as several modules: one a function (with the string literals only it
    uses), and one with the file's data and its constructors and destructors (so they
    are linked whenever the data is). Names private to the file (statics, literals) get a
    file-unique prefix and are exported, so the modules can reach each other."""
    import hashlib
    tag = 'S' + hashlib.md5(os.path.abspath(path).encode()).hexdigest()[:6] + '_'
    private = {f.name for f, _, _ in funcs if f.static} | \
        {d.name for d in unit.data if not d.export}
    ren = {n: tag + n for n in private}

    def rn(text):
        return _WORD.sub(lambda m: ren.get(m.group(0), m.group(0)), text)

    def data_lines(d):
        out = [f'{d.name}:']
        if d.section == 'BSS':
            return out + [f'\t.res {d.size}']
        for it in d.items:
            if it[0] == 'b':
                b = it[1]
                for k in range(0, len(b), 16):
                    out.append('\t.byte ' + ','.join(f'${x:02X}' for x in b[k:k + 16]))
            elif it[0] == 'w':
                out.append(f'\t.addr {_so(it[1], it[2])}')
            elif it[0] == 'f':
                out.append(f'\t.faraddr {_so(it[1], it[2])}')
                out.append('\t.byte 0')
        return out

    texts = {f.name: text(lines) for f, lines, _ in funcs}
    users = {}                  # literal -> the functions that use it
    lits = [d for d in unit.data if d.name.startswith('L_')]
    litnames = {d.name for d in lits}
    for f, _, _ in funcs:
        for w in set(_WORD.findall(texts[f.name])) & litnames:
            users.setdefault(w, set()).add(f.name)
    own = {}                    # function -> its literals
    shared = []
    for d in lits:
        u = users.get(d.name, set())
        if len(u) == 1:
            own.setdefault(next(iter(u)), []).append(d)
        else:
            shared.append(d)
    modules = []
    defined_all = {f.name for f, _, _ in funcs} | {d.name for d in unit.data}

    def module(name, code, data, helpers, condes=()):
        body = []
        for c in condes:
            body.append(c)
        if code:
            body.append('\t.segment "CODE"')
            body.append(code)
        segs = {'RODATA': [], 'DATA': [], 'BSS': []}
        for d in data:
            segs[d.section] += data_lines(d)
        for sg, l in segs.items():
            if l:
                body.append(f'\t.segment "{sg}"')
                body.extend(l)
        txt = rn('\n'.join(body))
        mine = {ren.get(n, n) for n in name_defs}
        words = set(_WORD.findall(txt))
        known = {ren.get(n, n) for n in defined_all} | set(unit.externs) | helpers | \
            {'__fpt', '__abs0'}
        imports = sorted((known & words) - mine)
        head = ['; generated by cc816', '\t.p816', '\t.smart +', '\t.a16', '\t.i16',
                '\t.importzp ' + ', '.join(DP_NAMES)]
        if imports:
            head.append('\t.import ' + ', '.join(imports))
        head.append('\t.export ' + ', '.join(sorted(mine)))
        modules.append((name, '\n'.join(head) + '\n' + txt + '\n'))

    condes_funcs = []
    for f, lines, helpers in funcs:
        m = _CONDES.match(getattr(f, 'cname', ''))
        if m and not f.static:
            condes_funcs.append((f, m))
            continue
        name_defs = [f.name] + [d.name for d in own.get(f.name, [])]
        module(f.name.lstrip('_'), texts[f.name], own.get(f.name, []), helpers)
    data = [d for d in unit.data if not d.name.startswith('L_')] + shared
    if data or condes_funcs:
        name_defs = [d.name for d in data] + [f.name for f, _ in condes_funcs]
        code = []
        cd = []
        helpers = set()
        for f, m in condes_funcs:
            kind = 'constructor' if m.group(1) == 'INIT' else 'destructor'
            cd.append(f'\t.{kind} {f.name}, {min(max(int(m.group(2)), 1), 31)}')
            code.append(texts[f.name])
            helpers |= next(h for g, _, h in funcs if g is f)
            for d in own.get(f.name, []):
                data.append(d)
                name_defs.append(d.name)
        module('data', '\n\n'.join(code), data, helpers, cd)
    return modules


def _so(name, off):
    return name + (f'+{off}' if off > 0 else (f'-{-off}' if off < 0 else ''))


def assemble(asm_path, obj_path, incs=()):
    cmd = ['ca65', '--cpu', '65816', '-I', os.path.join(HORIZON, 'user')]
    for i in incs:
        cmd += ['-I', i]
    r = subprocess.run(cmd + ['-o', obj_path, asm_path], capture_output=True, text=True)
    if r.returncode:
        raise CError(f'{asm_path}: the assembler (ca65) failed:\n{r.stdout}{r.stderr}')


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    mode = 'asm'
    out = None
    incs, defs, files = [], [], []
    level = 2
    dump = timing = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '-S':
            mode = 'asm'
        elif a == '-c':
            mode = 'obj'
        elif a == '-o':
            i += 1
            out = argv[i]
        elif a.startswith('-I'):
            incs.append(a[2:] or argv[i + 1])
            i += 0 if a[2:] else 1
        elif a.startswith('-D'):
            defs.append(a[2:] or argv[i + 1])
            i += 0 if a[2:] else 1
        elif a.startswith('-O'):
            level = int(a[2:] or 2)
        elif a == '--ir':
            dump = True
        elif a == '--time':
            timing = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            files.append(a)
        i += 1
    if not files or (out and len(files) > 1):
        print(__doc__)
        return 2
    try:
        for f in files:
            base = os.path.splitext(os.path.basename(f))[0]
            asm, warns = compile_c(f, incs, defs, level, dump)
            for w in warns:
                print(w, file=sys.stderr)
            asm_path = out if (mode == 'asm' and out) else base + '.s'
            with open(asm_path, 'w') as fh:
                fh.write(asm)
            if mode == 'obj':
                assemble(asm_path, out or base + '.o', incs)
    except CError as e:
        if os.environ.get('CC816_TRACE'):
            raise
        print(str(e), file=sys.stderr)
        return 1
    if timing:
        for k, v in TIMES.items():
            print(f'{k:12s} {v:.2f} s', file=sys.stderr)
    return 0
