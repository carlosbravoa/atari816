#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""Tests of the gateway's internet (channels 4 and 5, pclink.NetServer) without a board and
without the internet: NetServer is driven with a fake board (a send function that records
the frames and checks the credit), against servers on 127.0.0.1 that the tests start
(python3 tools/test_netgw.py)."""
import http.server
import os
import shutil
import socket
import socketserver
import ssl
import struct
import subprocess
import tempfile
import threading
import time
import unittest

import pclink as P

T = 10.0                                       # longest wait for one frame


class Board:
    """The board's side of channels 4 and 5, as far as the tests need it."""

    def __init__(self, net):
        self.net = net
        self.frames = []                       # (ch, payload), in order
        self.cv = threading.Condition()
        self.given = {}                        # (ch, sid) -> window + every CREDIT
        self.got = {}                          # (ch, sid) -> DATA bytes received
        self.errors = []                       # credit exceeded, frames after the end
        self.ended = set()
        net.send = self.send

    def send(self, ch, p):
        with self.cv:
            key = (ch, p[1])
            if key in self.ended:
                self.errors.append(f"frame {p[0]:#x} after the end of {key}")
            if p[0] == P.N_DATA:
                if not 1 <= len(p) - 4 <= 1024:
                    self.errors.append(f"DATA of {len(p) - 4} bytes")
                self.got[key] = self.got.get(key, 0) + len(p) - 4
                if self.got[key] > self.given.get(key, 0):
                    self.errors.append(f"credit exceeded on {key}")
            if p[0] == P.N_END or (p[0] == P.N_OPENED and p[3]):
                self.ended.add(key)
            self.frames.append((ch, bytes(p)))
            self.cv.notify_all()

    # ---- board to PC ----
    def open_fetch(self, sid, url, window=4096):
        with self.cv:
            self.given[(P.CH_FETCH, sid)] = window
            self.got[(P.CH_FETCH, sid)] = 0
            self.ended.discard((P.CH_FETCH, sid))
        self.net.frame(P.CH_FETCH, bytes([P.N_OPEN, sid, 0, 0]) + struct.pack("<HH", window, 0)
                       + url.encode() + b"\0")

    def open_net(self, sid, host, port, tls=False, window=4096):
        with self.cv:
            self.given[(P.CH_NET, sid)] = window
            self.got[(P.CH_NET, sid)] = 0
            self.ended.discard((P.CH_NET, sid))
        self.net.frame(P.CH_NET, bytes([P.N_OPEN, sid, 0, 0]) + struct.pack("<HHB", window, port, tls)
                       + host.encode() + b"\0")

    def credit(self, ch, sid, n):
        with self.cv:
            self.given[(ch, sid)] = self.given.get((ch, sid), 0) + n
        self.net.frame(ch, bytes([P.N_CREDIT, sid, 0, 0]) + struct.pack("<H", n))

    def send_net(self, sid, data):
        self.net.frame(P.CH_NET, bytes([P.N_SEND, sid, 0, 0]) + data)

    def close(self, ch, sid):
        with self.cv:
            self.ended.add((ch, sid))
        self.net.frame(ch, bytes([P.N_CLOSE, sid, 0, 0]))

    # ---- PC to board ----
    def of(self, ch, sid):
        with self.cv:
            return [p for c, p in self.frames if c == ch and p[1] == sid]

    def wait(self, pred, timeout=T):
        end = time.time() + timeout
        with self.cv:
            while True:
                r = pred()
                if r:
                    return r
                left = end - time.time()
                if left <= 0:
                    raise AssertionError("timed out waiting for the gateway")
                self.cv.wait(left)

    def opened(self, ch, sid, timeout=T):
        p = self.wait(lambda: next((p for c, p in self.frames if c == ch and p[1] == sid
                                    and p[0] == P.N_OPENED), None), timeout)
        size, status, credit = struct.unpack_from("<IHH", p, 4)
        return p[3], size, status, credit

    def end(self, ch, sid, timeout=T):
        p = self.wait(lambda: next((p for c, p in self.frames if c == ch and p[1] == sid
                                    and p[0] == P.N_END), None), timeout)
        return p[3]

    def data(self, ch, sid):
        return b"".join(p[4:] for p in self.of(ch, sid) if p[0] == P.N_DATA)

    def read_all(self, ch, sid, step=1024, timeout=T):
        """Read the stream as the firmware does: credit back in steps of 1 KB. -> (data, END)"""
        used = 0
        end = time.time() + timeout
        while True:
            fr = self.of(ch, sid)
            got = sum(len(p) - 4 for p in fr if p[0] == P.N_DATA)
            while got - used >= step:
                used += step
                self.credit(ch, sid, step)
            done = [p for p in fr if p[0] == P.N_END]
            if done:
                return self.data(ch, sid), done[0][3]
            if time.time() > end:
                raise AssertionError("the stream did not end")
            with self.cv:
                self.cv.wait(0.05)


