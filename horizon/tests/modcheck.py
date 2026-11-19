#!/usr/bin/env python3
"""modcheck.py - check the music engine's Lau writes against the reference player (modref.py).

    python3 modcheck.py FILE.MOD LOG [--start-us T] [--max-lag US] [--mvol 64] [--sep 32]
    python3 modcheck.py FILE.MOD LOG --timing [--threshold US]
    python3 modcheck.py --selftest [--keep DIR]

LOG is emu816's stderr with --log-lau-us: lines "lau <us> $DBxx = $yy" (other lines ignored).

How it works
  * Lau's register file is rebuilt from the writes.  Writes closer than --gap (3000 us) to the
    previous one form a burst; one burst = the writes of one engine tick.
  * Alignment: the first burst with a KEYON on one of the module's voices (8-N .. 7) is the
    reference's first tick with a note start; reference tick k is expected at
    t0 + tick_start_us(k).  A burst at time b belongs to the last tick k with
    t0 + start(k) - EARLY <= b (EARLY = 3000 us; ticks are >= 9.8 ms apart); its lag is
    b - t0 - start(k).  A tick without a burst keeps the previous state.
  * After each tick's bursts, per channel c (voice 8-N+c), compared with the reference:
      trig    a KEYON for that voice in that tick exactly when the reference starts a note
      stop    a KEYOFF not followed by a KEYON in that tick exactly when the reference stops
              the voice (sample 0 / empty sample / one-shot offset beyond its end)
      start   on note starts: START - (that sample's address); the address is learned from
              the sample's first start that plays from the sample itself (START = address +
              offset); 'copy' starts (offset inside a loop) check LEN/LOOP/CTRL only
      len, loop, ctrl   on note starts
      pitch, vol_l, vol_r  +-1, while the channel has a note playing (not after a stop, nor
              after a one-shot reached its end: the checker follows each voice's position
              from the written pitch, 48000 output samples/s, 3 ms margin)
      timing  a burst later than --max-lag (3000 us) after its tick's ideal time
  * --timing: per-burst lag, min/mean/max/jitter, ticks that must have writes (a note start /
    stop or a changed pitch/volume in the reference) vs ticks that had a burst, drift; fails
    when a tick that needs writes has none or |lag| exceeds --threshold (2000 us).
Exit status 0 = pass, 1 = mismatch.
"""

import sys
import os
import re
import bisect
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import modref  # noqa: E402

LINE_RE = re.compile(r'^lau (\d+) \$([0-9A-Fa-f]{4}) = \$([0-9A-Fa-f]{2})')
EARLY = 3000


def parse_log(lines, start_us=0):
    w = []
    for ln in lines:
        m = LINE_RE.match(ln)
        if not m:
            continue
        t = int(m.group(1))
        if t < start_us:
            continue
        w.append((t, int(m.group(2), 16), int(m.group(3), 16)))
    return w


def make_bursts(writes, gap=3000):
    out = []
    for wr in writes:
        if out and wr[0] - out[-1][-1][0] <= gap:
            out[-1].append(wr)
        else:
            out.append([wr])
    return out


class Lau:
    """Lau's write-side state, plus each voice's position (to know when a one-shot ended)."""

    def __init__(self):
        self.r = [0] * 128
        self.keyed = [False] * 8      # started and not keyed off
        self.pos = [0.0] * 8
        self.tl = [0] * 8

    def f(self, v, off, n):
        b = 16 * v + off
        return sum(self.r[b + i] << (8 * i) for i in range(n))

    def voice(self, v):
        return dict(start=self.f(v, 0, 3), len=self.f(v, 3, 3), loop=self.f(v, 6, 3),
                    pitch=self.f(v, 9, 2), vol_l=self.r[16 * v + 11], vol_r=self.r[16 * v + 12],
                    ctrl=self.r[16 * v + 13])

    def advance(self, v, t):
        if self.keyed[v]:
            self.pos[v] += self.f(v, 9, 2) / 16384.0 * (t - self.tl[v]) * 0.048
        self.tl[v] = t

    def ended(self, v, t, margin_us=3000):
        """A one-shot (CTRL loop off) voice at or within margin of its end at time t."""
        if not self.keyed[v]:
            return True
        if self.r[16 * v + 13] & 1:
            return False
        step = self.f(v, 9, 2) / 16384.0 * 0.048
        pos = self.pos[v] + step * (t - self.tl[v])
        return pos + step * margin_us >= self.f(v, 3, 3)

    def write(self, t, a, val, ev):
        i = a - 0xDB00
        if i >= 0x80:
            v = (i - 0x80) // 16
            if (i - 0x80) % 16 in (9, 10):
                self.advance(v, t)
            self.r[i - 0x80] = val
        elif i == 0x20:
            for v in range(8):
                if val >> v & 1:
                    self.keyed[v], self.pos[v], self.tl[v] = True, 0.0, t
                    ev[v] = 'on'
        elif i == 0x21:
            for v in range(8):
                if val >> v & 1:
                    self.advance(v, t)
                    self.keyed[v] = False
                    ev[v] = 'off'             # the last of KEYOFF/KEYON in the tick counts


