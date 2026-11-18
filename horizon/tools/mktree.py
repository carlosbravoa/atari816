#!/usr/bin/env python3
"""mktree.py SD_DIR - the test tree on the emulator's SD card: folders and files with long
names containing spaces, '+', '_', '(', ')', '!', '[', ']' and apostrophes, like the
owner's collection, and a folder of 250 entries. Deterministic. The Atari files are copies
of /BLUE.XEX (a real, tiny executable) so that they also run on hardware; emu816's stub
accepts any existing file with a known extension."""
import os, sys

sd = sys.argv[1]
blue = open(os.path.join(sd, 'BLUE.XEX'), 'rb').read()
hello = open(os.path.join(sd, 'SYSTEM', 'TESTS', 'HELLO.PRG'), 'rb').read()

def put(path, data=blue):
    full = os.path.join(sd, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'wb') as f:
        f.write(data)

put('disks/xex/R - Z/River Raid (Title Version).xex')
put('disks/xex/R - Z/Star Raiders II (1986)(Atari)[!].xex')
put('disks/xex/A - F/Boulder Dash + Boulder Dash II.xex')
put('disks/xex/A - F/Caverns of Mars_ Mars Mission (v1.1).xex')
put('disks/Caverns of Mars.atr')
put("carts/Montezuma's Revenge _ Parker Brothers.atr")
put('carts/Donkey Kong (1982)(Atari)[!].rom')
put('carts/Star Raiders + Manual.car')
put('programs/Hello Program.prg', hello)
put('docs/Read me first.txt',
    ''.join(f'Line {i:2d} of the read-me: long names, spaces and (brackets) work.\n'
            for i in range(1, 61)).encode())

words = ['Alpha', 'bravo', 'Charlie', 'delta', 'Echo', 'foxtrot', 'Golf', 'hotel',
         'India', 'juliet', 'Kilo', 'lima', 'Mike', 'november', 'Oscar', 'papa']
for i in range(240):
    a, b = words[(i * 7) % 16], words[(i * 11 + 3) % 16]
    name = f'{a} {b} {i:03d} (Demo) [!].xex'
    if i == 17:
        name = 'A very long name that goes on and on beyond the width of the name column ' \
               'of the list.xex'
    if i == 42:
        name = "Isn't it_odd + strange!.xex"
    put(f'many/{name}')
for i in range(10):
    os.makedirs(os.path.join(sd, f'many/Folder {i:02d}'), exist_ok=True)
