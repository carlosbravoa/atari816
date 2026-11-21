#!/usr/bin/env python3
"""Generate user/opl_gm.inc: General MIDI OPL2 (YM3812) patch bank & tables.

Outputs:
  gm_mel[128 * 12]   - 128 General MIDI melodic 2-op FM patches
  gm_drm[47 * 12]    - 47 General MIDI percussion patches (MIDI notes 35..81)
  mid_fnum[128 * 2]  - 10-bit OPL2 F-Numbers for MIDI notes 0..127
  mid_blk[128]       - 3-bit OPL2 Block (octave) for MIDI notes 0..127
  mid_atten[64]      - Logarithmic MIDI gain (0..63) -> OPL2 TL attenuation (0..63)
  opl_mod_off[9]     - OPL2 modulator operator offsets for voices 0..8
  opl_car_off[9]     - OPL2 carrier operator offsets for voices 0..8

Patch layout (12 bytes):
  [0] mod $20  AM/VIB/EGT/KSR/MULT     [1] car $20  AM/VIB/EGT/KSR/MULT
  [2] mod $40  KSL/TL                  [3] car $40  KSL/TL
  [4] mod $60  AR/DR                   [5] car $60  AR/DR
  [6] mod $80  SL/RR                   [7] car $80  SL/RR
  [8] mod $E0  WS (0..3)               [9] car $E0  WS (0..3)
  [10]    $C0  FB (3:1) | CNT (0)      [11] note_off (signed transpose, or fixed drum note)
"""
import math
import os
import sys


def op20(mult, ksr=0, egt=0, vib=0, am=0):
    return ((am & 1) << 7) | ((vib & 1) << 6) | ((egt & 1) << 5) | ((ksr & 1) << 4) | (mult & 0x0F)


def op40(tl, ksl=0):
    return ((ksl & 3) << 6) | (tl & 0x3F)


def op60(ar, dr):
    return ((ar & 0x0F) << 4) | (dr & 0x0F)


def op80(sl, rr):
    return ((sl & 0x0F) << 4) | (rr & 0x0F)


def c0(fb, cnt=0):
    return ((fb & 7) << 1) | (cnt & 1)


def patch(m20, c20, m40, c40, m60, c60, m80, c80, me0=0, ce0=0, fb_cnt=0, note=0):
    return (
        m20 & 0xFF, c20 & 0xFF,
        m40 & 0xFF, c40 & 0xFF,
        m60 & 0xFF, c60 & 0xFF,
        m80 & 0xFF, c80 & 0xFF,
        me0 & 3, ce0 & 3,
        fb_cnt & 0x0F, note & 0xFF,
    )


