#!/usr/bin/env python3
"""mkqbsfx.py OUT.SFX [--wav DIR] - Quabricks' sound effects for Lau, the sample player.

Synthesised here at build time (no recordings), in the character of the SDL2 Quabricks'
tools/gen_sfx.py: short triangle ticks for moving, a falling glide for rotating, a low
thump with a noise click for the hard drop, soft sine bells for clears that grow with the
number of lines, a falling run of bells for the end. The notes and envelopes are this
program's own.

OUT.SFX: "QSFX", u8 count, u8 rate code (1 = 16000 Hz), then count x {u16 offset, u16 length}
(offset from the start of the file), then the samples: signed 8-bit, 16000 Hz, mono. The order
is SFX_* in user/quabrick.s. --wav writes each effect as a .wav to look at or listen to."""
import math, os, struct, sys

SR = 16000
OUT = sys.argv[1]
WAV = sys.argv[sys.argv.index('--wav') + 1] if '--wav' in sys.argv else None

def n_of(t):
    return int(t * SR)

def sine(f, t):
    return math.sin(2 * math.pi * f * t)

def tri(f, t):
    x = (f * t) % 1.0
    return 4 * abs(x - 0.5) - 1

_seed = [0x2468ACE]
def noise():
    _seed[0] = (1103515245 * _seed[0] + 12345) & 0x7FFFFFFF
    return _seed[0] / 0x3FFFFFFF - 1.0

def env(t, dur, a, d, s, r):
    if t < a:
        return t / a
    if t < a + d:
        return 1 - (1 - s) * (t - a) / d
    if t < dur - r:
        return s
    return max(0.0, s * (dur - t) / r) if r else 0.0

def tone(f, dur, wave=sine, a=0.002, d=0.02, s=0.3, r=0.03):
    return [wave(f, i / SR) * env(i / SR, dur, a, d, s, r) for i in range(n_of(dur))]

def glide(f0, f1, dur, wave=sine, a=0.002, r=0.04):
    out, ph = [], 0.0
    for i in range(n_of(dur)):
        t = i / SR
        f = f0 * (f1 / f0) ** (t / dur)
        ph += f / SR
        x = ph % 1.0
        w = math.sin(2 * math.pi * x) if wave is sine else 4 * abs(x - 0.5) - 1
        out.append(w * env(t, dur, a, 0, 1, r))
    return out

def bells(notes, note=0.1, gap=0.05, decay=14, wave=sine):
    total = gap * (len(notes) - 1) + note + 0.03
    out = [0.0] * n_of(total)
    for k, f in enumerate(notes):
        st = n_of(k * gap)
        for i in range(n_of(note)):
            if st + i >= len(out):
                break
            t = i / SR
            e = math.exp(-t * decay) * min(1.0, t / 0.002)
            out[st + i] += (wave(f, t) * 0.8 + sine(2 * f, t) * 0.2) * e
    return out

def mix(*ls):
    n = max(len(l) for l in ls)
    out = [0.0] * n
    for l in ls:
        for i, v in enumerate(l):
            out[i] += v
    return out

def gain(l, g):
    return [v * g for v in l]

def clip(l):
    return [math.tanh(v * 1.2) for v in l]

def thump(f0, f1, dur):
    return glide(f0, f1, dur, sine, 0.001, dur * 0.6)

# MIDI note -> Hz
def m(n):
    return 440.0 * 2 ** ((n - 69) / 12)

def fx_move():
    return tone(720, 0.04, tri, 0.001, 0.012, 0.15, 0.02)
def fx_rotate():
    return clip(gain(mix(tone(380, 0.045, tri, 0.001, 0.02, 0.2, 0.02), glide(520, 320, 0.06, tri)), 0.7))
def fx_soft():
    return tone(280, 0.03, sine, 0.001, 0.01, 0.1, 0.015)
