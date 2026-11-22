#!/usr/bin/env python3
"""run.py - build and run the runtime tests (tests/rt/rttest.c) in emu816.

    run.py [--model cc816|cc816l|large|tiny|both|all] [--horizon DIR] [--out DIR] [--quick]
           [--seconds N]

Generates the table (tools/genrt.py), builds RTTEST.PRG with bin/hcc for each
configuration (cc816: its runtime, rt/cc816; large and tiny: vbcc's, fastrt/)
(HZ_BUILD in the environment is honoured, as hcc does), runs it in the text shell with the
table on the card, prints its "rt ..." lines and "RT PASS"/"RT FAIL" per model.
Exit 0 when every model passed. --quick: fewer cases (for a fast check). --seconds: how
long the emulator runs (emulated seconds; the default leaves room for the whole table).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(os.path.dirname(HERE))
SDK = os.path.dirname(SDKC)


def main():
    a = sys.argv[1:]
    models = ["cc816", "large", "tiny"]
    hz = os.environ.get("HORIZON") or os.path.join(SDK, "..", "horizon")
    out = os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"), "test", "rt")
    quick = False
    seconds = None
    i = 0
    while i < len(a):
        if a[i] == "--model":
            models = ["cc816", "large", "tiny"] if a[i + 1] == "both" else [a[i + 1]]; i += 2
        elif a[i] == "--horizon":
            hz = a[i + 1]; i += 2
        elif a[i] == "--out":
            out = a[i + 1]; i += 2
        elif a[i] == "--seconds":
            seconds = int(a[i + 1]); i += 2
        elif a[i] == "--quick":
            quick = True; i += 1
        else:
            sys.exit(__doc__)
    os.makedirs(out, exist_ok=True)
    table = os.path.join(out, "RTTAB.BIN")
    gen = [sys.executable, os.path.join(SDKC, "tools", "genrt.py"), table]
    if quick:
        gen += ["--cases", "300", "--memcases", "200"]
    subprocess.run(gen, check=True)
    ok = True
    for m in models:
        prg = os.path.join(out, f"RTTEST{ {'tiny': 'T', 'cc816': 'C', 'cc816l': 'L'}.get(m, '') }.PRG")
        cc = ["--cc", "cc816"] if m == "cc816" else \
            ["--cc", "cc816", "--code", "large", "--main-room", "0", "--bank-room", "8192"] \
            if m == "cc816l" else ["--cc", "vbcc", "--model", m]
        r = subprocess.run([os.path.join(SDKC, "bin", "hcc")] + cc + ["-o", prg,
                            os.path.join(HERE, "rttest.c")])
        if r.returncode:
            print(f"rt ({m}): build FAILED")
            ok = False
            continue
        run = os.path.join(out, "run-" + m)
        secs = seconds or (40 if quick else (130 if m == "tiny" else 260))
        subprocess.run([sys.executable, os.path.join(SDK, "tools", "run816.py"), prg,
                        "--horizon", hz, "--mode", "shell", "--seconds", str(secs),
                        "--file", table + ":/RTTAB.BIN", "--out", run],
                       stdout=subprocess.DEVNULL)
        con = open(os.path.join(run, "console.txt"), encoding="latin-1").read()
        lines = [ln for ln in con.splitlines()
                 if ln.startswith(("rt", "  ", "RT ", "[kill]")) or "[kill]" in ln]
        print(f"== rt, {m} model")
        print("\n".join(lines))
        if "RT PASS" not in con:
            ok = False
            if "RT FAIL" not in con:
                print(f"rt ({m}): no result (see {run}/console.txt)")
    print("RT TESTS " + ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