# ---------------------------------------------------------------------------
# General MIDI Melodic Patches (0..127)
# Clean, original 2-operator YM3812 voice designs across all 16 GM families.
# ---------------------------------------------------------------------------
def build_gm_melodic():
    P = []

    # ---- 0..7: Piano ----
    # 0 Acoustic Grand Piano: crisp hammer attack, warm decaying body
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(22, 2), op40(4, 1),
                   op60(15, 5), op60(15, 2), op80(7, 6), op80(5, 6), 0, 0, c0(3, 0)))
    # 1 Bright Acoustic Piano: brighter modulator, faster shimmer
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(19, 2), op40(3, 1),
                   op60(15, 6), op60(15, 2), op80(6, 6), op80(4, 6), 0, 1, c0(4, 0)))
    # 2 Electric Grand Piano: CP-80 metallic bite
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(20, 2), op40(4, 1),
                   op60(15, 5), op60(15, 2), op80(5, 6), op80(4, 6), 0, 0, c0(2, 0)))
    # 3 Honky-Tonk Piano: detuned/reedy double-harmonic feel
    P.append(patch(op20(2, ksr=1, vib=1), op20(1, ksr=1), op40(16, 1), op40(4, 1),
                   op60(15, 5), op60(15, 2), op80(5, 6), op80(4, 6), 1, 0, c0(5, 0)))
    # 4 Electric Piano 1 (Rhodes): classic bell tine (14:1 or 7:1) + warm sine body
    P.append(patch(op20(7, ksr=1), op20(1, ksr=1, vib=1), op40(26, 2), op40(3, 1),
                   op60(15, 7), op60(15, 2), op80(10, 6), op80(3, 6), 0, 0, c0(1, 0)))
    # 5 Electric Piano 2 (DX7 FM E-Piano): glassy 14:1 chime + sweet sustain
    P.append(patch(op20(14, ksr=1), op20(1, ksr=1, vib=1), op40(24, 2), op40(3, 1),
                   op60(15, 6), op60(15, 2), op80(8, 6), op80(4, 6), 0, 0, c0(0, 0)))
    # 6 Harpsichord: plucked bright saw-like overtones (WS 3)
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(14, 1), op40(5, 1),
                   op60(15, 4), op60(15, 3), op80(4, 7), op80(5, 8), 3, 1, c0(5, 0)))
    # 7 Clavinet: funky snappy plucky 3:1
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(15, 1), op40(4, 1),
                   op60(15, 7), op60(15, 4), op80(6, 8), op80(6, 8), 2, 1, c0(4, 0)))

    # ---- 8..15: Chromatic Percussion ----
    # 8 Celesta
    P.append(patch(op20(4, ksr=1), op20(1, ksr=1), op40(23, 2), op40(4, 1),
                   op60(15, 7), op60(15, 3), op80(8, 6), op80(5, 6), 0, 0, c0(0, 0)))
    # 9 Glockenspiel
    P.append(patch(op20(7, ksr=1), op20(2, ksr=1), op40(21, 2), op40(5, 1),
                   op60(15, 6), op60(15, 3), op80(6, 5), op80(4, 5), 0, 0, c0(0, 0)))
    # 10 Music Box
    P.append(patch(op20(6, ksr=1), op20(2, ksr=1), op40(25, 2), op40(5, 1),
                   op60(15, 8), op60(15, 4), op80(9, 6), op80(6, 6), 0, 0, c0(0, 0)))
    # 11 Vibraphone
    P.append(patch(op20(4, ksr=1), op20(1, ksr=1, am=1, vib=1), op40(27, 2), op40(3, 1),
                   op60(15, 8), op60(14, 2), op80(10, 5), op80(3, 5), 0, 0, c0(0, 0)))
    # 12 Marimba
    P.append(patch(op20(4, ksr=1), op20(1, ksr=1), op40(20, 2), op40(3, 1),
                   op60(15, 10), op60(15, 6), op80(11, 8), op80(8, 8), 0, 0, c0(1, 0)))
    # 13 Xylophone
    P.append(patch(op20(6, ksr=1), op20(2, ksr=1), op40(18, 2), op40(4, 1),
                   op60(15, 11), op60(15, 7), op80(12, 9), op80(9, 9), 0, 0, c0(2, 0)))
    # 14 Tubular Bells
    P.append(patch(op20(7, ksr=1), op20(2, ksr=1), op40(16, 1), op40(4, 1),
                   op60(15, 3), op60(15, 2), op80(5, 4), op80(4, 4), 0, 0, c0(2, 0)))
    # 15 Dulcimer
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(19, 1), op40(4, 1),
                   op60(15, 6), op60(15, 3), op80(7, 6), op80(5, 6), 1, 0, c0(3, 0)))

    # ---- 16..23: Organ ----
    # 16 Drawbar Organ (Hammond)
    P.append(patch(op20(3, egt=1), op20(1, egt=1, vib=1), op40(12, 1), op40(6, 1),
                   op60(14, 0), op60(14, 0), op80(0, 8), op80(0, 8), 0, 0, c0(2, 1)))
    # 17 Percussive Organ (key-click harmonic)
    P.append(patch(op20(4, egt=0), op20(1, egt=1), op40(14, 1), op40(4, 1),
                   op60(15, 8), op60(15, 1), op80(9, 8), op80(0, 8), 0, 0, c0(2, 1)))
    # 18 Rock Organ (overdriven Hammond)
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1, vib=1), op40(14, 1), op40(4, 1),
                   op60(15, 2), op60(15, 0), op80(1, 8), op80(0, 8), 1, 1, c0(6, 0)))
    # 19 Church Organ (rich pipe harmonics)
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(13, 1), op40(5, 1),
                   op60(11, 1), op60(11, 0), op80(1, 5), op80(0, 5), 2, 1, c0(4, 1)))
    # 20 Reed Organ
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(16, 1), op40(5, 1),
                   op60(10, 1), op60(10, 0), op80(1, 6), op80(0, 6), 1, 2, c0(3, 0)))
    # 21 Accordion
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1, vib=1), op40(15, 1), op40(5, 1),
                   op60(12, 2), op60(12, 0), op80(2, 7), op80(0, 7), 1, 1, c0(4, 0)))
    # 22 Harmonica
    P.append(patch(op20(1, egt=1, vib=1), op20(2, egt=1, vib=1), op40(14, 1), op40(5, 1),
                   op60(11, 2), op60(11, 0), op80(2, 7), op80(0, 7), 2, 1, c0(4, 0)))
    # 23 Tango Accordion
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1), op40(16, 1), op40(5, 1),
                   op60(12, 2), op60(12, 0), op80(2, 7), op80(0, 7), 1, 1, c0(5, 0)))

    # ---- 24..31: Guitar ----
    # 24 Acoustic Guitar (Nylon)
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(20, 2), op40(4, 1),
                   op60(15, 6), op60(15, 3), op80(7, 6), op80(5, 6), 1, 0, c0(3, 0)))
    # 25 Acoustic Guitar (Steel)
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(17, 2), op40(4, 1),
                   op60(15, 6), op60(15, 3), op80(6, 6), op80(5, 6), 2, 1, c0(4, 0)))
    # 26 Electric Guitar (Jazz)
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(24, 2), op40(3, 1),
                   op60(15, 5), op60(15, 2), op80(6, 6), op80(4, 6), 0, 0, c0(2, 0)))
    # 27 Electric Guitar (Clean)
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(20, 2), op40(4, 1),
                   op60(15, 6), op60(15, 2), op80(5, 6), op80(4, 6), 1, 0, c0(3, 0)))
    # 28 Electric Guitar (Muted)
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(18, 1), op40(4, 1),
                   op60(15, 11), op60(15, 9), op80(12, 10), op80(10, 10), 1, 0, c0(4, 0)))
    # 29 Overdriven Guitar
    P.append(patch(op20(1, egt=1, ksr=1), op20(1, egt=1, ksr=1), op40(12, 1), op40(4, 1),
                   op60(15, 4), op60(15, 2), op80(3, 7), op80(2, 7), 1, 1, c0(6, 0)))
    # 30 Distortion Guitar
    P.append(patch(op20(1, egt=1, ksr=1), op20(1, egt=1, ksr=1), op40(9, 1), op40(4, 1),
                   op60(15, 3), op60(15, 1), op80(2, 7), op80(1, 7), 2, 1, c0(7, 0)))
    # 31 Guitar Harmonics
    P.append(patch(op20(4, ksr=1), op20(2, ksr=1), op40(24, 2), op40(5, 1),
                   op60(15, 7), op60(15, 3), op80(8, 6), op80(5, 6), 0, 0, c0(1, 0)))

    # ---- 32..39: Bass ----
    # 32 Acoustic Bass (warm plucked upright)
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(22, 1), op40(2, 0),
                   op60(15, 7), op60(15, 4), op80(8, 7), op80(6, 7), 0, 0, c0(3, 0)))
    # 33 Electric Bass (Finger)
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(19, 1), op40(2, 0),
                   op60(15, 6), op60(15, 3), op80(6, 7), op80(4, 7), 1, 0, c0(4, 0)))
    # 34 Electric Bass (Pick)
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(16, 1), op40(2, 0),
                   op60(15, 7), op60(15, 3), op80(7, 7), op80(4, 7), 1, 0, c0(5, 0)))
    # 35 Fretless Bass
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1), op40(21, 1), op40(2, 0),
                   op60(13, 5), op60(13, 2), op80(5, 6), op80(3, 6), 0, 0, c0(3, 0)))
    # 36 Slap Bass 1
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(12, 1), op40(2, 0),
                   op60(15, 9), op60(15, 4), op80(9, 8), op80(5, 8), 1, 0, c0(5, 0)))
    # 37 Slap Bass 2
    P.append(patch(op20(4, ksr=1), op20(1, ksr=1), op40(11, 1), op40(2, 0),
                   op60(15, 10), op60(15, 4), op80(10, 8), op80(5, 8), 2, 0, c0(6, 0)))
    # 38 Synth Bass 1 (classic punchy FM bass)
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(13, 1), op40(2, 0),
                   op60(15, 6), op60(15, 2), op80(5, 8), op80(2, 8), 1, 0, c0(5, 0)))
    # 39 Synth Bass 2 (brighter resonant acid/FM bass)
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(11, 1), op40(2, 0),
                   op60(15, 7), op60(15, 2), op80(6, 8), op80(2, 8), 2, 1, c0(6, 0)))

    # ---- 40..47: Strings ----
    # 40 Violin
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(16, 1), op40(5, 1),
                   op60(8, 2), op60(8, 1), op80(2, 6), op80(1, 6), 1, 1, c0(5, 0)))
    # 41 Viola
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(18, 1), op40(5, 1),
                   op60(8, 2), op60(8, 1), op80(2, 6), op80(1, 6), 1, 0, c0(4, 0)))
    # 42 Cello
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(15, 1), op40(4, 1),
                   op60(8, 2), op60(8, 1), op80(2, 6), op80(1, 6), 1, 0, c0(5, 0)))
    # 43 Contrabass
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(16, 1), op40(3, 0),
                   op60(9, 2), op60(9, 1), op80(2, 6), op80(1, 6), 1, 0, c0(4, 0)))
    # 44 Tremolo Strings
    P.append(patch(op20(1, egt=1, am=1, vib=1), op20(1, egt=1, am=1, vib=1), op40(16, 1), op40(5, 1),
                   op60(9, 2), op60(9, 1), op80(2, 6), op80(1, 6), 1, 1, c0(5, 0)))
    # 45 Pizzicato Strings
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(20, 2), op40(4, 1),
                   op60(15, 9), op60(15, 7), op80(10, 8), op80(8, 8), 0, 0, c0(3, 0)))
    # 46 Orchestral Harp
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(21, 2), op40(4, 1),
                   op60(15, 6), op60(15, 3), op80(7, 5), op80(5, 5), 0, 0, c0(2, 0)))
    # 47 Timpani
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(14, 0), op40(2, 0),
                   op60(15, 7), op60(15, 4), op80(8, 5), op80(6, 5), 0, 0, c0(5, 0)))

    # ---- 48..55: Ensemble ----
    # 48 String Ensemble 1 (lush slow-attack strings)
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1, vib=1), op40(18, 1), op40(6, 1),
                   op60(6, 2), op60(6, 1), op80(2, 5), op80(1, 5), 1, 1, c0(4, 0)))
    # 49 String Ensemble 2 (softer, slower swell)
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(20, 1), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(2, 4), op80(1, 4), 1, 0, c0(3, 0)))
    # 50 Synth Strings 1
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1), op40(16, 1), op40(6, 1),
                   op60(7, 2), op60(7, 1), op80(2, 5), op80(1, 5), 2, 1, c0(5, 0)))
    # 51 Synth Strings 2
    P.append(patch(op20(1, egt=1, vib=1), op20(2, egt=1), op40(18, 1), op40(6, 1),
                   op60(6, 2), op60(6, 1), op80(2, 5), op80(1, 5), 1, 1, c0(4, 0)))
    # 52 Choir Aahs
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1, vib=1), op40(22, 2), op40(6, 1),
                   op60(6, 2), op60(6, 1), op80(2, 5), op80(1, 5), 0, 1, c0(2, 0)))
    # 53 Voice Oohs
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(26, 2), op40(6, 1),
                   op60(6, 2), op60(6, 1), op80(2, 5), op80(1, 5), 0, 0, c0(1, 0)))
    # 54 Synth Voice
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1), op40(20, 2), op40(6, 1),
                   op60(7, 2), op60(7, 1), op80(2, 5), op80(1, 5), 0, 1, c0(2, 0)))
    # 55 Orchestra Hit
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(10, 1), op40(3, 1),
                   op60(15, 7), op60(15, 5), op80(7, 6), op80(5, 6), 2, 1, c0(7, 0)))

    # ---- 56..63: Brass ----
    # 56 Trumpet (classic bright FM brass swell)
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(13, 1), op40(4, 1),
                   op60(10, 3), op60(12, 1), op80(2, 7), op80(1, 7), 1, 0, c0(5, 0)))
    # 57 Trombone
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(14, 1), op40(4, 1),
                   op60(9, 3), op60(11, 1), op80(2, 7), op80(1, 7), 1, 0, c0(5, 0)))
    # 58 Tuba
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(16, 1), op40(3, 0),
                   op60(9, 3), op60(10, 1), op80(3, 6), op80(1, 6), 0, 0, c0(4, 0)))
    # 59 Muted Trumpet
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1), op40(15, 2), op40(5, 1),
                   op60(12, 4), op60(13, 2), op80(3, 8), op80(2, 8), 3, 1, c0(4, 0)))
    # 60 French Horn
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(18, 1), op40(4, 1),
                   op60(8, 2), op60(9, 1), op80(2, 6), op80(1, 6), 0, 0, c0(4, 0)))
    # 61 Brass Section
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(12, 1), op40(4, 1),
                   op60(10, 3), op60(11, 1), op80(2, 6), op80(1, 6), 1, 1, c0(6, 0)))
    # 62 Synth Brass 1 (80s Oberheim/DX brass)
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(11, 1), op40(4, 1),
                   op60(12, 4), op60(13, 2), op80(3, 7), op80(1, 7), 1, 1, c0(6, 0)))
    # 63 Synth Brass 2
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(13, 1), op40(4, 1),
                   op60(11, 4), op60(12, 2), op80(3, 7), op80(1, 7), 2, 1, c0(5, 0)))

    # ---- 64..71: Reed ----
    # 64 Soprano Sax
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(15, 1), op40(4, 1),
                   op60(11, 3), op60(11, 1), op80(2, 7), op80(1, 7), 2, 1, c0(4, 0)))
    # 65 Alto Sax
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(14, 1), op40(4, 1),
                   op60(10, 3), op60(11, 1), op80(2, 7), op80(1, 7), 1, 1, c0(5, 0)))
    # 66 Tenor Sax
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(13, 1), op40(4, 1),
                   op60(10, 3), op60(10, 1), op80(2, 7), op80(1, 7), 1, 0, c0(5, 0)))
    # 67 Baritone Sax
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(12, 1), op40(3, 0),
                   op60(10, 3), op60(10, 1), op80(2, 7), op80(1, 7), 1, 0, c0(6, 0)))
    # 68 Oboe (nasal 3:1)
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1, vib=1), op40(17, 1), op40(5, 1),
                   op60(10, 2), op60(10, 1), op80(2, 7), op80(1, 7), 1, 1, c0(3, 0)))
    # 69 English Horn
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1, vib=1), op40(18, 1), op40(5, 1),
                   op60(9, 2), op60(10, 1), op80(2, 7), op80(1, 7), 1, 0, c0(3, 0)))
    # 70 Bassoon
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(16, 1), op40(4, 1),
                   op60(10, 2), op60(10, 1), op80(2, 7), op80(1, 7), 1, 0, c0(4, 0)))
    # 71 Clarinet (hollow odd harmonics: 2:1 FM)
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(19, 1), op40(4, 1),
                   op60(11, 2), op60(11, 1), op80(2, 7), op80(1, 7), 0, 0, c0(2, 0)))

    # ---- 72..79: Pipe ----
    # 72 Piccolo
    P.append(patch(op20(2, egt=1, vib=1), op20(2, egt=1, vib=1), op40(28, 2), op40(5, 1),
                   op60(10, 2), op60(10, 1), op80(2, 7), op80(1, 7), 0, 0, c0(1, 0)))
    # 73 Flute
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(27, 2), op40(4, 1),
                   op60(9, 2), op60(9, 1), op80(2, 7), op80(1, 7), 0, 0, c0(1, 0)))
    # 74 Recorder
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(30, 2), op40(4, 1),
                   op60(11, 2), op60(11, 1), op80(2, 7), op80(1, 7), 0, 0, c0(0, 0)))
    # 75 Pan Flute
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1, vib=1), op40(26, 2), op40(4, 1),
                   op60(8, 3), op60(9, 1), op80(4, 6), op80(1, 6), 0, 0, c0(2, 0)))
    # 76 Blown Bottle
    P.append(patch(op20(4, egt=1), op20(1, egt=1), op40(25, 2), op40(4, 1),
                   op60(9, 5), op60(9, 1), op80(6, 6), op80(1, 6), 0, 0, c0(1, 0)))
    # 77 Shakuhachi
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1, vib=1), op40(22, 2), op40(4, 1),
                   op60(9, 4), op60(9, 1), op80(4, 6), op80(1, 6), 1, 0, c0(3, 0)))
    # 78 Whistle
    P.append(patch(op20(2, egt=1, vib=1), op20(2, egt=1, vib=1), op40(34, 2), op40(5, 1),
                   op60(9, 1), op60(9, 1), op80(1, 7), op80(1, 7), 0, 0, c0(0, 0)))
    # 79 Ocarina
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(32, 2), op40(4, 1),
                   op60(10, 1), op60(10, 1), op80(1, 7), op80(1, 7), 0, 0, c0(0, 0)))

    # ---- 80..87: Synth Lead ----
    # 80 Lead 1 (Square)
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(14, 1), op40(4, 1),
                   op60(15, 1), op60(15, 0), op80(1, 8), op80(0, 8), 0, 0, c0(4, 0)))
    # 81 Lead 2 (Sawtooth)
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(12, 1), op40(4, 1),
                   op60(15, 2), op60(15, 0), op80(1, 8), op80(0, 8), 1, 1, c0(6, 0)))
    # 82 Lead 3 (Calliope)
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1, vib=1), op40(22, 2), op40(4, 1),
                   op60(12, 3), op60(12, 1), op80(3, 7), op80(1, 7), 0, 0, c0(2, 0)))
    # 83 Lead 4 (Chiff)
    P.append(patch(op20(5, egt=1), op20(1, egt=1), op40(20, 2), op40(4, 1),
                   op60(15, 7), op60(14, 1), op80(7, 7), op80(1, 7), 1, 0, c0(3, 0)))
    # 84 Lead 5 (Charang)
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1), op40(13, 1), op40(4, 1),
                   op60(14, 3), op60(14, 1), op80(2, 7), op80(1, 7), 2, 1, c0(5, 0)))
    # 85 Lead 6 (Voice)
    P.append(patch(op20(2, egt=1, vib=1), op20(1, egt=1, vib=1), op40(20, 2), op40(4, 1),
                   op60(10, 2), op60(10, 1), op80(2, 6), op80(1, 6), 0, 1, c0(2, 0)))
    # 86 Lead 7 (Fifths: 3:2 ratio!)
    P.append(patch(op20(3, egt=1), op20(2, egt=1), op40(14, 1), op40(4, 1),
                   op60(14, 2), op60(14, 0), op80(1, 7), op80(0, 7), 1, 1, c0(3, 1)))
    # 87 Lead 8 (Bass + Lead)
    P.append(patch(op20(1, egt=1), op20(2, egt=1), op40(12, 1), op40(4, 1),
                   op60(15, 4), op60(15, 1), op80(3, 7), op80(1, 7), 1, 0, c0(5, 0)))

    # ---- 88..95: Synth Pad ----
    # 88 Pad 1 (New Age)
    P.append(patch(op20(4, egt=1, vib=1), op20(1, egt=1, vib=1), op40(24, 2), op40(6, 1),
                   op60(6, 4), op60(6, 1), op80(5, 4), op80(1, 4), 0, 0, c0(1, 0)))
    # 89 Pad 2 (Warm)
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(22, 1), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(2, 4), op80(1, 4), 0, 0, c0(3, 0)))
    # 90 Pad 3 (Polysynth)
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(16, 1), op40(6, 1),
                   op60(8, 3), op60(8, 1), op80(3, 5), op80(1, 5), 1, 1, c0(4, 0)))
    # 91 Pad 4 (Choir)
    P.append(patch(op20(2, egt=1, am=1, vib=1), op20(1, egt=1, vib=1), op40(22, 2), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(2, 4), op80(1, 4), 0, 1, c0(2, 0)))
    # 92 Pad 5 (Bowed)
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1, vib=1), op40(20, 2), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(3, 4), op80(1, 4), 1, 0, c0(3, 0)))
    # 93 Pad 6 (Metallic)
    P.append(patch(op20(7, egt=1, vib=1), op20(1, egt=1), op40(18, 2), op40(6, 1),
                   op60(6, 3), op60(6, 1), op80(4, 4), op80(1, 4), 0, 0, c0(2, 0)))
    # 94 Pad 7 (Halo)
    P.append(patch(op20(4, egt=1, am=1, vib=1), op20(2, egt=1, vib=1), op40(24, 2), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(3, 4), op80(1, 4), 0, 0, c0(1, 1)))
    # 95 Pad 8 (Sweep)
    P.append(patch(op20(1, egt=1), op20(1, egt=1), op40(14, 1), op40(6, 1),
                   op60(4, 2), op60(5, 1), op80(2, 4), op80(1, 4), 1, 1, c0(5, 0)))

    # ---- 96..103: Synth Effects ----
    # 96 FX 1 (Rain)
    P.append(patch(op20(9, ksr=1), op20(2, ksr=1, am=1), op40(20, 2), op40(5, 1),
                   op60(14, 6), op60(14, 3), op80(7, 5), op80(5, 5), 0, 0, c0(2, 0)))
    # 97 FX 2 (Soundtrack)
    P.append(patch(op20(3, egt=1, vib=1), op20(2, egt=1), op40(16, 1), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(2, 4), op80(1, 4), 1, 0, c0(4, 0)))
    # 98 FX 3 (Crystal)
    P.append(patch(op20(12, ksr=1), op20(2, ksr=1), op40(22, 2), op40(5, 1),
                   op60(15, 5), op60(14, 3), op80(6, 5), op80(4, 5), 0, 0, c0(1, 0)))
    # 99 FX 4 (Atmosphere)
    P.append(patch(op20(5, egt=1, am=1), op20(1, egt=1, vib=1), op40(22, 2), op40(6, 1),
                   op60(6, 3), op60(6, 1), op80(4, 4), op80(1, 4), 0, 0, c0(2, 0)))
    # 100 FX 5 (Brightness)
    P.append(patch(op20(8, ksr=1), op20(1, egt=1), op40(19, 2), op40(5, 1),
                   op60(15, 5), op60(13, 1), op80(6, 5), op80(2, 5), 0, 1, c0(1, 0)))
    # 101 FX 6 (Goblins)
    P.append(patch(op20(5, egt=1, am=1, vib=1), op20(1, egt=1, am=1), op40(16, 1), op40(6, 1),
                   op60(5, 2), op60(5, 1), op80(3, 4), op80(1, 4), 2, 0, c0(4, 0)))
    # 102 FX 7 (Echoes)
    P.append(patch(op20(4, egt=1, am=1), op20(1, egt=1, am=1), op40(21, 2), op40(6, 1),
                   op60(7, 3), op60(7, 2), op80(4, 3), op80(2, 3), 0, 0, c0(2, 0)))
    # 103 FX 8 (Sci-Fi)
    P.append(patch(op20(6, egt=1, vib=1), op20(1, egt=1, vib=1), op40(14, 1), op40(5, 1),
                   op60(8, 3), op60(8, 1), op80(3, 5), op80(1, 5), 3, 1, c0(5, 0)))

    # ---- 104..111: Ethnic ----
    # 104 Sitar
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(12, 1), op40(4, 1),
                   op60(15, 4), op60(15, 3), op80(5, 6), op80(4, 6), 3, 2, c0(6, 0)))
    # 105 Banjo
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(15, 1), op40(4, 1),
                   op60(15, 8), op60(15, 5), op80(8, 8), op80(6, 8), 2, 1, c0(4, 0)))
    # 106 Shamisen
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(16, 1), op40(4, 1),
                   op60(15, 9), op60(15, 6), op80(9, 8), op80(7, 8), 1, 1, c0(4, 0)))
    # 107 Koto
    P.append(patch(op20(4, ksr=1), op20(1, ksr=1), op40(18, 1), op40(4, 1),
                   op60(15, 7), op60(15, 4), op80(7, 7), op80(5, 7), 1, 0, c0(3, 0)))
    # 108 Kalimba
    P.append(patch(op20(5, ksr=1), op20(1, ksr=1), op40(22, 2), op40(4, 1),
                   op60(15, 9), op60(15, 5), op80(10, 7), op80(7, 7), 0, 0, c0(1, 0)))
    # 109 Bagpipe
    P.append(patch(op20(2, egt=1), op20(1, egt=1), op40(12, 1), op40(5, 1),
                   op60(12, 1), op60(12, 0), op80(1, 7), op80(0, 7), 3, 1, c0(5, 0)))
    # 110 Fiddle
    P.append(patch(op20(1, egt=1, vib=1), op20(1, egt=1, vib=1), op40(15, 1), op40(5, 1),
                   op60(10, 2), op60(10, 1), op80(2, 6), op80(1, 6), 2, 1, c0(5, 0)))
    # 111 Shanai
    P.append(patch(op20(3, egt=1, vib=1), op20(1, egt=1, vib=1), op40(13, 1), op40(5, 1),
                   op60(11, 2), op60(11, 1), op80(2, 7), op80(1, 7), 3, 1, c0(5, 0)))

    # ---- 112..119: Percussive ----
    # 112 Tinkle Bell
    P.append(patch(op20(10, ksr=1), op20(3, ksr=1), op40(18, 2), op40(5, 1),
                   op60(15, 7), op60(15, 5), op80(8, 6), op80(6, 6), 0, 0, c0(2, 0)))
    # 113 Agogo
    P.append(patch(op20(5, ksr=1), op20(2, ksr=1), op40(16, 1), op40(4, 1),
                   op60(15, 9), op60(15, 7), op80(10, 8), op80(8, 8), 0, 0, c0(3, 0)))
    # 114 Steel Drums
    P.append(patch(op20(3, ksr=1), op20(1, ksr=1), op40(18, 1), op40(4, 1),
                   op60(15, 7), op60(15, 5), op80(8, 7), op80(6, 7), 1, 0, c0(3, 0)))
    # 115 Woodblock
    P.append(patch(op20(4, ksr=1), op20(2, ksr=1), op40(14, 1), op40(4, 1),
                   op60(15, 13), op60(15, 11), op80(14, 12), op80(12, 12), 0, 0, c0(4, 0)))
    # 116 Taiko Drum
    P.append(patch(op20(1, ksr=1), op20(1, ksr=1), op40(12, 0), op40(2, 0),
                   op60(15, 9), op60(15, 5), op80(10, 6), op80(7, 6), 0, 0, c0(6, 0)))
    # 117 Melodic Tom
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(14, 0), op40(3, 0),
                   op60(15, 9), op60(15, 6), op80(10, 7), op80(7, 7), 0, 0, c0(5, 0)))
    # 118 Synth Drum
    P.append(patch(op20(2, ksr=1), op20(1, ksr=1), op40(10, 0), op40(3, 0),
                   op60(15, 10), op60(15, 7), op80(11, 8), op80(8, 8), 1, 0, c0(6, 0)))
    # 119 Reverse Cymbal
    P.append(patch(op20(7, ksr=1), op20(15, ksr=1), op40(6, 0), op40(6, 0),
                   op60(5, 4), op60(4, 4), op80(2, 6), op80(2, 6), 3, 2, c0(7, 0)))

    # ---- 120..127: Sound Effects ----
    # 120 Guitar Fret Noise
    P.append(patch(op20(11, ksr=1), op20(7, ksr=1), op40(8, 0), op40(8, 0),
                   op60(15, 12), op60(15, 11), op80(12, 12), op80(12, 12), 3, 2, c0(7, 0)))
    # 121 Breath Noise
    P.append(patch(op20(15, ksr=1), op20(11, ksr=1), op40(6, 0), op40(10, 0),
                   op60(8, 6), op60(8, 6), op80(6, 6), op80(6, 6), 2, 2, c0(7, 0)))
    # 122 Seashore
    P.append(patch(op20(15, egt=1), op20(13, egt=1), op40(4, 0), op40(10, 0),
                   op60(4, 3), op60(4, 3), op80(3, 3), op80(3, 3), 2, 3, c0(7, 0)))
    # 123 Bird Tweet
    P.append(patch(op20(6, ksr=1, vib=1), op20(3, ksr=1, vib=1), op40(18, 1), op40(6, 1),
                   op60(14, 8), op60(14, 7), op80(9, 8), op80(8, 8), 0, 0, c0(2, 0)))
    # 124 Telephone Ring
    P.append(patch(op20(9, egt=1, am=1), op20(4, egt=1, am=1), op40(14, 1), op40(6, 1),
                   op60(15, 2), op60(15, 1), op80(2, 8), op80(1, 8), 0, 0, c0(3, 0)))
    # 125 Helicopter
    P.append(patch(op20(1, egt=1, am=1), op20(1, egt=1, am=1), op40(6, 0), op40(8, 0),
                   op60(9, 2), op60(9, 1), op80(2, 5), op80(1, 5), 2, 3, c0(7, 0)))
    # 126 Applause
    P.append(patch(op20(15, egt=1), op20(11, egt=1), op40(4, 0), op40(9, 0),
                   op60(6, 4), op60(6, 4), op80(4, 4), op80(4, 4), 3, 2, c0(7, 0)))
    # 127 Gunshot
    P.append(patch(op20(15, ksr=1), op20(9, ksr=1), op40(2, 0), op40(3, 0),
                   op60(15, 7), op60(15, 6), op80(8, 6), op80(7, 6), 3, 2, c0(7, 0)))

    assert len(P) == 128
    return P


