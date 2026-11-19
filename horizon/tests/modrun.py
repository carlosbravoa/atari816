#!/usr/bin/env python3
"""modrun.py EMU SD HORIZON.SYS [EMUFLAGS...] - (0.26) the music engine's conformance and tempo tests.

1. Conformance: the test modules of mkmodtests.py are played one by one by the engine from the
   text shell (`musicd /T/NAME.MOD`, plays once) in emu816 with --log-lau-us; modcheck.py compares
   every tick's Lau writes with the reference player modref.py.
2. Tempo under load: t12speed.mod (speeds 1-31, 32-255 BPM) again while eight
   /SYSTEM/TESTS/SPIN.PRG (busy loops at the shell's priority) run: modcheck.py --timing checks every tick came, none
   later than 2 ms after its time; the lags are printed (the jitter).
Without Lau (--rev 9 and below) the engine must refuse politely: its message is checked.
Prints PASS / FAIL lines; exit 1 on a failure. Work files in build/modrun/."""
import os
import shutil
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
emu, sd, sysf = sys.argv[1:4]
flags = sys.argv[4:]
work = 'build/modrun'
shutil.rmtree(work, ignore_errors=True)
os.makedirs(work)
subprocess.run([sys.executable, os.path.join(here, 'mkmodtests.py'), work + '/mods'], check=True,
               stdout=subprocess.DEVNULL)
mods = [l.split() for l in open(work + '/mods/tests.txt') if not l.startswith('#')]


def big_module(path):
    """tbig.mod: two long samples (50,000 and 40,000 bytes) so that the second one runs across
    a 64 KB bank boundary in the engine's memory; offsets into it, 16 rows (Dxx ends it)."""
    import math
    import struct
    s1 = bytes([0, 0] + [int(60 * math.sin(i / 7.0)) & 255 for i in range(49998)])
    s2 = bytes(int(50 * math.sin(i / 11.0) + 30 * math.sin(i / 3.1)) & 255 for i in range(40000))
    hdr = b'big test'.ljust(20, b'\0')
    smp = [(b'one-shot 50000', 25000, 0, 64, 0, 1), (b'looped 40000', 20000, 0, 48, 10000, 5000)]
    for i in range(31):
        if i < 2:
            n, ln, ft, vol, ls, ll = smp[i]
            hdr += n.ljust(22, b'\0') + struct.pack('>HBBHH', ln, ft, vol, ls, ll)
        else:
            hdr += bytes(22) + struct.pack('>HBBHH', 0, 0, 0, 0, 1)
    hdr += bytes([1, 127]) + bytes(128) + b'M.K.'
    pat = bytearray(1024)

    def cell(row, ch, per, sm, cmd, par):
        o = row * 16 + ch * 4
        pat[o:o + 4] = bytes([(sm & 0xF0) | (per >> 8), per & 255, ((sm & 15) << 4) | cmd, par])
    cell(0, 0, 428, 1, 0, 0)
    cell(0, 1, 214, 2, 0, 0)
    cell(4, 2, 285, 2, 9, 0x30)       # offset 12,288: before the loop
    cell(8, 3, 320, 2, 9, 0x50)       # 20,480: inside the loop (too long to copy: the loop)
    cell(8, 0, 214, 1, 9, 0xB0)       # 45,056 into the one-shot
    cell(12, 1, 254, 2, 4, 0x46)      # vibrato on a note of the long sample
    cell(15, 2, 0, 0, 0xD, 0)
    open(path, 'wb').write(hdr + bytes(pat) + s1 + s2)


big_module(work + '/mods/tbig.mod')
mods.append(['tbig.mod', '4', '2.0', 'two long samples (50 KB, 40 KB): across a 64 KB bank, offsets'])
nolau = any(f in ' '.join(flags) for f in ('--rev 9', '--rev 8', '--rev 7'))


def run(name, script, secs, extra=(), prep=None):
    card = work + '/sd'
    shutil.rmtree(card, ignore_errors=True)
    shutil.copytree(sd, card)
    if prep:
        prep(card)
    open(card + '/SYSTEM/NODESK', 'w').close()
    os.makedirs(card + '/T')
    for m in mods:
        shutil.copy(work + '/mods/' + m[0], card + '/T/' + m[0].upper())
    keys = subprocess.run([sys.executable, os.path.join(here, 'keyscript.py'), '/dev/stdin'],
                          input=script, capture_output=True, text=True, check=True).stdout.strip()
    with open(f'{work}/{name}.out', 'w') as out, open(f'{work}/{name}.err', 'w') as err:
        subprocess.run([emu] + flags + list(extra) + ['--headless', '--log-lau-us', '--sd', card, '--max-seconds',
                       str(secs), '--keys', keys, sysf], stdout=out, stderr=err)
    shutil.rmtree(card, ignore_errors=True)
    return open(f'{work}/{name}.out', encoding='latin-1').read()


