#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/smooth.py CONSOLE [--gap MS] [--frame MS]: what a player feels in a /M run (horizon/
# hz_perf.c), from its console.txt: the gaps between event polls (the pointer and the
# input stand still) and the frames (a present after the CPU worked without looking for
# input) over /M's limits, the player's ones (not under the hourglass, not while
# loading, not /M's own report), by what ran in them; the battle view's frame rates
# while it scrolls and while a soldier walks (the presents /M logged). With --gap /
# --frame: exit 1 when the player's longest gap / frame is over that many ms.
import re
import sys


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__ if __doc__ else 'tests/smooth.py CONSOLE [--gap MS] [--frame MS]')
        return 2
    path, lim = a[0], {}
    for i in range(1, len(a) - 1, 2):
        lim[a[i].lstrip('-')] = int(a[i + 1])
    gaps, frames, pres = [], [], []
    for line in open(path, errors='replace'):
        m = re.search(r'xcom: (gap|frame) +(\d+) ms at ([\d.]+) \(on ([\d.]+)\) (\w)(.)( \(\d+ apart\))?: (.*)', line)
        if m:
            kind, ms, flag, what = m.group(1), int(m.group(2)), m.group(6), m.group(8)
            if flag == ' ':
                (gaps if kind == 'gap' else frames).append((ms, float(m.group(3)), what))
            continue
        m = re.search(r'xcom: presents (.*)', line)
        if m:
            for w in m.group(1).split():
                t, f = w.split(':')
                pres.append((int(t), int(f)))
    fail = 0
    for name, lst, key in (('gaps between polls (the pointer still)', gaps, 'gap'),
                           ('frames (the view still while the CPU worked)', frames, 'frame')):
        lst.sort(reverse=True)
        top = lst[0][0] if lst else 0
        print('%s: %d over /M\'s limit, the longest %d ms' % (name, len(lst), top))
        for ms, t, what in lst[:6]:
            print('  %5d ms at %7.3f s: %s' % (ms, t, what))
        if key in lim and top > lim[key]:
            print('smooth: FAILED: the longest %s is %d ms, over %d' % (key, top, lim[key]))
            fail = 1
    # frame rates: a present after a scroll (flag 1) or an effect (2: a walk's step),
    # its interval from the present before (under 1 s)
    for name, bit in (('scrolling (the view moved)', 1), ('walking (a step\'s present)', 2)):
        iv = [pres[i][0] - pres[i - 1][0] for i in range(1, len(pres))
              if pres[i][1] & bit and not (bit == 2 and pres[i][1] & 1)
              and pres[i][0] - pres[i - 1][0] < 1000]
        if not iv:
            print('%s: no presents' % name)
            continue
        iv.sort()
        med = iv[len(iv) // 2]
        print('%s: %d presents, %.1f a second (median %d ms apart, the slowest %d ms)'
              % (name, len(iv), 1000.0 / med if med else 0, med, iv[-1]))
    return fail


if __name__ == '__main__':
    sys.exit(main())
