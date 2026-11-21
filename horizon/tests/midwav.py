#!/usr/bin/env python3
"""midwav.py EMU SD HORIZON.SYS [EMUFLAGS...] - (0.27) MIDI heard: the music engine's General
MIDI player on the OPL2 (REV $0C), through emu816's sound of the chip (--wav).

A small file is made with tools/mkmid.py's Track and write_smf: at 120 BPM, on the flute (GM 73)
of the built-in bank, A4, E5, A3 and C5 for 500 ms each (440, 659.3, 220 and 523.3 Hz), then a
rest of 500 ms, then an A-minor chord (A3 C4 E4) for 500 ms. It is played from the text shell
(`musicd /T/W.MID`) with --wav capturing the board's mix. Checked: early and late in each note
(50 ms from 100 ms and from 350 ms after its start, counted from the first sound) the pitch
heard (autocorrelation) is the note's, within 1 %; the rest is quiet; the chord sounds where
it should (louder than one note); nothing sounds before the first note (up to 10 ms before it,
its attack), and 1.5 s after the last note's end there is silence (no stuck note: within +-9,
the nine silent channels' -1 ripple); the song ends ("Ended").
Prints PASS / FAIL lines; exit 1 on a failure. Work files in build/midwav/."""
import importlib.util
import math
import os
import shutil
import struct
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('mkmid', os.path.join(here, '..', 'tools', 'mkmid.py'))
mkmid = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mkmid)

emu, sd, sysf = sys.argv[1:4]
flags = sys.argv[4:]
work = 'build/midwav'
shutil.rmtree(work, ignore_errors=True)
os.makedirs(work)

PPQN = 96                                    # 120 BPM: a quarter is 500 ms
NOTES = [(0, 69), (96, 76), (192, 57), (288, 72)]
CHORD = (480, (57, 60, 64))
END_MS = 3000


def hz(n):
    return 440 * 2 ** ((n - 69) / 12)


t0 = mkmid.Track('Midwav')
t0.tempo(0, 120)
t1 = mkmid.Track('Flute')
t1.prog(0, 0, 73)
t1.cc(0, 0, 7, 127)
for t, n in NOTES:
    t1.note(t, 96, 0, n, 112)
for n in CHORD[1]:
    t1.note(CHORD[0], 96, 0, n, 112)
mkmid.write_smf(f'{work}/w.mid', [t0, t1], ppqn=PPQN)

card = work + '/sd'
shutil.copytree(sd, card)
open(card + '/SYSTEM/NODESK', 'w').close()
os.makedirs(card + '/T')
shutil.copy(f'{work}/w.mid', card + '/T/W.MID')
keys = subprocess.run([sys.executable, os.path.join(here, 'keyscript.py'), '/dev/stdin'],
                      input='1500 {esc}\n+1500 musicd /T/W.MID\\n\n', capture_output=True, text=True,
                      check=True).stdout.strip()
wav = f'{work}/w.wav'
out = subprocess.run([emu] + flags + ['--headless', '--sd', card, '--max-seconds', '11', '--wav', wav,
                      '--keys', keys, sysf], capture_output=True, text=True).stdout
open(f'{work}/w.out', 'w').write(out)
shutil.rmtree(card, ignore_errors=True)
raw = open(wav, 'rb').read()[44:]
s = struct.unpack('<%dh' % (len(raw) // 2), raw)
L, R = s[0::2], s[1::2]


def f0(x):
    """the pitch of x: the shortest lag (48-480 samples: 100-1000 Hz) whose normalised
    autocorrelation comes within 5 % of the best, refined by a parabola"""
    n = len(x) - 482
    e0 = sum(v * v for v in x[:n]) or 1
    r = [0.0] * 482
    for lag in range(46, 482):
        r[lag] = sum(x[i] * x[i + lag] for i in range(n)) / e0
    best = max(r[48:481])
    lag = next(k for k in range(48, 481) if r[k] >= 0.95 * best and r[k] >= r[k - 1] and r[k] >= r[k + 1])
    a, b, c = r[lag - 1], r[lag], r[lag + 1]
    d = (a - c) / (2 * (a - 2 * b + c)) if a - 2 * b + c else 0
    return 48000 / (lag + d)


def rms(a, b):
    seg = L[a:b]
    return math.sqrt(sum(v * v for v in seg) / max(1, len(seg)))


bad = 0
log = []
loud = [i for i, v in enumerate(L) if abs(v) > 200]
ok = bool(loud) and 'Ended' in out and L == R
if ok:
    on = loud[0]
    ms = lambda t: on + int(t * 48)                          # noqa: E731
    for t, n in NOTES:
        w = t * 500 / PPQN
        for at in (100, 350):
            got = f0(L[ms(w + at):ms(w + at + 50) + 482])
            good = abs(got / hz(n) - 1) < 0.01
            log.append('note %d at %4d + %d ms: %.1f Hz (want %.1f) %s' % (n, w, at, got, hz(n), '' if good else '<-- wrong'))
            ok = ok and good
    one = rms(ms(100), ms(400))
    rest = rms(ms(2100), ms(2400))
    chord = rms(ms(2600), ms(2900))
    good = rest < one / 8 and chord > one * 1.3
    log.append('level: a note %.0f, the rest %.0f, the chord %.0f %s' % (one, rest, chord, '' if good else '<-- wrong'))
    ok = ok and good and max(abs(v) for v in L[:on - 480]) <= 9
    tail = L[ms(END_MS + 1500):]
    good = len(tail) > 48000 and max(abs(v) for v in tail) <= 9
    log.append('after the end: %d samples, at most %d %s' % (len(tail), max(abs(v) for v in tail) if tail else -1,
                                                              '' if good else '<-- not silent'))
    ok = ok and good
open(f'{work}/w.check', 'w').write('\n'.join(log) + '\n')
if ok:
    print('PASS  MIDI heard (--wav): A4 E5 A3 C5 at 120 BPM within 1 % of their pitches, the rest quiet, a chord, '
          'silence after the end')
else:
    print('FAIL  MIDI heard (--wav) (%s/w.check, %s/w.out)' % (work, work))
    bad += 1
sys.exit(1 if bad else 0)
