#!/usr/bin/env python3
"""cmpshots.py RUN REFDIR NAME [--prefix P] [--update]: RUN/PK.png (P: shot, or auto for
run816.py --shot-on's) against REFDIR/NAME-K.png, pixel for pixel. --update writes the
references."""
import os
import shutil
import sys

run, ref, name = sys.argv[1:4]
update = '--update' in sys.argv
pre = sys.argv[sys.argv.index('--prefix') + 1] if '--prefix' in sys.argv else 'shot'
try:
    from PIL import Image, ImageChops
except ImportError:
    print('SKIP  screenshots: no Pillow')
    sys.exit(0)
fail = 0
k = 1
while os.path.exists(os.path.join(run, f'{pre}{k}.png')):
    s = os.path.join(run, f'{pre}{k}.png')
    r = os.path.join(ref, f'{name}-{k}.png')
    if update:
        shutil.copy(s, r)
        print(f'PASS  {name}-{k}: reference written')
    elif not os.path.exists(r):
        print(f'FAIL  {name}-{k}: no reference ({r})')
        fail = 1
    else:
        a, b = Image.open(s).convert('RGB'), Image.open(r).convert('RGB')
        d = ImageChops.difference(a, b).getbbox() if a.size == b.size else (0, 0, 1, 1)
        if d:
            print(f'FAIL  {name}-{k}: differs from the reference in {d}')
            fail = 1
        else:
            print(f'PASS  {name}-{k}: as the reference')
    k += 1
sys.exit(fail)
