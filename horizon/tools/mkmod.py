#!/usr/bin/env python3
"""mkmod.py [--jingle] OUT.MOD | --check FILE.MOD - the music modules for the MOD player on Lau.

Generates original ProTracker modules: every sample is synthesised here (simple waveforms,
noise and envelopes, no recordings) and every note is composed here. Nothing is taken from
existing music.

  mkmod.py OUT.MOD           "Horizon", the demo song (about 1.5 minutes, loops to its start)
  mkmod.py --jingle OUT.MOD  "Lau", a short bright jingle in A major (about 13 seconds)
  mkmod.py --check FILE.MOD  parses a module back and prints what is in it

The format is the classic 4-channel "M.K." module: a 20-byte title, 31 sample headers, the
order table, 64-row patterns of Amiga periods (the finetune-0 table, C-1..B-3 = 856..113) and
the 8-bit signed sample data. Only ProTracker 2.3 effects are used. The output is the same
bytes on every run (the noise generators have fixed seeds).

Sample rates follow the Amiga clock: a note played at period P runs the sample at 3546895 / P
samples per second, so C-3 (214) is 16574 Hz and B-3 (113) is 31389 Hz. The pitched
instruments are looped cycles (32 samples per cycle: C-2 sounds C4; the bass has 128, the pads
64), the drums and the bell are one-shots tuned to sound right at C-3 or B-3."""
import math, struct, sys

PAL = 3546895
PERIODS = [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
           428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
           214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113]
NOTE_NAMES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-']
RATE_C3 = PAL / 214         # one-shots played at C-3
RATE_B3 = PAL / 113         # hats played at B-3

def note(name):
    """'C#3' -> 0..35 (index into PERIODS)"""
    n = NOTE_NAMES.index(name[:2]) + 12 * (int(name[2]) - 1)
    assert 0 <= n < 36, name
    return n

# ---------------------------------------------------------------------------- sounds

