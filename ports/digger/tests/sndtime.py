#!/usr/bin/env python3
"""sndtime.py EMU.ERR [FROM_S TO_S] - the timing of POKEY's writes in an emu816 log made
with --log-sound-us ("sound US $DBxx = $yy"): Digger's sound steps (soundint, 72.8 a second)
should change the voices on a grid of 13,736 us. The writes are grouped (those within 1 ms
are one step); for each step after the first: how far it is from the nearest point of the
grid continued from the step before (us), and how many steps came less than 6 ms after the
one before (two steps in a row: the first one heard for almost nothing).
Voice 0 (effects: $DB00-$DB03) and voice 1 (music: $DB04-$DB07) separately."""
import re
import sys

STEP = 13736.0


def main():
    a = sys.argv[1:]
    t0 = float(a[1]) * 1e6 if len(a) > 1 else 0
    t1 = float(a[2]) * 1e6 if len(a) > 2 else 1e18
    ev = {0: [], 1: []}
    for ln in open(a[0], encoding='latin-1'):
        m = re.match(r'sound (\d+) \$DB0([0-7]) = ', ln)
        if not m:
            continue
        t = int(m.group(1))
        if t0 <= t <= t1:
            ev[int(m.group(2)) // 4].append(t)
    for v, ts in ev.items():
        steps = []
        for t in ts:
            if not steps or t - steps[-1] > 1000:
                steps.append(t)
        devs, close = [], 0
        for p, q in zip(steps, steps[1:]):
            d = q - p
            if d < 6000:
                close += 1
            k = max(1, round(d / STEP))
            devs.append(abs(d - k * STEP))
        if devs:
            devs.sort()
            print(f'voice {v}: {len(steps)} steps; off the 13.7 ms grid by {sum(devs)/len(devs):.0f} us '
                  f'on average, {devs[len(devs)//2]:.0f} median, {devs[int(len(devs)*0.95)]:.0f} '
                  f'95th percentile, {devs[-1]:.0f} most; {close} steps < 6 ms after the one before')
        else:
            print(f'voice {v}: no steps')


if __name__ == '__main__':
    main()
