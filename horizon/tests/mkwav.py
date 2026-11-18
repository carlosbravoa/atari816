#!/usr/bin/env python3
"""mkwav.py DIR - the sound files BASIC 2.0's test (tests/basic2.bas) loads with WAVE:
T8.WAV (8-bit unsigned PCM, mono, 22,050 Hz, 0.1 s of a 441 Hz square), T16.WAV (16-bit
signed, mono, 11,025 Hz, 0.05 s, a LIST chunk before "data"), TST.WAV (stereo: refused),
TRAW.SND (raw signed 8-bit samples, 800 bytes)."""
import os
import struct
import sys

d = sys.argv[1]


def riff(fmt, data, extra=b''):
    body = b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt + extra + \
        b'data' + struct.pack('<I', len(data)) + data
    return b'RIFF' + struct.pack('<I', len(body)) + body


def fmt(ch, rate, bits):
    return struct.pack('<HHIIHH', 1, ch, rate, rate * ch * bits // 8, ch * bits // 8, bits)


sq8 = bytes(200 if (i // 25) % 2 else 56 for i in range(2205))
open(os.path.join(d, 'T8.WAV'), 'wb').write(riff(fmt(1, 22050, 8), sq8))
s16 = b''.join(struct.pack('<h', 8000 if (i // 10) % 2 else -8000) for i in range(551))
lst = b'LIST' + struct.pack('<I', 5) + b'INFOx' + b'\0'
open(os.path.join(d, 'T16.WAV'), 'wb').write(riff(fmt(1, 11025, 16), s16, lst))
open(os.path.join(d, 'TST.WAV'), 'wb').write(riff(fmt(2, 22050, 16), b'\0' * 400))
open(os.path.join(d, 'TRAW.SND'), 'wb').write(bytes((i * 7) & 0xFF for i in range(800)))
