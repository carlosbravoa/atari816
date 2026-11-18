#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""Host test of the PC link: the firmware's engine (pclink.c, built for the PC as
`harness`) against the real gateway (tools/pclink.py) through a pseudo terminal.

  ./run_tests.py            # build, run, print PASS / FAIL lines; exit 1 on a failure
  ./run_tests.py --drop N   # the board side loses one received byte in every N
  ./run_tests.py --pcdrop N # the PC side loses one received byte in every N
"""
import os
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pclink  # noqa: E402

fails = 0


def check(ok, text):
    global fails
    print(("PASS " if ok else "FAIL ") + text)
    if not ok:
        fails += 1


def main():
    drop = "0"
    if "--drop" in sys.argv:
        drop = sys.argv[sys.argv.index("--drop") + 1]
    if "--pcdrop" in sys.argv:                          # the PC side loses bytes too
        every = int(sys.argv[sys.argv.index("--pcdrop") + 1])
        feed = pclink.Parser.feed
        count = [0]

        def lossy(self, data):
            out = bytearray()
            for b in data:
                count[0] += 1
                if count[0] % every:
                    out.append(b)
            return feed(self, bytes(out))
        pclink.Parser.feed = lossy
    exe = os.path.join(HERE, "harness")
    subprocess.run(["gcc", "-O2", "-Wall", "-DPL_HOST", "-o", exe, os.path.join(HERE, "harness.c")],
                   check=True)
    tmp = tempfile.mkdtemp(prefix="pclink-test-")
    share = os.path.join(tmp, "share")
    os.mkdir(share)
    os.symlink("/etc", os.path.join(share, "OUT"))
    os.environ["XDG_RUNTIME_DIR"] = tmp
    h = subprocess.Popen([exe, drop], stdout=subprocess.PIPE, text=True)
    line = h.stdout.readline().split()
    assert line[0] == "PTY", line
    pty = line[1]
    gw = pclink.Gateway(share, port=pty, verbose=1)
    threading.Thread(target=gw.run, daemon=True).start()
    lines = []

    def reader():
        for ln in h.stdout:
            lines.append(ln.rstrip())
            print("board: " + ln.rstrip())
    threading.Thread(target=reader, daemon=True).start()
    t0 = time.time()
    while not os.path.exists(pclink.sock_path()) and time.time() - t0 < 5:
        time.sleep(0.05)
    # developer channel through the gateway, while the board runs its file requests
    with pclink.DevClient(timeout=20) as d:
        check(d.via == "gateway", "tools use the gateway")
        r, data = d.request(pclink.D_ECHO, b"hello, Atari816")
        check(r == 0 and data == b"hello, Atari816", "echo")
        t = time.time()
        r, data = d.request(pclink.D_SOURCE, (200000).to_bytes(4, "little"), timeout=60)
        dt = time.time() - t
        check(r == 0 and data == bytes((i & 0xFF) for i in range(200000)), f"source 200000 ({dt:.2f} s)")
        frames = [i.to_bytes(4, "little") + bytes(1024) for i in range(100)]
        r, data = d.request(pclink.D_SINK, b"", frames=frames, timeout=60)
        check(r == 0 and int.from_bytes(data, "little") == 100 * 1028, f"sink {int.from_bytes(data, 'little')}")
        r, data = d.request(0x7E)
        check(r == 0x82, "unknown op answered $82")
    t0 = time.time()
    while not any(l.startswith("FILES DONE") for l in lines) and time.time() - t0 < 90:
        time.sleep(0.1)
    check(any(l.startswith("FILES DONE 0") for l in lines), "board side file requests")
    check(not any(l.startswith("FAIL") for l in lines), "no board side FAIL")
    # the gateway goes away and comes back: a new session
    gw.close()
    time.sleep(4.5)
    check(any(l == "session down" for l in lines), "board saw the session end")
    gw2 = pclink.Gateway(share, port=pty, verbose=1)
    threading.Thread(target=gw2.run, daemon=True).start()
    t0 = time.time()
    while lines.count("session up") < 2 and time.time() - t0 < 10:
        time.sleep(0.1)
    check(lines.count("session up") >= 2, "new session after a gateway restart")
    gw2.close()
    h.kill()
    print("parser: skipped", gw2.link.parser.skipped, "bad", gw2.link.parser.bad,
          "retries", gw.link.retries)
    print("RESULT", "PASS" if not fails else f"FAIL ({fails})")
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(1 if fails else 0)                         # (daemon threads: no shutdown noise)


if __name__ == "__main__":
    main()
