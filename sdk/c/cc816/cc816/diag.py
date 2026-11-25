"""Diagnostics: the errors and warnings of one compile, in gcc's form

    file.c:LINE:COL: error: message
    file.c:LINE:COL: warning: message [-Wname]

The place is the user's file and line (through #include and #line). Warnings are on by
default; some only with -Wall (unused variables, ...), some only when named (-WNAME);
-Werror makes every warning an error. -Wno-NAME turns one off, -WNAME on. -w silences
every warning but the 16-bit ones (PORTABILITY: a value that a 16-bit int changes is a
wrong value on this machine, not a matter of style); -Wno-NAME silences those too.
"""
import re

from .ctypes816 import where

# the warnings, by name: True = on by default, False = only with -Wall, None = only when
# named (-WNAME)
WARNINGS = {
    'implicit-function-declaration': True,
    'int-conversion': True,             # integer <-> pointer without a cast
    'incompatible-pointer-types': True,
    'discarded-qualifiers': True,       # const char * -> char *
    'far-pointer': True,                # a far pointer given to a near one (loses the bank)
    'type-limits': True,                # a char compared with what it cannot hold
    'return-type': True,                # control reaches the end of a non-void function
    'overflow': True,                   # a constant changed by a conversion or overflowing
    'shift-count-overflow': True,
    'div-by-zero': True,
    'format': True,                     # printf / scanf formats against the arguments
    'excess-initializers': True,
    'cpp': True,                        # #warning
    'extern-initializer': True,         # extern int x = 1;
    'multichar': True,                  # 'abc'
    'attributes': True,                 # a GNU attribute cc816 does not honour
    'frame-larger-than': True,          # a function's software-stack frame over 1 KB
    'unknown-pragmas': True,            # a #pragma cc816 does not know (Watcom's aux, ...)
    'far-function': True,               # void (__far *f)(void): __far ignored
    'implicit-int': True,               # -fimplicit-int: 'f() {...}', 'register x;'
    'extra-args': True,                 # -fextra-args: a call with more arguments than
                                        # the prototype (they are pushed, never read)
    'unprototyped-args': True,          # a call without a prototype whose arguments'
                                        # sizes differ from the definition's parameters
    'prototype-mismatch': True,         # (hcc --check-calls) a prototype in one file that
                                        # differs from the definition in another
    'return-mismatch': True,            # (hcc --check-calls) a call without a prototype
                                        # that uses the value, or a prototype, whose return
                                        # type differs from the definition's in another file
    'unused-variable': False,
    'unused-label': False,
    'parentheses': False,               # if (a = b)
    'tautological-compare': False,      # x <= 32767 with an int x, u >= 0, ...
    'far-cast': False,                  # a far pointer cast to a near one
    'sequence-args': None,              # two arguments of one call that call functions
}

# the warnings -w leaves on (only -Wno-NAME turns them off): where cc816's 16-bit int
# gives another value than the source's arithmetic says (docs/c/reference.md, "Errors and
# warnings")
PORTABILITY = {'overflow'}


class Diag:
    def __init__(self, opts=None):
        o = opts or {}
        self.quiet = bool(o.get('w'))
        self.werror = bool(o.get('werror'))
        self.on = {k: bool(v) or (v is False and bool(o.get('wall')))
                   for k, v in WARNINGS.items()}
        for name, val in (o.get('wflags') or {}).items():
            if name in self.on:
                self.on[name] = val
        self.errors = []            # formatted lines
        self.warnings = []
        self.seen = set()
        self.unsupported = False    # an error was a feature cc816 does not have

    def error(self, coord, msg, unsupported=False):
        line = f'{_place(coord)}error: {msg}'
        if line in self.seen:
            return
        if unsupported:             # a missing feature: said once a file
            if msg in self.seen:
                return
            self.seen.add(msg)
        self.seen.add(line)
        self.errors.append(line)
        self.unsupported = self.unsupported or unsupported

    def warning(self, coord, msg, name):
        if not self.on.get(name, True):
            return
        if self.quiet and name not in PORTABILITY:
            return
        if self.werror:
            line = f'{_place(coord)}error: {msg} [-Werror={name}]'
            if line not in self.seen:
                self.seen.add(line)
                self.errors.append(line)
            return
        line = f'{_place(coord)}warning: {msg} [-W{name}]'
        if line in self.seen:
            return
        self.seen.add(line)
        self.warnings.append(line)


    def all_lines(self):
        """the errors and the warnings, in the order of their places in the files"""
        files = []

        def key(item):
            n, line = item
            m = _POS.match(line)
            if not m:
                return (len(files) + 1, 0, 0, n)
            f = m.group(1)
            if f not in files:
                files.append(f)
            return (files.index(f), int(m.group(2) or 0), int(m.group(3) or 0), n)
        items = list(enumerate(self.warnings + self.errors))
        for _, line in items:           # files in the order they first appear
            m = _POS.match(line)
            if m and m.group(1) not in files:
                files.append(m.group(1))
        return [line for _, line in sorted(items, key=key)]


_POS = re.compile(r'^(.+?):(\d+)(?::(\d+))?: ')


def _place(coord):
    if coord is None:
        return ''
    if isinstance(coord, str):
        return coord + ': '
    w = where(coord)
    return w + ': ' if w else ''
