#!/usr/bin/env python3
"""Generate demo Standard MIDI Files (SMF Type 1) to test Horizon's OPL2 MIDI player.

Generates:
  OPLGROOVE.MID  - 5-track 80s FM synth-funk showcase (E-Piano, FM Bass, Synth Brass/Lead
                   with pitch bend, Strings, GM Drums with hi-hat choke & sustain pedal)
  BAROQUE.MID    - 3-track Harpsichord / Piano baroque counterpoint with ritardando
"""
import os
import struct
import sys


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


class Track:
    def __init__(self, name=None):
        self.events = []  # (abs_tick, order, bytes)
        if name:
            self.meta(0, 0x03, name.encode("ascii"))

    def add(self, tick, data, order=1):
        self.events.append((int(tick), order, bytes(data)))

    def meta(self, tick, mtype, payload):
        self.add(tick, bytes([0xFF, mtype]) + vlq(len(payload)) + payload, order=0)

    def tempo(self, tick, bpm):
        us = int(round(60_000_000 / bpm))
        self.meta(tick, 0x51, bytes([(us >> 16) & 0xFF, (us >> 8) & 0xFF, us & 0xFF]))

    def prog(self, tick, ch, p):
        self.add(tick, [0xC0 | ch, p & 0x7F], order=0)

    def cc(self, tick, ch, num, val):
        self.add(tick, [0xB0 | ch, num & 0x7F, val & 0x7F], order=0)

    def bend(self, tick, ch, val):
        # val in -8192..+8191
        u = max(0, min(16383, val + 8192))
        self.add(tick, [0xE0 | ch, u & 0x7F, (u >> 7) & 0x7F], order=1)

    def note(self, tick, dur, ch, pitch, vel=100):
        self.add(tick, [0x90 | ch, pitch & 0x7F, vel & 0x7F], order=2)
        self.add(tick + dur, [0x80 | ch, pitch & 0x7F, 0], order=1)

    def encode(self):
        self.events.sort(key=lambda e: (e[0], e[1]))
        buf = bytearray()
        last = 0
        for t, _, data in self.events:
            buf += vlq(t - last)
            buf += data
            last = t
        buf += vlq(0) + b"\xFF\x2F\x00"
        return b"MTrk" + struct.pack(">I", len(buf)) + bytes(buf)


def write_smf(path, tracks, ppqn=480):
    hdr = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), ppqn)
    with open(path, "wb") as f:
        f.write(hdr)
        for tr in tracks:
            f.write(tr.encode())