bad = 0
if nolau:
    out = run('nolau', '1500 {esc}\n+1500 musicd /T/T01ARP.MOD\\n\n', 8)
    if 'has no Lau' in out:
        print('PASS  music engine without Lau: a polite refusal')
    else:
        print('FAIL  music engine without Lau (%s/nolau.out)' % work)
        sys.exit(1)
    sys.exit(0)

for m in mods:
    name = m[0][:-4]
    secs = 7 + float(m[2])
    out = run(name, '1500 {esc}\n+1500 musicd /T/%s\\n\n' % m[0].upper(), secs)
    r = subprocess.run([sys.executable, os.path.join(here, 'modcheck.py'), f'{work}/mods/{m[0]}',
                        f'{work}/{name}.err', '--max-lag', '5000'], capture_output=True, text=True)
    open(f'{work}/{name}.check', 'w').write(r.stdout + r.stderr)
    if r.returncode == 0 and 'Ended' in out:
        print('PASS  music conformance %-9s %s' % (name, ' '.join(m[3:])[:70]))
    else:
        print('FAIL  music conformance %s (%s/%s.check)' % (name, work, name))
        bad += 1

# tempo under load: eight SPIN (400 ms of computing each) in the background, the engine at priority 0
out = run('tempo', '1500 {esc}\n' + '+400 spin &\\n\n' * 8 + '+400 musicd /T/T12SPEED.MOD\\n\n', 16)
r = subprocess.run([sys.executable, os.path.join(here, 'modcheck.py'), f'{work}/mods/t12speed.mod',
                    f'{work}/tempo.err', '--timing'], capture_output=True, text=True)
open(f'{work}/tempo.check', 'w').write(r.stdout + r.stderr)
# the jitter: the spread of the ticks' lags after the first (the first tick runs when play
# starts; the timer's phase is set from there: a constant offset is not heard)
lags = [int(l.split('lag')[1].split()[0]) for l in r.stdout.splitlines() if l.startswith('burst')][1:]
miss = [l for l in r.stdout.splitlines() if l.startswith('ticks:')]
ok = lags and max(lags) - min(lags) <= 1000 and miss and ' 0 missing' in miss[0]
if ok and 'Ended' in out:
    print('PASS  music tempo under load (speeds 1-31, 32-255 BPM, 8 SPIN running): %d ticks, lag %d..%d us, jitter %d us, %s'
          % (len(lags) + 1, min(lags), max(lags), max(lags) - min(lags), miss[0].split(';')[0].replace('ticks: ', '')))
else:
    print('FAIL  music tempo under load (%s/tempo.check)' % work)
    bad += 1


def timing(name, mod, what):
    global bad
    r = subprocess.run([sys.executable, os.path.join(here, 'modcheck.py'), mod, f'{work}/{name}.err',
                        '--timing'], capture_output=True, text=True)
    open(f'{work}/{name}.check', 'w').write(r.stdout + r.stderr)
    lags = [int(l.split('lag')[1].split()[0]) for l in r.stdout.splitlines() if l.startswith('burst')][1:]
    miss = [l for l in r.stdout.splitlines() if l.startswith('ticks:')]
    if lags and max(lags) - min(lags) <= 1000 and miss and ' 0 missing' in miss[0]:
        print('PASS  music %s: %d ticks, lag %d..%d us, jitter %d us, 0 missing'
              % (what, len(lags) + 1, min(lags), max(lags), max(lags) - min(lags)))
    else:
        print('FAIL  music %s (%s/%s.check)' % (what, work, name))
        bad += 1


# background play during a long copy on the card (1 MB at the board's card speed, about 16 s):
# LAU.MOD (13 s) started in the background, then cp; every tick must come on time
def bigfile(card):
    with open(card + '/BIG.BIN', 'wb') as f:
        f.write(bytes(range(256)) * 4096)
out = run('copy', '1500 {esc}\n+1500 musicd /Music/LAU.MOD &\\n\n+1500 cp /BIG.BIN /B2.BIN\\n\n', 22,
          extra=['--card-kbps', '170:100'], prep=bigfile)
timing('copy', sd + '/Music/LAU.MOD', 'during a 1 MB file copy (cp, card at 170/100 KB/s), in the background')
sys.exit(1 if bad else 0)
