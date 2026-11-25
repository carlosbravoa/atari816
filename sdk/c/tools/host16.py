#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Carlos Bravo (the Atari816 SDK: sdk/LICENSE)
"""host16.py - build a C program on the PC with the Atari816's integer sizes, to compare
its behaviour with the Atari816's (a port's "host twin").

    host16.py [options] CC [CC options and files ...]
    host16.py [options] -E FILE.c -o OUT.c [CC preprocessor options]

The first form is a compiler wrapper: every .c file among the arguments is preprocessed
with CC (-E -C, the same -I -D -U -include options), its types rewritten as cc816 sees
them, and CC then compiles the rewritten copies with the rest of the arguments:

    host16.py cc -O1 -I src -o build/game16 src/*.c

The second form only writes the rewritten, preprocessed source.

What is rewritten, in the program's own files (the C library's headers, CC's system
headers, are left as they are: their structures and functions keep the PC's types):

    int, signed, short, short int, signed int        -> short           (16 bits)
    unsigned, unsigned int, unsigned short [int]     -> unsigned short
    long, long int, signed long                      -> int             (32 bits)
    unsigned long [int]                              -> unsigned int
    long long, unsigned long long, char              -> as they are
    double, long double                              -> float  (cc816's double is the
                                                        32-bit float; --keep-double: no)
    a constant's L or l suffix (not LL)              -> none   (5L is a 32-bit int)

The source is preprocessed first, so a type word that a macro hides is seen as the
compiler sees it: `#define QUAD long` then `unsigned QUAD` is an `unsigned int`, not an
`unsigned short` followed by a stray word (the fault of the ports' textual rewriters).
CC also gets -funsigned-char (cc816's plain char is unsigned; a -fsigned-char among CC's
options wins, for a program built with cc816 -fsigned-char), -fsingle-precision-constant
(unless --keep-double), -fwrapv and -fno-strict-aliasing, -std=gnu17 when its options
name no standard (gcc 15's C23 reads 'int f();' as 'int f(void)'), and every structure of the
program is packed (as cc816 lays structures
out without padding: __attribute__((packed)) on each one the program defines; --no-pack:
not).

Old C (a DOS program's) that the PC's compiler refuses once int is short, or reads with
its own 32-bit int, is mended in the program's lines (class OldC below; --report lists
each place):

    f(a, b) int a; { ... }        implicit int: short f(a, b) short a; short b; {
    static n;  register i;        short (C89's implicit int)
    g(1); ... int g(int x) {}     called before any declaration: 'short g();' first
    extern int abs(int);          a C library function a system header declares too:
                                  the program's declaration left out
    int f(struct s *);            (struct s not declared yet: the prototype's own type)
                                  written 'int f();'
    void f();  void f(int a) {}   declared without a prototype, defined with short (or
                                  char, float) parameters: a K&R definition, 'void
                                  f(a) short a; {', as C's default promotions need

A source named FILE.C (DOS) is C, as FILE.c. -O, -m and -std reach the preprocessor
too (the C library's headers depend on __OPTIMIZE__).

Fix-ups (--fixups FILE): the places where the PC would compute what the Atari816 does
not, written by the port (a 16-bit unsigned compared with -1, which the PC promotes to a
32-bit int; an object's place next to another). The file holds sections:

    # a comment
    [SAVE.C]                      the lines of the file of that name (or path's end)
    n == -1 => n == (unsigned) -1    OLD => NEW: OLD must be on one line of that file
                                     exactly once, as the preprocessor writes it

A section of a header applies to every source that includes it. The fix-ups are made
before the type rewrite (NEW's `unsigned` is then an unsigned short).

Kept as the PC has them: `main`'s return type and parameters, the type in va_arg(ap,
int) (a short is promoted to int through `...`), every function named with --native NAME
(a callback the C library calls: qsort's comparison, signal's handler; its return type
and parameters), and every token on a line with the comment `host16: native`.

What it cannot make 16 bits: the arithmetic. The PC computes a short + a short in 32
bits; a result stored is cut to 16 as on the Atari816, but a sum compared or passed
before it is stored can differ (cc816 computes in 16 bits). Pointers are 8 bytes on the
PC: a structure holding pointers has another size. printf's %ld with a long (now an int)
works for values that are not negative only. Comparing the two programs' output (a
port's test) shows where it matters.

Options (before CC):
  --native NAME     keep NAME's signature (repeatable)
  --keep-double     double stays double
  --no-pack         structures keep the PC's padding
  --keep DIR        keep the rewritten files in DIR (default: a temporary folder)
  --fixups FILE     the port's fix-ups (above)
  --report          print each place of old C mended (FILE:LINE: what)
  -v                print the commands (and --report)
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

TYPEWORDS = {'int', 'unsigned', 'signed', 'short', 'long', 'char', 'double', 'float'}

TOKEN = re.compile(r'''
    (?P<ws>[ \t\f\v]+|\n)
  | (?P<com>/\*.*?\*/|//[^\n]*)
  | (?P<str>(?:L|u8|u|U)?"(?:\\.|[^"\\\n])*"|(?:L|u|U)?'(?:\\.|[^'\\\n])*')
  | (?P<id>[A-Za-z_]\w*)
  | (?P<num>\.?[0-9](?:[eEpP][+-]|[\w.])*)
  | (?P<op>.)
''', re.S | re.X)

# a preprocessor line marker: # LINE "FILE" FLAGS (3: a system header)
MARKER = re.compile(r'^#\s*(?:line\s+)?(\d+)\s+"((?:\\.|[^"\\])*)"((?:\s+\d+)*)\s*$')


class Host16Error(Exception):
    pass


def canon(words, keep_double=False):
    """the type of a run of type words on the PC with the Atari816's sizes"""
    w = list(words)
    if 'double' in w and not keep_double:
        return 'float'
    if 'double' in w or 'float' in w or 'char' in w:
        return ' '.join(w)
    nlong = w.count('long')
    uns = 'unsigned' in w
    if nlong >= 2:
        return ('unsigned ' if uns else '') + 'long long'
    if nlong == 1:
        return ('unsigned ' if uns else '') + 'int'
    return ('unsigned ' if uns else '') + 'short'


