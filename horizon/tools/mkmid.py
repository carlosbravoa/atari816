#!/usr/bin/env python3
"""Generate demo Standard MIDI Files (SMF Type 1) for Horizon's OPL2 MIDI player.

  mkmid.py [DIR]             OPLGROOVE.MID and BAROQUE.MID in DIR (the Desktop test's songs):
    OPLGROOVE.MID  - 5-track 80s FM synth-funk showcase (E-Piano, FM Bass, Synth Brass/Lead
                     with pitch bend, Strings, GM Drums with hi-hat choke & sustain pedal)
    BAROQUE.MID    - 3-track Harpsichord / Piano baroque counterpoint with ritardando
  mkmid.py --song NAME FILE  (0.27) one of the card's /Music songs (the Makefile's):
    prelude        - PRELUDE.MID, J. S. Bach, Prelude in C major BWV 846
    elise          - ELISE.MID, L. van Beethoven, Fur Elise WoO 59
    entertainer    - ENTERTNR.MID, S. Joplin, The Entertainer
    horizon        - THEME.MID, "Horizon" (tools/mkmod.py's tune) for the OPL2
The songs are written here note by note; the output is the same bytes on every run. The
MIDI tests (tests/midrun.py, tests/midwav.py) use Track and write_smf.
"""
import math
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


# ---------------------------------------------------------------------------- the card's songs
# (0.27) /Music's demo songs for the OPL2 (made by the Makefile: mkmid.py --song NAME FILE).
# Every note is written here: J. S. Bach (1685-1750), L. van Beethoven (1770-1827) and
# S. Joplin (1868-1917) from their scores as remembered, in our own arrangements (the
# compositions are in the public domain); "Horizon" is the tune of tools/mkmod.py's module.

NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pitch(name):
    """'C4' = 60, 'F#3', 'Bb2' (MIDI octave numbers: C4 is middle C)"""
    n = NOTE_PC[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        n += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return n + 12 * (int(rest) + 1)


def line(tr, ch, t0, unit, text, vel=96, legato=1.0, accent=None):
    """lay 'NOTE:len' tokens from tick t0 (len in units; 'r:len' a rest, '|' ignored, a
    note 'C4+E4:len' a chord); returns the tick after the last token"""
    t = t0
    for tok in text.split():
        if tok == "|":
            continue
        n, d = tok.split(":")
        d = float(d) * unit
        if n != "r":
            for m in n.split("+"):
                v = vel if accent is None else accent(t, vel)
                tr.note(t, max(1, int(d * legato)), ch, pitch(m), v)
        t += int(d)
    return t


def make_prelude(path):
    """J. S. Bach, Prelude in C major BWV 846 (The Well-Tempered Clavier I, 1722): the 35 bars
    of broken chords on the piano, the two lower notes of each half bar held as written; strings
    join softly over the dominant pedal from bar 24 and hold the last chords; a ritardando into
    the end."""
    Q = 480
    S = Q // 4
    t0 = Track("Prelude in C major, BWV 846 (J. S. Bach)")
    t0.tempo(0, 76)
    pno = Track("Piano")
    pno.prog(0, 0, 0)
    pno.cc(0, 0, 7, 127)
    st = Track("Strings")
    st.prog(0, 1, 48)
    st.cc(0, 1, 7, 96)
    bars = """C4 E4 G4 C5 E5 | C4 D4 A4 D5 F5 | B3 D4 G4 D5 F5 | C4 E4 G4 C5 E5 |
        C4 E4 A4 E5 A5 | C4 D4 F#4 A4 D5 | B3 D4 G4 D5 G5 | B3 C4 E4 G4 C5 |
        A3 C4 E4 G4 C5 | D3 A3 D4 F#4 C5 | G3 B3 D4 G4 B4 | G3 Bb3 E4 G4 C#5 |
        F3 A3 D4 A4 D5 | F3 Ab3 D4 F4 B4 | E3 G3 C4 G4 C5 | E3 F3 A3 C4 F4 |
        D3 F3 A3 C4 F4 | G2 D3 G3 B3 F4 | C3 E3 G3 C4 E4 | C3 G3 Bb3 C4 E4 |
        F2 F3 A3 C4 E4 | F#2 C3 A3 C4 Eb4 | Ab2 F3 B3 C4 D4 | G2 F3 G3 B3 D4 |
        G2 E3 G3 C4 E4 | G2 D3 G3 C4 F4 | G2 D3 G3 B3 F4 | G2 Eb3 A3 C4 F#4 |
        G2 E3 G3 C4 G4 | G2 D3 G3 C4 F4 | G2 D3 G3 B3 F4 | C2 C3 G3 Bb3 E4"""
    bars = [[pitch(n) for n in b.split()] for b in bars.split("|")]
    B = 4 * Q
    for i, (a, b, c, d, e) in enumerate(bars):
        bt = i * B
        for h in range(2):
            ht = bt + h * 2 * Q
            pno.note(ht, 2 * Q - 20, 0, a, 96)
            pno.note(ht + S, 2 * Q - S - 20, 0, b, 92)
            for k, n in enumerate((c, d, e, c, d, e)):
                pno.note(ht + (k + 2) * S, S - 12, 0, n, 110 if k == 0 else 102 - 3 * (k % 3))
        if i >= 23:                                  # bar 24: strings on the bass, softly
            st.note(bt, B - 30, 1, a + 12, 60 if i < 31 else 70)
            if i >= 27:
                st.note(bt, B - 30, 1, c + 12, 52)
    # bars 33-34 (the coda's figures over the C pedal) and the last chord
    bt = len(bars) * B
    for k, (lo, mid, fig) in enumerate((("C2", "C3", "F3 A3 C4 F4 C4 A3 C4 A3 F3 A3 F3 D3 F3 D3"),
                                         ("C2", "B2", "G4 B4 D5 F5 D5 B4 D5 B4 G4 B4 D4 F4 E4 D4"))):
        b0 = bt + k * B
        pno.note(b0, B - 20, 0, pitch(lo), 98)
        pno.note(b0 + S, B - S - 20, 0, pitch(mid), 92)
        for j, n in enumerate(fig.split()):
            pno.note(b0 + (j + 2) * S, S - 12, 0, pitch(n), 106 if j % 4 == 0 else 98)
        st.note(b0, B - 30, 1, pitch("C3"), 66)
        st.note(b0, B - 30, 1, pitch("G3") if k == 0 else pitch("F3"), 54)
    end = bt + 2 * B
    for n, v in (("C2", 100), ("C3", 96), ("E4", 98), ("G4", 98), ("C5", 106)):
        pno.note(end, 6 * Q - 60, 0, pitch(n), v)
    for n in ("C3", "G3", "E4"):
        st.note(end, 6 * Q - 60, 1, pitch(n), 64)
    for i, bpm in enumerate((70, 63)):               # the ritardando over the coda
        t0.tempo(bt + i * B, bpm)
    t0.tempo(end, 52)
    write_smf(path, [t0, pno, st], ppqn=Q)


def make_elise(path):
    """L. van Beethoven, Fur Elise (Bagatelle in A minor WoO 59, 1810): its theme twice (the
    piano, then the FM electric piano), the C-major episode with soft strings, a turn of the
    E / D# figure, the theme again on the piano and a ritardando. The left hand's broken chords
    ring with the sustain pedal, changed every bar."""
    Q = 480
    U = Q // 4                                        # a sixteenth; a 3/8 bar is 6
    t0 = Track("Fur Elise, WoO 59 (L. van Beethoven)")
    t0.tempo(0, 63)                                   # a quarter: an eighth at 126
    rh = Track("Right hand")
    rh.prog(0, 0, 0)
    rh.cc(0, 0, 7, 127)
    lh = Track("Left hand")
    lh.prog(0, 1, 0)
    lh.cc(0, 1, 7, 116)
    st = Track("Strings")
    st.prog(0, 2, 48)
    st.cc(0, 2, 7, 92)
    R = {1: "E5:1 D#5:1 E5:1 B4:1 D5:1 C5:1", 2: "A4:3 C4:1 E4:1 A4:1", 3: "B4:3 E4:1 G#4:1 B4:1",
         4: "C5:3 E4:1 E5:1 D#5:1", 7: "B4:3 E4:1 C5:1 B4:1", "8a": "A4:4 E5:1 D#5:1",
         "8b": "A4:3 B4:1 C5:1 D5:1", 9: "E5:3 G4:1 F5:1 E5:1", 10: "D5:3 F4:1 E5:1 D5:1",
         11: "C5:3 E4:1 D5:1 C5:1", 12: "B4:3 E4:1 E5:1 D#5:1", 13: "E5:1 D#5:1 E5:1 D#5:1 E5:1 D#5:1"}
    R[5], R[6] = R[1], R[2]
    L = {2: "A2 E3 A3", 3: "E2 E3 G#3", 4: "A2 E3 A3", 6: "A2 E3 A3", 7: "E2 E3 G#3", "8a": "A2 E3 A3",
         "8b": "A2 E3 A3", 9: "C3 G3 C4", 10: "G2 G3 B3", 11: "A2 E3 A3", 12: "E2 E3 G#3"}
    STR = {9: "C4+E4+G4:6", 10: "B3+D4+G4:6", 11: "A3+C4+E4:6", 12: "G#3+B3+E4:6"}
    theme = [1, 2, 3, 4, 5, 6, 7]
    form = [(b, 0) for b in theme + ["8a"]] + [(b, 5) for b in theme + ["8b"]] + \
           [(b, 0) for b in (9, 10, 11, 12, 13)] + [(b, 0) for b in theme]
    t = line(rh, 0, 0, U, "E5:1 D#5:1", 92)           # the upbeat
    prog = 0
    for b, p in form:
        if p != prog:
            rh.prog(t, 0, p)
            prog = p
        line(rh, 0, t, U, R[b], 98 if p else 94, legato=0.92,
             accent=lambda tt, v, t=t: v + 6 if tt == t else v)
        if b in L:
            lh.cc(t, 1, 64, 127)
            for k, n in enumerate(L[b].split()):
                lh.note(t + k * U, U - 10, 1, pitch(n), 80 - 3 * k)
            lh.cc(t + 6 * U - 20, 1, 64, 0)
        if b in STR:
            line(st, 2, t, U, STR[b], 70, legato=0.97)
        t += 6 * U
    # the end: A over the A-minor chord, held two bars under the pedal
    lh.cc(t, 1, 64, 127)
    for k, n in enumerate(("A2", "E3", "A3", "C4", "E4")):
        lh.note(t + k * U, U, 1, pitch(n), 82 - 3 * k)
    rh.note(t, 12 * U - 30, 0, pitch("A4"), 92)
    st.note(t, 12 * U - 30, 2, pitch("A3"), 46)
    st.note(t, 12 * U - 30, 2, pitch("E4"), 42)
    lh.cc(t + 12 * U - 20, 1, 64, 0)
    t0.tempo(t - 12 * U, 56)
    t0.tempo(t - 6 * U, 50)
    t0.tempo(t, 42)
    write_smf(path, [t0, rh, lh, st], ppqn=Q)


def make_entertainer(path):
    """S. Joplin, The Entertainer (1902): its first strain twice, a stride left hand under
    the tune. First on the honky-tonk piano; the second time as a little band: the clarinet
    takes the tune, a tuba the bass, the piano the chords, brushes-like drums on channel 10."""
    Q = 480
    U = Q // 4                                        # a sixteenth; a 2/4 bar is 8
    B = 8 * U
    t0 = Track("The Entertainer (S. Joplin)")
    t0.tempo(0, 76)
    mel = Track("Tune")
    mel.prog(0, 0, 3)
    mel.cc(0, 0, 7, 122)
    pno = Track("Piano, left hand")
    pno.prog(0, 1, 0)
    pno.cc(0, 1, 7, 112)
    tuba = Track("Tuba")
    tuba.prog(0, 2, 58)
    tuba.cc(0, 2, 7, 118)
    dr = Track("Drums")
    dr.cc(0, 9, 7, 108)
    tune = """E5:1 C6:2 E5:1 C6:2 E5:1 C6:5 r:1 C6:1 D6:1 D#6:1 | E6:1 C6:1 D6:1 E6:2 B5:1 D6:2 |
        C6:4 r:2 D5:1 D#5:1 | E5:1 C6:2 E5:1 C6:2 E5:1 C6:5 r:1 A5:1 G5:1 F#5:1 |
        A5:1 C6:1 E6:3 D6:1 C6:1 A5:1 | D6:6 D5:1 D#5:1 | E5:1 C6:2 E5:1 C6:2 E5:1 C6:5
        r:1 C6:1 D6:1 D#6:1 | E6:1 C6:1 D6:1 E6:2 B5:1 D6:2 | C6:4 r:1 C6:1 D6:1 E6:1 |
        C6:1 D6:1 E6:2 C6:1 D6:1 C6:1 E6:1 | C6:1 D6:1 E6:2 C6:1 D6:1 C6:1 E6:1 |
        C6:1 D6:1 E6:2 B5:2 D6:2 |"""
    harm = "C C | C C | C G7 | C C | C C | C D7 | D7 D7 | G7 G7 | C C | C C | C G7 | C C | C7 C7 | F F | C G7 | C C"
    harm = [h.split() for h in harm.split("|")]
    BASS = {"C": ("C2", "G2"), "G7": ("G2", "D2"), "D7": ("D2", "A2"), "F": ("F2", "C2"), "C7": ("C2", "G2")}
    CHORD = {"C": "E3 G3 C4", "G7": "F3 B3 D4", "D7": "F#3 C4 D4", "F": "F3 A3 C4", "C7": "E3 Bb3 C4"}
    t = line(mel, 0, 0, U, "D5:1 D#5:1", 90)          # the upbeat
    for rnd in range(2):
        start = t
        if rnd == 1:
            mel.prog(t - 2 * U, 0, 71)                # the clarinet (from the upbeat)
            dr.note(t, 2 * U, 9, 49, 84)
        t = line(mel, 0, t, U, tune, 96 if rnd == 0 else 100, legato=0.9,
                 accent=lambda tt, v, s0=start: v + 8 if (tt - s0) % B == 0 else v)
        t = line(mel, 0, t, U, "C6:6 D5:1 D#5:1" if rnd == 0 else "C6:4 r:4", 96)
        for i, (h1, h2) in enumerate(harm):
            bt = start + i * B
            for half, h in enumerate((h1, h2)):
                ht = bt + half * 4 * U
                bass = pitch(BASS[h][half])
                if rnd == 0:
                    pno.note(ht, 2 * U - 20, 1, bass, 82)
                else:
                    tuba.note(ht, 2 * U - 20, 2, bass, 90)
                for n in CHORD[h].split():
                    pno.note(ht + 2 * U, U + U // 2, 1, pitch(n), 62)
                if rnd == 1:
                    dr.note(ht, U, 9, 36 if half == 0 else 38, 76 if half == 0 else 54)
                    dr.note(ht + 2 * U, U, 9, 42, 48)
    # the end: C, all together, a crash
    for n in ("C4", "E4", "G4"):
        pno.note(t, 4 * U, 1, pitch(n), 74)
    pno.note(t, 4 * U, 1, pitch("C3"), 74)
    tuba.note(t, 4 * U, 2, pitch("C2"), 96)
    mel.note(t, 4 * U, 0, pitch("C6"), 104)
    dr.note(t, 2 * U, 9, 49, 96)
    dr.note(t, U, 9, 36, 90)
    t0.tempo(t - B, 70)
    t0.tempo(t, 60)
    write_smf(path, [t0, mel, pno, tuba, dr], ppqn=Q)


def make_horizon(path):
    """"Horizon", the tune of the card's HORIZON.MOD (tools/mkmod.py: its melodies, chords, bass
    lines and drum grooves, row for row: a row is a sixteenth) arranged for the OPL2: a square
    lead with vibrato and slides made of pitch bend, a synth bass that dives at the end, an
    electric piano's stabs in the A part, a warm pad swelling with expression (CC 11) in the B
    part and the intro, a vibraphone for the bells, the GM drums on channel 10. Intro, A, B,
    the slower break, A, B, the outro with its ritardando: 1:23 as the module."""
    Q = 480
    R = Q // 4                                        # a row
    LEAD, BASS, KEYS, BELL, DR = 0, 1, 2, 3, 9
    t0 = Track("Horizon (OPL2)")
    lead = Track("Lead")
    lead.prog(0, LEAD, 80)
    lead.cc(0, LEAD, 7, 108)
    bass = Track("Bass")
    bass.prog(0, BASS, 38)
    bass.cc(0, BASS, 7, 122)
    keys = Track("Keys and pad")
    keys.prog(0, KEYS, 89)
    keys.cc(0, KEYS, 7, 100)
    bell = Track("Bells")
    bell.prog(0, BELL, 11)
    bell.cc(0, BELL, 7, 118)
    dr = Track("Drums")
    dr.cc(0, DR, 7, 116)
    PT = {"C-": 0, "C#": 1, "D-": 2, "D#": 3, "E-": 4, "F-": 5, "F#": 6, "G-": 7, "G#": 8, "A-": 9, "A#": 10, "B-": 11}

    def pt(name, octave_up):
        return PT[name[:2]] + 12 * (int(name[2]) + octave_up)

    def vibrato(tr, ch, t, n_rows, depth=420):
        for k in range(n_rows * 2):                   # 5.5 Hz at 132 BPM: a cycle in 1.6 rows
            tr.bend(t + k * R // 2, ch, int(depth * math.sin(k * 2 * math.pi / 3.3)))
        tr.bend(t + n_rows * R, ch, 0)

    def melody(tr, ch, t, text, vel=100, vib=True):
        """mkmod's 'NOTE:rows' lines: d = half a row late, p = slid into (a bend from a
        whole tone below: the bend's range is 2 semitones), vibrato on notes of 6 rows or more"""
        for tok in text.split():
            if tok == "|":
                continue
            n, d = tok.split(":")
            flags = "".join(c for c in d if c.isalpha())
            d = int(d.rstrip("dp"))
            if n != ".":
                at = t + (R // 2 if "d" in flags else 0)
                if "p" in flags:
                    tr.bend(at, ch, -8192)
                    for k in range(1, 7):
                        tr.bend(at + k * R // 2, ch, -8192 + 8192 * k // 6)
                tr.note(at, d * R - 30, ch, pt(n, 3), vel)
                v0 = 4 if "p" in flags else 2           # (after the slide)
                if vib and d >= v0 + 4:
                    vibrato(tr, ch, at + v0 * R, d - v0)
            t += d * R
        return t

    def drums(t, groove):
        for i, c in enumerate(groove):
            r = t + i * R
            hit = {"K": (36, 104), "S": (38, 96), "g": (38, 44), "G": (38, 64), "h": (42, 46),
                   "H": (42, 80), "o": (46, 70)}.get(c)
            if hit:
                dr.note(r, R, DR, *hit)
            elif c == "f":
                dr.note(r + R // 2, R, DR, 38, 90)
            elif c == "r":
                dr.note(r, R // 2, DR, 42, 66)
                dr.note(r + R // 2, R // 2, DR, 42, 58)

    def root(chord):
        return PT[chord.rstrip("m") + ("-" if len(chord.rstrip("m")) == 1 else "")], chord.endswith("m")

    def triad(chord):
        r, minor = root(chord)
        return sorted(53 + (pc - 53) % 12 for pc in (r, r + (3 if minor else 4), r + 7))

    def bassline(t, chord, style):
        r = root(chord)[0] + 36
        hits = [(i, {"L": r, "H": r + 12, "5": r + 7}[c]) for i, c in enumerate(style) if c != "."]
        for k, (i, n) in enumerate(hits):
            nxt = hits[k + 1][0] if k + 1 < len(hits) else len(style)
            bass.note(t + i * R, min(nxt - i, 6) * R - 25, BASS, n, 100 if style[i] == "L" else 88)

    def stabs(t, chord):
        for r in (2, 6, 10, 14):
            for n in triad(chord):
                keys.note(t + r * R, 2 * R - 30, KEYS, n, 70)

    def pad(t, chord, swell=None, rows=16):
        if swell:
            v0, n = swell
            for k in range(n + 1):
                keys.cc(t + k * R, KEYS, 11, v0 + (127 - v0) * k // n)
        for n in triad(chord):
            keys.note(t, rows * R - 30, KEYS, n - 12 if n >= 60 else n, 72)

    GA = "K.h.S.h.K.h.S.hh"
    GB = "K.hKS.h.K.hKS.o."

    def intro(t):
        t0.tempo(t, 132)
        keys.prog(t, KEYS, 89)
        for bar, c in enumerate(["C", "Am", "F", "G"]):
            pad(t + bar * 16 * R, c, (30, 7))
        melody(bell, BELL, t, "C-3:4 E-3:4 G-3:8 | A-3:4 G-3:4 E-3:8 | F-3:4 E-3:4 C-3:8 | D-3:4", 92, vib=False)
        lead.bend(t + 52 * R, LEAD, -8192)            # the swoop into the A part
        lead.note(t + 52 * R, 12 * R - 30, LEAD, pt("G-2", 3), 90)
        for k in range(1, 23):
            lead.bend(t + 52 * R + k * R // 2, LEAD, -8192 + 8191 * k // 22)
        drums(t, "..h...h...h...h." * 2 + "K.h...h.K.h...h.")
        drums(t + 48 * R, "K.h.S.h.gGgGSSSf")
        bassline(t + 32 * R, "F", "L.......L.....L.")
        bassline(t + 48 * R, "G", "L.......L.L.H.H.")
        return t + 64 * R

    def a_part(t, tune, last):
        t0.tempo(t, 132)
        keys.prog(t, KEYS, 5)
        keys.cc(t, KEYS, 11, 127)
        lead.bend(t, LEAD, 0)
        for bar, c in enumerate(["C", "Am", "F", "G"]):
            bassline(t + bar * 16 * R, c, "L.H.L.H.L.H.L.H.")
            stabs(t + bar * 16 * R, c)
            drums(t + bar * 16 * R, GA if bar < 3 else last)
        melody(lead, LEAD, t, tune)
        return t + 64 * R

    def b_part(t, chords, tune, last):
        keys.prog(t, KEYS, 89)
        for bar, c in enumerate(chords):
            bassline(t + bar * 16 * R, c, "L..L..H.L.5.L.H.")
            pad(t + bar * 16 * R, c, (60, 4))
            drums(t + bar * 16 * R, GB if bar < 3 else last)
        melody(lead, LEAD, t, tune)
        return t + 64 * R

    def a1(t):
        return a_part(t, "G-2:4 C-3:2 E-3:2 D-3:4 C-3:4 | E-3:6 D-3:2 C-3:4 A-2:4 |"
                         " A-2:2 C-3:2 F-3:4 E-3:2 D-3:2 C-3:4 | D-3:10 .:2 B-2:2 D-3:2", GA)

    def a2(t):
        return a_part(t, "G-2:4 C-3:2 E-3:2 G-3:4 E-3:4 | A-3:6 G-3:2 E-3:4 C-3:4 |"
                         " F-3:4 E-3:2 D-3:2 C-3:2 A-2:2 C-3:4 | D-3:6 E-3:2 D-3:4 B-2:4", "K.h.S.h.K.SgS.SS")

    def b1(t):
        return b_part(t, ["F", "G", "Em", "Am"],
                      "C-3:2 F-3:2 A-3:4 G-3:2 F-3:2 E-3:4d | D-3:2 G-3:2 B-3:4 A-3:2 G-3:2 D-3:4 |"
                      " E-3:2 G-3:2 B-3:6 A-3:2 G-3:4 | A-3:8 E-3:8p", GB)

    def b2(t):
        return b_part(t, ["F", "G", "C", "C"],
                      "C-3:2 F-3:2 A-3:4 G-3:2 F-3:2 A-3:4 | B-3:4 A-3:2 G-3:2 D-3:4 G-3:4 |"
                      " E-3:4 G-3:2 E-3:2 C-3:4 D-3:2 E-3:2 | C-3:12 .:4", "K.h.S.h.KhSgSSSf")

    def brk(t):                                       # speed 8: 99 BPM; 56 rows (D00 at 55)
        t0.tempo(t, 99)
        keys.prog(t, KEYS, 89)
        for bar, c in enumerate(["Am", "F", "C", "G"]):
            pad(t + bar * 16 * R, c, (40, 6), rows=16 if bar < 3 else 8)
        melody(bell, BELL, t, "E-3:4 A-3:4 G-3:4 E-3:4 | F-3:4 A-3:4 C-3:8 |"
               " E-3:4 G-3:4 C-3:4 E-3:4 | D-3:4 B-2:4", 92, vib=False)
        for row, n in ((0, "A-"), (16, "F-"), (32, "C-"), (48, "G-")):
            bass.note(t + row * R, (16 if row < 48 else 8) * R - 30, BASS, PT[n] + 36, 96)
        drums(t, "....h.......h...")
        drums(t + 16 * R, "K...h.......h..." * 2)
        drums(t + 48 * R, "K.rrgGSS")
        return t + 56 * R

    def outro(t):
        t0.tempo(t, 132)
        keys.prog(t, KEYS, 5)
        keys.cc(t, KEYS, 11, 127)
        for bar, c in enumerate(["F", "G"]):
            bassline(t + bar * 16 * R, c, "L.H.L.H.L.H.L.H.")
            stabs(t + bar * 16 * R, c)
            drums(t + bar * 16 * R, GA if bar == 0 else "K.h.S.h.K.SgS.SS")
        melody(lead, LEAD, t, "A-2:2 C-3:2 F-3:4 E-3:2 D-3:2 C-3:4 | D-3:6 E-3:2 D-3:4 B-2:4")
        e = t + 32 * R
        lead.note(e, 31 * R, LEAD, pt("C-3", 3), 100)   # held, vibrato, fading
        vibrato(lead, LEAD, e + 2 * R, 29)
        for k in range(20):
            lead.cc(e + (12 + k) * R, LEAD, 11, 127 - 6 * k)
        keys.prog(e, KEYS, 89)
        pad(e, "C", rows=31)
        for k in range(20):
            keys.cc(e + (12 + k) * R, KEYS, 11, 127 - 6 * k)
        bass.note(e, 16 * R - 30, BASS, 36, 100)
        bass.note(e + 16 * R, 15 * R, BASS, 48, 96)      # the dive
        for k in range(12):
            bass.bend(e + (20 + k) * R, BASS, -8192 * (k + 1) // 12)
        bass.bend(e + 33 * R, BASS, 0)
        dr.note(e, R, DR, 36, 110)
        dr.note(e, 2 * R, DR, 49, 90)
        for row, bpm in ((32, 113), (40, 99), (48, 79), (56, 66)):
            t0.tempo(t + row * R, bpm)
        return t + 64 * R

    t = 0
    for part in (intro, a1, a2, b1, b2, brk, a1, a2, b1, b2, outro):
        t = part(t)
    for tr, ch in ((lead, LEAD), (keys, KEYS)):
        tr.cc(t, ch, 11, 127)
    write_smf(path, [t0, lead, bass, keys, bell, dr], ppqn=Q)


SONGS = {"prelude": make_prelude, "elise": make_elise, "entertainer": make_entertainer, "horizon": make_horizon}


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--song":
        if len(sys.argv) != 4 or sys.argv[2] not in SONGS:
            sys.exit(__doc__)
        SONGS[sys.argv[2]](sys.argv[3])
        print(f"{sys.argv[3]}: {os.path.getsize(sys.argv[3])} bytes")
        return
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(outdir, exist_ok=True)
    p1 = os.path.join(outdir, "OPLGROOVE.MID")
    p2 = os.path.join(outdir, "BAROQUE.MID")
    make_oplgroove(p1)
    make_baroque(p2)
    print(f"Wrote {p1} ({os.path.getsize(p1)} B), {p2} ({os.path.getsize(p2)} B)")


if __name__ == "__main__":
    main()