class Result:
    def __init__(self):
        self.mism = []
        self.lags = []           # (burst index, tick, lag)
        self.compared = 0
        self.after_end = 0
        self.pre = 0
        self.need = set()
        self.seen = set()
        self.notes = []


def check(mod, writes, mvol=64, sep=32, gap=3000, max_lag=3000, song=None):
    song = song or modref.simulate(mod, mvol=mvol, sep=sep)
    ticks = song.ticks
    n = mod.nch
    v0 = 8 - n
    vmask = sum(1 << (v0 + c) for c in range(n))
    res = Result()
    times = [t.us for t in ticks]
    k0 = next((t.index for t in ticks if any(o.trig for o in t.chans)), None)
    bursts = make_bursts(writes, gap)
    if k0 is None:
        res.notes.append('the reference starts no note')
        return res, song
    first = None
    for i, b in enumerate(bursts):
        if any(a == 0xDB20 and val & vmask for _, a, val in b):
            first = i
            break
    lau = Lau()
    if first is None:
        res.mism.append((k0, ticks[k0].order, ticks[k0].row, -1, 'trig', 'a note start',
                         'no KEYON in the log'))
        return res, song
    t0 = bursts[first][0][0] - times[k0]
    end_rel = song.length_us
    # Assign bursts to ticks.
    per_tick = {}
    for i, b in enumerate(bursts):
        if i < first:
            for (t, a, val) in b:
                lau.write(t, a, val, {})
            res.pre += 1
            continue
        rel = b[0][0] - t0
        if rel >= end_rel - EARLY:
            res.after_end += 1
            continue
        k = bisect.bisect_right(times, rel + EARLY) - 1
        if k < 0:
            res.pre += 1
            for (t, a, val) in b:
                lau.write(t, a, val, {})
            continue
        per_tick.setdefault(k, []).append(i)
        lag = rel - times[k]
        res.lags.append((i, k, lag))
        if lag > max_lag:
            tk = ticks[k]
            res.mism.append((k, tk.order, tk.row, -1, 'timing', '<= %d us late' % max_lag,
                             '%d us late' % lag))
    res.seen = set(per_tick)
    base = {}          # sample number -> learned address
    prev = [None] * n
    for tk in ticks:
        k = tk.index
        ev = {}
        tcmp = t0 + times[k]
        for i in per_tick.get(k, ()):
            for (t, a, val) in bursts[i]:
                lau.write(t, a, val, ev)
            tcmp = bursts[i][-1][0]
        need = False
        for c, o in enumerate(tk.chans):
            v = v0 + c
            cur = (o.pitch, o.vol_l, o.vol_r)
            if o.trig or o.stop or (o.active and cur != prev[c]):
                need = True
            prev[c] = cur if o.active else None
            res.compared += 1
            st = lau.voice(v)
            got_on = ev.get(v) == 'on'
            got_off = ev.get(v) == 'off'

            def bad(field, exp, got):
                res.mism.append((k, tk.order, tk.row, c, field, exp, got))
            if o.trig != got_on:
                bad('trig', 'KEYON' if o.trig else 'no KEYON', 'KEYON' if got_on else 'none')
            # (the engine stops its voices when the song ends: a KEYOFF in the last tick's burst)
            # (a stop of a voice that is silent already, stopped or a one-shot at its end, may
            # be left out: the engine writes nothing for a voice that does not sound)
            if o.stop != got_off and not (got_off and not o.stop and k == ticks[-1].index) \
                    and not (o.stop and not got_off and lau.ended(v, tcmp, 0)):
                bad('stop', 'KEYOFF' if o.stop else 'no KEYOFF', 'KEYOFF' if got_off else 'none')
            if o.trig and got_on:
                kind, so, ln, lp, ctrl = o.regs
                if kind == 'sample':
                    if o.smp not in base:
                        base[o.smp] = st['start'] - so
                    elif st['start'] - base[o.smp] != so:
                        bad('start', 'sample %d + %d' % (o.smp, so),
                            'sample %d + %d' % (o.smp, st['start'] - base[o.smp]))
                for f, e in (('len', ln), ('loop', lp), ('ctrl', ctrl)):
                    if st[f] != e:
                        bad(f, e, st[f])
            if o.active and lau.keyed[v] and not lau.ended(v, tcmp):
                for f in ('pitch', 'vol_l', 'vol_r'):
                    if abs(st[f] - getattr(o, f)) > 1:
                        bad(f, getattr(o, f), st[f])
        if need:
            res.need.add(k)
    return res, song