class Noise:
    """white noise, -1..1, from a fixed-seed LCG so every run makes the same bytes"""
    def __init__(self, seed):
        self.s = seed
    def __call__(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s / 0x3FFFFFFF - 1.0

def cycle(n, harmonics):
    """one cycle of n samples: harmonics = [(k, amplitude, phase)]"""
    return [sum(a * math.sin(2 * math.pi * k * i / n + ph) for k, a, ph in harmonics)
            for i in range(n)]

def soft(k, fc, order=2):
    """a gentle low-pass: how much of harmonic k passes a cutoff at harmonic fc"""
    return 1 / (1 + (k / fc) ** order)

def fade_tail(xs, frac=0.15):
    """one-shots end at exactly zero"""
    n = len(xs)
    m = int(n * frac)
    return [v * min(1.0, (n - 1 - i) / m) for i, v in enumerate(xs)]

def s_bass():
    """filtered saw with a sub sine, 128 samples per cycle: 8 cycles in which the filter
    closes and the level drops a little (the pluck), then the last cycle loops"""
    out = []
    for c in range(8):
        x = c / 7
        fc = 5 + 14 * (1 - x) ** 2
        amp = 1 - 0.3 * x
        hs = [(k, amp / k * soft(k, fc, 4), 0) for k in range(1, 48)]
        hs[0] = (1, hs[0][1] + 0.6 * amp, 0)
        out += cycle(128, hs)
    return out, 7 * 128, 128

def s_lead():
    """30% pulse, 32 samples per cycle, a brighter attack of 6 cycles, the 7th loops"""
    out, d = [], 0.3
    for c in range(7):
        x = c / 6
        fc = 6 + 6 * (1 - x)
        amp = 1 - 0.2 * x
        out += [amp * sum(2 / (k * math.pi) * math.sin(math.pi * k * d) * soft(k, fc)
                          * math.cos(2 * math.pi * k * (i / 32 - d / 2)) for k in range(1, 16))
                for i in range(32)]
    return out, 6 * 32, 32

def s_arp():
    """soft square, one looped cycle of 32 samples (for the arpeggio chords)"""
    return cycle(32, [(k, soft(k, 7) / k, 0) for k in range(1, 16, 2)]), 0, 32

def chord_loop(length, voices, sub):
    """a looped chord in just intonation: voices = cycles per loop of each chord tone, each a
    soft three-harmonic tone; sub = a quiet octave below the root"""
    hs, g = [], 0.618
    for j, (cyc, a) in enumerate(voices):
        for h, ha in ((1, 1.0), (2, 0.35), (3, 0.15)):
            hs.append((cyc * h, a * ha, 2 * math.pi * ((j * 3 + h) * g % 1)))
    hs.append((sub, 0.35, 0))
    return cycle(length, hs)

def s_pad_major():
    """root : third : fifth : octave = 4 : 5 : 6 : 8 cycles in 256 samples (root 64 samples)"""
    return chord_loop(256, [(4, 1), (5, 0.8), (6, 0.8), (8, 0.5)], 2), 0, 256

def s_pad_minor():
    """10 : 12 : 15 : 20 cycles in 640 samples (root 64 samples)"""
    return chord_loop(640, [(10, 1), (12, 0.8), (15, 0.8), (20, 0.5)], 5), 0, 640

def s_kick(dur=0.2):
    """sine swept from about 200 Hz down to 48 Hz, with a short noise click"""
    nz, out, ph = Noise(0x13579B), [], 0.0
    for i in range(int(dur * RATE_C3)):
        t = i / RATE_C3
        ph += (48 + 150 * math.exp(-t * 28)) / RATE_C3
        out.append(math.sin(2 * math.pi * ph) * math.exp(-t * 9) * min(1, t / 0.001)
                   + 0.3 * nz() * math.exp(-t * 400))
    return fade_tail(out)

def s_snare(dur=0.18):
    """two damped tones (180 and 330 Hz) and gently filtered noise"""
    nz, out, lp = Noise(0x2468AC), [], 0.0
    for i in range(int(dur * RATE_C3)):
        t = i / RATE_C3
        lp += 0.6 * (nz() - lp)
        out.append(0.6 * math.sin(2 * math.pi * 180 * t) * math.exp(-t * 30)
                   + 0.3 * math.sin(2 * math.pi * 330 * t) * math.exp(-t * 40)
                   + 0.9 * lp * math.exp(-t * 16))
    return fade_tail(out)

def s_hat(dur, decay, seed):
    """high-passed noise (the noise minus a low-passed copy of it), decaying"""
    nz, out, lp = Noise(seed), [], 0.0
    for i in range(int(dur * RATE_B3)):
        t = i / RATE_B3
        x = nz()
        lp += 0.35 * (x - lp)
        out.append((x - lp) * math.exp(-t * decay))
    return fade_tail(out, 0.3)

def s_bell(dur=0.45):
    """glockenspiel-like partials 1 : 2.76 : 5.40, the higher ones dying faster; at C-3 it
    sounds the same C as the lead's C-3 (RATE_C3 / 32)"""
    f = RATE_C3 / 32
    out = []
    for i in range(int(dur * RATE_C3)):
        t = i / RATE_C3
        out.append(min(1, t / 0.002) * (math.sin(2 * math.pi * f * t) * math.exp(-t * 5)
                   + 0.5 * math.sin(2 * math.pi * 2.756 * f * t) * math.exp(-t * 9)
                   + 0.25 * math.sin(2 * math.pi * 5.404 * f * t) * math.exp(-t * 14)))
    return fade_tail(out)

def to_s8(xs, peak=0.97):
    """normalise to the 8-bit signed range; an even number of bytes"""
    m = max(abs(v) for v in xs) or 1
    b = bytes(max(-127, min(127, round(v / m * peak * 127))) & 255 for v in xs)
    return b + b'\0' * (len(b) & 1)

class Sample:
    def __init__(self, name, synth, volume):
        r = synth()
        if isinstance(r, tuple):                  # looped: (data, loop start, loop length)
            xs, ls, ll = r
            self.data = to_s8(xs)
            self.loop = (ls, ll)
        else:                                     # one-shot: first word silent (ProTracker)
            b = bytearray(to_s8(r))
            b[0] = b[1] = 0
            self.data = bytes(b)
            self.loop = (0, 2)
        self.name, self.volume = name, volume

# ---------------------------------------------------------------------------- patterns

class Pattern:
    """64 rows x 4 channels, each cell [note index or None, sample, effect or None, param]"""
    def __init__(self):
        self.cells = [[[None, 0, None, 0] for _ in range(4)] for _ in range(64)]

    def note(self, ch, row, n, inst, fx=None, par=0):
        c = self.cells[row][ch]
        assert c[0] is None and c[2] is None, (ch, row)
        c[0], c[1] = n, inst
        if fx is not None:
            self.fx(ch, row, fx, par)

    def fx(self, ch, row, fx, par):
        c = self.cells[row][ch]
        assert c[2] is None, ('effect clash', ch, row)
        c[2], c[3] = fx, par

    def pack(self):
        out = bytearray()
        for row in self.cells:
            for n, s, fx, par in row:
                p = PERIODS[n] if n is not None else 0
                fx = fx or 0
                out += bytes([(s & 0xF0) | (p >> 8), p & 0xFF, ((s & 0x0F) << 4) | fx, par])
        return bytes(out)

def melody(p, ch, start, text, inst, vib=0x52, porta=0x03):
    """lay a line of 'NOTE:rows' tokens from row start ('|' is ignored, '.' is a rest).
    Flags after the length: d = note delayed half a row (ED3), p = tone portamento to the note
    (3xx for 6 rows, no sample number, then vibrato). Notes of 6 rows or more get vibrato
    (4xy) from their 3rd row."""
    row = start
    for tok in text.split():
        if tok == '|':
            continue
        n, d = tok.split(':')
        flags = ''
        while d[-1].isalpha():
            flags, d = flags + d[-1], d[:-1]
        d = int(d)
        if n == '.':
            p.fx(ch, row, 0xC, 0)
        elif 'p' in flags:
            p.note(ch, row, note(n), 0, 0x3, porta)
            for r in range(row + 1, row + min(6, d)):
                p.fx(ch, r, 0x3, 0)
            for r in range(row + 6, row + d):
                p.fx(ch, r, 0x4, vib)
        else:
            p.note(ch, row, note(n), inst, *((0xE, 0xD3) if 'd' in flags else ()))
            if d >= 6:
                for r in range(row + 2, row + d):
                    p.fx(ch, r, 0x4, vib)
        row += d
    return row

# drum letters: K kick, S snare, g ghost snare (sample offset 9xx: starts into its decay),
# f snare delayed half a row (EDx), h soft closed hat (Cxx), H closed hat, o open hat,
# r closed-hat roll (retrigger E9x)
def drums(p, ch, row, groove, kit, roll=0x93):
    K, S, H, O = kit
    for i, c in enumerate(groove):
        r = row + i
        if c == 'K': p.note(ch, r, note('C-3'), K)
        elif c == 'S': p.note(ch, r, note('C-3'), S)
        elif c == 'g': p.note(ch, r, note('C-3'), S, 0x9, 0x06)
        elif c == 'G': p.note(ch, r, note('C-3'), S, 0x9, 0x03)
        elif c == 'f': p.note(ch, r, note('C-3'), S, 0xE, 0xD3)
        elif c == 'h': p.note(ch, r, note('B-3'), H, 0xC, 0x16)
        elif c == 'H': p.note(ch, r, note('B-3'), H)
        elif c == 'o': p.note(ch, r, note('B-3'), O)
        elif c == 'r': p.note(ch, r, note('B-3'), H, 0xE, roll)
        else: assert c == '.', c

def chord_root(chord):
    """'F#m' -> ('F#', minor?)"""
    minor = chord.endswith('m')
    name = chord[:-1] if minor else chord
    return (name if len(name) == 2 else name + '-'), minor

# bass letters: L root (octave 2), H root an octave up, 5 the fifth above the root
def bass(p, ch, row, chord, style, inst):
    root = note(chord_root(chord)[0] + '2')
    for i, c in enumerate(style):
        if c == 'L': p.note(ch, row + i, root, inst)
        elif c == 'H': p.note(ch, row + i, root + 12, inst)
        elif c == '5': p.note(ch, row + i, root + 7, inst)
        else: assert c == '.', c

def stabs(p, ch, row, chord, inst, rows=(2, 6, 10, 14), cut_last=True):
    """off-beat arpeggio chords: note + 0xy for two rows, then volume 0 (the last cut is left
    out at the end of a pattern, or when the next bar starts a new chord itself)"""
    name, minor = chord_root(chord)
    arp = 0x37 if minor else 0x47
    for r in rows:
        p.note(ch, row + r, note(name + '2'), inst, 0x0, arp)
        p.fx(ch, row + r + 1, 0x0, arp)
        if row + r + 2 < 64 and (cut_last or r != rows[-1]):
            p.fx(ch, row + r + 2, 0xC, 0)

def pad(p, ch, row, chord, maj, mnr, swell=None):
    """a held chord sample; swell = (start volume, Axy, rows of sliding)"""
    name, minor = chord_root(chord)
    octave = '2' if name in ('G-', 'G#', 'A-', 'A#', 'B-') else '3'
    inst = mnr if minor else maj
    if swell:
        v, a, n = swell
        p.note(ch, row, note(name + octave), inst, 0xC, v)
        for r in range(row + 1, row + 1 + n):
            p.fx(ch, r, 0xA, a)
    else:
        p.note(ch, row, note(name + octave), inst)

# ---------------------------------------------------------------------------- "Horizon"

def horizon():
    smp = [Sample('kick', s_kick, 64), Sample('snare', s_snare, 52),
           Sample('closed hat', lambda: s_hat(0.05, 70, 0x0BADA55), 34),
           Sample('open hat', lambda: s_hat(0.18, 14, 0x5EED5), 26),
           Sample('bass', s_bass, 46), Sample('lead', s_lead, 40),
           Sample('arp square', s_arp, 22), Sample('pad major', s_pad_major, 30),
           Sample('pad minor', s_pad_minor, 30), Sample('bell', s_bell, 44)]
    KICK, SNARE, HAT, OHAT, BASS, LEAD, ARP, PMAJ, PMIN, BELL = range(1, 11)
    kit = (KICK, SNARE, HAT, OHAT)
    B, D, L, C = 0, 1, 2, 3         # channels: bass, drums, lead, chords (Amiga L R R L)
    GA = 'K.h.S.h.K.h.S.hh'
    GB = 'K.hKS.h.K.hKS.o.'

    # 0: intro - pad swells, bells hint at the tune, bass and kick come in, a fill and a
    #    lead swoop (1xx) lead into the A part
    intro = Pattern()
    intro.fx(B, 0, 0xF, 132)        # tempo 132
    intro.fx(D, 0, 0xF, 6)          # speed 6
    for bar, ch in enumerate(['C', 'Am', 'F', 'G']):
        pad(intro, C, bar * 16, ch, PMAJ, PMIN, (8, 0x10, 7))
    melody(intro, L, 0, 'C-3:4 E-3:4 G-3:8 | A-3:4 G-3:4 E-3:8 | F-3:4 E-3:4 C-3:8 | D-3:4',
           BELL)
    intro.note(L, 52, note('C-2'), LEAD)
    for r in range(53, 64):
        intro.fx(L, r, 0x1, 0x02)
    drums(intro, D, 0, '..h...h...h...h.' * 2 + 'K.h...h.K.h...h.', kit)
    drums(intro, D, 48, 'K.h.S.h.gGgGSSSf', kit)
    bass(intro, B, 32, 'F', 'L.......L.....L.', BASS)
    bass(intro, B, 48, 'G', 'L.......L.L.H.H.', BASS)

    # 1, 2: the A part (C Am F G), arpeggio stabs, octave bass
    def a_part(tune, last_groove):
        p = Pattern()
        for bar, ch in enumerate(['C', 'Am', 'F', 'G']):
            bass(p, B, bar * 16, ch, 'L.H.L.H.L.H.L.H.', BASS)
            stabs(p, C, bar * 16, ch, ARP)
            drums(p, D, bar * 16, GA if bar < 3 else last_groove, kit)
        p.fx(D, 0, 0xF, 6)          # back to speed 6 after the slower break
        melody(p, L, 0, tune, LEAD)
        return p
    a1 = a_part('G-2:4 C-3:2 E-3:2 D-3:4 C-3:4 | E-3:6 D-3:2 C-3:4 A-2:4 |'
                ' A-2:2 C-3:2 F-3:4 E-3:2 D-3:2 C-3:4 | D-3:10 .:2 B-2:2 D-3:2', GA)
    a2 = a_part('G-2:4 C-3:2 E-3:2 G-3:4 E-3:4 | A-3:6 G-3:2 E-3:4 C-3:4 |'
                ' F-3:4 E-3:2 D-3:2 C-3:2 A-2:2 C-3:4 | D-3:6 E-3:2 D-3:4 B-2:4',
                'K.h.S.h.K.SgS.SS')

    # 3, 4: the B part, driving bass, held pad chords with a swell
    def b_part(chords, tune, last_groove):
        p = Pattern()
        for bar, ch in enumerate(chords):
            bass(p, B, bar * 16, ch, 'L..L..H.L.5.L.H.', BASS)
            pad(p, C, bar * 16, ch, PMAJ, PMIN, (20, 0x10, 4))
            drums(p, D, bar * 16, GB if bar < 3 else last_groove, kit)
        melody(p, L, 0, tune, LEAD, porta=0x02)
        return p
    b1 = b_part(['F', 'G', 'Em', 'Am'],
                'C-3:2 F-3:2 A-3:4 G-3:2 F-3:2 E-3:4d | D-3:2 G-3:2 B-3:4 A-3:2 G-3:2 D-3:4 |'
                ' E-3:2 G-3:2 B-3:6 A-3:2 G-3:4 | A-3:8 E-3:8p', GB)
    b2 = b_part(['F', 'G', 'C', 'C'],
                'C-3:2 F-3:2 A-3:4 G-3:2 F-3:2 A-3:4 | B-3:4 A-3:2 G-3:2 D-3:4 G-3:4 |'
                ' E-3:4 G-3:2 E-3:2 C-3:4 D-3:2 E-3:2 | C-3:12 .:4', 'K.h.S.h.KhSgSSSf')

    # 5: the break - slower (speed 8), bells over swelling pads, the bass glides between
    #    roots (3xx), half a bar of G with a hat roll (E9x) and snares, cut short (D00)
    brk = Pattern()
    brk.fx(D, 0, 0xF, 8)
    for bar, ch in enumerate(['Am', 'F', 'C', 'G']):
        pad(brk, C, bar * 16, ch, PMAJ, PMIN, (10, 0x10, 6))
    melody(brk, L, 0, 'E-3:4 A-3:4 G-3:4 E-3:4 | F-3:4 A-3:4 C-3:8 |'
           ' E-3:4 G-3:4 C-3:4 E-3:4 | D-3:4 B-2:4', BELL)
    brk.note(B, 0, note('A-2'), BASS)
    for row, n in ((16, 'F-2'), (32, 'C-2'), (48, 'G-2')):
        brk.note(B, row, note(n), 0, 0x3, 0x04)
        for r in range(row + 1, row + 6):
            brk.fx(B, r, 0x3, 0)
    drums(brk, D, 0, '....h.......h...', kit)
    drums(brk, D, 16, 'K...h.......h...' * 2, kit)
    drums(brk, D, 48, 'K.rrgGSS', kit, roll=0x92)
    brk.fx(C, 55, 0xD, 0)

    # 6: the outro (F G C) - the tune's opening, then a ritardando (F07..F0C), the lead fades
    #    with vibrato (6xy), the bass dives (2xx), and B00 jumps back to the start
    out = Pattern()
    for bar, ch in enumerate(['F', 'G']):
        bass(out, B, bar * 16, ch, 'L.H.L.H.L.H.L.H.', BASS)
        stabs(out, C, bar * 16, ch, ARP, cut_last=bar == 0)
        drums(out, D, bar * 16, GA if bar == 0 else 'K.h.S.h.K.SgS.SS', kit)
    melody(out, L, 0, 'A-2:2 C-3:2 F-3:4 E-3:2 D-3:2 C-3:4 | D-3:6 E-3:2 D-3:4 B-2:4', LEAD)
    out.note(L, 32, note('C-3'), LEAD)
    for r in range(34, 63):
        out.fx(L, r, 0x4 if r < 44 else 0x6, 0x52 if r < 44 else 0x01)
    pad(out, C, 32, 'C', PMAJ, PMIN)
    for r in range(44, 63):
        out.fx(C, r, 0xA, 0x01)
    out.note(B, 32, note('C-2'), BASS)
    out.note(B, 48, note('C-3'), BASS)
    for r in range(52, 63):
        out.fx(B, r, 0x2, 0x03)
    out.note(D, 32, note('C-3'), KICK, 0xF, 7)
    out.fx(D, 40, 0xF, 8)
    out.fx(D, 48, 0xF, 10)
    out.fx(D, 56, 0xF, 12)
    out.fx(D, 63, 0xB, 0)

    pats = [intro, a1, a2, b1, b2, brk, out]
    orders = [0, 1, 2, 3, 4, 5, 1, 2, 3, 4, 6]
    return 'Horizon', smp, pats, orders

# ---------------------------------------------------------------------------- "Lau"

def lau():
    smp = [Sample('kick', lambda: s_kick(0.16), 64), Sample('snare', lambda: s_snare(0.14), 50),
           Sample('closed hat', lambda: s_hat(0.04, 80, 0x0BADA55), 34),
           Sample('bass', s_bass, 46), Sample('lead', s_lead, 40),
           Sample('arp square', s_arp, 24), Sample('bell', lambda: s_bell(0.4), 48)]
    KICK, SNARE, HAT, BASS, LEAD, ARP, BELL = range(1, 8)
    kit = (KICK, SNARE, HAT, HAT)
    B, D, L, C = 0, 1, 2, 3
    G = 'K.hhS.h.K.hKS.h.'

    def part(chords, tune, fill):
        p = Pattern()
        for bar, ch in enumerate(chords):
            bass(p, B, bar * 16, ch, 'L.H.L.H.L.H.L5H.', BASS)
            stabs(p, C, bar * 16, ch, ARP)
            drums(p, D, bar * 16, G if bar < 3 else fill, kit, roll=0x92)
        melody(p, L, 0, tune, LEAD, porta=0x05)
        return p

    # "La-u": La is A, so the tune lives in A major and keeps returning to A
    p0 = part(['A', 'F#m', 'D', 'E'],
              'C#3:2 E-3:2 A-3:6 E-3:2 F#3:2 E-3:2 | C#3:6 A-2:2 C#3:2 E-3:2 F#3:4 |'
              ' F#3:2 A-3:2 F#3:2 E-3:2 D-3:4 F#3:4 | E-3:12 B-2:2 D-3:2', 'K.hhS.h.K.SgS.rr')
    p0.fx(B, 0, 0xF, 150)
    p0.fx(D, 0, 0xF, 5)
    p1 = part(['A', 'D', 'E', 'A'],
              'C#3:2 E-3:2 A-3:6 B-3:2 A-3:2 E-3:2 | F#3:4 A-3:4 F#3:2 E-3:2 D-3:4 |'
              ' B-2:2 D-3:2 G#3:4 F#3:2 E-3:2 D-3:4 | C#3:2 E-3:2 A-3:12p', 'K.h.S.h.KhSgSSSf')

    # the ending: the A chord rings, the bell calls "La-u" (E then A), everything slows
    # (F06, F08) and fades, and B00 goes back to the start
    end = Pattern()
    end.note(B, 0, note('A-2'), BASS)
    end.note(D, 0, note('C-3'), KICK)
    end.note(C, 0, note('E-3'), BELL)
    end.note(C, 4, note('A-3'), BELL)
    for r in range(0, 23):
        end.fx(L, r, 0x6, 0x01 if r >= 4 else 0x00)
    for r in range(8, 23):
        end.fx(B, r, 0xA, 0x01)
    end.fx(D, 8, 0xF, 6)
    end.fx(D, 16, 0xF, 8)
    end.fx(D, 23, 0xB, 0)
    return 'Lau', smp, [p0, p1, end], [0, 1, 2]

# ---------------------------------------------------------------------------- file

INFO = ['', 'Original music and', 'sounds generated by', 'horizon/tools/mkmod.py',
        'for the Atari816, 2026']

def build(title, smp, pats, orders):
    out = bytearray(title.encode('ascii').ljust(20, b'\0'))
    names = [s.name for s in smp] + INFO
    for i in range(31):
        name = names[i] if i < len(names) else ''
        out += name.encode('ascii').ljust(22, b'\0')[:22]
        if i < len(smp):
            s = smp[i]
            out += struct.pack('>HBBHH', len(s.data) // 2, 0, s.volume,
                               s.loop[0] // 2, s.loop[1] // 2)
        else:
            out += struct.pack('>HBBHH', 0, 0, 0, 0, 1)
    out += bytes([len(orders), 127]) + bytes(orders).ljust(128, b'\0') + b'M.K.'
    for p in pats:
        out += p.pack()
    for s in smp:
        out += s.data
    return bytes(out)

# ---------------------------------------------------------------------------- check

FX_NAMES = {0: 'arpeggio', 1: 'porta up', 2: 'porta down', 3: 'tone porta', 4: 'vibrato',
            5: 'tone porta+vol slide', 6: 'vibrato+vol slide', 7: 'tremolo', 9: 'sample offset',
            0xA: 'volume slide', 0xB: 'position jump', 0xC: 'set volume', 0xD: 'pattern break',
            0xF: 'speed/tempo'}

def check(path):
    """parse a module back, print its contents, flag constructs a strict replayer may mind"""
    m = open(path, 'rb').read()
    print(f'{path}: {len(m)} bytes, title "{m[:20].rstrip(bytes(1)).decode()}"')
    assert m[1080:1084] == b'M.K.', 'not an M.K. module'
    samples, problems = [], []
    for i in range(31):
        h = m[20 + 30 * i: 50 + 30 * i]
        name = h[:22].rstrip(b'\0').decode('ascii', 'replace')
        ln, ft, vol, ls, ll = struct.unpack('>HBBHH', h[22:])
        samples.append((name, ln * 2, ft, vol, ls * 2, ll * 2))
    nord, restart = m[950], m[951]
    orders = list(m[952:952 + nord])
    npat = max(m[952:1080]) + 1
    print(f'song length {nord}, restart {restart}, orders {orders}, {npat} patterns')
    pos = 1084 + npat * 1024
    for i, (name, ln, ft, vol, ls, ll) in enumerate(samples):
        if ln:
            loop = f'loop {ls}+{ll}' if ll > 2 else 'one-shot'
            first = m[pos:pos + 2]
            print(f'  {i + 1:2} {name:22} {ln:6} bytes  vol {vol:2}  {loop}')
            if ll <= 2 and first != b'\0\0':
                problems.append(f'sample {i + 1}: one-shot does not start with 0, 0')
            if ls + ll > ln:
                problems.append(f'sample {i + 1}: loop past the end')
            pos += ln
        elif name:
            print(f'     ({name})')
    if pos != len(m):
        problems.append(f'file size {len(m)}, expected {pos}')
    counts, played = {}, [False] * 4
    for o in orders:
        base = 1084 + o * 1024
        for r in range(64):
            jumps = []
            for ch in range(4):
                b = m[base + r * 16 + ch * 4: base + r * 16 + ch * 4 + 4]
                s = (b[0] & 0xF0) | (b[2] >> 4)
                p = ((b[0] & 0x0F) << 8) | b[1]
                fx, par = b[2] & 0x0F, b[3]
                if p and p not in PERIODS:
                    problems.append(f'pattern {o} row {r}: period {p} not in the table')
                if s and not samples[s - 1][1]:
                    problems.append(f'pattern {o} row {r}: empty sample {s}')
                if fx == 3 and not played[ch]:
                    problems.append(f'pattern {o} row {r} ch {ch}: tone porta before a note')
                if p:
                    played[ch] = True
                if fx or par:
                    key = f'E{par >> 4:X}x' if fx == 0xE else f'{fx:X}xx {FX_NAMES.get(fx, "")}'
                    counts[key] = counts.get(key, 0) + 1
                if fx in (0xB, 0xD):
                    jumps.append(fx)
            if len(jumps) > 1:
                problems.append(f'pattern {o} row {r}: several jumps on one row')
    print('effects (counted along the order list):')
    for k in sorted(counts):
        print(f'  {k:28} {counts[k]}')
    print('length: about %.1f s' % play_time(m, orders))
    print('problems:', '; '.join(problems) if problems else 'none')
    return not problems

def play_time(m, orders):
    """walk the song once (speed, tempo, Bxx, Dxx) and add up the row times"""
    speed, tempo, t, o, row, seen = 6, 125, 0.0, 0, 0, set()
    while o < len(orders) and (o, row) not in seen:
        seen.add((o, row))
        base = 1084 + orders[o] * 1024 + row * 16
        jump = brk = None
        for ch in range(4):
            fx, par = m[base + ch * 4 + 2] & 0x0F, m[base + ch * 4 + 3]
            if fx == 0xF and par:
                if par < 32: speed = par
                else: tempo = par
            elif fx == 0xB: jump = par
            elif fx == 0xD: brk = (par >> 4) * 10 + (par & 15)
        t += speed * 2.5 / tempo
        if jump is not None:
            o, row = jump, brk or 0
        elif brk is not None:
            o, row = o + 1, brk
        else:
            row += 1
            if row == 64:
                o, row = o + 1, 0
    return t

def main():
    args = sys.argv[1:]
    if args and args[0] == '--check':
        sys.exit(0 if all([check(f) for f in args[1:]]) else 1)
    song = lau() if '--jingle' in args else horizon()
    out = [a for a in args if not a.startswith('--')]
    if len(out) != 1:
        sys.exit(__doc__)
    data = build(*song)
    open(out[0], 'wb').write(data)
    print(f'{out[0]}: "{song[0]}", {len(song[2])} patterns, {len(song[3])} orders, '
          f'{len(data)} bytes')

main()
