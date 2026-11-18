#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""Host test of the PC link: the firmware's engine (pclink.c and pcnet.c, built for the PC as
`harness`) against the real gateway (tools/pclink.py) through a pseudo terminal. (Step 2) also
URLs from a loopback web server and a connection to a loopback echo server: no internet.

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
    # (step 2) a loopback web server with a file, and a loopback echo server that closes on QUIT
    web = os.path.join(tmp, "web")
    os.mkdir(web)
    big = bytes((i * 131 + (i >> 8)) & 0xFF for i in range(300000))
    open(os.path.join(web, "big.bin"), "wb").write(big)
    import functools
    import http.server
    import socketserver

    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a):
            pass
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
                                            functools.partial(Quiet, directory=web))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    class Echo(socketserver.BaseRequestHandler):
        def handle(self):
            while True:
                d = self.request.recv(1024)
                if not d or b"QUIT" in d:
                    break
                self.request.sendall(d)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    echo = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Echo)
    echo.daemon_threads = True
    threading.Thread(target=echo.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}"
    h = subprocess.Popen([exe, drop, base, str(len(big)), str(sum(big)), str(echo.server_address[1])],
                         stdout=subprocess.PIPE, text=True)
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
    t0 = time.time()
    while not any(l.startswith("NET DONE") for l in lines) and time.time() - t0 < 120:
        time.sleep(0.1)
    check(any(l.startswith("NET DONE 0") for l in lines), "board side URLs and connections (step 2)")
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
