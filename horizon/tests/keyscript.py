#!/usr/bin/env python3
"""keyscript.py [--mouse] [--shots PREFIX N] SCRIPT - turn typed text into an emu816 --keys
list (with --mouse: the script's mouse lines as an emu816 --mouse list).

Script lines:  <time> <text>   time in ms, absolute ("2000") or after the previous
line's start ("+3000"). Text escapes: \\n Enter, \\b Backspace, ^C ctrl-C, \\\\ backslash,
{up} {down} {left} {right} {home} {end} {pgup} {pgdn} {esc}, {F12} the system key, {dXX} / {uXX} key XX (hex usage)
down / up alone (to hold a key across other events).
Each character is pressed for 20 ms, one every 50 ms; shifted characters hold left shift.
A line whose text is "M dx:dy:wheel:buttons" is a mouse event at that time.
(0.29) "wait TEXT": nothing more until the console shows a line holding TEXT (at once if one
came since the input line before it began), then every later time moves by as long as the
wait took; it starts after every key and mouse event of the lines before it (emu816's
t:W:HEX, with a step mark t:M: at each input line). (0.31) "still N": nothing more until
the picture on the monitor stayed the same for N frames in a row (60 a second), then every
later time moves by as long as the wait took; it starts after every key and mouse event
of the lines before it (emu816's t:Q:HEX). "change": the same until a frame differs from
the one before it (t:C:; it ends at a frame's start, so what follows keeps its place in the
frames: a picture of an animation N frames after its first). "sound": the same until a voice
of Lau, the sample player, is started (t:A:; to the cycle: a song's first note).
"shot": a screenshot that moves with the
waits (PREFIX + its number .ppm, numbered from N + 1 in the script's order; shots.sh).
A picture taken at a state ("wait TEXT" or "still N", then "+0 shot") does not depend on
how fast the CPU or the kernel is; one taken at a time (shots.sh's T1 ...) may.
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
prefix, nshot = None, 0
if '--shots' in sys.argv:
    i = sys.argv.index('--shots'); prefix, nshot = sys.argv[i + 1], int(sys.argv[i + 2])
out, mout, t = [], [], 0
last = -1                               # the last key or mouse event (a wait comes after it)
for ln in open(sys.argv[-1]):
    ln = ln.rstrip('\n')
    if not ln.strip() or ln.startswith('#'): continue
    when, _, text = ln.partition(' ')
    t = t + int(when[1:]) if when.startswith('+') else int(when)
    if text.startswith('wait '):
        t = max(t, last + 1)
        out.append(f'{t}:W:{text[5:].encode("latin-1").hex()}')
        continue
    if text.startswith('still ') and text[6:].strip().isdigit():
        t = max(t, last + 1)
        out.append(f'{t}:Q:{text[6:].strip().encode("latin-1").hex()}')
        continue
    if text in ('change', 'sound'):
        t = max(t, last + 1)
        out.append(f'{t}:{"C" if text == "change" else "A"}:')
        continue
    if text == 'shot':
        if not prefix and not mouse: raise SystemExit('a shot line needs --shots PREFIX N')
        nshot += 1
        out.append(f'{t}:S:{(str(prefix) + str(nshot) + ".ppm").encode("latin-1").hex()}')
        continue
    out.append(f'{t}:M:')                 # (an input line: the console's lines count from here)
    if text.startswith('M '):
        mout.append(f'{t}:{text[2:].strip()}')
        last = max(last, t)
        continue
    k = t
    for usage, mod in keys_of(text):
        if usage == 'raw':
            out.append(f'{k}:{mod[0]:02x}:{int(mod[1])}')
            last = max(last, k)
            k += 50
            continue
        if mod: out.append(f'{k}:{mod:02x}:1')
        out.append(f'{k + 2}:{usage:02x}:1')
        out.append(f'{k + 22}:{usage:02x}:0')
        if mod: out.append(f'{k + 24}:{mod:02x}:0')
        last = max(last, k + 24 if mod else k + 22)
        k += 50
print(','.join(mout if mouse else out) or '0:0:0:0:0')
