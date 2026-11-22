#!/usr/bin/env python3
"""run.py - the C SDK's tests: build each test with hcc, run it in emu816, check it.

    python3 sdk/c/tests/run.py [--horizon DIR] [--cc cc816|vbcc] [--model large|tiny]
                               [--only NAME ...]

Every test runs for each compiler and memory model: cc816 (one model), vbcc large, vbcc
tiny (--cc and --model choose some). Prints one line per test and configuration (PASS /
FAIL and a detail) and a summary; exit code 1 when anything failed. Build output and the
emulator's runs: sdk/c/build/tests/<cc816|large|tiny>/.
Tests (in tests/):
  libc     the C library: printf formats, string.h, stdlib, malloc, files (create, write,
           seek, read back, append, delete, the 5th handle), folders, time, far memory,
           errno, argv, keyboard input (scanf, fgets on stdin), atexit
  sys      every syscall stub linked, the safe ones called, the blocks' sizes
  codegen  the compiler's known trouble spots (32-bit loads from tables)
  float    floating point (tests/float/float.c): arithmetic, conversions, math.h, printf
           %f %e %g, strtod, sscanf and scanf %f; with cc816 also IEEE 754's edges
           (tests/float/ieee.c: rounding ties, overflow, underflow, NaN compares, -0.0,
           conversions at the limits, printf's digits, strtod, math.h's special values)
  fpu      cc816 only: its floating point bit for bit (tests/fpu: genfp.py's table of
           + - * / compares conversions, genfmt.py's printf and strtod against glibc,
           math.h against the same C built for the host), and that a program without
           floating point links none of it
  ll       cc816 only: long long and setjmp (tests/ll/llbench.c): the time of one
           operation and its checks; a program without long long links none of its code
           (no 64-bit helpers, no %lld in printf), one with long long and printf links them
  stack    the stack guard (cc816's software stack and vbcc's tiny model: an overflow is
           reported; --debug's report)
  bench    the compiler trials' benchmark, its six check values (-O1 and -O3)
  fbench   a floating-point benchmark (tests/bench/fbench.c: a Mandelbrot row, sin and
           cos, sqrt, exp log pow, conversions): its times and the program's size
  rt       the tuned runtime against host-made tables (tests/rt/run.py), when present
  hcc      the driver's messages: a compile error with file:line, a program too big for
           its bank, data too big for the tiny model's window (no emulator)
  ui       the controls library from C (tests/ui/uitest.c, uitest.script; desktop mode):
           every kind of argument and result of the bindings, the callbacks, the controls,
           dialogs and events; pixel checks of its screenshots; the block's size
  uibad    the block's checks stop a program with a message (tests/ui/badhui.c: a control
           given as a local, a control routine called in a callback)
  uitiny   the tiny model is refused: hui.h's #error, hcc --ui, a link (no emulator)
  uitwin   sdk/templates/c-window-app against sdk/templates/window-app (assembly): both
           scripted tests, then their screenshots compared pixel by pixel
  appsdoc  the code blocks of docs/c/apps.md (the tutorial) are in examples/guests/stepN.c
           as written (no emulator; make -C examples/guests test runs the steps)
"""
import os
import re
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


# the configurations: (name, hcc's compiler options)
CONFIGS = {"cc816": ["--cc", "cc816"], "large": ["--cc", "vbcc", "--model", "large"],
           "tiny": ["--cc", "vbcc", "--model", "tiny"]}