def num_suffix(s):
    """5L -> 5, 7UL -> 7U, 0x10lu -> 0x10u (LL kept); floating constants as they are"""
    if re.fullmatch(r'(0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*', s):
        m = re.fullmatch(r'(0[xX][0-9a-fA-F]+|[0-9]+)([uUlL]*)', s)
        body, suf = m.group(1), m.group(2)
        if suf.lower().count('l') == 1:
            suf = suf.replace('l', '').replace('L', '')
        return body + suf
    return s


STORAGE = {'static', 'extern', 'register', 'auto', 'inline', '__inline', '__inline__'}
QUALS = {'const', 'volatile', '__const', 'restrict', '__restrict', '__restrict__'}
TAGWORDS = {'struct', 'union', 'enum'}
TYPEKW = TYPEWORDS | {'void', '_Bool', '_Complex', '__int128'} | TAGWORDS
KEYWORDS = TYPEKW | STORAGE | QUALS | {
    'typedef', 'if', 'else', 'while', 'for', 'do', 'switch', 'case', 'default', 'break',
    'continue', 'return', 'goto', 'sizeof', '_Alignof', '_Alignas', '_Generic',
    '_Static_assert', '_Noreturn', '_Thread_local', '_Atomic', 'asm', 'typeof'}
# a parameter of one of these types is not what the default promotions give: a prototype
# with it differs from a declaration without one ('f()')
PROMOTED = {'short', 'char', 'float', '_Bool'}


def is_ident(s):
    return bool(s) and (s[0].isalpha() or s[0] == '_') and s.replace('_', 'a').isalnum()


def is_name(s):
    """an identifier that can name something (not a keyword, not GNU's __words)"""
    return is_ident(s) and s not in KEYWORDS and not s.startswith('__')


def is_typetok(s):
    """a token the type rewrite wrote ('unsigned short' is one token) or a type keyword"""
    return bool(s) and all(w in TYPEKW for w in s.split())


class Item:
    """a declaration or a function definition at file scope (or an 'extern' declaration
    in a function): S positions start..end; body: the definition's braces; decl: the
    first function declarator's parentheses"""
    def __init__(self, start, end, body, decl, block=False):
        self.start, self.end, self.body, self.decl, self.block = start, end, body, decl, block


