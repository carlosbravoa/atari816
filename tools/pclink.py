# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""pclink.py - the Atari816 PC link, PC side.

The protocol is described in Docs/04-pc-link.md. This module has:

  - the frame format (encode, and a parser that finds frames in a byte stream),
  - Link: one connection over the USB serial port (sessions, acknowledgements, resending,
    keep-alive, reconnecting when the board goes away and comes back),
  - FileServer: the PC volume (one shared folder, never anything outside it),
  - DevClient: requests on the developer channel, either through a running gateway
    (a Unix socket in the user's runtime directory) or straight over the serial port,
  - NetServer: the internet for the Atari816 (TCP connections on channel 4, URLs fetched
    over HTTP, HTTPS and FTP on channel 5),
  - Gateway: what `atari816-link` runs.

Only the Python standard library and pyserial are needed.
"""
import binascii
import calendar
import errno
import ftplib
import http.client
import itertools
import os
import queue
import select
import shutil
import socket
import ssl
import stat as statmod
import struct
import sys
import threading
import time
import urllib.parse

import pdfprint   # (step 3) print jobs as PDF

BAUD = 1_500_000
MAXPAY = 1040            # largest payload of a frame
CHUNK = 1024             # file data per frame
PROTO = 1

CH_CTL, CH_LOG, CH_FILES, CH_DEV = 0, 1, 2, 3
CH_NET, CH_FETCH, CH_PRINT, CH_CLASSIC = 4, 5, 6, 7       # (6 and 7: reserved for step 3)
NCH = 16
F_DATA, F_ACK = 0x01, 0x02
MORE = 0x01
SV_FILES, SV_DEV, SV_NET, SV_FETCH = 0x01, 0x02, 0x04, 0x08
SV_PRINT = 0x10         # (step 3) marked files written to Printouts/*.pdf become PDF files

C_HELLO, C_HELLO_ACK, C_PING, C_PONG, C_BYE, C_NOSESSION, C_BOOT = 1, 2, 3, 4, 5, 6, 7

T_RETRY = 0.25           # resend a frame after this long without its ACK
N_RETRY = 14             # tries before the link is declared down
T_SILENT = 3.5           # no frame from the board for this long: the session is over
T_PING = 1.0
T_HELLO = 1.0

# FatFs result codes the board understands (and Horizon shows as $40 + n)
FR_OK, FR_DISK_ERR, FR_INT_ERR, FR_NOT_READY, FR_NO_FILE, FR_NO_PATH = 0, 1, 2, 3, 4, 5
FR_INVALID_NAME, FR_DENIED, FR_EXIST, FR_INVALID_OBJECT = 6, 7, 8, 9
FR_TOO_MANY_OPEN_FILES = 18
R_BADHANDLE, R_UNSUPPORTED = 0x80, 0x82

# files channel ops (board -> PC)
F_OPEN, F_CLOSE, F_READ, F_WRITE, F_SEEK, F_STAT, F_READDIR = 1, 2, 3, 4, 5, 6, 7
F_MKDIR, F_DELETE, F_RENAME, F_LOAD = 8, 9, 10, 0x10

# developer channel ops (PC -> board)
D_INFO, D_PUT, D_RESTART816, D_RUN, D_COLD, D_WARM, D_EJECT = 1, 2, 3, 4, 5, 6, 7
D_KEY, D_MOUSE, D_TYPE, D_PEEK, D_POKE, D_FWPEEK, D_PEEK816 = 8, 9, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E
D_ECHO, D_SOURCE, D_SINK = 0x0F, 0x10, 0x11

EPOCH2000 = calendar.timegm((2000, 1, 1, 0, 0, 0))


class LinkError(Exception):
    pass


class LinkDown(LinkError):
    pass


def crc16(data, init=0xFFFF):
    """CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection)."""
    return binascii.crc_hqx(data, init)


def frame(ch, seq, ack, flags, payload=b""):
    if len(payload) > MAXPAY:
        raise ValueError("payload too long")
    hdr = struct.pack("<HBBBB", len(payload), ch, seq, ack, flags)
    body = hdr + bytes([crc16(hdr) & 0xFF]) + payload
    return b"\xa8\x16" + body + struct.pack("<H", crc16(body))


class Parser:
    """Finds frames in a byte stream. Bytes that are not part of a good frame are skipped
    (and counted); after a bad frame the search goes on from the byte after its start, so
    a good frame inside garbage is never lost."""

    def __init__(self):
        self.buf = bytearray()
        self.skipped = 0
        self.bad = 0

    def feed(self, data):
        self.buf += data
        out = []
        buf = self.buf
        while True:
            i = buf.find(b"\xa8\x16")
            if i < 0:
                keep = 1 if buf[-1:] == b"\xa8" else 0
                self.skipped += len(buf) - keep
                del buf[:len(buf) - keep]
                break
            if i:
                self.skipped += i
                del buf[:i]
            if len(buf) < 9:
                break
            ln, ch = buf[2] | buf[3] << 8, buf[4]
            if crc16(bytes(buf[2:8])) & 0xFF != buf[8] or ln > MAXPAY or ch >= NCH:
                self.bad += 1
                del buf[:1]
                continue
            need = 11 + ln
            if len(buf) < need:
                break
            body = bytes(buf[2:9 + ln])
            if crc16(body) != (buf[9 + ln] | buf[10 + ln] << 8):
                self.bad += 1
                del buf[:1]
                continue
            out.append((ch, buf[5], buf[6], buf[7], body[7:]))
            del buf[:need]
        return out


def now2000():
    """Local time now, seconds since 2000-01-01 00:00 (what the board's clock counts)."""
    lt = time.localtime()
    return calendar.timegm(lt[:6] + (0, 0, 0)) - EPOCH2000


def other_boards():
    """Serial numbers of USB debuggers that are NOT an Atari816 (another project's board on
    the same PC): one a line in ~/.config/atari816/not-my-boards, and/or separated by commas
    in $ATARI816_SKIP_SERIALS. Their ports are never listed, so never opened."""
    out = set(x.strip() for x in os.environ.get("ATARI816_SKIP_SERIALS", "").split(",") if x.strip())
    try:
        with open(os.path.expanduser("~/.config/atari816/not-my-boards")) as f:
            out |= set(ln.split("#")[0].strip() for ln in f) - {""}
    except OSError:
        pass
    return out


def list_ports():
    import serial.tools.list_ports
    skip = other_boards()
    return sorted((p for p in serial.tools.list_ports.comports()
                   if not (skip and p.serial_number and p.serial_number in skip)),
                  key=lambda p: p.device)


def auto_port():
    """The Tang Nano 20K's BL616 shows up as an FT2232-style pair (same VID:PID): interface
    0 is JTAG, interface 1 is the UART. Pick the second of a pair."""
    cands = [p for p in list_ports() if p.vid is not None]
    if not cands:
        raise LinkError("no USB serial port found (is the board connected? Linux: modprobe ftdi_sio)")
    for a, b in zip(cands, cands[1:]):
        if (a.vid, a.pid) == (b.vid, b.pid):
            return b.device
    if len(cands) == 1:
        return cands[0].device
    for p in cands:
        text = f"{p.description} {p.manufacturer or ''}".lower()
        if any(k in text for k in ("sipeed", "bl616", "jtag", "debug")):
            return p.device
    raise LinkError("cannot pick a port: " + ", ".join(p.device for p in cands) + " (use --port)")


class Link:
    """One PC link over a serial port. Threads: a reader (frames in, ACKs out) and a
    keeper (HELLO until the board answers, PING every second, the silence timeout, and
    reopening the port after it went away).

    on_frame(ch, payload): a DATA frame arrived (once, in order; already acknowledged).
    on_log(bytes):         a log line from the board.
    on_state(up, info):    the session started (info = the board's id string) or ended.
    Callbacks run in the reader thread: keep them short (hand work to a queue)."""

    def __init__(self, port=None, baud=BAUD, services=SV_DEV, name="atari816-link",
                 on_frame=None, on_log=None, on_state=None, reconnect=True, verbose=0):
        self.port_arg = port
        self.port = None
        self.baud = baud
        self.services = services
        self.name = name
        self.on_frame = on_frame
        self.on_log = on_log
        self.on_state = on_state
        self.reconnect = reconnect
        self.verbose = verbose
        self.ser = None
        self.up = False
        self.info = ""
        self.epoch = 0
        self.parser = Parser()
        self.cv = threading.Condition()
        self.wlock = threading.Lock()
        self.chlocks = [threading.Lock() for _ in range(NCH)]
        self.tx_seq = [0] * NCH
        self.rx_last = [0] * NCH
        self.acked = [0] * NCH
        self.nonce = 0
        self.last_rx = 0.0
        self.last_hello = 0.0
        self.last_ping = 0.0
        self.stopping = False
        self.retries = 0
        self.threads = []

    # ---- port ----
    def _open(self):
        import serial
        port = self.port_arg or auto_port()
        ser = serial.Serial(port, self.baud, timeout=0.02, exclusive=True)
        self.port = port
        self.parser = Parser()
        with self.cv:
            self.ser = ser
            self.cv.notify_all()

    def _lost_port(self, why):
        with self.cv:
            if self.ser is None:
                return
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None
            self._session(False)
        self._say(f"port closed: {why}")

    def _say(self, text):
        if self.verbose:
            sys.stderr.write(f"pclink: {text}\n")

    def start(self, wait=0.0):
        """Open the port (or keep trying, with reconnect) and start the threads. wait > 0:
        return once the session is up, LinkError after that many seconds."""
        if not self.reconnect:
            end = time.time() + 10                        # (busy for a few seconds after
            while True:                                   # openFPGALoader used the board)
                try:
                    self._open()
                    break
                except Exception as e:
                    if "busy" not in str(e).lower() or time.time() > end:
                        raise LinkError(f"cannot open the serial port: {e}")
                    time.sleep(0.5)
        else:
            try:
                self._open()
            except Exception as e:
                self._say(f"waiting for the board ({e})")
        for fn in (self._reader, self._keeper):
            t = threading.Thread(target=fn, daemon=True)
            t.start()
            self.threads.append(t)
        if wait:
            self.wait_up(wait)
        return self

    def wait_up(self, timeout):
        end = time.time() + timeout
        with self.cv:
            while not self.up:
                left = end - time.time()
                if left <= 0:
                    raise LinkError("no answer from the Atari816 (is it on, and the firmware new enough?)")
                self.cv.wait(min(left, 0.1))

    def close(self):
        if self.up:
            try:
                self._write(frame(CH_CTL, 0, 0, 0, bytes([C_BYE])))
            except Exception:
                pass
        self.stopping = True
        with self.cv:
            self._session(False)
            ser, self.ser = self.ser, None
        if ser:
            try:
                ser.flush()
                ser.close()
            except Exception:
                pass

    # ---- sending ----
    def _write(self, data):
        with self.wlock:
            ser = self.ser
            if ser is None:
                raise LinkDown("the serial port is closed")
            try:
                ser.write(data)
            except Exception as e:
                raise LinkDown(f"serial write: {e}")

    def _hello(self):
        self.nonce = int.from_bytes(os.urandom(4), "little") or 1
        p = struct.pack("<BBIIB", C_HELLO, PROTO, self.nonce, now2000() & 0xFFFFFFFF,
                        self.services) + self.name.encode()[:32]
        self.last_hello = time.time()
        try:
            self._write(frame(CH_CTL, 0, 0, 0, p))
        except LinkDown:
            pass

    def send(self, ch, payload, timeout=60.0):
        """Send one DATA frame and wait for its ACK, sending it again after T_RETRY (then
        less often). The board may hold back the ACK while it is busy (a developer request
        while it serves the PC volume), so this waits as long as the board is alive, up to
        timeout seconds (LinkError, the session stays). LinkDown if the session ends."""
        with self.chlocks[ch]:
            with self.cv:
                if not self.up:
                    raise LinkDown("no session with the Atari816")
                ep = self.epoch
                seq = self.tx_seq[ch] % 255 + 1
                self.tx_seq[ch] = seq
            data = frame(ch, seq, 0, F_DATA, payload)
            start = time.time()
            wait = T_RETRY
            t = 0
            while True:
                if t:
                    self.retries += 1
                t += 1
                self._write(data)
                end = time.time() + wait
                wait = min(1.0, wait * 1.5) if t > 4 else wait
                with self.cv:
                    while True:
                        if self.epoch != ep or not self.up:
                            raise LinkDown("the session ended")
                        if self.acked[ch] == seq:
                            return
                        left = end - time.time()
                        if left <= 0:
                            break
                        self.cv.wait(left)
                if time.time() - start > timeout:
                    raise LinkError("the Atari816 did not take the frame (busy)")

    def send_many(self, ch, payloads, window=2, timeout=60.0):
        """Send DATA frames with up to `window` of them unacknowledged (go back N: after a
        timeout, everything from the oldest unacknowledged frame is sent again). The board
        takes a frame only if it is the next one, so the order always holds."""
        if len(payloads) <= 1 or window <= 1:
            for p in payloads:
                self.send(ch, p, timeout)
            return
        with self.chlocks[ch]:
            with self.cv:
                if not self.up:
                    raise LinkDown("no session with the Atari816")
                ep = self.epoch
                first = self.tx_seq[ch] % 255 + 1
                self.tx_seq[ch] = (first - 1 + len(payloads) - 1) % 255 + 1
            seqs = [(first - 1 + i) % 255 + 1 for i in range(len(payloads))]
            frames = [frame(ch, sq, 0, F_DATA, p) for sq, p in zip(seqs, payloads)]
            base = nxt = 0
            sent = 0.0
            start = time.time()
            while base < len(frames):
                while nxt < len(frames) and nxt < base + window:
                    if nxt == base:
                        sent = time.time()
                    self._write(frames[nxt])
                    nxt += 1
                with self.cv:
                    while True:
                        if self.epoch != ep or not self.up:
                            raise LinkDown("the session ended")
                        d = (self.acked[ch] - seqs[base]) % 255     # acks are cumulative
                        if d < nxt - base:
                            base += d + 1
                            sent = time.time()
                            break
                        left = sent + T_RETRY - time.time()
                        if left <= 0:
                            self.retries += 1
                            nxt = base                               # go back
                            break
                        self.cv.wait(left)
                if time.time() - start > timeout + len(frames) * 0.05:
                    raise LinkError("the Atari816 did not take the frames (busy)")

    # ---- receiving ----
    def _session(self, up, info=""):
        # (called with self.cv held)
        if self.up == up:
            return
        self.up = up
        self.epoch += 1
        if up:
            self.tx_seq = [0] * NCH
            self.rx_last = [0] * NCH
            self.acked = [0] * NCH
            self.info = info
            self.last_rx = time.time()
        self.cv.notify_all()
        if self.on_state:
            try:
                self.on_state(up, info)
            except Exception as e:
                self._say(f"on_state: {e}")

    def _reader(self):
        while not self.stopping:
            ser = self.ser
            if ser is None:
                time.sleep(0.05)
                continue
            try:
                data = ser.read(max(1, min(65536, ser.in_waiting)))
            except Exception as e:
                self._lost_port(e)
                continue
            if not data:
                continue
            for f in self.parser.feed(data):
                try:
                    self._frame(*f)
                except LinkDown:
                    pass

    def _frame(self, ch, seq, ack, flags, payload):
        with self.cv:
            self.last_rx = time.time()
            if flags & F_ACK:
                self.acked[ch] = ack
                self.cv.notify_all()
        if not flags & F_DATA:
            if ch == CH_CTL and payload:
                self._ctl(payload)
            elif ch == CH_LOG and self.on_log and self.up:   # (not old lines the BL616 kept)
                self.on_log(payload)
            return
        if not self.up:
            return
        if seq == self.rx_last[ch] or seq == self.rx_last[ch] % 255 + 1:
            self._write(frame(ch, 0, seq, F_ACK))
        with self.cv:
            if seq != self.rx_last[ch] % 255 + 1:
                return                           # a repeat (our ACK was lost), or not the next
            self.rx_last[ch] = seq
        if self.on_frame:
            self.on_frame(ch, payload)

    def _ctl(self, p):
        op = p[0]
        if op == C_HELLO_ACK and len(p) >= 8:
            nonce = struct.unpack_from("<I", p, 2)[0]
            if nonce == self.nonce:
                with self.cv:
                    self._session(True, p[8:].decode("latin1", "replace"))
                self._say(f"session up: {self.info}")
        elif op in (C_NOSESSION, C_BOOT):
            with self.cv:
                self._session(False)
            self._hello()
        elif op == C_BYE:
            with self.cv:
                self._session(False)

    def _keeper(self):
        while not self.stopping:
            time.sleep(0.1)
            if self.ser is None:
                if not self.reconnect:
                    continue
                try:
                    self._open()
                    self._say(f"port {self.port} open")
                    self._hello()
                except Exception:
                    time.sleep(1.0)
                continue
            t = time.time()
            if not self.up:
                if t - self.last_hello > T_HELLO:
                    self._hello()
                continue
            if t - self.last_rx > T_SILENT:
                with self.cv:
                    self._session(False)
                self._say("no answer from the board: session over")
                continue
            if t - self.last_ping > T_PING:
                self.last_ping = t
                try:
                    self._write(frame(CH_CTL, 0, 0, 0, struct.pack("<BI", C_PING, self.nonce)))
                except LinkDown:
                    pass


# ======================================================================================
# The PC volume: one shared folder
# ======================================================================================

def fat_time(t):
    """POSIX time -> FAT date/time (local), fdate << 16 | ftime."""
    lt = time.localtime(t)
    y = lt.tm_year
    if y < 1980:
        return (0 << 25 | 1 << 21 | 1 << 16)
    if y > 2107:
        y = 2107
    return ((y - 1980) << 25 | lt.tm_mon << 21 | lt.tm_mday << 16 |
            lt.tm_hour << 11 | lt.tm_min << 5 | lt.tm_sec // 2)


def errno_fr(e, missing_parent=False):
    n = getattr(e, "errno", None)
    if n == errno.ENOENT:
        return FR_NO_PATH if missing_parent else FR_NO_FILE
    if n == errno.ENOTDIR:
        return FR_NO_PATH
    if n in (errno.EACCES, errno.EPERM, errno.EROFS, errno.ENOTEMPTY, errno.ENOSPC,
             errno.EBUSY, errno.EISDIR, errno.ELOOP, errno.EXDEV):
        return FR_DENIED
    if n == errno.EEXIST:
        return FR_EXIST
    if n in (errno.ENAMETOOLONG, errno.EINVAL, errno.EILSEQ):
        return FR_INVALID_NAME
    if n in (errno.EMFILE, errno.ENFILE):
        return FR_TOO_MANY_OPEN_FILES
    return FR_DISK_ERR


class Refused(Exception):
    def __init__(self, code):
        self.code = code


class FileServer:
    """Serves the files channel from one folder. Every path the board sends is relative to
    that folder; nothing outside it is ever opened, listed, created, renamed or deleted:
    '..' and '.' components and hidden names (starting with '.') are refused, and the real
    path (symlinks resolved) of whatever is touched must be inside the folder.

    A file opened with mode 2 (create) is written under a temporary name in the hidden
    folder PARTIAL and moved onto its real name at CLOSE. When the session ends with it still
    open, the temporary file is deleted and an old file of that name stays as it was. What a
    killed gateway left in PARTIAL is deleted when the next one starts. Modes 1 and 3 write
    in place, as before."""

    MAXFILES = 16
    PARTIAL = ".atari816-partial"
    names = itertools.count(1)        # temporary names: <pid>-<n>.part, unique in a process

    def __init__(self, folder, send, log=None, readonly=False, send_many=None):
        self.root = os.path.realpath(folder)
        if not os.path.isdir(self.root):
            raise LinkError(f"not a folder: {folder}")
        self.send = send              # send(payload): one DATA frame on the files channel
        self.send_many = send_many    # send_many(payloads): several, with a window
        self.log = log or (lambda s: None)
        self.readonly = readonly
        self.files = {}               # handle -> fd
        self.temps = {}               # handle -> (temporary path, final path), mode 2
        self.pending = {}             # tag -> list of request frames (multi-frame WRITE)
        self.lock = threading.Lock()  # requests and reset() (the gateway's close) take turns
        self.partial = os.path.join(self.root, self.PARTIAL)
        self._clean_partial()

    def reset(self):
        """The session is over: close every file; unfinished mode 2 files are deleted."""
        with self.lock:
            for h, fd in self.files.items():
                try:
                    os.close(fd)
                except OSError:
                    pass
                if h in self.temps:
                    self._unlink(self.temps[h][0])
            self.files.clear()
            self.temps.clear()
            self.pending.clear()

    def _unlink(self, path):
        try:
            os.unlink(path)
        except OSError:
            pass

    def _clean_partial(self):
        """Delete the regular files left in PARTIAL (a gateway that was killed), then the
        folder if it is empty. Nothing else: a link there is not followed."""
        try:
            if not statmod.S_ISDIR(os.lstat(self.partial).st_mode):
                return
            names = os.listdir(self.partial)
        except OSError:
            return
        for n in names:
            p = os.path.join(self.partial, n)
            try:
                if statmod.S_ISREG(os.lstat(p).st_mode):
                    os.unlink(p)
            except OSError:
                pass
        try:
            os.rmdir(self.partial)
        except OSError:
            pass

    def _open_temp(self, path, fl):
        """Mode 2: a new empty file in PARTIAL for `path` (nothing is changed there yet)."""
        if os.path.islink(path):
            raise Refused(FR_DENIED)                     # (as O_NOFOLLOW refused it before)
        if os.path.exists(path) and not os.access(path, os.W_OK):
            raise Refused(FR_DENIED)
        if not os.access(os.path.dirname(path), os.W_OK | os.X_OK):
            raise Refused(FR_DENIED)
        try:
            os.mkdir(self.partial, 0o700)
        except FileExistsError:
            pass
        st = os.lstat(self.partial)
        if not statmod.S_ISDIR(st.st_mode):
            raise Refused(FR_DENIED)                     # not our folder: leave it alone
        tmp = os.path.join(self.partial, f"{os.getpid()}-{next(self.names)}.part")
        fd = os.open(tmp, os.O_RDWR | os.O_CREAT | os.O_EXCL | fl, 0o644)
        try:
            if os.path.exists(path):                     # an old file keeps its permissions
                os.fchmod(fd, statmod.S_IMODE(os.stat(path).st_mode))
        except OSError:
            pass
        return fd, tmp

    def _finish(self, tmp, final):
        """CLOSE of a mode 2 file: move it onto its real name. The temporary file is gone
        afterwards, whatever happens."""
        try:
            if (not self._inside(os.path.realpath(os.path.dirname(final)))
                    or os.path.islink(final) or os.path.isdir(final)):
                raise Refused(FR_DENIED)
            self._printout(tmp, final)
            try:
                os.replace(tmp, final)
            except OSError as e:
                if e.errno != errno.EXDEV:
                    raise
                fl = getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0)
                fd = os.open(final, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | fl, 0o644)
                with os.fdopen(fd, "wb") as out, open(tmp, "rb") as src:
                    shutil.copyfileobj(src, out)
        finally:
            self._unlink(tmp)

    def _printout(self, tmp, final):
        """(Step 3) A print job from the Atari816: a file `Printouts/NAME.pdf` (directly in the
        folder Printouts at the top of the shared folder) that starts with the marker becomes the
        PDF (tools/pdfprint.py) before it is put in place; the text itself is not kept."""
        d = os.path.dirname(os.path.realpath(final)) if os.path.exists(final) else os.path.realpath(os.path.dirname(final))
        if (os.path.dirname(d) != self.root or os.path.basename(d).lower() != "printouts"
                or not final.lower().endswith(".pdf")):
            return
        with open(tmp, "rb") as f:
            data = f.read()
        if not pdfprint.is_job(data):
            return
        pdf = pdfprint.convert(data)
        with open(tmp, "wb") as f:
            f.write(pdf)
        if self.log:
            self.log(f"print: {os.path.basename(final)} ({len(pdf)} bytes of PDF)")

    # ---- paths ----
    def _inside(self, real):
        return real == self.root or real.startswith(self.root + os.sep)

    def resolve(self, raw, create=False):
        """Board path (bytes, '/'-separated, relative to the folder) -> host path. Case-
        insensitive per component when the exact name is not there. create: the last
        component may be missing (its parent must exist). Raises Refused."""
        try:
            text = raw.decode("utf-8", "surrogateescape")
        except Exception:
            raise Refused(FR_INVALID_NAME)
        parts = [c for c in text.split("/") if c]
        cur = self.root
        for i, c in enumerate(parts):
            last = i == len(parts) - 1
            if c in (".", "..") or c.startswith(".") or "\\" in c or "\0" in c or len(c.encode("utf-8", "surrogateescape")) > 255:
                raise Refused(FR_INVALID_NAME)
            nxt = os.path.join(cur, c)
            if not os.path.lexists(nxt):
                try:
                    names = os.listdir(cur)
                except OSError:
                    raise Refused(FR_NO_PATH)
                low = c.casefold()
                hit = [n for n in names if n.casefold() == low and not n.startswith(".")]
                if hit:
                    nxt = os.path.join(cur, sorted(hit)[0])
                elif last and create:
                    nxt = os.path.join(cur, c)
                else:
                    raise Refused(FR_NO_FILE if last else FR_NO_PATH)
            real = os.path.realpath(nxt)
            if os.path.lexists(nxt) and not self._inside(real):
                raise Refused(FR_DENIED)                 # a symlink that leaves the folder
            if not last and not os.path.isdir(real):
                raise Refused(FR_NO_PATH)
            cur = nxt
        real = os.path.realpath(cur)
        if not self._inside(real if os.path.lexists(cur) else os.path.realpath(os.path.dirname(cur))):
            raise Refused(FR_DENIED)
        return cur

    # ---- requests ----
    def request(self, p):
        """One frame of a files request (from the reader thread's queue)."""
        if len(p) < 4:
            return
        op, tag, fl = p[0], p[1], p[2]
        if op == F_WRITE:
            self.pending.setdefault(tag, []).append(p[4:])
            if fl & MORE:
                return
            parts = self.pending.pop(tag)
            with self.lock:
                res, data = self._write_req(parts)
            self._reply(op, tag, res, data)
            return
        args = p[4:]
        try:
            with self.lock:
                res, data = self._do(op, args)
        except Refused as e:
            res, data = e.code, b""
        except OSError as e:
            res, data = errno_fr(e), b""
        self._reply(op, tag, res, data)

    def _reply(self, op, tag, res, data=b""):
        """The response: one frame, or one per CHUNK bytes of data (MORE on all but the last;
        the result is in the last)."""
        frames = []
        off = 0
        while True:
            part = data[off:off + CHUNK]
            off += len(part)
            last = off >= len(data)
            frames.append(bytes([op | 0x80, tag, 0 if last else MORE, res if last else 0]) + part)
            if last:
                break
        if self.send_many:
            self.send_many(frames)
        else:
            for f in frames:
                self.send(f)

    def _fd(self, h):
        fd = self.files.get(h)
        if fd is None:
            raise Refused(R_BADHANDLE)
        return fd

    def _write_req(self, parts):
        if not parts or len(parts[0]) < 4:
            return FR_INT_ERR, b""
        h = parts[0][0]
        n = 0
        try:
            fd = self._fd(h)
            for part in parts:
                data = part[4:]
                while data:
                    k = os.write(fd, data)
                    n += k
                    data = data[k:]
        except Refused as e:
            return e.code, struct.pack("<I", n)
        except OSError as e:
            return errno_fr(e), struct.pack("<I", n)
        return FR_OK, struct.pack("<I", n)

    def _path(self, args, create=False):
        raw = args.split(b"\0", 1)[0]
        return self.resolve(raw, create)

    def _guard_write(self):
        if self.readonly:
            raise Refused(FR_DENIED)

    def _do(self, op, a):
        if op == F_OPEN:                                  # mode u8, 3 x 0, path
            mode = a[0] & 3
            if mode:
                self._guard_write()
            path = self._path(a[4:], create=mode >= 2)
            if os.path.isdir(path):
                return FR_NO_FILE, b""
            if len(self.files) >= self.MAXFILES:
                return FR_TOO_MANY_OPEN_FILES, b""
            fl = getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0)
            if mode == 0:
                fd = os.open(path, os.O_RDONLY | fl)
            elif mode == 1:
                fd = os.open(path, os.O_RDWR | fl)
            elif mode == 2:
                fd, tmp = self._open_temp(path, fl)
            else:                                         # (1 and 3 write in place)
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | fl, 0o644)
                os.lseek(fd, 0, os.SEEK_END)
            h = next(i for i in range(256) if i not in self.files)
            self.files[h] = fd
            if mode == 2:
                self.temps[h] = (tmp, path)
            size = os.fstat(fd).st_size
            self.log(f"open {path!r} mode {mode} -> {h}")
            return FR_OK, struct.pack("<BxxxI", h, size & 0xFFFFFFFF)
        if op == F_CLOSE:
            fd = self.files.pop(a[0], None)
            if fd is None:
                return R_BADHANDLE, b""
            temp = self.temps.pop(a[0], None)
            try:
                os.close(fd)
            except OSError:
                if temp:
                    self._unlink(temp[0])
                raise
            if temp:
                self._finish(*temp)
            return FR_OK, b""
        if op == F_READ:                                  # handle, 3 x 0, len u32
            fd = self._fd(a[0])
            n = struct.unpack_from("<I", a, 4)[0]
            out = bytearray()
            while len(out) < n:
                d = os.read(fd, n - len(out))
                if not d:
                    break
                out += d
            return FR_OK, bytes(out)
        if op == F_SEEK:                                  # handle, 3 x 0, offset u32
            fd = self._fd(a[0])
            pos = os.lseek(fd, struct.unpack_from("<I", a, 4)[0], os.SEEK_SET)
            return FR_OK, struct.pack("<I", pos & 0xFFFFFFFF)
        if op == F_STAT:                                  # path
            path = self._path(a)
            st = os.stat(path)
            return FR_OK, self._statrec(path, st)
        if op == F_READDIR:                               # skip u16, room u16, path
            skip, room = struct.unpack_from("<HH", a, 0)
            path = self._path(a[4:])
            if not os.path.isdir(path):
                return FR_NO_PATH, b""
            names = sorted((n for n in os.listdir(path) if not n.startswith(".")),
                           key=lambda n: (n.casefold(), n))
            out = bytearray()
            count = 0
            for n in names[skip:]:
                full = os.path.join(path, n)
                try:
                    if not self._inside(os.path.realpath(full)):
                        continue
                    st = os.stat(full)
                except OSError:
                    continue
                nb = n.encode("utf-8", "surrogateescape")
                if len(nb) > 255:
                    continue
                isdir = statmod.S_ISDIR(st.st_mode)
                ent = struct.pack("<IBB", 0 if isdir else st.st_size & 0xFFFFFFFF,
                                  self._attr(full, st), len(nb)) + nb
                if len(out) + len(ent) > room:
                    break
                out += ent
                count += 1
            return FR_OK, struct.pack("<I", count) + bytes(out)
        if op == F_MKDIR:
            self._guard_write()
            path = self._path(a, create=True)
            os.mkdir(path)
            return FR_OK, b""
        if op == F_DELETE:
            self._guard_write()
            path = self._path(a)
            if path == self.root:
                return FR_DENIED, b""
            if os.path.isdir(path) and not os.path.islink(path):
                os.rmdir(path)
            else:
                os.unlink(path)
            return FR_OK, b""
        if op == F_RENAME:                                # old \0 new
            self._guard_write()
            old_raw, _, rest = a.partition(b"\0")
            new_raw = rest.split(b"\0", 1)[0]
            old = self.resolve(old_raw)
            new = self.resolve(new_raw, create=True)
            if old == self.root:
                return FR_DENIED, b""
            if os.path.lexists(new) and os.path.realpath(new) != os.path.realpath(old):
                return FR_EXIST, b""
            os.rename(old, new)
            return FR_OK, b""
        if op == F_LOAD:                                  # path: the whole file
            path = self._path(a)
            if os.path.isdir(path):
                return FR_NO_FILE, b""
            with open(path, "rb") as f:
                data = f.read(16 << 20)
            return FR_OK, data
        return R_UNSUPPORTED, b""

    def _attr(self, path, st):
        if statmod.S_ISDIR(st.st_mode):
            return 0x10
        return 0x20 if os.access(path, os.W_OK) else 0x01

    def _statrec(self, path, st):
        isdir = statmod.S_ISDIR(st.st_mode)
        return struct.pack("<IBxxxI", 0 if isdir else st.st_size & 0xFFFFFFFF,
                           self._attr(path, st), fat_time(st.st_mtime))


