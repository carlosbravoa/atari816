#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tests/soundcheck.py: tests/sound.sh's checks (PASS / FAIL lines, exit 1 on a FAIL).

  opl NAME HOSTLOG EMUERR TICKS LATE_MS   (TICKS 0: the whole run)
      The Atari816's OPL2 writes (run816 --log-opl-us: "opl US $RR = $VV", the music task
      MUSD.PRG's) against the host's (xcomhost -opl: "TICK MS RR VV", the engine's own
      driver at its virtual clock): the same registers and values in the same order, from
      the driver's start (its detection: 04=60 04=80 02=FF) to the end of the TICKS-th tick
      after the first track's start; and the time of each tick's writes on the Atari816
      (the host's tick numbers): at most LATE_MS after the 13.731 ms beat (the beat's phase:
      the earliest tick). Prints the spacing figures.
  sfx NAME HOSTSB CONSOLE EMUERR [MIN [EXPECT]]
      (MIN: the Atari816's run may end first: its lines, at least MIN, as the host's
      first ones) The Sound Blaster's blocks: the host's -sb lines (time, kind, bytes, address, rate,
      checksum, samples) and the Atari816's "xcom: sfx" lines the same, in the same order;
      SOUNDS.PAK's effect named for each (by its checksum); each block a Lau start
      (run816 --log-lau: a write to AU_KEYON) with that many samples at that rate
      (pitch = rate * 16384 / 48000). EXPECT: the effects that must start, in order, as
      letters: B the button's click, W a window's pop-up (window 1, window 2 or geo popup).
  quieter NAME WAV1 FROM1 TO1 WAV2 FROM2 TO2
      The loudest 50 ms of WAV1's part under WAV2's (the interface's sounds under a
      battle's shots).
  wav NAME WAV FROM TO MINRMS
      The recording (run816 --wav: Lau and the OPL2 as the board mixes them) from FROM to
      TO seconds: RMS above MINRMS, under 0.05 % of the samples clipped; the loudest
      50 ms (an effect over the music) against the median (the music)."""
import array
import math
import re
import struct
import sys
import wave

PERIOD_US = 13731.0
bad = 0


def ok(s):
    print('PASS  ' + s)


def fail(s):
    global bad
    bad += 1
    print('FAIL  ' + s)


def detect_at(seq):
    pat = [(0x04, 0x60), (0x04, 0x80), (0x02, 0xFF)]
    for i in range(len(seq) - 2):
        if [seq[i][:2], seq[i + 1][:2], seq[i + 2][:2]] == pat:
            return i
    return -1


def opl(name, hostlog, emuerr, ticks, late_ms, last=False):
    host, play = [], None
    for ln in open(hostlog):
        if ln.startswith('# play') and (play is None or last):
            # (last: the run's last track, e.g. the geoscape's after the start menu's
            # GMSTORY, which the player leaves at a moment of the real clock on the
            # Atari816 and of the virtual one on the host: compared from its start)
            play = int(ln.split()[-1])
            host_play_at = len(host)
        elif not ln.startswith('#'):
            t, ms, r, v = ln.split()
            host.append((int(r, 16), int(v, 16), int(t)))
    emu = []
    rx = re.compile(r'^opl (\d+) \$([0-9A-F]{2}) = \$([0-9A-F]{2})')
    for ln in open(emuerr, errors='replace'):
        m = rx.match(ln)
        if m:
            emu.append((int(m.group(2), 16), int(m.group(3), 16), int(m.group(1))))
    if play is None:
        return fail(f'{name}: the host played no track')
    h0, e0 = detect_at(host), detect_at(emu)
    if h0 < 0 or e0 < 0:
        return fail(f'{name}: no OPL2 detection in the {"host" if h0 < 0 else "Atari816"} log')
    if last:
        # the track's first 64 writes found in the Atari816's log
        want = [w[:2] for w in host[host_play_at:host_play_at + 64]]
        at = next((i for i in range(e0, len(emu) - len(want))
                   if [w[:2] for w in emu[i:i + len(want)]] == want), None)
        if at is None:
            return fail(f'{name}: the last track\'s start is not in the Atari816\'s writes')
        h0, e0 = host_play_at, at
    if ticks:
        end = next((i for i, w in enumerate(host) if w[2] > play + ticks), None)
        if end is None:
            return fail(f'{name}: the host ran fewer than {ticks} ticks after the track\'s start')
    else:
        # the whole run: as far as the Atari816's log goes, but for its end (the game left:
        # the task's silence at its quit, mus_shutdown, about 260 writes)
        n = 0
        while h0 + n < len(host) and e0 + n < len(emu) and host[h0 + n][:2] == emu[e0 + n][:2]:
            n += 1
        if len(emu) - (e0 + n) > 300:
            return fail(f'{name}: the writes differ at {n} of the Atari816\'s {len(emu) - e0}')
        end = h0 + n
        ticks = host[end - 1][2] - play
    h, e = host[h0:end], emu[e0:e0 + end - h0]
    diff = next((i for i in range(min(len(h), len(e))) if h[i][:2] != e[i][:2]), None)
    if diff is not None or len(e) < len(h):
        i = diff if diff is not None else len(e)
        w = h[i] if i < len(h) else None
        return fail(f'{name}: OPL2 write {i} of {len(h)} differs: host '
                    f'{"%02X=%02X tick %d" % w if w else "-"}, Atari816 '
                    f'{"%02X=%02X" % e[i][:2] if i < len(e) else "none (the log ends)"}')
    # each tick's first write: its time against the beat
    first = {}
    for (r, v, t), (_, _, us) in zip(h, e):
        k = t - play
        if k >= 1 and k not in first:
            first[k] = us
    ks = sorted(first)
    # the beat's phase: the median tick's (where the track starts just after a timer
    # message was queued, the task's first tick comes at once: a period early against the
    # host's numbering)
    ph = sorted(first[k] - k * PERIOD_US for k in ks)
    phase = ph[len(ph) // 2]
    late = [(first[k] - k * PERIOD_US - phase) / 1000.0 for k in ks]
    gaps = [(first[b] - first[a]) / (b - a) / 1000.0 for a, b in zip(ks, ks[1:]) if b - a == 1]
    worst = max(range(len(late)), key=lambda i: late[i])
    # the beat from the second tick with writes to the last (the first can be a period
    # early or late: the phase note above)
    k0 = ks[1] if len(ks) > 2 else ks[0]
    span = (first[ks[-1]] - first[k0]) / (ks[-1] - k0) / 1000.0
    msg = (f'{name}: {len(h)} OPL2 writes as the host\'s, {ticks} ticks of the track '
           f'({len(ks)} with writes); beat {span:.4f} ms a tick (13.731), ticks off the beat '
           f'by {min(late):.2f} to {max(late):.2f} ms, {max(late):.2f} ms late at most '
           f'(tick {ks[worst]}, {first[ks[worst]] / 1e6:.2f} s)'
           + (f', next-tick gaps {min(gaps):.2f}-{max(gaps):.2f} ms' if gaps else ''))
    top = sorted(range(len(late)), key=lambda i: -late[i])[:6]
    print(f'      {name}: the latest ticks: ' + ', '.join(
        f'{late[i]:.1f} ms at {first[ks[i]] / 1e6:.2f} s' for i in sorted(top, key=lambda i: ks[i])))
    if max(late) > late_ms or abs(span - PERIOD_US / 1000.0) > 0.02:   # (drift: the lateness limit against the fixed beat)
        return fail(msg + f' (limit {late_ms} ms)')
    ok(msg)


def sfx_names():
    try:
        d = open('data/packs/SOUNDS.PAK', 'rb').read()
    except OSError:
        return {}
    names = ['rifle', 'cannon', 'laser', 'plasma', 'hit bullet', 'hit beam', 'explosion',
             'die sectoid', 'die snakeman', 'die muton', 'die ethereal', 'die male',
             'die female', 'door', 'step', 'throw', 'geo popup', 'craft cannon',
             'craft missile', 'ufo fire', 'ufo hit', 'ufo crash', 'craft explode',
             'button', 'window 1', 'window 2',
             # pack format 6 (engine/tools/sound.py)
             'step 1a', 'step 1b', 'step 2b', 'step 3b', 'step 5a', 'step 5b', 'step 6a',
             'step 6b', 'fly', 'explosion big', 'ufo door', 'drop', 'reload', 'die mech',
             'rocket', 'blaster']
    n = struct.unpack('<H', d[4:6])[0]
    out = {}
    for i in range(n):
        off, ln = struct.unpack('<IH', d[6 + 10 * i:12 + 10 * i])
        # plat/sb.c sb_sum: the length, every 61st byte, the last 16
        blk, s = d[off:off + ln], ln
        for b in list(blk[::61]) + list(blk[max(0, ln - 16):]):
            s = (((s << 1) | (s >> 15)) + b) & 0xFFFF
        nm = names[i] if i < len(names) else str(i)
        out[(ln, s)] = out[(ln, s)] + '/' + nm if (ln, s) in out else nm
    return out


def sfx(name, hostsb, console, emuerr, minimum=0, expect=None):
    host = [ln.strip() for ln in open(hostsb) if ln.strip()]
    rx = re.compile(r'xcom: sfx (\d+ (?:halt|sfx .*?samples \d+))(?: voice (-?\d+))?\s*$')
    emu, voices = [], []
    for ln in open(console, errors='replace'):
        m = rx.search(ln)
        if m:
            emu.append(m.group(1))
            if m.group(2) is not None:
                voices.append(int(m.group(2)))
    if not host:
        return fail(f'{name}: the host played no effect')
    if minimum and len(emu) < len(host):
        host = host[:max(len(emu), minimum)]    # (the Atari816's run ends first: its part)
    if host != emu:
        i = next((i for i in range(min(len(host), len(emu))) if host[i] != emu[i]), min(len(host), len(emu)))
        return fail(f'{name}: effect line {i} differs: host "{host[i] if i < len(host) else "-"}", '
                    f'Atari816 "{emu[i] if i < len(emu) else "-"}"')
    names = sfx_names()
    starts = []
    for ln in emu:
        f = ln.split()
        if f[1] == 'sfx':
            nm = names.get((int(f[3]), int(f[9], 16)), '?')
            starts.append((nm, int(f[11]), int(f[6])))
    # Lau: the voices' LEN and PITCH, each AU_KEYON a start
    regs = {}
    lau = []
    rx = re.compile(r'^lau \$DB([0-9A-F]{2}) = \$([0-9A-F]{2})')
    for ln in open(emuerr, errors='replace'):
        m = rx.match(ln)
        if not m:
            continue
        a, v = int(m.group(1), 16), int(m.group(2), 16)
        if a >= 0x80:
            regs[(a - 0x80) // 16, (a - 0x80) % 16] = v
        elif a == 0x20:
            for vc in range(8):
                if v >> vc & 1:
                    g = lambda o: regs.get((vc, o), 0)
                    lau.append((g(3) | g(4) << 8 | g(5) << 16, g(9) | g(10) << 8))
    want = [(n, r * 16384 // 48000) for _, n, r in starts]
    if len(lau) != len(want) or any(l[0] != w[0] or abs(l[1] - w[1]) > 1 for l, w in zip(lau, want)):
        return fail(f'{name}: Lau starts {lau[:6]}... are not the effects\' (samples, pitch) {want[:6]}...')
    if any(v < 0 for v in voices):
        return fail(f'{name}: an effect found no Lau voice')
    if expect is not None and expect.startswith('has:'):
        # the effects that must be among those started (names, comma separated)
        miss = [w for w in expect[4:].split(',') if not any(w in s[0].split('/') for s in starts)]
        if miss:
            return fail(f'{name}: no {", ".join(miss)} among the effects started '
                        f'({", ".join(s[0] for s in starts)})')
    elif expect is not None:
        got = ''.join('B' if s[0] == 'button' else 'W' if s[0] in ('window 1', 'window 2', 'geo popup')
                      else '?' for s in starts)
        if got != expect:
            return fail(f'{name}: the effects started {got} ({", ".join(s[0] for s in starts)}), '
                        f'not {expect} (B button, W window)')
    ok(f'{name}: {len(starts)} Sound Blaster blocks as the host\'s, each a Lau start of its '
       f'samples at its rate ({", ".join(sorted(set("%s %d Hz" % (s[0], s[2]) for s in starts)))})')


def loudest(path, lo, hi):
    """the loudest 50 ms window's RMS of the recording from lo to hi seconds"""
    w = wave.open(path)
    rate, ch = w.getframerate(), w.getnchannels()
    a = array.array('h', w.readframes(w.getnframes()))
    seg = a[int(lo * rate) * ch:int(hi * rate) * ch]
    win = rate * ch // 20
    return max(math.sqrt(sum(x * x for x in seg[i:i + win]) / win) for i in range(0, len(seg) - win, win))


def quieter(name, w1, lo1, hi1, w2, lo2, hi2):
    a, b = loudest(w1, lo1, hi1), loudest(w2, lo2, hi2)
    msg = (f'{name}: the loudest 50 ms {a:.0f} against {b:.0f} '
           f'({20 * math.log10(a / b):+.1f} dB)')
    if a > b:
        return fail(msg)
    ok(msg)


def wav(name, path, lo, hi, minrms):
    w = wave.open(path)
    rate, ch = w.getframerate(), w.getnchannels()
    a = array.array('h', w.readframes(w.getnframes()))
    seg = a[int(lo * rate) * ch:int(hi * rate) * ch]
    if not seg:
        return fail(f'{name}: the recording is shorter than {hi} s')
    r = math.sqrt(sum(x * x for x in seg) / len(seg))
    clip = sum(1 for x in seg if x >= 32700 or x <= -32700) / len(seg)
    win = rate * ch // 20
    rw = sorted(math.sqrt(sum(x * x for x in seg[i:i + win]) / win) for i in range(0, len(seg) - win, win))
    peak = max(abs(x) for x in seg)
    msg = (f'{name}: {lo}-{hi} s RMS {r:.0f}, 50 ms windows median {rw[len(rw) // 2]:.0f} '
           f'loudest {rw[-1]:.0f}, peak {peak}, {clip * 100:.3f} % clipped')
    if r < minrms or clip > 0.0005:
        return fail(msg)
    ok(msg)


def main():
    a = sys.argv[1:]
    if a[0] == 'opl':
        opl(a[1], a[2], a[3], int(a[4]), float(a[5]), len(a) > 6 and a[6] == 'last')
    elif a[0] == 'sfx':
        sfx(a[1], a[2], a[3], a[4], int(a[5]) if len(a) > 5 else 0, a[6] if len(a) > 6 else None)
    elif a[0] == 'quieter':
        quieter(a[1], a[2], float(a[3]), float(a[4]), a[5], float(a[6]), float(a[7]))
    elif a[0] == 'wav':
        wav(a[1], a[2], float(a[3]), float(a[4]), float(a[5]))
    sys.exit(1 if bad else 0)


main()
