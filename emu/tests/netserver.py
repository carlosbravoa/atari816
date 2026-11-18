#!/usr/bin/env python3
"""Loopback servers for the emu816 net tests (never the internet).

netserver.py PORTFILE: listens on 127.0.0.1 at a free port and writes "ECHO CLOSED" to
PORTFILE: ECHO is the echo server's port, CLOSED a port where nothing listens (connections
there are refused). The echo server sends every line back; for the line "quit" it sends
"bye" and closes the connection. It runs until it is killed (or stdin is closed).
"""
import socket, sys, threading


def serve(conn):
    buf = b""
    with conn:
        while True:
            try:
                d = conn.recv(4096)
            except OSError:
                return
            if not d:
                return
            buf += d
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if line.strip() == b"quit":
                    conn.sendall(b"bye\n")
                    conn.shutdown(socket.SHUT_RDWR)
                    return
                conn.sendall(line + b"\n")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(8)
    tmp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tmp.bind(("127.0.0.1", 0))
    closed = tmp.getsockname()[1]
    tmp.close()                                     # nothing listens there now
    with open(sys.argv[1] + ".tmp", "w") as f:
        f.write("%d %d\n" % (srv.getsockname()[1], closed))
    import os
    os.rename(sys.argv[1] + ".tmp", sys.argv[1])
    while True:
        c, _ = srv.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
