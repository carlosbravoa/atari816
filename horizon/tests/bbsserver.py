#!/usr/bin/env python3
"""bbsserver.py PORTFILE LOGFILE - (0.22) a scripted "BBS" on 127.0.0.1 for the BBS terminal's
test (tests/bbs.keys, emu816 --net). It listens on a free port (written to PORTFILE), then
serves one caller after another; it ends after 3 callers or 150 s.

To each caller: the telnet negotiation (DO TERMINAL-TYPE, WILL ECHO, WILL SUPPRESS-GO-AHEAD,
DO NAWS, then TERMINAL-TYPE SEND), then an ATASCII screen (clear, an inverse title, a box of
graphics characters, the card suits, arrows, an ESC-shown control code). Then it reads; the bytes it
gets are logged to LOGFILE in hex ("caller N: ..."): the negotiation answers, the terminal
type, then everything typed, on one line when the call ends. The caller's commands, one byte
each:
  'a'  an ANSI / VT52 screen (for the ASCII mode): ESC [ 2 J, positions, bold, inverse
  'e'  the bytes "e!" and a CR LF echoed (an echo check), and IAC IAC (a data byte 255)
  'q'  "Bye." then the server closes the connection (the remote close)
Anything else is only logged. No internet: loopback only."""
import socket, sys, time, select

IAC, DO, DONT, WILL, WONT, SB, SE = 255, 253, 254, 251, 252, 250, 240
TTYPE, ECHO, SGA, NAWS = 24, 1, 3, 31

def atascii_screen():
    s = bytes([0x7D])                                   # clear
    s += bytes(c | 0x80 for c in b' ATASCII TEST BOARD ') + bytes([0x9B, 0x9B])
    s += bytes([0x11] + [0x12] * 20 + [0x05, 0x9B])      # a box: top
    s += bytes([0x7C]) + b' Hearts ' + bytes([0x00, 0x20, 0x10, 0x20, 0x60, 0x20, 0x7B]) + b'     ' + bytes([0x7C, 0x9B])
    s += bytes([0x01] + [0x12] * 20 + [0x04, 0x9B])
    s += bytes([0x7C]) + b' ' + bytes([0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x14, 0x15, 0x16, 0x19, 0x06, 0x07, 0x02]) + b'    ' + bytes([0x7C, 0x9B])
    s += bytes([0x1A] + [0x12] * 20 + [0x03, 0x9B, 0x9B])
    s += b'Arrows: ' + bytes([0x1B, 0x1C, 0x1B, 0x1D, 0x1B, 0x1E, 0x1B, 0x1F]) + b'  Esc: ' + bytes([0x1B, 0x1B]) + bytes([0x9B])
    s += b'Inverse: ' + bytes(c | 0x80 for c in b'Ready') + b' ' + bytes([0x80 | 0x14, 0x80 | 0x60]) + bytes([0x9B, 0x9B])
    s += b'Type a, e or q> '
    return s

def ansi_screen():
    e = b'\x1b['
    s = e + b'2J' + e + b'H'
    s += e + b'1mANSI test' + e + b'0m on 80 columns' + b'\r\n\r\n'
    s += e + b'7m inverse ' + e + b'27m and ' + e + b'1;7mbold inverse' + e + b'm\r\n'
    s += e + b'10;30Hat row 10, column 30'
    s += b'\x1bY' + bytes([32 + 12, 32 + 5]) + b'VT52 at row 13, column 6'
    s += e + b'20;1H' + b'x' * 80                       # a full line (no extra wrap)
    s += b'next line' + e + b'5D' + e + b'K' + b'\r\nType a, e or q> '
    return s

def main():
    portfile, logfile = sys.argv[1], sys.argv[2]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    open(portfile, 'w').write(str(srv.getsockname()[1]))
    log = open(logfile, 'w')
    end = time.time() + 150
    for n in range(1, 4):
        r, _, _ = select.select([srv], [], [], max(0, end - time.time()))
        if not r:
            break
        c, _ = srv.accept()
        c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        c.sendall(bytes([IAC, DO, TTYPE, IAC, WILL, ECHO, IAC, WILL, SGA, IAC, DO, NAWS]))
        got = read_for(c, 1.0)
        log.write(f'caller {n}: negotiation answers: {got.hex(" ")}\n')
        c.sendall(bytes([IAC, SB, TTYPE, 1, IAC, SE]))
        got = read_for(c, 1.0)
        log.write(f'caller {n}: terminal type: {got.hex(" ")}\n')
        log.flush()
        c.sendall(atascii_screen())
        typed = b''
        how = 'the server stopped waiting'
        while time.time() < end:
            r, _, _ = select.select([c], [], [], max(0, end - time.time()))
            if not r:
                break
            try:
                b = c.recv(256)
            except OSError:
                b = b''
            if not b:
                how = 'closed by the caller'
                break
            typed += b
            if b'a' in b:
                c.sendall(ansi_screen())
            if b'e' in b:
                c.sendall(b'e!\r\n' + bytes([IAC, IAC]) + b'\r\n')
            if b'q' in b:
                c.sendall(b'\r\nBye.\r\n')
                time.sleep(0.3)
                how = 'the server closed it'
                break
        log.write(f'caller {n}: typed:{" " + typed.hex(" ") if typed else ""}\n')
        log.write(f'caller {n}: {how}\n')
        log.flush()
        c.close()
    log.write('server: done\n')
    log.close()

def read_for(c, secs):
    """the bytes that come within secs"""
    got, t = b'', time.time() + secs
    while True:
        r, _, _ = select.select([c], [], [], max(0, t - time.time()))
        if not r:
            return got
        b = c.recv(256)
        if not b:
            return got
        got += b

main()