def make_oplgroove(path):
    Q = 480  # quarter note
    S = Q // 4  # 16th note
    B = Q * 4  # 1 bar = 4 beats

    t0 = Track("OPL2 Synth Groove")
    t0.tempo(0, 122)

    t_ep = Track("Electric Piano")
    t_ep.prog(0, 0, 4)       # Rhodes E-Piano
    t_ep.cc(0, 0, 7, 108)

    t_bs = Track("FM Synth Bass")
    t_bs.prog(0, 1, 38)      # Synth Bass 1
    t_bs.cc(0, 1, 7, 118)

    t_ld = Track("Synth Brass Lead")
    t_ld.prog(0, 2, 62)      # Synth Brass 1
    t_ld.cc(0, 2, 7, 112)

    t_st = Track("String Pad")
    t_st.prog(0, 3, 48)      # String Ensemble 1
    t_st.cc(0, 3, 7, 82)

    t_dr = Track("GM Drums")
    t_dr.cc(0, 9, 7, 115)

    # 4-bar progression in D minor: Dm9 -> Bbmaj7 -> Gm7 -> A7sus4 / A7
    chords = [
        ([50, 57, 60, 64, 65], 38),  # Dm9 (root D2=38)
        ([46, 53, 57, 60, 62], 34),  # Bbmaj7 (root Bb1=34)
        ([43, 50, 53, 58, 62], 31),  # Gm7 (root G1=31)
        ([45, 52, 55, 61, 64], 33),  # A7 (root A1=33)
    ]

    melody_a = [
        # (bar_in_4, 16th_offset, len_16ths, note, vel, bend_end)
        (0, 0, 3, 74, 108, 0), (0, 3, 3, 77, 102, 0), (0, 6, 4, 81, 112, 0),
        (0, 10, 2, 79, 98, 0), (0, 12, 4, 77, 105, 0),
        (1, 0, 4, 74, 108, 0), (1, 4, 2, 72, 96, 0), (1, 6, 4, 74, 108, 0),
        (1, 10, 6, 70, 104, 1200),
        (2, 0, 3, 70, 106, 0), (2, 3, 3, 74, 104, 0), (2, 6, 4, 77, 112, 0),
        (2, 10, 2, 76, 100, 0), (2, 12, 4, 74, 106, 0),
        (3, 0, 6, 73, 110, 0), (3, 6, 2, 74, 100, 0), (3, 8, 4, 76, 114, 0),
        (3, 12, 4, 79, 116, -2000),
    ]

    # 16 bars total (~31.5 seconds)
    for sec in range(4):
        if sec == 2:
            t_ld.prog(sec * 4 * B, 2, 81)  # Switch to Sawtooth Lead for section B!
            t_ep.prog(sec * 4 * B, 0, 5)   # Switch to DX7 E-Piano 2!
        elif sec == 3:
            t_ld.prog(sec * 4 * B, 2, 62)  # Back to Synth Brass
            t_ep.prog(sec * 4 * B, 0, 4)

        for bi in range(4):
            bar_t = (sec * 4 + bi) * B
            c_notes, root = chords[bi]

            # E-Piano: syncopated chords with sustain pedal
            t_ep.cc(bar_t, 0, 64, 127)
            for n in c_notes[:4]:
                t_ep.note(bar_t, 6 * S, 0, n, 86)
            t_ep.cc(bar_t + 7 * S, 0, 64, 0)
            for n in c_notes[1:]:
                t_ep.note(bar_t + 8 * S, 5 * S, 0, n, 82)

            # Strings pad in sections 1, 2, 3
            if sec >= 1:
                t_st.note(bar_t, B - S, 3, c_notes[2], 74)
                t_st.note(bar_t, B - S, 3, c_notes[3], 70)

            # Funky FM bassline
            bass_pat = [
                (0, 3, root, 112), (3, 2, root, 96), (6, 2, root + 12, 108),
                (8, 3, root, 110), (11, 2, root + 7, 102), (14, 2, root + 10, 104),
            ]
            for off, ln, pitch, vel in bass_pat:
                t_bs.note(bar_t + off * S, ln * S - 20, 1, pitch, vel)

            # Drums (Channel 9): Kick, Snare, Closed/Open Hi-Hat, Crash on section start
            if bi == 0:
                t_dr.note(bar_t, S, 9, 49, 105)  # Crash Cymbal 1
            for step in range(16):
                st = bar_t + step * S
                if step in (0, 6, 8, 10):
                    t_dr.note(st, S, 9, 36, 118 if step in (0, 8) else 98)
                if step in (4, 12):
                    t_dr.note(st, S, 9, 38, 112)
                if step == 14:
                    t_dr.note(st, S, 9, 46, 94)  # Open Hi-Hat (choked at step 0!)
                elif step % 2 == 0:
                    t_dr.note(st, S, 9, 42, 86 if step % 4 == 0 else 68)
            # Tom fill at end of every 4th bar
            if bi == 3:
                t_dr.note(bar_t + 12 * S, S, 9, 50, 104)
                t_dr.note(bar_t + 13 * S, S, 9, 48, 104)
                t_dr.note(bar_t + 14 * S, S, 9, 47, 108)
                t_dr.note(bar_t + 15 * S, S, 9, 45, 112)

        # Lead melody in sections 1, 2, 3
        if sec >= 1:
            base_t = sec * 4 * B
            for bi, off, ln, pitch, vel, bend_end in melody_a:
                nt = base_t + bi * B + off * S
                nd = ln * S - 24
                t_ld.bend(nt, 2, 0)
                t_ld.note(nt, nd, 2, pitch, vel)
                if bend_end:
                    for k in range(1, 5):
                        t_ld.bend(nt + (nd * k) // 5, 2, (bend_end * k) // 4)
                    t_ld.bend(nt + nd + 10, 2, 0)

    # Final D minor resolve chord
    end_t = 16 * B
    t_dr.note(end_t, S, 9, 49, 112)
    t_dr.note(end_t, S, 9, 36, 120)
    t_bs.note(end_t, 2 * Q, 1, 38, 115)
    for n in (50, 57, 62, 65, 69):
        t_ep.note(end_t, 3 * Q, 0, n, 100)
    t_st.note(end_t, 3 * Q, 3, 74, 88)

    write_smf(path, [t0, t_ep, t_bs, t_ld, t_st, t_dr], ppqn=Q)


def make_baroque(path):
    Q = 480
    E = Q // 2
    S = Q // 4

    t0 = Track("OPL2 Baroque Prelude")
    t0.tempo(0, 108)

    t1 = Track("Harpsichord RH")
    t1.prog(0, 0, 6)    # Harpsichord
    t1.cc(0, 0, 7, 106)

    t2 = Track("Harpsichord LH")
    t2.prog(0, 1, 6)    # Harpsichord
    t2.cc(0, 1, 7, 100)

    t3 = Track("Cello Continuo")
    t3.prog(0, 2, 42)   # Cello
    t3.cc(0, 2, 7, 90)

    # Broken-chord baroque prelude progression in C major (16 bars)
    prog = [
        (48, 52, 55, 60, 64),  # C
        (48, 50, 57, 62, 65),  # Dm7/C
        (47, 50, 55, 62, 65),  # G7/B
        (48, 52, 55, 60, 64),  # C
        (48, 52, 57, 64, 69),  # Am/C
        (48, 50, 54, 57, 62),  # D7/C
        (47, 50, 55, 62, 67),  # G/B
        (47, 48, 52, 55, 60),  # Cmaj7/B
        (45, 48, 52, 55, 60),  # Am7
        (42, 48, 50, 57, 62),  # D7/F#
        (43, 47, 50, 55, 59),  # G
        (43, 46, 52, 55, 61),  # Gdim7 / A7b9
        (41, 45, 50, 57, 62),  # Dm/F
        (41, 44, 50, 53, 59),  # G7b9/F
        (43, 48, 52, 55, 60),  # C/G
        (43, 47, 50, 53, 59),  # G7
    ]

    for i, (n0, n1, n2, n3, n4) in enumerate(prog):
        bt = i * 4 * Q
        if i == 14:
            t0.tempo(bt, 96)
        elif i == 15:
            t0.tempo(bt, 84)
        # Cello holds bass note for the whole bar
        t3.note(bt, 4 * Q - 40, 2, n0 - 12, 88)
        # Classic broken arpeggio pattern repeated twice per bar
        for half in range(2):
            ht = bt + half * 2 * Q
            t2.note(ht, 2 * Q - 30, 1, n0, 92)
            t2.note(ht + S, 2 * Q - S - 30, 1, n1, 86)
            pattern = [n2, n3, n4, n2, n3, n4]
            for k, p in enumerate(pattern):
                t1.note(ht + (k + 2) * S, S - 10, 0, p, 94 if k in (0, 3) else 82)

    # Final C major cadence
    end_t = len(prog) * 4 * Q
    t0.tempo(end_t, 72)
    t3.note(end_t, 4 * Q, 2, 36, 98)
    for k, n in enumerate((48, 52, 55, 60, 64, 67)):
        t1.note(end_t + k * 45, 4 * Q - k * 45, 0, n, 102)

    write_smf(path, [t0, t1, t2, t3], ppqn=Q)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(outdir, exist_ok=True)
    p1 = os.path.join(outdir, "OPLGROOVE.MID")
    p2 = os.path.join(outdir, "BAROQUE.MID")
    make_oplgroove(p1)
    make_baroque(p2)
    print(f"Wrote {p1} ({os.path.getsize(p1)} B), {p2} ({os.path.getsize(p2)} B)")


if __name__ == "__main__":
    main()
