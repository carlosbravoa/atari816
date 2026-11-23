#!/usr/bin/env python3
"""shots.py RUN SUMS [--update]: the pictures a run took (RUN/autoK.png: run816.py
--shot-on, at the program's "xargon: shot K" lines) against the checksums in SUMS (the MD5
of each picture's RGB pixels: the game's pictures stay out of the repository, as its data
do). A line of SUMS whose checksum is "-" is a picture not compared (its screen holds
something the keys' timing decides); it is still taken, and must be. A line with
"crop:X0,Y0,X1,Y1" after the file name compares only that rectangle of the picture.
--update writes SUMS anew (keeping its "-" lines) and the pictures into tests/ref/ as
NAME-K.png, NAME from SUMS's file name (look at them)."""
import hashlib
import os
import shutil
import sys

run, sums = sys.argv[1:3]
update = '--update' in sys.argv
try:
    from PIL import Image
except ImportError:
    print('SKIP  screenshots: no Pillow')
    sys.exit(0)
name = os.path.splitext(os.path.basename(sums))[0]
lines = [line.split(None, 1) for line in open(sums)
         if line.strip() and not line.startswith('#')] if os.path.exists(sums) else []
want = [w[0] for w in lines]


def box(i):
    for w in (lines[i - 1][1].split() if i <= len(lines) else []):
        if w.startswith('crop:'):
            return tuple(int(v) for v in w[5:].split(','))
    return None


got = []
k = 1
while os.path.exists(os.path.join(run, f'auto{k}.png')):
    im = Image.open(os.path.join(run, f'auto{k}.png')).convert('RGB')
    if box(k):
        im = im.crop(box(k))
    got.append(hashlib.md5(im.tobytes()).hexdigest())
    k += 1
if update:
    ref = os.path.join(os.path.dirname(sums), 'ref')
    os.makedirs(ref, exist_ok=True)
    head = [line for line in open(sums) if line.startswith('#')] if os.path.exists(sums) else []
    with open(sums, 'w') as f:
        f.writelines(head)
        for i, h in enumerate(got, 1):
            skip = i <= len(lines) and want[i - 1] == '-'
            rest = lines[i - 1][1].strip() if i <= len(lines) else f'{name}-{i}.png'
            f.write(f'{"-" if skip else h}  {rest}\n')
            shutil.copy(os.path.join(run, f'auto{i}.png'), os.path.join(ref, f'{name}-{i}.png'))
    print(f'PASS  {len(got)} pictures: references written ({sums}, {ref}/{name}-K.png)')
    sys.exit(0)
fail = 0
same = 0
for i, h in enumerate(got, 1):
    if i > len(want):
        print(f'FAIL  {name} picture {i}: no reference')
        fail = 1
    elif want[i - 1] == '-':
        pass
    elif h != want[i - 1]:
        print(f'FAIL  {name} picture {i}: differs from the reference ({lines[i - 1][1].strip()})')
        fail = 1
    else:
        same += 1
if len(got) < len(want):
    print(f'FAIL  {name}: {len(want) - len(got)} pictures not taken (of {len(want)})')
    fail = 1
if not fail:
    print(f'PASS  {name}: {same} pictures as the references'
          + (f' ({len(got) - same} not compared)' if len(got) > same else ''))
sys.exit(fail)
