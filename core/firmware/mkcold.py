#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""mkcold.py HOT.bin COLD_RAW.bin COLD_SIG_ADDR OUT_COLD.bin

Wraps the cold image for SPI flash (header: "COLD", length, CRC-32) and patches the hot
image's cold_sig {length, crc} so the boot loader only accepts the matching cold image.
"""
import sys, struct, zlib
hot, raw, addr, out = sys.argv[1], sys.argv[2], int(sys.argv[3], 16), sys.argv[4]
c = open(raw, "rb").read()
crc = zlib.crc32(c) & 0xFFFFFFFF
h = bytearray(open(hot, "rb").read())
assert h[addr:addr + 8] == bytes(8), "cold_sig not found at 0x%x" % addr
h[addr:addr + 8] = struct.pack("<II", len(c), crc)
open(hot, "wb").write(h)
open(out, "wb").write(struct.pack("<III", 0x444C4F43, len(c), crc) + c)
print("cold image: %d bytes, crc %08x -> %s" % (len(c), crc, out))