class OldC:
    """Old C that gcc refuses (or reads with other types) once int is short, mended in
    the program's own lines of one preprocessed file. Works on its significant tokens
    after the type rewrite; returns text to put before (pre) and after (post) tokens.
    A file whose brackets do not balance is left as it is.

    - implicit int: a function, a variable or a K&R parameter without a type ('f(a) {',
      'static n;', 'register i;', an undeclared parameter) gets 'short' (C89's int; gcc
      would take its own 32-bit int, which conflicts with a 'short f();' elsewhere);
    - a function called before any declaration (C89's implicit 'int f()'): 'short f();'
      (or the return type of its later declaration) before the definition or declaration
      that holds the first call;
    - a declaration of a C library function that a system header in the file declares
      too ('extern int abs(int);', 'char *strcpy();'): left out (the C library's own is
      in scope; with short for int it would conflict);
    - a prototype whose parameter is a structure first named in the prototype (a type
      of the prototype's own scope: no later definition can match it): written without
      its parameters ('f();');
    - a function declared somewhere without a prototype ('f();', or one of the two above)
      and defined (or declared) with a prototype whose parameter is short, char or float
      (the default promotions differ): the definition becomes a K&R one ('f(a, b) short
      a; char *b; {'), the declaration loses its parameters. Calls then pass promoted
      arguments that the definition converts back, as cc816 does with 16-bit int."""

    def __init__(self, toks, S, native, native_lines, report=None):
        self.toks, self.S = toks, S
        self.native = set(native)
        self.native_lines = native_lines
        self.report = report
        self.pre, self.post = {}, {}

    # the token at S position k
    def tx(self, k):
        return self.toks[self.S[k]][1] if 0 <= k < len(self.S) else ''

    def usr(self, k):
        t = self.toks[self.S[k]]
        return t[3] and t[2] not in self.native_lines

    def add_pre(self, k, s):
        i = self.S[k]
        self.pre[i] = self.pre.get(i, '') + s

    def add_post(self, k, s):
        i = self.S[k]
        self.post[i] = s + self.post.get(i, '')

    def blank(self, a, b):
        for k in range(a, b + 1):
            self.toks[self.S[k]][1] = ''

    def note(self, k, what):
        """what was mended, at the original file's line (the line markers')"""
        if self.report is None:
            return
        if not hasattr(self, 'srcpos'):
            self.srcpos = {}
            f, base, first = '?', 0, 1
            for t in self.toks:
                if t[0] == 'marker':
                    m = MARKER.match(t[1])
                    f, base, first = m.group(2), t[2] + 1, int(m.group(1))
                else:
                    self.srcpos.setdefault(t[2], (f, first + t[2] - base))
        f, ln = self.srcpos.get(self.toks[self.S[k]][2], ('?', 0))
        self.report.append(f'{f}:{ln}: {what}')

    def run(self):
        n = len(self.S)
        self.match = {}
        stack = []
        pair = {')': '(', ']': '[', '}': '{'}
        for k in range(n):
            t = self.tx(k)
            if t in ('(', '[', '{'):
                stack.append(k)
            elif t in pair:
                if not stack or self.tx(stack[-1]) != pair[t]:
                    return {}, {}
                o = stack.pop()
                self.match[o], self.match[k] = k, o
        if stack:
            return {}, {}
        self.items = self.scan_items()
        self.inbody = [False] * n
        for it in self.items:
            if it.body:
                for k in range(it.body[0], it.body[1] + 1):
                    self.inbody[k] = True
        self.items += self.block_externs()
        self.items.sort(key=lambda it: it.start)
        self.typedefs()
        self.sysfuncs()
        self.implicit_int_funcs()
        self.implicit_int_vars()
        self.knr_params()
        self.libc_decls()
        empty = self.empty_decls()
        empty |= self.implicit_calls()
        empty |= self.proto_scope_tags()
        self.unprototype(empty - self.native)
        return self.pre, self.post

    # ---- the file's shape
    def scan_items(self):
        S, tx, m = self.S, self.tx, self.match
        n = len(S)
        items = []
        k = 0
        while k < n:
            start, j = k, k
            knr, body, decl, init = False, None, None, False
            while j < n:
                t = tx(j)
                if t == '=':
                    init = True                 # (an initializer: its calls declare nothing)
                elif t == ',':
                    init = False
                if t in ('(', '['):
                    if t == '(' and decl is None and j > start and is_name(tx(j - 1)) and \
                            tx(j + 1) not in ('*', '^') and not init:
                        decl = (j, m[j])
                    j = m[j] + 1
                    if decl and decl[1] == j - 1 and j < n and \
                            (is_typetok(tx(j)) or tx(j) in STORAGE | QUALS or
                             is_name(tx(j))):
                        knr = True              # a K&R definition's declarations follow
                    continue
                if t == '{':
                    if (tx(j - 1) == ')' and decl is not None) or knr:
                        body = (j, m[j])
                        j = m[j]
                        break
                    j = m[j] + 1
                    continue
                if t == ';' and not knr:
                    break
                j += 1
            items.append(Item(start, min(j, n - 1), body, decl))
            k = j + 1
        return items

    def block_externs(self):
        """the 'extern' declarations in function bodies (DOS programs declare there)"""
        out = []
        for k in range(1, len(self.S)):
            if self.inbody[k] and self.tx(k) == 'extern' and self.tx(k - 1) in (';', '{', '}'):
                j, decl = k, None
                while j < len(self.S) and self.tx(j) != ';':
                    if self.tx(j) in ('(', '[', '{'):
                        if self.tx(j) == '(' and decl is None and is_name(self.tx(j - 1)) \
                                and self.tx(j + 1) not in ('*', '^'):
                            decl = (j, self.match[j])
                        j = self.match[j]
                    j += 1
                out.append(Item(k, j, None, decl, block=True))
        return out

    def skip(self, j):
        """past a bracketed group starting at j"""
        return self.match[j] + 1 if self.tx(j) in ('(', '[', '{') else j + 1

    def pieces(self, a, b):
        """the comma-separated declarators of S a..b (brackets skipped)"""
        out, s, j = [], a, a
        while j <= b:
            if self.tx(j) == ',':
                out.append((s, j - 1))
                s = j + 1
            j = self.skip(j)
        out.append((s, b))
        return out

    def decl_name(self, a, b):
        """the name a declarator of S a..b declares, or None"""
        tx = self.tx
        name, j = None, a
        while j <= b:
            t = tx(j)
            if t == '(':
                if tx(j + 1) in ('*', '^'):
                    c = self.match[j]
                    inner = [tx(x) for x in range(j + 1, c)
                             if is_name(tx(x)) and tx(x - 1) not in TAGWORDS]
                    return inner[-1] if inner else None
                if j > a and tx(j - 1).startswith('__'):
                    j = self.skip(j)            # (__attribute__((...)))
                    continue
                break
            if t in ('[', '=', ':', '{'):
                if t == '{':
                    j = self.skip(j)
                    continue
                break
            if is_name(t) and tx(j - 1) not in TAGWORDS:
                name = t
            j += 1
        return name

    def fdecls(self, it):
        """[(name, open, close)] of the item's function declarators"""
        out = []
        end = it.body[0] - 1 if it.body else it.end
        for a, b in self.pieces(it.start, end):
            j = a
            while j <= b:
                if self.tx(j) == '=':
                    break                       # (an initializer)
                if self.tx(j) == '(':
                    if is_name(self.tx(j - 1)) and self.tx(j + 1) not in ('*', '^') and j > a:
                        out.append((self.tx(j - 1), j, self.match[j]))
                    break
                if self.tx(j) in ('[', '{'):
                    j = self.skip(j)
                    continue
                j += 1
        return out

    def first(self, it):
        """the item's first token past __extension__"""
        k = it.start
        while self.tx(k) == '__extension__':
            k += 1
        return k

    def promoted(self, a, b):
        """a parameter (S a..b) whose type the default promotions change"""
        words = []
        for k in range(a, b + 1):
            t = self.tx(k)
            if t in ('*', '[', '('):
                return False
            words += t.split()
        return any(w in PROMOTED or w in self.promo for w in words) and \
            not any(w in ('struct', 'union') for w in words)

    def typedefs(self):
        """typedef names, and those of a promoted type (unsigned char, short ...)"""
        self.tdefs, self.promo = set(), set()
        for it in self.items:
            k = self.first(it)
            if self.tx(k) != 'typedef' or it.body:
                continue
            ps = self.pieces(k + 1, it.end - 1 if self.tx(it.end) == ';' else it.end)
            base = None                 # the first declarator's type words (before its name)
            for a, b in ps:
                name = self.decl_name(a, b)
                if not name:
                    continue
                self.tdefs.add(name)
                words, j, before = [], a, []
                while j <= b:
                    t = self.tx(j)
                    if t == '{':
                        words.append('struct')      # (a structure's body)
                        j = self.skip(j)
                        continue
                    if t == name:
                        before = list(words)
                    else:
                        words += t.split()
                    j += 1
                if base is None:
                    base = before
                else:
                    words = base + words
                if any(w in ('*', '[', '(', 'struct', 'union') for w in words):
                    continue
                if any(w in PROMOTED or w in self.promo for w in words):
                    self.promo.add(name)

    def sysfuncs(self):
        """the functions the system headers (the C library) declare in this file"""
        self.sys = set()
        for it in self.items:
            if not self.toks[self.S[it.start]][3]:
                for name, _, _ in self.fdecls(it):
                    self.sys.add(name)

    # ---- implicit int
    def implicit_int_funcs(self):
        for it in self.items:
            if it.decl is None or it.block:
                continue
            k = self.first(it)
            if not self.usr(k):
                continue
            while self.tx(k) in STORAGE:
                k += 1
            if k == it.decl[0] - 1 and self.tx(k) not in self.native:
                self.add_pre(k, 'short ')
                self.note(k, f"'{self.tx(k)}' without a type: short (implicit int)")

    def implicit_int_vars(self):
        """'static n;', 'register i, j;', 'const k = 3;': short"""
        tx = self.tx
        for k in range(len(self.S)):
            t = tx(k)
            if t not in STORAGE | QUALS or not self.usr(k):
                continue
            p = tx(k - 1) if k else ';'
            if not (p in (';', '{', ')') or (p == '}' and t in STORAGE)):
                continue
            j = k
            while tx(j) in STORAGE | QUALS:
                j += 1
            x = tx(j)
            if is_name(x) and x not in self.tdefs and tx(j + 1) in (';', '=', ',', '['):
                self.add_pre(j, 'short ')
                self.note(j, f"'{x}' without a type: short (implicit int)")

    def knr_params(self):
        """a K&R definition's parameters that its declarations leave out: short"""
        for it in self.items:
            if not it.body or not it.decl or not self.usr(it.decl[0]):
                continue
            o, c = it.decl
            if c == o + 1:
                continue
            ids = []
            for a, b in self.pieces(o + 1, c - 1):
                if a != b or not is_name(self.tx(a)) or self.tx(a) in self.tdefs:
                    ids = None
                    break
                ids.append(self.tx(a))
            if not ids:
                continue
            declared = set()
            j = c + 1
            while j < it.body[0]:
                e = j
                while e < it.body[0] and self.tx(e) != ';':
                    e = self.skip(e)
                for a, b in self.pieces(j, e - 1):
                    declared.add(self.decl_name(a, b))
                j = e + 1
            miss = [x for x in ids if x not in declared]
            if miss:
                self.add_pre(it.body[0], ' '.join(f'short {x};' for x in miss) + ' ')
                self.note(it.body[0], f"K&R parameter(s) without a declaration: short "
                                      f"{', '.join(miss)}")

    # ---- declarations
    def libc_decls(self):
        """the program's own declarations of C library functions a system header declares"""
        for it in self.items:
            if it.body or not self.usr(it.start) or self.tx(self.first(it)) == 'typedef':
                continue
            fd = self.fdecls(it)
            pieces = self.pieces(it.start, it.end - 1 if self.tx(it.end) == ';' else it.end)
            if fd and len(fd) == len(pieces) and all(nm in self.sys for nm, _, _ in fd):
                self.note(it.start, f"{', '.join(nm for nm, _, _ in fd)}: the C library's "
                                    f"declaration (the program's left out)")
                self.blank(it.start, it.end)

    def empty_decls(self):
        """the functions declared without a prototype: 'f();'"""
        out = set()
        for it in self.items:
            if it.body:
                continue
            for name, o, c in self.fdecls(it):
                if c == o + 1 and self.tx(o) == '(':
                    out.add(name)
        return out

    def implicit_calls(self):
        """functions called before any declaration: a declaration before the first call's
        definition (C89's 'int f()', short here)"""
        tx = self.tx
        n = len(self.S)
        firstpos = {}
        calls = []
        for k in range(n):
            t = tx(k)
            if not is_ident(t):
                continue
            if self.inbody[k] and tx(k + 1) == '(' and tx(k - 1) not in ('.', '->') and \
                    is_name(t) and not (is_typetok(tx(k - 1)) or
                                        (is_ident(tx(k - 1)) and tx(k - 1) not in
                                         ('return', 'else', 'do', 'case', 'sizeof'))):
                calls.append(k)
                continue
            firstpos.setdefault(t, k)
        out = set()
        done = set()
        for k in calls:
            t = tx(k)
            if t in done or firstpos.get(t, n) < k or t in self.sys or not self.usr(k):
                continue
            done.add(t)
            it = next(i for i in self.items if i.start <= k <= i.end and not i.block)
            ret, static = 'short', False
            for later in self.items:
                if later.start <= it.start or later.block:
                    continue
                d = [x for x in self.fdecls(later) if x[0] == t]
                if not d:
                    continue
                words, ok = [], True
                for x in range(self.first(later), d[0][1] - 1):
                    w = tx(x)
                    if w in STORAGE:
                        static |= w == 'static'
                        continue
                    if not (is_typetok(w) or w in QUALS or w == '*' or w == '' or
                            (is_ident(w) and firstpos.get(w, n) < it.start)):
                        ok = False
                    words.append(w)
                if ok and words:
                    ret = ' '.join(w for w in words if w)
                break
            if t in self.native:
                continue
            self.add_pre(it.start, f"{'static ' if static else ''}{ret} {t}(); ")
            self.note(k, f"'{t}' called before its declaration: '{ret} {t}();' above")
            out.add(t)
        return out

    def proto_scope_tags(self):
        """prototypes whose parameter names a structure not declared before (its scope is
        the prototype's alone): written 'f();'"""
        first = {}
        depth = 0
        for k in range(len(self.S)):
            t = self.tx(k)
            if t == '(':
                depth += 1
            elif t == ')':
                depth -= 1
            elif t in TAGWORDS and depth == 0 and not self.inbody[k] and is_ident(self.tx(k + 1)):
                first.setdefault(self.tx(k + 1), k)
        out = set()
        for it in self.items:
            if it.body or not self.usr(it.start):
                continue
            for name, o, c in self.fdecls(it):
                ws = [self.tx(x) for x in range(o + 1, c)]
                if '...' in ''.join(ws) or name in self.native:
                    continue
                bad = [ws[x + 1] for x in range(len(ws) - 1)
                       if ws[x] in ('struct', 'union') and is_ident(ws[x + 1]) and
                       first.get(ws[x + 1], len(self.S)) > o]
                if bad:
                    self.blank(o + 1, c - 1)
                    self.note(o, f"'{name}': its prototype names struct {bad[0]} before it "
                                 f"is declared: '{name}()'")
                    out.add(name)
        return out

    def unprototype(self, names):
        """prototypes with promoted parameters of functions declared without one"""
        for it in self.items:
            if not self.usr(it.start):
                continue
            for name, o, c in self.fdecls(it):
                if name not in names or c == o + 1:
                    continue
                ws = [self.tx(x) for x in range(o + 1, c)]
                if ws in (['void'],) or '...' in ''.join(ws):
                    continue
                ps = self.pieces(o + 1, c - 1)
                if not any(self.promoted(a, b) for a, b in ps):
                    continue
                if not it.body or (o, c) != it.decl:
                    self.blank(o + 1, c - 1)
                    self.note(o, f"'{name}': declared without a prototype elsewhere: "
                                 f"'{name}()' here too")
                    continue
                pnames = [self.decl_name(a, b) for a, b in ps]
                if not all(pnames):
                    continue
                decls = ' '.join(' '.join(self.tx(x) for x in range(a, b + 1)
                                          if self.tx(x)) + ';' for a, b in ps)
                self.blank(o + 1, c - 1)
                self.toks[self.S[o + 1]][1] = ', '.join(pnames)
                self.add_post(c, ' ' + decls)
                self.note(o, f"'{name}': declared without a prototype elsewhere: a K&R "
                             f"definition")


