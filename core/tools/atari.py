#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""atari.py — developer CLI for the Atari816 over the PC link (USB-C serial, BL616).

The requests go through the gateway (tools/atari816-link at the top of the repository) when
it runs, else straight over the serial port (Docs/04-pc-link.md).

Usage:
  atari.py ports                     # list candidate serial ports
  atari.py log  [-p PORT]            # tail firmware logs (Ctrl-C to stop)
  atari.py ping [-p PORT]            # send ENQ, expect "A8OK" back
  atari.py send FILE [NAME] [-p P]   # copy FILE to the SD, default /PC/<name>;
                                     #   NAME may include folders: GAMES/X.ATR
  atari.py run  FILE.XEX [-p P]      # send + boot it (the make-run dev loop)
  atari.py type FILE|- [-p P]        # paste text as keystrokes (~18 chars/s;
                                     #   OSD must be closed)
  atari.py kbd [-p P]                # LIVE keyboard: type on the PC, it lands
                                     #   on the Atari; Ctrl-] exits
  atari.py eject [-p P]              # just eject the virtual .xex from D1:
  atari.py key NAME|0xNN [--shift] [--ctrl] [--hold MS]  # press one raw key:
                                     #   start/select/option (=F6/F7/F8), f1..f12,
                                     #   esc, enter, arrows, a..z, 0..9
  atari.py run816 [FILE] [--name N] # Atari816: send a 65C816 program (default
                                     #   /A816.BIN), restart the 65C816, show its log
  atari.py shot816 OUT.png [-p P]   # Atari816: screenshot of the native screen
                                     #   (--mode/--base/--stride override, --scale N)
  atari.py peek816 ADDR [LEN] [-p P] # hex dump of 65C816 memory (24-bit address)
  atari.py reset [--warm] [-p P]     # eject virtual .xex + cold boot (--warm =
                                     #   warm start; --keep = don't eject)
  atari.py status [-p P]             # firmware status line (boot stage, mounts,
                                     #   SIO counters, stack canary)
  atari.py screen [-p P]             # text dump of the Atari's screen (GR.0)
  atari.py peek ADDR [LEN] [-p P]    # hex dump of Atari memory (e.g. 0x58 16)
  atari.py fwpeek ADDR [LEN] [-p P]  # hex dump of FIRMWARE BSRAM (fw globals, debug)
  atari.py poke ADDR B [B...] [-p P] # write bytes into Atari memory
  atari.py hdd-install [-p P]        # install the H: handler above MEMLO
  atari.py r-install [-p P]          # install the R: modem handler (for BobTerm)
                                     #   (files -> /HDD on the SD); session-
                                     #   scoped; type NEW in BASIC after

