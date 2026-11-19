#!/usr/bin/env python3
"""mkmodtests.py OUTDIR - writes the music engine's test modules (deterministic) and a manifest.

Each module is short and exercises one group of ProTracker effects.  Every sample a module uses
is first started plainly (no offset) on row 0 of its first pattern (where the channel count
allows; modcheck.py learns a sample's address from its first plain start anyway), so the checker
can learn each sample's START address in Lau's log.

OUTDIR/tests.txt lists: file, channels, expected duration (s, from modref.py), coverage.
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import modref  # noqa: E402  (only for the manifest durations)


# ---------------------------------------------------------------------------------------------
# Synthetic samples: (length bytes, loopstart, looplen, finetune -8..7, volume, wave)
# Distinct lengths so samples are identifiable.  looplen 0 = one-shot.
BANK = {
    1: ('square1200', 1200, 0, 0, 0, 64, 'square'),
    2: ('saw2000L', 2000, 400, 1200, 0, 64, 'saw'),
    3: ('sine512L', 512, 0, 512, 0, 50, 'sine'),
    4: ('tri300', 300, 0, 0, 0, 40, 'tri'),
    5: ('sq3000L-3', 3000, 1024, 1536, -3, 64, 'square'),
    6: ('saw2600+5', 2600, 0, 0, 5, 60, 'saw'),
    7: ('sine800L+7', 800, 200, 400, 7, 64, 'sine'),
    8: ('empty', 0, 0, 0, 0, 64, 'none'),
    9: ('big5000L', 5000, 1000, 3500, 0, 64, 'saw'),
}


def sample_data(length, wave, seed):
    out = bytearray()
    per = 32 + 8 * seed
    for i in range(length):
        ph = (i % per) / per
        if wave == 'square':
            v = 80 if ph < 0.5 else -80
        elif wave == 'saw':
            v = int(-100 + 200 * ph)
        elif wave == 'tri':
            v = int(-100 + 400 * ph) if ph < 0.5 else int(300 - 400 * ph)
        else:
            v = int(100 * math.sin(2 * math.pi * ph))
        out.append(v & 0xFF)
    return bytes(out)


# ---------------------------------------------------------------------------------------------
# Pattern building

class Pat:
    def __init__(self, nch):
        self.nch = nch
        self.rows = [[(0, 0, 0, 0)] * nch for _ in range(64)]

    def c(self, row, ch, note=None, smp=0, fx=None):
        """note 'C-2' (or None), sample number, effect '3 08' style string 'EFF' (3 hex)."""
        per = modref.note_period(note) if note else 0
        eff = prm = 0
        if fx:
            eff = int(fx[0], 16)
            prm = int(fx[1:], 16)
        self.rows[row][ch] = (smp, per, eff, prm)
        return self


def cell_bytes(smp, per, eff, prm):
    return bytes([(smp & 0xF0) | (per >> 8), per & 0xFF, ((smp & 15) << 4) | eff, prm])


def build_mod(nch, orders, pats, used, tag=None, restart=0, title='test', fmt31=True):
    """Return MOD bytes.  pats: list of Pat (nch channels); orders: pattern numbers.
    tag None -> M.K. / xCHN by nch; 'FLT8' -> 8 channels stored as 4-channel pattern pairs."""
    if tag is None:
        tag = 'M.K.' if nch == 4 else '%dCHN' % nch
    nsmp = 31 if fmt31 else 15
    out = bytearray(title.encode()[:20].ljust(20, b'\0'))
    datas = []
    for i in range(1, nsmp + 1):
        if i in used:
            name, ln, ls, ll, ft, vol, wave = BANK[i]
        else:
            name, ln, ls, ll, ft, vol, wave = ('', 0, 0, 0, 0, 0, 'none')
        out += name.encode()[:22].ljust(22, b'\0')
        rep = ll if ll else 2                              # one-shot: repeat length 1 word
        out += bytes([ln // 2 >> 8, ln // 2 & 255, ft & 15, vol,
                      ls // 2 >> 8, ls // 2 & 255, rep // 2 >> 8, rep // 2 & 255])
        datas.append(sample_data(ln, wave, i))
    if tag == 'FLT8':
        ords = [2 * o for o in orders]
    else:
        ords = list(orders)
    out += bytes([len(ords), restart]) + bytes(ords).ljust(128, b'\0')
    if fmt31:
        out += tag.encode()
    for p in pats:
        if tag == 'FLT8':
            for half in (0, 4):
                for r in range(64):
                    for c in range(4):
                        out += cell_bytes(*p.rows[r][half + c])
        else:
            for r in range(64):
                for c in range(nch):
                    out += cell_bytes(*p.rows[r][c])
    for d in datas:
        out += d
    return bytes(out)


# ---------------------------------------------------------------------------------------------
# The modules.  Each returns (filename, nch, bytes, coverage).

def first_row(p, notes):
    """Row 0: plain starts, one per channel: notes = [(note, smp), ...]."""
    for c, (n, s) in enumerate(notes):
        p.c(0, c, n, s)


def t01_arp():
    p = Pat(4)
    first_row(p, [('C-2', 1), ('E-2', 2), ('G-2', 3), ('C-3', 4)])
    p.c(1, 0, 'C-2', 1, '037').c(1, 1, None, 0, '047').c(1, 2, 'A-3', 3, '0F0').c(1, 3, None, 0, '0C7')
    p.c(2, 0, None, 0, '000').c(2, 1, None, 0, '037').c(2, 2, 'B-3', 3, '0FF').c(2, 3, None, 0, '010')
    p.c(3, 0, None, 0, '105').c(3, 1, None, 0, '047')            # slide off the table ...
    p.c(4, 0, None, 0, '037').c(4, 2, 'C-1', 3, '0CC')          # ... arpeggio on it
    p.c(5, 0, None, 0, 'F09').c(5, 1, None, 0, '037').c(5, 2, None, 0, '0CC')  # speed 9: t%3
    p.c(6, 0, None, 0, '037').c(6, 3, 'C-3', 4, '012')
    p.c(7, 0, None, 0, 'D00')
    return 't01arp.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 4}), \
        'arpeggio 0xy: held notes, clamp at B-3, on an off-table (slid) period, speed 9'


def t02_slides():
    p = Pat(4)
    first_row(p, [('C-2', 2), ('A-1', 3), ('B-3', 1), ('C-1', 5)])
    p.c(1, 0, None, 0, '110').c(1, 1, None, 0, '220').c(1, 2, None, 0, '1FF').c(1, 3, None, 0, '2FF')
    p.c(2, 0, None, 0, '100').c(2, 1, None, 0, '200').c(2, 2, None, 0, '2FF').c(2, 3, None, 0, '1FF')
    p.c(3, 0, None, 0, 'E1F').c(3, 1, None, 0, 'E2F').c(3, 2, None, 0, 'E2F').c(3, 3, None, 0, 'E1F')
    p.c(4, 0, None, 0, 'E13').c(4, 1, None, 0, 'E23').c(4, 2, None, 0, 'E1F').c(4, 3, None, 0, 'E2F')
    p.c(5, 0, None, 0, '103').c(5, 1, None, 0, '203').c(5, 2, 'G-2', 1, 'E21').c(5, 3, 'G-2', 5, 'E11')
    p.c(6, 0, None, 0, 'D00')
    return 't02slide.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 5}, tag='FLT4'), \
        'slides 1xx/2xx incl. clamps 113/856 and no memory (100/200); fine slides E1x/E2x ' \
        'incl. clamps; note+E1/E2 on one row (FLT4 tag)'


def t03_porta():
    p = Pat(4)
    first_row(p, [('C-2', 2), ('C-3', 3), ('G-1', 5), ('C-2', 1)])
    p.c(1, 0, 'E-2', 0, '308').c(1, 1, 'C-2', 0, '310').c(1, 2, 'G-2', 5, '340').c(1, 3, None, 0, 'E31')
    p.c(2, 0, None, 0, '300').c(2, 1, None, 0, '300').c(2, 2, 'C-1', 0, '300').c(2, 3, 'C-3', 0, '303')
    p.c(3, 0, None, 0, '300').c(3, 1, None, 0, '502').c(3, 2, None, 0, 'A04').c(3, 3, None, 0, '300')
    p.c(4, 0, 'G-2', 2).c(4, 1, None, 0, '510').c(4, 2, 'C-2', 0, '310').c(4, 3, None, 0, '300')
    p.c(5, 0, None, 0, '300').c(5, 1, None, 0, '500').c(5, 2, None, 0, '300').c(5, 3, None, 0, 'E30')
    p.c(6, 0, 'C-2', 0, '320').c(6, 2, None, 0, '300').c(6, 3, 'G-2', 0, '302')
    p.c(7, 0, None, 0, '300').c(7, 3, None, 0, '300')
    p.c(8, 0, None, 0, 'D00')
    return 't03porta.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 5}), \
        'tone portamento 3xx incl. memory (300), target reached/cleared, note+sample number ' \
        '(volume reset, no trigger), glissando E31/E30, 5xy'


def t04_vibrato():
    p = Pat(4)
    p.c(0, 0, 'C-2', 2).c(0, 1, 'G-2', 3, 'E41').c(0, 2, 'C-2', 5, 'E42').c(0, 3, 'E-2', 1, 'E43')
    p.c(1, 0, None, 0, '448').c(1, 1, None, 0, '46F').c(1, 2, None, 0, '438').c(1, 3, None, 0, '48C')
    p.c(2, 0, None, 0, '400').c(2, 1, None, 0, '404').c(2, 2, None, 0, '450').c(2, 3, None, 0, '400')
    p.c(3, 0, 'D-2', 0, '400').c(3, 1, None, 0, 'E45').c(3, 2, None, 0, '602').c(3, 3, 'E-2', 1, '400')
    p.c(4, 0, None, 0, '604').c(4, 1, 'A-2', 0, '400').c(4, 2, None, 0, '601').c(4, 3, None, 0, '000')
    p.c(5, 0, None, 0, '4F2').c(5, 1, None, 0, '400').c(5, 2, None, 0, 'E46').c(5, 3, None, 0, '43F')
    p.c(6, 0, None, 0, '400').c(6, 1, None, 0, '400').c(6, 2, 'C-2', 0, '400').c(6, 3, None, 0, '400')
    p.c(7, 0, None, 0, 'D00')
    return 't04vib.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 5}), \
        'vibrato 4xy incl. per-nibble memory, waveforms E40-E43, no-reset E45/E46, new note ' \
        'reset, 6xy'


def t05_tremolo():
    p = Pat(4)
    first_row(p, [('C-2', 2), ('G-2', 3), ('C-2', 5), ('E-2', 1)])
    p.c(1, 0, None, 0, '748').c(1, 1, None, 0, '74F').c(1, 2, None, 0, 'E71').c(1, 3, None, 0, 'E72')
    p.c(2, 0, None, 0, '700').c(2, 1, None, 0, '708').c(2, 2, None, 0, '768').c(2, 3, None, 0, '786')
    p.c(3, 0, None, 0, 'C20').c(3, 1, None, 0, '700').c(3, 2, None, 0, '700').c(3, 3, None, 0, 'E75')
    p.c(4, 0, None, 0, '788').c(4, 1, 'C-2', 3, '700').c(4, 2, 'C-2', 0, '700').c(4, 3, None, 0, '700')
    p.c(5, 0, None, 0, '700').c(5, 1, None, 0, '700').c(5, 2, None, 0, 'A02').c(5, 3, 'E-2', 0, '748')
    p.c(6, 0, None, 0, 'D00')
    return 't05trem.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 5}), \
        'tremolo 7xy incl. memory, clamps 0/64, waveforms E71/E72, no-reset E75, new note reset'


def t06_offset():
    p = Pat(4)
    first_row(p, [('C-2', 1), ('C-2', 2), ('C-2', 5), ('C-2', 9)])
    p.c(1, 0, 'C-2', 1, '902').c(1, 1, 'C-2', 2, '901').c(1, 2, 'C-2', 5, '908').c(1, 3, 'C-2', 9, '904')
    p.c(2, 0, 'C-2', 1, '905').c(2, 1, 'C-2', 2, '906').c(2, 2, 'C-2', 5, '904').c(2, 3, 'C-2', 9, '903')
    p.c(3, 0, 'C-2', 1, '900').c(3, 1, 'C-2', 2, '907').c(3, 2, 'C-2', 5, '90A').c(3, 3, 'C-2', 9, '910')
    p.c(4, 0, 'C-2', 1).c(4, 1, None, 0, '903').c(4, 2, 'D-2', 0, '900').c(4, 3, 'C-3', 1, '904')
    p.c(5, 0, 'C-2', 8).c(5, 1, 'C-2', 0, '900').c(5, 3, 'E-2', 9)
    p.c(6, 0, 'C-2', 1).c(6, 0, None, 0, 'D00')
    return 't06offs.mod', 4, build_mod(4, [0], [p], {1, 2, 5, 8, 9}), \
        'sample offset 9xx: one-shot inside / beyond its length (KEYOFF), memory (900, and ' \
        '9xx without a note), looped: o <= loopstart, inside the loop (copy), = loopstart, ' \
        '>= loop end, inside but copy > 2048 bytes (as loopstart); empty sample (KEYOFF)'


def t07_volume():
    p = Pat(4)
    first_row(p, [('C-2', 2), ('C-2', 3), ('C-2', 4), ('C-2', 5)])
    p.c(1, 0, None, 0, 'A04').c(1, 1, None, 0, 'A20').c(1, 2, None, 0, 'C10').c(1, 3, None, 0, 'C7F')
    p.c(2, 0, None, 0, 'A0F').c(2, 1, None, 0, 'A0F').c(2, 2, None, 0, 'A35').c(2, 3, None, 0, 'C00')
    p.c(3, 0, None, 0, 'C30').c(3, 1, None, 0, 'C20').c(3, 2, None, 0, 'EAF').c(3, 3, None, 0, 'EA8')
    p.c(4, 0, None, 0, 'EB4').c(4, 1, None, 0, 'EA0').c(4, 2, None, 0, 'EAF').c(4, 3, None, 0, 'EBF')
    p.c(5, 0, None, 2).c(5, 1, None, 3, 'A01').c(5, 2, None, 4, 'C05').c(5, 3, None, 0, 'EBF')
    p.c(6, 0, None, 0, 'A00').c(6, 1, 'E-2', 0).c(6, 2, None, 0, 'A10').c(6, 3, None, 5)
    p.c(7, 0, None, 0, 'D00')
    return 't07vol.mod', 4, build_mod(4, [0], [p], {2, 3, 4, 5}), \
        'volume slide Axy incl. clamps and x-wins, set volume Cxx (C7F -> 64), fine volume ' \
        'EAx/EBx incl. clamps, sample number without a note (volume reset), note without sample'


def t08_finetune():
    p = Pat(4)
    first_row(p, [('C-2', 5), ('C-2', 6), ('C-2', 7), ('C-2', 1)])
    p.c(1, 0, 'E-2').c(1, 1, 'G-2', 6).c(1, 2, 'B-3', 7).c(1, 3, 'C-2', 0, 'E58')
    p.c(2, 0, 'C-2', 0, 'E57').c(2, 1, 'C-2', 1).c(2, 2, 'C-1', 7, 'E5F').c(2, 3, 'D-2')
    p.c(3, 0, 'C-2', 5).c(3, 1, 'A-2', 6).c(3, 2, 'E-2', 7).c(3, 3, None, 1)
    p.c(4, 0, 'C-3', 0, 'E50').c(4, 3, 'C-2')
    p.c(5, 0, None, 0, 'D00')
    return 't08fine.mod', 4, build_mod(4, [0], [p], {1, 5, 6, 7}), \
        'sample finetunes (-3, +5, +7), E5x on a note row, finetune kept for notes without ' \
        'sample number, reset by a sample number'


def t09_retrig():
    p = Pat(4)
    first_row(p, [('C-2', 1), ('C-2', 2), ('C-2', 3), ('C-2', 4)])
    p.c(1, 0, 'C-2', 1, 'E92').c(1, 1, None, 0, 'E93').c(1, 2, None, 0, 'EC3').c(1, 3, 'E-2', 4, 'ED2')
    p.c(2, 0, None, 0, 'E91').c(2, 1, None, 0, 'E90').c(2, 2, 'C-2', 3, 'EC0').c(2, 3, 'G-2', 0, 'ED6')
    p.c(3, 0, None, 0, 'E95').c(3, 1, 'C-2', 2, 'ED0').c(3, 2, None, 3, 'ECA').c(3, 3, 'A-2', 2, 'ED3')
    p.c(4, 0, 'C-3', 1, 'ED1').c(4, 1, None, 0, 'EC1').c(4, 2, None, 0, 'E96').c(4, 3, 'E-2', 0, 'ED5')
    p.c(5, 0, None, 0, 'D00')
    return 't09retr.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 4}), \
        'retrigger E9x (with/without note: tick 0 retrigger on note-less rows, E90), note cut ' \
        'ECx (EC0, x >= speed: never), note delay EDx (ED0, sample change, x >= speed: no ' \
        'trigger)'


def t10_patloop():
    p = Pat(4)
    p.c(0, 0, 'C-2', 1).c(0, 1, 'C-2', 2).c(0, 2, 'G-2', 3).c(0, 3, 'E-2', 4, 'F03')
    p.c(1, 0, None, 0, 'E60').c(1, 1, 'D-2', 2)
    p.c(2, 1, 'E-2', 2)
    p.c(3, 0, None, 0, 'E62').c(3, 1, None, 0, 'A02')
    p.c(4, 2, None, 0, 'E60').c(4, 3, 'C-3', 4)
    p.c(5, 3, 'D-3', 4)
    p.c(6, 2, None, 0, 'E61').c(6, 0, 'G-2', 1)
    p.c(7, 0, None, 0, 'D00')
    return 't10loop.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 4}), \
        'pattern loop E60/E6x on two channels (x2 and x1), song end not triggered by the loop'


def t11_patdelay():
    p = Pat(4)
    p.c(0, 0, 'C-2', 2, 'F04').c(0, 1, 'C-2', 3).c(0, 2, 'E-2', 5).c(0, 3, 'G-2', 1, 'C30')
    p.c(1, 0, None, 0, 'EE2').c(1, 1, None, 0, '102').c(1, 2, None, 0, 'A02').c(1, 3, None, 0, '448')
    p.c(2, 0, 'C-2', 1).c(2, 1, None, 0, 'EE1').c(2, 2, 'G-2', 0, '304').c(2, 3, None, 0, '748')
    p.c(3, 0, None, 0, 'EB4').c(3, 1, None, 0, 'EE1').c(3, 2, None, 0, 'E12').c(3, 3, None, 0, '037')
    p.c(4, 0, None, 0, 'EE0').c(4, 1, None, 0, '202').c(4, 2, None, 0, '300').c(4, 3, None, 0, '400')
    p.c(5, 0, None, 0, 'D00')
    return 't11pdel.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 5}), \
        'pattern delay EEx with slides, volume slide, vibrato, tremolo, porta, arpeggio, and ' \
        'E1x/EBx re-run on each repeat; note on a delayed row'


def t12_speed():
    p = Pat(4)
    p.c(0, 0, 'C-2', 1, 'F03').c(0, 1, 'C-2', 2).c(0, 2, 'C-2', 3, '444').c(0, 3, 'E-2', 4)
    p.c(1, 0, None, 0, 'F20').c(1, 1, None, 0, 'A01').c(1, 2, None, 0, '400')
    p.c(2, 0, None, 0, 'F50').c(2, 1, None, 0, 'A01').c(2, 2, None, 0, '400')
    p.c(3, 0, None, 0, 'F09').c(3, 3, None, 0, 'F96').c(3, 2, None, 0, '400')
    p.c(4, 0, None, 0, 'FFF').c(4, 2, None, 0, '400').c(4, 1, None, 0, 'A02')
    p.c(5, 0, None, 0, 'F01').c(5, 2, None, 0, '400')
    p.c(6, 1, 'C-2', 2).c(6, 3, 'G-2', 4)
    p.c(7, 0, None, 0, 'F06').c(7, 3, None, 0, 'F7D').c(7, 2, None, 0, '400')
    p.c(8, 0, None, 0, 'F1F').c(8, 2, None, 0, '400')
    p.c(9, 0, None, 0, 'F03').c(9, 2, None, 0, '400').c(9, 3, None, 0, 'F80')
    p.c(10, 0, None, 0, 'D00').c(10, 2, None, 0, '400')
    return 't12speed.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 4}), \
        'speed/tempo Fxx: speeds 3, 9, 1, 6, 31; BPM 32, 80, 150, 255, 125, 128; speed and ' \
        'BPM on one row'


def t13_jumps():
    p0, p1, p2, p3, p4 = (Pat(4) for _ in range(5))
    p0.c(0, 0, 'C-2', 1).c(0, 1, 'E-2', 2).c(0, 2, 'G-2', 3).c(0, 3, 'C-3', 4)
    p0.c(1, 0, None, 0, 'B02')
    p1.c(0, 0, 'C-3', 1)                                   # never played
    p1.c(5, 2, 'C-2', 3)
    p1.c(6, 3, None, 0, 'B00')                             # back to played row: song end
    p2.c(0, 0, 'E-2', 1)
    p2.c(1, 1, None, 0, 'D12')                             # BCD: row 12
    p3.c(12, 0, 'G-2', 1)
    p3.c(13, 0, None, 0, 'B04').c(13, 1, None, 0, 'D02')   # B then D: order 4 row 2
    p4.c(2, 0, 'A-2', 1)
    p4.c(3, 0, None, 0, 'D03').c(3, 2, None, 0, 'B03')     # D then B: order 3 row 0
    p3.c(0, 1, 'D-2', 2)
    p3.c(1, 1, None, 0, 'D70')                             # 70 > 63: next order (4), row 0
    p4.c(0, 3, 'E-2', 4)
    p4.c(1, 0, None, 0, 'B01').c(1, 1, None, 0, 'D05')     # order 1 row 5
    return 't13jump.mod', 4, build_mod(4, [0, 1, 2, 3, 4], [p0, p1, p2, p3, p4], {1, 2, 3, 4}), \
        'position jump Bxx (skipping an order), pattern break Dxy (BCD row, > 63 -> 0), B and ' \
        'D on one row in both channel orders, song end by B jumping back'


def t14_runoff():
    p0, p1 = Pat(4), Pat(4)
    first_row(p0, [('C-2', 1), ('E-2', 2), ('G-2', 3), ('C-3', 4)])
    p0.c(3, 0, None, 0, 'D00')
    p1.c(0, 0, 'C-2', 1, 'F01')
    for r in range(4, 64, 8):
        p1.c(r, (r // 8) % 4, 'E-2', 1 + (r // 8) % 4)
    return 't14end.mod', 4, build_mod(4, [0, 1], [p0, p1], {1, 2, 3, 4}, tag='4CHN'), \
        'song end by running off the last pattern (speed 1, 64 rows), 4CHN tag'


def t15_f00():
    p = Pat(4)
    first_row(p, [('C-2', 1), ('E-2', 2), ('G-2', 3), ('C-3', 4)])
    p.c(1, 1, None, 0, 'A02')
    p.c(3, 2, None, 0, 'F00').c(3, 0, 'D-2', 1)
    p.c(4, 0, 'C-3', 1)                                    # never played
    return 't15f00.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 4}), 'song end by F00'


def t16_8chn():
    p = Pat(8)
    for c, s in enumerate([1, 2, 3, 4, 5, 6, 7, 3]):
        p.c(0, c, ['C-2', 'E-2', 'G-2', 'C-3', 'C-2', 'E-2', 'G-2', 'C-1'][c], s)
    p.c(1, 0, None, 0, 'A02').c(1, 1, None, 0, '104').c(1, 4, None, 0, 'C20').c(1, 5, None, 0, '448')
    p.c(1, 7, None, 0, '204').c(1, 6, None, 0, '037')
    p.c(2, 2, 'D-2', 3, '308').c(2, 3, None, 0, '744').c(2, 6, 'A-2', 7)
    p.c(3, 4, 'C-2', 5, '902').c(3, 0, 'E-2', 0).c(3, 7, None, 0, 'EC2')
    p.c(4, 1, None, 0, 'E93').c(4, 5, None, 0, '400')
    p.c(5, 0, None, 0, 'D00')
    return 't16ch8.mod', 8, build_mod(8, [0], [p], {1, 2, 3, 4, 5, 6, 7}), \
        '8 channels (8CHN): voices 0-7, pan LRRLLRRL, mixed effects'


def t17_6chn():
    p = Pat(6)
    for c, s in enumerate([1, 2, 3, 4, 5]):
        p.c(0, c, ['C-2', 'E-2', 'G-2', 'C-3', 'C-2'][c], s)
    p.c(1, 5, 'C-2')                                       # no sample yet: KEYOFF, no KEYON
    p.c(1, 0, None, 0, 'A02').c(1, 4, None, 0, '448').c(1, 2, None, 0, '204')
    p.c(2, 5, 'G-2', 6).c(2, 3, None, 0, '744')
    p.c(3, 5, 'C-2', 0, '901').c(3, 1, None, 0, 'C10')
    p.c(4, 0, None, 0, 'D00')
    return 't17ch6.mod', 6, build_mod(6, [0], [p], {1, 2, 3, 4, 5, 6}), \
        '6 channels (6CHN): voices 2-7, a note with no sample ever set (KEYOFF)'


def t18_15smp():
    p = Pat(4)
    first_row(p, [('C-2', 1), ('E-2', 2), ('G-2', 3), ('C-3', 4)])
    p.c(1, 0, None, 0, '037').c(1, 1, None, 0, '102').c(1, 2, None, 0, 'C20')
    p.c(2, 3, 'C-2', 4).c(2, 1, None, 0, '202')
    p.c(3, 0, None, 0, 'D00')
    return 't18old.mod', 4, build_mod(4, [0], [p], {1, 2, 3, 4}, restart=120, fmt31=False), \
        '15-sample (Soundtracker) format, no tag, restart byte 120'


def t19_flt8(tag='FLT8'):
    a, b = Pat(8), Pat(8)
    for c, s in enumerate([1, 2, 3, 4, 5, 6, 7, 1]):
        a.c(0, c, 'C-2', s)
    a.c(1, 6, None, 0, 'A04').c(1, 1, None, 0, '448')
    a.c(2, 5, 'G-2', 0).c(2, 0, None, 0, 'D00')
    b.c(0, 7, 'E-2', 1).c(0, 3, 'G-2', 4)
    b.c(1, 4, None, 0, 'C10')
    b.c(2, 0, None, 0, 'D00')
    return 't19flt8.mod', 8, build_mod(8, [0, 1], [a, b], {1, 2, 3, 4, 5, 6, 7}, tag=tag), \
        'FLT8 (Startrekker): 8 channels stored as pairs of 4-channel patterns'


ALL = [t01_arp, t02_slides, t03_porta, t04_vibrato, t05_tremolo, t06_offset, t07_volume,
       t08_finetune, t09_retrig, t10_patloop, t11_patdelay, t12_speed, t13_jumps, t14_runoff,
       t15_f00, t16_8chn, t17_6chn, t18_15smp, t19_flt8]


def generate():
    """Yield (name, nch, data, coverage) for every test module."""
    for f in ALL:
        yield f()


def main(argv):
    if len(argv) != 2:
        print('usage: mkmodtests.py OUTDIR', file=sys.stderr)
        return 2
    outdir = argv[1]
    os.makedirs(outdir, exist_ok=True)
    lines = ['# file channels seconds coverage']
    total = 0.0
    for name, nch, data, cov in generate():
        with open(os.path.join(outdir, name), 'wb') as f:
            f.write(data)
        song = modref.simulate(modref.load_mod(data))
        secs = song.length_us / 1e6
        total += secs
        lines.append('%s %d %.3f %s' % (name, nch, secs, cov))
    lines.append('# total %.3f s' % total)
    with open(os.path.join(outdir, 'tests.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
