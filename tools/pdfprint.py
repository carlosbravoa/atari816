# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""The Atari816's print jobs as PDF files (PC link step 3; the gateway, tools/pclink.py).

A job the board sends to the PC is a file written as `Printouts/NAME.pdf` in the shared folder
whose content starts with a marker line; the gateway turns it into a real PDF when the file is
closed (Docs/04-pc-link.md, "Printing"):

    ESC "A816PRINT 1" LF
    title=TEXT LF
    date=YYYY-MM-DD HH:MM LF
    LF
    the job's text (Latin-1; LF or CR LF line ends; FF starts a new page)

The PDF: A4, the built-in Courier font at 10 points (80 columns, 58 lines a page), margins of
2 cm, a small header on every page (the title, the date, the page number). Long lines are
wrapped, tabs go to the next multiple of 8, characters Courier cannot show become '?'. Only the
Python standard library."""

MARK = b"\x1bA816PRINT 1\n"

PAGE_W, PAGE_H = 595.28, 841.89          # A4 in points
MARGIN = 56.69                           # 2 cm
SIZE, LEAD = 10, 12                      # Courier 10 pt: 6 pt a character
COLS = 80
HEAD = 2 * LEAD                          # the header line and a blank one
ROWS = int((PAGE_H - 2 * MARGIN - HEAD) // LEAD)   # 58


def is_job(data):
    return data.startswith(MARK)


def parse(data):
    """The marked file -> (title, date, text as str)."""
    rest = data[len(MARK):]
    title, date = "", ""
    while True:
        nl = rest.find(b"\n")
        if nl < 0:
            line, rest = rest, b""
        else:
            line, rest = rest[:nl], rest[nl + 1:]
        line = line.rstrip(b"\r")
        if not line:
            break
        k, _, v = line.partition(b"=")
        if k == b"title":
            title = v.decode("latin-1")
        elif k == b"date":
            date = v.decode("latin-1")
    return title, date, rest.decode("latin-1")


def _clean(ch):
    o = ord(ch)
    return ch if 32 <= o < 127 or 160 <= o < 256 else "?"


def pages(text):
    """The text -> a list of pages, each a list of lines of at most COLS characters."""
    out, page = [], []

    def put(line):
        nonlocal page
        if len(page) == ROWS:
            out.append(page)
            page = []
        page.append(line)

    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if text.endswith("\n"):
        text = text[:-1]
    for raw in text.split("\n"):
        parts = raw.split("\f")
        for i, part in enumerate(parts):
            if i:                                         # a form feed: a new page
                out.append(page)
                page = []
            if not part and len(parts) > 1:
                continue
            line = ""
            for ch in part:
                if ch == "\t":
                    line += " " * (8 - len(line) % 8)
                else:
                    line += _clean(ch)
                while len(line) > COLS:
                    put(line[:COLS])
                    line = line[COLS:]
            put(line.rstrip())
    out.append(page)
    while len(out) > 1 and not out[-1]:
        out.pop()
    return out


def _esc(s):
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("latin-1")


def make_pdf(title, date, text):
    """The PDF file's bytes."""
    pl = pages(text)
    objs = []                                             # object n + 1 = objs[n]
    objs.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objs.append(None)                                     # the page tree (below)
    objs.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")
    kids = []
    for n, lines in enumerate(pl):
        y = PAGE_H - MARGIN - SIZE
        head = f"Page {n + 1} of {len(pl)}"
        right = (date + "   " if date else "") + head
        c = [b"BT /F1 8 Tf",
             b"%.2f %.2f Td (" % (MARGIN, y) + _esc(title[:60]) + b") Tj ET",
             b"BT /F1 8 Tf %.2f %.2f Td (" % (PAGE_W - MARGIN - 4.8 * len(right), y) + _esc(right) + b") Tj ET",
             b"BT /F1 %d Tf %d TL %.2f %.2f Td" % (SIZE, LEAD, MARGIN, y - HEAD)]
        for line in lines:
            c.append(b"(" + _esc(line) + b") '")
        c.append(b"ET")
        stream = b"\n".join(c)
        objs.append(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream")
        content = len(objs)
        objs.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>"
                    % (PAGE_W, PAGE_H, content))
        kids.append(len(objs))
    objs[1] = b"<< /Type /Pages /Kids [" + b" ".join(b"%d 0 R" % k for k in kids) + b"] /Count %d >>" % len(kids)
    info = len(objs) + 1
    objs.append(b"<< /Title (" + _esc(title) + b") /Producer (Atari816 gateway) >>")
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offs = []
    for i, o in enumerate(objs):
        offs.append(len(out))
        out += b"%d 0 obj\n" % (i + 1) + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for o in offs:
        out += b"%010d 00000 n \n" % o
    out += b"trailer\n<< /Size %d /Root 1 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, info, xref)
    return bytes(out)


def convert(data):
    """A marked job -> the PDF's bytes (None if data is not a marked job)."""
    if not is_job(data):
        return None
    return make_pdf(*parse(data))
