#!/usr/bin/env python3
"""zpcheck.py PROG.PRG PROG.map - look for 6502 code that breaks under Horizon's 65816 model.

cc65's code assumes zero page = page 0 of the data bank. Under Horizon DBR = the code bank
and the zero page is the direct page in bank 0, so an *absolute* access to $00xx (as
"lda zpvar,y" assembles: there is no zp,y form for lda/sta/...) reads the code bank's page
0 instead of the direct page. Also flagged: TSX/TXS (with 8-bit X they lose the high byte
of the 16-bit S) and the Rockwell bit opcodes ($x7/$xF: other instructions on a 65816).

Linear disassembly of the ONCE, LOWCODE and CODE segments, skipping the modules written for
the 65816 with 16-bit registers (STARTUP/crt0, hzsys, uibind, fastrt, ulib.o, ui.lib), whose
immediates a 6502 disassembly would misread; data inside code can give false reports, which
are listed with the nearest symbol.
"""
import re, struct, sys

# addressing mode lengths for the 6502/65C02 opcode map (65816 reading where they differ
# in length is irrelevant: cc65 emits only 6502/65C02 opcodes in C code)
IMPL, IMM, ZP, ABS, REL, ZPREL = 1, 2, 2, 3, 2, 3
L = [1] * 256
ABSMODE = set()   # opcodes with an absolute (bank DBR) data operand
def setop(ops, n, absmode=False):
    for o in ops:
        L[o] = n
        if absmode: ABSMODE.add(o)
# immediates / zp / relative / (zp) forms: 2 bytes
setop([0x09,0x29,0x49,0x69,0xA9,0xC9,0xE9,0xA0,0xA2,0xC0,0xE0,0x89,
       0x05,0x25,0x45,0x65,0x85,0xA5,0xC5,0xE5,0x06,0x26,0x46,0x66,0xC6,0xE6,0x84,0xA4,0xC4,0xE4,0x86,0xA6,0x24,0x64,0x04,0x14,
       0x15,0x35,0x55,0x75,0x95,0xB5,0xD5,0xF5,0x16,0x36,0x56,0x76,0xD6,0xF6,0x94,0xB4,0x96,0xB6,0x34,0x74,
       0x01,0x21,0x41,0x61,0x81,0xA1,0xC1,0xE1,0x11,0x31,0x51,0x71,0x91,0xB1,0xD1,0xF1,
       0x12,0x32,0x52,0x72,0x92,0xB2,0xD2,0xF2,
       0x10,0x30,0x50,0x70,0x90,0xB0,0xD0,0xF0,0x80,
       0x02,0xC2,0xE2], 2)   # 65816: COP, REP, SEP (hand-written gates)
# absolute data operands: 3 bytes, flagged when < $0100
setop([0x0D,0x2D,0x4D,0x6D,0x8D,0xAD,0xCD,0xED,0x0E,0x2E,0x4E,0x6E,0xCE,0xEE,0x8C,0xAC,0xCC,0xEC,0x8E,0xAE,0x2C,0x9C,0x0C,0x1C,
       0x1D,0x3D,0x5D,0x7D,0x9D,0xBD,0xDD,0xFD,0x1E,0x3E,0x5E,0x7E,0xDE,0xFE,0xBC,0x3C,0x9E,
       0x19,0x39,0x59,0x79,0x99,0xB9,0xD9,0xF9,0xBE], 3, True)
setop([0x20,0x4C,0x6C,0x7C], 3)   # JSR/JMP (program bank; (abs) reads bank 0: fine for zp vectors)
BAD = {0xBA: "TSX", 0x9A: "TXS"}
for o in range(256):
    if (o & 0x0F) in (0x07, 0x0F):
        BAD[o] = "Rockwell bit op $%02X (not on a 65816)" % o

def main():
    prg, mp = sys.argv[1], sys.argv[2]
    d = open(prg, "rb").read()
    assert d[:6] == b"\x01\x00o65\x00", "not o65"
    mode, tbase, tlen, dbase, dlen, bbase, blen, zbase, zlen, stack = struct.unpack("<10H", d[6:26])
    p = 26
    while d[p]:
        p += d[p]
    text = d[p + 1:p + 1 + tlen + dlen]       # text, then data, both from tbase
    m = open(mp).read()
    segs = {n: (int(s, 16), int(e, 16)) for n, s, e in re.findall(r"^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+[0-9A-F]{6}", m, re.M)}
    syms = sorted((int(a, 16), n) for n, a in re.findall(r"(\w+)\s+([0-9A-F]{6}) R?L?A", m))
    def near(a):
        best = "?"
        for sa, sn in syms:
            if sa <= a: best = "%s+%d" % (sn, a - sa)
        return best
    # module ranges to skip (65816 code with 16-bit registers)
    skip = []
    mod = None
    for line in m.split("Segment list")[0].splitlines():
        mm = re.match(r"^(\S+):$", line)
        if mm: mod = mm.group(1); continue
        mm = re.match(r"^\s+(\w+)\s+Offs=(\w+)\s+Size=(\w+)", line)
        if mm and mod and re.search(r"ui\.lib|ulib\.o|uibind|hzsys|fast_", mod) and mm.group(1) in segs:
            st = segs[mm.group(1)][0] + int(mm.group(2), 16)
            skip.append((st, st + int(mm.group(3), 16)))
    found = 0
    for seg in ("ONCE", "LOWCODE", "CODE"):
        if seg not in segs: continue
        a, end = segs[seg]
        while a <= end:
            sk = [e for s0, e in skip if s0 <= a < e]
            if sk:
                a = sk[0]; continue
            o = text[a - tbase]
            n = L[o]
            if o in BAD:
                print("%s: $%04X %s  (%s)" % (prg, a, BAD[o], near(a))); found += 1
            if o in ABSMODE:
                opnd = text[a - tbase + 1] | text[a - tbase + 2] << 8
                if opnd < 0x100:
                    print("%s: $%04X opcode $%02X absolute $%04X: reaches the code bank, not the direct page  (%s)"
                          % (prg, a, o, opnd, near(a))); found += 1
            a += n
    print("%s: %d suspect(s)" % (prg, found))
    return 1 if found else 0

if __name__ == "__main__":
    sys.exit(main())
