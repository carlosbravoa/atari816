#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
# Simulates the "Run in Atari" boot program (bas_loader.h) in py65: the OS's HATABS with a fake
# editor, the boot call, the editor's GET as BASIC calls it (the input lines must be ENTER "D:"
# and RUN, then the real editor again), the "D:" handler (OPEN, GET to the end of file through
# a fake DSKINV that serves the firmware's sectors), a RESET (DOSINI) and the SAVE-file mode.
import re, sys
from py65.devices.mpu6502 import MPU

src = open('bas_loader.h').read()
def const(n): return int(re.search(r'#define %s\s+(0x[0-9A-F]+|\d+)' % n, src).group(1), 0)
NSEC, DATASEC, P_LEN, P_MODE = const('BAS_NSEC'), const('BAS_DATASEC'), const('BAS_P_LEN'), const('BAS_P_MODE')
img = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', src.split('{', 1)[1])]
fails = 0
def check(ok, text):
    global fails
    print(("PASS " if ok else "FAIL ") + text)
    fails += not ok

HATABS, MEMLO, DOSINI = 0x031A, 0x02E7, 0x000C
EDITOR, EGET, EPUT, DSKINV, TRAP = 0xE400, 0xE500, 0xE510, 0xE453, 0xFFF0

def run(stream, mode):
    m = MPU()
    mem = m.memory
    for i in range(0x10000): mem[i] = 0
    # HATABS: P, C, E, S, K (ROM order)
    for k, (dev, addr) in enumerate([(b'P', 0xE430), (b'C', 0xE440), (b'E', EDITOR), (b'S', 0xE410), (b'K', 0xE420)]):
        mem[HATABS + 3 * k] = dev[0]; mem[HATABS + 3 * k + 1] = addr & 0xFF; mem[HATABS + 3 * k + 2] = addr >> 8
    # the editor's table: GET = EGET (LDA #'k', LDY #1, RTS)
    vec = [0xE600, 0xE600, EGET, EPUT, 0xE600, 0xE600]
    for i, v in enumerate(vec): mem[EDITOR + 2 * i] = (v - 1) & 0xFF; mem[EDITOR + 2 * i + 1] = (v - 1) >> 8
    mem[EGET:EGET + 5] = [0xA9, ord('k'), 0xA0, 0x01, 0x60]
    mem[0xE600] = 0x60
    mem[DSKINV] = 0x60                                  # (served in Python, below)
    # the disk: the loader (patched) then the stream
    disk = bytearray(img)
    disk[P_LEN:P_LEN + 3] = len(stream).to_bytes(3, 'little'); disk[P_MODE] = mode
    disk += bytes((DATASEC - 1 - NSEC) * 128) + stream + bytes(256)
    for i in range(NSEC * 128): mem[0x0700 + i] = disk[i]
    def call(addr, a=0, x=0, y=0):
        # JSR addr with a return to TRAP; DSKINV served when the PC reaches it
        sp = 0xFF
        m.sp = sp; m.a = a; m.x = x; m.y = y; m.p = 0x20
        ret = TRAP - 1
        mem[0x100 + m.sp] = ret >> 8; m.sp -= 1
        mem[0x100 + m.sp] = ret & 0xFF; m.sp -= 1
        m.pc = addr
        for _ in range(200000):
            if m.pc == TRAP: return
            if m.pc == DSKINV:
                sec = mem[0x030A] | mem[0x030B] << 8
                buf = mem[0x0304] | mem[0x0305] << 8
                assert mem[0x0302] == 0x52 and mem[0x0301] == 1, "DSKINV: a read of D1:"
                for i in range(128): mem[buf + i] = disk[(sec - 1) * 128 + i]
                m.y = 1; m.p = (m.p & ~0x80)
            m.step()
        raise RuntimeError("no return from $%04X" % addr)
    def handler(dev):
        for k in range(12):
            if mem[HATABS + 3 * k] == ord(dev): return mem[HATABS + 3 * k + 1] | mem[HATABS + 3 * k + 2] << 8
        return None
    def hcall(dev, slot, x=0):
        t = handler(dev)
        v = (mem[t + 2 * slot] | mem[t + 2 * slot + 1] << 8) + 1
        call(v, x=x)
        return m.a, m.y, m.x
    mem[DOSINI] = disk[4]; mem[DOSINI + 1] = disk[5]     # (the OS takes DOSINI from the header)
    call(0x0706)
    check(not (m.p & 1), "boot: carry clear")
    dosini = mem[DOSINI] | mem[DOSINI + 1] << 8
    call(dosini)                                        # (the OS calls DOSINI after the boot)
    memlo = mem[MEMLO] | mem[MEMLO + 1] << 8
    check(memlo >= 0x0700 + NSEC * 128 and memlo < 0x0C00, "MEMLO raised to $%04X" % memlo)
    check(handler('D') is not None, "a D: handler in HATABS")
    # BASIC reads its input lines from the editor (IOCB 0: X = 0)
    def line():
        s = b''
        while True:
            a, y, x = hcall('E', 2, x=0)
            assert y == 1 and x == 0
            s += bytes([a])
            if a == 0x9B: return s
    def dread():
        a, y, _ = hcall('D', 0, x=0x70)                 # OPEN #7 (AUX1 = 4 in ZP $2A)
        assert y == 1
        out = b''
        for _ in range(len(stream) + 5):
            a, y, x = hcall('D', 2, x=0x70)
            if y == 136: return out
            assert y == 1 and x == 0x70, (y, x)
            out += bytes([a])
        return out
    return m, mem, line, dread, hcall, call, dosini

listing = b''.join(b'%d PRINT "LINE %d"\x9b' % (10 * i, i) for i in range(1, 60)) + b'RUN\x9b'
m, mem, line, dread, hcall, call, dosini = run(listing, 0)
mem[0x2A] = 4
check(line() == b'ENTER "D:"\x9b', "the first line typed: ENTER \"D:\"")
check(dread() == listing, "D: gives the listing (%d bytes, %d sectors) and then end of file" % (len(listing), (len(listing) + 127) // 128))
check(line() == b'RUN\x9b', "then RUN")
a, y, _ = hcall('E', 2)
check(a == ord('k') and y == 1, "then the editor is the keyboard again")
mem[0x2A] = 4
check(dread() == listing, "D: OPEN again: from the start")
mem[0x2A] = 8
a, y, _ = hcall('D', 0, x=0x70)
check(y == 146, "D: OPEN for writing: 146")
# RESET: the OS rebuilds HATABS from ROM, calls DOSINI
for k in range(5, 12): mem[HATABS + 3 * k] = 0
call(dosini)
check(any(mem[HATABS + 3 * k] == ord('D') for k in range(12)), "after RESET: D: again")
saved = bytes([0, 0, 0, 1, 0x10, 1, 0x20, 1, 0x30, 1, 0x40, 1, 0x50, 1]) + bytes(range(256)) * 3
m, mem, line, dread, hcall, call, dosini = run(saved, 1)
check(line() == b'RUN "D:"\x9b', "a SAVE file: RUN \"D:\"")
mem[0x2A] = 4
check(dread() == saved, "D: gives the SAVE file's bytes")
a, y, _ = hcall('E', 2)
check(a == ord('k'), "then the editor is the keyboard again")
big = bytes((i * 7) & 0xFF for i in range(70000))
m, mem, line, dread, hcall, call, dosini = run(big, 1)
line(); mem[0x2A] = 4
check(dread() == big, "a 70,000-byte stream (24-bit length)")
print("RESULT", "PASS" if not fails else "FAIL")
sys.exit(1 if fails else 0)
