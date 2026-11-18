#!/usr/bin/env python3
"""inputscript.py - the SDK's input script language, turned into emu816 --keys / --mouse
lists (and screenshot times). Used by run816.py; also usable alone:

    inputscript.py SCRIPT [--offset MS] [--keys | --mouse | --shots]

A script is one event per line. Lines starting with '#' and blank lines are ignored.
Every line starts with a time in milliseconds: absolute ("2000"), or relative to the time
of the previous line ("+500"). run816.py adds the program's start time, so in a script
given to run816.py, 0 is the moment the program was started.

    T text            type text (one key every 50 ms, each held 20 ms; capitals and
                      symbols hold left Shift). Escapes:
                        \\n Enter   \\b Backspace   \\t Tab   \\\\ a backslash
                        ^A .. ^Z    ctrl + that letter (^C is ctrl-C)
                        {esc} {up} {down} {left} {right} {home} {end} {pgup} {pgdn}
                        {ins} {del} {tab} {enter} {space} {bksp} {f1} .. {f12}
                        {alt-x}     Alt + key x (a letter, digit or one of the names)
                        {ctrl-x}    ctrl + key x
                        {dXX} {uXX} raw key down / up, XX = HID usage in hex
    T key NAME MS     hold one key for MS milliseconds (NAME: a letter, a digit, or a
                      name above without braces, or lshift lctrl lalt rshift rctrl ralt)
    T down NAME       press one key and keep it down / T up NAME: release it
    T M dx:dy:wheel:buttons   one raw mouse event (relative)
    T move X Y        move the pointer to screen pixel X, Y (640 x 360 space) in steps;
                      the pointer starts at 320, 180 when the machine boots
    T click [left|right|middle]   press and release (80 ms) where the pointer is
    T dclick          double click (left)
    T press [btn] / T release     hold / let go of a button
    T drag X Y        move to X, Y with the left button held, 16 pixels every 30 ms (start
                      with 'press', end with 'release' after the drag's time has passed)
    T wheel N         wheel steps (positive = up / away from you: ui.lib scrolls up)
    T shot            a screenshot at this time
"""
import sys

HID = {
    'enter': 0x28, 'esc': 0x29, 'bksp': 0x2A, 'tab': 0x2B, 'space': 0x2C,
    'f1': 0x3A, 'f2': 0x3B, 'f3': 0x3C, 'f4': 0x3D, 'f5': 0x3E, 'f6': 0x3F,
    'f7': 0x40, 'f8': 0x41, 'f9': 0x42, 'f10': 0x43, 'f11': 0x44, 'f12': 0x45,
    'ins': 0x49, 'home': 0x4A, 'pgup': 0x4B, 'del': 0x4C, 'end': 0x4D, 'pgdn': 0x4E,
    'right': 0x4F, 'left': 0x50, 'down': 0x51, 'up': 0x52,
    'lctrl': 0xE0, 'lshift': 0xE1, 'lalt': 0xE2, 'lgui': 0xE3,
    'rctrl': 0xE4, 'rshift': 0xE5, 'ralt': 0xE6, 'rgui': 0xE7,
}
LOWER = 'abcdefghijklmnopqrstuvwxyz'
DIGITS = '1234567890'
SYM = {' ': (0x2C, 0), '-': (0x2D, 0), '=': (0x2E, 0), '[': (0x2F, 0), ']': (0x30, 0),
       '\\': (0x31, 0), ';': (0x33, 0), "'": (0x34, 0), '`': (0x35, 0), ',': (0x36, 0),
       '.': (0x37, 0), '/': (0x38, 0), '_': (0x2D, 1), '+': (0x2E, 1), '{': (0x2F, 1),
       '}': (0x30, 1), '|': (0x31, 1), ':': (0x33, 1), '"': (0x34, 1), '~': (0x35, 1),
       '<': (0x36, 1), '>': (0x37, 1), '?': (0x38, 1), '!': (0x1E, 1), '@': (0x1F, 1),
       '#': (0x20, 1), '$': (0x21, 1), '%': (0x22, 1), '^': (0x23, 1), '&': (0x24, 1),
       '*': (0x25, 1), '(': (0x26, 1), ')': (0x27, 1)}
BUTTONS = {'left': 1, 'right': 2, 'middle': 4}


class ScriptError(Exception):
    pass


def key_of_name(name):
    """A key name (or one character) -> (usage, shift?)"""
    n = name.lower()
    if n in HID:
        return HID[n], False
    if len(name) == 1:
        c = name
        if c in LOWER:
            return 4 + LOWER.index(c), False
        if c.lower() in LOWER:
            return 4 + LOWER.index(c.lower()), True
        if c in DIGITS:
            return 0x1E + DIGITS.index(c), False
        if c in SYM:
            u, sh = SYM[c]
            return u, bool(sh)
    raise ScriptError(f'unknown key {name!r}')


def strokes(text):
    """Typed text -> list of (usage, [modifier usages])."""
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if text.startswith('\\n', i):
            out.append((0x28, [])); i += 2; continue
        if text.startswith('\\b', i):
            out.append((0x2A, [])); i += 2; continue
        if text.startswith('\\t', i):
            out.append((0x2B, [])); i += 2; continue
        if text.startswith('\\\\', i):
            out.append((0x31, [])); i += 2; continue
        if c == '^' and i + 1 < len(text) and text[i + 1].upper() in LOWER.upper():
            out.append((4 + LOWER.index(text[i + 1].lower()), [0xE0])); i += 2; continue
        if c == '{':
            j = text.find('}', i)
            if j < 0:
                raise ScriptError('missing }')
            tok = text[i + 1:j]
            i = j + 1
            low = tok.lower()
            if low.startswith('alt-') or low.startswith('ctrl-'):
                mod = 0xE2 if low.startswith('alt-') else 0xE0
                u, sh = key_of_name(tok.split('-', 1)[1])
                out.append((u, [mod] + ([0xE1] if sh else [])))
            elif len(tok) == 3 and tok[0] in 'du' and all(h in '0123456789abcdefABCDEF' for h in tok[1:]):
                out.append(('raw', (int(tok[1:], 16), tok[0] == 'd')))
            else:
                u, sh = key_of_name(tok)
                out.append((u, [0xE1] if sh else []))
            continue
        u, sh = key_of_name(c)
        out.append((u, [0xE1] if sh else []))
        i += 1
    return out


