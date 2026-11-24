#!/usr/bin/env python3
"""tools/p1rstrip.py - SDLPoP replays (.p1r) without the game's level data, for git.

A .p1r (src/replay.c, save_recorded_replay) is: "P1R", the format's class, version and
deprecation numbers, the creation time, the levelset's and the implementation's names, a
savestate (src/seg000.c, quick_process: the level structure, 2,305 bytes, then the
checkpoint, the room, the level's number, the moving objects, the kid, the guard, ...),
SDLPoP's options per section, the start level, the random seed and the moves (a byte a
tick). The level structure is the publisher's level (LEVELS.DAT's resource 2000+N) as the
game's own start-of-level code left it (load_level: alter_mods_allrm and
reset_level_unused_fields, ported below), then changed by the run of the game in a few
bytes (a torch's flame, a gate on its way down, a button's timer, a guard's place kept for
its room): the level is game data and never goes into git, the few changes are kept as
their XOR with the loaded level (the change, not the level's byte). The rest is the state
of a run of the game (where the kid and the guard are, what they do, the timers) and the
recorded moves: ours, kept in a text file (.p1x) next to the scripted input.

  p1rstrip.py strip IN.p1r OUT.p1x [--levels DIR]
        the replay without its level (DIR: SDLPoP's data/LEVELS, the res20NN.bin files of
        tools/getdata.sh; default data/sdlpop/data/LEVELS). The level must be the one DIR's
        resource and the start-of-level code make, but for at most 64 bytes the run changed
        (kept as their XOR with it).
  p1rstrip.py build IN.p1x OUT.p1r [--levels DIR]
        the replay again, byte for byte (its MD5 is in the .p1x and is checked)
  p1rstrip.py test [--levels DIR] P1X...
        builds each, strips it again: the same .p1x, the MD5 recorded in it
"""
import hashlib
import os
import struct
import sys

LEVEL_SIZE = 2305
FG, BG, ROOMLINKS, USED_ROOMS = 0, 720, 1952, 2048
ROOMXS, ROOMYS, FILL_1, FILL_2 = 2049, 2073, 2097, 2115
GUARDS_SKILL, GUARDS_COLOR, FILL_3 = 2215, 2263, 2287
CURRENT_LEVEL = LEVEL_SIZE + 6          # checkpoint, upside_down, drawn_room: 2 bytes each
MAX_CHANGED = 64                        # bytes of the level the run may have changed
GATE, POTION, LOOSE, TORCH, WALL, TORCH_DEBRIS, EMPTY, FLOOR = 4, 10, 11, 19, 20, 30, 0, 1


def alter_mods_allrm(lv):
    """src/seg008.c's alter_mods_allrm and load_alter_mod (VGA, USE_FAKE_TILES,
    USE_COLORED_TORCHES; the copy protection's potion of level 15 is not here: the
    original levels have none in the savestates this is for)."""
    if lv[USED_ROOMS] > 24:
        lv[USED_ROOMS] = 24
    fg, bg = FG, BG

    def is_wall(tile, modif):
        return ((tile == WALL and modif != 4 and (modif >> 4) != 4 and modif != 6 and (modif >> 4) != 6)
                or (tile in (EMPTY, FLOOR) and (modif in (5, 13) or 50 <= modif <= 53)))

    for room in range(1, lv[USED_ROOMS] + 1):
        t0, m0 = fg + (room - 1) * 30, bg + (room - 1) * 30
        room_l = lv[ROOMLINKS + (room - 1) * 4]
        room_r = lv[ROOMLINKS + (room - 1) * 4 + 1]
        for pos in range(30):
            m = m0 + pos
            tile = lv[t0 + pos] & 0x1F
            if tile == GATE:
                lv[m] = 188 if lv[m] == 1 else 0
                continue
            if tile == LOOSE:
                lv[m] = 0
                continue
            if tile == POTION:
                lv[m] = (lv[m] << 3) & 0xFF
                continue
            if tile in (TORCH, TORCH_DEBRIS):
                lv[m] = 0
                continue
            if tile == WALL:
                s = lv[m]
                lv[m] = 0x80 if s == 1 else (s << 4) & 0xFF
            elif tile in (EMPTY, FLOOR):
                if (lv[m] & 7) != 5:
                    continue
            else:
                continue
            left = right = True
            if pos % 10 == 0:
                if room_l:
                    a = 30 * (room_l - 1) + pos + 9
                    left = is_wall(lv[fg + a] & 0x1F, lv[bg + a])
            else:
                left = is_wall(lv[t0 + pos - 1] & 0x1F, lv[m0 + pos - 1])
            if pos % 10 == 9:
                if room_r:
                    a = 30 * (room_r - 1) + pos - 9
                    right = is_wall(lv[fg + a] & 0x1F, lv[bg + a])
            else:
                right = is_wall(lv[t0 + pos + 1] & 0x1F, lv[m0 + pos + 1])
            if tile in (EMPTY, FLOOR):
                if left and right:
                    lv[m] = 53
                elif left:
                    lv[m] = 52
                elif right:
                    lv[m] = 51
                continue
            lv[m] |= 3 if (left and right) else 2 if left else 1 if right else 0


