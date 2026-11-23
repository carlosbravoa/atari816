#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tests/compare.py NAME DIR LOG: one run of make test (tests/check.sh), the Atari816's
against the host's. DIR/host: the host's run (host.txt its lines, shotNNNN.ppm, card/LOG);
DIR/816: run816's (console.txt, autoN.png, card/GAMES/XCOM/LOG). Checks:

  - the LOG: every line the host's, except the lines listed in MAY_DIFFER (each with its
    reason: the build's own numbers, not the game's);
  - the run's pictures: the same list (number, virtual time, checksum of A000 and the DAC,
    why) on both, and the run's end;
  - the emulator's picture at each (autoN.png: the screen as Marga showed it, 320 x 180
    rows of the 320 x 200 from the pan printed) equal pixel for pixel to the host's PPM;
  - the files the run wrote (saves) equal byte for byte, for the names in FILES.

Prints PASS / FAIL lines; exit 1 on any FAIL."""
import os
import re
import sys

from PIL import Image

# LOG lines that may differ between the builds, and why
MAY_DIFFER = [
    # the VGA back buffer's segment: where the DOS heap put it, after blocks whose sizes
    # are the structures' (pointers are 8 bytes on the host, 4 on the Atari816)
    (re.compile(r'^video: VGA prototype .*buffer at [0-9A-F]{4}$'), 'the back buffer\'s segment'),
    # all free DOS memory (main.c dos_total_kb): the battle pack's tables of sprite
    # pointers (pak.c load_sprite_table, load_race: (n + 1) * sizeof(unsigned char *)) are
    # 8 bytes an entry on the host, 4 on the Atari816 (DOS: 4), about 1 KB more in use
    (re.compile(r'.*free (memory )?\d+ KB \(\d+ KB in all'), 'sprite pointer tables'),
]

SHOT = re.compile(r'xcom: shot (\d+) at (\d+) ms sum ([0-9a-f]{8}) \((.*?)\)(?: pan (-?\d+))?')
END = re.compile(r'xcom: end at (\d+) ms')


def lines(path):
    try:
        with open(path, encoding='latin-1') as f:
            return f.read().replace('\r', '').split('\n')
    except OSError:
        return None


def main():
    name, d, log = sys.argv[1], sys.argv[2], sys.argv[3]
    bad = 0

    def ok(s):
        print(f'PASS  {name}: {s}')

    def fail(s):
        nonlocal bad
        bad += 1
        print(f'FAIL  {name}: {s}')

    con = lines(f'{d}/816/console.txt') or []
    host = lines(f'{d}/host.txt') or []
    kill = [c for c in con if '[kill]' in c]
    if kill:
        fail(f'the Atari816 run was killed: {kill[0].strip()}')
    err = lines(f'{d}/816/emu.err') or []
    rule = [e for e in err if 'emu816: blitter:' in e]
    if rule:
        fail(f'emu816: a blitter rule broken ({len(rule)} times): {rule[0].strip()}')
    blit = [c.strip() for c in con if 'xcom: blitter:' in c and ' draws, ' not in c]
    if blit:
        fail(f'the blitter back end said: {blit[0]}')

    # ---- the LOG
    if log:
        h = lines(f'{d}/host/card/{log}')
        a = lines(f'{d}/816/card/GAMES/XCOM/{log}')
        if h is None or a is None:
            fail(f'no {log} ({"host" if h is None else "Atari816"})')
        else:
            diffs, allowed = [], []
            for i in range(max(len(h), len(a))):
                x = h[i] if i < len(h) else '(none)'
                y = a[i] if i < len(a) else '(none)'
                if x == y:
                    continue
                why = [w for r, w in MAY_DIFFER if r.match(x) and r.match(y)]
                (allowed if why else diffs).append((i + 1, x, y, why))
            if diffs:
                fail(f'{log}: {len(diffs)} lines differ from the host\'s:')
                for n, x, y, _ in diffs[:5]:
                    print(f'        line {n}: host    {x}\n        line {n}: Atari816 {y}')
            else:
                ok(f'{log}: {len([x for x in h if x])} lines as the host\'s'
                   + (f' ({len(allowed)} allowed: {", ".join(sorted(set(w[0] for *_, w in allowed)))})'
                      if allowed else ''))
            # a battle loaded in the run: its state (the engine's checksums of the units,
            # the map, the fog, the AI, the random number) as when it was saved
            saved = [x.split(':', 1)[1] for x in a if x.startswith('bsave state:')]
            loaded = [x.split(':', 1)[1] for x in a if x.startswith('bload state:')]
            if loaded:
                if all(x in saved for x in loaded):
                    ok(f'{log}: {len(loaded)} battle(s) loaded back with the state they were '
                       f'saved with ({loaded[0].strip()[:60]}...)')
                else:
                    fail(f'{log}: a battle loaded with another state than saved: '
                         f'{[x for x in loaded if x not in saved][0].strip()}')
            # tests/bsave.keys: the same keys after the save and after the load: the
            # battle goes on the same way (the moves, the alien turns, the round's end)
            if name == 'bsave':
                b = [x for x in a if not x.startswith(('ARROW', 'MARKS'))]
                try:
                    s0 = next(i for i, x in enumerate(b) if x.startswith('bsave state:')) + 1
                    s1 = next(i for i in range(s0, len(b)) if 'load slot' in b[i]) - 1
                    l0 = next(i for i, x in enumerate(b) if x.startswith('bload state:'))
                    l0 = next(i for i in range(l0, len(b)) if 'setup:' in b[i]) + 1
                    l1 = next(i for i in range(l0, len(b)) if b[i] == 'script finished')
                    one, two = b[s0:s1], b[l0:l1]
                    while one and 'options window' in one[-1]:
                        one.pop()
                    if one == two and len(one) > 10:
                        ok(f'{log}: after the load the battle went on as after the save '
                           f'({len(one)} lines, two alien turns)')
                    else:
                        fail(f'{log}: after the load the battle went on otherwise than after '
                             f'the save ({len(one)} / {len(two)} lines)')
                except StopIteration:
                    fail(f'{log}: no save and load in it')

    # ---- the open files (Horizon: 4 in the whole system; plat/xdos.c refuses a fifth
    # on both builds and says so)
    FILES = re.compile(r'xcom: files: at most (\d+) open \((.*?)\), (\d+) refused')
    hf = [m for m in map(FILES.search, host) if m]
    af = [m for m in map(FILES.search, con) if m]
    refused = [c.strip() for c in host + con if re.search(r'xcom: files: .* refused: ', c)]
    if refused:
        fail(f'a file was refused (4 open): {refused[0]}')
    elif hf and af:
        if hf[-1].group(1) == af[-1].group(1):
            ok(f'at most {af[-1].group(1)} files open at once on both ({af[-1].group(2)}), none refused')
        else:
            fail(f'files open at once: host {hf[-1].group(1)} ({hf[-1].group(2)}), '
                 f'Atari816 {af[-1].group(1)} ({af[-1].group(2)})')

    # ---- BENCH's report (upstream's own checks of the renderer; with the virtual clock
    # its times are the clock's readings, the same on both)
    h = lines(f'{d}/host/card/BENCH.TXT')
    if h is not None:
        a = lines(f'{d}/816/card/GAMES/XCOM/BENCH.TXT')
        if a is None:
            fail('no BENCH.TXT from the Atari816')
        elif a == h:
            checks = [x for x in h if 'check' in x.lower() or 'match' in x]
            ok(f'BENCH.TXT: {len([x for x in h if x])} lines as the host\'s ({len(checks)} '
               f'checks of upstream\'s, e.g. "{checks[0] if checks else ""}")')
        else:
            n = [i for i in range(max(len(a), len(h))) if (a[i:i + 1] or [None]) != (h[i:i + 1] or [None])]
            fail(f'BENCH.TXT: {len(n)} lines differ from the host\'s, the first:')
            i = n[0]
            print(f'        host     {h[i] if i < len(h) else "(none)"}\n'
                  f'        Atari816 {a[i] if i < len(a) else "(none)"}')

    # ---- the pictures' list
    hs = [m.groups() for m in map(SHOT.search, host) if m]
    as_ = [m.groups() for m in map(SHOT.search, con) if m]
    he = [m.group(1) for m in map(END.search, host) if m]
    ae = [m.group(1) for m in map(END.search, con) if m]
    if not hs:
        fail('the host took no pictures')
    if [x[:4] for x in hs] == [x[:4] for x in as_]:
        ok(f'{len(hs)} pictures at the same virtual times with the same checksums '
           f'(the last at {hs[-1][1] if hs else 0} ms)')
    else:
        fail(f'pictures: host {len(hs)}, Atari816 {len(as_)}; first difference:')
        for i in range(max(len(hs), len(as_))):
            x = hs[i] if i < len(hs) else None
            y = as_[i] if i < len(as_) else None
            if x is None or y is None or x[:4] != y[:4]:
                print(f'        host     {x}\n        Atari816 {y}')
                break
    if he and he == ae:
        ok(f'the run ended at the same virtual time ({he[0]} ms)')
    else:
        fail(f'the end: host {he}, Atari816 {ae} (no "xcom: end": the run took longer than '
             f'its --seconds, or stopped)')

    # ---- what the emulator showed
    shown = 0
    for k, s in enumerate(as_, 1):
        p = f'{d}/816/auto{k}.png'
        n, pan = int(s[0]), int(s[4] or 0)
        q = f'{d}/host/shot{n:04d}.ppm'
        if not os.path.exists(p) or not os.path.exists(q):
            fail(f'picture {n}: {"no " + p if not os.path.exists(p) else "no " + q}')
            continue
        em = Image.open(p).convert('RGB').resize((320, 180), Image.NEAREST)
        full = Image.open(q).convert('RGB')
        if pan >= 1000:
            # the battle view split: its rows pan - 1000 .. + 123, then the panel's 144-199
            ho = Image.new('RGB', (320, 180))
            ho.paste(full.crop((0, pan - 1000, 320, pan - 1000 + 124)), (0, 0))
            ho.paste(full.crop((0, 144, 320, 200)), (0, 124))
        else:
            ho = full.crop((0, pan, 320, pan + 180))
        if em.tobytes() == ho.tobytes():
            shown += 1
        else:
            a, b = em.load(), ho.load()
            nd = sum(1 for y in range(180) for x in range(320) if a[x, y] != b[x, y])
            fail(f'picture {n} ({s[3]}, {s[1]} ms): the emulator\'s screen differs from the '
                 f'host\'s (pan {pan}) in {nd} of 57,600 pixels ({p})')
    if as_ and shown == len(as_):
        ok(f'the emulator showed all {shown} pictures as the host\'s, pixel for pixel')

    # ---- files written (saves)
    for f in sorted(os.listdir(f'{d}/host/card')):
        if not f.upper().endswith('.SAV'):
            continue
        a = f'{d}/816/card/GAMES/XCOM/{f.upper()}'
        hb = open(f'{d}/host/card/{f}', 'rb').read()
        ab = open(a, 'rb').read() if os.path.exists(a) else None
        if ab is None:
            fail(f'{f}: written by the host, not by the Atari816')
        elif ab == hb:
            ok(f'{f}: {len(hb)} bytes, the host\'s byte for byte')
        else:
            k = next((i for i in range(min(len(hb), len(ab))) if hb[i] != ab[i]), min(len(hb), len(ab)))
            fail(f'{f}: host {len(hb)} bytes, Atari816 {len(ab)}; first difference at byte {k}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
