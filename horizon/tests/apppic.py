#!/usr/bin/env python3
"""apppic.py NAME - (0.29) build/NAME.pic: the md5 of each picture build/NAMEn.ppm (or .png)
with the right end of the menu bar (the status: free memory and the clock, which differ
between hardware revisions and runs) painted over, so one list holds for every revision."""
import glob
import hashlib
import os
import re
import sys

from PIL import Image

name = sys.argv[1]
files = sorted(glob.glob(f"build/{name}[0-9]*.ppm") + glob.glob(f"build/{name}[0-9]*.png"),
               key=lambda f: int(re.search(r"(\d+)\.\w+$", f).group(1)))
out = []
for f in files:
    im = Image.open(f).convert("RGB")
    w, h = im.size
    s = w // 640                        # (1280 x 720: 2 screen pixels a pixel)
    im.paste((0, 0, 0), (w - 230 * s, 0, w, 15 * s))
    out.append(f"{hashlib.md5(im.tobytes()).hexdigest()}  {os.path.basename(f)}")
open(f"build/{name}.pic", "w").write("\n".join(out) + "\n")