def rewrite(text, native=(), keep_double=False, pack=True, report=None, fixups=None,
            src=None):
    """a preprocessed source (CC -E -C) -> the same with the Atari816's types in the
    program's own lines (not the system headers')"""
    native = set(native) | {'main'}
    if fixups:
        text = apply_fixups(text, fixups, src)
    out = []
    user = True                     # the current line is the program's own
    lines = text.split('\n')
    # the program's tokens, line by line, with the system lines passed through as they are
    toks = []                       # [kind, text, line index]
    incom = False                   # inside a /* comment */ that began on an earlier line
    for k, ln in enumerate(lines):
        pos = 0
        if incom:
            e = ln.find('*/')
            pos = len(ln) if e < 0 else e + 2
            toks.append(['com', ln[:pos], k, user])
            incom = e < 0
        else:
            m = MARKER.match(ln)
            if m:
                flags = m.group(3).split()
                user = '3' not in flags
                toks.append(['marker', ln, k, user])
                continue
            if ln.lstrip().startswith('#'):
                toks.append(['pp', ln, k, user])
                continue
        while pos < len(ln):
            if ln.startswith('/*', pos) and ln.find('*/', pos + 2) < 0:
                toks.append(['com', ln[pos:], k, user])     # (it goes on below)
                incom = True
                break
            mt = TOKEN.match(ln, pos)
            toks.append([mt.lastgroup, mt.group(), k, user])
            pos = mt.end()
        toks.append(['ws', '', k, user])        # (the line's end)
    native_lines = {t[2] for t in toks if t[0] == 'com' and 'host16: native' in t[1]}
    sig = [i for i, t in enumerate(toks) if t[0] in ('id', 'num', 'str', 'op')]
    keep = set()
    # native regions: main's and --native functions' parameters and return types,
    # va_arg's type
    for n, i in enumerate(sig):
        t = toks[i]
        if t[0] != 'id' or n + 1 >= len(sig) or toks[sig[n + 1]][1] != '(':
            continue
        if t[1] in native or t[1] in ('__builtin_va_arg', 'va_arg'):
            depth, m = 0, n + 1
            while m < len(sig):
                s = toks[sig[m]][1]
                depth += (s == '(') - (s == ')')
                keep.add(sig[m])
                if depth == 0:
                    break
                m += 1
            if t[1] in native:
                m = n - 1
                while m >= 0 and toks[sig[m]][0] == 'id' and \
                        toks[sig[m]][1] in TYPEWORDS | {'static', 'extern', 'const', 'inline'}:
                    keep.add(sig[m])
                    m -= 1
    n = 0
    while n < len(sig):
        i = sig[n]
        t = toks[i]
        if not t[3]:
            n += 1                      # (a system header's token, or its macro's)
            continue
        if t[0] == 'num' and i not in keep and t[2] not in native_lines:
            t[1] = num_suffix(t[1])
            n += 1
            continue
        if t[0] != 'id' or t[1] not in TYPEWORDS:
            n += 1
            continue
        m = n
        while m < len(sig) and toks[sig[m]][0] == 'id' and toks[sig[m]][1] in TYPEWORDS:
            m += 1
        run = sig[n:m]
        if not any(j in keep or toks[j][2] in native_lines or not toks[j][3] for j in run):
            words = [toks[j][1] for j in run]
            new = canon(words, keep_double)
            if new != ' '.join(words):
                toks[run[0]][1] = new
                for j in run[1:]:
                    toks[j][1] = ''
                    # (the space after a dropped word stays: harmless)
        n = m
    # old C that the PC's compiler refuses once int is short (OldC below): text to put
    # before or after a token
    pre, post = OldC(toks, [i for i in sig if toks[i][1]], native, native_lines,
                     report).run()
    # the program's structures and unions packed (cc816 pads none): the attribute after
    # the keyword of each one defined here (struct [tag] {); a system header's keep
    # their layout
    if pack:
        for n, i in enumerate(sig):
            t = toks[i]
            if t[0] == 'id' and t[1] in ('struct', 'union') and t[3] and n + 1 < len(sig):
                nx = toks[sig[n + 1]]
                if nx[1] == '{' or (nx[0] == 'id' and n + 2 < len(sig) and
                                    toks[sig[n + 2]][1] == '{'):
                    t[1] += ' __attribute__((packed))'
    # put the lines back together
    cur = None
    buf = []
    for i, t in enumerate(toks):
        if t[0] in ('marker', 'pp'):
            if cur is not None:
                out.append(''.join(buf))
                buf, cur = [], None
            out.append(t[1])
            continue
        if cur is not None and t[2] != cur:
            out.append(''.join(buf))
            buf = []
        cur = t[2]
        buf.append(pre.get(i, '') + t[1] + post.get(i, ''))
    if cur is not None:
        out.append(''.join(buf))
    return '\n'.join(out) + '\n'


