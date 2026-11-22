#!/usr/bin/env python3
"""shots.py RUN SUMS [--update]: RUN/shotK.png against the checksums in SUMS (the MD5 of
each picture's RGB pixels: the game's pictures stay out of the repository, as its data do).
--update writes SUMS and the pictures into tests/ref/ (look at them)."""
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
got = []
k = 1
while os.path.exists(os.path.join(run, f'shot{k}.png')):
    im = Image.open(os.path.join(run, f'shot{k}.png')).convert('RGB')
    got.append(hashlib.md5(im.tobytes()).hexdigest())
    k += 1
if update:
    ref = os.path.join(os.path.dirname(sums), 'ref')
    os.makedirs(ref, exist_ok=True)
    name = os.path.splitext(os.path.basename(sums))[0]
    with open(sums, 'w') as f:
        for i, h in enumerate(got, 1):
            f.write(f'{h}  {name}-{i}.png\n')
            shutil.copy(os.path.join(run, f'shot{i}.png'), os.path.join(ref, f'{name}-{i}.png'))
    print(f'PASS  {len(got)} screenshots: references written ({sums}, {ref})')
    sys.exit(0)
want = [line.split()[0] for line in open(sums) if line.strip() and not line.startswith('#')]
fail = 0
for i, h in enumerate(got, 1):
    if i > len(want):
        print(f'FAIL  screenshot {i}: no reference')
        fail = 1
    elif h != want[i - 1]:
        print(f'FAIL  screenshot {i}: differs from the reference')
        fail = 1
if len(got) < len(want):
    print(f'FAIL  {len(want) - len(got)} screenshots missing')
    fail = 1
if not fail:
    print(f'PASS  {len(got)} screenshots as the references')
sys.exit(fail)
