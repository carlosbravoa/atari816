"""ca65obj.py - the segments of ca65 object files and ar65 libraries (cc65 2.19 formats:
object version 17, library version 13), read without cc65's od65.

    segments(path) -> [(segment name, size)] of an object, or of every module of a library

hcc --code large needs the names of the code segments cc816 gives each function
(F_name, FS<tag>_name) before it links: ld65's configuration must list every segment.
"""
import struct

OBJ_MAGIC = 0x616E7A55
LIB_MAGIC = 0x7A55616E


class ObjError(Exception):
    pass


def _var(d, p):
    v = 0
    s = 0
    while True:
        c = d[p]
        p += 1
        v |= (c & 0x7F) << s
        s += 7
        if not c & 0x80:
            return v, p


def _obj_segments(d, where):
    if len(d) < 4 + 4 + 8 * 12 or struct.unpack_from("<I", d, 0)[0] != OBJ_MAGIC:
        raise ObjError(f"{where}: not a ca65 object file")
    ver = struct.unpack_from("<H", d, 4)[0]
    if ver != 17:
        raise ObjError(f"{where}: ca65 object version {ver} (hcc knows version 17, cc65 2.19)")
    # header: magic, version, flags, then (offset, size) pairs: options, files, segments,
    # imports, exports, debug symbols, line infos, string pool, ...
    pairs = struct.unpack_from("<" + "I" * 24, d, 8)
    seg_off = pairs[4]
    str_off = pairs[14]
    # the string pool
    n, p = _var(d, str_off)
    strings = []
    for _ in range(n):
        ln, p = _var(d, p)
        strings.append(d[p:p + ln].decode("latin-1"))
        p += ln
    n, p = _var(d, seg_off)
    out = []
    for _ in range(n):
        dsize = struct.unpack_from("<I", d, p)[0]
        q = p + 4
        name, q = _var(d, q)
        _flags, q = _var(d, q)
        size, q = _var(d, q)
        out.append((strings[name], size))
        p = p + 4 + dsize
    return out


def segments(path):
    d = open(path, "rb").read()
    if len(d) >= 4 and struct.unpack_from("<I", d, 0)[0] == LIB_MAGIC:
        ver, _flags, idx = struct.unpack_from("<HHI", d, 4)
        n, p = _var(d, idx)
        out = []
        for _ in range(n):
            ln, p = _var(d, p)
            name = d[p:p + ln].decode("latin-1")
            p += ln
            _f, _mt, start, size = struct.unpack_from("<HIII", d, p)
            p += 14
            out += _obj_segments(d[start:start + size], f"{path}({name})")
        return out
    return _obj_segments(d, path)


if __name__ == "__main__":
    import sys
    for a in sys.argv[1:]:
        for n, s in segments(a):
            print(f"{a}: {n} {s}")
