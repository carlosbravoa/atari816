#!/usr/bin/env python3
"""tools/mkicon.py - the app's icon from the game's own art: a running frame of the kid
(KID/res408.png of SDLPoP's data), its colour 0 transparent, as an RGBA picture for
sdk/tools/hzapp.py icon.   mkicon.py SDLPOP_DATA OUT.png"""
import sys
from PIL import Image

im = Image.open(sys.argv[1] + "/KID/res408.png")
rgba = im.convert("RGBA")
px = rgba.load()
idx = im.load()
for y in range(im.size[1]):
    for x in range(im.size[0]):
        if idx[x, y] == 0:
            px[x, y] = (0, 0, 0, 0)
rgba.save(sys.argv[2])
