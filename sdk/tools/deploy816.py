#!/usr/bin/env python3
"""deploy816.py - put a program on the real Atari816 over the PC link (USB-C) and look at it.

    deploy816.py FILE [--dest /PATH/NAME] [--restart] [--type TEXT]... [--key NAME]...
                 [--wait SECONDS] [--shot OUT.png] [--port PORT] [--dry-run]

A thin wrapper around the PC link library of the core, core/tools/atari_link.py (the same
code as core/tools/atari.py: send, shot816, key). Needs pyserial (pip install pyserial)
and the board's firmware from the same release as core/tools.

  FILE            the file to copy to the SD card (a .PRG, a .BAS, a picture, ...)
  --dest PATH     where on the card (default /BIN/NAME: the shell then finds it by name;
                  at most 63 characters; the link upper-cases it)
  --restart       restart Horizon afterwards (the PC link's restart816: reloads
                  /SYSTEM/HORIZON.SYS from the card, like a reset)
  --type TEXT     type TEXT on the machine's keyboard (inputscript escapes: \\n Enter,
                  {esc}, {f10}, ^S ...); keys go to whatever has the focus
  --key NAME      press one key (a name as in inputscript: enter, esc, f10, up, a, ...)
  --wait S        wait S seconds (between the steps above and the shot; default 2)
  --shot OUT.png  screenshot of the native screen (atari.py shot816; about 6 s)
  --port PORT     the serial port (default: found automatically)
  --dry-run       print what would be done; touch nothing

Steps run in this order: send, restart, type / key (in the order given), wait, shot.

Typical use, with the Desktop running and a Terminal window focused:
    deploy816.py GEMRUN.PRG --type 'gemrun\\n' --wait 3 --shot gemrun.png

Not verified by the SDK author (written without access to the board): the key injection
reaching Horizon (it goes through the firmware's virtual keyboard), and sending a file
while Horizon has files open. A program started from the Desktop needs a Programs menu
entry (/SYSTEM/PROGRAMS on the card: Title=/path) or Files.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import inputscript  # noqa: E402


def core_tools():
    for p in (os.environ.get('ATARI_CORE_TOOLS'), os.path.join(HERE, '..', '..', 'core', 'tools')):
        if p and os.path.exists(os.path.join(p, 'atari_link.py')):
            return os.path.abspath(p)
    sys.exit('deploy816: core/tools/atari_link.py not found (set ATARI_CORE_TOOLS)')


def main():
    a = sys.argv[1:]
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); return 0
    f, dest, restart, steps, wait, shot, port, dry = None, None, False, [], 2.0, None, None, False
    i = 0
    while i < len(a):
        w = a[i]
        if w == '--dest': dest = a[i + 1]; i += 2
        elif w == '--restart': restart = True; i += 1
        elif w == '--type': steps.append(('type', a[i + 1])); i += 2
        elif w == '--key': steps.append(('key', a[i + 1])); i += 2
        elif w == '--wait': wait = float(a[i + 1]); i += 2
        elif w == '--shot': shot = a[i + 1]; i += 2
        elif w == '--port': port = a[i + 1]; i += 2
        elif w == '--dry-run': dry = True; i += 1
        elif w.startswith('--'): sys.exit(f'deploy816: unknown option {w}')
        else: f = w; i += 1
    if not f:
        sys.exit('deploy816: no file')
    data = open(f, 'rb').read()
    dest = dest or '/BIN/' + os.path.basename(f).upper()
    name = dest.lstrip('/').upper()
    if len(name) > 63:
        sys.exit(f'deploy816: {dest}: at most 63 characters on the link')
    strokes = []
    for kind, v in steps:
        try:
            if kind == 'type':
                strokes.append([s for s in inputscript.strokes(v)])
            else:
                u, sh = inputscript.key_of_name(v)
                strokes.append([(u, [0xE1] if sh else [])])
        except inputscript.ScriptError as e:
            sys.exit(f'deploy816: {e}')

    print(f'send {f} ({len(data)} bytes) -> /{name}')
    if restart:
        print('restart Horizon (restart816)')
    for (kind, v), ks in zip(steps, strokes):
        print(f'{kind} {v!r}: {len(ks)} key(s)')
    if shot:
        print(f'wait {wait:g} s, screenshot -> {shot}')
    if dry:
        return 0

    sys.path.insert(0, core_tools())
    from atari_link import AtariLink  # noqa: E402  (needs pyserial)
    with AtariLink(port) as link:
        link.send(data, name)
        print(f'OK: /{name} on the card')
        if restart:
            link.restart816(test=False)
            time.sleep(3)
        for ks in strokes:
            for usage, mods in ks:
                if usage == 'raw':
                    continue
                mod = 0
                for m in mods:                 # HID modifier usages -> modifier bits
                    mod |= 1 << (m - 0xE0)
                link.key(usage, mod=mod, hold_ms=60)
                time.sleep(0.12)
        if shot:
            time.sleep(wait)
            s = link.shot816(shot)
            print(f'{shot}: {s.width}x{s.height}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