def load_fixups(path):
    """a fix-up file -> {file name: [(old, new, line)]}:

        # a comment
        [SAVE.C]                       the fix-ups of the file of that name (or path end)
        x == -1  =>  x == (unsigned) -1
    """
    out, cur = {}, None
    with open(path, encoding='latin-1') as f:
        for n, ln in enumerate(f, 1):
            s = ln.strip()
            if not s or s.startswith('#'):
                continue
            if s.startswith('[') and s.endswith(']'):
                cur = out.setdefault(s[1:-1].strip(), [])
                continue
            if cur is None or ' => ' not in s:
                raise Host16Error(f'{path}:{n}: neither [FILE] nor OLD => NEW')
            old, new = s.split(' => ', 1)
            cur.append((old.strip(), new.strip(), f'{path}:{n}'))
    return out


def _same_file(marker_name, name):
    return marker_name == name or marker_name.endswith('/' + name)


def apply_fixups(text, fixups, src=None):
    """each fix-up of a file the preprocessed text holds (by its line markers), applied
    to that file's lines: OLD must be on one of them exactly once (as the preprocessor
    wrote it: macros expanded)"""
    lines = text.split('\n')
    owner = []                      # the file each line belongs to
    cur = src or ''
    for ln in lines:
        m = MARKER.match(ln)
        if m:
            cur = m.group(2)
            owner.append(None)
            continue
        owner.append(cur)
    for name, fixes in fixups.items():
        mine = [k for k, o in enumerate(owner) if o is not None and _same_file(o, name)]
        if not mine:
            continue                # (a file this one does not include)
        for old, new, where in fixes:
            hits = [(k, lines[k].count(old)) for k in mine if old in lines[k]]
            if sum(c for _, c in hits) != 1:
                raise Host16Error(f'{where}: the fix-up {old!r} is in {name} '
                                  f'{sum(c for _, c in hits)} times, not once'
                                  + (f' (compiling {src})' if src else ''))
            k = hits[0][0]
            lines[k] = lines[k].replace(old, new)
    return '\n'.join(lines)