def fetch(board, sid, url, window=4096):
    board.open_fetch(sid, url, window)
    return board.opened(P.CH_FETCH, sid)


# ======================================================================================
# Servers on 127.0.0.1
# ======================================================================================

BIG = bytes(i * 7 & 0xFF for i in range(20000))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    requests = []

    def log_message(self, *a):
        pass

    def body(self, data, status=200, extra=()):
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        Handler.requests.append((self.path, list(self.headers.items())))
        p = self.path
        if p == "/file":
            self.body(b"hello, Atari816\n")
        elif p == "/big":
            self.body(BIG)
        elif p == "/chunked":
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for i in range(0, 3000, 700):
                part = BIG[i:min(i + 700, 3000)]
                self.wfile.write(b"%x\r\n" % len(part) + part + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        elif p == "/nolen":
            self.send_response(200)
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(BIG[:2500])
            self.close_connection = True
        elif p == "/missing":
            self.body(b"not here", 404)
        elif p == "/r1":
            self.body(b"", 301, [("Location", "/r2")])
        elif p == "/r2":
            self.body(b"", 302, [("Location", "/file")])
        elif p == "/loop":
            self.body(b"", 302, [("Location", "/loop")])
        elif p == "/pause":
            self.send_response(200)
            self.send_header("Content-Length", "100")
            self.end_headers()
            self.wfile.write(b"0123456789")
            self.wfile.flush()
            time.sleep(3)
        else:
            self.body(b"?", 400)


class HTTPServer(http.server.ThreadingHTTPServer):
    daemon_threads = True


class Silent:
    """Accepts connections and never says anything."""

    def __init__(self):
        self.s = socket.socket()
        self.s.bind(("127.0.0.1", 0))
        self.s.listen(8)
        self.port = self.s.getsockname()[1]
        self.conns = []
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        try:
            while True:
                self.conns.append(self.s.accept()[0])
        except OSError:
            pass

    def stop(self):
        self.s.close()
        for c in self.conns:
            c.close()


class Echo(socketserver.ThreadingTCPServer):
    """Echoes; "bye" makes it close the connection. Counts the connections it saw end."""
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self):
        self.ended = 0
        self.lock = threading.Lock()
        server = self

        class H(socketserver.BaseRequestHandler):
            def handle(self):
                try:
                    while True:
                        d = self.request.recv(4096)
                        if not d:
                            break
                        if d.strip() == b"bye":
                            self.request.sendall(b"see you")
                            break
                        self.request.sendall(d)
                finally:
                    with server.lock:
                        server.ended += 1
        super().__init__(("127.0.0.1", 0), H)
        self.port = self.server_address[1]
        threading.Thread(target=self.serve_forever, daemon=True).start()


