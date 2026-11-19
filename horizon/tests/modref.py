#!/usr/bin/env python3
"""modref.py - independent reference ProTracker MOD player for the Atari816 music engine tests.

Written from the public description of the MOD format and of ProTracker 2.3's effects, plus the
shared conventions of the Atari816 music engine (how channels map to Lau voices, volumes, pan,
pitch, samples/loops/offsets, tick timing). It shares no code with the 65C816 replayer
(horizon MUSICD.PRG); the two are compared through emu816's Lau write log by modcheck.py.

Library:
    mod = load_mod(path_or_bytes)
    song = simulate(mod, max_ticks=None, mvol=64, sep=32)
    song.ticks[k].us, .order, .row, .chans[c].pitch, .vol_l ...   (see Tick / ChanOut)

CLI:
    python3 modref.py FILE.MOD [--ticks N] [--csv] [--mvol 64] [--sep 32]

Conventions followed (summary; the shared conventions file is the authority):
  * Channel c of an N-channel module plays on Lau voice 8-N+c; pan LRRL (c%4 in {0,3} = left).
  * amp = (vol*mvol)>>4, near = 128+2*sep, far = 256-near, VOL = min(255, (amp*gain)>>8).
  * Lau pitch = round(1210673.29 / period) (PAL Paula 3546894.6 Hz * 16384 / 48000).
  * Tick k starts at sum(round(2500000/BPM_j), j < k); speed/BPM changes act from the next tick.
  * Effect semantics: ProTracker 2.3 with the "PT 2.3 literal decisions" appendix.
"""

import sys
import argparse

# ---------------------------------------------------------------------------------------------
# Tables

# ProTracker period table: 16 finetunes (index 0..7 = finetune 0..+7, 8..15 = -8..-1), 36 notes
# each (C-1 .. B-3). Values as in the ProTracker 2.x replay routine (mt_PeriodTable).
PERIODS = [
    # finetune 0
    [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
     428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
     214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113],
    # finetune +1
    [850, 802, 757, 715, 674, 637, 601, 567, 535, 505, 477, 450,
     425, 401, 379, 357, 337, 318, 300, 284, 268, 253, 239, 225,
     213, 201, 189, 179, 169, 159, 150, 142, 134, 126, 119, 113],
    # finetune +2
    [844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474, 447,
     422, 398, 376, 355, 335, 316, 298, 282, 266, 251, 237, 224,
     211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118, 112],
    # finetune +3
    [838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470, 444,
     419, 395, 373, 352, 332, 314, 296, 280, 264, 249, 235, 222,
     209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118, 111],
    # finetune +4
    [832, 785, 741, 699, 660, 623, 588, 555, 524, 495, 467, 441,
     416, 392, 370, 350, 330, 312, 294, 278, 262, 247, 233, 220,
     208, 196, 185, 175, 165, 156, 147, 139, 131, 124, 117, 110],
    # finetune +5
    [826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463, 437,
     413, 390, 368, 347, 328, 309, 292, 276, 260, 245, 232, 219,
     206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116, 109],
    # finetune +6
    [820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460, 434,
     410, 387, 365, 345, 325, 307, 290, 274, 258, 244, 230, 217,
     205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115, 109],
    # finetune +7
    [814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457, 431,
     407, 384, 363, 342, 323, 305, 288, 272, 256, 242, 228, 216,
     204, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114, 108],
    # finetune -8
    [907, 856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480,
     453, 428, 404, 381, 360, 340, 320, 302, 285, 269, 254, 240,
     226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120],
    # finetune -7
    [900, 850, 802, 757, 715, 675, 636, 601, 567, 535, 505, 477,
     450, 425, 401, 379, 357, 337, 318, 300, 284, 268, 253, 238,
     225, 212, 200, 189, 179, 169, 159, 150, 142, 134, 126, 119],
    # finetune -6
    [894, 844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474,
     447, 422, 398, 376, 355, 335, 316, 298, 282, 266, 251, 237,
     223, 211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118],
    # finetune -5
    [887, 838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470,
     444, 419, 395, 373, 352, 332, 314, 296, 280, 264, 249, 235,
     222, 209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118],
    # finetune -4
    [881, 832, 785, 741, 699, 660, 623, 588, 555, 524, 494, 467,
     441, 416, 392, 370, 350, 330, 312, 294, 278, 262, 247, 233,
     220, 208, 196, 185, 175, 165, 156, 147, 139, 131, 123, 117],
    # finetune -3
    [875, 826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463,
     437, 413, 390, 368, 347, 328, 309, 292, 276, 260, 245, 232,
     219, 206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116],
    # finetune -2
    [868, 820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460,
     434, 410, 387, 365, 345, 325, 307, 290, 274, 258, 244, 230,
     217, 205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115],
    # finetune -1
    [862, 814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457,
     431, 407, 384, 363, 342, 323, 305, 288, 272, 256, 242, 228,
     216, 203, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114],
]

