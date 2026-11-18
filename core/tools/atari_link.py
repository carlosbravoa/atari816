# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""atari_link.py - the developer tools' side of the Atari816 PC link.

Since the PC link (Docs/04-pc-link.md) the serial port carries framed packets. The
developer commands (send a file, restart the 65C816, read memory, press keys...) are
requests on the link's developer channel. This module keeps the AtariLink class that
atari.py, atari_gui.py and a816_screen.py use, on top of tools/pclink.py:

  - if the gateway (`tools/atari816-link`) is running, the requests go through it (its
    Unix socket), and the PC volume stays served;
  - otherwise the port is opened here, for the time of the command.

Developer channel ops (payload: op, tag, flags, result, then the data):
  $01 INFO        -> the firmware's status line
  $02 PUT         size u32 + path, then frames of offset u32 + data -> result
  $03 RESTART816  [1 = /A816.BIN only]
  $04 RUN path    (a .xex: mount + cold boot)     $05 COLD   $06 WARM   $07 EJECT
  $08 KEY mod hid hold10ms      $09 MOUSE dx dy wheel buttons      $0A TYPE text
  $0B PEEK addr16 len16         $0C POKE addr16 bytes              $0D FWPEEK addr32 len16
  $0E PEEK816 addr32 width16 rows16 stride32 flags8 -> data + sum16
      (flags bit 0 RLE: h < 128: h + 1 literals, h >= 128: next byte x (h - 125);
       bit 1 XOR2: byte ^= the byte two before, per row; bit 2: the sum only)
  $0F ECHO   $10 SOURCE len32   $11 SINK   (link tests)
