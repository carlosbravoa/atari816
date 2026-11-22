"""cc816 driver: C -> ca65 assembly (-> objects with ca65). Programs are linked by hcc
(sdk/c/bin/hcc, tools/hzc816.py: the C library, the startup, ld65).

    cc816.py [options] file.c ...         compile each file to FILE.s (default) or FILE.o
      -S        the assembly (.s), the default
      -c        the object (.o: ca65)
      -E        preprocess only (to stdout, or -o FILE)
      -o FILE   the output (one source)
      -I DIR    include directory      -D NAME[=VAL]  define a macro   -U NAME  undefine
      -include FILE                    include FILE before the source
      -O0 / -O1 / -O2 (default)        optimisation level
      -w        no warnings            -Wall  more warnings (unused variables, ...)
      -Werror   warnings are errors    -WNAME / -Wno-NAME  one warning on / off
      -fsigned-char                    plain char is signed (default: unsigned)
      --ir      print the IR after optimisation (stderr)
      --time    print the time each phase took (stderr)
      --trace   a Python traceback with an internal compiler error (or CC816_TRACE=1)

Errors and warnings are printed as gcc does: file.c:LINE:COL: error: message.

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
from pcpp.parser import OutputDirective, Action    # noqa: E402

from .ctypes816 import CError, Unsupported, ICE, CHAR   # noqa: E402
from .diag import Diag                             # noqa: E402
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
    """pcpp, with its errors and warnings in the diagnostics (the preprocessing goes on
    after an error, so that all of them are reported)"""
    def __init__(self, diag):
        super().__init__()
        self.diag = diag
        self.here = None            # the directive being done: (file, line)
        self.texts = {}             # a file's text (for the column of a message)
        self.pushed = {}            # #pragma push_macro's saved macros

    def parsegen(self, input, source=None, abssource=None):
        for k in (source, abssource):
            if k:
                self.texts[k] = input
        for tok in super().parsegen(input, source, abssource):
            yield tok

    def col(self, file, line, tok=None):
        """the column of a token (or of the first character of a line that is not a
        space) in a file"""
        text = self.texts.get(file)
        if text is None:
            for k, v in self.texts.items():
                if k and file and os.path.abspath(k) == os.path.abspath(file):
                    text = v
                    break
        if text is None:
            return 1
        lp = getattr(tok, 'lexpos', None) if tok is not None else None
        if isinstance(lp, int) and 0 <= lp <= len(text):
            return lp - text.rfind('\n', 0, lp)
        lines = text.split('\n')
        if 0 < line <= len(lines):
            t = lines[line - 1]
            return len(t) - len(t.lstrip()) + 1
        return 1

    def place(self, file, line, tok=None):
        return f'{file}:{line}:{self.col(file, line, tok)}' if line else f'{file}'

    def on_error(self, file, line, msg):
        if file in (None, 'unknown') and self.here:
            file, line = self.here
        self.diag.error(self.place(file, line), _pp_message(msg))

    def on_directive_handle(self, directive, toks, ifpassthru, precedingtoks):
        self.here = (getattr(directive, 'source', None) or '?', directive.lineno)
        return super().on_directive_handle(directive, toks, ifpassthru, precedingtoks)

    def on_include_not_found(self, is_malformed, is_system_include, curdir, includepath):
        place = self.place(*self.here) if self.here else None
        if is_malformed:
            self.diag.error(place, f'#include needs "file" or <file>, not {includepath}')
        else:
            self.diag.error(place, f'cannot find the include file {includepath} (-I DIR adds '
                                   f'a folder to look in)')
        raise OutputDirective(Action.IgnoreAndRemove)

    def on_unknown_macro_in_defined_expr(self, tok):
        return False

    def on_directive_unknown(self, directive, toks, ifpassthru, precedingtoks):
        d = directive.value
        place = self.place(getattr(directive, "source", None) or "?", directive.lineno, directive)
        msg = ''.join(t.value for t in toks).strip()
        if d == 'error':
            self.diag.error(place, f'#error {msg}')
            raise OutputDirective(Action.IgnoreAndRemove)
        if d == 'warning':
            self.diag.warning(place, f'#warning {msg}', 'cpp')
            raise OutputDirective(Action.IgnoreAndRemove)
        if d in ('ident', 'sccs', 'assert', 'unassert'):
            raise OutputDirective(Action.IgnoreAndRemove)
        if d == 'include_next':
            self.diag.error(place, 'cc816 does not support #include_next')
            raise OutputDirective(Action.IgnoreAndRemove)
        if d == 'pragma':
            words = [t.value for t in toks if t.type not in self.t_WS]
            if words[:1] in (['push_macro'], ['pop_macro']) and len(words) >= 4 and \
                    words[1] == '(' and words[2][:1] == '"':
                # #pragma push_macro("name") / pop_macro("name"): the macro kept and
                # put back (gcc, MSVC)
                name = words[2][1:-1]
                stack = self.pushed.setdefault(name, [])
                if words[0] == 'push_macro':
                    stack.append(self.macros.get(name))
                elif stack:
                    m = stack.pop()
                    if m is None:
                        self.macros.pop(name, None)
                    else:
                        self.macros[name] = m
                raise OutputDirective(Action.IgnoreAndRemove)
            return None
        self.diag.error(place, f'unknown preprocessor directive #{d}')
        raise OutputDirective(Action.IgnoreAndRemove)

    def evalexpr(self, tokens):
        return super().evalexpr(self.has_include(tokens))

    def has_include(self, tokens):
        """__has_include("file") / __has_include(<file>) -> 1 or 0; defined(__has_include)
        is 1"""
        import copy
        out = []
        i = 0
        vals = [t.value for t in tokens]
        while i < len(tokens):
            t = tokens[i]
            if t.value == 'defined':
                j = i + 1
                while j < len(tokens) and tokens[j].value in ('(', ' ', '\t'):
                    j += 1
                if j < len(tokens) and tokens[j].value == '__has_include':
                    k = j + 1
                    while k < len(tokens) and tokens[k].value in (')', ' ', '\t'):
                        k += 1
                    one = copy.copy(t)
                    one.type, one.value = self.t_INTEGER, '1'
                    out.append(one)
                    i = k
                    continue
            if t.value in ('__has_include', '__has_include_next'):
                try:
                    a = vals.index('(', i)
                    b = vals.index(')', a)
                except ValueError:
                    self.on_error(t.source, t.lineno, '__has_include needs ("file") or (<file>)')
                    return tokens
                name = ''.join(vals[a + 1:b]).strip()
                found = 0
                if len(name) > 2 and name[0] in '<"':
                    fn = name[1:-1]
                    dirs = (self.path if name[0] == '<' else self.temp_path + self.path) + ['']
                    found = int(any(os.path.isfile(os.path.join(d, fn)) for d in dirs))
                one = copy.copy(t)
                one.type, one.value = self.t_INTEGER, str(found)
                out.append(one)
                i = b + 1
                continue
            out.append(t)
            i += 1
        return out


def _pp_message(msg):
    """pcpp's messages in the compiler's words"""
    msg = ' '.join(msg.split())
    m = re.match(r'^Unterminated (#\s*\w+)', msg)
    if m:
        return f"this {m.group(1).replace(' ', '')} has no #endif"
    m = re.match(r'^Misplaced #(\w+)', msg)
    if m:
        return f'#{m.group(1)} without an #if before it'
    m = re.match(r'^Macro (\w+) requires (\d+) arguments? but was passed (\d+)', msg)
    if m:
        return f'the macro {m.group(1)} takes {m.group(2)} arguments, not {m.group(3)}'
    m = re.match(r'^Macro (\w+) must have at least (\d+)', msg)
    if m:
        return f'the macro {m.group(1)} takes at least {m.group(2)} arguments'
    if msg.startswith('Could not evaluate expression'):
        return '#if or #elif: the expression cannot be computed (' + msg.split(' due to ', 1)[-1] + ')'
    return msg


def preprocess(path, incs, defs, diag=None, opts=None):
    """the source preprocessed (text with #line lines); errors go to diag"""
    o = opts or {}
    diag = diag if diag is not None else Diag(o)
    p = PP(diag)
    p.auto_pragma_once_enabled = False      # its guess is wrong for multi-pass headers
    p.line_directive = '#line'
    p.compress = 1
    tm = time.localtime()
    p.define('__DATE__ "%s %2d %d"' % (time.strftime('%b', tm), tm.tm_mday, tm.tm_year))
    predef = list(PREDEF)
    if o.get('signed_char'):
        predef.remove('__CHAR_UNSIGNED__ 1')
    for u in o.get('undefs') or ():         # (opts' undefs: after the predefined ones)
        if u in [x.split()[0] for x in predef]:
            predef = [x for x in predef if x.split()[0] != u]
    for d in predef + list(defs):
        if d.startswith('-U'):              # -U in the defines' list: in its order
            if d[2:] in p.macros:
                p.undef([_tok(p, d[2:])])
            continue
        p.define(d.replace('=', ' ', 1) if '=' in d and ' ' not in d else
                 (d if ' ' in d else d + ' 1'))
    for u in o.get('undefs') or ():
        if u in p.macros:
            p.undef([_tok(p, u)])
    for i in list(incs) + INCLUDE:
        p.add_path(i)
    try:
        with open(path, encoding='latin-1') as fh:
            src = fh.read()
    except OSError as e:
        raise CError(f'{path}: error: cannot read the file ({e.strerror})')
    pre = ''.join(f'#include "{os.path.abspath(f)}"\n' for f in o.get('includes') or ())
    if pre:
        src = pre + f'#line 1 "{path}"\n' + src
    p.parse(src, source=path)
    out = io.StringIO()
    p.write(out)
    return out.getvalue()


def _tok(p, name):
    t = p.tokenize(name)
    return t[0]


_PARSE = re.compile(r'^(.*?):(\d+):(\d+): (.*)$', re.S)


def default_opts():
    return {'w': False, 'wall': False, 'werror': False, 'wflags': {}, 'signed_char': False,
            'undefs': [], 'includes': [], 'trace': bool(os.environ.get('CC816_TRACE'))}


def compile_c(path, incs=(), defs=(), level=2, dump_ir=False, split=False, opts=None):
    """C file -> (assembly text, warnings); raises CError ('file:line:col: error: ...',
    a line for each error), Unsupported (a feature cc816 does not have: its first error
    is one) or ICE (an internal compiler error).
    split: -> ([(module name, assembly text)], warnings): one module a function (ld65
    then links only the functions a program uses: for libraries)"""
    o = dict(default_opts(), **(opts or {}))
    diag = Diag(o)
    CHAR.signed = bool(o.get('signed_char'))
    old_limit = sys.getrecursionlimit()
    sys.setrecursionlimit(max(old_limit, 20000))
    try:
        return _compile(path, incs, defs, level, dump_ir, split, o, diag)
    except (CError, KeyboardInterrupt):
        raise
    except RecursionError:
        raise CError(f'{path}: error: an expression or a statement is nested too deeply '
                     f'for cc816')
    except Exception as e:
        if o.get('trace'):
            raise
        fn = _CURRENT.get('fn')
        fr = _CURRENT.get('front')
        if fn is None and fr is not None and fr.fn is not None:
            fn = getattr(fr.fn, 'cname', None)
        raise ICE(f'{path}: internal compiler error: {type(e).__name__}: {e}'
                  + (f' (in function {fn})' if fn else '')
                  + ' (please report; CC816_TRACE=1 shows where)')
    finally:
        sys.setrecursionlimit(old_limit)
        CHAR.signed = False
        _CURRENT.clear()


_CURRENT = {}


def _fail(diag):
    """the errors so far as one CError (Unsupported when the first is a missing feature)"""
    if diag.errors:
        msg = '\n'.join(diag.all_lines())
        cls = Unsupported if diag.unsupported else CError
        e = cls(diag.errors[0].split(': error: ', 1)[-1])
        e.args = (msg,)
        e.lines = list(diag.errors)
        raise e


def _compile(path, incs, defs, level, dump_ir, split, o, diag):
    t0 = time.time()
    src = preprocess(path, list(incs), list(defs), diag, o)
    _fail(diag)
    t0 = _tick('preprocess', t0)
    src = _strip_gnu(src)
    parser = c_parser.CParser()
    try:
        ast = parser.parse(src, path)
    except Exception as e:      # pycparser ParseError: 'file:line:col: before: X'
        if not type(e).__name__ == 'ParseError':
            raise
        from .syntax import explain
        m = _PARSE.match(str(e))
        if m:
            place = f'{m.group(1)}:{m.group(2)}:{m.group(3)}'
            msg, unsup = explain(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4))
            diag.error(place, msg, unsup)
        else:
            diag.error(path, f'syntax error: {str(e).split(": ", 1)[-1]}')
        _fail(diag)
    t0 = _tick('parse', t0)
    fr = Front(path, diag, parser.implicit_int)
    fr.compound_end = parser.compound_end
    _CURRENT['front'] = fr
    unit = fr.translate(ast)
    _fail(diag)
    t0 = _tick('front', t0)
    lines_all = []
    helpers = set()
    for f in unit.funcs:
        _CURRENT['fn'] = getattr(f, 'cname', f.name)
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
    _CURRENT.pop('fn', None)
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


