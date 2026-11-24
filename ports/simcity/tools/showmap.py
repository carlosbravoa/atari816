#!/usr/bin/env python3
"""tools/showmap.py DUMP [X0 Y0 W H]: the map of a simtest dump as characters (for a
person reading a test's city): . dirt ~ water T trees # road = rail + wire, R C I zones'
centres (r c i their other tiles), P power plant, * fire, ! powered zone centre."""
import sys
L = open(sys.argv[1]).read().split('\n')
x0, y0, w, h = (int(a) for a in sys.argv[2:6]) if len(sys.argv) > 5 else (0, 0, 120, 100)
def ch(v):
    t = v & 1023
    z = v & 1024
    p = v & 0x8000
    if t == 0: return '.'
    if 2 <= t <= 20: return '~'
    if 21 <= t <= 43: return 'T'
    if 44 <= t <= 47: return ':'
    if 56 <= t <= 63: return '*'
    if 64 <= t <= 207: return '#'
    if 208 <= t <= 222: return '+'
    if 224 <= t <= 238: return '='
    if 240 <= t <= 422: return ('!' if p else 'R') if z else 'r'
    if 423 <= t <= 611: return ('!' if p else 'C') if z else 'c'
    if 612 <= t <= 692: return ('!' if p else 'I') if z else 'i'
    if 745 <= t <= 760: return 'P'
    return '?'
for y in range(y0, y0 + h):
    row = L[1 + y]
    print(''.join(ch(int(row[4*x:4*x+4], 16)) for x in range(x0, x0 + w)))