def sh(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.returncode, r.stdout.decode("latin-1")


def hcc(out, srcs, model, extra=()):
    """model: a configuration (cc816, large, tiny)"""
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


def fpu_test(b, horizon):
    """cc816's floating point bit for bit: the runtime, the conversions, printf, strtod and
    math.h against tables (tests/fpu); a program without float links none of it"""
    fpu = os.path.join(HERE, "fpu")
    tab, txt, mtab = (os.path.join(b, n) for n in ("FPTAB.BIN", "FMTTAB.TXT", "MATHTAB.BIN"))
    for cmd in ([sys.executable, os.path.join(fpu, "genfp.py"), tab, "--cases", "2500"],
                [sys.executable, os.path.join(fpu, "genfmt.py"), txt, "--cases", "1500"],
                ["sh", os.path.join(fpu, "mathhost.sh"), "100000", mtab]):
        rc, out = sh(cmd)
        if rc:
            report("fpu", "cc816", False, f"{os.path.basename(cmd[1])}: " +
                   out.strip()[-200:])
            return
        if "mathhost" in cmd[1]:
            acc = out
    prg = os.path.join(b, "FPTEST.PRG")
    rc, out = hcc(prg, [os.path.join(fpu, "fptest.c")], "cc816")
    if rc:
        report("fpu", "cc816", False, "build: " + out.strip().splitlines()[-1])
        return
    cmd = [sys.executable, RUN816, prg, "--horizon", horizon, "--mode", "shell", "--seconds",
           "600", "--out", os.path.join(b, "run-fpu"), "--file", tab + ":/FPTAB.BIN",
           "--file", txt + ":/FMTTAB.TXT", "--file", mtab + ":/MATHTAB.BIN"]
    sh(cmd)
    con = open(os.path.join(b, "run-fpu", "console.txt"), encoding="latin-1").read()
    ok = "FPU PASS" in con and "[kill]" not in con
    worst = max((int(w) for w in re.findall(r"worst\s+(\d+) ulp", acc)), default=-1)
    report("fpu", "cc816", ok, grab(con, r"fpu: \d+ cases, \d+ failures") +
           f"; math.h within {worst} ulp of glibc (100,000 arguments a function)" +
           ("" if ok else " | " + " | ".join(l.strip() for l in con.splitlines()
                                             if l.startswith("  ") or "failures" in l
                                             and " 0 failures" not in l)[:400]))
    # a program without floating point: no float runtime, no float printf
    src = os.path.join(b, "nofloat.c")
    with open(src, "w") as f:
        f.write('#include <stdio.h>\n#include <stdlib.h>\nint main(void)\n{\n'
                '    printf("%d %s\\n", atoi("42"), "x");\n    return 0;\n}\n')
    rc, out = hcc(os.path.join(b, "NOFLOAT.PRG"), [src], "cc816", ["--map"])
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
    rc2, out2 = hcc(os.path.join(b, "NOPRINTF.PRG"), [src2], "cc816", ["--map"])
    mp2 = os.path.join(b, "NOPRINTF.map")
    names2 = open(mp2, encoding="latin-1").read() if os.path.exists(mp2) else ""
    fl2 = [n for n in ("___hz_fmtfp", "___hz_scanfp", "_strtod", "__cc816_fmtf")
           if re.search(r"\b" + n + r"\b", names2)]
    ok = rc == 0 and not fl and names != "" and rc2 == 0 and not fl2 and "__fmul" in names2
    report("fpu", "nofloat", ok,
           f"a program without float links no float code ({size}); one with float but no "
           f"printf no float printf ({grab(out2, r'[\d,]+ bytes on the card')})"
           if ok else f"links {fl} {fl2} {(out + out2).strip()[-120:]}")


def ll_test(b, horizon):
    """long long and setjmp: tests/ll/llbench.c's times and checks; the 64-bit code only
    in programs that use long long"""
    prg = os.path.join(b, "LLBENCH.PRG")
    rc, out = hcc(prg, [os.path.join(HERE, "ll", "llbench.c")], "cc816", ["--map"])
    if rc:
        report("ll", "cc816", False, "build: " + out.strip().splitlines()[-1])
        return
    mp = os.path.join(b, "LLBENCH.map")
    names = open(mp, encoding="latin-1").read() if os.path.exists(mp) else ""
    rc, con, _ = emu(prg, os.path.join(b, "run-ll"), horizon, seconds=40)
    times = re.findall(r"^(\w+)\s+(\d+) us", con, re.M)
    ok = "llbench done" in con and "check 488427781 6640827 1500000026624" in con and \
        len(times) == 12 and all(re.search(r"\b" + n + r"\b", names)
                                 for n in ("__mul64", "__udiv64", "___hz_fmtll", "_setjmp"))
    report("ll", "cc816", ok, " ".join(f"{n} {t}" for n, t in times) + " us" +
           ("" if ok else " " + " | ".join(l for l in con.splitlines() if "check" in l)))
    src = os.path.join(b, "noll.c")
    with open(src, "w") as f:
        f.write('#include <stdio.h>\n#include <stdlib.h>\nint main(void)\n{\n'
                '    long x = atol("123456789");\n    printf("%ld %lu %d\\n", x * 3, '
                '(unsigned long)x / 7, (int)sizeof x);\n    return 0;\n}\n')
    rc, out = hcc(os.path.join(b, "NOLL.PRG"), [src], "cc816", ["--map"])
    mp = os.path.join(b, "NOLL.map")
    names = open(mp, encoding="latin-1").read() if os.path.exists(mp) else ""
    ll = [n for n in ("__mul64", "__udiv64", "__shl64", "___hz_fmtll", "___hz_scanll",
                      "__cc816_fmtll", "___lltof") if re.search(r"\b" + n + r"\b", names)]
    size = grab(out, r"[\d,]+ bytes on the card")
    report("ll", "noll", rc == 0 and names != "" and not ll,
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
        rc, out = hcc(prg, [T("float", "float.c")], model, ["--float", "--map"])
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
        if model == "cc816":
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

    if want("fpu") and model == "cc816":
        fpu_test(b, horizon)

    if want("ll") and model == "cc816":
        ll_test(b, horizon)

    if want("stack"):
        prg = os.path.join(b, "STACK.PRG")
        rc, out = hcc(prg, [T("stack", "stack.c")], model)
        if not rc:
            rc, con, _ = emu(prg, os.path.join(b, "run-stack"), horizon, seconds=3)
            overflow = "stack overflow:" in con
            # 200 levels of ~70 bytes: more than the tiny model's 4 KB and cc816's 8 KB
            # software stack (the array is there), less than the large model's 32 KB
            ok = overflow if model in ("tiny", "cc816") else (not overflow and "intact" in con)
            report("stack", model, ok, "overflow reported" if overflow else "no overflow, guard intact")
        else:
            report("stack", model, False, "build: " + out.strip().splitlines()[-1])
        prg = os.path.join(b, "STACKD.PRG")
        rc, out = hcc(prg, [T("stack", "stack.c")], model, ["--debug"])
        if not rc:
            rc, con, _ = emu(prg, os.path.join(b, "run-stackd"), horizon, args="ok", seconds=3)
            m = re.search(r"stack: (\d+) of (\d+) bytes used", con)
            m2 = re.search(r"software stack: (\d+) of (\d+) bytes used", con)
            ok = bool(m) and "overflow" not in con and (bool(m2) or model != "cc816")
            report("stackdbg", model, ok, (m.group(0) if m else "no report") +
                   (", " + m2.group(0) if m2 else ""))
        else:
            report("stackdbg", model, False, "build: " + out.strip().splitlines()[-1])

    if want("bench"):
        # vbcc: -O1 (its default) and -O3; cc816: its default (-O2) and -O1
        for opt in (("-O2", "-O1") if model == "cc816" else ("-O1", "-O3")):
            name = "bench" if opt in ("-O1", "-O2") and opt == (
                "-O2" if model == "cc816" else "-O1") else "bench" + opt
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
        rc, out = hcc(prg, [T("bench", "fbench.c")], model, ["--float", "--map"])
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
    if want("rt") and os.path.exists(rt):
        rc, out = sh([sys.executable, rt, "--model", model, "--horizon", horizon])
        # (rt/run.py takes the configurations too: cc816, large, tiny)
        lines = [l for l in out.splitlines() if l.strip()]
        summary = [l for l in lines if re.match(r"^rt \w+", l)]
        report("rt", model, rc == 0, f"{len(summary)} operations" +
               ("" if rc == 0 else ": " + " | ".join(l for l in lines if "FAIL" in l)[:300]))


def hcc_messages(only, models):
    """the driver's messages (no emulator), the same for both compilers"""
    if only and "hcc" not in only:
        return
    b = os.path.join(SDKC, "build", "tests", "hcc")
    os.makedirs(b, exist_ok=True)
    W = lambda n, t: (open(os.path.join(b, n), "w").write(t), os.path.join(b, n))[1]  # noqa: E731
    bad = W("bad.c", "int main(void)\n{\n    int x = ;\n    return 0;\n}\n")
    big = W("big.c", "char big[70000u / 2], big2[70000u / 2];\n"
                     "int main(void) { big[1] = big2[2]; return 0; }\n")
    undef = W("undef.c", "void nosuch(void);\nint main(void) { nosuch(); return 0; }\n")
    for m in [m for m in ("cc816", "large") if m in models]:
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
    if "tiny" in models:
        # tiny model: data too big for the window
        bigt = W("bigt.c", "char big[30000];\nint main(void) { big[1] = 1; return big[1]; }\n")
        rc, out = hcc(os.path.join(b, "BIGT.PRG"), [bigt], "tiny")
        ok = rc != 0 and "does not fit in the window" in out
        report("hcc", "tiny", ok, "tiny data: " + (grab(out, r"= [\d,]+ bytes, the window has [\d,]+ bytes")
                                                   or out.strip()[:200]))
    if "cc816" in models and "large" in models:
        # objects of the two compilers are not mixed
        rc, out = hcc(os.path.join(b, "undef_v.o"), [undef], "large", ["-c"])
        rc2, out2 = hcc(os.path.join(b, "MIX.PRG"), [bad.replace("bad.c", "undef_v.o")], "cc816")
        ok = rc == 0 and rc2 != 0 and "made by vbcc" in out2
        rc, out = hcc(os.path.join(b, "undef_c.o"), [undef], "cc816", ["-c"])
        rc3, out3 = hcc(os.path.join(b, "MIX.PRG"), [bad.replace("bad.c", "undef_c.o")], "large")
        ok = ok and rc == 0 and rc3 != 0 and "made by cc816" in out3
        report("hcc", "mixed", ok, "objects of the other compiler refused" if ok
               else (out2 + out3).strip()[-200:])
    if "cc816" in models:
        # cc816: one model: one plain line; long long and float are built (--float too),
        # what is not supported is one plain line with file:line (a VLA)
        rc, out = hcc(os.path.join(b, "BAD.PRG"), [undef], "cc816", ["--model", "tiny"])
        ok1 = rc != 0 and "--model tiny is for vbcc" in out
        ll = W("ll.c", "int main(void)\n{\n    long long x = 1;\n    return (int)x;\n}\n")
        rc, out = hcc(os.path.join(b, "LL.PRG"), [ll], "cc816")
        ok2 = rc == 0
        vla = W("vla.c", "int f(int n)\n{\n    int a[n];\n    a[0] = n;\n    return a[0];\n}\n"
                "int main(void) { return f(1); }\n")
        rc, out5 = hcc(os.path.join(b, "VLA.PRG"), [vla], "cc816")
        ok2 = ok2 and rc != 0 and re.search(r"vla\.c:3(:\d+)?: error: cc816 does not support "
                                            r"variable-length arrays", out5) is not None
        out += out5
        fl = W("fl.c", "int main(void)\n{\n    float f = 2;\n    return (int)f;\n}\n")
        rc, out3 = hcc(os.path.join(b, "FL.PRG"), [fl], "cc816", ["--float"])
        ok3 = rc == 0
        fs = W("fs.c", "int main(void)\n{\n    float f = 2;\n    switch (f) { default: ; }\n"
               "    return 0;\n}\n")
        rc, out4 = hcc(os.path.join(b, "FS.PRG"), [fs], "cc816")
        ok4 = rc != 0 and re.search(r"fs\.c:4(:\d+)?: error: switch on a value that is not an integer",
                                    out4) is not None
        report("hcc", "cc816", ok1 and ok2 and ok3 and ok4, "--model and a VLA refused "
               "with file:line, long long and float built, a float switch refused" if ok1 and ok2 and ok3
               and ok4 else (out + out3 + out4).strip()[-200:])


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


def run_ui(horizon, only, m="large"):
    """The controls library from C (cc816, vbcc's large model; the tiny model's refusal)."""
    want = lambda n: not only or n in only  # noqa: E731
    b = os.path.join(SDKC, "build", "tests", "ui" if m == "large" else "ui-" + m)
    os.makedirs(b, exist_ok=True)
    T = lambda *p: os.path.join(HERE, *p)  # noqa: E731

    if want("ui"):
        prg = os.path.join(b, "UITEST.PRG")
        rc, out = hcc(prg, [T("ui", "uitest.c")], m, ["--map"])
        if rc:
            report("ui", m, False, "build: " + out.strip().splitlines()[-1])
        else:
            if m == "cc816":            # no block: the program's own size
                blk = "program " + grab(out, r"[\d,]+ bytes on the card")
            else:
                blk = grab(out, r"block: [\d,]+ bytes") + " for " + \
                    grab(out, r"\d+ hui.h names")
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
                if m == "cc816" and arg == "ptr":
                    # cc816: a local is in the code bank too (the software stack): allowed
                    ok = i >= 0 and "BADHUI: not stopped" in con and "hui:" not in con \
                        and "[kill]" not in con
                    report("uibad", m, ok, "ptr: a local control works (cc816's locals are in "
                           "the code bank)" if ok else con.strip()[-200:])
                    continue
                ok = 0 <= i < j and "not stopped" not in con
                report("uibad", m, ok, f"{arg}: " + (text if ok else con.strip()[-200:]))

    if want("uitiny") and m == "large":
        t = os.path.join(b, "tiny")
        os.makedirs(t, exist_ok=True)
        msg = "needs the large model"
        rc, out = hcc(os.path.join(t, "X.PRG"), [T("ui", "badhui.c")], "tiny")
        report("uitiny", "tiny", rc != 0 and msg in out and "hui.h:" in out,
               "hui.h in the tiny model: #error" if rc else out.strip()[-200:])
        e = os.path.join(t, "e.c")
        open(e, "w").write("int main(void) { return 0; }\n")
        rc, out = hcc(os.path.join(t, "E.PRG"), [e], "tiny", ["--ui"])
        report("uitiny", "tiny", rc != 0 and msg in out, "hcc --ui --model tiny refused"
               if rc else out.strip()[-200:])
        u = os.path.join(t, "u.c")
        open(u, "w").write("void ui_beep(void);\nint main(void) { ui_beep(); return 0; }\n")
        rc, out = hcc(os.path.join(t, "U.PRG"), [u], "tiny")
        report("uitiny", "tiny", rc != 0 and msg in out, "a hui name at the tiny link refused"
               if rc else out.strip()[-200:])
        rc, out = hcc(os.path.join(t, "U.PRG"), [u], "large", ["--map"])
        report("uitiny", "large", rc == 0 and "block:" in out, "the same in the large model: "
               + (grab(out, r"block: [\d,]+ bytes") or out.strip()[-200:]) + " for ui_beep")

    if want("appsdoc") and m == "large":
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
                          "HORIZON=" + horizon] + (["HZ_CC=cc816" if m == "cc816" else "HZ_CC=vbcc"]
                                                   if d == "c-window-app" else []))
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
                    for im in (a, c):
                        im.paste((0, 0, 0), (0, 480, 680, 512))
                    box = ImageChops.difference(a, c).getbbox()
                    n += 1
                    if box:
                        bad.append(f"shot {i}: differs in {box}")
            except ImportError:
                bad.append("(PIL not installed: screenshots not compared)")
        report("uitwin", m, not [x for x in bad if not x.startswith("(")],
               f"both templates' tests pass; {n} screenshots identical" if not bad
               else " | ".join(bad))


