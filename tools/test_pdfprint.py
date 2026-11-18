#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""Tests of pdfprint.py (python3 tools/test_pdfprint.py): pages, wrapping, form feeds, the PDF's
structure (xref offsets), and pdftotext's view of it when poppler is installed."""
import shutil
import subprocess
import tempfile
import unittest

import pdfprint


class Pages(unittest.TestCase):
    def test_wrap_tabs_ff(self):
        p = pdfprint.pages("a\tb\n" + "x" * 170 + "\nend\fnext\n\fthird\n")
        self.assertEqual(p[0], ["a       b", "x" * 80, "x" * 80, "x" * 10, "end"])
        self.assertEqual(p[1], ["next"])
        self.assertEqual(p[2], ["third"])

    def test_page_length_and_chars(self):
        p = pdfprint.pages("\n".join(str(i) for i in range(130)) + "\n\x01€é\n")
        self.assertEqual([len(x) for x in p], [58, 58, 15])
        self.assertEqual(p[2][-1], "??é")

    def test_xref(self):
        pdf = pdfprint.make_pdf("T (x)", "2026-11-18 15:30", "one\ntwo\n")
        start = int(pdf.rsplit(b"startxref\n", 1)[1].split()[0])
        self.assertTrue(pdf[start:].startswith(b"xref"))
        lines = pdf[start:].split(b"\n")
        n = int(lines[1].split()[1])
        for i in range(1, n):
            off = int(lines[2 + i].split()[0])
            self.assertTrue(pdf[off:].startswith(b"%d 0 obj" % i))
        self.assertIn(b"(T \\(x\\))", pdf)

    @unittest.skipUnless(shutil.which("pdftotext"), "pdftotext not installed")
    def test_pdftotext(self):
        job = pdfprint.MARK + b"title=Atari\ndate=2026-11-18 15:30\n\n10 PRINT \"HELLO\"\r\n20 GOTO 10\n"
        with tempfile.NamedTemporaryFile(suffix=".pdf") as f:
            f.write(pdfprint.convert(job))
            f.flush()
            out = subprocess.run(["pdftotext", "-layout", f.name, "-"], capture_output=True, text=True).stdout
        self.assertIn('10 PRINT "HELLO"', out)
        self.assertIn("20 GOTO 10", out)
        self.assertIn("Page 1 of 1", out)


if __name__ == "__main__":
    unittest.main()