class FTPServer:
    """A small FTP server: USER PASS TYPE PASV SIZE RETR NLST MLSD QUIT."""

    def __init__(self, files, users, mlsd=True):
        self.files = files                    # "pub/a.txt" -> bytes; folders: "pub/" -> None
        self.users = users
        self.mlsd = mlsd
        self.commands = []
        self.s = socket.socket()
        self.s.bind(("127.0.0.1", 0))
        self.s.listen(8)
        self.port = self.s.getsockname()[1]
        threading.Thread(target=self._run, daemon=True).start()

    def stop(self):
        self.s.close()

    def _run(self):
        try:
            while True:
                c, _ = self.s.accept()
                threading.Thread(target=self._session, args=(c,), daemon=True).start()
        except OSError:
            pass

    def _entries(self, folder):
        pre = folder.strip("/")
        pre = pre + "/" if pre else ""
        out = {}
        for k, v in self.files.items():
            if k.startswith(pre) and k != pre:
                rest = k[len(pre):]
                name = rest.split("/")[0]
                out[name] = (v is None or "/" in rest.rstrip("/"), len(v or b""))
        return out

    def _session(self, c):
        f = c.makefile("rb")
        say = lambda t: c.sendall(t.encode("latin-1") + b"\r\n")     # noqa: E731
        user = None
        logged = False
        data = None
        say("220 test server")
        try:
            for line in f:
                line = line.decode("latin-1").rstrip("\r\n")
                cmd, _, arg = line.partition(" ")
                cmd = cmd.upper()
                self.commands.append(cmd)
                if cmd == "USER":
                    user = arg
                    say("331 password please" if arg == "anonymous" or arg in self.users
                        else "530 no such user")
                elif cmd == "PASS":
                    logged = user == "anonymous" or self.users.get(user) == arg
                    say("230 in" if logged else "530 Login incorrect")
                elif cmd == "QUIT":
                    say("221 bye")
                    break
                elif not logged:
                    say("530 log in first")
                elif cmd == "TYPE":
                    say("200 ok")
                elif cmd == "PASV":
                    if data:
                        data.close()
                    data = socket.socket()
                    data.bind(("127.0.0.1", 0))
                    data.listen(1)
                    p = data.getsockname()[1]
                    say(f"227 Entering Passive Mode (127,0,0,1,{p >> 8},{p & 255})")
                elif cmd == "SIZE":
                    v = self.files.get(arg)
                    say(f"213 {len(v)}" if v is not None else "550 no such file")
                elif cmd in ("RETR", "NLST", "MLSD"):
                    if cmd == "MLSD" and not self.mlsd:
                        say("500 unknown command")
                        continue
                    if cmd == "RETR":
                        body = self.files.get(arg)
                        if body is None:
                            say("550 no such file")
                            continue
                    else:
                        ents = self._entries(arg)
                        if arg and arg.strip("/") + "/" not in self.files:
                            say("550 no such folder")
                            continue
                        if cmd == "NLST":
                            body = "".join(n + "\r\n" for n in sorted(ents)).encode()
                        else:
                            body = b"type=cdir;modify=20260101000000; .\r\n" + "".join(
                                (f"type=dir;modify=20260102030400; {n}\r\n" if d else
                                 f"type=file;size={sz};modify=20260102030405; {n}\r\n")
                                for n, (d, sz) in sorted(ents.items())).encode()
                    d, _ = data.accept()
                    say("150 here it comes")
                    d.sendall(body)
                    d.close()
                    data.close()
                    say("226 done")
                else:
                    say("502 not implemented")
        except OSError:
            pass
        finally:
            if data:
                data.close()
            c.close()


def tls_cert(folder):
    """A self-signed certificate for 127.0.0.1 (openssl), or None without openssl."""
    if not shutil.which("openssl"):
        return None
    key, crt = os.path.join(folder, "k.pem"), os.path.join(folder, "c.pem")
    r = subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
                        "-out", crt, "-days", "1", "-subj", "/CN=127.0.0.1",
                        "-addext", "subjectAltName=IP:127.0.0.1"],
                       capture_output=True)
    return (crt, key) if r.returncode == 0 else None


# ======================================================================================
# Tests
# ======================================================================================

class Base(unittest.TestCase):
    def setUp(self):
        self.logs = []
        self.net = P.NetServer(None, log=self.logs.append)
        self.board = Board(self.net)

    def tearDown(self):
        self.net.reset()
        self.assertEqual(self.board.errors, [])