def parse(lines, offset=0):
    """-> (keys, mouse, shots): emu816 list items and screenshot times in seconds."""
    keys, mouse, shots = [], [], []
    t = 0
    x, y = 320, 180
    held = 0

    def mv(t0, tx, ty, step, dt, b):
        nonlocal x, y
        tx = max(0, min(639, tx)); ty = max(0, min(359, ty))
        tt = t0
        while (x, y) != (tx, ty):
            dx = max(-step, min(step, tx - x)); dy = max(-step, min(step, ty - y))
            mouse.append(f'{tt + offset}:{dx}:{dy}:0:{b}')
            x += dx; y += dy; tt += dt
        return tt

    for no, ln in enumerate(lines, 1):
        ln = ln.rstrip('\n')
        if not ln.strip() or ln.lstrip().startswith('#'):
            continue
        when, _, rest = ln.partition(' ')
        try:
            t = t + int(when[1:]) if when.startswith('+') else int(when)
        except ValueError:
            raise ScriptError(f'line {no}: bad time {when!r}')
        words = rest.split()
        cmd = words[0] if words else ''
        try:
            if rest.startswith('M '):
                d = rest[2:].strip().split(':')
                if len(d) != 4:
                    raise ScriptError('M needs dx:dy:wheel:buttons')
                mouse.append(f'{t + offset}:{rest[2:].strip()}')
                x = max(0, min(639, x + int(d[0], 0))); y = max(0, min(359, y + int(d[1], 0)))
            elif cmd == 'shot' and len(words) == 1:
                shots.append((t + offset) / 1000.0)
            elif cmd == 'move' and len(words) == 3:
                mv(t, int(words[1]), int(words[2]), 100, 20, held)
            elif cmd == 'drag' and len(words) == 3:
                held = held or 1
                mv(t, int(words[1]), int(words[2]), 16, 30, held)
            elif cmd in ('click', 'press', 'release', 'dclick') and len(words) <= 2:
                b = BUTTONS[words[1]] if len(words) == 2 else 1
                if cmd == 'click':
                    mouse += [f'{t + offset}:0:0:0:{b}', f'{t + 80 + offset}:0:0:0:0']
                    held = 0
                elif cmd == 'dclick':
                    mouse += [f'{t + offset}:0:0:0:1', f'{t + 80 + offset}:0:0:0:0',
                              f'{t + 200 + offset}:0:0:0:1', f'{t + 280 + offset}:0:0:0:0']
                    held = 0
                elif cmd == 'press':
                    held = b
                    mouse.append(f'{t + offset}:0:0:0:{b}')
                else:
                    held = 0
                    mouse.append(f'{t + offset}:0:0:0:0')
            elif cmd == 'wheel' and len(words) == 2:
                mouse.append(f'{t + offset}:0:0:{int(words[1])}:{held}')
            elif cmd == 'key' and len(words) == 3:
                u, sh = key_of_name(words[1])
                ms = int(words[2])
                if sh:
                    keys.append((t, 0xE1, 1))
                keys.append((t + 2, u, 1)); keys.append((t + 2 + ms, u, 0))
                if sh:
                    keys.append((t + 4 + ms, 0xE1, 0))
            elif cmd in ('down', 'up') and len(words) == 2:
                u, _ = key_of_name(words[1])
                keys.append((t, u, 1 if cmd == 'down' else 0))
            else:
                k = t
                for usage, mods in strokes(rest):
                    if usage == 'raw':
                        keys.append((k, mods[0], int(mods[1])))
                        k += 50
                        continue
                    for m in mods:
                        keys.append((k, m, 1))
                    keys.append((k + 2, usage, 1))
                    keys.append((k + 22, usage, 0))
                    for m in reversed(mods):
                        keys.append((k + 24, m, 0))
                    k += 50
        except ScriptError as e:
            raise ScriptError(f'line {no}: {e}')
    keys.sort(key=lambda e: e[0])
    klist = [f'{k + offset}:{u:02x}:{d}' for k, u, d in keys]
    return klist, mouse, shots


def end_time(keys, mouse, shots):
    """The last event or shot, in ms."""
    ts = [float(k.split(':')[0]) for k in keys + mouse] + [s * 1000 for s in shots]
    return max(ts) if ts else 0


def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        return
    off = 0
    if '--offset' in args:
        i = args.index('--offset'); off = int(args[i + 1]); del args[i:i + 2]
    what = '--keys'
    for w in ('--keys', '--mouse', '--shots'):
        if w in args:
            what = w; args.remove(w)
    try:
        k, m, s = parse(open(args[0]).readlines(), off)
    except ScriptError as e:
        sys.exit(f'{args[0]}: {e}')
    if what == '--keys':
        print(','.join(k) or '0:0:0')
    elif what == '--mouse':
        print(','.join(m) or '0:0:0:0:0')
    else:
        print(' '.join(f'{x:g}' for x in s))


if __name__ == '__main__':
    main()