# ======================================================================================
# Developer channel clients
# ======================================================================================

def sock_path():
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not base or not os.path.isdir(base):
        base = os.path.join("/tmp", f"atari816-{getattr(os, 'getuid', lambda: 0)()}")
    return os.path.join(base, "atari816-link.sock")


# Messages on the gateway's Unix socket: u32 length (of type + data), u8 type, data.
#   'R' client -> gateway: one frame payload of a developer request
#   'P' gateway -> client: one frame payload of the response
#   'S' client -> gateway: send me the board's log ('L' messages) from now on
#   'L' gateway -> client: one log line
#   'E' gateway -> client: the request failed (text)
#   'I' client -> gateway: the link state; gateway -> client: text
def sock_send(s, typ, data=b""):
    s.sendall(struct.pack("<IB", len(data) + 1, typ) + data)


def sock_recv(s):
    hdr = b""
    while len(hdr) < 5:
        d = s.recv(5 - len(hdr))
        if not d:
            raise EOFError
        hdr += d
    n, typ = struct.unpack("<IB", hdr)
    data = bytearray()
    while len(data) < n - 1:
        d = s.recv(min(65536, n - 1 - len(data)))
        if not d:
            raise EOFError
        data += d
    return typ, bytes(data)


class DevClient:
    """Requests on the developer channel. Uses the running gateway if there is one, else
    opens the serial port itself (then the PC volume is not served meanwhile)."""

    def __init__(self, port=None, timeout=10.0, verbose=0):
        self.tag = 0
        self.timeout = timeout
        self.logs = queue.Queue()
        self.log_cb = None
        self.sock = None
        self.link = None
        path = sock_path()
        if port is None and os.path.exists(path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(path)
                self.sock = s
                self.via = "gateway"
                self.resp = queue.Queue()
                t = threading.Thread(target=self._sock_reader, daemon=True)
                t.start()
                return
            except OSError:
                self.sock = None
        self.resp = queue.Queue()
        self.link = Link(port=port, services=SV_DEV, name="atari816 tools",
                         on_frame=self._on_frame, on_log=self._on_log,
                         reconnect=False, verbose=verbose)
        self.via = "serial"
        try:
            self.link.start(wait=5.0)
        except Exception:
            self.link.close()
            raise

    # ---- plumbing ----
    def _on_frame(self, ch, payload):
        if ch == CH_DEV:
            self.resp.put(payload)

    def _on_log(self, data):
        if self.log_cb:
            self.log_cb(data)
        else:
            self.logs.put(data)

    def _sock_reader(self):
        try:
            while True:
                typ, data = sock_recv(self.sock)
                if typ == ord("P"):
                    self.resp.put(data)
                elif typ == ord("E"):
                    self.resp.put(LinkError(data.decode("utf-8", "replace")))
                elif typ == ord("L"):
                    self._on_log(data)
                elif typ == ord("I"):
                    self.resp.put(data)
        except (EOFError, OSError):
            self.resp.put(LinkError("the gateway closed the connection"))

    def subscribe_log(self, cb=None):
        """Receive the board's log lines (cb(bytes), or read them from self.logs)."""
        self.log_cb = cb
        if self.sock:
            sock_send(self.sock, ord("S"))

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None
        if self.link:
            self.link.close()
            self.link = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def _send_frame(self, payload):
        if self.sock:
            sock_send(self.sock, ord("R"), payload)
        else:
            self.link.send(CH_DEV, payload)

    def request(self, op, args=b"", frames=(), timeout=None, progress=None):
        """Send a request (the first frame: args; then each item of frames as a frame of its
        own, MORE on all but the last) and collect the response stream. Returns (result,
        data). progress(done, total) counts frames sent."""
        self.tag = self.tag % 255 + 1
        tag = self.tag
        while not self.resp.empty():                     # anything left from an old request
            self.resp.get_nowait()
        frames = list(frames)
        total = 1 + len(frames)
        self._send_frame(bytes([op, tag, MORE if frames else 0, 0]) + args)
        for i, f in enumerate(frames):
            if progress:
                progress(i + 1, total)
            self._send_frame(bytes([op, tag, MORE if i < len(frames) - 1 else 0, 0]) + f)
        if progress:
            progress(total, total)
        out = bytearray()
        to = timeout or self.timeout
        while True:
            try:
                p = self.resp.get(timeout=to)
            except queue.Empty:
                raise LinkError(f"no answer to request {op:#04x}")
            if isinstance(p, Exception):
                raise p
            if len(p) < 4 or p[0] != op | 0x80 or p[1] != tag:
                continue
            out += p[4:]
            if not p[2] & MORE:
                return p[3], bytes(out)

    def state(self):
        if self.sock:
            sock_send(self.sock, ord("I"))
            p = self.resp.get(timeout=5)
            if isinstance(p, Exception):
                raise p
            return p.decode("utf-8", "replace")
        return f"serial {self.link.port}: " + ("session up, " + self.link.info if self.link.up else "no session")


# ======================================================================================
# The internet: channels 4 (Net) and 5 (Fetch)
# ======================================================================================

# stream ops: board -> PC, PC -> board
N_OPEN, N_SEND, N_CREDIT, N_CLOSE = 0x01, 0x02, 0x03, 0x04
N_OPENED, N_DATA, N_SCREDIT, N_END = 0x81, 0x82, 0x83, 0x84

# results of OPENED and END
R_NOSERVICE, R_BADADDR, R_NONAME, R_REFUSED, R_TIMEOUT = 0x8A, 0x8B, 0x8C, 0x8D, 0x8E
R_HTTP, R_CLOSED, R_TLS, R_TOOMANY, R_NETERR = 0x8F, 0x90, 0x91, 0x92, 0x93

RESULT_NAMES = {
    0: "ok", R_NOSERVICE: "no such service", R_BADADDR: "bad address",
    R_NONAME: "name not found", R_REFUSED: "refused or unreachable", R_TIMEOUT: "timeout",
    R_HTTP: "HTTP error", R_CLOSED: "closed", R_TLS: "TLS failed",
    R_TOOMANY: "too many streams", R_NETERR: "network error",
}

UNKNOWN_SIZE = 0xFFFFFFFF
REDIRECTS = (301, 302, 303, 307, 308)
USER_AGENT = "Atari816-link/1"


class NetError(Exception):
    """A stream failed with a result code (and, for HTTP, the status)."""

    def __init__(self, code, why="", status=0, size=UNKNOWN_SIZE):
        super().__init__(why or RESULT_NAMES.get(code, ""))
        self.code = code
        self.status = status
        self.size = size


class _Gone(Exception):
    """The stream was closed (CLOSE from the board, the session ended): say nothing more."""


def net_result(e):
    """The result code for an exception raised while making or using a connection."""
    if isinstance(e, NetError):
        return e.code
    if isinstance(e, (ssl.SSLError, ssl.CertificateError)):    # (before ValueError)
        return R_TLS
    if isinstance(e, socket.gaierror):
        if e.errno in (getattr(socket, "EAI_SERVICE", None), getattr(socket, "EAI_BADFLAGS", None)):
            return R_BADADDR
        return R_NONAME
    if isinstance(e, http.client.InvalidURL):
        return R_BADADDR
    if isinstance(e, (UnicodeError, ValueError)):
        return R_BADADDR
    if isinstance(e, TimeoutError):
        return R_TIMEOUT
    if isinstance(e, (ftplib.error_perm, ftplib.error_temp, ConnectionRefusedError)):
        return R_REFUSED
    if isinstance(e, OSError) and e.errno in (errno.ECONNREFUSED, errno.EHOSTUNREACH,
                                              errno.ENETUNREACH, errno.EHOSTDOWN,
                                              errno.EADDRNOTAVAIL, errno.ENETDOWN):
        return R_REFUSED
    return R_NETERR


def safe_url(url):
    """The URL as the gateway may print it: a password is replaced by ***. Careful rather
    than exact: a password with '/' or '@' in it (not percent-encoded) must not show either,
    so everything from a ':' before the first '/' to the last '@' before '?' or '#' goes."""
    scheme, sep, rest = url.partition("://")
    if not sep:
        return url
    slash = rest.find("/")
    slash = len(rest) if slash < 0 else slash
    query = min([i for i in (rest.find("?"), rest.find("#")) if i >= 0] or [len(rest)])
    colon = rest.find(":")
    at = rest.rfind("@", 0, query)
    if 0 <= colon < slash and at > colon:
        rest = rest[:colon] + ":***" + rest[at:]
    return scheme + sep + rest


def _unq(text):
    """Percent-decode a URL part to the exact bytes, as a latin-1 string (for ftplib)."""
    return urllib.parse.unquote_to_bytes(text or "").decode("latin-1")


class _Stream:
    """One stream (a SID on channel 4 or 5)."""

    def __init__(self, ch, sid, window):
        self.ch, self.sid = ch, sid
        self.credit = window              # bytes the board can still take
        self.cv = threading.Condition()
        self.closed = False               # closed: nothing more is sent for it
        self.socks = []                   # sockets to shut down at close
        self.sendq = queue.Queue()        # Net: SEND data for the socket
        self.wake_r = self.wake_w = None  # Net: wakes the stream's thread
        self.secret = None                # FTP password: never printed
        self.opened = False
        self.sent = 0
        self.timed_out = False            # the watchdog stopped it
        self.watch = None
        self.what = ""

    def wake(self):
        with self.cv:
            self.cv.notify_all()
        w = self.wake_w
        if w is not None:
            try:
                w.send(b"x")
            except OSError:
                pass

    def add_sock(self, s):
        with self.cv:
            if self.closed:
                s.close()
                raise _Gone
            self.socks.append(s)

    def close(self):
        """Close at once: shut down every socket (a thread blocked on one wakes up)."""
        with self.cv:
            self.closed = True
            socks, self.socks = self.socks, []
            if self.watch:
                self.watch.cancel()
            self.cv.notify_all()
        for s in socks:
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
            except OSError:
                pass
        self.wake()

    def close_socks(self):
        """Close the sockets but keep the stream (an HTTP redirect)."""
        with self.cv:
            socks, self.socks = self.socks, []
        for s in socks:
            try:
                s.close()
            except OSError:
                pass


class NetServer:
    """The internet for the Atari816: channel 4 (Net, outgoing TCP, TLS on the PC if asked)
    and channel 5 (Fetch: a URL over HTTP, HTTPS or FTP, streamed). Docs/04-pc-link.md,
    "Channels 4 and 5".

    send(ch, payload): send one DATA frame to the board (blocks until it is acknowledged;
    LinkError when it cannot be sent). frame(ch, payload) takes every DATA frame the board
    sends on channels 4 and 5; it never blocks (it may be called from the link's reader
    thread). Each stream has a thread of its own. reset() (the session ended) closes every
    stream at once. The gateway never listens: it only connects outwards."""

    MAXSTREAMS = 8

    def __init__(self, send, log=None):
        self.send = send
        self.log = log or (lambda s: None)
        self.t_net_connect = 15.0       # Net: lookup + connect + TLS
        self.t_fetch_head = 20.0        # Fetch: lookup + connect + TLS + the answer's headers
        self.t_fetch_body = 30.0        # Fetch: longest pause in the body
        self.max_redirects = 5
        self.send_credit = 4096         # Net: the send credit in OPENED
        self.ssl_context = None         # (default: ssl.create_default_context())
        self.lock = threading.Lock()
        self.streams = {CH_NET: {}, CH_FETCH: {}}
        self.emit_locks = {CH_NET: threading.Lock(), CH_FETCH: threading.Lock()}

    # ---- frames from the board (never block) ----
    def frame(self, ch, p):
        if ch not in self.streams or len(p) < 4:
            return
        op, sid = p[0], p[1]
        if op == N_OPEN:
            self._open(ch, sid, p[4:])
            return
        with self.lock:
            st = self.streams[ch].get(sid)
        if st is None:
            return                                    # (it may have crossed our END)
        if op == N_CREDIT and len(p) >= 6:
            with st.cv:
                st.credit += struct.unpack_from("<H", p, 4)[0]
                st.cv.notify_all()
            st.wake()
        elif op == N_SEND and ch == CH_NET and len(p) > 4:
            st.sendq.put(bytes(p[4:]))
            st.wake()
        elif op == N_CLOSE:
            self._forget(st)
            st.close()
            self.log(f"{self._name(st)}: closed by the Atari816 ({st.sent} bytes sent)")

    def reset(self):
        """The session is over: every stream ends at once, nothing more is sent."""
        with self.lock:
            sts = [st for t in self.streams.values() for st in t.values()]
            for t in self.streams.values():
                t.clear()
        for st in sts:
            st.close()
        if sts:
            self.log(f"internet: {len(sts)} stream(s) closed (the session ended)")

    def _name(self, st):
        return f"{'net' if st.ch == CH_NET else 'fetch'} {st.sid}"

    def _forget(self, st):
        with self.lock:
            t = self.streams[st.ch]
            if t.get(st.sid) is st:
                del t[st.sid]

    def _open(self, ch, sid, a):
        if len(a) < 4:
            return
        window = struct.unpack_from("<H", a, 0)[0]
        st = _Stream(ch, sid, window)
        with self.lock:
            old = self.streams[ch].pop(sid, None)
            full = len(self.streams[ch]) >= self.MAXSTREAMS
            if not full:
                self.streams[ch][sid] = st
        if old:
            old.close()
        if full:
            self.log(f"{self._name(st)}: refused, too many streams")
            target, args = self._refuse, (st,)
        elif ch == CH_NET:
            st.wake_r, st.wake_w = socket.socketpair()
            st.wake_r.setblocking(False)
            st.wake_w.setblocking(False)
            target, args = self._net, (st, a)
        else:
            target, args = self._fetch, (st, a)
        threading.Thread(target=target, args=args, daemon=True).start()

    # ---- frames to the board ----
    def _emit(self, st, op, res=0, data=b"", last=False):
        """Send one frame of the stream (from the stream's own thread). last: the stream
        ends with it (END, or OPENED with an error). _Gone if it is closed."""
        with self.emit_locks[st.ch]:
            if st.closed:
                raise _Gone
            if last:
                self._forget(st)
                st.close()
            try:
                self.send(st.ch, bytes([op, st.sid, 0, res]) + data)
            except Exception:
                self._forget(st)
                st.close()
                raise _Gone

    def _opened(self, st, res=0, size=UNKNOWN_SIZE, status=0, credit=0):
        self._emit(st, N_OPENED, res, struct.pack("<IHH", min(size, UNKNOWN_SIZE), status & 0xFFFF,
                                                  credit), last=res != 0)
        st.opened = res == 0

    def _data(self, st, data):
        with st.cv:
            st.credit -= len(data)
            st.sent += len(data)
        self._emit(st, N_DATA, 0, data)

    def _wait_credit(self, st):
        """Wait until the board can take bytes; how many may go in one frame."""
        with st.cv:
            while not st.closed and st.credit <= 0:
                st.cv.wait()
            if st.closed:
                raise _Gone
            return min(CHUNK, st.credit)

    def _fail(self, st, e):
        """End a stream with the error e (OPENED if it was not opened yet, else END)."""
        code = R_TIMEOUT if st.timed_out else net_result(e)
        status = getattr(e, "status", 0)
        size = getattr(e, "size", UNKNOWN_SIZE)
        why = str(e)
        if st.secret:
            why = why.replace(st.secret, "***")
        self.log(f"{self._name(st)}: {RESULT_NAMES.get(code, hex(code))} (${code:02X})"
                 + (f", HTTP {status}" if status else "") + (f": {why[:100]}" if why else ""))
        try:
            if st.opened:
                self._emit(st, N_END, code, last=True)
            else:
                self._opened(st, code, size, status)
        except _Gone:
            pass

    def _refuse(self, st):
        try:
            self._emit(st, N_OPENED, R_TOOMANY, struct.pack("<IHH", UNKNOWN_SIZE, 0, 0), last=True)
        except _Gone:
            pass

    def _run(self, st, fn, *args):
        try:
            fn(st, *args)
        except _Gone:
            pass
        except Exception as e:
            if st.closed:
                return
            self._fail(st, e)
        finally:
            self._forget(st)
            st.close()
            for s in (st.wake_r, st.wake_w):
                if s is not None:
                    s.close()

    # ---- the watchdog of a deadline ----
    def _watch(self, st, deadline):
        def fire():
            with st.cv:
                if st.watch is not t:
                    return
                st.timed_out = True
                socks = list(st.socks)
            for s in socks:
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        t = threading.Timer(max(0.0, deadline - time.monotonic()), fire)
        t.daemon = True
        with st.cv:
            st.watch = t
        t.start()

    def _unwatch(self, st):
        with st.cv:
            t, st.watch = st.watch, None
            if st.timed_out:
                raise TimeoutError("too slow")
        if t:
            t.cancel()

    # ---- connecting ----
    def _left(self, deadline):
        left = deadline - time.monotonic()
        if left <= 0:
            raise TimeoutError("too slow")
        return left

    def _resolve(self, st, host, port, deadline):
        """getaddrinfo in a thread of its own, so a slow lookup has a time limit too."""
        box = {}
        ev = threading.Event()

        def run():
            try:
                box["r"] = socket.getaddrinfo(host, port, 0, socket.SOCK_STREAM)
            except Exception as e:
                box["e"] = e
            ev.set()
        threading.Thread(target=run, daemon=True).start()
        while not ev.wait(0.1):
            if st.closed:
                raise _Gone
            self._left(deadline)
        if "e" in box:
            raise box["e"]
        return box["r"]

    def _connect(self, st, host, port, deadline, tls=False):
        infos = self._resolve(st, host, port, deadline)
        s, last = None, NetError(R_REFUSED, "no address")
        for af, typ, proto, _, addr in infos:         # each address in turn, as curl does
            s = socket.socket(af, typ, proto)
            st.add_sock(s)
            try:
                self._connect_one(st, s, addr, deadline)
                break
            except OSError as e:
                if st.closed:
                    raise _Gone
                with st.cv:
                    if s in st.socks:
                        st.socks.remove(s)
                s.close()
                s, last = None, e
                if isinstance(e, TimeoutError):
                    break
        if s is None:
            raise last
        if tls:
            s.settimeout(self._left(deadline))
            if self.ssl_context is None:
                self.ssl_context = ssl.create_default_context()
            with st.cv:
                if s in st.socks:
                    st.socks.remove(s)
            try:
                ss = self.ssl_context.wrap_socket(s, server_hostname=host)
            except Exception:
                s.close()
                raise
            st.add_sock(ss)
            s = ss
        return s

    def _connect_one(self, st, s, addr, deadline):
        """A connect that the deadline and close() can stop."""
        s.setblocking(False)
        err = s.connect_ex(addr)
        if err not in (0, errno.EINPROGRESS, errno.EWOULDBLOCK, errno.EALREADY):
            raise OSError(err, os.strerror(err))
        while err:
            if st.closed:
                raise _Gone
            left = self._left(deadline)
            _, w, x = select.select([], [s], [s], min(left, 0.2))
            if w or x:
                err = s.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
                if err:
                    raise OSError(err, os.strerror(err))
                break
        s.setblocking(True)

    # ---- channel 4: Net ----
    def _net(self, st, a):
        self._run(st, self._net_run, a)

    def _net_run(self, st, a):
        if len(a) < 6:
            raise NetError(R_BADADDR, "short OPEN")
        port, flags = struct.unpack_from("<HB", a, 2)
        raw = a[5:].split(b"\0", 1)[0]
        tls = bool(flags & 1)
        try:
            host = raw.decode("ascii")
        except UnicodeError:
            raise NetError(R_BADADDR, "the host name is not ASCII")
        st.what = f"{'tls' if tls else 'tcp'}://{host}:{port}"
        self.log(f"{self._name(st)}: open {st.what}")
        if (not host or len(raw) > 100 or port == 0
                or any(c.isspace() or ord(c) < 33 or c in "/@?#" for c in host)):
            raise NetError(R_BADADDR, "bad host or port")
        if host.startswith("[") and host.endswith("]"):
            host = host[1:-1]
        s = self._connect(st, host, port, time.monotonic() + self.t_net_connect, tls)
        s.settimeout(None)
        try:
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        self._opened(st, 0, UNKNOWN_SIZE, 0, self.send_credit)
        self.log(f"{self._name(st)}: connected")
        rd = st.wake_r
        while True:
            n = 0                                         # the board's bytes to the socket
            while True:
                try:
                    d = st.sendq.get_nowait()
                except queue.Empty:
                    break
                s.sendall(d)
                n += len(d)
            while n:
                k = min(n, 0xFFFF)
                self._emit(st, N_SCREDIT, 0, struct.pack("<H", k))
                n -= k
            with st.cv:
                if st.closed:
                    raise _Gone
                credit = st.credit
            ready = credit > 0 and isinstance(s, ssl.SSLSocket) and s.pending()
            if not ready:
                r, _, _ = select.select([s, rd] if credit > 0 else [rd], [], [])
                ready = s in r
            try:
                while rd.recv(256):
                    pass
            except OSError:
                pass
            if not ready:
                continue
            try:
                data = s.recv(min(CHUNK, credit))
            except ssl.SSLEOFError:
                data = b""                                # (closed without a TLS goodbye)
            if not data:
                self.log(f"{self._name(st)}: the other end closed ({st.sent} bytes)")
                self._emit(st, N_END, 0, last=True)
                return
            self._data(st, data)

    # ---- channel 5: Fetch ----
    def _fetch(self, st, a):
        self._run(st, self._fetch_run, a)

    def _fetch_run(self, st, a):
        raw = a[4:].split(b"\0", 1)[0]
        try:
            url = raw.decode("utf-8")
        except UnicodeError:
            url = raw.decode("latin-1")
        st.what = safe_url(url)
        self.log(f"{self._name(st)}: get {st.what}")
        if len(raw) > 255:
            raise NetError(R_BADADDR, "the URL is too long")
        deadline = time.monotonic() + self.t_fetch_head
        self._watch(st, deadline)
        u = self._split(url)
        if u.scheme == "ftp":
            self._ftp(st, u, deadline)
            return
        status = 0
        for hop in range(self.max_redirects + 1):
            sock, resp = self._http_get(st, u, deadline)
            status = resp.status
            loc = resp.getheader("Location")
            if status not in REDIRECTS or not loc:
                break
            url = urllib.parse.urljoin(url, loc.strip())
            st.close_socks()
            self.log(f"{self._name(st)}: {status} to {safe_url(url)}")
            u = self._split(url)
            if u.scheme not in ("http", "https"):
                raise NetError(R_BADADDR, "redirected to a scheme other than HTTP", status)
        else:
            raise NetError(R_NETERR, "too many redirects", status)
        self._unwatch(st)
        size = UNKNOWN_SIZE
        cl = resp.getheader("Content-Length")
        if cl and cl.strip().isdigit():
            size = min(int(cl.strip()), UNKNOWN_SIZE)
        if status >= 400:
            raise NetError(R_HTTP, f"HTTP {status} {resp.reason}", status, size)
        sock.settimeout(self.t_fetch_body)            # (http.client may have let go of it)
        self._opened(st, 0, size, status)
        self.log(f"{self._name(st)}: HTTP {status}, "
                 + ("size unknown" if size == UNKNOWN_SIZE else f"{size} bytes"))
        self._pump(st, resp.read1)

    def _split(self, url):
        try:
            u = urllib.parse.urlsplit(url)
            u.port                                        # (ValueError: a bad port)
        except ValueError as e:
            raise NetError(R_BADADDR, str(e))
        if u.scheme.lower() not in ("http", "https", "ftp") or not u.hostname or u.port == 0:
            raise NetError(R_BADADDR, "unknown scheme, no host or port 0")
        if any(c.isspace() or ord(c) < 32 for c in url):
            raise NetError(R_BADADDR, "spaces or control characters in the URL")
        return u._replace(scheme=u.scheme.lower())

    def _http_get(self, st, u, deadline):
        tls = u.scheme == "https"
        port = u.port or (443 if tls else 80)
        host = u.hostname
        s = self._connect(st, host, port, deadline, tls)
        s.settimeout(self._left(deadline))
        conn = http.client.HTTPConnection(host, port)
        conn.sock = s
        path = u.path or "/"
        if u.query:
            path += "?" + u.query
        path = urllib.parse.quote(path, safe="/%:@!$&'()*+,;=-._~?")
        hostport = f"[{host}]" if ":" in host else host
        if port != (443 if tls else 80):
            hostport += f":{port}"
        conn.putrequest("GET", path, skip_host=True, skip_accept_encoding=True)
        conn.putheader("Host", hostport.encode("idna").decode("ascii"))
        conn.putheader("User-Agent", USER_AGENT)
        conn.putheader("Accept", "*/*")
        conn.putheader("Accept-Encoding", "identity")
        conn.putheader("Connection", "close")
        conn.endheaders()
        return s, conn.getresponse()

    def _pump(self, st, read):
        """Send the body: as much as the credit allows, a frame at a time; END at its end."""
        while True:
            n = self._wait_credit(st)
            data = read(n)
            if not data:
                break
            self._data(st, data[:n])
        self.log(f"{self._name(st)}: done ({st.sent} bytes)")
        self._emit(st, N_END, 0, last=True)

    def _ftp(self, st, u, deadline):
        port = u.port or 21
        user = _unq(u.username) if u.username is not None else None
        password = _unq(u.password) if u.password is not None else ""
        if password:
            st.secret = password
        path = _unq(u.path)
        if path.startswith("/"):
            path = path[1:]
        if any(c in path for c in "\r\n\0"):
            raise NetError(R_BADADDR, "bad path")
        addr = self._resolve(st, u.hostname, port, deadline)[0][4]
        ftp = ftplib.FTP()
        ftp.encoding = "latin-1"
        try:
            ftp.connect(addr[0], port, timeout=self._left(deadline))
            st.add_sock(ftp.sock)
            if user:
                ftp.login(user, password)
            else:
                ftp.login()
            ftp.set_pasv(True)
            if not path or path.endswith("/"):
                text = self._ftp_list(ftp, path.rstrip("/") if path != "/" else "/")
                self._unwatch(st)
                body = text.encode("latin-1")
                self._opened(st, 0, len(body))
                self.log(f"{self._name(st)}: listing, {len(body)} bytes")
                view = memoryview(body)
                pos = [0]

                def read(n):
                    d = bytes(view[pos[0]:pos[0] + n])
                    pos[0] += len(d)
                    return d
                self._pump(st, read)
                return
            ftp.voidcmd("TYPE I")
            size = UNKNOWN_SIZE
            try:
                size = min(ftp.size(path), UNKNOWN_SIZE)
            except (ftplib.error_perm, ftplib.error_temp, ftplib.error_reply, ValueError, TypeError):
                pass
            conn = ftp.transfercmd("RETR " + path)
            st.add_sock(conn)
            self._unwatch(st)
            conn.settimeout(self.t_fetch_body)
            ftp.sock.settimeout(self.t_fetch_body)
            self._opened(st, 0, size)
            self.log(f"{self._name(st)}: " + ("size unknown" if size == UNKNOWN_SIZE else f"{size} bytes"))
            while True:
                n = self._wait_credit(st)
                data = conn.recv(n)
                if not data:
                    break
                self._data(st, data)
            conn.close()
            ftp.voidresp()
            self.log(f"{self._name(st)}: done ({st.sent} bytes)")
            self._emit(st, N_END, 0, last=True)
        finally:
            try:
                ftp.close()
            except Exception:
                pass

    def _ftp_list(self, ftp, path):
        """A folder's listing: MLSD (name, size, time) when the server has it, else NLST."""
        lines = []
        try:
            for name, facts in ftp.mlsd(path):
                kind = facts.get("type", "").lower()
                if kind in ("cdir", "pdir") or name in (".", ".."):
                    continue
                isdir = kind == "dir"
                size = facts.get("size", "0") if not isdir else "0"
                mod = facts.get("modify", "")
                when = ""
                if len(mod) >= 12 and mod[:12].isdigit():
                    t = calendar.timegm((int(mod[0:4]), int(mod[4:6]), int(mod[6:8]),
                                         int(mod[8:10]), int(mod[10:12]), 0, 0, 0, 0))
                    when = time.strftime("%Y-%m-%d %H:%M", time.localtime(t))
                lines.append(f"{name}{'/' if isdir else ''}\t{size if size.isdigit() else 0}\t{when}")
        except ftplib.error_perm as e:
            if not str(e)[:3] in ("500", "502", "504"):
                raise
            # (some servers answer NLST of a folder with paths: keep the last part)
            lines = [n.rstrip("/").rsplit("/", 1)[-1] for n in ftp.nlst(*([path] if path else []))]
        return "".join(line + "\n" for line in lines)


# ======================================================================================
# The gateway
# ======================================================================================

class Gateway:
    """net=False (--no-net): no internet for the Atari816 (HELLO without NET and FETCH)."""

    def __init__(self, folder, port=None, readonly=False, verbose=0, logfile=None, net=True):
        self.verbose = verbose
        self.logfile = logfile
        self.clients = set()
        self.subs = set()
        self.dev_owner = None
        self.dev_lock = threading.Lock()
        self.files_q = queue.Queue()
        services = SV_FILES | SV_DEV | SV_PRINT | (SV_NET | SV_FETCH if net else 0)
        self.link = Link(port=port, services=services, name="atari816-link",
                         on_frame=self._on_frame, on_log=self._on_log,
                         on_state=self._on_state, verbose=verbose)
        self.fs = FileServer(folder, lambda p: self.link.send(CH_FILES, p),
                             log=self._say if verbose > 1 else None, readonly=readonly,
                             send_many=lambda ps: self.link.send_many(CH_FILES, ps))
        self.net = (NetServer(lambda ch, p: self.link.send(ch, p),
                              log=self._say if verbose > 1 else None) if net else None)
        self.sock = None

    def _say(self, text):
        sys.stderr.write(time.strftime("%H:%M:%S ") + text + "\n")
        sys.stderr.flush()

    def _on_state(self, up, info):
        self.files_q.put(("reset", None))
        if self.net:
            self.net.reset()                              # (never blocks)
        if up:
            self._say(f"connected: {info} (port {self.link.port})")
        else:
            self._say("disconnected")
        owner = self.dev_owner
        if not up and owner:
            try:
                sock_send(owner, ord("E"), b"the link to the Atari816 went down")
            except OSError:
                pass

    def _on_log(self, data):
        if self.logfile:
            self.logfile.write(data.decode("latin1") + "\n")
            self.logfile.flush()
        for c in list(self.subs):
            try:
                sock_send(c, ord("L"), data)
            except OSError:
                self.subs.discard(c)

    def _on_frame(self, ch, payload):
        if ch == CH_FILES:
            self.files_q.put(("req", payload))
        elif ch == CH_DEV:
            owner = self.dev_owner
            if owner:
                # the last frame of the answer: the channel is free BEFORE the tool sees the
                # answer (it may send its next request at once; released afterwards, the next
                # request's answer found no owner and was dropped)
                if len(payload) >= 4 and not payload[2] & MORE:
                    self._release(owner)
                try:
                    sock_send(owner, ord("P"), payload)
                except OSError:
                    pass
        elif ch in (CH_NET, CH_FETCH):
            if self.net:
                self.net.frame(ch, payload)               # (never blocks)
        # other channels: reserved for later steps (acknowledged, dropped)

    def _release(self, owner):
        if self.dev_owner is owner:
            self.dev_owner = None
            try:
                self.dev_lock.release()
            except RuntimeError:
                pass

    def _files_worker(self):
        while True:
            kind, p = self.files_q.get()
            if kind == "reset":
                self.fs.reset()
                continue
            try:
                self.fs.request(p)
            except LinkDown:
                pass
            except Exception as e:
                self._say(f"files: {e!r}")

    def _client(self, c):
        try:
            while True:
                typ, data = sock_recv(c)
                if typ == ord("S"):
                    self.subs.add(c)
                elif typ == ord("I"):
                    st = (f"connected to {self.link.port}: {self.link.info}" if self.link.up
                          else "waiting for the Atari816")
                    sock_send(c, ord("I"), st.encode())
                elif typ == ord("R"):
                    if self.dev_owner is not c:
                        if not self.dev_lock.acquire(timeout=60):
                            sock_send(c, ord("E"), b"the developer channel is busy")
                            continue
                        self.dev_owner = c
                    try:
                        if not self.link.up:
                            self.link.wait_up(5.0)
                        self.link.send(CH_DEV, data)
                    except LinkError as e:
                        sock_send(c, ord("E"), str(e).encode())
                        self._release(c)
        except (EOFError, OSError):
            pass
        finally:
            self.subs.discard(c)
            self.clients.discard(c)
            self._release(c)
            try:
                c.close()
            except OSError:
                pass

    def _listen(self):
        path = sock_path()
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        if os.path.exists(path):
            try:                                          # another gateway running?
                t = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                t.connect(path)
                t.close()
                raise LinkError(f"another gateway is running ({path})")
            except ConnectionRefusedError:
                os.unlink(path)
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old = os.umask(0o177)
        try:
            s.bind(path)
        finally:
            os.umask(old)
        s.listen(4)
        self.sock = s
        self.sock_file = path

    def run(self):
        self._listen()
        threading.Thread(target=self._files_worker, daemon=True).start()
        self.link.start()
        self._say(f"sharing {self.fs.root}" + (" (read only)" if self.fs.readonly else "") +
                  f"; internet {'on' if self.net else 'off'}; tools socket {self.sock_file}")
        try:
            while True:
                c, _ = self.sock.accept()
                self.clients.add(c)
                threading.Thread(target=self._client, args=(c,), daemon=True).start()
        finally:
            self.close()

    def close(self):
        try:
            self.link.close()
        except Exception:
            pass
        self.fs.reset()                                   # unfinished files are deleted
        if self.net:
            self.net.reset()
        if self.sock:
            try:
                self.sock.close()
                os.unlink(self.sock_file)
            except OSError:
                pass
            self.sock = None
