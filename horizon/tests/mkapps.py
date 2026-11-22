#!/usr/bin/env python3
"""mkapps.py MODE BUILD CARD - (0.29) the apps tests' files on a card copy (make test-29).

BUILD holds the test programs: apptest.prg (no needs), needv.prg, needm.prg, needo.prg,
needok.prg (user/apptest.s with -D), apscan.prg. The archives are made here with Python's
tarfile (ustar, as sdk/tools/hzapp.py makes them), and the broken ones by hand.

MODE shell   /T: the archives for the text shell session (tests/app29.keys): GOOD.HZA and
             GOOD2.HZA (its update: DATA.TXT changed, NEW.TXT added; the user's SAVE.DAT
             must stay), SPACE.HZA (a folder "My Game (2)"), PAX.HZA (pax headers: skipped),
             and the refused ones: BADSUM (a header's checksum), CUT (cut in a file's data),
             DOTDOT (a ".." part), ABS (an absolute name), TWO (two top folders), NOINF (no
             APP.INF), NOPRG (no program), GNU (a GNU long name), LINK (a symbolic link),
             BADCH (a '?' in a name); the needs programs NEEDV.PRG ... NEEDOK.PRG; SAVE.DAT.
MODE desk1   two apps (/APPS/ONE: its icon a file, ONE.ICN; /APPS/TWO: icon=calc; no
             category) with a shortcut to each on the desktop, /ZZGAMES.HZA and /ZZGAMEB.HZA
             (GAMEA, GAMEB: category Games; GAMEA opens .ZZT) and /ZZDOC.ZZT for the Desktop
             session (tests/app29d.src).
MODE desk20  twenty apps (18 without a category, two in Games), and the odd ones: BROKEN
             (APP.INF of junk, BROKEN.PRG: listed by its folder name), NOPROG (program= a
             file that is not there: left out), NOINF (no APP.INF, NOINF.PRG: listed),
             LOOSE.PRG right in /APPS (listed), .HIDDEN (left out); NEEDV (needs 0.99) for
             the needs window; APSCAN.PRG in /T.
MODE scan20  twenty apps only, and /T/APSCAN.PRG (the scan time)."""
import io
import os
import shutil
import sys
import tarfile

mode, build, card = sys.argv[1:4]


def prg(name):
    return open(os.path.join(build, name), "rb").read()


def tar(path, members, fmt=tarfile.USTAR_FORMAT, pax=None):
    """members: [(name, bytes | None for a folder | ('link', target))]"""
    with tarfile.open(path, "w", format=fmt) as tf:
        for name, data in members:
            ti = tarfile.TarInfo(name)
            ti.mtime = 1793000000
            ti.uid = ti.gid = 0
            if pax:
                ti.pax_headers = dict(pax)
            if data is None:
                ti.type = tarfile.DIRTYPE
                ti.mode = 0o755
                tf.addfile(ti)
            elif isinstance(data, tuple):
                ti.type = tarfile.SYMTYPE
                ti.linkname = data[1]
                tf.addfile(ti)
            else:
                ti.size = len(data)
                ti.mode = 0o644
                tf.addfile(ti, io.BytesIO(data))


def inf(**kw):
    return "".join(f"{k}={v}\n" for k, v in kw.items()).encode()


def app_dir(root, folder, prog, info, extra=()):
    d = os.path.join(root, folder)
    os.makedirs(d, exist_ok=True)
    if prog:
        open(os.path.join(d, prog[0]), "wb").write(prg(prog[1]))
    if info is not None:
        open(os.path.join(d, "APP.INF"), "wb").write(info)
    for n, data in extra:
        open(os.path.join(d, n), "wb").write(data)


apps = os.path.join(card, "APPS")
T = os.path.join(card, "T")
A = prg("apptest.prg")