def main():
    a = sys.argv[1:]
    horizon = os.environ.get("HORIZON") or os.path.join(SDK, "..", "horizon")
    models = ["cc816", "large", "tiny"]
    ccs = None
    only = []
    i = 0
    while i < len(a):
        if a[i] == "--horizon":
            horizon = a[i + 1]; i += 2
        elif a[i] == "--model":
            models = [a[i + 1]]; i += 2
        elif a[i] == "--cc":
            ccs = a[i + 1]; i += 2
        elif a[i] == "--only":
            only.append(a[i + 1]); i += 2
        else:
            sys.exit(__doc__)
    horizon = os.path.abspath(horizon)
    if not os.path.exists(os.path.join(horizon, "build", "sd", "SYSTEM", "HORIZON.SYS")):
        sys.exit(f"run.py: no built Horizon card in {horizon}/build/sd (make -C {horizon})")
    sys.path.insert(0, os.path.join(SDKC, "tools"))
    import hzc
    try:
        hzc.vbcc_dir()
    except hzc.HccError:
        if ccs != "cc816" and [m for m in models if m != "cc816"]:
            print("run.py: the vbcc toolchain is not installed (tools/get-toolchain.sh): "
                  "its configurations (large, tiny) are skipped")
        ccs = "cc816"
    if ccs == "cc816":
        models = ["cc816"]
    elif ccs == "vbcc":
        models = [m for m in models if m != "cc816"] or ["large", "tiny"]
    t0 = time.time()
    hcc_messages(only, models)
    # the configurations side by side (each has its own build folder; the libraries are
    # built first, one after another, so no two of them build the same one)
    sh([sys.executable, HCC, "--build-lib"] + ["cc816"] * ("cc816" in models))
    if [m for m in models if m != "cc816"]:
        sh([sys.executable, HCC, "--build-lib"] + [m for m in models if m != "cc816"])
        sh([sys.executable, HCC, "--build-ui"])
    import concurrent.futures as cf
    with cf.ThreadPoolExecutor(len(models)) as ex:
        list(ex.map(lambda m: run_model(m, horizon, only), models))
    for m in ("cc816", "large"):
        if m in models:
            run_ui(horizon, only, m)
    bad = [r for r in results if not r[2]]
    print(f"\nC SDK tests: {len(results) - len(bad)} passed, {len(bad)} failed "
          f"({time.time() - t0:.0f} s)")
    print("C SDK TESTS PASSED" if not bad else "C SDK TESTS FAILED")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
