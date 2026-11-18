#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""Tests of pclink.py without a board: the frame format, the parser and the shared folder's
safety rules (python3 tools/test_pclink.py). The firmware side is tested against this code in
core/test/pclink_host/run_tests.py."""
import os
import struct
import tempfile
import unittest

import pclink


class Frames(unittest.TestCase):
    def test_crc(self):
        self.assertEqual(pclink.crc16(b"123456789"), 0x29B1)

    def test_roundtrip_and_garbage(self):
        p = pclink.Parser()
        a = pclink.frame(3, 7, 0, pclink.F_DATA, b"hello")
        b = pclink.frame(2, 0, 9, pclink.F_ACK)
        bad = bytearray(a)
        bad[12] ^= 1                                   # a payload byte: CRC fails
        out = p.feed(b"\x00\xa8\xa8\x16junk" + bytes(bad) + a[:5])
        out += p.feed(a[5:] + b"\xa8" + b)
        self.assertEqual([(f[0], f[1], f[2], f[3], f[4]) for f in out],
                         [(3, 7, 0, 1, b"hello"), (2, 0, 9, 2, b"")])


def put(path, text):
    with open(path, "w") as f:
        f.write(text)


class Folder(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.root = os.path.join(self.tmp, "share")
        os.mkdir(self.root)
        put(os.path.join(self.tmp, "secret.txt"), "secret")
        os.symlink(os.path.join(self.tmp, "secret.txt"), os.path.join(self.root, "link.txt"))
        os.symlink(self.tmp, os.path.join(self.root, "up"))
        os.mkdir(os.path.join(self.root, "Docs"))
        put(os.path.join(self.root, "Docs", "Read Me.txt"), "hi")
        put(os.path.join(self.root, ".hidden"), "x")
        self.sent = []
        self.fs = pclink.FileServer(self.root, self.sent.append)

    def req(self, op, args, ro=False):
        self.fs.readonly = ro
        self.sent.clear()
        self.fs.request(bytes([op, 5, 0, 0]) + args)
        data = b"".join(p[4:] for p in self.sent)
        return self.sent[-1][3], data

    def test_case_insensitive(self):
        r, d = self.req(pclink.F_STAT, b"/docs/READ ME.TXT\0")
        self.assertEqual(r, 0)
        self.assertEqual(struct.unpack_from("<I", d)[0], 2)

    def test_escapes(self):
        for path in (b"/../secret.txt", b"/Docs/../../secret.txt", b"/./Docs", b"/.hidden"):
            self.assertEqual(self.req(pclink.F_STAT, path + b"\0")[0], pclink.FR_INVALID_NAME, path)
        for path in (b"/link.txt", b"/up/secret.txt", b"/up"):
            self.assertEqual(self.req(pclink.F_STAT, path + b"\0")[0], pclink.FR_DENIED, path)
        self.assertEqual(self.req(pclink.F_OPEN, b"\x00\0\0\0/link.txt\0")[0], pclink.FR_DENIED)
        self.assertEqual(self.req(pclink.F_OPEN, b"\x02\0\0\0/up/new.txt\0")[0], pclink.FR_DENIED)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "new.txt")))
        self.assertEqual(self.req(pclink.F_RENAME, b"/Docs\0/up/x\0")[0], pclink.FR_DENIED)
        self.assertEqual(self.req(pclink.F_DELETE, b"/\0")[0], pclink.FR_DENIED)

    def test_listing(self):
        r, d = self.req(pclink.F_READDIR, struct.pack("<HH", 0, 1000) + b"/\0")
        self.assertEqual(r, 0)
        n = struct.unpack_from("<I", d)[0]
        names, i = [], 4
        for _ in range(n):
            size, attr, ln = struct.unpack_from("<IBB", d, i)
            names.append(d[i + 6:i + 6 + ln])
            i += 6 + ln
        self.assertEqual(names, [b"Docs"])            # no hidden names, no links that leave

    def test_files_and_readonly(self):
        r, d = self.req(pclink.F_OPEN, b"\x02\0\0\0/new.bin\0")
        self.assertEqual(r, 0)
        h = d[0]
        self.sent.clear()
        self.fs.request(bytes([pclink.F_WRITE, 6, pclink.MORE, 0, h, 0, 0, 0]) + b"abc")
        self.fs.request(bytes([pclink.F_WRITE, 6, 0, 0, h, 0, 0, 0]) + b"def")
        self.assertEqual(struct.unpack("<I", self.sent[-1][4:8])[0], 6)
        self.req(pclink.F_SEEK, bytes([h, 0, 0, 0]) + struct.pack("<I", 0))
        r, d = self.req(pclink.F_READ, bytes([h, 0, 0, 0]) + struct.pack("<I", 100))
        self.assertEqual(d, b"abcdef")
        self.assertEqual(self.req(pclink.F_CLOSE, bytes([h, 0, 0, 0]))[0], 0)
        self.assertEqual(self.req(pclink.F_DELETE, b"/new.bin\0", ro=True)[0], pclink.FR_DENIED)
        self.assertEqual(self.req(pclink.F_MKDIR, b"/x\0", ro=True)[0], pclink.FR_DENIED)
        self.assertEqual(self.req(pclink.F_DELETE, b"/new.bin\0")[0], 0)
        self.assertEqual(self.req(pclink.F_DELETE, b"/Docs\0")[0], pclink.FR_DENIED)   # not empty


if __name__ == "__main__":
    unittest.main()