# ProTracker vibrato/tremolo sine table (32 entries, one half period, magnitude).
SINE = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
        255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24]

NOTE_NAMES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-']

PITCH_K = 1210673.29          # 3546894.6 Hz * 16384 / 48000
COPY_LIMIT = 2048             # largest per-channel copy buffer (bytes) for offsets inside loops


def note_period(name, finetune=0):
    """'C-2' -> period in the given finetune's table (octaves 1..3 as in ProTracker)."""
    n = NOTE_NAMES.index(name[:2].upper())
    octv = int(name[2])
    return PERIODS[finetune & 15][(octv - 1) * 12 + n]


def first_le_index(table, period):
    """Appendix rule: the FIRST entry of a (descending) table that is <= period; none -> 35."""
    for i, p in enumerate(table):
        if p <= period:
            return i
    return 35


def lau_pitch(period):
    """Conventions: Lau pitch = round(1210673.29 / period), period 0 -> 0 (clamped to 16 bits)."""
    if period <= 0:
        return 0
    period = min(period, 1023)                    # decision: periods above 1023 -> 1023
    return min(0xFFFF, int(PITCH_K / period + 0.5))


def lau_vols(vol, chan, mvol=64, sep=32):
    """Conventions: amp=(vol*mvol)>>4; near=128+2*sep, far=256-near; LRRL panning."""
    amp = (vol * mvol) >> 4
    near = 128 + 2 * sep
    far = 256 - near
    a = min(255, (amp * near) >> 8)
    b = min(255, (amp * far) >> 8)
    if chan % 4 in (0, 3):          # left channel
        return a, b
    return b, a


def signed_nibble(x):
    return x - 16 if x >= 8 else x


# ---------------------------------------------------------------------------------------------
# Module loading

class Sample:
    def __init__(self, num, name, length, finetune, volume, loopstart, looplen, data):
        self.num = num
        self.name = name
        self.length = length            # bytes
        self.finetune = finetune & 15   # table index 0..15
        self.volume = min(volume, 64)
        self.loopstart = loopstart      # bytes
        self.looplen = looplen          # bytes
        self.data = data

    @property
    def loops(self):
        # Conventions: loops when the repeat length > 1 word (> 2 bytes); a loop start at or
        # past the end of the sample cannot loop (decision: treated as one-shot).
        return self.looplen > 2 and self.loopstart < self.length

    @property
    def loopend(self):
        return min(self.loopstart + self.looplen, self.length)


class Module:
    def __init__(self):
        self.title = ''
        self.tag = ''
        self.nch = 4
        self.samples = [None]           # 1-based
        self.orders = []                # song (length = song length)
        self.restart = 0
        self.patterns = []              # [pattern][row][chan] = (smp, period, eff, prm)
        self.order_to_pattern = []      # order index -> index in self.patterns


TAGS4 = (b'M.K.', b'M!K!', b'M&K!', b'N.T.', b'FLT4', b'4CHN')
TAGS8 = (b'FLT8', b'OKTA', b'OCTA', b'CD81')


def _cell(b):
    smp = (b[0] & 0xF0) | (b[2] >> 4)
    per = ((b[0] & 0x0F) << 8) | b[1]
    return (smp, per, b[2] & 0x0F, b[3])