# ---------------------------------------------------------------------------
# General MIDI Percussion Patches (MIDI notes 35..81, 47 entries)
# byte[11] is the fixed OPL2 MIDI note number for that drum!
# ---------------------------------------------------------------------------
def build_gm_drums():
    def kick(n):
        return patch(op20(1, ksr=1), op20(1, ksr=1), op40(10, 0), op40(2, 0),
                     op60(15, 12), op60(15, 8), op80(13, 10), op80(10, 9), 0, 0, c0(6, 0), n)

    def snare(n, dr=8, rr=8):
        return patch(op20(7, ksr=1), op20(15, ksr=1), op40(4, 0), op40(4, 0),
                     op60(15, 10), op60(15, dr), op80(11, 10), op80(9, rr), 3, 2, c0(7, 0), n)

    def hihat(n, dr=12, rr=12, tl=7):
        return patch(op20(11, ksr=1), op20(15, ksr=1), op40(4, 0), op40(tl, 0),
                     op60(15, dr), op60(15, dr), op80(12, rr), op80(11, rr), 3, 3, c0(7, 0), n)

    def cymbal(n, dr=4, rr=4, tl=6):
        return patch(op20(9, ksr=1), op20(15, ksr=1), op40(3, 0), op40(tl, 0),
                     op60(15, dr + 1), op60(15, dr), op80(8, rr), op80(6, rr), 3, 2, c0(7, 0), n)

    def tom(n):
        return patch(op20(2, ksr=1), op20(1, ksr=1), op40(14, 0), op40(3, 0),
                     op60(15, 10), op60(15, 7), op80(11, 8), op80(8, 7), 0, 0, c0(5, 0), n)

    def wood(n):
        return patch(op20(5, ksr=1), op20(2, ksr=1), op40(14, 1), op40(5, 0),
                     op60(15, 13), op60(15, 11), op80(14, 12), op80(12, 12), 0, 0, c0(3, 0), n)

    def metal(n, dr=7, rr=7):
        return patch(op20(7, ksr=1), op20(3, ksr=1), op40(12, 0), op40(6, 0),
                     op60(15, dr + 1), op60(15, dr), op80(10, rr), op80(8, rr), 1, 0, c0(4, 0), n)

    D = [
        kick(36),                      # 35 Acoustic Bass Drum
        kick(38),                      # 36 Bass Drum 1
        wood(64),                      # 37 Side Stick
        snare(50, 9, 9),               # 38 Acoustic Snare
        snare(58, 10, 10),             # 39 Hand Clap
        snare(53, 8, 9),               # 40 Electric Snare
        tom(41),                       # 41 Low Floor Tom
        hihat(76, 13, 13, 8),          # 42 Closed Hi-Hat
        tom(44),                       # 43 High Floor Tom
        hihat(74, 11, 11, 8),          # 44 Pedal Hi-Hat
        tom(47),                       # 45 Low Tom
        hihat(78, 6, 6, 7),            # 46 Open Hi-Hat
        tom(50),                       # 47 Low-Mid Tom
        tom(53),                       # 48 Hi-Mid Tom
        cymbal(72, 4, 4, 6),           # 49 Crash Cymbal 1
        tom(57),                       # 50 High Tom
        cymbal(80, 6, 6, 7),           # 51 Ride Cymbal 1
        cymbal(68, 4, 4, 6),           # 52 Chinese Cymbal
        metal(76, 6, 6),               # 53 Ride Bell
        hihat(82, 10, 10, 9),          # 54 Tambourine
        cymbal(75, 7, 7, 7),           # 55 Splash Cymbal
        metal(66, 9, 9),               # 56 Cowbell
        cymbal(74, 4, 4, 6),           # 57 Crash Cymbal 2
        snare(62, 6, 6),               # 58 Vibraslap
        cymbal(82, 6, 6, 7),           # 59 Ride Cymbal 2
        tom(62),                       # 60 Hi Bongo
        tom(57),                       # 61 Low Bongo
        wood(56),                      # 62 Mute Hi Conga
        tom(55),                       # 63 Open Hi Conga
        tom(50),                       # 64 Low Conga
        tom(60),                       # 65 High Timbale
        tom(54),                       # 66 Low Timbale
        metal(72, 9, 9),               # 67 High Agogo
        metal(65, 9, 9),               # 68 Low Agogo
        hihat(84, 12, 12, 10),         # 69 Cabasa
        hihat(86, 12, 12, 10),         # 70 Maracas
        metal(84, 10, 10),             # 71 Short Whistle
        metal(82, 5, 6),               # 72 Long Whistle
        hihat(72, 11, 11, 9),          # 73 Short Guiro
        hihat(70, 6, 6, 9),            # 74 Long Guiro
        wood(74),                      # 75 Claves
        wood(72),                      # 76 Hi Wood Block
        wood(66),                      # 77 Low Wood Block
        tom(58),                       # 78 Mute Cuica
        tom(62),                       # 79 Open Cuica
        metal(86, 12, 12),             # 80 Mute Triangle
        metal(86, 5, 5),               # 81 Open Triangle
    ]
    assert len(D) == 47
    return D


