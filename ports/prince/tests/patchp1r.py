#!/usr/bin/env python3
"""tests/patchp1r.py IN.P1R OUT.P1R ROOM X Y DIR - a replay whose savestate (the state the
replay starts from) has the kid in another place: Kid.room, x, y, direction and drawn_room
changed. For scenes the replays cannot reach cheaply from a level's start (the shadow of
level 6: tests/mklevels.sh). The offsets are those of SDLPoP's quick_process at f7be2e9:
level (2,305 bytes), checkpoint, upside_down, drawn_room, current_level, next_level,
mobs_count (2 each), mobs (84), trobs_count (2), trobs (90), leveldoor_open (2), Kid."""
import struct
import sys

DRAWN_ROOM, KID = 2309, 2495


def main():
    b = bytearray(open(sys.argv[1], "rb").read())
    if b[:3] != b"P1R":
        raise SystemExit("patchp1r: %s is not a replay" % sys.argv[1])
    o = 3 + 2 + 1 + 1 + 8               # magic, class, version, deprecation, time
    o += 1 + b[o]                       # the levelset's name
    o += 1 + b[o]                       # the implementation's name
    size = struct.unpack_from("<I", b, o)[0]
    o += 4
    if size < KID + 16:
        raise SystemExit("patchp1r: a savestate of %d bytes" % size)
    room, x, y, d = (int(v) for v in sys.argv[3:7])
    struct.pack_into("<H", b, o + DRAWN_ROOM, room)
    b[o + KID + 1] = x
    b[o + KID + 2] = y
    b[o + KID + 3] = d & 0xFF
    b[o + KID + 9] = room
    open(sys.argv[2], "wb").write(b)


if __name__ == "__main__":
    main()
