#!/usr/bin/env python3
"""keyscript.py [--mouse] SCRIPT - turn typed text into an emu816 --keys list (with
--mouse: the script's mouse lines as an emu816 --mouse list).

Script lines:  <time> <text>   time in ms, absolute ("2000") or after the previous
line's start ("+3000"). Text escapes: \\n Enter, \\b Backspace, ^C ctrl-C, \\\\ backslash,
{up} {down} {left} {right} {home} {end} {pgup} {pgdn} {esc}, {F12} the system key, {dXX} / {uXX} key XX (hex usage)
down / up alone (to hold a key across other events).
Each character is pressed for 20 ms, one every 50 ms; shifted characters hold left shift.
A line whose text is "M dx:dy:wheel:buttons" is a mouse event at that time.
Lines starting with # are comments."""
import sys

LOWER = 'abcdefghijklmnopqrstuvwxyz1234567890'
SYM = {' ': (0x2C, 0), '-': (0x2D, 0), '=': (0x2E, 0), '[': (0x2F, 0), ']': (0x30, 0),
       '\\': (0x31, 0), ';': (0x33, 0), "'": (0x34, 0), '`': (0x35, 0), ',': (0x36, 0),
       '.': (0x37, 0), '/': (0x38, 0), '_': (0x2D, 1), '+': (0x2E, 1), '{': (0x2F, 1),
       '}': (0x30, 1), '|': (0x31, 1), ':': (0x33, 1), '"': (0x34, 1), '~': (0x35, 1),
       '<': (0x36, 1), '>': (0x37, 1), '?': (0x38, 1), '!': (0x1E, 1), '@': (0x1F, 1),
       '#': (0x20, 1), '$': (0x21, 1), '%': (0x22, 1), '^': (0x23, 1), '&': (0x24, 1),
       '*': (0x25, 1), '(': (0x26, 1), ')': (0x27, 1)}

def keys_of(text):
    i = 0
    while i < len(text):
        c = text[i]
        if text.startswith('\\n', i): yield (0x28, None); i += 2; continue
        if text.startswith('\\b', i): yield (0x2A, None); i += 2; continue
        if text.startswith('\\\\', i): yield (0x31, None); i += 2; continue
        if text.startswith('^C', i): yield (0x06, 0xE0); i += 2; continue
        if c == '{':
            tok = text[i + 1:text.index('}', i)]
            i += len(tok) + 2
            arrows = {'right': 0x4F, 'left': 0x50, 'down': 0x51, 'up': 0x52, 'F12': 0x45, 'esc': 0x29,
                      'home': 0x4A, 'pgup': 0x4B, 'end': 0x4D, 'pgdn': 0x4E}
            if tok in arrows: yield (arrows[tok], None)
            elif tok[0] in 'du': yield ('raw', (int(tok[1:], 16), tok[0] == 'd'))
            else: raise SystemExit(f'bad token {tok!r}')
            continue
        if c in LOWER: yield (4 + LOWER.index(c) if c.isalpha() else 0x1E + '1234567890'.index(c), None)
        elif c.isalpha(): yield (4 + LOWER.index(c.lower()), 0xE1)
        elif c in SYM:
            u, sh = SYM[c]; yield (u, 0xE1 if sh else None)
        else: raise SystemExit(f'cannot type {c!r}')
        i += 1

mouse = sys.argv[1] == '--mouse'
out, mout, t = [], [], 0
for ln in open(sys.argv[-1]):
    ln = ln.rstrip('\n')
    if not ln.strip() or ln.startswith('#'): continue
    when, _, text = ln.partition(' ')
    t = t + int(when[1:]) if when.startswith('+') else int(when)
    if text.startswith('M '):
        mout.append(f'{t}:{text[2:].strip()}')
        continue
    k = t
    for usage, mod in keys_of(text):
        if usage == 'raw':
            out.append(f'{k}:{mod[0]:02x}:{int(mod[1])}')
            k += 50
            continue
        if mod: out.append(f'{k}:{mod:02x}:1')
        out.append(f'{k + 2}:{usage:02x}:1')
        out.append(f'{k + 22}:{usage:02x}:0')
        if mod: out.append(f'{k + 24}:{mod:02x}:0')
        k += 50
print(','.join(mout if mouse else out) or '0:0:0:0:0')
