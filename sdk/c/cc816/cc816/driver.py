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
      -w        no warnings but -Woverflow  -Wall  more warnings (unused variables, ...)
      -Werror   warnings are errors    -WNAME / -Wno-NAME  one warning on / off
      -fsigned-char                    plain char is signed (default: unsigned)
      -fdos-keywords                   far, near and huge are keywords (DOS compilers');
                                       also -fimplicit-int and -fextra-args (C89)
      -std=c89 (c90, gnu89, -ansi)     C89: -fimplicit-int and -fextra-args
      -fimplicit-int                   C89's implicit int: 'f() {...}', 'register x;' a
                                       warning (-Wimplicit-int), not an error
      -fextra-args                     a call with more arguments than the prototype: a
                                       warning (-Wextra-args), not an error
      -fno-merge-strings               each string literal an object of its own
      -fwritable-strings               string literals in the data, each its own
      -fargs-right-to-left             a call's arguments evaluated right to left (DOS's
                                       compilers' order; default: left to right)
      -ffar-wrap                       far pointer arithmetic on the offset alone, the bank
                                       never changes (DOS's far pointers)
      --code small|large, --data near|far   the code and data models (hcc's options)
      --ir      print the IR after optimisation (stderr)
      --time    print the time each phase took (stderr)
      --trace   a Python traceback with an internal compiler error (or CC816_TRACE=1)

Errors and warnings are printed as gcc does: file.c:LINE:COL: error: message.

A whole program: hcc -o PROG.PRG main.c (sdk/c/bin/hcc).
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

from .ctypes816 import CError, Unsupported, ICE, CHAR, MODEL   # noqa: E402
from .diag import Diag                             # noqa: E402
from .front import Front                           # noqa: E402
from . import opt as optmod                        # noqa: E402
from .regalloc import allocate, demote_spills, sr_reach, SR_MAX  # noqa: E402
from .gen import Gen, DP_NAMES, SSCHECK            # noqa: E402
from .peep import peephole, text                   # noqa: E402

# the standard headers (cc816/include), then the SDK's (horizon.h, hgame.h, ...)
INCLUDE = [os.path.join(ROOT, 'include'), os.path.join(SDKC, 'include')]
HORIZON = os.path.abspath(os.environ.get('HORIZON') or os.path.join(SDKC, '..', '..', 'horizon'))

PREDEF = ['__CC816__ 1', '__65816__ 1', '__HORIZON__ 1', '__ATARI816__ 1', '__far _Atomic',
          '__STDC__ 1', '__STDC_VERSION__ 199901L', '__CHAR_UNSIGNED__ 1', '__SIZE_T_INT 1',
          '__near ', '__builtin_expect(x, y) (x)', '__extension__ ',
          # DOS compilers' spellings (docs/c/reference.md, "Compatibility spellings"):
          # _far, __huge and _huge are __far; _near is __near; the calling conventions
          # and the rest are nothing (cc816 has one convention)
          '_far _Atomic', '__huge _Atomic', '_huge _Atomic', '_near __near',
          '__cdecl ', '_cdecl ', '__pascal ', '_pascal ', '__loadds ', '_loadds ',
          '__saveregs ', '_saveregs ', '__interrupt ', '_interrupt ', '__export ',
          '_export ', '_Seg16 ']
# the far data model (hcc --data far): __near is a keyword, __CC816_FAR_DATA__ is defined
PREDEF_FAR = {'__near ': '__near __cc816_near'}
# -fdos-keywords: far, near and huge too (ordinary names in other C)
PREDEF_DOS = ['far _Atomic', 'near __near', 'huge _Atomic']

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

    def on_warning(self, file, line, msg):
        if file in (None, 'unknown') and self.here:
            file, line = self.here
        self.diag.warning(self.place(file, line), msg, 'cpp')

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
    if o.get('large'):
        predef.append('__CC816_LARGE__ 1')      # hcc --code large (docs/c/reference.md)
    if o.get('far_data'):
        predef = [PREDEF_FAR.get(x, x) for x in predef] + ['__CC816_FAR_DATA__ 1']
    if o.get('dos_keywords'):
        predef += PREDEF_DOS
    if o.get('far_wrap'):
        predef.append('__CC816_FAR_WRAP__ 1')   # -ffar-wrap
    if o.get('args_rtl'):
        predef.append('__CC816_ARGS_RTL__ 1')   # -fargs-right-to-left
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
    p.assume_encoding = 'latin-1'           # (included files too: bytes as they are)
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
            'undefs': [], 'includes': [], 'trace': bool(os.environ.get('CC816_TRACE')),
            'large': False}


def compile_c(path, incs=(), defs=(), level=2, dump_ir=False, split=False, opts=None):
    """C file -> (assembly text, warnings); raises CError ('file:line:col: error: ...',
    a line for each error), Unsupported (a feature cc816 does not have: its first error
    is one) or ICE (an internal compiler error).
    split: -> ([(module name, assembly text)], warnings): one module a function (ld65
    then links only the functions a program uses: for libraries)"""
    o = dict(default_opts(), **(opts or {}))
    diag = Diag(o)
    CHAR.signed = bool(o.get('signed_char'))
    MODEL['far_data'] = bool(o.get('far_data'))
    MODEL['far_wrap'] = bool(o.get('far_wrap'))
    MODEL['args_rtl'] = bool(o.get('args_rtl'))
    (MODEL['implicit_int'], MODEL['extra_args'], MODEL['merge_strings'],
     MODEL['writable_strings']) = old_c(o)
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
        MODEL['far_data'] = False
        MODEL.update(implicit_int=False, extra_args=False, merge_strings=True,
                     writable_strings=False)
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
    src, attrs = gnu_attributes(src, diag)
    parser = c_parser.CParser()
    parser.implicit_int_ok = MODEL['implicit_int']
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
    for c, name in parser.implicit_int_decl:
        diag.warning(c, f"type defaults to 'int' in the declaration of '{name}' (C89's "
                        f"implicit int)", 'implicit-int')
    fr = Front(path, diag, parser.implicit_int, attrs)
    # __far objects in banks of their own: a large-model program's file (a library's
    # stay in the main bank, reached by far pointers as any object there)
    fr.unit.fardata = bool(o.get('large')) and not o.get('resident') and not split
    fr.unit.far_model = MODEL['far_data']   # (hcc --data far: f: addressing, the mark)
    fr.compound_end = parser.compound_end
    _CURRENT['front'] = fr
    unit = fr.translate(ast)
    _fail(diag)
    t0 = _tick('front', t0)
    # every function's assembler name (a value of one is its main-bank entry in the large
    # code model)
    unit.funcnames = {sy.asm for sy in fr.scopes[0].values()
                      if getattr(sy, 'kind', None) == 'global' and sy.t.is_func}
    frame_sizes(unit, o, diag)
    _fail(diag)
    if o.get('sigs') is not None:
        # (hcc --check-calls: the unit's calls without a prototype, its definitions and
        # its prototypes, compared across the files by cross_check)
        o['sigs'].append((path, getattr(unit, 'sigs', {})))
        if o.get('front_only'):
            return '', unit.warnings
    large = bool(o.get('large'))
    lines_all = []
    helpers = set()
    for f in unit.funcs:
        _CURRENT['fn'] = getattr(f, 'cname', f.name)
        if getattr(f, 'naked', None) is not None:
            # a naked function: its asm statements alone (no prologue, no epilogue)
            from .gen import asm_size
            f.has_asm = True
            lines_all.append((f, [('L', f.name), ('ASM', f.naked, asm_size(f.naked))], set()))
            continue
        f.has_asm = any(i.op == 'asm' for b in f.blocks for i in b.ins)
        optmod.optimise(f, level)
        t0 = _tick('optimise', t0)
        if dump_ir:
            print(f.dump(), file=sys.stderr)
        allocate(f)
        t0 = _tick('regalloc', t0)
        g = Gen(f, unit, {'level': level, 'large': large, 'sscheck': o.get('sscheck', SSCHECK)})
        lines = g.gen()
        t0 = _tick('codegen', t0)
        lines = peephole(lines, level >= 1)
        t0 = _tick('peephole', t0)
        tries = 0
        while sr_reach(lines) > SR_MAX:
            # a frame out of n,s's reach (8 bits: spills, saved registers and arguments
            # past 255 bytes): its farthest spill slots move to the software stack, then
            # once more all of them (demote_spills); what still does not fit is refused
            reach = sr_reach(lines)
            keep = max(0, f.frame_size - (reach - SR_MAX) - 32) if tries == 0 else 0
            if tries >= 2 or not demote_spills(f, keep):
                diag.error(getattr(f, 'coord', None),
                           f"the function '{getattr(f, 'cname', f.name)}' needs "
                           f"{reach} bytes of hardware stack under its arguments (its "
                           f"parameters and the arguments of its calls: at most "
                           f"{SR_MAX}); split it, or pass a structure's address")
                break
            tries += 1
            allocate(f)
            g = Gen(f, unit, {'level': level, 'large': large,
                              'sscheck': o.get('sscheck', SSCHECK)})
            lines = peephole(g.gen(), level >= 1)
        _fail(diag)
        helpers |= g.helpers
        lines_all.append((f, lines, g.helpers))
    _CURRENT.pop('fn', None)
    if split:
        return emit_split(unit, lines_all, path, large,
                          large and not o.get('resident')), unit.warnings
    return emit(unit, [(f, l) for f, l, _ in lines_all], helpers, path,
                large and not o.get('resident'), large), unit.warnings


def cross_check(units):
    """hcc --check-calls: [(path, unit.sigs)] of every file of a program -> warnings in
    gcc's form. A call without a prototype in one file to a function another file defines
    (its arguments against the definition's parameters: front.sig_mismatch), and a
    prototype in one file that differs from the definition in another (the number of
    parameters, or one's size or kind): both read the arguments from the wrong place,
    and neither compile sees the other file"""
    from .front import sig_mismatch, short_place
    defs = {}
    for path, sg in units:
        for name, d in (sg.get('defs') or {}).items():
            if not d[4]:                        # (not static)
                defs.setdefault(name, d)
    out = []
    for path, sg in units:
        own = sg.get('defs') or {}
        for name, place, sig in sg.get('calls') or ():
            d = defs.get(name)
            if name in own or d is None:
                continue
            for msg in sig_mismatch(name, sig, d[1], d[3], short_place(d[0], place)):
                out.append(f'{place}: warning: {msg} [-Wunprototyped-args]')
        for name, (place, params, variadic) in (sg.get('protos') or {}).items():
            d = defs.get(name)
            if name in own or d is None:
                continue
            dp = short_place(d[0], place)
            if len(params) != len(d[1]) or variadic != d[3]:
                out.append(f"{place}: warning: the prototype of '{name}' takes "
                           f"{len(params)} parameter{'s' if len(params) != 1 else ''}"
                           f"{' and more' if variadic else ''}, but its definition ({dp}) "
                           f"takes {len(d[1])}{' and more' if d[3] else ''} [-Wprototype-mismatch]")
                continue
            for k, (a, p) in enumerate(zip(params, d[1]), 1):
                if a[0] != p[0] or (a[1] == 'float') != (p[1] == 'float'):
                    out.append(f"{place}: warning: the prototype of '{name}' says parameter "
                               f"{k} is {a[2]} ({a[0]} bytes), but its definition ({dp}) "
                               f"reads {p[2]} ({p[0]} bytes): the callers that see this "
                               f"prototype push the wrong thing [-Wprototype-mismatch]")
                    break
    return out


# the software stack's size when hcc does not say (tools/hzc816.py SSTACK, hcc --stack)
SSTACK = 8192
SSTACK_MAX = 0x8000          # the largest one (hcc --stack)
# a frame bigger than this is worth a warning (-Wframe-larger-than)
FRAME_WARN = 1024


def frame_sizes(unit, o, diag):
    """a function's software-stack frame (its arrays, structures, locals whose address is
    taken, the temporaries of structures returned by value) bigger than FRAME_WARN bytes:
    a warning; bigger than the whole software stack (o['sstack'], hcc --stack): an error
    (it would overflow into the heap at every call)"""
    given = o.get('sstack') and o.get('sstack_given', True)
    total = o.get('sstack') if given else SSTACK
    for f in unit.funcs:
        n = sum(s.size for s in f.slots)
        if n <= FRAME_WARN:
            continue
        name = getattr(f, 'cname', f.name)
        where = getattr(f, 'coord', None)
        if not given:
            # (the stack the program links with is not known here: hcc -c without --stack;
            # an error only past the largest stack hcc makes, else the default is named)
            if n > SSTACK_MAX:
                diag.error(where, f"the function '{name}' needs a software-stack frame of "
                                  f"{n:,} bytes, more than the largest software stack "
                                  f"({SSTACK_MAX:,} bytes, hcc --stack): make the big "
                                  f"locals static or global")
            else:
                diag.warning(where, f"the function '{name}' needs a software-stack frame of "
                                    f"{n:,} bytes (the default software stack is "
                                    f"{SSTACK:,} bytes; the program's is what its link says, "
                                    f"hcc --stack N" +
                                    (f": at least {-(-(n + 1024) // 1024) * 1024}"
                                     if n > SSTACK else '') +
                                    "; arrays and structures returned by value are there)",
                             'frame-larger-than')
            continue
        if n > total:
            more = -(-(n + 1024) // 1024) * 1024
            diag.error(where, f"the function '{name}' needs a software-stack frame of {n:,} "
                              f"bytes, more than the whole software stack ({total:,} bytes): "
                              f"make the big locals static or global" +
                              (f", or give hcc --stack {more}" if more <= 0x8000 else ''))
        else:
            diag.warning(where, f"the function '{name}' needs a software-stack frame of "
                                f"{n:,} bytes (the software stack is {total:,} bytes: hcc "
                                f"--stack N; arrays and structures returned by value are "
                                f"there)", 'frame-larger-than')


def _strip_gnu(src):
    # tolerate a few GNU spellings pycparser does not know
    return _GNU_WORDS.sub(lambda m: _GNU_SPELL[m.group(0)], src)


_GNU_SPELL = {'__inline__': 'inline', '__inline': 'inline', '__restrict__': 'restrict',
              '__restrict': 'restrict', '__const__': 'const', '__const': 'const',
              '__signed__': 'signed', '__signed': 'signed', '__volatile__': 'volatile',
              '__volatile': 'volatile', '__typeof__': 'typeof', '__typeof': 'typeof',
              '__alignof__': '_Alignof', '__alignof': '_Alignof'}
_GNU_WORDS = re.compile(r'\b(?:' + '|'.join(sorted(_GNU_SPELL, key=len, reverse=True)) +
                        r')\b')

# GNU attributes: read (and taken out of the text: pycparser does not know them).
# noreturn and naked are used; the ones that change nothing here (packed: structures are
# packed anyway) are ignored; the ones cc816 cannot honour get a warning
_ATTR_USED = {'noreturn', 'naked'}
_ATTR_QUIET = {'unused', 'used', 'packed', 'const', 'pure', 'noinline', 'always_inline',
               'inline', 'gnu_inline', 'artificial', 'format', 'format_arg', 'nonnull',
               'returns_nonnull', 'warn_unused_result', 'deprecated', 'unavailable',
               'malloc', 'cold', 'hot', 'visibility', 'nothrow', 'leaf', 'flatten',
               'may_alias', 'fallthrough', 'sentinel', 'externally_visible', 'optimize',
               'no_instrument_function', 'noclone', 'noipa', 'access', 'alloc_size',
               'assume_aligned', 'designated_init', 'transparent_union', 'mode_unused',
               'no_sanitize', 'retain', 'nonstring', 'warning', 'error', 'copy',
               'target', 'interrupt', 'signal'}
_IDENT = re.compile(r'[A-Za-z_]\w*')
_C_WORDS = {'void', 'char', 'short', 'int', 'long', 'float', 'double', 'signed', 'unsigned',
            '_Bool', 'struct', 'union', 'enum', 'const', 'volatile', 'static', 'extern',
            'inline', 'register', 'auto', 'typedef', 'restrict', '_Noreturn', 'sizeof',
            'return', 'if', 'while', 'for', 'switch', '_Atomic'}


def _skip_literal(src, i):
    """i at a quote: the index after the string or character constant"""
    q = src[i]
    i += 1
    while i < len(src) and src[i] != q:
        i += 2 if src[i] == '\\' else 1
    return i + 1


def _places(src):
    """offset -> 'file:line:col' of the preprocessed text (its #line lines followed)"""
    marks = []
    f, ln = '?', 1
    pos = 0
    for line in src.split('\n'):
        m = re.match(r'#\s*(?:line\s+)?(\d+)\s*(?:"([^"]*)")?', line)
        if m:
            ln = int(m.group(1)) - 1
            f = m.group(2) or f
        marks.append((pos, f, ln))
        pos += len(line) + 1
        ln += 1

    def place(off):
        import bisect
        k = bisect.bisect_right([p for p, _, _ in marks], off) - 1
        p, f, ln = marks[k]
        return f'{f}:{ln}:{off - p + 1}'
    return place


def gnu_attributes(src, diag):
    """__attribute__((...)) taken out of the text (blanks in its place: the lines and
    columns stay) -> (text, {'noreturn': names, 'naked': names}): the functions declared
    where those attributes appear"""
    if '__attribute' not in src:
        return src, {}
    out = list(src)
    found = {'noreturn': set(), 'naked': set()}
    place = None
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c in '"\'':
            i = _skip_literal(src, i)
            continue
        if c == '\n' and src.startswith('#', i + 1):
            i = src.find('\n', i + 1)
            if i < 0:
                break
            continue
        if c != '_' or not src.startswith('__attribute', i) or \
                (i and (src[i - 1].isalnum() or src[i - 1] == '_')):
            i += 1
            continue
        m = re.match(r'__attribute(?:__)?\s*\(', src[i:])
        if not m:
            i += 1
            continue
        start = i
        j = i + m.end()
        depth = 1
        while j < n and depth:
            if src[j] in '"\'':
                j = _skip_literal(src, j)
                continue
            depth += {'(': 1, ')': -1}.get(src[j], 0)
            j += 1
        body = src[i + m.end():j - 1]
        for k in range(start, j):
            if out[k] != '\n':
                out[k] = ' '
        names = []
        for a in _split_attrs(body):
            nm = re.match(r'\s*([A-Za-z_]\w*)', a)
            if nm:
                names.append((nm.group(1).strip('_'), a))
        for name, a in names:
            if name in _ATTR_USED:
                fn = _declared_function(src, start, j)
                if fn:
                    found[name].add(fn)
                continue
            if name in _ATTR_QUIET:
                continue
            if name == 'aligned':
                arg = re.search(r'\(\s*(\d+)\s*\)', a)
                if arg and int(arg.group(1)) <= 1:
                    continue
            place = place or _places(src)
            why = {'aligned': 'cc816 does not align objects (structures are packed, '
                              '_Alignof is 1)',
                   'constructor': "use a function named _INIT_<n>_name (run before main)",
                   'destructor': "use a function named _EXIT_<n>_name (run at exit)",
                   'section': 'the code and data go to the usual segments',
                   'weak': 'ld65 has no weak symbols',
                   'alias': 'ld65 has no aliases: write a function that calls the other',
                   'cleanup': 'call the function yourself where the variable ends'}.get(
                       name, 'cc816 does not know it')
            diag.warning(place(start), f"the attribute '{name}' is ignored: {why}",
                         'attributes')
        i = j
    return ''.join(out), found


def _split_attrs(body):
    """the attributes of (( a, b(1, 2) )) -> ['a', 'b(1, 2)']"""
    body = body.strip()
    if body.startswith('(') and body.endswith(')'):
        body = body[1:-1]
    parts, depth, cur = [], 0, ''
    for ch in body:
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
            continue
        depth += {'(': 1, ')': -1}.get(ch, 0)
        cur += ch
    parts.append(cur)
    return [p for p in parts if p.strip()]


def _declared_function(src, a, b):
    """the name of the function declared by the declaration around src[a:b] (an
    attribute): the first identifier followed by '(' in it, from its start (after the
    last ; { or } before it) to its end (; { or =)"""
    s = a
    while s > 0 and src[s - 1] not in ';{}':
        s -= 1
    e = b
    while e < len(src) and src[e] not in ';{=':
        e += 1
    text = src[s:a] + ' ' * (b - a) + src[b:e]
    for m in _IDENT.finditer(text):
        w = m.group(0)
        if w in _C_WORDS or w.startswith('__attribute'):
            continue
        rest = text[m.end():].lstrip()
        if rest.startswith('('):
            return w
    return None


# a function named _INIT_<n>_name / _EXIT_<n>_name is a constructor
# (run before main) / destructor (run at exit, after the atexit functions): ld65 lists them
# for the startup (rt/crt0.s); n is the order (smaller first)
_CONDES = re.compile(r'^_(INIT|EXIT)_(\d+)_')


def _tag(path):
    import hashlib
    return 'S' + hashlib.md5(os.path.abspath(path).encode()).hexdigest()[:6] + '_'


MAXSEG = 100            # movable segments a module
FARGROUP = 16384        # the far data model: a file's far objects in segments of this size


def movable(f):
    """may a function of the large code model go to any code bank? Not one with asm
    statements (or naked: its assembly may name main-bank addresses, JSL and RTL as it
    likes), and not a constructor or destructor (crt0.s's tables are 16-bit)"""
    return not getattr(f, 'has_asm', False) and not _CONDES.match(getattr(f, 'cname', '') or '')


def far_lines(lines, fname, recs):
    """a movable function's lines: after each instruction with a bank byte (JSL, JML, MVN:
    the banks are known only when the program runs) a label, and the bank byte's address
    recorded (recs: XREL's .faraddr lines, which hcc reads); a jump table's entries 16-bit
    (.loword: the code is linked in a bank above 0)"""
    out = []
    for l in lines:
        if l[0] == 'D' and l[1].startswith('.addr '):
            out.append(('D', f'.word .loword({l[1][6:]})', l[2]))
            continue
        out.append(l)
        if l[0] == 'I' and l[1] not in ('mvn', 'mvp') and len(l) > 2 and \
                str(l[2]).startswith('#^'):
            # a __far object's bank (lda #^name: a 16-bit immediate, the bank its low byte)
            lab = f'L{fname[1:]}_x{len(recs)}'
            out.append(('L', lab))
            recs.append(f'\t.faraddr {lab}-2')
            continue
        if l[0] == 'I' and len(l) > 2 and str(l[2]).startswith('f:'):
            # (far data: long addressing, lda f:name / f:name,x: the bank its last byte)
            lab = f'L{fname[1:]}_x{len(recs)}'
            out.append(('L', lab))
            recs.append(f'\t.faraddr {lab}-1')
            continue
        if l[0] == 'I' and l[1] in ('jsl', 'jml', 'mvn', 'mvp'):
            lab = f'L{fname[1:]}_x{len(recs)}'
            out.append(('L', lab))
            recs.append(f'\t.faraddr {lab}-1')
            if l[1] in ('mvn', 'mvp'):
                recs.append(f'\t.faraddr {lab}-2')
    return out


def emit(unit, funcs, helpers, path='?', far=False, large=False):
    """far: the large code model's movable functions (each in a segment of its own, F<name>,
    which hcc places in a bank); large: the large model (a function's 16-bit address is
    __T<name>: the function itself when it is in the main bank, else a thunk there)"""
    out = ['; generated by cc816', '\t.p816', '\t.smart +', '\t.a16', '\t.i16',
           '\t.importzp ' + ', '.join(DP_NAMES)]
    body = []
    exports = set()
    defined = set()
    recs = []
    fnames = unit.funcnames if large else set()
    body.append('\t.segment "CODE"')
    tops = list(getattr(unit, 'asm', ()))
    tag = _tag(path) if far else ''
    statics_far = []
    # each movable function's segment: its own, or, in a file of more than MAXSEG of them,
    # one for a run of consecutive functions (ca65 takes at most 255 segments a module,
    # ar65 about 128)
    mov = [f for f, _ in funcs if far and movable(f)]
    per = -(-len(mov) // MAXSEG) if len(mov) > MAXSEG else 1
    segname = {}
    for i, f in enumerate(mov):
        g = mov[i - i % per]
        segname[f.name] = 'F' + (tag if g.static else '') + g.name

    def top_asm(upto):
        # file-scope asm statements, where they were among the functions (a .macro must
        # come before its use); the code segment and 16-bit registers again after each
        while tops and tops[0][0] <= upto:
            body.append(tops.pop(0)[1])
            body.extend(['\t.segment "CODE"', '\t.a16', '\t.i16'])
    for k, (f, lines) in enumerate(funcs):
        top_asm(k)
        if not f.static:
            exports.add(f.name)
            m = _CONDES.match(getattr(f, 'cname', ''))
            if m:
                kind = 'constructor' if m.group(1) == 'INIT' else 'destructor'
                body.append(f'\t.{kind} {f.name}, {min(max(int(m.group(2)), 1), 31)}')
        body.append('')
        if far and movable(f):
            body.append(f'\t.segment "{segname[f.name]}"')
            body.append(text(far_lines(lines, f.name, recs)))
            body.append('\t.segment "CODE"')
            if f.static:
                statics_far.append(f.name)
            continue
        if large:
            body.append(f'__T{f.name}:')            # (in the main bank: itself)
            defined.add('__T' + f.name)
            if not f.static:
                exports.add('__T' + f.name)
        body.append(text(lines))
    top_asm(len(funcs) + 1)
    segs = {'RODATA': [], 'DATA': [], 'BSS': []}
    ftag = _tag(path)
    group = {}                  # (the far data model: a far object -> its group's segment)
    if getattr(unit, 'far_model', False):
        # far data: the file's far objects (string literals, constants, __far ones) in
        # groups of about 16 KB, each a segment hcc places in a bank (a segment each would
        # pass ca65's limit of segments in a module); a bigger object is a group alone
        k, used = 0, None
        for d in unit.data:
            if getattr(d, 'far', False):
                if used is not None and used + d.size > FARGROUP:
                    k, used = k + 1, None
                group[d.name] = f'FD{ftag}g{k}'
                used = (used or 0) + d.size
    for d in unit.data:
        if getattr(d, 'far', False):
            # a __far object (the large model): a segment of its own, FD_name (a static
            # one's FD<tag>_name), which hcc places in a bank of far data
            sg = group.get(d.name) or 'FD' + ('' if d.export else ftag) + d.name
            lines = segs.setdefault(sg, [])
        else:
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
                lines.append(f'\t.addr {_so(_hn(it[1], fnames), it[2])}')
            elif it[0] == 'f':
                if getattr(d, 'far', False):
                    # (a far address in far data: its bank byte recorded for the link)
                    lab = f'Lfd_x{len(recs)}'
                    lines.append(f'{lab}:')
                    recs.append(f'\t.faraddr {lab}+2')
                lines.append(f'\t.faraddr {_so(_hn(it[1], fnames), it[2])}')
                lines.append('\t.byte 0')
    for s, l in segs.items():
        if l:
            body.append(f'\t.segment "{s}"')
            body.extend(l)
    text_all = '\n'.join(body)
    words = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text_all))
    # a static function in another bank whose address is taken: its thunk here, in the
    # main bank (THUNK)
    th = [n for n in statics_far if '__T' + n in words]
    if th:
        tl = ['\t.segment "THUNK"']
        for n in th:
            tl += [f'__T{n}:', f'\tjml\t{n}']
            defined.add('__T' + n)
        text_all += '\n' + '\n'.join(tl)
    if recs:
        text_all += '\n\t.segment "XREL"\n' + '\n'.join(recs)
    # imports: every extern or helper the text mentions
    defined |= {f.name for f, _ in funcs} | {d.name for d in unit.data}
    known = set(unit.externs) | helpers | {'__fpt', '__abs0'} | {'__T' + n for n in fnames}
    imports = sorted(known & words - defined)
    if imports:
        out.append('\t.import ' + ', '.join(imports))
    if exports:
        out.append('\t.export ' + ', '.join(sorted(exports)))
    # the code model: a link of objects made for different ones fails (hcc says why)
    out.append('\t.forceimport __cc816_' + ('largefar' if getattr(unit, 'far_model', False)
                                             else 'large' if large else 'small'))
    # a unit with floating point that calls a printf (or gives a float to any variadic
    # function: a printf wrapper) links printf's float conversions, one that calls a scanf
    # scanf's (rt/fp_hookp.s, fp_hooks.s: a constructor installs them); the
    # library's own units (split) do not
    if getattr(unit, 'float_printf', False):
        out.append('\t.forceimport __cc816_fmtf')
    if getattr(unit, 'float_scanf', False):
        out.append('\t.forceimport __cc816_scanf')
    # the same for long long: printf's and scanf's %lld (rt/ll_hookp.s, ll_hooks.s)
    if getattr(unit, 'll_printf', False):
        out.append('\t.forceimport __cc816_fmtll')
    if getattr(unit, 'll_scanf', False):
        out.append('\t.forceimport __cc816_scanll')
    return '\n'.join(out) + '\n' + text_all + '\n'


def _hn(name, fnames):
    return '__T' + name if name in fnames else name


_WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')


def emit_split(unit, funcs, path, large=False, far=False):
    """the unit as several modules: one a function (with the string literals only it
    uses), and one with the file's data and its constructors and destructors (so they
    are linked whenever the data is). Names private to the file (statics, literals) get a
    file-unique prefix and are exported, so the modules can reach each other.
    far (the large code model, a library that is not resident): each movable function in a
    segment of its own (F<name>, or F<tag><name> for a static one: hcc places it in any
    code bank, as a program's own); its 16-bit address __T<name> is then hcc's (a thunk
    or the function), a static one's a thunk in its module (THUNK) when it is used. A
    resident library's functions are all in the main bank: __T<name> is the function"""
    tag = _tag(path)
    fnames = unit.funcnames if large else set()
    private = {f.name for f, _, _ in funcs if f.static} | \
        {d.name for d in unit.data if not d.export}
    if large:
        private |= {'__T' + f.name for f, _, _ in funcs if f.static}
    ren = {n: tag + n for n in private}
    mov = {f.name for f, _, _ in funcs if far and movable(f) and
           not (_CONDES.match(getattr(f, 'cname', '')) and not f.static)}
    recs_of = {}                # a movable function -> its XREL lines

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
                out.append(f'\t.addr {_so(_hn(it[1], fnames), it[2])}')
            elif it[0] == 'f':
                out.append(f'\t.faraddr {_so(_hn(it[1], fnames), it[2])}')
                out.append('\t.byte 0')
        return out

    texts = {}
    for f, lines, _ in funcs:
        if f.name in mov:
            recs_of[f.name] = []
            texts[f.name] = text(far_lines(lines, f.name, recs_of[f.name]))
        else:
            texts[f.name] = (f'__T{f.name}:\n' if large else '') + text(lines)
    # the static movable functions whose 16-bit address is used (in the file's code or
    # data): a thunk each
    used = set()
    for t in texts.values():
        used |= set(_WORD.findall(t))
    for d in unit.data:
        for it in d.items:
            if it[0] in ('w', 'f'):
                used.add(_hn(it[1], fnames))
    thunked = {f.name for f, _, _ in funcs if f.name in mov and f.static and
               '__T' + f.name in used}
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
    if large:
        defined_all |= {'__T' + f.name for f, _, _ in funcs}

    def module(name, code, data, helpers, condes=(), fn=None):
        body = []
        for c in condes:
            body.append(c)
        if code and fn in mov:
            f = fn
            body.append(f'\t.segment "F{ren.get(f, f) if f in private else f}"')
            body.append(code)
            if f in thunked:
                body += ['\t.segment "THUNK"', f'__T{f}:', f'\tjml\t{f}']
            if recs_of.get(f):
                body.append('\t.segment "XREL"')
                body += recs_of[f]
        elif code:
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
            {'__fpt', '__abs0'} | {'__T' + n for n in fnames}
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
        name_defs = [f.name] + [d.name for d in own.get(f.name, [])] + \
            (['__T' + f.name] if large and (f.name not in mov or f.name in thunked) else [])
        module(f.name.lstrip('_'), texts[f.name], own.get(f.name, []), helpers, fn=f.name)
    data = [d for d in unit.data if not d.name.startswith('L_')] + shared
    if getattr(unit, 'asm', None):
        raise CError(f'{path}: error: asm at file scope is not allowed in a library file '
                     f'(one module a function): put it in a function, or in a .s file')
    if data or condes_funcs:
        name_defs = [d.name for d in data] + [f.name for f, _ in condes_funcs] + \
            (['__T' + f.name for f, _ in condes_funcs] if large else [])
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


def parse_f_flag(a, opts):
    """the -f options (-fsigned-char, -fdos-keywords, -fargs-right-to-left, -ffar-wrap and
    their opposites) into opts; False if a is not one"""
    f = {'-fsigned-char': ('signed_char', True), '-fno-unsigned-char': ('signed_char', True),
         '-funsigned-char': ('signed_char', False), '-fno-signed-char': ('signed_char', False),
         '-fdos-keywords': ('dos_keywords', True),
         '-fargs-right-to-left': ('args_rtl', True), '-fargs-left-to-right': ('args_rtl', False),
         '-ffar-wrap': ('far_wrap', True), '-fno-far-wrap': ('far_wrap', False),
         # old code (docs/c/reference.md, "Old C"): C89's implicit int, calls with more
         # arguments than the prototype, a string literal of its own each time (and in
         # the data: written into)
         '-fimplicit-int': ('implicit_int', True), '-fno-implicit-int': ('implicit_int', False),
         '-fextra-args': ('extra_args', True), '-fno-extra-args': ('extra_args', False),
         '-fmerge-strings': ('merge_strings', True),
         '-fno-merge-strings': ('merge_strings', False),
         '-fwritable-strings': ('writable_strings', True),
         '-fno-writable-strings': ('writable_strings', False),
         '-ansi': ('std89', True)}.get(a)
    if f is None and a.startswith('-std='):
        # -std=c89 (c90, gnu89, gnu90, iso9899:1990, iso9899:199409): -fimplicit-int and
        # -fextra-args; the later standards: cc816's own (C99 with most of C11)
        v = a[5:]
        if v in STD89:
            f = ('std89', True)
        elif v in STD_LATER:
            f = ('std89', False)
    if f is None:
        return False
    opts[f[0]] = f[1]
    return True


STD89 = {'c89', 'c90', 'gnu89', 'gnu90', 'iso9899:1990', 'iso9899:199409'}
STD_LATER = {'c99', 'c9x', 'gnu99', 'gnu9x', 'c11', 'c1x', 'gnu11', 'gnu1x', 'c17', 'c18',
             'gnu17', 'gnu18', 'iso9899:1999', 'iso9899:2011', 'iso9899:2017',
             'iso9899:2018', 'c2x', 'gnu2x', 'c23', 'gnu23'}


def old_c(o):
    """the old-code switches in force: (implicit int, extra arguments a warning, strings
    merged, strings writable). -std=c89 and -fdos-keywords (a DOS program: C89) turn on
    the first two unless -fno-... says otherwise"""
    legacy = bool(o.get('std89') or o.get('dos_keywords'))
    imp = o.get('implicit_int')
    extra = o.get('extra_args')
    writable = bool(o.get('writable_strings'))
    merge = o.get('merge_strings', True) and not writable
    return (legacy if imp is None else bool(imp), legacy if extra is None else bool(extra),
            bool(merge), writable)


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
        elif parse_f_flag(a, opts):
            pass
        elif a in ('--code', '--data') and i + 1 < len(argv):
            i += 1
            if a == '--code':
                opts['large'] = argv[i] == 'large'
            else:
                opts['far_data'] = argv[i] == 'far'
                opts['large'] = opts['large'] or opts['far_data']
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