def is_csrc(a):
    return a.endswith(('.c', '.C'))


PP_ARG = ('-I', '-D', '-U', '-include', '-isystem', '-iquote', '-imacros')


def pp_options(args):
    """the preprocessor's options among CC's arguments"""
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if a in PP_ARG and i + 1 < len(args):
            out += [a, args[i + 1]]
            i += 2
            continue
        # (and what changes the predefined macros: -O gives __OPTIMIZE__, and with it the
        # C library's inline and _FORTIFY_SOURCE versions of its functions; -m, -fPIC)
        if any(a.startswith(p) and len(a) > len(p) for p in ('-I', '-D', '-U')) or \
                a.startswith(('-std=', '-O', '-m')) or \
                a in ('-ansi', '-funsigned-char', '-fsigned-char', '-pthread', '-fpic',
                      '-fPIC', '-fpie', '-fPIE', '-fno-pic', '-fno-pie', '-ffast-math'):
            out.append(a)
        i += 1
    return out


def preprocess(cc, src, ppopts, verbose=False):
    # (-x c: a DOS program's FILE.C is C, not the C++ gcc takes .C for)
    cmd = [cc, '-E', '-C', '-funsigned-char'] + ppopts + ['-x', 'c', src]
    if verbose:
        print(' '.join(cmd), file=sys.stderr)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='latin-1')
    if r.returncode:
        raise Host16Error(r.stderr.strip() or f'{cc} -E {src} failed')
    return r.stdout


