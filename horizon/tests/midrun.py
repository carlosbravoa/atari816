#!/usr/bin/env python3
"""midrun.py EMU SD HORIZON.SYS [EMUFLAGS...] - (0.27) MIDI on the OPL2: the music engine's
General MIDI player (user/midplay.s in /SYSTEM/MUSICD.PRG) at the board's speed.

Small deterministic files are made here with tools/mkmid.py's Track and write_smf, played
from the text shell (`musicd /T/NAME.MID`, plays once) in emu816 with --log-opl-us, and the
OPL2 register stream is read back: every key-on and key-off of the nine channels with its time,
its pitch from the F-number and block.

1. song.mid: melodic notes at 120 BPM then 60 BPM (a Set Tempo in the conductor track): the
   key-ons in order, their relative pitches, and the key-on and key-off times against the
   file's (from the first key-on, -1 .. +8 ms: the engine's 5 ms tick); a held chord while 12
   different drums play (more than the free voices): no chord note is cut short by a drum.
2. cc121.mid: a note held by the sustain pedal is released by Reset All Controllers (CC 121).
3. smpte.mid: SMPTE division (25 fps x 40 = 1000 ticks a second) with a Set Tempo in it, which
   must change nothing: the second note 500 ms after the first.
4. Broken files (no hang, the engine not killed): a chunk
   whose length wraps the address ($FFFFFFF8: the shell is back, `ls` answers); a track whose
   delta is the largest a file can hold (2^28 - 1 ticks: the length is capped at an hour,
   quickly: its first note within 2.5 s of the command, as a plain song's within 1.2 s).
5. big.mid: a file of exactly 65,536 bytes (its last byte at $FFFF of its bank): played to its
   end.
Before REV $0C (and with Lau) the engine must refuse a .MID politely.
Prints PASS / FAIL lines; exit 1 on a failure. Work files in build/midrun/."""
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
work = 'build/midrun'
shutil.rmtree(work, ignore_errors=True)
os.makedirs(work + '/mids')
fl = ' '.join(flags)
nolau = any(f in fl for f in ('--rev 9', '--rev 8', '--rev 7'))
noopl = nolau or any(f in fl for f in ('--rev 10', '--rev 11'))

PPQN = 96
MEL = [(0, 96, 60), (96, 96, 64), (192, 96, 67), (288, 96, 72),      # 120 BPM: 500 ms each
       (384, 384, 60), (384, 384, 64), (384, 384, 67),                # a chord, 2 s
       (768, 96, 62), (864, 48, 65)]                                  # 60 BPM: 1 s, 0.5 s
DRUMS = [35, 36, 37, 38, 39, 40, 41, 43, 45, 47, 48, 50]             # (not 42, 44, 46: the hi-hat choke)
DRT = [384 + 12 + 24 * k for k in range(len(DRUMS))]


def ms(t):
    """the file's tick t in ms: 120 BPM up to tick 768, then 60 BPM"""
    return t * 500 / PPQN if t <= 768 else 4000 + (t - 768) * 1000 / PPQN


def make_song(path):
    t0 = mkmid.Track('Midrun')
    t0.tempo(0, 120)
    t0.tempo(768, 60)
    t1 = mkmid.Track('Piano')
    t1.prog(0, 0, 0)
    for t, d, n in MEL:
        t1.note(t, d, 0, n, 100)
    t2 = mkmid.Track('Drums')
    for t, n in zip(DRT, DRUMS):
        t2.note(t, 6, 9, n, 100)
    mkmid.write_smf(path, [t0, t1, t2], ppqn=PPQN)


def make_cc121(path):
    t0 = mkmid.Track('CC 121')
    t0.tempo(0, 120)
    t1 = mkmid.Track('Held')
    t1.prog(0, 0, 0)
    t1.cc(0, 0, 64, 127)               # the pedal down
    t1.note(0, 48, 0, 60, 100)         # off at 250 ms: held by the pedal
    t1.cc(96, 0, 121, 0)               # 500 ms: Reset All Controllers releases it
    t1.note(192, 48, 0, 64, 100)       # (the song goes on: 1000 ms)
    mkmid.write_smf(path, [t0, t1], ppqn=PPQN)


