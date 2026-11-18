#!/usr/bin/env python3
"""mkfcsfx.py OUT.SFX [--wav DIR] - FreeCell's sound effects for Lau, the sample player.

Synthesised here at build time (no recordings): a soft tick when a card is taken, a short
snap when it is put down, a little bell when it goes home, two low soft notes when a move is
not allowed, a rising run of bells for the win, a riffle for a new deal.

OUT.SFX: "FSFX", u8 count, u8 rate code (1 = 16000 Hz), then count x {u16 offset, u16 length}
(offset from the start of the file), then the samples: signed 8-bit, 16000 Hz, mono. The order
is SFX_* in user/fc_snd.s. --wav writes each effect as a .wav to listen to."""
import math, os, struct, sys

SR = 16000
OUT = sys.argv[1]
WAV = sys.argv[sys.argv.index('--wav') + 1] if '--wav' in sys.argv else None

_seed = [0x1F2E3D]
def noise():
    _seed[0] = (1103515245 * _seed[0] + 12345) & 0x7FFFFFFF
    return _seed[0] / 0x3FFFFFFF - 1.0

def n_of(t):
    return int(t * SR)

def bell(f, dur, amp=1.0):
    out = []
    for i in range(n_of(dur)):
        t = i / SR
        e = math.exp(-t * 9) * min(1, t * 400)
        out.append(amp * e * (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * 2.01 * f * t)
                              + 0.12 * math.sin(2 * math.pi * 3.0 * f * t)))
    return out

def click(dur, amp, tone=0.0, f=180):
    out, lp = [], 0.0
    for i in range(n_of(dur)):
        t = i / SR
        e = math.exp(-t * 160)
        lp += 0.45 * (noise() - lp)
        out.append(amp * e * (lp + tone * math.sin(2 * math.pi * f * t) * math.exp(-t * 40)))
    return out

def soft(f, dur, amp):
    out = []
    for i in range(n_of(dur)):
        t = i / SR
        e = min(1, t * 200) * min(1, (dur - t) * 60)
        x = math.sin(2 * math.pi * f * t)
        out.append(amp * e * (x + 0.2 * math.sin(2 * math.pi * 2 * f * t)))
    return out

def silence(dur):
    return [0.0] * n_of(dur)

def mix(a, b, at=0.0):
    k = n_of(at)
    out = a + [0.0] * max(0, k + len(b) - len(a))
    for i, v in enumerate(b):
        out[k + i] += v
    return out

def fx_pick():
    return click(0.025, 0.5)

def fx_place():
    return click(0.06, 0.9, tone=0.6, f=150)

def fx_home():
    return bell(1318.5, 0.22, 0.5)

def fx_bad():
    return soft(196, 0.07, 0.5) + silence(0.03) + soft(174.6, 0.10, 0.5)

def fx_win():
    out = []
    for k, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5)):
        out = mix(out, bell(f, 0.5, 0.45), k * 0.11)
    for f in (523.25, 659.25, 783.99):
        out = mix(out, bell(f, 0.9, 0.3), 0.62)
    return out

def fx_deal():
    out = []
    for k in range(9):
        out = mix(out, click(0.03, 0.55 - k * 0.03), k * 0.028)
    return out

FX = [fx_pick, fx_place, fx_home, fx_bad, fx_win, fx_deal]

def q8(s):
    peak = max(1e-9, max(abs(v) for v in s))
    g = min(1.0, 0.95 / peak)
    return [max(-127, min(127, int(round(v * g * 127)))) for v in s]

samples = [q8(f()) for f in FX]
table, data, off = [], b'', 6 + 4 * len(FX)
for s in samples:
    b = bytes(v & 255 for v in s)
    table.append((off + len(data), len(b)))
    data += b
out = b'FSFX' + bytes([len(FX), 1]) + b''.join(struct.pack('<HH', o, l) for o, l in table) + data
assert len(out) < 65536
open(OUT, 'wb').write(out)
if WAV:
    import wave
    os.makedirs(WAV, exist_ok=True)
    for f, s in zip(FX, samples):
        with wave.open(os.path.join(WAV, f.__name__ + '.wav'), 'wb') as w:
            w.setnchannels(1); w.setsampwidth(1); w.setframerate(SR)
            w.writeframes(bytes((x + 128) & 255 for x in s))
