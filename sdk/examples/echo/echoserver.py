#!/usr/bin/env python3
"""echoserver.py - a small TCP echo server for testing ECHO.PRG in the emulator.

    echoserver.py [--port N]            serve until ctrl-C (default port 7007)
    echoserver.py --run CMD ARGS...     serve on a free port of 127.0.0.1 while CMD runs;
                                        "{port}" in an argument becomes that port; the exit
                                        code is CMD's

It sends every line it gets back, unchanged, then waits for the next one. `make test`
runs the emulator (run816.py --net) under --run, so tcp://127.0.0.1:{port} reaches it.
"""
import socketserver
import subprocess
import sys
import threading


class Echo(socketserver.StreamRequestHandler):
    def handle(self):
        for line in self.rfile:
            self.wfile.write(line)
            self.wfile.flush()


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    a = sys.argv[1:]
    if a and a[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    if a and a[0] == '--run':
        srv = Server(('127.0.0.1', 0), Echo)
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        cmd = [x.replace('{port}', str(port)) for x in a[1:]]
        r = subprocess.run(cmd)
        srv.shutdown()
        return r.returncode
    port = int(a[1]) if len(a) == 2 and a[0] == '--port' else 7007
    srv = Server(('0.0.0.0', port), Echo)
    print(f'echoserver: listening on port {port} (ctrl-C to stop)')
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
