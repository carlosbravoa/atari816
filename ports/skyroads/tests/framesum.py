#!/usr/bin/env python3
"""framesum.py - the checksums hz_main.c's /CHECK prints, of frames on the PC.

    framesum.py FRAMES.raw > sums.txt     (frames of 64000 pixels + 768 palette bytes:
                                           srtool demo-frames, or the C++ ref_frames)
    framesum.py --compare FRAMES.raw console.txt
"""
import sys


def fsum(b):
    a = s = 0
    for i in range(0, len(b), 2):
        a = (a + b[i] + (b[i + 1] << 8)) & 0xFFFF
        s = (s + a) & 0xFFFF
    return (s << 16) | a


def sums(path):
    data = open(path, 'rb').read()
    n = len(data) // 64768
    for k in range(n):
        f = data[k * 64768:(k + 1) * 64768]
        yield '%08x %08x' % (fsum(f[:64000]), fsum(f[64000:]))


if __name__ == '__main__':
    if sys.argv[1] == '--compare':
        ref = list(sums(sys.argv[2]))
        got = {}
        for line in open(sys.argv[3], errors='replace'):
            p = line.split()
            if len(p) == 4 and p[0] == 'c':
                got[int(p[1])] = p[2] + ' ' + p[3]
        bad = [k for k in range(len(ref)) if got.get(k) != ref[k]]
        print('framesum: %d frames of %d match%s' % (len(ref) - len(bad), len(ref),
              '' if not bad else '; first differing: %s' % bad[:10]))
        sys.exit(1 if bad or len(got) != len(ref) else 0)
    for i, s in enumerate(sums(sys.argv[1])):
        print(i, s)
