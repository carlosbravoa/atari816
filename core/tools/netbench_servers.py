#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""netbench_servers.py [SIZE] - the PC side of sw/a816/NETBENCH.BIN: a web server on
127.0.0.1:8816 serving /big.bin (SIZE bytes, default 1 MB) and an echo server on
127.0.0.1:8817. Loopback only; Ctrl-C stops both. The gateway reaches them for the board."""
import functools
import http.server
import os
import socketserver
import sys
import tempfile
import threading

size = int(sys.argv[1]) if len(sys.argv) > 1 else 1 << 20
d = tempfile.mkdtemp(prefix="netbench-")
open(os.path.join(d, "big.bin"), "wb").write(bytes((i * 131 + (i >> 8)) & 0xFF for i in range(size)))


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.setsockopt(6, 1, 1)                 # TCP_NODELAY
        while True:
            b = self.request.recv(1024)
            if not b:
                break
            self.request.sendall(b)


socketserver.ThreadingTCPServer.allow_reuse_address = True
http.server.ThreadingHTTPServer.allow_reuse_address = True
web = http.server.ThreadingHTTPServer(("127.0.0.1", 8816), functools.partial(Quiet, directory=d))
echo = socketserver.ThreadingTCPServer(("127.0.0.1", 8817), Echo)
echo.daemon_threads = True
threading.Thread(target=echo.serve_forever, daemon=True).start()
print(f"http://127.0.0.1:8816/big.bin ({size} bytes), echo on 127.0.0.1:8817", flush=True)
try:
    web.serve_forever()
except KeyboardInterrupt:
    pass