def fx_hard():
    click = [noise() * math.exp(-i / SR * 70) for i in range(n_of(0.04))]
    return clip(mix(gain(glide(210, 85, 0.15, tri, 0.001, 0.08), 0.7),
                    gain(thump(115, 50, 0.15), 0.9), gain(click, 0.5)))
def fx_lock():
    c = [(noise() * 0.4 + tri(420, i / SR) * 0.6) * math.exp(-i / SR * 48) for i in range(n_of(0.05))]
    return clip(mix(c, gain(tone(310, 0.06, sine, 0.001, 0.03, 0.15, 0.025), 0.6)))
# the clears: bells rising, one more note (and a brighter layer) per line
def fx_clear1():
    return gain(bells([m(74), m(79)], 0.11, 0.05), 0.62)
def fx_clear2():
    return gain(bells([m(74), m(79), m(83)], 0.11, 0.05), 0.74)
def fx_clear3():
    return gain(mix(bells([m(74), m(79), m(83), m(86)], 0.11, 0.05),
                    gain(bells([m(86), m(91), m(95)], 0.07, 0.045, 18, tri), 0.3)), 0.86)
def fx_clear4():
    return gain(clip(mix(bells([m(74), m(79), m(83), m(86), m(91)], 0.12, 0.055),
                         gain(bells([m(91), m(95), m(98), m(103)], 0.08, 0.05, 18, tri), 0.4),
                         gain(thump(150, 65, 0.2), 0.8))), 0.98)
def fx_level():
    return bells([m(76), m(81), m(85), m(88)], 0.1, 0.05, 14, tri)
def fx_over():
    return bells([m(71), m(67), m(64), m(59)], 0.2, 0.15, 9)
def fx_mmove():
    return tone(620, 0.04, tri, 0.001, 0.02, 0.2, 0.02)
def fx_msel():
    return clip(gain(mix(tone(660, 0.05, sine, 0.001, 0.02, 0.25, 0.025), glide(660, 990, 0.1, sine, 0.001, 0.05)), 0.8))
def fx_hold():
    return clip(gain(mix(tone(540, 0.045, tri, 0.001, 0.02, 0.2, 0.02), glide(610, 880, 0.055, tri)), 0.7))
def fx_pause():
    return glide(520, 340, 0.09, sine, 0.002, 0.045)

FX = [fx_move, fx_rotate, fx_soft, fx_hard, fx_lock, fx_clear1, fx_clear2, fx_clear3,
      fx_clear4, fx_level, fx_over, fx_mmove, fx_msel, fx_hold, fx_pause]
NAMES = ['move', 'rotate', 'softdrop', 'harddrop', 'lock', 'clear1', 'clear2', 'clear3',
         'clear4', 'levelup', 'gameover', 'menu_move', 'menu_select', 'hold', 'pause']
GAINS = {'clear1': 0.62, 'clear2': 0.74, 'clear3': 0.86, 'clear4': 0.98}

data, table = b'', []
head = 4 + 2 + 4 * len(FX)
for name, f in zip(NAMES, FX):
    s = f()
    pk = max(1e-9, max(abs(v) for v in s))
    g = GAINS.get(name, 0.85) / pk
    b = bytes((max(-127, min(127, int(round(v * g * 127)))) & 255) for v in s)
    table.append((head + len(data), len(b)))
    data += b
    if WAV:
        import wave
        os.makedirs(WAV, exist_ok=True)
        with wave.open(os.path.join(WAV, name + '.wav'), 'w') as w:
            w.setnchannels(1); w.setsampwidth(1); w.setframerate(SR)
            w.writeframes(bytes((x + 128) & 255 for x in b))
out = b'QSFX' + bytes([len(FX), 1]) + b''.join(struct.pack('<HH', o, l) for o, l in table) + data
assert len(out) < 65536
open(OUT, 'wb').write(out)
print(f'QUABRICK.SFX: {len(FX)} effects, {len(data)} bytes of samples ({len(data) / SR:.2f} s at 16 kHz), {len(out)} bytes')
