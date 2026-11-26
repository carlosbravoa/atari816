#!/usr/bin/env python3
"""run.py - hgame's tests: each test program built with hcc, run in emu816 by run816.py,
then checked: its own PASS / FAIL lines (it reads the framebuffer back, compares values),
expected console lines, the emulator's sound logs and WAV output, and its screenshots
against the reference pictures in tests/ref/ (a few differing pixels allowed).

    python3 sdk/c/game/tests/run.py [--horizon DIR] [--code small|large] [--only NAME ...]
                                    [--update-refs]

Every test runs in both code models (small, and large: hcc --code large, every function
that can move in another bank) against the SAME reference pictures; --code chooses one.
--update-refs writes the screenshots of this run as the new references (look at them
first: build/game-tests/CODE/NAME/shotN.png). Output: one line per check, PASS or FAIL,
and a summary; exit code 1 when anything failed. Runs go to
sdk/c/build/game-tests/<small|large>/.
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SDKC = os.path.dirname(GAME)
SDK = os.path.dirname(SDKC)
HCC = os.path.join(SDKC, "bin", "hcc")
RUN816 = os.path.join(SDK, "tools", "run816.py")
OUT = os.path.join(SDKC, "build", "game-tests")
REF = os.path.join(HERE, "ref")

results = []


def report(name, ok, detail=""):
    results.append((name, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {name:<16} {detail}", flush=True)


def sh(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.returncode, r.stdout.decode("latin-1")


def wav_level(path):
    """the largest absolute sample of a 16-bit WAV file (0 if missing)"""
    if not os.path.exists(path):
        return 0
    with wave.open(path) as w:
        n = w.getnframes()
        data = w.readframes(n)
    best = 0
    for (v,) in struct.iter_unpack("<h", data[: len(data) // 2 * 2]):
        if abs(v) > best:
            best = abs(v)
    return best


def compare(name, shot, ref, update):
    """screenshot against its reference: the share of differing pixels"""
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return True, "no Pillow: not compared"
    if update or not os.path.exists(ref):
        os.makedirs(REF, exist_ok=True)
        shutil.copy(shot, ref)
        return True, f"reference written ({os.path.relpath(ref, SDK)})"
    a = Image.open(shot).convert("RGB")
    b = Image.open(ref).convert("RGB")
    if a.size != b.size:
        return False, "size differs"
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v else 0)
    hist = d.histogram()
    bad = hist[255]
    share = bad / (a.size[0] * a.size[1])
    if share > 0.002:
        d.save(shot[:-4] + "-diff.png")
        return False, f"{share * 100:.2f} % of the pixels differ (see {shot[:-4]}-diff.png)"
    return True, f"{bad} pixels differ"


# name, sources, run816 options, expected console lines, checks of emu.err / the WAV
TESTS = [
    ("draw", ["gt_draw.c"], ["--shot", "3", "--seconds", "5"],
     ["gt_draw: 0 failed"], []),
    ("screens", ["gt_screens.c"], ["--script", "gt_screens.script"],
     ["gt_screens: 0 failed"], []),
    ("window", ["gt_window.c"], ["--script", "gt_window.script"],
     ["gt_window: 0 failed"], []),
    ("sprites", ["gt_sprites.c"], ["--script", "gt_sprites.script"],
     ["gt_sprites: 0 failed"], []),
    ("map", ["gt_map.c"], ["--script", "gt_map.script"],
     ["gt_map: 0 failed"], []),
    # (the ports' wishes) 16-bit tile numbers from a wide sheet; the ring for a game's own
    # drawing; the palette bank of 4 bpp sprites. Pictures at the states the programs print
    ("map16", ["gt_map16.c"], ["--script", "gt_map16.script", "--seconds", "60",
                           "--stop-on", "gt_map16: 0 failed"],
     ["gt_map16: 0 failed"], []),
    ("wrap", ["gt_wrap.c"], ["--script", "gt_wrap.script", "--seconds", "40",
                         "--stop-on", "gt_wrap: 0 failed"],
     ["gt_wrap: 0 failed"], []),
    ("sprpal", ["gt_sprpal.c"], ["--script", "gt_sprpal.script", "--seconds", "10",
                                 "--file", "{run}/SPRPAL.HGI:/SPRPAL.HGI"],
     ["gt_sprpal: 0 failed"], []),
    # what scrolling a map16 costs a frame, and the Micropolis port's way by hand (its lines
    # in console.txt)
    ("mapbench", ["gt_mapbench.c"], ["--seconds", "40", "--stop-on", "gt_mapbench: 0 failed"],
     ["gt_mapbench: 0 failed"], []),
    ("input", ["gt_input.c"], ["--script", "gt_input.script"],
     ["gt_input: 0 failed"], []),
    # each key event's modifiers: a modifier and a key changed in one batch of events
    ("keymods", ["gt_keymods.c"], ["--script", "gt_keymods.script", "--seconds", "8"],
     ["gt_keymods: 0 failed"], []),
    # the mouse's motion without a button in full screen; a program without frames: its
    # view by hg_poll and hg_view_send (the X-COM port's needs)
    ("poll", ["gt_poll.c"], ["--script", "gt_poll.script", "--seconds", "5"],
     ["gt_poll: 0 failed"], []),
    ("sound", ["gt_sound.c"], ["--script", "gt_sound.script", "--seconds", "14",
                               "--log-sound", "--log-lau",
                               "--file", "{run}/BEEP.WAV:/BEEP.WAV",
                               "--file", "{run}/BEEP16.WAV:/BEEP16.WAV"],
     ["gt_sound: 0 failed"], ["pokey", "lau", "wav"]),
    ("view", ["gt_view.c"], ["--script", "gt_view.script", "--seconds", "6", "--log-sound"],
     ["gt_view: 0 failed"], ["audctl"]),
    ("util", ["gt_util.c"], ["--seconds", "4", "--file", "{run}/TEST.HGI:/TEST.HGI"],
     ["gt_util: 0 failed"], []),
    # (0.30) runs by the blitter in one call, page flipping without waiting, hg_us; and the
    # measurement of a run's cost by each way of filling it (its lines in console.txt)
    ("runs", ["gt_runs.c"], ["--shot", "3", "--seconds", "4"],
     ["gt_runs: 0 failed"], []),
    ("runbench", ["gt_runbench.c"], ["--seconds", "20"],
     ["gt_runbench: 0 failed"], []),
    # (REV $0D) colour remapping by the blitter's table; and on REV $0C by the CPU: the same
    # checks and the same picture (remap12 is compared with remap's reference)
    ("remap", ["gt_remap.c"], ["--shot", "4", "--seconds", "6"],
     ["gt_remap: 0 failed"], []),
    ("remap12", ["gt_remap.c"], ["--shot", "4", "--seconds", "6", "--rev", "12"],
     ["gt_remap: 0 failed"], []),
    # (REV $0D) the remap as the X-COM port's night view uses it (16 x 8 cells, tall records,
    # a table every 128 records), and at every byte offset: every screen pixel against the
    # CPU's result. Also a program for the board (PASS / FAIL lines with the first wrong pixel)
    ("nightx", ["gt_nightx.c"], ["--seconds", "40", "--stop-on", "gt_nightx: 0 failed"],
     ["gt_nightx: 0 failed"], []),
]

# tests whose pictures must be another test's (the same program on another board)
REFNAME = {"remap12": "remap"}


def make_files(name, run):
    """the files a test puts on the card, made here"""
    if name == "sound":                         # a WAV file: 8-bit mono 16 kHz, 0.25 s
        with wave.open(os.path.join(run, "BEEP.WAV"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(1)
            w.setframerate(16000)
            w.writeframes(bytes(128 + (60 if (i // 20) & 1 else -60) for i in range(4000)))
        with wave.open(os.path.join(run, "BEEP16.WAV"), "wb") as w:  # 16-bit, 22,050 Hz
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(22050)
            w.writeframes(b"".join(struct.pack("<h", 8000 if (i // 25) & 1 else -8000)
                                   for i in range(2205)))
    if name == "sprpal":                        # a 4 bpp image of 16 x 16: stripes 1-15
        px = bytearray()
        for y in range(16):
            for x in range(0, 16, 2):
                a, b = 1 + (x + y) % 15, 1 + (x + 1 + y) % 15
                px.append(a << 4 | b)
        hd = b"HGI1" + struct.pack("<HHHHBBHH", 16, 16, 1, 0, 4, 0, 0, 0) + bytes(14)
        open(os.path.join(run, "SPRPAL.HGI"), "wb").write(hd + bytes(px))
    if name == "util":                          # an .HGI file from text art, by img2c.py
        art = os.path.join(run, "test.txt")
        open(art, "w").write(". = key\na = 40\nb = 41\n\naab.\nabb.\n\nbbaa\n.ab.\n")
        rc, out = sh([sys.executable, os.path.join(SDK, "tools", "img2c.py"), art, "-o",
                      os.path.join(run, "TEST.HGI"), "--own-palette", "200", "--key", "7"])
        if rc:
            print(out)


CODES = {"small": [],
         # the large code model: every function that can move in another bank
         "large": ["--code", "large", "--main-room", "0", "--bank-room", "16384"],
         # the same with far data (hcc --data far)
         "largefar": ["--code", "large", "--data", "far", "--main-room", "0",
                      "--bank-room", "16384"]}


def run_tests(cc, horizon, only, update):
    for name, srcs, opts, expect, checks in TESTS:
        if only and name not in only:
            continue
        run = os.path.join(OUT, cc, name)
        shutil.rmtree(run, ignore_errors=True)
        os.makedirs(run)
        make_files(name, run)
        prg = os.path.join(run, "GT" + name.upper()[:6] + ".PRG")
        rc, out = sh([sys.executable, HCC] + CODES[cc] + ["-o", prg] +
                     [os.path.join(HERE, s) for s in srcs])
        if rc:
            report(f"{cc}/{name}", False, "build failed:\n" + out)
            continue
        cmd = [sys.executable, RUN816, prg, "--horizon", horizon, "--out", run]
        for o in opts:
            o = o.replace("{run}", run)
            if o.endswith(".script"):
                o = os.path.join(HERE, o)
            cmd.append(o)
        if "wav" in checks:
            cmd += ["--wav", os.path.join(run, "out.wav")]
        for e in expect:
            cmd += ["--expect", e]
        rc, out = sh(cmd)
        con = open(os.path.join(run, "console.txt"), encoding="latin-1").read() \
            if os.path.exists(os.path.join(run, "console.txt")) else ""
        fails = re.findall(r"^FAIL .*$", con, re.M)
        passes = re.findall(r"^PASS .*$", con, re.M)
        hgerr = re.findall(r"^hgame: .*$", con, re.M)
        detail = f"{len(passes)} checks passed in the program"
        if fails:
            detail += "; " + "; ".join(fails)
        if rc:
            detail += "; run816: " + " | ".join(ln for ln in out.splitlines()
                                                 if ln.startswith("run816"))
        report(f"{cc}/{name}", rc == 0 and not fails and passes != [], detail)
        if hgerr and name not in ("util",):
            print("      (library messages: " + "; ".join(hgerr) + ")")
        err = open(os.path.join(run, "emu.err"), encoding="latin-1").read() \
            if os.path.exists(os.path.join(run, "emu.err")) else ""
        if "pokey" in checks:
            n = len(re.findall(r"^sound \$DB0[0-7]", err, re.M))
            report(f"{cc}/{name}/pokey", n > 0, f"{n} POKEY writes logged")
        if "audctl" in checks:
            ok = re.search(r"^sound \$DB08 = \$(50|78)", err, re.M) is not None
            report(f"{cc}/{name}/audctl", ok, "hg_note joined POKEY's channels (AUDCTL)"
                   if ok else "no AUDCTL write logged")
        if "lau" in checks:
            n = len(re.findall(r"^lau ", err, re.M))
            report(f"{cc}/{name}/lau", n > 0, f"{n} Lau writes logged")
        if "wav" in checks:
            lv = wav_level(os.path.join(run, "out.wav"))
            report(f"{cc}/{name}/wav", lv > 1000, f"the recorded output peaks at {lv} of 32767")
        for k in range(1, 17):
            shot = os.path.join(run, f"shot{k}.png")
            if not os.path.exists(shot):
                break
            ok, d = compare(name, shot, os.path.join(REF, f"{REFNAME.get(name, name)}-{k}.png"),
                            update and name not in REFNAME)
            report(f"{cc}/{name}/shot{k}", ok, d)


def main():
    a = sys.argv[1:]
    horizon = os.environ.get("HORIZON") or os.path.join(os.path.dirname(SDK), "horizon")
    only, update = [], False
    ccs = list(CODES)
    i = 0
    while i < len(a):
        if a[i] == "--horizon":
            horizon = a[i + 1]; i += 2
        elif a[i] == "--code":
            ccs = [a[i + 1]]; i += 2
            if ccs[0] not in CODES:
                sys.exit("run.py: --code is small, large or largefar")
        elif a[i] == "--only":
            only.append(a[i + 1]); i += 2
        elif a[i] == "--update-refs":
            update = True; i += 1
        else:
            sys.exit(f"run.py: unknown option {a[i]}")
    sys.path.insert(0, GAME)
    import hgbuild
    for cc in ccs:
        hgbuild.lib_for({"largefar": "large-far"}.get(cc, cc))
        run_tests(cc, horizon, only, update)
    bad = [n for n, ok in results if not ok]
    print(f"hgame tests: {len(results) - len(bad)} passed, {len(bad)} failed"
          + (": " + ", ".join(bad) if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