class Fetch(Base):
    @classmethod
    def setUpClass(cls):
        cls.http = HTTPServer(("127.0.0.1", 0), Handler)
        cls.port = cls.http.server_address[1]
        threading.Thread(target=cls.http.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.port}"

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()

    def test_get_known_size(self):
        Handler.requests.clear()
        self.assertEqual(fetch(self.board, 1, self.base + "/file"), (0, 16, 200, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 1), (b"hello, Atari816\n", 0))
        path, headers = Handler.requests[0]
        self.assertEqual(path, "/file")
        self.assertEqual(sorted(k.lower() for k, _ in headers),
                         ["accept", "accept-encoding", "connection", "host", "user-agent"])
        h = {k.lower(): v for k, v in headers}
        self.assertEqual(h["host"], f"127.0.0.1:{self.port}")
        self.assertEqual(h["user-agent"], "Atari816-link/1")
        self.assertEqual(h["accept-encoding"], "identity")
        self.assertEqual(h["connection"], "close")

    def test_chunked_and_unknown_size(self):
        self.assertEqual(fetch(self.board, 2, self.base + "/chunked"), (0, 0xFFFFFFFF, 200, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 2), (BIG[:3000], 0))
        self.assertEqual(fetch(self.board, 3, self.base + "/nolen"), (0, 0xFFFFFFFF, 200, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 3), (BIG[:2500], 0))

    def test_http_error(self):
        self.assertEqual(fetch(self.board, 4, self.base + "/missing"), (0x8F, 8, 404, 0))
        time.sleep(0.2)
        self.assertEqual(len(self.board.of(P.CH_FETCH, 4)), 1)        # nothing after it

    def test_redirects(self):
        self.assertEqual(fetch(self.board, 5, self.base + "/r1"), (0, 16, 200, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 5), (b"hello, Atari816\n", 0))
        res, _, status, _ = fetch(self.board, 6, self.base + "/loop")
        self.assertEqual((res, status), (P.R_NETERR, 302))

    def test_credit_is_respected(self):
        self.assertEqual(fetch(self.board, 7, self.base + "/big", window=1500), (0, 20000, 200, 0))
        self.board.wait(lambda: self.board.got[(P.CH_FETCH, 7)] == 1500)
        time.sleep(0.3)                                             # no credit: nothing more
        self.assertEqual(self.board.got[(P.CH_FETCH, 7)], 1500)
        self.assertEqual(self.board.data(P.CH_FETCH, 7), BIG[:1500])
        sizes = [len(p) - 4 for p in self.board.of(P.CH_FETCH, 7) if p[0] == P.N_DATA]
        self.assertEqual(sizes, [1024, 476])
        self.board.credit(P.CH_FETCH, 7, 100)
        self.board.wait(lambda: self.board.got[(P.CH_FETCH, 7)] == 1600)
        data, res = self.board.read_all(P.CH_FETCH, 7, step=100)
        self.assertEqual((data, res), (BIG, 0))

    def test_bad_addresses(self):
        for sid, url in enumerate(["gopher://example.com/", "http://", "http://h:99999/",
                                   "http://127.0.0.1:0/", "nonsense", "http://a b/"], 10):
            self.assertEqual(fetch(self.board, sid, url)[0], P.R_BADADDR, url)

    def test_name_not_found(self):
        self.assertEqual(fetch(self.board, 20, "http://nothing-here.invalid/")[0], P.R_NONAME)

    def test_refused(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        self.assertEqual(fetch(self.board, 21, f"http://127.0.0.1:{port}/")[0], P.R_REFUSED)

    def test_timeouts(self):
        quiet = Silent()
        try:
            self.net.t_fetch_head = 0.5
            t = time.time()
            self.assertEqual(fetch(self.board, 22, f"http://127.0.0.1:{quiet.port}/")[0],
                             P.R_TIMEOUT)
            self.assertLess(time.time() - t, 3)
        finally:
            quiet.stop()
        self.net.t_fetch_body = 0.5
        self.assertEqual(fetch(self.board, 23, self.base + "/pause"), (0, 100, 200, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 23), (b"0123456789", P.R_TIMEOUT))

    def test_tls_to_a_plain_server(self):
        self.assertEqual(fetch(self.board, 24, f"https://127.0.0.1:{self.port}/file")[0],
                         P.R_TLS)

    def test_tls_bad_certificate(self):
        tmp = tempfile.mkdtemp()
        cert = tls_cert(tmp)
        if not cert:
            self.skipTest("no openssl to make a certificate")
        srv = HTTPServer(("127.0.0.1", 0), Handler)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(*cert)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            port = srv.server_address[1]
            self.assertEqual(fetch(self.board, 25, f"https://127.0.0.1:{port}/file")[0], P.R_TLS)
            # trusting it: the same server works
            self.net.ssl_context = ssl.create_default_context(cafile=cert[0])
            self.assertEqual(fetch(self.board, 26, f"https://127.0.0.1:{port}/file"),
                             (0, 16, 200, 0))
            self.assertEqual(self.board.read_all(P.CH_FETCH, 26), (b"hello, Atari816\n", 0))
        finally:
            srv.shutdown()
            srv.server_close()
            shutil.rmtree(tmp)

    def test_close_and_session_end(self):
        self.assertEqual(fetch(self.board, 27, self.base + "/big", window=1024)[0], 0)
        self.board.wait(lambda: self.board.got[(P.CH_FETCH, 27)] == 1024)
        self.board.close(P.CH_FETCH, 27)
        self.board.credit(P.CH_FETCH, 27, 4096)                    # (ignored: it is closed)
        time.sleep(0.3)
        self.assertEqual(self.board.got[(P.CH_FETCH, 27)], 1024)
        self.assertEqual(self.net.streams[P.CH_FETCH], {})
        self.assertEqual(fetch(self.board, 28, self.base + "/big", window=1024)[0], 0)
        self.board.wait(lambda: self.board.got[(P.CH_FETCH, 28)] == 1024)
        self.net.reset()
        self.board.ended.add((P.CH_FETCH, 28))
        time.sleep(0.3)
        self.assertEqual(self.board.got[(P.CH_FETCH, 28)], 1024)

    def test_result_mapping(self):
        self.assertEqual(P.net_result(ssl.SSLCertVerificationError("x")), P.R_TLS)
        self.assertEqual(P.net_result(socket.timeout()), P.R_TIMEOUT)
        self.assertEqual(P.net_result(ConnectionRefusedError()), P.R_REFUSED)
        self.assertEqual(P.net_result(ConnectionResetError()), P.R_NETERR)
        self.assertEqual(P.net_result(socket.gaierror(socket.EAI_NONAME, "x")), P.R_NONAME)

    def test_safe_url(self):
        self.assertEqual(P.safe_url("ftp://bob:p@ss:w/rd@host:21/a/b?x"), "ftp://bob:***@host:21/a/b?x")
        self.assertEqual(P.safe_url("ftp://bob@host/a"), "ftp://bob@host/a")
        self.assertEqual(P.safe_url("http://host/a:b@c"), "http://host/a:b@c")
        self.assertEqual(P.safe_url("ftp://bob:pa/ss@host/x"), "ftp://bob:***@host/x")
        self.assertEqual(P.safe_url("http://host:8080/a?b@c"), "http://host:8080/a?b@c")


class Net(Base):
    @classmethod
    def setUpClass(cls):
        cls.echo = Echo()

    @classmethod
    def tearDownClass(cls):
        cls.echo.shutdown()
        cls.echo.server_close()

    def connect(self, sid):
        self.board.open_net(sid, "127.0.0.1", self.echo.port)
        self.assertEqual(self.board.opened(P.CH_NET, sid), (0, 0xFFFFFFFF, 0, 4096))

    def test_round_trip(self):
        self.connect(1)
        st = self.net.streams[P.CH_NET][1]
        self.assertEqual(st.socks[0].getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY), 1)
        self.board.send_net(1, b"ping")
        self.board.wait(lambda: self.board.data(P.CH_NET, 1) == b"ping")
        scr = [struct.unpack_from("<H", p, 4)[0] for p in self.board.of(P.CH_NET, 1)
               if p[0] == P.N_SCREDIT]
        self.assertEqual(sum(scr), 4)
        self.board.send_net(1, b"x" * 1024)
        self.board.send_net(1, b"y" * 1024)
        self.board.wait(lambda: len(self.board.data(P.CH_NET, 1)) == 2052)
        self.assertEqual(self.board.data(P.CH_NET, 1), b"ping" + b"x" * 1024 + b"y" * 1024)
        self.board.wait(lambda: sum(struct.unpack_from("<H", p, 4)[0]
                                    for p in self.board.of(P.CH_NET, 1) if p[0] == P.N_SCREDIT) == 2052)

    def test_credit(self):
        self.board.open_net(2, "127.0.0.1", self.echo.port, window=10)
        self.board.opened(P.CH_NET, 2)
        self.board.send_net(2, b"0123456789abcdef")
        self.board.wait(lambda: self.board.got[(P.CH_NET, 2)] == 10)
        time.sleep(0.2)
        self.assertEqual(self.board.data(P.CH_NET, 2), b"0123456789")
        self.board.credit(P.CH_NET, 2, 100)
        self.board.wait(lambda: self.board.data(P.CH_NET, 2) == b"0123456789abcdef")

    def test_remote_close(self):
        self.connect(3)
        self.board.send_net(3, b"bye")
        self.assertEqual(self.board.end(P.CH_NET, 3), 0)
        self.assertEqual(self.board.data(P.CH_NET, 3), b"see you")

    def test_close_from_board_and_session_end(self):
        before = self.echo.ended
        self.connect(4)
        self.board.close(P.CH_NET, 4)
        self.board.wait(lambda: self.echo.ended == before + 1, 5)
        for sid in (5, 6):
            self.connect(sid)
        self.net.reset()
        self.board.ended.update({(P.CH_NET, 5), (P.CH_NET, 6)})
        self.board.wait(lambda: self.echo.ended == before + 3, 5)

    def test_too_many_streams(self):
        for sid in range(10, 18):
            self.connect(sid)
        self.board.open_net(18, "127.0.0.1", self.echo.port)
        self.assertEqual(self.board.opened(P.CH_NET, 18)[0], P.R_TOOMANY)
        self.board.close(P.CH_NET, 10)
        self.connect(19)

    def test_reopen_same_sid(self):
        before = self.echo.ended
        self.connect(30)
        with self.board.cv:
            self.board.frames.clear()
        self.connect(30)                                # the old one is closed first
        self.board.wait(lambda: self.echo.ended == before + 1, 5)

    def test_errors(self):
        self.board.open_net(40, "127.0.0.1", 0)
        self.assertEqual(self.board.opened(P.CH_NET, 40)[0], P.R_BADADDR)
        self.board.open_net(41, "", 80)
        self.assertEqual(self.board.opened(P.CH_NET, 41)[0], P.R_BADADDR)
        self.board.open_net(42, "nothing-here.invalid", 80)
        self.assertEqual(self.board.opened(P.CH_NET, 42)[0], P.R_NONAME)
        self.board.open_net(43, "127.0.0.1", self.echo.port, tls=True)
        self.assertEqual(self.board.opened(P.CH_NET, 43)[0], P.R_TLS)


