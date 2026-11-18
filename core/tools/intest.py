#!/usr/bin/env python3
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
"""intest.py - board test: are key and mouse events lost, and how long does the pointer wait,
while the I/O processor serves long requests? Runs sw/a816/INTEST.BIN (see its header) and
injects input at every phase start.

  --inject fw   (default) the firmware's input generator (developer op $12 INJECT): key taps
                and mouse reports enter at the firmware's input layer at a steady rate, as a
                real keyboard and mouse would (including the loss a full receive FIFO causes)
  --inject dev  developer MOUSE requests, one every 10 ms for 5 s (any firmware; they wait
                while the firmware is busy, so they show how long events were held back)

Phase 4 sends a 500 KB file to the card (developer PUT) while the input is injected.
The gateway (tools/atari816-link) must run for phases 2 and 3 (/PC:).
Prints the 65C816's counts next to what was injected; exit code 1 if anything was lost.
"""
import argparse
import os
import queue
import re
import sys
import time

from atari_link import AtariLink, LinkError
import pclink

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "..", "sw", "a816", "INTEST.BIN")
D_INJECT = 0x12

KEYS, KEY_MS, MICE, MOUSE_MS = 80, 60, 600, 8          # 4.8 s of input per phase


def inject(l, keys, key_ms, mice, mouse_ms):
    l._req(D_INJECT, keys.to_bytes(2, "little") + key_ms.to_bytes(2, "little") +
           mice.to_bytes(2, "little") + bytes([mouse_ms]), timeout=20, what="inject")


def info_fields(l):
    st = l.status(timeout=20)
    return dict(re.findall(r"(\w+):(-?\d+)", st)), st


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inject", choices=("fw", "dev"), default="fw")
    ap.add_argument("--send-kb", type=int, default=500, help="size of the phase 4 upload")
    ap.add_argument("-p", "--port", default=None)
    a = ap.parse_args()

    lines = queue.Queue()
    with AtariLink(a.port, timeout=0.5) as l:
        l.on_log = lambda b: lines.put(b.decode("ascii", "replace").strip())
        l.send(open(BIN, "rb").read(), "A816.BIN")
        l.restart816(test=True)
        res, bad, end = {}, 0, time.time() + 400
        while time.time() < end:
            try:
                ln = lines.get(timeout=1)
            except queue.Empty:
                continue
            if not ln.startswith("816: "):
                continue
            ln = ln[5:]
            print(ln, flush=True)
            m = re.match(r"P(\d) START", ln)
            if m:
                ph = int(m.group(1))
                if a.inject == "fw":
                    info_fields(l)                       # (resets the firmware's meters)
                    inject(l, KEYS, KEY_MS, MICE, MOUSE_MS)
                    if ph == 4:
                        data = bytes((i * 7) & 0xFF for i in range(a.send_kb * 1024))
                        t = time.time()
                        l.send(data, "INTEST3.TMP")
                        print(f"   (upload of {a.send_kb} KB: {time.time() - t:.1f} s)", flush=True)
                else:
                    n, t0 = 0, time.time()
                    while time.time() - t0 < 5:
                        l.mouse(dx=1)
                        n += 1
                        time.sleep(max(0, t0 + n * 0.010 - time.time()))
                    res[ph] = {"mice": n}
                continue
            m = re.match(r"P(\d) US (\w+) KD (\w+) KU (\w+) M (\w+) DX (\w+) G (\w+)", ln)
            if m:
                ph = int(m.group(1))
                us, kd, ku, mc, dx, g = (int(x, 16) for x in m.groups()[1:])
                if dx >= 1 << 31:
                    dx -= 1 << 32
                line = (f"   phase {ph}: {us / 1e6:.1f} s, keys {kd} down / {ku} up, "
                        f"{mc} mouse events, dx {dx}, longest gap {g / 1000:.1f} ms")
                if a.inject == "fw":
                    time.sleep(0.2)
                    f, st = info_fields(l)
                    line += f"\n   firmware: {st}"
                    lost = kd != KEYS or ku != KEYS or dx != MICE
                    if lost:
                        bad = 1
                        line += "\n   LOST INPUT"
                else:
                    sent = res.get(ph, {}).get("mice", 0)
                    line += f" (sent {sent})"
                print(line, flush=True)
                continue
            if "INTEST DONE" in ln or "INTEST FAIL" in ln:
                bad |= "FAIL" in ln
                break
        try:
            l.dev.request(pclink.D_INFO, timeout=5)
        except LinkError:
            pass
    sys.exit(bad)


if __name__ == "__main__":
    main()
