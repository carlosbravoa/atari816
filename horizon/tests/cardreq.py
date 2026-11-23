#!/usr/bin/env python3
"""cardreq.py LBL ERR [FROM TO] - (0.31) the card requests of an emu816 run, one line each:
"T OP PATH" (T in seconds; PATH for the requests that name one). The run is made with
  --watch 00B000:1000 --watch KPATH:80 --watch-max 3000000
(the mailbox's request ring, $00:B000, and the kernel's path buffer kpath, whose address is
in build/horizon.lbl: python3 tests/cardreq.py --watch build/horizon.lbl prints both
options). A request is the write of the first byte of a 16-byte slot of the ring; its path
is what kpath holds then (the kernel resolves every path there before it sends the
request). FROM, TO (seconds): only the requests between them.
cardreq.py --menu LBL ERR FROM TO: make test-31's summary (menu() below)."""
import sys

NM = {1: 'OPEN', 2: 'CLOSE', 3: 'READ', 4: 'WRITE', 5: 'SEEK', 6: 'STAT', 7: 'READDIR',
      8: 'MKDIR', 9: 'DELETE', 10: 'RENAME', 16: 'LOAD'}
PATHOPS = {'OPEN', 'STAT', 'READDIR', 'MKDIR', 'DELETE', 'RENAME', 'LOAD'}


def kpath(lbl):
    for ln in open(lbl):
        p = ln.split()
        if len(p) == 3 and p[2] == '.kpath':
            return int(p[1], 16)
    sys.exit('cardreq: no kpath in ' + lbl)


def requests(lbl, err):
    kp = kpath(lbl)
    buf = bytearray(128)
    out = []
    for ln in open(err, errors='replace'):
        if not ln.startswith('watch '):
            continue
        p = ln.split()
        try:
            i = p.index('=')
            a = int(p[i - 1][1:], 16)
            v = int(p[i + 1][1:], 16)
            t = int(p[1]) / 1e6
        except (ValueError, IndexError):
            continue
        if kp <= a < kp + 128:
            buf[a - kp] = v
        elif 0xB000 <= a < 0xC000 and a % 16 == 0:
            op = NM.get(v, 'op$%02X' % v)
            path = bytes(buf).split(b'\0')[0].decode('latin-1') if op in PATHOPS else ''
            out.append((t, op, path))
    return out


BACKGROUND = ('/PRN:', '/PC:', '/Desktop', '/Printouts')


def menu(lbl, err, lo, hi):
    """(make test-31) the Programs menu's card requests: those between lo and hi besides the
    Desktop's timers (/PRN: every second, /PC: and /Desktop every 5 s, /Printouts), and how
    often the menu was read in the run"""
    rq = requests(lbl, err)
    win = [r for r in rq if lo <= r[0] < hi and r[1] in PATHOPS and not r[2].startswith(BACKGROUND)]
    print('menu: %g-%g s: %d card requests besides the timers' % (lo, hi, len(win)))
    for t, op, path in win:
        print('menu:   %.3f %s %s' % (t, op, path))
    n = lambda op, path: sum(1 for r in rq if r[1] == op and r[2].upper() == path)
    print('menu: /SYSTEM/PROGRAMS read %d times, /APPS listed %d times, /SYSTEM/APPS.NEW looked for %d times'
          % (n('OPEN', '/SYSTEM/PROGRAMS'), n('READDIR', '/APPS'), n('STAT', '/SYSTEM/APPS.NEW')))


if __name__ == '__main__':
    if sys.argv[1] == '--menu':
        menu(sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]))
        sys.exit(0)
    if sys.argv[1] == '--watch':
        print('--watch 00B000:1000 --watch %06X:80 --watch-max 3000000' % kpath(sys.argv[2]))
        sys.exit(0)
    lo, hi = (float(sys.argv[3]), float(sys.argv[4])) if len(sys.argv) > 4 else (0, 1e9)
    for t, op, path in requests(sys.argv[1], sys.argv[2]):
        if lo <= t < hi:
            print('%.3f %s %s' % (t, op, path))