def make_smpte(path):
    tr = mkmid.Track('SMPTE')
    tr.prog(0, 0, 0)
    tr.note(0, 200, 0, 60, 100)
    tr.tempo(100, 30)                  # Set Tempo: ignored in SMPTE division
    tr.note(500, 200, 0, 67, 100)      # 500 ms
    data = b'MThd' + struct.pack('>IHHBB', 6, 0, 1, 256 - 25, 40) + tr.encode()
    open(path, 'wb').write(data)


def make_wrap(path):
    open(path, 'wb').write(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96) + b'MTrk' + bytes([0xFF, 0xFF, 0xFF, 0xF8]))


def make_huge(path):
    trk = (bytes([0, 0xC0, 0, 0, 0x90, 60, 100]) + bytes([0xFF, 0xFF, 0xFF, 0x7F]) + bytes([0x80, 60, 0])
           + bytes([0, 0xFF, 0x2F, 0]))
    open(path, 'wb').write(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96) + b'MTrk' + struct.pack('>I', len(trk)) + trk)


def make_big(path):
    head = bytes([0, 0xC0, 0, 0, 0x90, 60, 100, 0x60, 0x80, 60, 0])   # a note, 500 ms
    tail = bytes([0, 0xFF, 0x2F, 0])
    n = 65536 - 14 - 8 - len(head) - len(tail) - 2 - 3                # a SysEx fills the rest
    sysex = bytes([0, 0xF0]) + mkmid.vlq(n) + bytes(n - 1) + bytes([0xF7])
    trk = head + sysex + tail
    data = b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96) + b'MTrk' + struct.pack('>I', len(trk)) + trk
    assert len(data) == 65536, len(data)
    open(path, 'wb').write(data)


files = {'song': make_song, 'cc121': make_cc121, 'smpte': make_smpte, 'wrap': make_wrap, 'huge': make_huge,
         'big': make_big}
for name, f in files.items():
    f(f'{work}/mids/{name}.mid')


def run(name, script, secs):
    card = work + '/sd'
    shutil.rmtree(card, ignore_errors=True)
    shutil.copytree(sd, card)
    open(card + '/SYSTEM/NODESK', 'w').close()
    os.makedirs(card + '/T')
    for n in files:
        shutil.copy(f'{work}/mids/{n}.mid', f'{card}/T/{n.upper()}.MID')
    keys = subprocess.run([sys.executable, os.path.join(here, 'keyscript.py'), '/dev/stdin'],
                          input=script, capture_output=True, text=True, check=True).stdout.strip()
    with open(f'{work}/{name}.out', 'w') as out, open(f'{work}/{name}.err', 'w') as err:
        subprocess.run([emu] + flags + ['--headless', '--log-opl-us', '--sd', card, '--max-seconds', str(secs),
                       '--keys', keys, sysf], stdout=out, stderr=err)
    shutil.rmtree(card, ignore_errors=True)
    return open(f'{work}/{name}.out', encoding='latin-1').read()


def play(name, secs):
    return run(name, '1500 {esc}\n+1500 musicd /T/%s.MID\\n\n' % name.upper(), secs)


def events(name):
    """the key-ons and key-offs of the log: (us, 'on'/'off', channel, MIDI note at key-on)"""
    a = [0] * 9
    b = [0] * 9
    ev = []
    for line in open(f'{work}/{name}.err'):
        p = line.split()
        if len(p) != 5 or p[0] != 'opl':
            continue
        us, reg, val = int(p[1]), int(p[2][1:], 16), int(p[4][1:], 16)
        if 0xA0 <= reg <= 0xA8:
            a[reg - 0xA0] = val
        elif 0xB0 <= reg <= 0xB8:
            c = reg - 0xB0
            was, now = b[c] & 0x20, val & 0x20
            b[c] = val
            if now and not was:
                fnum = (val & 3) << 8 | a[c]
                block = (val >> 2) & 7
                f = fnum * 49716 / 2 ** (20 - block) if fnum else 0
                note = round(69 + 12 * math.log2(f / 440)) if f else None
                ev.append((us, 'on', c, note))
            elif was and not now:
                ev.append((us, 'off', c, None))
    return ev


def near(t_ms, want_ms):
    return -1 <= t_ms - want_ms <= 8


bad = 0


def result(ok, text, where):
    global bad
    if ok:
        print('PASS  ' + text)
    else:
        print('FAIL  %s (%s)' % (text[:72], where))
        bad += 1


