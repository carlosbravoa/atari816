#!/usr/bin/env python3
"""run.py - the C SDK's tests: build each test with hcc, run it in emu816, check it.

    python3 sdk/c/tests/run.py [--horizon DIR] [--code small|large] [--only NAME ...]

Every test runs in both code models: small (hcc's default) and large (hcc --code large,
with --main-room 0 --bank-room 8192: every function that can move goes to another bank,
a bank holds at most 8 KB of code, so calls, pointers, callbacks, helpers and setjmp all
cross banks); --code chooses one. Prints one line per test and code model (PASS / FAIL
and a detail) and a summary; exit code 1 when anything failed. Build output and the
emulator's runs: sdk/c/build/tests/<small|large>/.
Tests (in tests/):
  libc     the C library: printf formats, string.h, stdlib, malloc, files (create, write,
           seek, read back, append, delete, the 5th handle), folders, time, far memory,
           errno, argv, keyboard input (scanf, fgets on stdin), atexit
  sys      every syscall stub linked, the safe ones called, the blocks' sizes
  codegen  code generation trouble spots (32-bit loads from tables)
  float    floating point (tests/float/float.c): arithmetic, conversions, math.h, printf
           %f %e %g, strtod, sscanf and scanf %f
  ieee     IEEE 754's edges (tests/float/ieee.c: rounding ties, overflow, underflow, NaN
           compares, -0.0, conversions at the limits, printf's digits, strtod, math.h's
           special values)
  fpu      the floating point bit for bit (tests/fpu: genfp.py's table of + - * /
           compares conversions, genfmt.py's printf and strtod against glibc, math.h
           against the same C built for the host); nofloat: a program without floating
           point links none of it
  ll       long long and setjmp (tests/ll/llbench.c): the time of one operation and its
           checks; noll: a program without long long links none of its code (no 64-bit
           helpers, no %lld in printf), one with long long and printf links them
  stack    the stack guard (the software stack: an overflow is reported by the entry check
           with the function's name); stackbig: a big structure returned by value in a
           6 KB software stack (hcc --stack 6144): the compile's frame warnings, the check
           stops it before the heap; stackdbg: --debug's report
  bench    the benchmark, its six check values (-O2 and -O1)
  fbench   a floating-point benchmark (tests/bench/fbench.c: a Mandelbrot row, sin and
           cos, sqrt, exp log pow, conversions): its times and the program's size
  rt       the tuned runtime against host-made tables (tests/rt/run.py)
  hcc      the driver's messages: a compile error with file:line, a program too big for
           its bank, an undefined function, options it does not have (no emulator)
  bigprog  the large code model on its own (tests/bigprog): a program with 180 KB of
           code, the messages, the failed starts
  ui       the controls library from C (tests/ui/uitest.c, uitest.script; desktop mode):
           every kind of argument and result of the bindings, the callbacks, the controls,
           dialogs and events; pixel checks of its screenshots; the block's size
  uibad    the binding's checks stop a program with a message (tests/ui/badhui.c: a
           control routine called in a callback; a control given as a local works)
  uitwin   sdk/templates/c-window-app against sdk/templates/window-app (assembly): both
           scripted tests, then their screenshots compared pixel by pixel
  appsdoc  the code blocks of docs/c/apps.md (the tutorial) are in examples/guests/stepN.c
           as written (no emulator; make -C examples/guests test runs the steps)
  apps     (Horizon 0.29) apps (tests/apps): hcc --needs refuses bad lists; CWIN (C, a
           window, --needs horizon=0.29,mem=256K) and ASMAPP (assembly, HZ_NEEDS: 0.29 and
           Lau) packed with sdk/tools/hzapp.py (check, pack, list: no warning), installed
           with the Installer (install -y), started from their folders; the needs refused:
           Horizon 0.99, the OPL2 on REV 11, Lau on REV 9 (console and desktop)
"""
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
SDK = os.path.dirname(SDKC)
HCC = os.path.join(SDKC, "bin", "hcc")
RUN816 = os.path.join(SDK, "tools", "run816.py")
BENCH_CHECKS = ["1899", "27824", "1071602483", "17711", "3160", "4275534039"]

results = []