class FTP(Base):
    FILES = {"pub/": None, "pub/hello.txt": b"hello from ftp\n", "pub/big.bin": BIG,
             "pub/docs/": None, "pub/docs/x.txt": b"x", "secret/": None,
             "secret/plan.txt": b"the plan"}
    PASSWORD = "s3cr%t:@/"

    def setUp(self):
        super().setUp()
        self.ftp = FTPServer(self.FILES, {"alice": self.PASSWORD})
        self.base = f"ftp://127.0.0.1:{self.ftp.port}"

    def tearDown(self):
        self.ftp.stop()
        super().tearDown()

    def test_retr_anonymous(self):
        self.assertEqual(fetch(self.board, 1, self.base + "/pub/big.bin"), (0, 20000, 0, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 1), (BIG, 0))
        self.assertIn("PASV", self.ftp.commands)

    def test_listing(self):
        res, size, _, _ = fetch(self.board, 2, self.base + "/pub/")
        data, end = self.board.read_all(P.CH_FETCH, 2)
        self.assertEqual((res, end, size), (0, 0, len(data)))
        lines = data.decode().split("\n")
        self.assertEqual(lines[-1], "")
        names = [ln.split("\t")[0] for ln in lines[:-1]]
        self.assertEqual(names, ["big.bin", "docs/", "hello.txt"])
        f = lines[0].split("\t")
        self.assertEqual(f[1], "20000")
        self.assertRegex(f[2], r"^2026-01-0[12] \d\d:\d\d$")

    def test_listing_without_mlsd(self):
        self.ftp.mlsd = False
        fetch(self.board, 3, self.base + "/pub/")
        data, end = self.board.read_all(P.CH_FETCH, 3)
        self.assertEqual((data, end), (b"big.bin\ndocs\nhello.txt\n", 0))

    def test_user_and_password(self):
        quoted = "s3cr%25t%3A%40%2F"
        url = f"ftp://alice:{quoted}@127.0.0.1:{self.ftp.port}/secret/plan.txt"
        self.assertEqual(fetch(self.board, 4, url), (0, 8, 0, 0))
        self.assertEqual(self.board.read_all(P.CH_FETCH, 4), (b"the plan", 0))
        bad = f"ftp://alice:wrong-{quoted}@127.0.0.1:{self.ftp.port}/secret/plan.txt"
        self.assertEqual(fetch(self.board, 5, bad)[0], P.R_REFUSED)
        text = "\n".join(self.logs)
        self.assertIn("alice:***@", text)
        for secret in (self.PASSWORD, quoted, "s3cr"):
            self.assertNotIn(secret, text)

    def test_missing_file(self):
        self.assertEqual(fetch(self.board, 6, self.base + "/pub/nothing.txt")[0], P.R_REFUSED)
        self.assertEqual(fetch(self.board, 7, self.base + "/nofolder/")[0], P.R_REFUSED)