def print_mismatches(res, limit=20, out=sys.stdout):
    by = {}
    for m in res.mism:
        by[m[4]] = by.get(m[4], 0) + 1
    out.write('mismatches: %d %s\n' % (len(res.mism), ' '.join('%s=%d' % kv
                                                               for kv in sorted(by.items()))))
    for m in res.mism[:limit]:
        k, order, row, c, field, exp, got = m
        out.write('  tick %d  order %d row %d  ch %s  %s: expected %s, got %s\n' % (
            k, order, row, c if c >= 0 else '-', field, exp, got))


def lag_stats(res):
    lags = [l for _, _, l in res.lags]
    if not lags:
        return None
    return min(lags), sum(lags) / len(lags), max(lags), max(lags) - min(lags)


def timing_report(res, song, threshold=2000, out=sys.stdout, verbose=True):
    ticks = song.ticks
    if verbose:
        for i, k, lag in res.lags:
            t = ticks[k]
            out.write('burst %5d  tick %5d  %02d:%02d.%-2d  ideal %9d  lag %6d us\n' % (
                i, k, t.order, t.row, t.rowtick, t.us, lag))
    st = lag_stats(res)
    missing = sorted(res.need - res.seen)
    extra = sorted(res.seen - res.need)
    ok = True
    if st:
        out.write('lag us: min %d mean %.1f max %d jitter %d (%d bursts)\n' % (
            st[0], st[1], st[2], st[3], len(res.lags)))
        if st[2] > threshold or st[0] < -threshold:
            out.write('FAIL: lag beyond +-%d us\n' % threshold)
            ok = False
        if len(res.lags) >= 2:
            xs = [ticks[k].us for _, k, _ in res.lags]
            ys = [ticks[k].us + l for _, k, l in res.lags]
            mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
            sxx = sum((x - mx) ** 2 for x in xs)
            if sxx:
                slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
                out.write('tick rate: %.1f ppm from ideal\n' % ((slope - 1) * 1e6))
    else:
        out.write('FAIL: no bursts\n')
        ok = False
    out.write('ticks: %d in the song, %d need writes, %d had a burst, %d missing, %d extra; '
              '%d bursts after the end ignored\n' % (len(ticks), len(res.need), len(res.seen),
                                                     len(missing), len(extra), res.after_end))
    if missing:
        out.write('FAIL: ticks without the expected writes: %s\n' % ' '.join(
            '%d(%d:%d)' % (k, ticks[k].order, ticks[k].row) for k in missing[:20]))
        ok = False
    return ok


# ---------------------------------------------------------------------------------------------
# Self-test: synthesise logs from the reference the way the kernel writes Lau.