def main(argv):
    native, keep_double, pack, keepdir, verbose = [], False, True, None, False
    fixups, report = None, False
    i = 0
    while i < len(argv) and argv[i].startswith('-') and argv[i] != '-E':
        a = argv[i]
        if a == '--native' and i + 1 < len(argv):
            native.append(argv[i + 1])
            i += 2
            continue
        if a == '--keep-double':
            keep_double = True
        elif a == '--no-pack':
            pack = False
        elif a == '--keep' and i + 1 < len(argv):
            keepdir = argv[i + 1]
            i += 1
        elif a == '--fixups' and i + 1 < len(argv):
            try:
                fixups = load_fixups(argv[i + 1])
            except (OSError, Host16Error) as e:
                print(f'host16.py: {e}', file=sys.stderr)
                return 2
            i += 1
        elif a == '--report':
            report = True
        elif a == '-v':
            verbose = report = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            print(f'host16.py: unknown option {a}', file=sys.stderr)
            return 2
        i += 1
    rest = argv[i:]

    def convert(cc, src, ppopts):
        notes = [] if report else None
        text = rewrite(preprocess(cc, src, ppopts, verbose), native, keep_double, pack,
                       notes, fixups, src)
        for n in notes or ():
            print(f'host16.py: {n}', file=sys.stderr)
        return text
    try:
        if rest[:1] == ['-E']:
            # host16.py -E FILE.c -o OUT.c [options]
            src = out = None
            opts = []
            k = 1
            while k < len(rest):
                if rest[k] == '-o' and k + 1 < len(rest):
                    out = rest[k + 1]
                    k += 2
                    continue
                if is_csrc(rest[k]) and src is None:
                    src = rest[k]
                else:
                    opts.append(rest[k])
                k += 1
            if not src or not out:
                print(__doc__)
                return 2
            cc = os.environ.get('CC', 'cc')
            if not any(a.startswith('-std=') or a == '-ansi' for a in opts):
                opts = ['-std=gnu17'] + opts
            text = convert(cc, src, pp_options(opts))
            with open(out, 'w', encoding='latin-1') as f:
                f.write(text)
            return 0
        if not rest:
            print(__doc__)
            return 2
        cc, args = rest[0], rest[1:]
        if not any(a.startswith('-std=') or a == '-ansi' for a in args):
            args = ['-std=gnu17'] + args        # (C23, gcc 15's default: 'f()' is f(void))
        ppopts = pp_options(args)
        tmp = keepdir or tempfile.mkdtemp(prefix='host16')
        os.makedirs(tmp, exist_ok=True)
        try:
            new = []
            seen = {}
            for a in args:
                if is_csrc(a) and os.path.exists(a):
                    base = os.path.splitext(os.path.basename(a))[0]
                    seen[base] = seen.get(base, 0) + 1
                    name = base if seen[base] == 1 else f'{base}_{seen[base]}'
                    dst = os.path.join(tmp, name + '.i')
                    text = convert(cc, a, ppopts)
                    with open(dst, 'w', encoding='latin-1') as f:
                        f.write(text)
                    new.append(dst)
                else:
                    new.append(a)
            # (an object named after its source when -c gives no -o: the original name)
            if '-c' in new and '-o' not in new:
                cmds = []
                for a, b in zip(args, new):
                    if is_csrc(a) and b != a:
                        o = os.path.splitext(os.path.basename(a))[0] + '.o'
                        cmds.append([cc] + EXTRA(keep_double) +
                                    [x for x in new if not x.endswith('.i')] + [b, '-o', o])
            else:
                cmds = [[cc] + EXTRA(keep_double) + new]
            for cmd in cmds:
                if verbose:
                    print(' '.join(cmd), file=sys.stderr)
                r = subprocess.run(cmd)
                if r.returncode:
                    return r.returncode
            return 0
        finally:
            if not keepdir:
                shutil.rmtree(tmp, ignore_errors=True)
    except Host16Error as e:
        print(f'host16.py: {e}', file=sys.stderr)
        return 1


def EXTRA(keep_double):
    return ['-funsigned-char', '-fwrapv', '-fno-strict-aliasing'] + \
        ([] if keep_double else ['-fsingle-precision-constant'])


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