def build_pitch_tables():
    # Exact Atari816 OPL2 sample rate: 28.6875 MHz / 8 / 72 = 49804.6875 Hz
    fs = 28687500.0 / 8.0 / 72.0
    fnums = []
    blks = []
    for note in range(128):
        freq = 440.0 * (2.0 ** ((note - 69) / 12.0))
        chosen_b = 7
        chosen_f = 1023
        for b in range(8):
            fn = int(round(freq * (1 << (20 - b)) / fs))
            if fn < 1024:
                chosen_b = b
                chosen_f = max(1, fn)
                break
        fnums.append(chosen_f)
        blks.append(chosen_b)
    return fnums, blks


def build_atten_table():
    # Linear MIDI gain 0..63 -> OPL2 0.75 dB attenuation steps 0..63
    tab = [63]
    for g in range(1, 64):
        db = -20.0 * math.log10(g / 63.0)
        att = int(round(db / 0.75))
        tab.append(min(63, max(0, att)))
    return tab


def emit_bytes(f, label, data, per_line=12, comment=None):
    if comment:
        f.write(f"; {comment}\n")
    f.write(f"{label}:\n")
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        f.write("        .byte   " + ", ".join(f"${b:02X}" for b in chunk) + "\n")


def emit_words(f, label, data, per_line=8, comment=None):
    if comment:
        f.write(f"; {comment}\n")
    f.write(f"{label}:\n")
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        f.write("        .word   " + ", ".join(f"${w:04X}" for w in chunk) + "\n")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "user", "opl_gm.inc"
    )
    mel = build_gm_melodic()
    drm = build_gm_drums()
    fnums, blks = build_pitch_tables()
    atten = build_atten_table()

    with open(out, "w") as f:
        f.write("; opl_gm.inc - Generated by tools/mkoplgm.py (do not edit by hand).\n")
        f.write("; General MIDI OPL2 (YM3812) 2-operator FM patch bank and pitch/attenuation tables.\n\n")
        f.write("        .segment \"RODATA\"\n\n")

        f.write("; 128 General MIDI melodic patches (12 bytes each: 1536 bytes)\n")
        f.write("gm_mel:\n")
        for idx, p in enumerate(mel):
            f.write("        .byte   " + ", ".join(f"${b:02X}" for b in p) + f"  ; {idx:3d}\n")
        f.write("\n")

        f.write("; 47 General MIDI percussion patches for notes 35..81 (12 bytes each: 564 bytes)\n")
        f.write("gm_drm:\n")
        for idx, p in enumerate(drm):
            f.write("        .byte   " + ", ".join(f"${b:02X}" for b in p) + f"  ; {idx + 35:3d}\n")
        f.write("\n")

        emit_words(f, "mid_fnum", fnums, 8, "OPL2 10-bit F-Numbers for MIDI notes 0..127 (fs = 49804.69 Hz)")
        f.write("\n")
        emit_bytes(f, "mid_blk", blks, 16, "OPL2 3-bit Block (octave) for MIDI notes 0..127")
        f.write("\n")
        emit_bytes(f, "mid_atten", atten, 16, "Linear MIDI gain 0..63 -> OPL2 0.75 dB attenuation 0..63")
        f.write("\n")
        emit_bytes(f, "opl_mod_off", [0, 1, 2, 8, 9, 10, 16, 17, 18], 9,
                   "OPL2 modulator operator offsets for voices 0..8")
        emit_bytes(f, "opl_car_off", [3, 4, 5, 11, 12, 13, 19, 20, 21], 9,
                   "OPL2 carrier operator offsets for voices 0..8")

    print(f"Wrote {out}: {len(mel)} melodic, {len(drm)} drums")


if __name__ == "__main__":
    main()