def reset_level_unused_fields(lv):
    """src/seg000.c's reset_level_unused_fields(true)."""
    for o, n in ((ROOMXS, 24), (ROOMYS, 24), (FILL_1, 15), (FILL_2, 4), (FILL_3, 18)):
        lv[o:o + n] = bytes(n)
    if lv[USED_ROOMS] > 24:
        lv[USED_ROOMS] = 24
    for i in range(lv[USED_ROOMS]):
        lv[GUARDS_SKILL + i] &= 0x0F
        lv[GUARDS_COLOR + i] &= 0x0F


def level_of(levels, n):
    """the level as load_level leaves it: the resource, then the start-of-level code"""
    path = os.path.join(levels, "res%d.bin" % (2000 + n))
    try:
        raw = open(path, "rb").read()
    except OSError:
        raise SystemExit("p1rstrip: no %s (the game's data: make data, tools/getdata.sh)" % path)
    if len(raw) != LEVEL_SIZE:
        raise SystemExit("p1rstrip: %s is %d bytes, not %d" % (path, len(raw), LEVEL_SIZE))
    lv = bytearray(raw)
    alter_mods_allrm(lv)
    reset_level_unused_fields(lv)
    return bytes(lv)


def parse(b):
    """the replay's parts: (head, savestate, tail)"""
    if b[:3] != b"P1R":
        raise SystemExit("p1rstrip: not a replay")
    o = 3 + 2 + 1 + 1 + 8
    o += 1 + b[o]
    o += 1 + b[o]
    size = struct.unpack_from("<I", b, o)[0]
    o += 4
    if size < LEVEL_SIZE + 8 or o + size > len(b):
        raise SystemExit("p1rstrip: a savestate of %d bytes" % size)
    return b[:o], b[o:o + size], b[o + size:]


def hexlines(tag, data, width=32):
    out = ["%s %d" % (tag, len(data))]
    for i in range(0, len(data), width):
        out.append("  " + data[i:i + width].hex())
    return out


def strip(p1r, levels):
    b = open(p1r, "rb").read()
    head, ss, tail = parse(b)
    level_no = struct.unpack_from("<H", ss, CURRENT_LEVEL)[0]
    want = level_of(levels, level_no)
    changed = [(i, ss[i] ^ want[i]) for i in range(LEVEL_SIZE) if ss[i] != want[i]]
    if len(changed) > MAX_CHANGED:
        raise SystemExit("p1rstrip: %s: the level is not level %d as the game loads it: %d bytes "
                         "differ (the first at %d)" % (p1r, level_no, len(changed), changed[0][0]))
    o = 3
    cls, ver, dep, t = struct.unpack_from("<HBBq", b, o)
    o += 12
    lsn = b[o + 1:o + 1 + b[o]]
    o += 1 + b[o]
    impl = b[o + 1:o + 1 + b[o]]
    lines = [
        "# %s without the game's level (tools/p1rstrip.py build: the .p1r again, from the" % os.path.basename(p1r),
        "# level data of tools/getdata.sh). An SDLPoP replay's own fields; the savestate after",
        "# its level structure (the kid, the guard, the objects, the timers); the options, the",
        "# start level, the seed and the moves (a byte a tick).",
        "p1x 1",
        "md5 %s" % hashlib.md5(b).hexdigest(),
        "class %d" % cls, "version %d" % ver, "deprecation %d" % dep, "time %d" % t,
        "levelset %s" % (lsn.hex() or "-"), "implementation %s" % impl.decode("latin-1"),
        "level %d" % level_no,
        "changed %d" % len(changed),
    ]
    lines += ["  %d %d" % c for c in changed]
    lines += hexlines("state", ss[LEVEL_SIZE:])
    lines += hexlines("tail", tail)
    return "\n".join(lines) + "\n"


