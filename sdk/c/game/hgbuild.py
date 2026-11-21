#!/usr/bin/env python3
"""hgbuild.py - build hgame, the game library (sdk/c/game), into build/game/large/libhgame.a.

    python3 sdk/c/game/hgbuild.py [--force]      (make -C sdk/c/game does this)

bin/hcc calls lib_for(sources) to link it by itself when a C source includes <hgame.h>,
<conio.h> or <joystick.h> (or with hcc --game); it is rebuilt whenever one of its sources,
its headers or the SDK's C library is newer than it. Large model only.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(SDKC, "tools"))
import hzc  # noqa: E402

HEADERS = ("hgame.h", "conio.h", "joystick.h")
_USES = re.compile(r'^\s*#\s*include\s*[<"](?:hgame|conio|joystick)\.h[>"]', re.M)


def outdir(model="large"):
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"),
                        "game", model)


def lib_path(model="large"):
    return os.path.join(outdir(model), "libhgame.a")


def sources():
    return sorted(os.path.join(HERE, f) for f in os.listdir(HERE)
                  if f.endswith((".c", ".s")))


def inputs():
    files = sources() + [os.path.join(HERE, "hg_int.h"), os.path.abspath(__file__)]
    files += [os.path.join(SDKC, "include", h) for h in HEADERS + ("horizon.h", "hzsys.h")]
    return [f for f in files if os.path.exists(f)]


def stale(model="large"):
    lib = lib_path(model)
    if not os.path.exists(lib):
        return True
    t = os.path.getmtime(lib)
    return any(os.path.getmtime(f) > t for f in inputs())


def build(model="large", quiet=False):
    if model != "large":
        raise hzc.HccError("hgame (hgame.h, conio.h, joystick.h) is for the large model")
    od = os.path.join(outdir(model), "obj")
    os.makedirs(od, exist_ok=True)
    if not quiet:
        print(f"hcc: building the game library ({lib_path(model)})", file=sys.stderr)
    objs = []
    for src in sources():
        o = os.path.join(od, os.path.splitext(os.path.basename(src))[0] + ".o")
        if src.endswith(".c"):
            hzc.compile_c(src, o, model, opt="1", incs=[HERE])
        else:
            hzc.assemble(src, o, model, incs=[os.path.join(SDKC, "include")])
        objs.append(o)
    hzc.write_ar(lib_path(model), objs)
    return lib_path(model)


def uses_game(srcs):
    """True when one of the C sources includes hgame.h, conio.h or joystick.h"""
    for s in srcs:
        if s.lower().endswith(".c"):
            try:
                if _USES.search(open(s, encoding="latin-1").read()):
                    return True
            except OSError:
                pass
    return False


def lib_for(model="large"):
    """the library, (re)built if needed -> its path"""
    hzc.ensure_lib(model)
    if stale(model):
        build(model)
    return lib_path(model)


if __name__ == "__main__":
    try:
        if "--force" in sys.argv[1:] or stale():
            hzc.ensure_lib("large")
            build()
    except hzc.HccError as e:
        sys.exit(f"hgbuild: {e}")