class GatewayWiring(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_services(self):
        gw = P.Gateway(self.tmp, port="/dev/null-no-port")
        self.assertEqual(gw.link.services, P.SV_FILES | P.SV_DEV | P.SV_NET | P.SV_FETCH)
        gw = P.Gateway(self.tmp, port="/dev/null-no-port", net=False)
        self.assertEqual(gw.link.services & (P.SV_NET | P.SV_FETCH), 0)
        self.assertIsNone(gw.net)
        out = []
        gw.link._write = out.append
        gw.link._hello()
        hello = P.Parser().feed(out[0])[0][4]
        self.assertEqual((hello[0], hello[10]), (P.C_HELLO, P.SV_FILES | P.SV_DEV))
        gw._on_frame(P.CH_FETCH, b"\x01\x01\x00\x00\x00\x10\x00\x00http://x/\0")   # dropped

    def test_frames_reach_the_net_server(self):
        srv = HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            gw = P.Gateway(self.tmp, port="/dev/null-no-port")
            board = Board(gw.net)
            gw.net.send = None
            gw.link.send = lambda ch, p, timeout=60.0: board.send(ch, p)
            gw.net.send = lambda ch, p: gw.link.send(ch, p)
            board.given[(P.CH_FETCH, 9)] = 4096
            gw._on_frame(P.CH_FETCH, bytes([P.N_OPEN, 9, 0, 0]) + struct.pack("<HH", 4096, 0)
                         + f"http://127.0.0.1:{srv.server_address[1]}/file".encode() + b"\0")
            self.assertEqual(board.opened(P.CH_FETCH, 9), (0, 16, 200, 0))
            self.assertEqual(board.end(P.CH_FETCH, 9), 0)
            self.assertEqual(board.data(P.CH_FETCH, 9), b"hello, Atari816\n")
            gw._on_state(False, "")
            self.assertEqual(board.errors, [])
        finally:
            srv.shutdown()
            srv.server_close()


if __name__ == "__main__":
    unittest.main()
