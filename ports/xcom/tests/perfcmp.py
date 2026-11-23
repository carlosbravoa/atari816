#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/perfcmp.py BOARD.TXT EMU.TXT: two /M reports of the same run (horizon/hz_perf.c),
# the board's and the emulator's: their TOTAL tables side by side (ms, ms per call, the
# emulator's figure over the board's) and the per-file table. Lines: "what calls ms avg max KB".
import re, sys

def load(path):
    t, files, sec, cur = {}, {}, None, None
    for line in open(path, encoding='latin-1'):
        if line.startswith('== TOTAL'):
            sec = 'total'
            continue
        if sec != 'total':
            continue
        m = re.match(r'  (\w+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)$', line)
        if m:
            t[m.group(1)] = (int(m.group(2)), float(m.group(3)))
        m = re.match(r'  wall (\d+) ms, idle .*? (\d+) %', line)
        if m:
            t['WALL'], t['IDLE%'] = (0, float(m.group(1))), (0, float(m.group(2)))
        m = re.match(r'    (\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$', line)
        if m:
            files[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)))
    return t, files

b, bf = load(sys.argv[1])
e, ef = load(sys.argv[2])
print('%-10s %8s %10s %10s %9s %9s %7s' % ('what', 'calls', 'board ms', 'emu ms', 'board/c', 'emu/c', 'emu/bd'))
for k in sorted(set(b) | set(e)):
    nb, mb = b.get(k, (0, 0.0))
    ne, me = e.get(k, (0, 0.0))
    print('%-10s %8s %10.1f %10.1f %9.2f %9.2f %7.2f' % (k, '%d/%d' % (nb, ne) if nb != ne else nb, mb, me,
          mb / nb if nb else 0, me / ne if ne else 0, me / mb if mb else 0))
print('\n%-14s %13s %13s %7s' % ('file', 'board ms', 'emu ms', 'emu/bd'))
for k in sorted(set(bf) | set(ef)):
    mb = bf.get(k, (0, 0, 0, 0))[3]
    me = ef.get(k, (0, 0, 0, 0))[3]
    print('%-14s %13d %13d %7.2f' % (k, mb, me, me / mb if mb else 0))