Protocol implementation lives in atari_link.py (shared with the desktop app,
atari_gui.py) on top of tools/pclink.py. Needs: pip install pyserial.
Linux: sudo modprobe ftdi_sio if no /dev/ttyUSB* appears.
"""
import argparse
import sys

from atari_link import AtariLink, LinkError, list_ports, sd_name


def _progress(name):
    def cb(done, total):
        pct = done * 100 // total
        if sys.stdout.isatty():
            sys.stdout.write(f"\r{name}: {done}/{total} bytes ({pct}%)")
            sys.stdout.flush()
        elif pct % 25 == 0:
            print(f"{name}: {pct}%")
    return cb


def cmd_ports(args):
    for p in list_ports():
        print(f"{p.device}  {p.description}  [{p.manufacturer or '?'}]")


def cmd_ping(args):
    with AtariLink(args.port) as l:
        if l.ping():
            print(f"the Atari816 answers (via {l.dev.via})")
        else:
            sys.exit("no reply — check the board is on and the port is right")


def cmd_log(args):
    with AtariLink(args.port) as l:
        print(f"— the firmware's log via {l.dev.via} (Ctrl-C to stop) —")
        try:
            while True:
                d = l.read_log()
                if d:
                    sys.stdout.write(d.decode("ascii", "replace"))
                    sys.stdout.flush()
        except KeyboardInterrupt:
            print("\n— stopped —")


def cmd_send(args):
    data = open(args.file, "rb").read()
    if getattr(args, "text", False):
        # Atari INPUT needs ATASCII EOLs ($9B) — a raw \n text file reads as
        # one endless record (HW-hit during the H: bring-up).
        data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\x9b")
    name = sd_name(args.file, args.name)
    with AtariLink(args.port) as l:
        l.send(data, name, _progress(name))
    print(f"\nOK — /{name} on the SD card"
          + (" (ATASCII EOLs)" if getattr(args, "text", False) else ""))


def cmd_run(args):
    data = open(args.file, "rb").read()
    name = sd_name(args.file, args.name)
    with AtariLink(args.port) as l:
        l.run(data, name, _progress(name))
    print("\nbooting it on the Atari…")


def cmd_type(args):
    text = sys.stdin.read() if args.file == "-" else \
        open(args.file, "r", encoding="utf-8", errors="replace").read()
    with AtariLink(args.port) as l:
        # line-wise with drop-recovery (BL616 USB flaps mid-session; numbered
        # BASIC lines make whole-line retypes idempotent)
        l.type_lines(text, _progress("lines"))
    print("\ndone — check the screen")


def cmd_kbd(args):
    import os
    import termios
    import tty
    print("live keyboard -> the classic Atari  (Ctrl-] to exit)")
    with AtariLink(args.port) as l:
        sess = l.kbd_session()
        fd = sys.stdin.fileno()
        old_t = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            while True:
                ch = os.read(fd, 1)
                if ch == b"\x1d":          # Ctrl-]
                    break
                sess.send_key(ch.decode("latin1"))
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_t)
        sess.end()
    print("\nsession closed")


def cmd_status(args):
    with AtariLink(args.port) as l:
        print(l.status())


def cmd_screen(args):
    with AtariLink(args.port) as l:
        print(l.screen())


def cmd_peek(args):
    addr = int(args.addr, 0)
    length = int(args.len, 0)
    with AtariLink(args.port) as l:
        data = l.peek(addr, length)
    for off in range(0, len(data), 16):
        row = data[off:off + 16]
        hexs = " ".join(f"{b:02x}" for b in row)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
        print(f"{addr + off:04x}  {hexs:<48}  {text}")


def cmd_poke(args):
    addr = int(args.addr, 0)
    data = bytes(int(b, 0) for b in args.bytes)
    with AtariLink(args.port) as l:
        l.poke(addr, data)
    print(f"{len(data)} byte(s) written at {addr:#06x}")


def cmd_fwpeek(args):
    addr = int(args.addr, 0)
    length = int(args.len, 0)
    with AtariLink(args.port) as l:
        data = l.fwpeek(addr, length)
    for off in range(0, len(data), 16):
        row = data[off:off + 16]
        hexs = " ".join(f"{b:02x}" for b in row)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
        print(f"{addr + off:04x}  {hexs:<48}  {text}")


def cmd_hdd_install(args):
    with AtariLink(args.port) as l:
        lo, hi, memlo = l.hdd_install()
    print(f"H: installed at ${lo:04X}-${hi - 1:04X} (above MEMLO), "
          f"MEMLO raised to ${memlo:04X}.")
    print("In BASIC, type NEW now (BASIC only re-reads MEMLO on NEW), then "
          'try OPEN #1,8,0,"H:HELLO.TXT" (files land in /HDD on the SD). '
          "RESET clears it; re-run to restore.")


def cmd_r_install(args):
    with AtariLink(args.port) as l:
        lo, hi, memlo = l.r_install(force=args.force)
    print(f"R: installed at ${lo:04X}-${hi - 1:04X} (above MEMLO), "
          f"MEMLO raised to ${memlo:04X}.")
    print("In BASIC, type NEW now (BASIC only re-reads MEMLO on NEW). BobTerm "
          "(and R:-aware software) will now find the modem handler. Run "
          "`atari_net.py --modem` for the PC side. RESET clears it; re-run.")


def cmd_eject(args):
    with AtariLink(args.port) as l:
        l.eject()
    print("virtual .xex ejected from D1:")


KEY_NAMES = {
    "start": 0x3F, "select": 0x40, "option": 0x41, "help": 0x3E,
    "esc": 0x29, "enter": 0x28, "return": 0x28, "space": 0x2C, "tab": 0x2B,
    "backspace": 0x2A, "up": 0x52, "down": 0x51, "left": 0x50, "right": 0x4F,
    "f9": 0x42, "f11": 0x44, "f12": 0x45,
}
for _i in range(1, 9):
    KEY_NAMES[f"f{_i}"] = 0x39 + _i          # f1..f8 = 0x3A..0x41 (f6/f7/f8 = start/select/option)
for _i, _c in enumerate("abcdefghijklmnopqrstuvwxyz"):
    KEY_NAMES[_c] = 0x04 + _i
for _i, _c in enumerate("1234567890"):
    KEY_NAMES[_c] = 0x1E + _i


def cmd_key(args):
    name = args.key.lower()
    hid = KEY_NAMES.get(name)
    if hid is None:
        hid = int(args.key, 0)
    mod = (0x01 if args.ctrl else 0) | (0x02 if args.shift else 0)
    with AtariLink(args.port) as l:
        l.key(hid, mod=mod, hold_ms=args.hold)
    print(f"key 0x{hid:02X} mod 0x{mod:02X} held {args.hold} ms")


def cmd_reset(args):
    with AtariLink(args.port) as l:
        l.reset(warm=args.warm, keep=args.keep)
    print("warm start requested" if args.warm else "cold boot requested")


def cmd_run816(args):
    """Atari816 dev loop: send a 65C816 program, restart the CPU, show its log."""
    import time
    with AtariLink(args.port, timeout=0.5) as l:
        if args.file:
            data = open(args.file, "rb").read()
            l.send(data, args.name, _progress(args.name))
            print()
        l.restart816(test=True)
        end = time.time() + args.seconds
        buf = ""
        while time.time() < end:
            d = l.read_log()
            if d:
                t = d.decode("ascii", "replace")
                sys.stdout.write(t)
                sys.stdout.flush()
                buf = (buf + t)[-200:]
                if args.until and args.until in buf:
                    break


def cmd_shot816(args):
    import time
    t = time.time()
    kw = {}
    if args.mode is not None:
        kw["mode"] = args.mode
    if args.base is not None:
        kw["base"] = int(args.base, 0)
    if args.stride is not None:
        kw["stride"] = int(args.stride, 0)
    with AtariLink(args.port) as l:
        try:
            shot = l.shot816(args.out, pointer=not args.no_pointer, scale=args.scale,
                             horizon=not args.no_horizon, **kw)
        except ValueError as e:
            sys.exit(f"shot816: {e}")
    info = " ".join(f"{k}={v:#x}" if k == "base" else f"{k}={v}" for k, v in shot.info.items())
    print(f"{args.out}: {shot.width}x{shot.height}, {time.time() - t:.1f} s ({info})")


def cmd_peek816(args):
    addr, n = int(args.addr, 0), int(args.len, 0)
    with AtariLink(args.port) as l:
        data = l.peek816(addr, n)
    for i in range(0, len(data), 16):
        row = data[i:i + 16]
        a = addr + i
        print(f"{a >> 16:02X}:{a & 0xFFFF:04X}  " + " ".join(f"{b:02X}" for b in row).ljust(48) +
              " " + "".join(chr(b) if 32 <= b < 127 else "." for b in row))


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, *extra):
        sp = sub.add_parser(name)
        for e in extra:
            e(sp)
        sp.add_argument("-p", "--port", default=None)
        sp.set_defaults(fn=fn)

    add("ports", cmd_ports)
    add("ping", cmd_ping)
    add("log", cmd_log)
    add("send", cmd_send, lambda sp: sp.add_argument("file"),
        lambda sp: sp.add_argument("name", nargs="?", default=None),
        lambda sp: sp.add_argument("--text", action="store_true",
                                   help="convert \\n line endings to ATASCII $9B"))
    add("run", cmd_run, lambda sp: sp.add_argument("file"),
        lambda sp: sp.add_argument("name", nargs="?", default=None))
    add("type", cmd_type,
        lambda sp: sp.add_argument("file", help="text file, or - for stdin"))
    add("kbd", cmd_kbd)
    add("eject", cmd_eject)
    add("hdd-install", cmd_hdd_install)
    add("r-install", cmd_r_install,
        lambda sp: sp.add_argument("--force", action="store_true",
                                   help="reinstall even if R: is already in HATABS"))
    add("status", cmd_status)
    add("screen", cmd_screen)
    add("peek", cmd_peek, lambda sp: sp.add_argument("addr"),
        lambda sp: sp.add_argument("len", nargs="?", default="64"))
    add("poke", cmd_poke, lambda sp: sp.add_argument("addr"),
        lambda sp: sp.add_argument("bytes", nargs="+"))
    add("fwpeek", cmd_fwpeek, lambda sp: sp.add_argument("addr"),
        lambda sp: sp.add_argument("len", nargs="?", default="64"))
    add("key", cmd_key,
        lambda sp: sp.add_argument("key", help="start/select/option/f1..f12/esc/enter/up/down/a..z/0..9 or 0xNN HID code"),
        lambda sp: sp.add_argument("--shift", action="store_true"),
        lambda sp: sp.add_argument("--ctrl", action="store_true"),
        lambda sp: sp.add_argument("--hold", type=int, default=100, help="hold time ms (default 100)"))
    add("run816", cmd_run816,
        lambda sp: sp.add_argument("file", nargs="?", default=None,
                                   help="65C816 program to send first (omit to just restart)"),
        lambda sp: sp.add_argument("--name", default="A816.BIN", help="name on the SD card"),
        lambda sp: sp.add_argument("--seconds", type=float, default=15, help="how long to show the log"),
        lambda sp: sp.add_argument("--until", default="816: DONE", help="stop when this text appears"))
    add("shot816", cmd_shot816, lambda sp: sp.add_argument("out", help="PNG file to write"),
        lambda sp: sp.add_argument("--mode", type=int, choices=(0, 1, 2), default=None),
        lambda sp: sp.add_argument("--base", default=None, help="framebuffer address (24-bit)"),
        lambda sp: sp.add_argument("--stride", default=None),
        lambda sp: sp.add_argument("--scale", type=int, default=1),
        lambda sp: sp.add_argument("--no-pointer", action="store_true"),
        lambda sp: sp.add_argument("--no-horizon", action="store_true",
                                   help="don't read the video state from the Horizon kernel"))
    add("peek816", cmd_peek816, lambda sp: sp.add_argument("addr"),
        lambda sp: sp.add_argument("len", nargs="?", default="64"))
    add("reset", cmd_reset,
        lambda sp: sp.add_argument("--warm", action="store_true"),
        lambda sp: sp.add_argument("--keep", action="store_true",
                                   help="don't eject the virtual .xex first"))

    args = ap.parse_args()
    try:
        args.fn(args)
    except LinkError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
