#!/usr/bin/env python3
"""mousegen.py SRC > KEYS: absolute mouse points to a keys file (tests/files.src, tests/system.src).
SRC lines: '#...' copied; 'T key TEXT'; 'T move X Y'; 'T click'; 'T dclick'; 'T drag X Y'
(button held, small steps); 'T press'; 'T release'; 'T rclick' (the right button); (0.15)
'T rpress', 'T rdrag X Y', 'T rrelease' (the right button held). T in ms.
(0.15) A button change never comes before the end of the move before it: a click written
while the pointer is still on its way waits for it (it would land wherever the pointer
happened to be, which depends on the kernel's timing).
(0.29) 'T wait TEXT' and 'T shot' are passed on (tests/keyscript.py: a wait for a console
line, a screenshot that moves with the waits); T may be '+MS', after the line before.
(0.31) 'T still N', 'T change', 'T sound' are passed on too (keyscript.py's waits for a
still screen, a changed frame, a Lau note)."""
import sys
x, y = 320, 180
out = []
busy = 0                                # the end of the last move
prev = 0                                # the time of the line before (for '+MS')
def mv(t, tx, ty, step, dt, b):
    global x, y
    while (x, y) != (tx, ty):
        dx = max(-step, min(step, tx - x)); dy = max(-step, min(step, ty - y))
        out.append(f'{t} M {dx}:{dy}:0:{b}'); x += dx; y += dy; t += dt
    return t
for ln in open(sys.argv[1]):
    ln = ln.rstrip('\n')
    if not ln.strip(): continue
    if ln.startswith('#'): out.append(ln); continue
    t, cmd, *rest = ln.split(' ', 2)
    t = prev + int(t[1:]) if t.startswith('+') else int(t)
    prev = t
    if cmd in ('click', 'dclick', 'rclick', 'press', 'release', 'rpress', 'rrelease'): t = max(t, busy)
    if cmd == 'key': out.append(f'{t} {rest[0]}')
    elif cmd == 'wait': out.append(f'{t} wait {rest[0]}')
    elif cmd == 'shot': out.append(f'{t} shot')
    elif cmd == 'still': out.append(f'{t} still {rest[0]}')       # (0.31) keyscript.py's
    elif cmd in ('change', 'sound'): out.append(f'{t} {cmd}')
    elif cmd == 'move': a = rest[0].split(); busy = mv(t, int(a[0]), int(a[1]), 100, 50, 0)
    elif cmd == 'drag': a = rest[0].split(); busy = mv(t, int(a[0]), int(a[1]), 30, 60, 1)
    elif cmd == 'rdrag': a = rest[0].split(); busy = mv(t, int(a[0]), int(a[1]), 30, 60, 2)
    elif cmd == 'rpress': out.append(f'{t} M 0:0:0:2')
    elif cmd == 'rrelease': out.append(f'{t} M 0:0:0:0')
    elif cmd == 'click': out += [f'{t} M 0:0:0:1', f'{t + 80} M 0:0:0:0']
    elif cmd == 'dclick': out += [f'{t} M 0:0:0:1', f'{t + 80} M 0:0:0:0', f'{t + 200} M 0:0:0:1', f'{t + 280} M 0:0:0:0']
    elif cmd == 'rclick': out += [f'{t} M 0:0:0:2', f'{t + 80} M 0:0:0:0']
    elif cmd == 'press': out.append(f'{t} M 0:0:0:1')
    elif cmd == 'release': out.append(f'{t} M 0:0:0:0')
    else: raise SystemExit('bad ' + ln)
print('\n'.join(out))