def synth_bursts(mod, song):
    """[(tick, [(addr, val), ...])]: sample_play / sample_set / sample_stop per the conventions."""
    n = mod.nch
    v0 = 8 - n
    addr = {}
    a = 0x020000
    for s in mod.samples[1:]:
        addr[s.num] = a
        a += (s.length + 1) & ~1
    copybuf = [0x0F0000 + 0x2000 * c for c in range(n)]
    last = [None] * n
    out = []
    for tk in song.ticks:
        w = []
        for c, o in enumerate(tk.chans):
            v = v0 + c
            vb = 0xDB80 + 16 * v
            cur = (o.pitch, o.vol_l, o.vol_r)
            if o.trig:
                kind, so, ln, lp, ctrl = o.regs
                start = addr[o.smp] + so if kind == 'sample' else copybuf[c]
                w.append((0xDB21, 1 << v))
                for i, b in enumerate([start & 255, start >> 8 & 255, start >> 16,
                                       ln & 255, ln >> 8 & 255, ln >> 16,
                                       lp & 255, lp >> 8 & 255, lp >> 16,
                                       o.pitch & 255, o.pitch >> 8, o.vol_l, o.vol_r, ctrl]):
                    w.append((vb + i, b))
                w.append((0xDB23, 1 << v))
                w.append((0xDB20, 1 << v))
                last[c] = cur
            elif o.stop:
                w.append((0xDB21, 1 << v))
                last[c] = None
            elif o.active and cur != last[c]:
                for i, b in enumerate([o.pitch & 255, o.pitch >> 8, o.vol_l, o.vol_r]):
                    w.append((vb + 9 + i, b))
                last[c] = cur
        if w:
            out.append([tk.index, w])
    return out


def serialize(song, bursts, base=2000000, shift=None):
    shift = shift or {}
    lines = ['emu816: started', 'lau %d $DB21 = $FF' % (base - 50000),
             'lau %d $DB25 = $C0' % (base - 49990), 'some other stderr line']
    for k, w in bursts:
        t = base + song.ticks[k].us + 150 + (k * 7919) % 1300 + shift.get(k, 0)
        for a, val in w:
            lines.append('lau %d $%04X = $%02X' % (t, a, val))
            t += 4
    lines.append('lau %d $DB21 = $FF' % (base + song.length_us + 30000))
    return lines


def _find(bursts, song, mod, pred, frac=0.5):
    """A burst index (around frac of the song) holding a channel event satisfying pred."""
    cands = []
    for bi, (k, w) in enumerate(bursts):
        for c, o in enumerate(song.ticks[k].chans):
            if pred(o):
                cands.append((bi, c))
    return cands[int(len(cands) * frac)] if cands else None


