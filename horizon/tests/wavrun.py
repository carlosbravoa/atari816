#!/usr/bin/env python3
"""wavrun.py EMU SD HORIZON.SYS [EMUFLAGS...] - (0.26) WAV playback by the music engine.

Three WAV files are made (16-bit stereo 44,100 Hz: 440 Hz left, 660 Hz right, 1.5 s; 8-bit
unsigned mono 22,050 Hz: 330 Hz, 1 s; 16-bit mono 48,000 Hz with a LIST chunk before "data":
550 Hz, 1 s) and each is played from the shell (`musicd FILE`) with emu816 --wav capturing Lau's
output. Checked: the tone of each side (zero crossings), that the left and right are kept apart,
how long it sounds (+-60 ms), and that the program ends ("Ended"). Prints PASS / FAIL lines."""
import math
import os
import shutil
import struct
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
emu, sd, sysf = sys.argv[1:4]
flags = sys.argv[4:]
work = 'build/wavrun'
shutil.rmtree(work, ignore_errors=True)
os.makedirs(work)


def riff(ch, rate, bits, data, extra=b''):
    fmt = struct.pack('<HHIIHH', 1, ch, rate, rate * ch * bits // 8, ch * bits // 8, bits)
    body = b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt + extra + \
        b'data' + struct.pack('<I', len(data)) + data
    return b'RIFF' + struct.pack('<I', len(body)) + body


def tone(f, rate, n, amp):
    return [int(amp * math.sin(2 * math.pi * f * i / rate)) for i in range(n)]


files = []
l, r = tone(440, 44100, 66150, 20000), tone(660, 44100, 66150, 20000)
files.append(('ST16.WAV', riff(2, 44100, 16, b''.join(struct.pack('<hh', a, b) for a, b in zip(l, r))),
              440, 660, 1.5))
m = tone(330, 22050, 22050, 100)
files.append(('M8.WAV', riff(1, 22050, 8, bytes(128 + v for v in m)), 330, 330, 1.0))
m = tone(550, 48000, 48000, 20000)
files.append(('M16.WAV', riff(1, 48000, 16, b''.join(struct.pack('<h', v) for v in m),
                              b'LIST' + struct.pack('<I', 6) + b'INFOab'), 550, 550, 1.0))


def freq(x, rate=48000):
    z = [i for i in range(1, len(x)) if x[i - 1] < 0 <= x[i]]
    return (len(z) - 1) * rate / (z[-1] - z[0]) if len(z) > 2 else 0


bad = 0
for name, data, fl, fr, secs in files:
    card = work + '/sd'
    shutil.rmtree(card, ignore_errors=True)
    shutil.copytree(sd, card)
    open(card + '/SYSTEM/NODESK', 'w').close()
    open(card + '/' + name, 'wb').write(data)
    keys = subprocess.run([sys.executable, os.path.join(here, 'keyscript.py'), '/dev/stdin'],
                          input='1500 {esc}\n+1500 musicd /%s\\n\n' % name, capture_output=True,
                          text=True, check=True).stdout.strip()
    wav = f'{work}/{name}.out.wav'
    out = subprocess.run([emu] + flags + ['--headless', '--sd', card, '--max-seconds', str(7 + secs),
                          '--wav', wav, '--keys', keys, sysf], capture_output=True, text=True).stdout
    open(f'{work}/{name}.out', 'w').write(out)
    shutil.rmtree(card, ignore_errors=True)
    raw = open(wav, 'rb').read()[44:]
    os.remove(wav)
    L = [struct.unpack_from('<h', raw, i)[0] for i in range(0, len(raw) - 3, 4)]
    R = [struct.unpack_from('<h', raw, i)[0] for i in range(2, len(raw) - 1, 4)]
    loud = [i for i in range(len(L)) if abs(L[i]) > 200 or abs(R[i]) > 200]
    if not loud:
        print('FAIL  WAV %s: silent' % name)
        bad += 1
        continue
    a, b = loud[0], loud[-1]
    dur = (b - a) / 48000
    gl, gr = freq(L[a:b]), freq(R[a:b])
    pl, pr = max(abs(v) for v in L[a:b]), max(abs(v) for v in R[a:b])
    apart = True
    if fl != fr:                       # stereo: the other tone must not leak into a side
        apart = abs(gl - fl) < 3 and abs(gr - fr) < 3
    ok = abs(gl - fl) < 3 and abs(gr - fr) < 3 and abs(dur - secs) < 0.06 and apart and 'Ended' in out
    print('%s  WAV %s: %.1f Hz left, %.1f Hz right (want %d, %d), peaks %d / %d, %.3f s (want %.1f)'
          % ('PASS' if ok else 'FAIL', name, gl, gr, fl, fr, pl, pr, dur, secs))
    bad += not ok
sys.exit(1 if bad else 0)