if noopl:
    out = play('song', 9)
    want = 'has no Lau' if nolau else 'MIDI needs the OPL2'
    result(want in out, 'MIDI without the OPL2: a polite refusal', f'{work}/song.out')
    sys.exit(1 if bad else 0)

# 1. the song
out = play('song', 13)
ev = events('song')
ons = [e for e in ev if e[1] == 'on']
log = []
ok = 'Ended' in out and len(ons) == len(MEL) + len(DRUMS)
if ok:
    t0 = ons[0][0]
    want_on = sorted([(ms(t), 'm', n) for t, d, n in MEL] + [(ms(t), 'd', n) for t, n in zip(DRT, DRUMS)])
    base = ons[0][3]
    for (us, _, c, note), (w, kind, n) in zip(ons, want_on):
        t = (us - t0) / 1000
        good = near(t, w) and (kind == 'd' or note - base == n - MEL[0][2])
        log.append('on  %8.1f ms (file %6.1f) ch %d note %s %s %s' % (t, w, c, note, kind, '' if good else '<-- wrong'))
        ok = ok and good
    # each melodic note's key-off: the next key-off of its channel
    for i, (us, _, c, note) in enumerate(ons):
        w, kind, n = want_on[i]
        if kind != 'm':
            continue
        d = [m for t, dd, m in MEL if abs(ms(t) - w) < 1 and m == n]
        dur = [ms(t + dd) - ms(t) for t, dd, m in MEL if abs(ms(t) - w) < 1 and m == n][0]
        off = [e for e in ev if e[1] == 'off' and e[2] == c and e[0] > us]
        t = (off[0][0] - t0) / 1000 if off else None
        good = t is not None and near(t, w + dur)
        log.append('off %8s ms (file %6.1f) ch %d %s' % ('%.1f' % t if t is not None else '-', w + dur, c,
                                                       '' if good else '<-- wrong (cut short by a drum?)'))
        ok = ok and good
open(f'{work}/song.check', 'w').write('\n'.join(log) + '\n')
result(ok, 'MIDI on the OPL2: %d notes and %d drums at 120 then 60 BPM, key-on and key-off times within -1..+8 ms, '
       'pitches, a chord not cut short by 12 drums' % (len(MEL), len(DRUMS)), f'{work}/song.check')

# 2. CC 121 releases what the pedal holds
out = play('cc121', 10)
ev = events('cc121')
ons = [e for e in ev if e[1] == 'on']
offs = [e for e in ev if e[1] == 'off' and ons and e[2] == ons[0][2]]
ok = 'Ended' in out and len(ons) == 2 and offs and near((offs[0][0] - ons[0][0]) / 1000, 500)
result(ok, 'MIDI: Reset All Controllers (CC 121) releases a note held by the sustain pedal', f'{work}/cc121.err')

# 3. SMPTE division: Set Tempo ignored
out = play('smpte', 10)
ons = [e for e in events('smpte') if e[1] == 'on']
ok = 'Ended' in out and len(ons) == 2 and near((ons[1][0] - ons[0][0]) / 1000, 500)
result(ok, 'MIDI: SMPTE division (1000 ticks a second), its Set Tempo ignored', f'{work}/smpte.err')

# 4. broken files: no hang, the engine not killed
out = run('wrap', '1500 {esc}\n+1500 musicd /T/WRAP.MID\\n\n+3000 ls /T\\n\n', 9)
tail = out.split('musicd /T/')[-1] if 'musicd /T/' in out else ''
result('SONG.MID' in tail.split('ls /T')[-1], 'MIDI: a chunk length that wraps the address ($FFFFFFF8): no hang',
       f'{work}/wrap.out')
out = play('huge', 9)              # typed from 3 s: its first note by 5.5 s (a plain song's: 4.2 s)
ons = [e for e in events('huge') if e[1] == 'on']
result('Playing' in out and ons and ons[0][0] < 5500000,
       'MIDI: a delta of 2^28 - 1 ticks: loaded at once (the length capped at an hour)', f'{work}/huge.out')

# 5. a file of 65,536 bytes
out = play('big', 10)
ok = 'Ended' in out and [e[1] for e in events('big')][:2] == ['on', 'off']
result(ok, 'MIDI: a file of exactly 64 KB (its last byte at $FFFF of its bank) plays to its end', f'{work}/big.out')
sys.exit(1 if bad else 0)