def selftest(keep=None):
    import mkmodtests
    ok = True
    total = 0
    if keep:
        os.makedirs(keep, exist_ok=True)
    mods = list(mkmodtests.generate())
    for name, nch, data, cov in mods:
        mod = modref.load_mod(data)
        song = modref.simulate(mod)
        total += song.length_us
        b = synth_bursts(mod, song)
        lines = serialize(song, b)
        if keep:
            with open(os.path.join(keep, name + '.log'), 'w') as f:
                f.write('\n'.join(lines) + '\n')
        res, _ = check(mod, parse_log(lines), song=song)
        sink = open(os.devnull, 'w')
        tok = timing_report(res, song, out=sink, verbose=False)
        st = lag_stats(res)
        good = not res.mism and tok
        ok &= good
        print('%-13s %d ch %6.3f s %5d ticks: %s (lag %d..%d us)' % (
            name, nch, song.length_us / 1e6, len(song.ticks), 'pass' if good else 'FAIL',
            st[0], st[2]))
        if not good:
            print_mismatches(res)
    print('total playback %.3f s' % (total / 1e6))

    # FLT8 must give the same reference as the same patterns stored as 8CHN.
    a = modref.simulate(modref.load_mod(mkmodtests.t19_flt8('FLT8')[2]))
    c = modref.simulate(modref.load_mod(mkmodtests.t19_flt8('8CHN')[2]))
    same = len(a.ticks) == len(c.ticks) and all(
        [(o.trig, o.pitch, o.vol_l, o.vol_r) for o in x.chans] ==
        [(o.trig, o.pitch, o.vol_l, o.vol_r) for o in y.chans] for x, y in zip(a.ticks, c.ticks))
    print('FLT8 == 8CHN reference: %s' % ('pass' if same else 'FAIL'))
    ok &= same

    # Corrupted logs: each must fail.
    def corrupt(modname, what):
        data = next(d for nm, _, d, _ in mods if nm == modname)
        mod = modref.load_mod(data)
        song = modref.simulate(mod)
        b = synth_bursts(mod, song)
        v0 = 8 - mod.nch
        shift = {}
        timing = False
        if what == 'wrong pitch':
            bi, c = _find(b, song, mod, lambda o: o.trig)
            w = b[bi][1]
            j = max(i for i, (a, _) in enumerate(w) if a == 0xDB80 + 16 * (v0 + c) + 9)
            w[j] = (w[j][0], (w[j][1] + 5) & 255)
        elif what == 'wrong volume':
            bi, c = _find(b, song, mod, lambda o: o.active and not o.trig and o.regs[4] & 1, 0.3)
            b[bi][1].append((0xDB80 + 16 * (v0 + c) + 11, 7))
        elif what == 'missing trigger':
            bi, c = _find(b, song, mod, lambda o: o.trig, 0.7)
            b[bi][1] = [x for x in b[bi][1] if not (x[0] == 0xDB20 and x[1] == 1 << (v0 + c))]
        elif what == 'missing stop':
            bi, c = _find(b, song, mod, lambda o: o.stop)
            b[bi][1] = [x for x in b[bi][1] if not (x[0] == 0xDB21 and x[1] == 1 << (v0 + c))]
        elif what == 'wrong offset':
            bi, c = _find(b, song, mod, lambda o: o.trig and o.off and o.regs[0] == 'sample')
            w = b[bi][1]
            j = next(i for i, (a, _) in enumerate(w) if a == 0xDB80 + 16 * (v0 + c) + 1)
            w[j] = (w[j][0], (w[j][1] + 1) & 255)
        elif what == 'late tick':
            shift[b[len(b) // 2][0]] = 4000
        elif what == 'late tick (timing, 2.5 ms)':
            shift[b[len(b) // 2][0]] = 2500
            timing = True
        elif what == 'missing tick (timing)':
            del b[len(b) // 2]
            timing = True
        lines = serialize(song, b, shift=shift)
        res, _ = check(mod, parse_log(lines), song=song)
        if timing:
            failed = not timing_report(res, song, out=open(os.devnull, 'w'), verbose=False)
        else:
            failed = bool(res.mism)
        detail = res.mism[0] if res.mism else ''
        print('corrupt %-13s %-28s -> %s %s' % (modname, what, 'fails (good)' if failed
                                                else 'PASSES (BAD)', detail))
        return failed

    for modname, what in [('t04vib.mod', 'wrong pitch'), ('t07vol.mod', 'wrong volume'),
                          ('t09retr.mod', 'missing trigger'), ('t06offs.mod', 'missing stop'),
                          ('t06offs.mod', 'wrong offset'), ('t12speed.mod', 'late tick'),
                          ('t12speed.mod', 'late tick (timing, 2.5 ms)'),
                          ('t05trem.mod', 'missing tick (timing)')]:
        ok &= corrupt(modname, what)
    print('selftest: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description='Check Lau writes against the reference player.')
    ap.add_argument('mod', nargs='?')
    ap.add_argument('log', nargs='?')
    ap.add_argument('--start-us', type=int, default=0, help='ignore log lines before T us')
    ap.add_argument('--timing', action='store_true')
    ap.add_argument('--threshold', type=int, default=2000, help='timing mode: max |lag| us')
    ap.add_argument('--max-lag', type=int, default=3000, help='compare mode: max lag us')
    ap.add_argument('--gap', type=int, default=3000, help='burst gap us')
    ap.add_argument('--mvol', type=int, default=64)
    ap.add_argument('--sep', type=int, default=32)
    ap.add_argument('--limit', type=int, default=20, help='mismatches to print')
    ap.add_argument('--selftest', action='store_true')
    ap.add_argument('--keep', help='selftest: write the synthetic logs to this directory')
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest(a.keep)
    if not a.mod or not a.log:
        ap.error('FILE.MOD and LOG are required')
    mod = modref.load_mod(a.mod)
    with open(a.log, errors='replace') as f:
        writes = parse_log(f, a.start_us)
    res, song = check(mod, writes, a.mvol, a.sep, a.gap, a.max_lag)
    for nline in res.notes:
        print(nline)
    if a.timing:
        ok = timing_report(res, song, a.threshold)
        return 0 if ok else 1
    st = lag_stats(res)
    print('%s: %d ticks (%.3f s, end: %s), %d channel-ticks compared, %d bursts '
          '(%d before the first note, %d after the end)' % (
              a.mod, len(song.ticks), song.length_us / 1e6, song.end_reason, res.compared,
              len(res.lags), res.pre, res.after_end))
    if st:
        print('lag us: min %d mean %.1f max %d jitter %d' % st)
    extra = len(res.seen - res.need)
    if extra:
        print('note: %d ticks had writes where the reference changes nothing' % extra)
    if res.mism:
        print_mismatches(res, a.limit)
        print('FAIL')
        return 1
    print('PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