def build(p1x, levels):
    f, cur = {}, None
    for ln in open(p1x).read().splitlines():
        if not ln or ln.startswith("#"):
            continue
        if ln.startswith("  "):
            if cur == "changed":
                f[cur].append(tuple(int(v) for v in ln.split()))
            else:
                f[cur] += bytes.fromhex(ln.strip())
            continue
        k, _, v = ln.partition(" ")
        if k == "changed":
            cur, f[k], f[k + "_n"] = k, [], int(v)
        elif k in ("state", "tail"):
            cur, f[k], f[k + "_n"] = k, b"", int(v)
        else:
            f[k] = v
    if f.get("p1x") != "1":
        raise SystemExit("p1rstrip: %s is not a .p1x" % p1x)
    for k in ("changed", "state", "tail"):
        if len(f[k]) != f[k + "_n"]:
            raise SystemExit("p1rstrip: %s: %s holds %d bytes, not %d" % (p1x, k, len(f[k]), f[k + "_n"]))
    lsn, impl = bytes.fromhex(f["levelset"].strip("-")), f["implementation"].encode("latin-1")
    lv = bytearray(level_of(levels, int(f["level"])))
    for o, x in f["changed"]:
        lv[o] ^= x
    ss = bytes(lv) + f["state"]
    b = (b"P1R" + struct.pack("<HBBq", int(f["class"]), int(f["version"]), int(f["deprecation"]),
                              int(f["time"]))
         + bytes([len(lsn)]) + lsn + bytes([len(impl)]) + impl
         + struct.pack("<I", len(ss)) + ss + f["tail"])
    if hashlib.md5(b).hexdigest() != f["md5"]:
        raise SystemExit("p1rstrip: %s: the rebuilt replay's MD5 is %s, not %s (another level data?)"
                         % (p1x, hashlib.md5(b).hexdigest(), f["md5"]))
    return b, f["md5"]


def main():
    a = sys.argv[1:]
    levels = "data/sdlpop/data/LEVELS"
    if "--levels" in a:
        i = a.index("--levels")
        levels = a[i + 1]
        del a[i:i + 2]
    if len(a) == 3 and a[0] == "strip":
        t = strip(a[1], levels)
        open(a[2], "w").write(t)
    elif len(a) == 3 and a[0] == "build":
        b, _ = build(a[1], levels)
        d = os.path.dirname(a[2])
        if d:
            os.makedirs(d, exist_ok=True)
        open(a[2] + ".new", "wb").write(b)
        os.replace(a[2] + ".new", a[2])
    elif len(a) >= 2 and a[0] == "test":
        import tempfile
        for p1x in a[1:]:
            b, md5 = build(p1x, levels)
            with tempfile.TemporaryDirectory() as t:
                p = os.path.join(t, "r.p1r")
                open(p, "wb").write(b)
                again = strip(p, levels).splitlines()[4:]
            if again != open(p1x).read().splitlines()[4:]:
                raise SystemExit("p1rstrip: %s: stripping the rebuilt replay gives another .p1x" % p1x)
            print("p1rstrip: %s: %d bytes, MD5 %s as recorded" % (p1x, len(b), md5))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