if mode == "shell":
    os.makedirs(T, exist_ok=True)
    good_inf = inf(name="Good App", version="1.0", description="The apps test's app",
                   category="Games", types="ZZT", needs="horizon=0.29")
    good = [("GOOD/", None), ("GOOD/APP.INF", good_inf), ("GOOD/GOOD.PRG", A),
            ("GOOD/DATA.TXT", b"version one\n"), ("GOOD/LEVELS/", None),
            ("GOOD/LEVELS/L1.DAT", b"level one\n")]
    tar(os.path.join(T, "GOOD.HZA"), good)
    good2 = [("GOOD/", None), ("GOOD/APP.INF", good_inf.replace(b"1.0", b"2.0")),
             ("GOOD/GOOD.PRG", A), ("GOOD/DATA.TXT", b"version two\n"),
             ("GOOD/NEW.TXT", b"new in two\n"), ("GOOD/LEVELS/", None),
             ("GOOD/LEVELS/L1.DAT", b"level one, two\n"), ("GOOD/LEVELS/L2.DAT", b"level 2\n")]
    tar(os.path.join(T, "GOOD2.HZA"), good2)
    open(os.path.join(T, "SAVE.DAT"), "wb").write(b"the user's save\n")
    open(os.path.join(T, "HISCORE.DAT"), "wb").write(b"9999\n")
    # a folder name with spaces and brackets; its program found as its only .PRG
    tar(os.path.join(T, "SPACE.HZA"),
        [("My Game (2)/", None), ("My Game (2)/APP.INF", inf(name="My Game")),
         ("My Game (2)/Start Me.PRG", A), ("My Game (2)/Read me first.txt", b"hello\n")])
    # pax: the per-file headers are skipped, the ustar names used
    tar(os.path.join(T, "PAX.HZA"),
        [("PAXAPP/", None), ("PAXAPP/APP.INF", inf(name="Pax App")), ("PAXAPP/PAXAPP.PRG", A)],
        fmt=tarfile.PAX_FORMAT, pax={"comment": "a pax header"})
    raw = bytearray(open(os.path.join(T, "GOOD.HZA"), "rb").read())
    bad = bytearray(raw)
    bad[512 + 5] ^= 0x20                                    # the second header's name
    open(os.path.join(T, "BADSUM.HZA"), "wb").write(bad)
    open(os.path.join(T, "CUT.HZA"), "wb").write(raw[:512 * 4 + 300])   # in GOOD.PRG's data
    tar(os.path.join(T, "DOTDOT.HZA"), [("GOOD/", None), ("GOOD/APP.INF", good_inf),
                                       ("GOOD/GOOD.PRG", A), ("GOOD/../EVIL.TXT", b"x\n")])
    tar(os.path.join(T, "ABS.HZA"), [("/GOOD/APP.INF", good_inf), ("/GOOD/GOOD.PRG", A)])
    tar(os.path.join(T, "TWO.HZA"), [("GOOD/APP.INF", good_inf), ("GOOD/GOOD.PRG", A),
                                    ("OTHER/X.TXT", b"x\n")])
    tar(os.path.join(T, "NOINF.HZA"), [("GOOD/", None), ("GOOD/GOOD.PRG", A)])
    tar(os.path.join(T, "NOPRG.HZA"), [("GOOD/", None), ("GOOD/APP.INF", inf(name="G")),
                                      ("GOOD/DATA.TXT", b"x\n")])
    tar(os.path.join(T, "GNU.HZA"), [("GOOD/", None), ("GOOD/APP.INF", good_inf),
                                    ("GOOD/" + "L" * 110 + ".TXT", b"x\n")],
        fmt=tarfile.GNU_FORMAT)
    tar(os.path.join(T, "LINK.HZA"), [("GOOD/", None), ("GOOD/APP.INF", good_inf),
                                     ("GOOD/GOOD.PRG", A), ("GOOD/LINK", ("link", "/BIN"))])
    tar(os.path.join(T, "BADCH.HZA"), [("GOOD/", None), ("GOOD/APP.INF", good_inf),
                                      ("GOOD/WHAT?.TXT", b"x\n")])
    for n in ("needv", "needm", "needo", "needok"):
        shutil.copy(os.path.join(build, n + ".prg"), os.path.join(T, n.upper() + ".PRG"))
elif mode == "desk1":
    # an icon file: 32 x 32, 8 bpp, 255 transparent: a red disc with a white bar
    ico = bytearray([255] * 1024)
    for y in range(32):
        for x in range(32):
            d = (x - 15.5) ** 2 + (y - 15.5) ** 2
            if d < 14 ** 2:
                ico[y * 32 + x] = 0 if d > 12.5 ** 2 else (1 if 13 <= x <= 18 and 7 <= y <= 24 else 196)
    app_dir(apps, "ONE", ("ONE.PRG", "apptest.prg"),
            inf(name="One App", version="1.0", icon="ONE.ICN"), [("ONE.ICN", bytes(ico))])
    app_dir(apps, "TWO", ("TWO.PRG", "apptest.prg"), inf(name="Two", icon="calc"))
    os.makedirs(os.path.join(card, "Desktop"), exist_ok=True)
    open(os.path.join(card, "Desktop", "One.LNK"), "w").write("/APPS/ONE/ONE.PRG\ntitle=One\n")
    open(os.path.join(card, "Desktop", "Two.LNK"), "w").write("/APPS/TWO\n")
    tar(os.path.join(card, "ZZGAMES.HZA"),
        [("GAMEA/", None), ("GAMEA/APP.INF", inf(name="Game A", category="Games", types="ZZT",
                                                 description="The first game")),
         ("GAMEA/GAMEA.PRG", A)])
    tar(os.path.join(card, "ZZGAMEB.HZA"),
        [("GAMEB/", None), ("GAMEB/APP.INF", inf(name="Game B", category="Games")),
         ("GAMEB/GAMEB.PRG", A)])
    open(os.path.join(card, "ZZDOC.ZZT"), "wb").write(b"a document of type ZZT\n")
elif mode in ("desk20", "scan20"):
    names = ["Abacus", "Bricks", "Clock", "Dice", "Easel", "Fractal", "Garden", "Harbor",
             "Island", "Jigsaw", "Kite", "Lantern", "Maze", "Notes", "Orbit", "Puzzle",
             "Quiz", "Rocket", "Snake", "Tetra"]
    for i, n in enumerate(names):
        cat = "Games" if n in ("Snake", "Tetra") else None
        kw = {"name": n, "version": f"1.{i}"}
        if cat:
            kw["category"] = cat
        app_dir(apps, n.upper()[:8], (n.upper()[:8] + ".PRG", "apptest.prg"), inf(**kw))
    if mode == "desk20":
        app_dir(apps, "BROKEN", ("BROKEN.PRG", "apptest.prg"),
                b"\x00\xff junk = = =\nno equals sign here\n=value without key\n\x01\x02\n")
        app_dir(apps, "NOPROG", ("OTHER.PRG", "apptest.prg"),
                inf(name="No Program", program="MISSING.PRG"))
        app_dir(apps, "NOINF", ("NOINF.PRG", "apptest.prg"), None)
        shutil.copy(os.path.join(build, "apptest.prg"), os.path.join(apps, "LOOSE.PRG"))
        app_dir(apps, ".HIDDEN", ("HIDDEN.PRG", "apptest.prg"), inf(name="Hidden"))
        app_dir(apps, "NEEDV", ("NEEDV.PRG", "needv.prg"), inf(name="Needs 0.99"))
    os.makedirs(T, exist_ok=True)
    shutil.copy(os.path.join(build, "apscan.prg"), os.path.join(T, "APSCAN.PRG"))
else:
    sys.exit(f"mkapps: unknown mode {mode}")