"""
import os
import queue
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "tools")))
import pclink  # noqa: E402
from pclink import LinkError, list_ports  # noqa: E402,F401

BAUD = pclink.BAUD


def _screencode_to_ascii(c):
    """Atari internal screen code -> printable ASCII (inverse video ignored)."""
    c &= 0x7F
    a = c + 32 if c < 64 else (c - 64 if c < 96 else c)
    return chr(a) if 32 <= a < 127 else "."


class MenuTakeover(Exception):
    """(Kept for old callers; the firmware menu is gone and never takes the keyboard.)"""


def usb_ports():
    return [p for p in list_ports() if p.vid is not None]


def auto_port():
    return pclink.auto_port()


def sd_name(path, override=None, default_dir="PC"):
    """Destination path on the SD: default <default_dir>/<basename>, uppercased."""
    name = override or (f"{default_dir}/" + os.path.basename(path)
                        if default_dir else os.path.basename(path))
    name = name.upper().lstrip("/")
    if len(name) > 150:
        raise LinkError(f"path too long: {name}")
    return name


def _check(res, what):
    if res:
        raise LinkError(f"{what}: the firmware answered error ${res:02X}")


class AtariLink:
    """One connection for developer requests. Not thread-safe."""

    def __init__(self, port=None, timeout=1.0, settle=True):
        self.dev = pclink.DevClient(port=port, timeout=max(10.0, timeout))
        self.port = self.dev.via if self.dev.sock else self.dev.link.port
        self.backlog = b""
        self.dev.subscribe_log(self._log)
        self._lines = queue.Queue()

    on_log = None          # on_log(bytes): a firmware log line arrived (with its newline)

    def _log(self, data):
        line = data + b"\n"
        if self.on_log is not None:
            try:
                self.on_log(line)
            except Exception:
                pass
        else:
            self._lines.put(line)

    def reconnect(self, wait=1.0, deadline=20.0):
        self.close()
        time.sleep(wait)
        end = time.time() + deadline
        while True:
            try:
                self.dev = pclink.DevClient(timeout=10.0)
                self.dev.subscribe_log(self._log)
                return
            except Exception:
                if time.time() > end:
                    raise
                time.sleep(1)

    def close(self):
        try:
            self.dev.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def _req(self, op, args=b"", frames=(), timeout=None, progress=None, what="request"):
        res, data = self.dev.request(op, args, frames=frames, timeout=timeout, progress=progress)
        _check(res, what)
        return data

    # ---- commands ----
    def ping(self, timeout=2):
        try:
            return self.dev.request(pclink.D_ECHO, b"A8OK", timeout=timeout)[1] == b"A8OK"
        except LinkError:
            return False

    def send(self, data, name, progress=None):
        """Write `data` to /`name` on the SD card (folders are created)."""
        name = name.lstrip("/")
        frames = [off.to_bytes(4, "little") + data[off:off + pclink.CHUNK]
                  for off in range(0, len(data), pclink.CHUNK)]
        cb = None
        if progress:
            def cb(done, total):
                progress(min(len(data), max(0, done - 1) * pclink.CHUNK), len(data))
        self._req(pclink.D_PUT, len(data).to_bytes(4, "little") + name.encode() + b"\0",
                  frames=frames, timeout=30, progress=cb, what="send")
        if progress:
            progress(len(data), len(data))

    def run(self, data, name, progress=None):
        """Send then boot. `data` must be a .xex ($FFFF header)."""
        if data[:2] != b"\xff\xff":
            raise LinkError("not a .xex (missing $FFFF header)")
        self.send(data, name, progress)
        self._req(pclink.D_RUN, name.lstrip("/").encode() + b"\0", what="run")

    def eject(self):
        self._req(pclink.D_EJECT, what="eject")

    def reset(self, warm=False, keep=False):
        if not keep:
            self.eject()
        self._req(pclink.D_WARM if warm else pclink.D_COLD, what="reset")

    def restart816(self, test=False):
        """Reload /SYSTEM/HORIZON.SYS (or /A816.BIN) and restart the 65C816."""
        self._req(pclink.D_RESTART816, bytes([1 if test else 0]), timeout=15, what="restart816")

    def key(self, hid, mod=0, hold_ms=100):
        """Press one raw HID key (mod bit0=Ctrl, bit1=Shift) for hold_ms, release."""
        self._req(pclink.D_KEY, bytes([mod & 0xFF, hid & 0xFF, max(1, min(255, hold_ms // 10))]),
                  what="key")

    def mouse(self, dx=0, dy=0, wheel=0, buttons=0):
        """Inject a mouse movement for the 65C816 side (MOUSE event)."""
        self._req(pclink.D_MOUSE, bytes([dx & 0xFF, dy & 0xFF, wheel & 0xFF, buttons & 0xFF]),
                  what="mouse")

    def type_text(self, text, progress=None):
        """Paste text as keystrokes on the classic machine (~18 chars/s)."""
        data = text.replace("\r\n", "\n").encode("ascii", "replace")
        done = 0
        for i in range(0, len(data), 200):
            part = data[i:i + 200]
            self._req(pclink.D_TYPE, part, timeout=len(part) * 0.4 + 10, what="type")
            done += len(part)
            if progress:
                progress(done, len(data))

    def type_lines(self, text, progress=None, retries=4):
        lines = [l for l in text.replace("\r\n", "\n").split("\n") if l != ""]
        for n, line in enumerate(lines):
            self.type_text(line + "\n")
            if progress:
                progress(n + 1, len(lines))

    def type_key(self, ch):
        data = ch.encode("ascii", "replace")[:1]
        if data:
            self._req(pclink.D_TYPE, data, timeout=5, what="type")

    def kbd_session(self):
        return KbdSession(self)

    def status(self, timeout=3):
        """The firmware's status line."""
        return self._req(pclink.D_INFO, timeout=timeout, what="status").decode("ascii", "replace").strip()

    def peek(self, addr, length):
        """Read classic machine memory: `length` (1..1024) bytes from `addr`."""
        if not 0 < length <= 1024:
            raise LinkError("peek length 1..1024")
        return self._req(pclink.D_PEEK, addr.to_bytes(2, "little") + length.to_bytes(2, "little"),
                         what="peek")

    def fwpeek(self, addr, length):
        """Read the I/O processor's own memory (debug aid)."""
        if not 0 < length <= 1024:
            raise LinkError("fwpeek length 1..1024")
        return self._req(pclink.D_FWPEEK, addr.to_bytes(4, "little") + length.to_bytes(2, "little"),
                         what="fwpeek")

    def poke(self, addr, data):
        """Write bytes into classic machine memory."""
        if not 0 < len(data) <= 1000:
            raise LinkError("poke length 1..1000")
        self._req(pclink.D_POKE, addr.to_bytes(2, "little") + bytes(data), what="poke")

    def peek816(self, addr, length=None, width=None, rows=1, stride=0, rle=True, xor2=False):
        """Read 65C816 memory: `length` bytes from the native 24-bit `addr`, or `rows` spans
        of `width` bytes `stride` apart (a framebuffer). Reads SDRAM behind the 65C816's
        write-through cache, so it sees every completed CPU and blitter write and never pauses
        the CPU. Bank $10 and $80+ read as 0. Large reads are split into ~64 KB requests."""
        if width is None:
            width, rows, stride = length, 1, 0
        if not (0 < width <= 0xFFFF and rows > 0):
            raise LinkError("peek816: width 1..65535, rows >= 1")
        out = bytearray()
        per = max(1, 0x10000 // width)
        r = 0
        while r < rows:
            n = min(per, rows - r)
            out += self._peek816_req(addr + r * stride, width, n, stride,
                                     (1 if rle else 0) | (2 if xor2 else 0))
            r += n
        return bytes(out)

    def sum816(self, addr, length):
        """16-bit sum of `length` (<= 1 MB) bytes of 65C816 memory, without the data."""
        rows = (length + 0xFFFF) // 0x10000
        if length % rows:
            raise LinkError("sum816: length must split into equal spans of <= 64 KB")
        return self._peek816_req(addr, length // rows, rows, length // rows, 4)

    def _peek816_req(self, addr, width, rows, stride, flags):
        total = width * rows
        d = self._req(pclink.D_PEEK816,
                      (addr & 0xFFFFFF).to_bytes(4, "little") + width.to_bytes(2, "little") +
                      rows.to_bytes(2, "little") + (stride & 0xFFFFFFFF).to_bytes(4, "little") +
                      bytes([flags]), timeout=30, what="peek816")
        if len(d) < 2:
            raise LinkError("peek816: short answer")
        sum_rx = int.from_bytes(d[-2:], "little")
        if flags & 4:
            return sum_rx
        d = d[:-2]
        if not flags & 1:
            out = bytearray(d)
        else:
            out = bytearray()
            i = 0
            while i < len(d):
                h = d[i]
                if h < 128:
                    out += d[i + 1:i + 2 + h]
                    i += 2 + h
                else:
                    out += d[i + 1:i + 2] * (h - 125)
                    i += 2
        if len(out) != total:
            raise LinkError(f"peek816: {len(out)} bytes, expected {total}")
        if flags & 2:                                   # undo XOR2, span by span
            for r0 in range(0, total, width):
                for i in range(r0 + 2, r0 + width):
                    out[i] ^= out[i - 2]
        if sum(out) & 0xFFFF != sum_rx:
            raise LinkError("peek816: checksum mismatch")
        return bytes(out)

    def shot816(self, path=None, **kw):
        """Screenshot of the 65C816's native screen (Marga) as an RGB image; a PNG at `path`
        if given. See a816_screen.py for how the video state is found."""
        sys.path.insert(0, HERE)
        import a816_screen
        shot = a816_screen.capture(self, **kw)
        if path:
            shot.save_png(path)
        return shot

    def screen(self):
        """Text dump of the classic machine's screen (GR.0): 24 x 40, via SAVMSC."""
        savmsc = int.from_bytes(self.peek(0x58, 2), "little")
        raw = self.peek(savmsc, 960)
        return "\n".join("".join(_screencode_to_ascii(c) for c in raw[r * 40:(r + 1) * 40])
                         for r in range(24))

    def alive(self):
        """Is the 6502 running? Watch the OS jiffy counter (RTCLOK $12-14)."""
        a = self.peek(0x12, 3)
        time.sleep(0.1)
        return a != self.peek(0x12, 3)

    def read_log(self, max_bytes=4096, timeout=0.5):
        """Firmware log lines received since the last call (bytes, newline-separated)."""
        out = b""
        try:
            out += self._lines.get(timeout=timeout)
            while len(out) < max_bytes:
                out += self._lines.get_nowait()
        except queue.Empty:
            pass
        return out


class KbdSession:
    """Live keyboard: every key is one TYPE request."""

    def __init__(self, link):
        self.link = link
        self.open = True

    def send_key(self, ch):
        if not self.open:
            raise LinkError("session closed")
        if ch == "\r":
            ch = "\n"
        self.link.type_key(ch)

    def poll_takeover(self):
        pass

    def end(self):
        self.open = False