def parse_warning_flag(a, opts):
    """-w -Wall -Wextra -Werror -WNAME -Wno-NAME -Werror=NAME into opts; False if a is
    not one"""
    from .diag import WARNINGS
    if a == '-w':
        opts['w'] = True
    elif a in ('-Wall', '-Wextra', '-Weverything'):
        opts['wall'] = True
    elif a == '-Werror':
        opts['werror'] = True
    elif a.startswith('-Werror='):
        opts['werror'] = True
    elif a.startswith('-Wno-'):
        opts.setdefault('wflags', {})[a[5:]] = False
    elif a.startswith('-W') and len(a) > 2:
        opts.setdefault('wflags', {})[a[2:]] = True
    else:
        return False
    return True


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    mode = 'asm'
    out = None
    incs, defs, files = [], [], []
    level = 2
    dump = timing = False
    opts = default_opts()
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '-S':
            mode = 'asm'
        elif a == '-c':
            mode = 'obj'
        elif a == '-E':
            mode = 'pre'
        elif a == '-o':
            i += 1
            out = argv[i]
        elif a == '-include':
            i += 1
            opts['includes'].append(argv[i])
        elif a.startswith('-I'):
            incs.append(a[2:] or argv[i + 1])
            i += 0 if a[2:] else 1
        elif a.startswith('-D'):
            defs.append(a[2:] or argv[i + 1])
            i += 0 if a[2:] else 1
        elif a.startswith('-U'):
            defs.append('-U' + (a[2:] or argv[i + 1]))      # (in order with the -D)
            i += 0 if a[2:] else 1
        elif a.startswith('-O'):
            level = {'0': 0, '1': 1}.get(a[2:], 2)
        elif a in ('-fsigned-char', '-fno-unsigned-char'):
            opts['signed_char'] = True
        elif a in ('-funsigned-char', '-fno-signed-char'):
            opts['signed_char'] = False
        elif parse_warning_flag(a, opts):
            pass
        elif a == '--ir':
            dump = True
        elif a == '--time':
            timing = True
        elif a == '--trace':
            opts['trace'] = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            print(f'cc816: unknown option {a} (cc816.py -h lists them)', file=sys.stderr)
            return 2
        else:
            files.append(a)
        i += 1
    if not files or (out and len(files) > 1):
        print(__doc__)
        return 2
    bad = 0
    for f in files:
        base = os.path.splitext(os.path.basename(f))[0]
        try:
            if mode == 'pre':
                diag = Diag(opts)
                text = preprocess(f, incs, defs, diag, opts)
                for w in diag.all_lines():
                    print(w, file=sys.stderr)
                if diag.errors:
                    bad += 1
                    continue
                if out:
                    with open(out, 'w') as fh:
                        fh.write(text)
                else:
                    sys.stdout.write(text)
                continue
            asm, warns = compile_c(f, incs, defs, level, dump, opts=opts)
            for w in warns:
                print(w, file=sys.stderr)
            asm_path = out if (mode == 'asm' and out) else base + '.s'
            with open(asm_path, 'w') as fh:
                fh.write(asm)
            if mode == 'obj':
                assemble(asm_path, out or base + '.o', incs)
        except CError as e:
            print(str(e), file=sys.stderr)
            bad += 1
    if timing:
        for k, v in TIMES.items():
            print(f'{k:12s} {v:.2f} s', file=sys.stderr)
    return 1 if bad else 0