def load_mod(src):
    data = src if isinstance(src, (bytes, bytearray)) else open(src, 'rb').read()
    data = bytes(data)
    m = Module()
    tag = data[1080:1084] if len(data) >= 1084 else b''
    nsmp = 31
    flt8 = False
    if tag in TAGS4:
        m.nch = 4
    elif tag in TAGS8:
        m.nch = 8
        flt8 = tag == b'FLT8'
    elif len(tag) == 4 and tag[1:] == b'CHN' and 0x31 <= tag[0] <= 0x38:
        m.nch = tag[0] - 0x30
    else:
        nsmp = 15                       # old Ultimate SoundTracker format: no tag, 15 samples
        tag = b''
        m.nch = 4
    m.tag = tag.decode('latin-1')
    m.title = data[0:20].split(b'\0')[0].decode('latin-1')
    hdr = 20 + 30 * nsmp
    m.samples = [None]
    for i in range(nsmp):
        o = 20 + 30 * i
        name = data[o:o + 22].split(b'\0')[0].decode('latin-1')
        length = 2 * ((data[o + 22] << 8) | data[o + 23])
        ft = data[o + 24] & 15
        vol = data[o + 25]
        ls = 2 * ((data[o + 26] << 8) | data[o + 27])
        ll = 2 * ((data[o + 28] << 8) | data[o + 29])
        m.samples.append(Sample(i + 1, name, length, ft, vol, ls, ll, b''))
    songlen = max(1, min(128, data[hdr]))
    m.restart = data[hdr + 1]
    allorders = list(data[hdr + 2:hdr + 2 + 128])
    m.orders = allorders[:songlen]
    pdata = hdr + 2 + 128 + (4 if nsmp == 31 else 0)
    if flt8:
        # FLT8 (Startrekker): orders name 4-channel patterns; the 8-channel pattern for order
        # entry e is 4-channel pattern e&~1 (channels 0-3) beside e|1 (channels 4-7); the file
        # holds (highest order value | 1) + 1 four-channel blocks of 1024 bytes.
        npairs = max(allorders) // 2 + 1
        rowsz = 16
        for p in range(npairs):
            pat = []
            a = pdata + (2 * p) * 1024
            b = pdata + (2 * p + 1) * 1024
            for r in range(64):
                left = [_cell(_get(data, a + r * rowsz + 4 * c, 4)) for c in range(4)]
                right = [_cell(_get(data, b + r * rowsz + 4 * c, 4)) for c in range(4)]
                pat.append(left + right)
            m.patterns.append(pat)
        m.order_to_pattern = [e // 2 for e in m.orders]
        sdata = pdata + npairs * 2 * 1024
    else:
        npat = max(allorders) + 1
        rowsz = 4 * m.nch
        for p in range(npat):
            base = pdata + p * 64 * rowsz
            pat = [[_cell(_get(data, base + r * rowsz + 4 * c, 4)) for c in range(m.nch)]
                   for r in range(64)]
            m.patterns.append(pat)
        m.order_to_pattern = list(m.orders)
        sdata = pdata + npat * 64 * rowsz
    for s in m.samples[1:]:
        s.data = _get(data, sdata, s.length)
        sdata += s.length
    return m


def _get(data, off, n):
    b = data[off:off + n]
    return b + bytes(n - len(b))       # truncated files: pad with zeros


# ---------------------------------------------------------------------------------------------
# Lau register image of a note start

def lau_regs(s, o):
    """Conventions: what the engine programs for sample s started at byte offset o.

    Returns None when the note is silent (sample 0 / length 0, or a one-shot with o >= L): the
    engine then stops the voice (KEYOFF) instead of a KEYON.  Otherwise a tuple
    (kind, start_offset, LEN, LOOP, CTRL) where kind is 'sample' (START = sample + start_offset)
    or 'copy' (START = the channel's copy buffer, address unknown, start_offset None).
    """
    if s is None or s.length == 0:
        return None
    if s.loops:
        ls, le = s.loopstart, s.loopend
        ll = le - ls
        # o >= loop end ("length" for the o test is the loop end), or an inside-loop offset whose
        # copy would not fit in the buffer: played as o = loopstart.
        if o >= le or (o > ls and (le - o) + ll > COPY_LIMIT):
            return ('sample', ls, ll, 0, 1)
        if o <= ls:
            return ('sample', o, le - o, ls - o, 1)
        return ('copy', None, (le - o) + ll, le - o, 1)
    if o >= s.length:
        return None
    return ('sample', o, s.length - o, 0, 0)


# ---------------------------------------------------------------------------------------------
# Player

class ChanOut:
    """Per channel, per tick: what the hardware (Lau) is told."""
    __slots__ = ('trig', 'stop', 'smp', 'off', 'period', 'pitch', 'vol', 'vol_l', 'vol_r',
                 'regs', 'active')

    def __init__(self, **kw):
        for k, v in kw.items():
            setattr(self, k, v)


class Tick:
    __slots__ = ('index', 'us', 'dur', 'order', 'row', 'rowtick', 'speed', 'bpm', 'chans')


class Song:
    def __init__(self):
        self.ticks = []
        self.end_reason = ''
        self.length_us = 0


class Chan:
    def __init__(self):
        self.smp = 0            # channel's sample number (0 = none yet)
        self.vol = 0            # channel volume 0..64
        self.ft = 0             # finetune table index 0..15
        self.period = 0         # internal (base) period
        self.target = 0         # tone portamento target (0 = none)
        self.pspeed = 0         # tone portamento speed (memory)
        self.gliss = False
        self.vspeed = self.vdepth = self.vpos = self.vwave = 0
        self.tspeed = self.tdepth = self.tpos = self.twave = 0
        self.offmem = 0         # 9xx memory (high byte of the offset)
        self.looprow = 0        # E6x
        self.loopcnt = 0
        self.cur_smp = 0        # sample of the last note start
        self.cur_off = 0        # its offset
        self.regs = None        # its Lau register image
        self.active = False     # a voice was started and not stopped since
        self.pending = False    # EDx: a note start waiting for tick x
        # per tick outputs
        self.trig = False
        self.stop = False
        self.out_period = 0
        self.out_vol = 0


class _RowCtl:
    def __init__(self):
        self.jump = False        # a B or D was seen
        self.next_order = None   # Bxx
        self.brk_row = 0
        self.loop_to = None      # E6x jump
        self.pdelay = None       # EEx
        self.speed = None
        self.bpm = None
        self.stop = False        # F00


class Player:
    def __init__(self, mod, mvol=64, sep=32):
        self.m = mod
        self.mvol, self.sep = mvol, sep
        self.ch = [Chan() for _ in range(mod.nch)]
        self.speed = 6
        self.bpm = 125

    # -- note handling --------------------------------------------------------------------------

    def _sample(self, n):
        if 0 < n < len(self.m.samples):
            return self.m.samples[n]
        return None

    def _start(self, ch, off):
        """A note start (trigger): KEYON with the register image, or KEYOFF if silent."""
        ch.cur_smp, ch.cur_off = ch.smp, off
        regs = lau_regs(self._sample(ch.smp), off)
        if regs is None:
            # Appendix: sample 0 / length 0 / one-shot with o >= L -> no KEYON, voice stopped.
            ch.stop, ch.trig, ch.active, ch.regs = True, False, False, None
        else:
            ch.trig, ch.stop, ch.active, ch.regs = True, False, True, regs

    def _note(self, ch, cell, delayed):
        """Tick-0 note handling: sample number, E5x, period, trigger (deferred for EDx)."""
        smp, per, eff, prm = cell
        x, y = prm >> 4, prm & 15
        s = self._sample(smp)
        if s is not None:
            # Sample number (with or without a note): channel sample, volume, finetune.
            ch.smp, ch.vol, ch.ft = smp, s.volume, s.finetune
        if eff == 0xE and x == 5:
            ch.ft = y                                     # E5x: finetune for this row's note
        if eff == 9 and prm:
            ch.offmem = prm                               # 9xx memory (also without a note)
        if not per:
            return
        # Appendix: index = first entry of the finetune-0 table <= the pattern period.
        p = PERIODS[ch.ft][first_le_index(PERIODS[0], per)]
        if eff in (3, 5):
            ch.target = p                                 # tone portamento: no trigger
            return
        ch.period = p
        if not ch.vwave & 4:
            ch.vpos = 0                                   # new note: vibrato/tremolo reset
        if not ch.twave & 4:
            ch.tpos = 0
        off = ch.offmem * 256 if eff == 9 else 0
        if delayed:
            ch.pending = True                             # EDx: KEYON at tick x (offset 0)
        else:
            self._start(ch, off)

    # -- continuous effects -------------------------------------------------------------------

    def _porta(self, ch):
        if ch.target and ch.period:
            if ch.period < ch.target:
                ch.period = min(ch.target, ch.period + ch.pspeed)
            else:
                ch.period = max(ch.target, ch.period - ch.pspeed)
            if ch.period == ch.target:
                ch.target = 0
        ch.out_period = ch.period
        if ch.gliss and ch.period:
            # Appendix: glissando -> first entry of the channel's table <= the slid period.
            t = PERIODS[ch.ft]
            ch.out_period = t[first_le_index(t, ch.period)]

    @staticmethod
    def _wave(wave, pos):
        idx = pos & 31
        w = wave & 3
        if w == 1:                                        # ramp down
            return idx * 8 if pos < 32 else 255 - idx * 8
        if w == 2:                                        # square
            return 255
        return SINE[idx]                                  # sine (and 3 = random -> sine)

    def _vibrato(self, ch):
        if not ch.period:
            return
        d = (self._wave(ch.vwave, ch.vpos) * ch.vdepth) >> 7
        ch.out_period = ch.period + d if ch.vpos < 32 else ch.period - d
        ch.vpos = (ch.vpos + ch.vspeed) & 63

    def _tremolo(self, ch):
        d = (self._wave(ch.twave, ch.tpos) * ch.tdepth) >> 6
        v = ch.vol + d if ch.tpos < 32 else ch.vol - d
        ch.out_vol = max(0, min(64, v))
        ch.tpos = (ch.tpos + ch.tspeed) & 63

    @staticmethod
    def _volslide(ch, prm):
        x, y = prm >> 4, prm & 15
        if x:
            ch.vol = min(64, ch.vol + x)
        else:
            ch.vol = max(0, ch.vol - y)

    @staticmethod
    def _fine_e(ch, x, y):
        """E1x/E2x/EAx/EBx (tick-0-only E commands; also re-run on EE repeats' tick 0)."""
        if x == 1 and ch.period:
            ch.period = max(113, ch.period - y)
        elif x == 2 and ch.period:
            ch.period = min(856, ch.period + y)
        elif x == 0xA:
            ch.vol = min(64, ch.vol + y)
        elif x == 0xB:
            ch.vol = max(0, ch.vol - y)

    # -- ticks --------------------------------------------------------------------------------

    def _tick0(self, ch, cell, row, ctl):
        smp, per, eff, prm = cell
        x, y = prm >> 4, prm & 15
        ch.pending = False
        delayed = eff == 0xE and x == 0xD and y > 0
        self._note(ch, cell, delayed)
        if eff == 3 and prm:
            ch.pspeed = prm
        elif eff == 4:
            if x:
                ch.vspeed = x
            if y:
                ch.vdepth = y
        elif eff == 7:
            if x:
                ch.tspeed = x
            if y:
                ch.tdepth = y
        elif eff == 0xB:                                  # B: next order xx, row 0
            ctl.jump, ctl.next_order, ctl.brk_row = True, prm, 0
        elif eff == 0xC:
            ch.vol = min(prm, 64)
        elif eff == 0xD:                                  # D: break row x*10+y (> 63 -> 0)
            r = x * 10 + y
            ctl.jump, ctl.brk_row = True, (r if r <= 63 else 0)
        elif eff == 0xE:
            if x in (1, 2, 0xA, 0xB):
                self._fine_e(ch, x, y)
            elif x == 3:
                ch.gliss = y != 0
            elif x == 4:
                ch.vwave = y
            elif x == 6:                                  # pattern loop (per channel, PT)
                if y == 0:
                    ch.looprow = row
                else:
                    if ch.loopcnt == 0:
                        ch.loopcnt = y
                        ctl.loop_to = ch.looprow
                    else:
                        ch.loopcnt -= 1
                        if ch.loopcnt:
                            ctl.loop_to = ch.looprow
            elif x == 7:
                ch.twave = y
            elif x == 9 and y and not per:
                # Appendix: E9x retriggers when tick % x == 0, except on tick 0 of a row with a
                # note (that note started anyway).
                self._start(ch, 0)                        # decision: offset 0, current sample
            elif x == 0xC and y == 0:
                ch.vol = 0                                # EC0: cut at tick 0
            elif x == 0xE:
                ctl.pdelay = y                            # last channel wins
        elif eff == 0xF:
            if prm == 0:
                ctl.stop = True
            elif prm < 32:
                ctl.speed = prm
            else:
                ctl.bpm = prm
        ch.out_period = ch.period
        ch.out_vol = ch.vol

    def _tickn(self, ch, cell, c, first_block):
        """A tick > 0 of the row (c = the PT tick counter, t % speed; on pattern-delay repeats
        c is 0 at the start of each repeat and runs the same path, as PT does)."""
        smp, per, eff, prm = cell
        x, y = prm >> 4, prm & 15
        ch.out_period = None
        ch.out_vol = None
        if eff == 0 and prm:
            k = c % 3                                     # arpeggio
            if k and ch.period:
                t = PERIODS[ch.ft]
                i = first_le_index(t, ch.period)          # appendix: base = current period
                ch.out_period = t[min(35, i + (x if k == 1 else y))]
        elif eff == 1:
            if ch.period:
                ch.period = max(113, ch.period - prm)
        elif eff == 2:
            if ch.period:
                ch.period = min(856, ch.period + prm)
        elif eff == 3:
            self._porta(ch)
        elif eff == 4:
            self._vibrato(ch)
        elif eff == 5:
            self._porta(ch)
            self._volslide(ch, prm)
        elif eff == 6:
            self._vibrato(ch)
            self._volslide(ch, prm)
        elif eff == 7:
            self._tremolo(ch)
        elif eff == 0xA:
            self._volslide(ch, prm)
        elif eff == 0xE:
            if x in (1, 2, 0xA, 0xB) and c == 0:
                self._fine_e(ch, x, y)                    # EE repeat: PT re-runs them
            elif x == 9 and y and c % y == 0 and not (c == 0 and per):
                self._start(ch, 0)                        # decision: offset 0, current sample
            elif x == 0xC and c == y:
                ch.vol = 0
            elif x == 0xD and c == y and first_block and ch.pending:
                ch.pending = False
                self._start(ch, 0)                        # delayed KEYON, offset 0
        if ch.out_period is None:
            ch.out_period = ch.period
        if ch.out_vol is None:
            ch.out_vol = ch.vol

    def _emit(self, song, us, dur, order, row, rt):
        t = Tick()
        t.index = len(song.ticks)
        t.us, t.dur, t.order, t.row, t.rowtick = us, dur, order, row, rt
        t.speed, t.bpm = self.speed, self.bpm
        outs = []
        for c, ch in enumerate(self.ch):
            vl, vr = lau_vols(ch.out_vol, c, self.mvol, self.sep)
            outs.append(ChanOut(trig=ch.trig, stop=ch.stop, smp=ch.cur_smp, off=ch.cur_off,
                                period=ch.out_period, pitch=lau_pitch(ch.out_period),
                                vol=ch.out_vol, vol_l=vl, vol_r=vr, regs=ch.regs,
                                active=ch.active))
            ch.trig = ch.stop = False
        t.chans = outs
        song.ticks.append(t)

    def run(self, max_ticks=None):
        m = self.m
        song = Song()
        order, row = 0, 0
        played = set()
        us = 0
        limit = max_ticks if max_ticks is not None else 500000
        while True:
            played.add((order, row))
            cells = m.patterns[m.order_to_pattern[order]][row]
            ctl = _RowCtl()
            for c, ch in enumerate(self.ch):
                self._tick0(ch, cells[c], row, ctl)
            dur = int(2500000 / self.bpm + 0.5)
            self._emit(song, us, dur, order, row, 0)
            us += dur
            # Speed/BPM changes take effect from the next tick.
            if ctl.speed:
                self.speed = ctl.speed
            if ctl.bpm:
                self.bpm = ctl.bpm
            if ctl.stop:
                song.end_reason = 'F00 at order %d row %d' % (order, row)
                break
            if len(song.ticks) >= limit:
                song.end_reason = 'tick limit'
                break
            rowlen = self.speed * ((ctl.pdelay or 0) + 1)
            for t in range(1, rowlen):
                for c, ch in enumerate(self.ch):
                    self._tickn(ch, cells[c], t % self.speed, t < self.speed)
                dur = int(2500000 / self.bpm + 0.5)
                self._emit(song, us, dur, order, row, t)
                us += dur
                if len(song.ticks) >= limit:
                    break
            if len(song.ticks) >= limit:
                song.end_reason = 'tick limit'
                break
            # Next position.
            if ctl.loop_to is not None:
                # E6x jump back: those rows become "unplayed" again (appendix).
                for r in range(ctl.loop_to, row + 1):
                    played.discard((order, r))
                row = ctl.loop_to
            elif ctl.jump:
                order = ctl.next_order if ctl.next_order is not None else order + 1
                row = ctl.brk_row
            else:
                row += 1
                if row >= 64:
                    row = 0
                    order += 1
            if order >= len(m.orders):
                # Past the last order: the restart position if < song length, else order 0.
                order = m.restart if m.restart < len(m.orders) else 0
            if (order, row) in played:
                song.end_reason = 'row order %d row %d already played' % (order, row)
                break
        song.length_us = us
        return song


def simulate(mod, max_ticks=None, mvol=64, sep=32):
    return Player(mod, mvol, sep).run(max_ticks)


# ---------------------------------------------------------------------------------------------
# CLI

def _regs_str(r):
    if r is None:
        return '-'
    kind, so, ln, lp, ctrl = r
    return '%s%s/%d/%d/%d' % (kind[0], '' if so is None else '+%d' % so, ln, lp, ctrl)


def main(argv=None):
    ap = argparse.ArgumentParser(description='Reference ProTracker MOD player (tick table).')
    ap.add_argument('mod')
    ap.add_argument('--ticks', type=int, default=None, help='stop after N ticks')
    ap.add_argument('--csv', action='store_true')
    ap.add_argument('--mvol', type=int, default=64)
    ap.add_argument('--sep', type=int, default=32)
    a = ap.parse_args(argv)
    m = load_mod(a.mod)
    song = simulate(m, a.ticks, a.mvol, a.sep)
    out = sys.stdout
    if a.csv:
        hdr = ['tick', 'us', 'order', 'row', 'rowtick']
        for c in range(m.nch):
            hdr += ['c%d_%s' % (c, f) for f in ('trig', 'stop', 'smp', 'off', 'period', 'pitch',
                                                 'vol', 'voll', 'volr', 'regs')]
        out.write(','.join(hdr) + '\n')
        for t in song.ticks:
            row = [t.index, t.us, t.order, t.row, t.rowtick]
            for o in t.chans:
                row += [int(o.trig), int(o.stop), o.smp, o.off, o.period, o.pitch, o.vol,
                        o.vol_l, o.vol_r, _regs_str(o.regs)]
            out.write(','.join(str(v) for v in row) + '\n')
    else:
        out.write('%s: "%s" tag %s, %d channels, %d orders, %d patterns, restart %d\n' % (
            a.mod, m.title, m.tag or '(15 samples)', m.nch, len(m.orders), len(m.patterns),
            m.restart))
        for t in song.ticks:
            parts = []
            for o in t.chans:
                flag = 'K' if o.trig else ('X' if o.stop else ' ')
                parts.append('%s%02d %5d %5d v%2d %3d/%3d' % (flag, o.smp, o.off, o.pitch,
                                                              o.vol, o.vol_l, o.vol_r))
            out.write('%5d %9d %02d:%02d.%-2d| %s\n' % (t.index, t.us, t.order, t.row,
                                                       t.rowtick, ' | '.join(parts)))
        out.write('end: %s; %d ticks, %.3f s\n' % (song.end_reason, len(song.ticks),
                                                   song.length_us / 1e6))
    return 0


if __name__ == '__main__':
    sys.exit(main())
