#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# plat/font8x8.h from a PSF1 console font of 8 x 8 (default: kbd's Arabic-VGA8.psf.gz, whose
# lower half is the IBM VGA BIOS 8 x 8 font). Run once; the header is in git.
import gzip, sys
src = sys.argv[1] if len(sys.argv) > 1 else '/usr/share/consolefonts/Arabic-VGA8.psf.gz'
d = gzip.open(src).read() if src.endswith('.gz') else open(src, 'rb').read()
assert d[:2] == b'\x36\x04' and d[3] == 8, 'a PSF1 font of 8 rows'
g = d[4:4 + 128 * 8]
out = ['/* SPDX-License-Identifier: GPL-3.0-or-later */',
       '/* The 8 x 8 font of the VGA BIOS, characters 0-127 (the engine reads the BIOS font at',
       '   F000:FA6E: hud.c). Made by tools/mkfont8.py from the Linux console font Arabic-VGA8.psf',
       '   (kbd), whose lower half is the IBM VGA 8 x 8 font. */',
       'static const unsigned char font8x8[128 * 8] = {']
for i in range(128):
    out.append('    ' + ', '.join('0x%02X' % b for b in g[i * 8:i * 8 + 8]) + ',')
out.append('};')
open(sys.argv[2] if len(sys.argv) > 2 else 'plat/font8x8.h', 'w').write('\n'.join(out) + '\n')