def report(name, model, ok, detail=""):
    results.append((name, model, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'}  {name:<8} {model:<6} {detail}", flush=True)


# the configurations, the code models: (name, hcc's options)
LARGE_CODE = ["--code", "large", "--main-room", "0", "--bank-room", "8192"]
CONFIGS = {"small": [], "large": LARGE_CODE}


def sh(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.returncode, r.stdout.decode("latin-1")


def hcc(out, srcs, model, extra=()):
    """model: a configuration (small, large)"""
    return sh([sys.executable, HCC] + CONFIGS[model] + ["-o", out] + list(extra) + list(srcs))


def emu(prg, outdir, horizon, args=None, script=None, seconds=6, expect=(), mode="shell"):
    cmd = [sys.executable, RUN816, prg, "--horizon", horizon, "--mode", mode,
           "--seconds", str(seconds), "--out", outdir]
    if args:
        cmd += ["--args", args]
    if script:
        cmd += ["--script", script]
    for e in expect:
        cmd += ["--expect", e]
    rc, out = sh(cmd)
    con = ""
    p = os.path.join(outdir, "console.txt")
    if os.path.exists(p):
        con = open(p, encoding="latin-1").read()
        # only what the program printed: from its command line on
        i = con.rfind("> /APPS/")
        if i >= 0:
            con = con[i:]
    return rc, con, out


def grab(con, pattern):
    m = re.search(pattern, con)
    return m.group(0) if m else ""


def fpu_test(b, horizon, model="small"):
    """the floating point bit for bit: the runtime, the conversions, printf, strtod and
    math.h against tables (tests/fpu); a program without float links none of it"""
    fpu = os.path.join(HERE, "fpu")
    tab, txt, mtab = (os.path.join(b, n) for n in ("FPTAB.BIN", "FMTTAB.TXT", "MATHTAB.BIN"))
    for cmd in ([sys.executable, os.path.join(fpu, "genfp.py"), tab, "--cases", "2500"],
                [sys.executable, os.path.join(fpu, "genfmt.py"), txt, "--cases", "1500"],
                ["sh", os.path.join(fpu, "mathhost.sh"), "100000", mtab]):
        rc, out = sh(cmd)
        if rc:
            report("fpu", model, False, f"{os.path.basename(cmd[1])}: " +
                   out.strip()[-200:])
            return
        if "mathhost" in cmd[1]:
            acc = out
    prg = os.path.join(b, "FPTEST.PRG")
    rc, out = hcc(prg, [os.path.join(fpu, "fptest.c")], model)
    if rc:
        report("fpu", model, False, "build: " + out.strip().splitlines()[-1])
        return
    cmd = [sys.executable, RUN816, prg, "--horizon", horizon, "--mode", "shell", "--seconds",
           "600", "--out", os.path.join(b, "run-fpu"), "--file", tab + ":/FPTAB.BIN",
           "--file", txt + ":/FMTTAB.TXT", "--file", mtab + ":/MATHTAB.BIN"]
    sh(cmd)
    con = open(os.path.join(b, "run-fpu", "console.txt"), encoding="latin-1").read()
    ok = "FPU PASS" in con and "[kill]" not in con
    worst = max((int(w) for w in re.findall(r"worst\s+(\d+) ulp", acc)), default=-1)
    report("fpu", model, ok, grab(con, r"fpu: \d+ cases, \d+ failures") +
           f"; math.h within {worst} ulp of glibc (100,000 arguments a function)" +
           ("" if ok else " | " + " | ".join(l.strip() for l in con.splitlines()
                                             if l.startswith("  ") or "failures" in l
                                             and " 0 failures" not in l)[:400]))
    # a program without floating point: no float runtime, no float printf
    src = os.path.join(b, "nofloat.c")
    with open(src, "w") as f:
        f.write('#include <stdio.h>\n#include <stdlib.h>\nint main(void)\n{\n'
                '    printf("%d %s\\n", atoi("42"), "x");\n    return 0;\n}\n')
    rc, out = hcc(os.path.join(b, "NOFLOAT.PRG"), [src], model, ["--map"])
    mp = os.path.join(b, "NOFLOAT.map")
    names = open(mp, encoding="latin-1").read() if os.path.exists(mp) else ""
    fl = [n for n in ("__fadd", "__fmul", "___hz_fmtfp", "__fpack", "__cc816_fmtf", "__cc816_scanf")
          if re.search(r"\b" + n + r"\b", names)]
    size = grab(out, r"[\d,]+ bytes on the card")
    # a program with float arithmetic but no printf or scanf: no float formatting
    src2 = os.path.join(b, "noprintf.c")
    with open(src2, "w") as f:
        f.write('#include <horizon.h>\n#include <math.h>\nvolatile float x = 2.0f;\n'
                'int main(void)\n{\n    hz_puts(sqrt(x) * 3.0f > 4.0f ? "big" : "small");\n'
                '    return 0;\n}\n')
    rc2, out2 = hcc(os.path.join(b, "NOPRINTF.PRG"), [src2], model, ["--map"])
    mp2 = os.path.join(b, "NOPRINTF.map")
    names2 = open(mp2, encoding="latin-1").read() if os.path.exists(mp2) else ""
    fl2 = [n for n in ("___hz_fmtfp", "___hz_scanfp", "_strtod", "__cc816_fmtf")
           if re.search(r"\b" + n + r"\b", names2)]
    ok = rc == 0 and not fl and names != "" and rc2 == 0 and not fl2 and "__fmul" in names2
    report("nofloat", model, ok,
           f"a program without float links no float code ({size}); one with float but no "
           f"printf no float printf ({grab(out2, r'[\d,]+ bytes on the card')})"
           if ok else f"links {fl} {fl2} {(out + out2).strip()[-120:]}")


def ll_test(b, horizon, model="small"):
    """long long and setjmp: tests/ll/llbench.c's times and checks; the 64-bit code only
    in programs that use long long"""
    prg = os.path.join(b, "LLBENCH.PRG")
    rc, out = hcc(prg, [os.path.join(HERE, "ll", "llbench.c")], model, ["--map"])
    if rc:
        report("ll", model, False, "build: " + out.strip().splitlines()[-1])
        return
    mp = os.path.join(b, "LLBENCH.map")
    names = open(mp, encoding="latin-1").read() if os.path.exists(mp) else ""
    rc, con, _ = emu(prg, os.path.join(b, "run-ll"), horizon, seconds=40)
    times = re.findall(r"^(\w+)\s+(\d+) us", con, re.M)
    ok = "llbench done" in con and "check 488427781 6640827 1500000026624" in con and \
        len(times) == 12 and all(re.search(r"\b" + n + r"\b", names)
                                 for n in ("__mul64", "__udiv64", "___hz_fmtll", "_setjmp"))
    report("ll", model, ok, " ".join(f"{n} {t}" for n, t in times) + " us" +
           ("" if ok else " " + " | ".join(l for l in con.splitlines() if "check" in l)))
    src = os.path.join(b, "noll.c")
    with open(src, "w") as f:
        f.write('#include <stdio.h>\n#include <stdlib.h>\nint main(void)\n{\n'
                '    long x = atol("123456789");\n    printf("%ld %lu %d\\n", x * 3, '
                '(unsigned long)x / 7, (int)sizeof x);\n    return 0;\n}\n')
    rc, out = hcc(os.path.join(b, "NOLL.PRG"), [src], model, ["--map"])
    mp = os.path.join(b, "NOLL.map")
    names = open(mp, encoding="latin-1").read() if os.path.exists(mp) else ""
    ll = [n for n in ("__mul64", "__udiv64", "__shl64", "___hz_fmtll", "___hz_scanll",
                      "__cc816_fmtll", "___lltof") if re.search(r"\b" + n + r"\b", names)]
    size = grab(out, r"[\d,]+ bytes on the card")
    report("noll", model, rc == 0 and names != "" and not ll,
           f"a program without long long links none of its code ({size})" if not ll
           else f"links {ll}")


def allsys(path):
    names = []
    for ln in open(os.path.join(SDKC, "include", "hzsys.h")):
        m = re.match(r"^\w+ (hz_\w+)\(", ln)
        if m:
            names.append(m.group(1))
    with open(path, "w") as f:
        f.write("/* generated by tests/run.py: every syscall function of hzsys.h */\n")
        f.write("#include <horizon.h>\n")
        f.write("void (*hz_all_syscalls[])(void) = {\n")
        for n in names:
            f.write(f"    (void (*)(void)){n},\n")
        f.write("};\n")
        f.write(f"unsigned hz_all_count = {len(names)};\n")
    return len(names)


def run_model(model, horizon, only):
    b = os.path.join(SDKC, "build", "tests", model)
    os.makedirs(b, exist_ok=True)
    T = lambda *p: os.path.join(HERE, *p)  # noqa: E731
    want = lambda n: not only or n in only  # noqa: E731

    if want("libc"):
        prg = os.path.join(b, "LIBC.PRG")
        rc, out = hcc(prg, [T("libc", "libc.c")], model)
        if rc:
            report("libc", model, False, "build: " + out.strip().splitlines()[-1])
        else:
            rc, con, _ = emu(prg, os.path.join(b, "run-libc"), horizon, args='one "two words" 3',
                             script=T("libc", "input.script"), seconds=8)
            ok = "LIBC PASS" in con and "atexit ran" in con and "[kill]" not in con
            report("libc", model, ok, grab(con, r"libc: \d+ checks, \d+ failures") +
                   ("" if ok else " " + " | ".join(l for l in con.splitlines() if "FAIL" in l)))

    if want("sys"):
        prg = os.path.join(b, "SYS.PRG")
        n = allsys(os.path.join(b, "allsys.c"))
        rc, out = hcc(prg, [T("sys", "sys.c"), os.path.join(b, "allsys.c")], model)
        if rc:
            report("sys", model, False, "build: " + out.strip().splitlines()[-1])
        else:
            rc, con, _ = emu(prg, os.path.join(b, "run-sys"), horizon, seconds=4)
            ok = "SYS PASS" in con and "[kill]" not in con
            report("sys", model, ok, f"{n} stubs linked, " + grab(con, r"syscalls called: \d+") +
                   ", " + grab(con, r"sys: \d+ checks, \d+ failures") +
                   ("" if ok else " " + " | ".join(l for l in con.splitlines() if "FAIL" in l)))

    if want("codegen"):
        prg = os.path.join(b, "CODEGEN.PRG")
        rc, out = hcc(prg, [T("codegen", "codegen.c")], model)
        if rc:
            report("codegen", model, False, "build: " + out.strip().splitlines()[-1])
        else:
            rc, con, _ = emu(prg, os.path.join(b, "run-codegen"), horizon, seconds=2)
            ok = "CODEGEN PASS" in con
            report("codegen", model, ok, grab(con, r"codegen: \d+ checks, \d+ failures") +
                   ("" if ok else " " + " | ".join(l for l in con.splitlines() if "FAIL" in l)))

    if want("float"):
        prg = os.path.join(b, "FLOAT.PRG")
        rc, out = hcc(prg, [T("float", "float.c")], model, ["--map"])
        if rc:
            report("float", model, False, "build: " + out.strip().splitlines()[-1])
        else:
            size = grab(out, r"[\d,]+ bytes on the card")
            rc, con, _ = emu(prg, os.path.join(b, "run-float"), horizon, args="2.5 -1e3",
                             script=T("float", "input.script"), seconds=8)
            ok = "FLOAT PASS" in con and "[kill]" not in con
            report("float", model, ok, grab(con, r"float: \d+ checks, \d+ failures") +
                   f" (program {size})" +
                   ("" if ok else " " + " | ".join(l for l in con.splitlines() if "FAIL" in l)))
        if True:
            prg = os.path.join(b, "IEEE.PRG")
            rc, out = hcc(prg, [T("float", "ieee.c")], model, ["--map"])
            if rc:
                report("ieee", model, False, "build: " + out.strip().splitlines()[-1])
            else:
                size = grab(out, r"[\d,]+ bytes on the card")
                rc, con, _ = emu(prg, os.path.join(b, "run-ieee"), horizon, seconds=8)
                ok = "IEEE PASS" in con and "[kill]" not in con
                report("ieee", model, ok, grab(con, r"ieee: \d+ checks, \d+ failures") +
                       f" (program {size})" +
                       ("" if ok else " " + " | ".join(l for l in con.splitlines()
                                                         if "FAIL" in l)))

    if want("fpu"):
        fpu_test(b, horizon, model)

    if want("ll"):
        ll_test(b, horizon, model)

    if want("stack"):
        prg = os.path.join(b, "STACK.PRG")
        rc, out = hcc(prg, [T("stack", "stack.c")], model)
        if not rc:
            rc, con, _ = emu(prg, os.path.join(b, "run-stack"), horizon, seconds=3)
            # 200 levels of ~70 bytes: more than the 8 KB software stack (the array is
            # there): the entry check of depth's frame stops it (rt/crt0.s ___hz_sovf)
            overflow = "software stack overflow: depth needs a frame of" in con
            ok = overflow and "result" not in con
            report("stack", model, ok, "overflow reported" if overflow else "no overflow, guard intact")
        else:
            report("stack", model, False, "build: " + out.strip().splitlines()[-1])
        # a structure returned by value in a 6 KB stack: stopped at big_atlas's entry; the
        # warnings of its two frames (over 1 KB) at the compile
        prg = os.path.join(b, "STACKBIG.PRG")
        rc, out = hcc(prg, [T("stack", "stackbig.c")], model, ["--stack", "6144"])
        if not rc:
            rc, con, _ = emu(prg, os.path.join(b, "run-stackbig"), horizon, seconds=3)
            m = re.search(r"software stack overflow: big_atlas needs a frame of (\d+) bytes; "
                          r"(\d+) of the software stack's 6144 bytes are free", con)
            warned = "'big_atlas' needs a software-stack frame of 2,500 bytes" in out and \
                "'main' needs a software-stack frame of" in out
            ok = bool(m) and "survived" not in con and "calling big_atlas" in con and warned
            report("stackbig", model, ok, (m.group(0) if m else "no overflow reported") +
                   ("" if warned else "; the frame warnings missing"))
        else:
            report("stackbig", model, False, "build: " + out.strip().splitlines()[-1])
        prg = os.path.join(b, "STACKD.PRG")
        rc, out = hcc(prg, [T("stack", "stack.c")], model, ["--debug"])
        if not rc:
            rc, con, _ = emu(prg, os.path.join(b, "run-stackd"), horizon, args="ok", seconds=3)
            m = re.search(r"stack: (\d+) of (\d+) bytes used", con)
            m2 = re.search(r"software stack: (\d+) of (\d+) bytes used", con)
            m3 = re.search(r"heap: (\d+) of (\d+) bytes used at most", con)
            ok = bool(m and m2 and m3) and "overflow" not in con
            report("stackdbg", model, ok, (m.group(0) if m else "no report") +
                   (", " + m2.group(0) if m2 else "") + (", " + m3.group(0) if m3 else ""))
        else:
            report("stackdbg", model, False, "build: " + out.strip().splitlines()[-1])

    if want("bench"):
        # the default (-O2) and -O1
        for opt in ("-O2", "-O1"):
            name = "bench" if opt == "-O2" else "bench" + opt
            prg = os.path.join(b, "BENCH.PRG")
            rc, out = hcc(prg, [T("bench", "bench_hz.c"), T("bench", "bench.c")], model, [opt])
            if rc:
                report(name, model, False, "build: " + out.strip().splitlines()[-1])
                continue
            rc, con, _ = emu(prg, os.path.join(b, "run-" + name), horizon, seconds=40)
            missing = [c for c in BENCH_CHECKS if f"check {c}" not in con]
            times = re.findall(r"^(\w+)\s+(\d+) ms", con, re.M)
            ok = "bench done" in con and not missing
            report(name, model, ok, " ".join(f"{n} {t}" for n, t in times) + " ms" +
                   ("" if ok else f" missing checks {missing}"))

    if want("fbench"):
        prg = os.path.join(b, "FBENCH.PRG")
        rc, out = hcc(prg, [T("bench", "fbench.c")], model, ["--map"])
        if rc:
            report("fbench", model, False, "build: " + out.strip().splitlines()[-1])
        else:
            size = grab(out, r"[\d,]+ bytes on the card")
            rc, con, _ = emu(prg, os.path.join(b, "run-fbench"), horizon, seconds=60)
            times = re.findall(r"^(\w+)\s+(\d+) ms", con, re.M)
            ok = "fbench done" in con and len(times) == 5
            report("fbench", model, ok, " ".join(f"{n} {t}" for n, t in times) + " ms" +
                   f" (program {size})")

    rt = os.path.join(HERE, "rt", "run.py")
    if want("rt"):
        rc, out = sh([sys.executable, rt, "--code", model, "--horizon", horizon,
                      "--out", os.path.join(b, "rt")])
        lines = [l for l in out.splitlines() if l.strip()]
        summary = [l for l in lines if re.match(r"^rt \w+", l)]
        report("rt", model, rc == 0, f"{len(summary)} operations" +
               ("" if rc == 0 else ": " + " | ".join(l for l in lines if "FAIL" in l)[:300]))


def hcc_messages(only, models):
    """the driver's messages (no emulator)"""
    if only and "hcc" not in only:
        return
    b = os.path.join(SDKC, "build", "tests", "hcc")
    os.makedirs(b, exist_ok=True)
    W = lambda n, t: (open(os.path.join(b, n), "w").write(t), os.path.join(b, n))[1]  # noqa: E731
    bad = W("bad.c", "int main(void)\n{\n    int x = ;\n    return 0;\n}\n")
    big = W("big.c", "char big[70000u / 2], big2[70000u / 2];\n"
                     "int main(void) { big[1] = big2[2]; return 0; }\n")
    undef = W("undef.c", "void nosuch(void);\nint main(void) { nosuch(); return 0; }\n")
    undef2 = W("undef2.c", "void nosuch(void);\nstatic int helper(int x) { return x + 1; }\n"
               "int (*fp)(int) = helper;\nint main(void) { nosuch(); return fp(1); }\n")
    for m in models:
        # a compile error: file:line
        rc, out = hcc(os.path.join(b, "BAD.PRG"), [bad], m)
        ok = rc != 0 and re.search(r"bad\.c:3(:\d+)?: error", out) is not None
        report("hcc", m, ok, "compile error reported as bad.c:3" if ok else out.strip()[:200])
        # too big for the code bank
        rc, out = hcc(os.path.join(b, "BIG.PRG"), [big], m)
        ok = rc != 0 and "does not fit in its code bank" in out
        report("hcc", m, ok, "too big: " + (grab(out, r"by [\d,]+ bytes|= [\d,]+ bytes; a code bank holds [\d,]+")
                                            or out.strip()[:200]))
        # an undefined function: said in C terms
        rc, out = hcc(os.path.join(b, "UNDEF.PRG"), [undef], m)
        ok = rc != 0 and "undefined: nosuch" in out
        report("hcc", m, ok, "undefined function reported as 'undefined: nosuch'" if ok
               else out.strip()[:200])
        # ... and only it, also beside functions whose address is taken (the large model's
        # thunks: they were all listed as undefined; the Prince of Persia port)
        rc, out = hcc(os.path.join(b, "UNDEF2.PRG"), [undef2], m)
        ok = rc != 0 and "undefined: nosuch" in out and "helper" not in out
        report("hcc", m, ok, "undefined beside address-taken functions: only 'nosuch'" if ok
               else out.strip()[:200])
    if "small" in models:
        # options hcc does not have: one plain line; long long and float are built (-lm
        # accepted), what is not supported is one plain line with file:line (a VLA)
        rc, out = hcc(os.path.join(b, "BAD.PRG"), [undef], "small", ["--model", "tiny"])
        rc1, out1 = hcc(os.path.join(b, "BAD.PRG"), [undef], "small", ["--cc", "vbcc"])
        ok1 = rc != 0 and "unknown option --model" in out and rc1 != 0 and \
            "unknown option --cc" in out1
        ll = W("ll.c", "int main(void)\n{\n    long long x = 1;\n    return (int)x;\n}\n")
        rc, out = hcc(os.path.join(b, "LL.PRG"), [ll], "small")
        ok2 = rc == 0
        vla = W("vla.c", "int f(int n)\n{\n    int a[n];\n    a[0] = n;\n    return a[0];\n}\n"
                "int main(void) { return f(1); }\n")
        rc, out5 = hcc(os.path.join(b, "VLA.PRG"), [vla], "small")
        ok2 = ok2 and rc != 0 and re.search(r"vla\.c:3(:\d+)?: error: cc816 does not support "
                                            r"variable-length arrays", out5) is not None
        out += out5
        fl = W("fl.c", "int main(void)\n{\n    float f = 2;\n    return (int)f;\n}\n")
        rc, out3 = hcc(os.path.join(b, "FL.PRG"), [fl], "small", ["-lm"])
        ok3 = rc == 0
        fs = W("fs.c", "int main(void)\n{\n    float f = 2;\n    switch (f) { default: ; }\n"
               "    return 0;\n}\n")
        rc, out4 = hcc(os.path.join(b, "FS.PRG"), [fs], "small")
        ok4 = rc != 0 and re.search(r"fs\.c:4(:\d+)?: error: switch on a value that is not an integer",
                                    out4) is not None
        report("hcc", "options", ok1 and ok2 and ok3 and ok4, "--model and --cc refused as "
               "unknown options, a VLA refused with file:line, long long and float built, a "
               "float switch refused" if ok1 and ok2 and ok3 and ok4
               else (out1 + out + out3 + out4).strip()[-200:])


def bigprog(only, horizon):
    """the large code model (hcc --code large) on its own: a program with about 180 KB of
    code (tests/bigprog/genbig.py: 1,600 functions calling each other directly, through
    pointers and recursively across banks) refused by the small model with the advice and
    built and run by the large one (its output checked line by line); the messages (data
    too big even for --code large, objects of the two code models mixed); and the start's
    failures: the file cut short, its trailer damaged or wrong, the other banks of another
    build, no memory for the banks (tests/bigprog/memhog.c); and its start by path from
    another folder (absolute and relative) and from the Desktop: one file, found by
    task_path wherever it is"""
    want = lambda n: not only or n in only  # noqa: E731
    if not want("bigprog"):
        return
    b = os.path.join(SDKC, "build", "tests", "bigprog")
    os.makedirs(b, exist_ok=True)
    gen = os.path.join(b, "gen")
    rc, out = sh([sys.executable, os.path.join(HERE, "bigprog", "genbig.py"), gen])
    if rc:
        report("bigprog", "big", False, "genbig: " + out.strip()[-200:])
        return
    srcs = [os.path.join(gen, f) for f in sorted(os.listdir(gen)) if f.endswith(".c")]
    rc, out = sh([sys.executable, HCC, "-o", os.path.join(b, "BIGS.PRG")] + srcs)
    ok = rc != 0 and "program too big by" in out and "build with --code large" in out
    report("bigprog", "small", ok, "the small model: " + (grab(out, r"program too big by [\d,]+ "
                                                              r"bytes: build with --code large")
                                                         if ok else out.strip()[-200:]))
    prg = os.path.join(b, "BIGL.PRG")
    rc, out = sh([sys.executable, HCC, "--code", "large", "--map", "-o", prg] + srcs)
    if rc:
        report("bigprog", "big", False, "build: " + out.strip()[-300:])
        return
    banks = re.search(r"in (\d+) other bank", out)
    exp = open(os.path.join(gen, "expected.txt")).read().splitlines()

    def ran(con):
        got = [ln.strip() for ln in con.splitlines()]
        return [e for e in exp if e not in got]
    rc, con, _ = emu(prg, os.path.join(b, "run-big"), horizon, seconds=20)
    missing = ran(con)
    one = not os.path.exists(os.path.join(b, "BIGL.PRX")) and os.path.getsize(prg) > 0xFFFF
    ok = not missing and banks is not None and int(banks.group(1)) >= 2 and one and \
        "[kill]" not in con
    report("bigprog", "big", ok, (f"{len(exp)} lines as computed; "
                                + grab(out, r"[\d,]+ bytes of movable code in the main bank, "
                                            r"[\d,]+ in \d+ other bank\(s\)") + "; one file of "
                                + f"{os.path.getsize(prg):,} bytes ("
                                + grab(out, r"the o65 [\d,]+ bytes") + ")")
           if ok else "missing: " + " | ".join(missing[:4]) + " " + con.strip()[-200:])
    # started by its path from elsewhere: it finds its own file (task_path, Horizon 0.28)
    # wherever it is; before, its .PRX was looked for in the current folder and a fixed list
    for tag, mode, cd, what in (("bypath", "shell", None, "by its absolute path from /"),
                                ("relpath", "shell", "/GAMES", "by a relative path from /GAMES"),
                                ("desktop", "desktop", None, "from the Desktop's Programs menu")):
        cmd = [sys.executable, RUN816, prg, "--horizon", horizon, "--mode", mode,
               "--seconds", "20", "--out", os.path.join(b, "run-" + tag),
               "--dest", "/GAMES/MINE/BIGL.PRG"]
        if cd:
            cmd += ["--cd", cd]
        sh(cmd)
        p = os.path.join(b, "run-" + tag, "console.txt")
        con = open(p, encoding="latin-1").read() if os.path.exists(p) else ""
        missing = ran(con)
        report("bigprog", tag, not missing and "[kill]" not in con,
               f"/GAMES/MINE/BIGL.PRG {what}: {len(exp)} lines as computed" if not missing
               else "missing: " + " | ".join(missing[:4]) + " " + con.strip()[-200:])
    # the start's failures: the file cut short, its trailer damaged, the banks of another build
    fails = os.path.join(b, "fail")
    shutil.rmtree(fails, ignore_errors=True)
    os.makedirs(fails)
    whole = open(prg, "rb").read()
    at = int.from_bytes(whole[-8:-4], "little")
    alone = os.path.join(fails, "BIGL.PRG")
    for tag, data, what in (("cut", whole[:-1000], "the file cut short"),
                            ("damaged", whole[:-2] + b"XX", "its trailer damaged"),
                            ("tail", whole[:-8] + (at + 2).to_bytes(4, "little") + b"HZPX",
                             "the trailer pointing to the wrong place")):
        open(alone, "wb").write(data)
        rc, con, _ = emu(alone, os.path.join(b, "run-" + tag), horizon, seconds=4)
        ok = "cut short or damaged" in con and "big done" not in con and "[kill]" not in con
        report("bigprog", tag, ok, what + ": " + (grab(con, r"cut short or damaged[^\n]*")
                                                 if ok else con.strip()[-200:]))
    # (another build: the same sources at -O1; the same build would have the same stamp):
    # its o65 with the other banks of the first build
    other = os.path.join(fails, "OTHER.PRG")
    rc, out = sh([sys.executable, HCC, "--code", "large", "-O1", "-o", other] + srcs)
    o2 = open(other, "rb").read()
    at2 = int.from_bytes(o2[-8:-4], "little")
    open(alone, "wb").write(o2[:at2] + whole[at:-8] + at2.to_bytes(4, "little") + b"HZPX")
    rc, con, _ = emu(alone, os.path.join(b, "run-otherbuild"), horizon, seconds=4)
    ok = "of another build" in con and "big done" not in con and "[kill]" not in con
    report("bigprog", "otherbld", ok, "the other banks of another build refused" if ok
           else (out + con).strip()[-200:])
    hog = os.path.join(b, "MEMHOG.PRG")
    rc, out = sh([sys.executable, HCC, "-o", hog, os.path.join(HERE, "bigprog", "memhog.c")])
    if rc:
        report("bigprog", "nomem", False, "build: " + out.strip()[-200:])
    else:
        cmd = [sys.executable, RUN816, hog, "--horizon", horizon, "--mode", "shell",
               "--seconds", "8", "--out", os.path.join(b, "run-nomem"), "--args",
               "/APPS/BIGL.PRG", "--file", prg + ":/APPS/BIGL.PRG"]
        sh(cmd)
        p = os.path.join(b, "run-nomem", "console.txt")
        con = open(p, encoding="latin-1").read() if os.path.exists(p) else ""
        ok = "not enough memory" in con and "ended with code 1" in con and \
            "big done" not in con and "[kill]" not in con
        report("bigprog", "nomem", ok, ("no memory: " + grab(con, r"memhog: \d+ banks taken, \d+ "
                                                              r"free") + "; "
                                      + grab(con, r"not enough memory[^\n]*"))
               if ok else con.strip()[-300:])
    # the messages
    W = lambda n, t: (open(os.path.join(b, n), "w").write(t), os.path.join(b, n))[1]  # noqa: E731
    # a file of 300 functions (more than cc816 gives segments of their own in one module:
    # they share them, 3 a segment), compiled with -c into an ar65 library, every function
    # in other banks: each function's address in the main bank must still be right
    g2 = os.path.join(b, "gen300")
    rc, out = sh([sys.executable, os.path.join(HERE, "bigprog", "genbig.py"), g2, "--funcs",
                  "300", "--files", "1", "--seed", "7"])
    objs = []
    for f in ("big0.c", "bigmain.c"):
        o = os.path.join(b, "g300_" + f[:-2] + ".o")
        rc2, out2 = sh([sys.executable, HCC, "--code", "large", "-c", "-o", o,
                        os.path.join(g2, f)])
        rc |= rc2
        out += out2
        objs.append(o)
    lib = os.path.join(b, "g300.lib")
    if os.path.exists(lib):
        os.remove(lib)
    rc2, out2 = sh([os.environ.get("AR65") or "ar65", "a", lib, objs[0]])
    rc |= rc2
    gprg = os.path.join(b, "G300.PRG")
    rc2, out2 = sh([sys.executable, HCC, "--code", "large", "--main-room", "0", "--map", "-o",
                    gprg, objs[1], lib])
    if rc or rc2:
        report("bigprog", "grouped", False, "build: " + (out + out2).strip()[-300:])
    else:
        rc, con, _ = emu(gprg, os.path.join(b, "run-g300"), horizon, seconds=10)
        exp = open(os.path.join(g2, "expected.txt")).read().splitlines()
        missing = [e for e in exp if e not in [ln.strip() for ln in con.splitlines()]]
        report("bigprog", "grouped", not missing, "300 functions in one library module, "
               + grab(out2, r"[\d,]+ in \d+ other bank\(s\)") + ", "
               + grab(out2, r"\d+ thunks") if not missing else
               "missing: " + " | ".join(missing[:3]) + " " + con.strip()[-200:])
    # a 16-bit address of a function in another bank written in assembly (in the main bank)
    # is refused (ld65's o65 output would cut it silently); __T_name is the right one
    cf = W("trunc.c", "int sqx(int x) { return x * x; }\nextern int (*tab_x[1])(int);\n"
                      "int main(void) { return tab_x[0](3) == 9 ? 0 : 1; }\n")
    for name, sym in (("trunc", "_sqx"), ("truncok", "__T_sqx")):
        sf = W(name + ".s", f"\t.p816\n\t.import {sym}\n\t.export _tab_x\n"
                            f"\t.segment \"RODATA\"\n_tab_x:\t.addr {sym}\n")
        rc, out = sh([sys.executable, HCC, "--code", "large", "--main-room", "0", "-o",
                      os.path.join(b, name.upper() + ".PRG"), cf, sf])
        if name == "trunc":
            ok1 = rc != 0 and "a value that depends on where code is" in out and \
                "__T_name" in out
            o1 = out
        else:
            rc2, con, _ = emu(os.path.join(b, "TRUNCOK.PRG"), os.path.join(b, "run-tok"),
                              horizon, seconds=3)
            ok2 = rc == 0 and "[kill]" not in con
            o2 = out + con
    report("bigprog", "truncate", ok1 and ok2, "a function's 16-bit address in assembly: "
           "_name refused, __T_name works" if ok1 and ok2 else (o1 + o2).strip()[-300:])
    # a program whose code all fits in the main bank: one file, no loader
    one = W("one.c", "#include <stdio.h>\nstatic int sq(int x) { return x * x; }\n"
                     "int (*fp)(int) = sq;\nint main(void)\n{\n"
                     "    printf(\"one: %d\\n\", fp(12) + sq(3));\n    return 0;\n}\n")
    oprg = os.path.join(b, "ONE.PRG")
    rc, out = sh([sys.executable, HCC, "--code", "large", "--map", "-o", oprg, one])
    if rc:
        report("bigprog", "onefile", False, "build: " + out.strip()[-200:])
    else:
        rc, con, _ = emu(oprg, os.path.join(b, "run-one"), horizon, seconds=3)
        ok = "one: 153" in con and "no other banks to load" in out and \
            open(oprg, "rb").read()[-4:] != b"HZPX"
        report("bigprog", "onefile", ok, "everything in the main bank: one file, no loader ("
               + grab(out, r"[\d,]+ bytes on the card") + ")" if ok else
               (out + con).strip()[-300:])
    big = W("bigdata.c", "char big[30000], big2[30000];\n"
                         "int main(void) { big[1] = big2[2]; return 0; }\n")
    rc, out = sh([sys.executable, HCC, "--code", "large", "-o", os.path.join(b, "BD.PRG"), big])
    ok = rc != 0 and "does not fit in its code bank (the main bank)" in out
    report("bigprog", "bigdata", ok, "data too big for the main bank: said" if ok
           else out.strip()[-200:])
    small = W("small.c", "int main(void) { return 0; }\n")
    rc, out = sh([sys.executable, HCC, "-o", os.path.join(b, "big.o"), "-c", small])
    rc2, out2 = sh([sys.executable, HCC, "--code", "large", "-o", os.path.join(b, "MX.PRG"),
                    os.path.join(b, "big.o")])
    rc3, out3 = sh([sys.executable, HCC, "--code", "large", "-o", os.path.join(b, "bigl.o"),
                    "-c", small])
    rc4, out4 = sh([sys.executable, HCC, "-o", os.path.join(b, "MX.PRG"),
                    os.path.join(b, "bigl.o")])
    ok = rc == 0 and rc3 == 0 and rc2 != 0 and rc4 != 0 and \
        "made for the small code model" in out2 and "made for the large code model" in out4
    report("bigprog", "mixed", ok, "objects of the other code model refused" if ok
           else (out2 + out4).strip()[-300:])


# pixels of uitest's screenshots (1280 x 720): (shot, x, y, RGB, what)
UI_PIXELS = [
    (1, 112, 181, (200, 52, 44), "row 0's icon, drawn by the row function (C_RED)"),
    (1, 112, 237, (255, 255, 255), "row 2's icon on the selection (C_WHITE)"),
    (1, 400, 236, (204, 206, 210), "row 2 selected, the list without the focus (C_LIGHT)"),
    (1, 400, 208, (255, 255, 255), "row 1 not selected (white)"),
    (6, 400, 264, (52, 100, 204), "row 3 selected by a click, the list focused (C_SELECT)"),
    (6, 112, 237, (200, 52, 44), "row 2's icon, not selected any more (C_RED)"),
]


def pixel_checks(outdir, table):
    try:
        from PIL import Image
    except ImportError:
        return ["(PIL not installed: no pixel checks)"], 0
    bad, n = [], 0
    for shot, x, y, rgb, what in table:
        p = os.path.join(outdir, f"shot{shot}.png")
        if not os.path.exists(p):
            bad.append(f"no shot{shot}.png")
            continue
        got = Image.open(p).convert("RGB").getpixel((x, y))
        n += 1
        if tuple(got) != rgb:
            bad.append(f"shot{shot} ({x},{y}) {what}: {got}, not {rgb}")
    return bad, n


def run_ui(horizon, only, m="small"):
    """The controls library from C (in a code model)."""
    want = lambda n: not only or n in only  # noqa: E731
    b = os.path.join(SDKC, "build", "tests", "ui-" + m)
    os.makedirs(b, exist_ok=True)
    T = lambda *p: os.path.join(HERE, *p)  # noqa: E731

    if want("ui"):
        prg = os.path.join(b, "UITEST.PRG")
        rc, out = hcc(prg, [T("ui", "uitest.c")], m, ["--map"])
        if rc:
            report("ui", m, False, "build: " + out.strip().splitlines()[-1])
        else:
            blk = "program " + grab(out, r"[\d,]+ bytes on the card")
            od = os.path.join(b, "run-ui")
            rc, con, _ = emu(prg, od, horizon, script=T("ui", "uitest.script"), seconds=45,
                             mode="desktop")
            want_lines = ["UITEST: click 1, name 'Ada'", "UITEST: list sel 3",
                          "UITEST: list open 3", "UITEST: vscroll 13", "UITEST: alert 0",
                          "UITEST: ask 0 'blue'", "UITEST: dialog OK 'x'", "UITEST: popup 1",
                          "UITEST: saved '/UITEST.TXT'", "UITEST: open '/UITEST.TXT'",
                          "UITEST: dropped '/DROPPED.TXT'", "UITEST: 3 ticks",
                          "UITEST: launch -1, error $44", "UITEST: ui_open -1",
                          "UITEST: popat 1"]
            con = open(os.path.join(od, "console.txt"), encoding="latin-1").read() \
                if os.path.exists(os.path.join(od, "console.txt")) else ""
            missing = [w for w in want_lines if w not in con]
            bad, n = pixel_checks(od, UI_PIXELS)
            ok = "UITEST PASS" in con and "[kill]" not in con and not missing and \
                not [x for x in bad if not x.startswith("(")]
            report("ui", m, ok, grab(con, r"uitest: \d+ checks, \d+ failures") +
                   f", {len(want_lines) - len(missing)} events, {n} pixels; {blk}" + ("" if ok else " | " + " | ".join(
                       [l for l in con.splitlines() if "FAIL" in l] + missing + bad)))

    if want("uibad"):
        prg = os.path.join(b, "BADHUI.PRG")
        rc, out = hcc(prg, [T("ui", "badhui.c")], m)
        if rc:
            report("uibad", m, False, "build: " + out.strip().splitlines()[-1])
        else:
            for arg, text in (("ptr", "hui: ui_draw: ctl: not in the code bank"),
                              ("cb", "hui: ui_lsset: a control routine called inside a "
                                     "callback")):
                rc, con, _ = emu(prg, os.path.join(b, "run-bad" + arg), horizon, args=arg,
                                 seconds=4)
                i, j = con.find("BADHUI: start"), con.find(text)
                if arg == "ptr":
                    # a local is in the code bank too (the software stack): allowed
                    ok = i >= 0 and "BADHUI: not stopped" in con and "hui:" not in con \
                        and "[kill]" not in con
                    report("uibad", m, ok, "ptr: a local control works (locals are in the "
                           "code bank)" if ok else con.strip()[-200:])
                    continue
                ok = 0 <= i < j and "not stopped" not in con
                report("uibad", m, ok, f"{arg}: " + (text if ok else con.strip()[-200:]))

    if want("appsdoc") and m == "small":
        doc = os.path.join(SDK, "docs", "c", "apps.md")
        guests = os.path.join(SDKC, "examples", "guests")
        cur, blk, inblk, bad, n = None, [], False, [], 0
        for ln in open(doc, encoding="utf-8"):
            mm = re.search(r"From `(step\d\.c)`:", ln)
            if mm:
                cur = mm.group(1)
            elif ln.startswith("## "):
                cur = None
            elif ln.startswith("```c") and cur:
                inblk, blk = True, []
            elif ln.startswith("```") and inblk:
                inblk = False
                n += 1
                if "".join(blk) not in open(os.path.join(guests, cur)).read():
                    bad.append(f"a block of {cur} ({blk[0].strip()[:40]}...)")
            elif inblk:
                blk.append(ln)
        report("appsdoc", "-", n > 0 and not bad, f"{n} code blocks as in the step files"
               if not bad else "not in the files: " + " | ".join(bad))

    if want("uitwin"):
        tpl = os.path.join(SDK, "templates")
        res = []
        for d in ("c-window-app", "window-app"):
            rc, out = sh(["make", "--no-print-directory", "-C", os.path.join(tpl, d), "test",
                          "HORIZON=" + horizon] +
                         (["HZ_CODE=large", "HCCFLAGS=" + " ".join(LARGE_CODE[2:])]
                          if m == "large" and d == "c-window-app" else []))
            res.append((d, rc, out))
        bad = [f"{d}: make test failed: {out.strip()[-200:]}" for d, rc, out in res if rc]
        n = 0
        if not bad:
            try:
                from PIL import Image, ImageChops
                for i in range(1, 6):
                    a = Image.open(os.path.join(tpl, "window-app", "build", "test",
                                                f"shot{i}.png")).convert("RGB")
                    c = Image.open(os.path.join(tpl, "c-window-app", "build", "test",
                                                f"shot{i + 1}.png")).convert("RGB")
                    # (Files' status line shows the time a file changed: not compared)
                    # (the menu bar's free memory: the large program's code bank; (Horizon
                    # 0.29) and in any model a moment's memory: the Desktop samples it
                    # every 5 s, and a program being loaded then holds the loader's bank)
                    for im in (a, c):
                        im.paste((0, 0, 0), (0, 480, 680, 512))
                        im.paste((0, 0, 0), (900, 0, 1280, 24))
                    box = ImageChops.difference(a, c).getbbox()
                    n += 1
                    if box:
                        bad.append(f"shot {i}: differs in {box}")
            except ImportError:
                bad.append("(PIL not installed: screenshots not compared)")
        report("uitwin", m, not [x for x in bad if not x.startswith("(")],
               f"both templates' tests pass; {n} screenshots identical" if not bad
               else " | ".join(bad))


def apps_tools(d, hza, app, checkout, horizon):
    """(Horizon 0.29) hzapp.py: the program's needs into the archive's APP.INF (added when
    missing, --needs-from-program when different), check printing them, the icon command;
    its built-in icon names and palette against Horizon's sources and sdk/docs/apps.md"""
    import tarfile
    report("apps", "hzapp", "CWIN.PRG checks: horizon=0.29,mem=256K" in checkout,
           "check prints the program's needs")
    inf0 = open(os.path.join(app, "APP.INF")).read()
    nn = os.path.join(d, "NONEEDS", "CWIN")
    shutil.copytree(app, nn)
    open(os.path.join(nn, "APP.INF"), "w").write(
        "".join(ln for ln in inf0.splitlines(True) if not ln.startswith("needs=")))

    def packed_inf(folder, hzaname, extra=()):
        out = os.path.join(d, hzaname)
        rc, o = sh(hza + ["pack", folder, "-o", out] + list(extra))
        txt = ""
        if rc == 0:
            with tarfile.open(out) as tf:
                txt = tf.extractfile("CWIN/APP.INF").read().decode("latin-1")
        return rc, o, txt
    rc, o, txt = packed_inf(nn, "NONEEDS.HZA")
    ok = (rc == 0 and "needs=horizon=0.29,mem=256K\n" in txt and "warning" not in o and
          "needs=" not in open(os.path.join(nn, "APP.INF")).read())
    report("apps", "hzapp", ok, "pack: APP.INF without needs= gets the program's in the "
           "archive (the folder's file unchanged)" + ("" if ok else ": " + o[-300:]))
    df = os.path.join(d, "DIFFER", "CWIN")
    shutil.copytree(app, df)
    open(os.path.join(df, "APP.INF"), "w").write(inf0.replace("needs=horizon=0.29,mem=256K",
                                                              "needs=horizon=0.28"))
    rc1, o1, t1 = packed_inf(df, "DIFFER1.HZA")
    rc2, o2, t2 = packed_inf(df, "DIFFER2.HZA", ["--needs-from-program"])
    ok = (rc1 == 0 and "warning: APP.INF says needs=horizon=0.28, but CWIN.PRG checks "
          "horizon=0.29,mem=256K" in o1 and "needs=horizon=0.28\n" in t1 and
          rc2 == 0 and "warning" not in o2 and "needs=horizon=0.29,mem=256K\n" in t2 and
          t2.count("needs=") == 1)
    report("apps", "hzapp", ok, "pack: a different needs= is a warning; --needs-from-program "
           "replaces it" + ("" if ok else ": " + o1[-200:] + o2[-200:]))
    # the icon: a picture with alpha -> 32 x 32 bytes of the palette, 255 transparent
    try:
        from PIL import Image
        im = Image.new("RGBA", (62, 62), (0, 0, 0, 0))   # (halved: pixel art, 31 + shadow)
        for y in range(8, 54):
            for x in range(8, 54):
                im.putpixel((x, y), (250, 5, 0, 255) if x < 32 else (0, 0, 250, 255))
        png, icn = os.path.join(d, "art.png"), os.path.join(d, "ART.ICN")
        im.save(png)
        rc, o = sh(hza + ["icon", png, icn])
        ic = open(icn, "rb").read() if rc == 0 else b""
        ok = (len(ic) == 1024 and ic[0] == 255 and ic[16 * 32 + 6] == 196 and
              ic[16 * 32 + 24] == 21 and set(ic) == {255, 196, 21, 15} and
              ic[27 * 32 + 27] == 15 and ic[28 * 32 + 28] == 255)
        report("apps", "hzapp", ok, "icon: a 62 x 62 PNG -> 1024 bytes (red 196, blue 21, "
               "transparent 255, the shadow 15)" + ("" if ok else ": " + o[-300:]))
        ia = os.path.join(d, "ICONAPP", "CWIN")
        shutil.copytree(app, ia)
        shutil.copy(icn, os.path.join(ia, "ART.ICN"))
        open(os.path.join(ia, "APP.INF"), "a").write("icon=ART.ICN\n")
        rc1, o1 = sh(hza + ["check", ia])
        open(os.path.join(ia, "APP.INF"), "a").write("icon=nosuch\n")
        rc2, o2 = sh(hza + ["check", ia])
        report("apps", "hzapp", rc1 == 0 and "warning" not in o1 and "icon=nosuch is neither"
               in o2, "check: icon= a file of 1024 bytes; a name that is neither: a warning")
    except ImportError:
        report("apps", "hzapp", False, "icon: no Pillow")
    # the built-in icon names: hzapp.py's list, the Desktop's (desk.s apinames), apps.md's
    sys.path.insert(0, os.path.join(SDK, "tools"))
    import hzapp
    src = open(os.path.join(horizon, "user", "desk.s"), encoding="latin-1").read()
    blk = src[src.index("apinames:"):]
    blk = blk[:blk.index("        .byte   0\n")]
    desk = re.findall(r'"([a-z]+)", 0, ICO_', blk)
    doc = open(os.path.join(SDK, "docs", "apps.md"), encoding="utf-8").read()
    row = [ln for ln in doc.splitlines() if ln.startswith("| `icon` |")]
    docnames = re.findall(r"`([a-z]+)`", row[0].split("built-in icon", 1)[1].split(")", 1)[0]) \
        if row else []
    ok = desk == hzapp.BUILTIN_ICONS and sorted(docnames) == sorted(desk)
    report("apps", "hzapp", ok, f"the {len(desk)} built-in icon names: hzapp.py, the Desktop "
           f"and apps.md agree" + ("" if ok else f": desk {desk} hzapp {hzapp.BUILTIN_ICONS} "
                                   f"doc {docnames}"))
    import ast                          # (as horizon/tools/mkicons.py reads it)
    psrc = open(os.path.join(horizon, "tools", "mkpalette.py")).read()
    ui = ast.literal_eval(re.sub(r"#.*", "", re.search(r"^ui = (\[.*?^\])", psrc,
                                                        re.S | re.M).group(1)))
    pal = ([c for _, c in ui] + [(r * 51, g * 51, b * 51) for r in range(6) for g in range(6)
                                 for b in range(6)] + [(8 + 10 * i,) * 3 for i in range(24)])
    report("apps", "hzapp", pal == hzapp.PALETTE,
           "hzapp.py's palette is Horizon's (tools/mkpalette.py)")


def run_apps(horizon, only, models):
    """(Horizon 0.29) apps: hcc --needs, hzapp.py, the Installer, the needs checked at the
    start (tests/apps)"""
    if only and "apps" not in only:
        return
    src = os.path.join(HERE, "apps")
    hza = [sys.executable, os.path.join(SDK, "tools", "hzapp.py")]
    cwin = os.path.join(src, "cwin.c")
    b = os.path.join(SDKC, "build", "tests", "apps")
    shutil.rmtree(b, ignore_errors=True)
    os.makedirs(b)
    for bad, msg in (("horizon=1", "a version such as 0.29"), ("warp", "unknown need"),
                     ("mem=99M", "65535K at most")):
        rc, out = sh([sys.executable, HCC, "--needs", bad, "-o", os.path.join(b, "X.PRG"), cwin])
        report("apps", "hcc", rc != 0 and msg in out, f"--needs {bad}: refused")
    # ASMAPP: the assembly SDK's way (ca65 + ld65 + ulib.o)
    user = os.path.join(horizon, "user")
    asm = os.path.join(b, "ASMAPP")
    os.makedirs(asm)
    rc1, o1 = sh(["ca65", "-I", user, "-o", os.path.join(b, "asmapp.o"),
                  os.path.join(src, "asmapp.s")])
    rc2, o2 = sh(["ld65", "-C", os.path.join(user, "prog.cfg"), "-o",
                  os.path.join(asm, "ASMAPP.PRG"), os.path.join(b, "asmapp.o"),
                  os.path.join(horizon, "build", "ulib.o")])
    shutil.copy(os.path.join(src, "ASMAPP.INF"), os.path.join(asm, "APP.INF"))
    report("apps", "asm", rc1 == 0 and rc2 == 0, "ASMAPP assembled (HZ_NEEDS)" + o1 + o2)
    for m in models:
        d = os.path.join(b, m)
        app = os.path.join(d, "CWIN")
        os.makedirs(app)
        rc, out = hcc(os.path.join(app, "CWIN.PRG"), [cwin], m,
                      ["--needs", "horizon=0.29", "--needs", "mem=256K"])
        shutil.copy(os.path.join(src, "CWIN.INF"), os.path.join(app, "APP.INF"))
        rv, outv = hcc(os.path.join(d, "CNEEDV.PRG"), [cwin], m, ["--needs", "horizon=0.99"])
        ro, outo = hcc(os.path.join(d, "CNEEDO.PRG"), [cwin], m, ["--needs", "opl2"])
        report("apps", m, rc == 0 and rv == 0 and ro == 0, "CWIN, CNEEDV, CNEEDO built with "
               "--needs" + ("" if rc == 0 else ": " + out[-300:]))
        if rc:
            continue
        # hzapp.py: check (the needs block read from the program: no warning), pack, list
        rc, out = sh(hza + ["check", app])
        okc = rc == 0 and out.strip().endswith("hzapp: OK")
        rc, out2 = sh(hza + ["pack", app, "-o", os.path.join(d, "CWIN.HZA"), "--mtime", "1793000000"],
                      cwd=d)
        rc3, out3 = sh(hza + ["list", os.path.join(d, "CWIN.HZA")])
        rc4, out4 = sh(hza + ["pack", asm, "-o", os.path.join(d, "ASMAPP.HZA")], cwd=d)
        report("apps", m, okc and rc == 0 and rc3 == 0 and "CWIN.PRG" in out3 and
               "needs: horizon=0.29,mem=256K" in out3 and rc4 == 0 and "warning" not in out4,
               "hzapp.py check, pack, list (CWIN, ASMAPP)" +
               ("" if okc else ": " + out[-300:]))
        if m == models[0]:
            apps_tools(d, hza, app, out, horizon)
        # the Installer (shell): both installed, then started from their folders
        inst = os.path.join(horizon, "build", "sd", "BIN", "INSTALL.PRG")
        scr = os.path.join(d, "install.script")
        # (each step waits for the line before it: the Installer's "install: installed
        # /APPS/NAME", the programs' own)
        open(scr, "w").write("0 wait install: installed /APPS/CWIN\n"
                             "+500 install -y /ASMAPP.HZA\\n\n"
                             "+0 wait install: installed /APPS/ASMAPP\n"
                             "+500 /APPS/CWIN/CWIN.PRG\\n\n+0 wait cwin: done\n"
                             "+500 /APPS/ASMAPP/ASMAPP.PRG\\n\n+0 wait asmapp: running\n")
        sh([sys.executable, RUN816, inst, "--horizon", horizon, "--mode", "shell",
            "--dest", "/BIN/INSTALL.PRG", "--args", "-y /CWIN.HZA", "--script", scr,
            "--seconds", "20", "--out", os.path.join(d, "run-install"),
            "--file", os.path.join(d, "CWIN.HZA") + ":/CWIN.HZA",
            "--file", os.path.join(d, "ASMAPP.HZA") + ":/ASMAPP.HZA"])
        p = os.path.join(d, "run-install", "console.txt")
        con = open(p, encoding="latin-1").read() if os.path.exists(p) else ""
        exp = ["C App is installed", "Assembly App is installed",
               "install: installed /APPS/CWIN", "install: installed /APPS/ASMAPP",
               "cwin: in /APPS/CWIN/, current folder /, Horizon 0.30", "cwin: done",
               "asmapp: running"]
        miss = [e for e in exp if e not in con]
        report("apps", m, not miss and os.path.isdir(os.path.join(d, "run-install", "card",
                                                                  "APPS", "CWIN")),
               "installed with install -y, started" + (f": missing {miss}" if miss else ""))
        # started from the Desktop, in its folder
        sh([sys.executable, RUN816, os.path.join(app, "CWIN.PRG"), "--horizon", horizon,
            "--mode", "desktop", "--dest", "/APPS/CWIN/CWIN.PRG", "--seconds", "5",
            "--out", os.path.join(d, "run-desk")])
        p = os.path.join(d, "run-desk", "console.txt")
        con = open(p, encoding="latin-1").read() if os.path.exists(p) else ""
        report("apps", m, "cwin: done" in con and "Horizon 0.30" in con,
               "CWIN on the Desktop (its window, then its end)")
        # the needs refused (console; the Desktop: the message window too)
        for prg, rev, want, mode in (
                ("CNEEDV.PRG", None, "CNEEDV needs Horizon 0.99 or later (this is 0.30).", "shell"),
                ("CNEEDV.PRG", None, "CNEEDV needs Horizon 0.99 or later (this is 0.30).", "desktop"),
                ("CNEEDO.PRG", "11", "CNEEDO needs the OPL2 sound chip (hardware revision $0C).", "shell"),
                ("CNEEDO.PRG", None, "cwin: in", "shell")):
            out_dir = os.path.join(d, f"run-{prg[:-4].lower()}-{mode}-{rev or 'def'}")
            cmd = [sys.executable, RUN816, os.path.join(d, prg), "--horizon", horizon,
                   "--mode", mode, "--seconds", "4", "--out", out_dir]
            if rev:
                cmd += ["--rev", rev]
            if mode == "desktop":
                cmd += ["--shot", "2"]
            sh(cmd)
            p = os.path.join(out_dir, "console.txt")
            con = open(p, encoding="latin-1").read() if os.path.exists(p) else ""
            report("apps", m, want in con, f"{prg} ({mode}{', REV ' + rev if rev else ''}): "
                   f"{want}")
    out_dir = os.path.join(b, "run-asm-rev9")
    sh([sys.executable, RUN816, os.path.join(asm, "ASMAPP.PRG"), "--horizon", horizon,
        "--mode", "shell", "--seconds", "3", "--rev", "9", "--out", out_dir])
    p = os.path.join(out_dir, "console.txt")
    con = open(p, encoding="latin-1").read() if os.path.exists(p) else ""
    want = "ASMAPP needs Lau, the sample player (hardware revision $0A or later)."
    report("apps", "asm", want in con, f"ASMAPP on REV 9: {want}")


def main():
    a = sys.argv[1:]
    horizon = os.environ.get("HORIZON") or os.path.join(SDK, "..", "horizon")
    models = list(CONFIGS)
    only = []
    i = 0
    while i < len(a):
        if a[i] == "--horizon":
            horizon = a[i + 1]; i += 2
        elif a[i] == "--only":
            only.append(a[i + 1]); i += 2
        elif a[i] == "--code" and i + 1 < len(a) and a[i + 1] in CONFIGS:
            models = [a[i + 1]]; i += 2
        else:
            sys.exit(__doc__)
    horizon = os.path.abspath(horizon)
    if not os.path.exists(os.path.join(horizon, "build", "sd", "SYSTEM", "HORIZON.SYS")):
        sys.exit(f"run.py: no built Horizon card in {horizon}/build/sd (make -C {horizon})")
    t0 = time.time()
    hcc_messages(only, models)
    # the code models side by side (each has its own build folder; the libraries are
    # built first, one after another, so no two of them build the same one)
    sh([sys.executable, HCC, "--build-lib"] + models)
    if "large" in models:
        bigprog(only, horizon)
    import concurrent.futures as cf
    with cf.ThreadPoolExecutor(len(models)) as ex:
        list(ex.map(lambda m: run_model(m, horizon, only), models))
    for m in models:
        run_ui(horizon, only, m)
    run_apps(horizon, only, models)
    bad = [r for r in results if not r[2]]
    print(f"\nC SDK tests: {len(results) - len(bad)} passed, {len(bad)} failed "
          f"({time.time() - t0:.0f} s)")
    print("C SDK TESTS PASSED" if not bad else "C SDK TESTS FAILED")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
