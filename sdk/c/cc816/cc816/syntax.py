"""Syntax errors in plain words: pycparser says 'before: X'; this looks at the source line
to say what is most likely wrong (an unknown type name, a missing ';', a GNU extension
cc816 does not have, ...).

    explain(file, line, col, pycparser's message) -> (message, unsupported)
"""
import re

KEYWORDS = {
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double',
    'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline', 'int', 'long',
    'register', 'restrict', 'return', 'short', 'signed', 'sizeof', 'static', 'struct',
    'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile', 'while', '_Bool',
    '_Complex', '_Imaginary', '_Alignas', '_Alignof', '_Atomic', '_Generic', '_Noreturn',
    '_Static_assert', '_Thread_local',
}
STATEMENT_WORDS = {'return', 'if', 'for', 'while', 'do', 'switch', 'break', 'continue',
                   'goto', 'else', 'case', 'default'}
TYPE_WORDS = {'char', 'short', 'int', 'long', 'float', 'double', 'void', 'signed',
              'unsigned', '_Bool', 'struct', 'union', 'enum', 'const', 'volatile', 'static',
              'extern', 'register', 'auto', 'inline', 'typedef'}
STDINT = {'int8_t', 'uint8_t', 'int16_t', 'uint16_t', 'int32_t', 'uint32_t', 'int64_t',
          'uint64_t', 'int_least64_t', 'uint_least64_t', 'int_fast64_t', 'uint_fast64_t',
          'intptr_t', 'uintptr_t', 'intmax_t', 'uintmax_t'}
INT128 = {'__int128', '__uint128_t', '__int128_t'}

_TOKEN = re.compile(r'''\s*(?:([A-Za-z_]\w*)|(\d[\w.]*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|'''
                    r'''(\.\.\.|->|\+\+|--|<<=|>>=|<<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^]=|'''
                    r'''##|.))''')


def _tokens(text):
    """[(column (1-based), token)] of a line"""
    out = []
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m or m.end() == pos:
            break
        tok = m.group(0).strip()
        if tok:
            out.append((m.end() - len(tok) + 1, tok))
        pos = m.end()
    return out


def _source_lines(path):
    try:
        with open(path, encoding='latin-1') as f:
            return f.read().split('\n')
    except OSError:
        return None


def _ident(t):
    return bool(t) and bool(re.match(r'^[A-Za-z_]\w*$', t)) and t not in KEYWORDS


def explain(path, line, col, msg):
    lines = _source_lines(path)
    toks = []          # every token up to and including the line, [(line, col, tok)]
    if lines is not None and 0 < line <= len(lines):
        for n in range(max(0, line - 20), line):
            text = re.sub(r'/\*.*?\*/', lambda m: ' ' * len(m.group(0)), lines[n])
            text = re.sub(r'//.*$', '', text)
            if text.lstrip().startswith('#'):
                continue
            for c, t in _tokens(text):
                toks.append((n + 1, c, t))
    # the token at the error and the ones before it
    at = None
    for k, (ln, c, t) in enumerate(toks):
        if ln == line and c >= col:
            at = k
            break
    m = re.match(r'^(?:invalid expression )?before: (.*)$', msg)
    words = [t for ln, c, t in toks if ln == line]
    for w in words:
        if w in INT128:
            return (f"cc816 does not support 128-bit integers ({w}): long long is 64 bits",
                    True)
    if m:
        x = m.group(1)
        prev = toks[at - 1][2] if at is not None and at > 0 else None
        nxt = toks[at + 1][2] if at is not None and at + 1 < len(toks) else None
        if x == '&&' and msg.startswith('invalid expression') and _ident(nxt or ''):
            return ("cc816 does not support labels as values (&&label and goto *p, a GNU "
                    "extension): use a switch", True)
        if x == '{' and prev == ')':
            return ("syntax error before '{': a function cannot be defined inside another "
                    "one (cc816 does not support nested functions, a GNU extension), and a "
                    "declaration needs its ';'", False)
        if _ident(prev or '') and (_ident(x) or x == '*') and at is not None and at >= 1:
            before = toks[at - 2][2] if at >= 2 else None
            if before is None or before in (';', '{', '}', '(', ',') or \
                    (before in TYPE_WORDS and before not in ('struct', 'union', 'enum')):
                if prev in STDINT:
                    return f"unknown type name '{prev}' (#include <stdint.h>)", False
                return f"unknown type name '{prev}' (a typedef or a header missing?)", False
        if at is not None and at > 0 and toks[at - 1][0] < line and \
                toks[at - 1][2] not in (';', '{', '}', ',', ':', '(', '[', '=') and \
                not toks[at - 1][2].startswith('#'):
            return (f"expected ';' before '{x}' (at the end of line {toks[at - 1][0]})",
                    False)
        if x in STATEMENT_WORDS and prev not in (';', '{', '}', ')', ':', 'else', None):
            return f"expected ';' before '{x}'", False
        return f"syntax error before '{x}'", False
    if msg == 'Invalid function definition':
        if len(words) >= 2 and _ident(words[0]) and _ident(words[1]):
            if words[0] in STDINT:
                return f"unknown type name '{words[0]}' (#include <stdint.h>)", False
            return f"unknown type name '{words[0]}' (a typedef or a header missing?)", False
        return ("syntax error: a statement outside a function, or a declaration without its "
                "type", False)
    if msg == 'Missing type in declaration':
        return ("a declaration without a type: write 'int x;', not 'x;' (C99 has no implicit "
                "int: -fimplicit-int or -std=c89 takes C89's), or an unknown type name", False)
    if msg == 'Invalid multiple types specified':
        return ("two types in one declaration (a ';' missing after a struct, union or enum "
                "definition, or 'unsigned float'?)", False)
    return f'syntax error: {msg}', False
