#!/usr/bin/env python3
"""basic2s-prep.py CARD - (0.31) the BASIC 2.0 picture session's programs (tests/basic2s.keys)
made to stop at a step instead of a moment: the copies on the card CARD of SPRITES.BAS,
DRIFT.BAS and SCROLLER.BAS are changed so that what they show at a picture does not depend
on how fast the CPU, the kernel or BASIC is:
  - a fixed RANDOMIZE seed (they seed from the time of day);
  - the animation holds still after a given number of steps (frames) and waits there (a
    loop that BASIC's Break, Esc, still stops), so the picture is taken when the screen is
    still (keyscript.py "still N") and shows that step;
  - DRIFT steers its boat by its step count (right and down from step 20 to 109) instead of
    the arrow keys, which the script would press at moments, not at steps;
  - SCROLLER reads its pictures, then waits for a key before the raster bands and its
    first step (the bands' edges move by a line now and then: no long still screen with
    them), holds at steps 120 and 240 (a key goes
    on from the first); its ship's
    flame flickers by its step count, not by the frame counter; the hills and houses are
    drawn in sight (no long still screen before the scrolling starts).
Each line replaced must be there as written (else exit 1: the program changed; update this
file and the pictures)."""
import os
import sys

EDITS = {
    'SPRITES.BAS': [
        ('40 SCREEN 320,200:GCLS 17:COLOR 59:FRECT 0,186,320,14:RANDOMIZE',
         '40 SCREEN 320,200:GCLS 17:COLOR 59:FRECT 0,186,320,14:RANDOMIZE 5'),
        ('180 VSYNC:GOTO 110', '180 VSYNC:F=F+1:IF F<110 THEN 110\n185 GOTO 185'),
    ],
    'DRIFT.BAS': [
        ('50 SCREEN 1:RANDOMIZE:HI=0', '50 SCREEN 1:RANDOMIZE 5:HI=0'),
        ('210 S=STICK(0)', '210 S=15:IF T>=20 AND T<110 THEN S=5'),
        ('350 VSYNC:GOTO 210', '350 VSYNC:IF T<150 THEN 210\n355 GOTO 355'),
    ],
    'SCROLLER.BAS': [
        ('90 REM hills all around', '90 SCROLL 0,180:REM (basic2s-prep.py: drawn in sight) hills all around'),
        ('170 PANEL -16', '175 FOR P=0 TO 1:FOR R=0 TO 6:READ A$:SHAPE P,R,A$:NEXT R,P\n'
         '176 IF INKEY$="" THEN 176\n170 PANEL -16'),
        ('190 FOR P=0 TO 1:FOR R=0 TO 6:READ A$:SHAPE P,R,A$:NEXT R,P', '190 REM (basic2s-prep.py: at 175)'),
        ('290 SPRITE 0,144,92,(FRAME AND 4)\\4', '290 SPRITE 0,144,92,(K AND 4)\\4'),
        ('300 VSYNC:GOTO 220',
         '300 VSYNC:K=K+1:IF K<>120 AND K<>240 THEN 220\n'
         '305 IF K=120 AND INKEY$="" THEN 305\n306 IF K=240 THEN 306\n307 GOTO 220'),
    ],
}

card = sys.argv[1]
for name, edits in EDITS.items():
    p = os.path.join(card, 'programs', name)
    text = open(p, encoding='latin-1').read()
    for old, new in edits:
        lines = text.split('\n')
        hits = [i for i, l in enumerate(lines) if l.startswith(old)]
        if len(hits) != 1:
            sys.exit(f'basic2s-prep.py: {name}: no line "{old}"')
        i = hits[0]
        lines[i] = new + lines[i][len(old):]
        text = '\n'.join(lines)
    open(p, 'w', encoding='latin-1').write(text)
