#!/usr/bin/env python3
"""tests/heapcheck.py CARD CONSOLE - does every board of the three episodes leave room in
the heap for the longest text window (make test, tests/check.sh)?

The heap holds, while a board is played, its texts (objs[].inside: loadboard mallocs each)
and, when a text window opens (text_get, horizon/hz_snd.c), the text: the longest is the
help (F1 in a level, INSTRUCTIONS on the title's menu: 4,313 bytes in each episode).
CONSOLE is the scripted game's console: its first "xargon: heap before ...: F free, L in
one piece" line is the heap at a board's start, measured (XARGON1.PRG's: XARGON2 and 3
link differently, their heaps a few hundred bytes apart, but no board of theirs comes
within 1 KB of the limit). A board's texts are taken from its file (as loadboard reads
them) and laid out as cc816's malloc does (a 4-byte header, even sizes, first fit from a
block's end), with both files closed while the room is taken (loadboard, text_get): the
largest piece left is L - texts, and it must hold the longest text. The boards played
only from a macro (DEMO*: the macro reads the keys) and the story (pageview: no text
windows) are not counted."""
import glob
import os
import re
import struct
import sys

HDR = 4


def blk(n):
    return max((n + HDR + 1) & ~1, HDR + 2)


def texts(path):
    """the heap a board's texts take (and how many)"""
    d = open(path, 'rb').read()
    o = 128 * 64 * 2                    # bd[128][64]
    n = struct.unpack_from('<h', d, o)[0]
    o += 2
    objs = [d[o + i * 31:o + i * 31 + 31] for i in range(n)]    # objtype: 31 bytes
    o += n * 31 + 96 + 1                # pl (pltype: 96), cnt_fruit
    total = count = 0
    for r in objs:
        if struct.unpack_from('<I', r, 23)[0]:      # inside (a far pointer) not NULL
            ln = struct.unpack_from('<h', d, o)[0]
            o += 2 + ln + 1
            total += blk(ln + 1)
            count += 1
    if o != len(d):
        raise SystemExit('heapcheck: %s: %d bytes left after its texts' % (path, len(d) - o))
    return total, count


def main():
    card, console = sys.argv[1], sys.argv[2]
    m = None
    for line in open(console, 'rb').read().decode('latin-1').splitlines():
        m = re.match(r'xargon: heap before \S+: (\d+) free, (\d+) in one piece', line)
        if m:
            break
    if not m:
        print('FAIL  heap: no "xargon: heap before" line in %s' % console)
        return 1
    free, largest = int(m.group(1)), int(m.group(2))
    worst = None
    bad = []
    for ep in '123':
        audio = os.path.join(card, 'AUDIO.XR' + ep)
        lens = struct.unpack_from('<40h', open(audio, 'rb').read(), 50 * 8 + 40 * 4)
        need = blk(max(lens))
        for path in sorted(glob.glob(os.path.join(card, '*.XR' + ep))):
            name = os.path.basename(path)
            if not re.match(r'(BOARD_\d+|MAP|INTRO)\.', name):
                continue
            t, c = texts(path)
            left = largest - t
            if worst is None or left - need < worst[0]:
                worst = (left - need, name, t, c, left, need)
            if left < need:
                bad.append('%s (texts %d bytes: %d in one piece, the text needs %d)'
                           % (name, t, left, need))
    if bad:
        print('FAIL  heap: no room for the longest text window on ' + '; '.join(bad))
        return 1
    print('PASS  heap: every board leaves room for the longest text window (heap %d free, '
          '%d in one piece; the tightest %s: texts %d bytes in %d pieces, %d left in one '
          'piece for %d)' % (free, largest, worst[1], worst[2], worst[3], worst[4], worst[5]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
