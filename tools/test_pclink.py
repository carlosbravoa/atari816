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


class Unfinished(unittest.TestCase):
    """Mode 2 writes a temporary file in .atari816-partial, moved into place at CLOSE."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        put(os.path.join(self.root, "old.txt"), "old")
        self.sent = []
        self.fs = pclink.FileServer(self.root, self.sent.append)
        self.partial = os.path.join(self.root, pclink.FileServer.PARTIAL)

    def req(self, op, args):
        self.sent.clear()
        self.fs.request(bytes([op, 5, 0, 0]) + args)
        return self.sent[-1][3], b"".join(p[4:] for p in self.sent)

    def create(self, name):
        r, d = self.req(pclink.F_OPEN, b"\x02\0\0\0" + name + b"\0")
        self.assertEqual(r, 0)
        self.assertEqual(struct.unpack_from("<I", d, 4)[0], 0)
        return d[0]

    def write(self, h, data):
        self.assertEqual(self.req(pclink.F_WRITE, bytes([h, 0, 0, 0]) + data)[0], 0)

    def close(self, h):
        return self.req(pclink.F_CLOSE, bytes([h, 0, 0, 0]))[0]

    def read(self, name):
        with open(os.path.join(self.root, name)) as f:
            return f.read()

    def temps(self):
        return os.listdir(self.partial) if os.path.isdir(self.partial) else []

    def test_new_file(self):
        h = self.create(b"/new.txt")
        self.write(h, b"hello")
        self.assertFalse(os.path.exists(os.path.join(self.root, "new.txt")))
        self.assertEqual(len(self.temps()), 1)
        self.assertEqual(self.close(h), 0)
        self.assertEqual(self.read("new.txt"), "hello")
        self.assertEqual(self.temps(), [])

    def test_overwrite(self):
        h = self.create(b"/OLD.TXT")                  # (found ignoring case)
        self.write(h, b"new content")
        self.assertEqual(self.read("old.txt"), "old")
        self.assertEqual(self.close(h), 0)
        self.assertEqual(self.read("old.txt"), "new content")
        self.assertFalse(os.path.exists(os.path.join(self.root, "OLD.TXT")))

    def test_read_back(self):
        h = self.create(b"/rb.bin")
        self.write(h, b"abcdef")
        self.req(pclink.F_SEEK, bytes([h, 0, 0, 0]) + struct.pack("<I", 2))
        self.assertEqual(self.req(pclink.F_READ, bytes([h, 0, 0, 0]) + struct.pack("<I", 100)),
                         (0, b"cdef"))
        self.assertEqual(self.close(h), 0)

    def test_session_end(self):
        h1 = self.create(b"/old.txt")
        h2 = self.create(b"/gone.txt")
        self.write(h1, b"half")
        self.write(h2, b"half")
        self.assertEqual(len(self.temps()), 2)
        self.fs.reset()
        self.assertEqual(self.read("old.txt"), "old")
        self.assertFalse(os.path.exists(os.path.join(self.root, "gone.txt")))
        self.assertEqual(self.temps(), [])
        self.assertEqual(self.close(h1), pclink.R_BADHANDLE)

    def test_leftovers_removed_at_start(self):
        os.mkdir(self.partial)
        put(os.path.join(self.partial, "123-1.part"), "junk")
        outside = os.path.join(self.root, "keep.txt")
        put(outside, "keep")
        os.symlink(outside, os.path.join(self.partial, "link"))
        pclink.FileServer(self.root, self.sent.append)
        self.assertEqual(os.listdir(self.partial), ["link"])   # links are not touched
        self.assertEqual(self.read("keep.txt"), "keep")
        os.unlink(os.path.join(self.partial, "link"))
        put(os.path.join(self.partial, "123-2.part"), "junk")
        pclink.FileServer(self.root, self.sent.append)
        self.assertFalse(os.path.exists(self.partial))

    def test_hidden_from_the_board(self):
        h = self.create(b"/x.txt")                    # the folder exists now
        name = b"/" + pclink.FileServer.PARTIAL.encode()
        tmp = name + b"/" + self.temps()[0].encode()
        r, d = self.req(pclink.F_READDIR, struct.pack("<HH", 0, 1000) + b"/\0")
        self.assertEqual((r, struct.unpack_from("<I", d)[0]), (0, 1))     # only old.txt
        self.assertNotIn(b"partial", d)
        for path in (name, tmp, name.upper()):
            self.assertEqual(self.req(pclink.F_STAT, path + b"\0")[0], pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_LOAD, path + b"\0")[0], pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_DELETE, path + b"\0")[0], pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_OPEN, b"\x00\0\0\0" + path + b"\0")[0],
                             pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_OPEN, b"\x02\0\0\0" + path + b"\0")[0],
                             pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_READDIR, struct.pack("<HH", 0, 1000) + path + b"\0")[0],
                             pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_RENAME, path + b"\0/y\0")[0], pclink.FR_INVALID_NAME)
            self.assertEqual(self.req(pclink.F_RENAME, b"/old.txt\0" + path + b"\0")[0],
                             pclink.FR_INVALID_NAME)
        self.assertEqual(self.close(h), 0)

    def test_open_errors(self):
        self.fs.readonly = True
        self.assertEqual(self.req(pclink.F_OPEN, b"\x02\0\0\0/ro.txt\0")[0], pclink.FR_DENIED)
        self.fs.readonly = False
        self.assertFalse(os.path.exists(os.path.join(self.root, "ro.txt")))
        os.mkdir(os.path.join(self.root, "dir"))
        self.assertEqual(self.req(pclink.F_OPEN, b"\x02\0\0\0/dir\0")[0], pclink.FR_NO_FILE)
        self.assertEqual(self.req(pclink.F_OPEN, b"\x02\0\0\0/nodir/x\0")[0], pclink.FR_NO_PATH)
        self.assertEqual(self.temps(), [])


if __name__ == "__main__":
    unittest.main()
