#!/usr/bin/env python3
"""hgbuild.py - build hgame, the game library (sdk/c/game): build/game/small/libhgame.lib
and build/game/large/libhgame.lib (the two code models: the C files and *.s, ca65).

    python3 sdk/c/game/hgbuild.py [--force] [--code small|large]   (make -C sdk/c/game)

bin/hcc calls lib_for(code) to link it by itself when a C source includes <hgame.h>,
<conio.h> or <joystick.h> (or with hcc --game); it is rebuilt whenever one of its sources,
its headers, the compiler or the SDK's C library is newer than it.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(SDKC, "tools"))
import hzc816  # noqa: E402

HEADERS = ("hgame.h", "conio.h", "joystick.h")
_USES = re.compile(r'^\s*#\s*include\s*[<"](?:hgame|conio|joystick)\.h[>"]', re.M)


def outdir(code="small"):
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"),
                        "game", code)


def lib_path(code="small"):
    """code: the code model, small or large (hcc --code large)"""
    return os.path.join(outdir(code), "libhgame.lib")


def sources():
    """the C files and the assembly (ca65)"""
    return sorted(os.path.join(HERE, f) for f in os.listdir(HERE) if f.endswith((".c", ".s")))


def inputs(code="small"):
    files = sources() + [os.path.join(HERE, "hg_int.h"), os.path.abspath(__file__)]
    files += [os.path.join(SDKC, "include", h) for h in HEADERS + ("horizon.h", "hzsys.h")]
    files += hzc816.compiler_files() + [os.path.join(hzc816.RT, "model.inc")]
    return [f for f in files if os.path.exists(f)]


def stale(code="small"):
    lib = lib_path(code)
    if not os.path.exists(lib):
        return True
    t = os.path.getmtime(lib)
    return any(os.path.getmtime(f) > t for f in inputs(code))


def build(code="small", quiet=False):
    if code not in hzc816.CODES:
        raise hzc816.HccError(f"hgame: the code model is small or large, not {code}")
    od = os.path.join(outdir(code), "obj")
    if os.path.exists(od):
        import shutil
        shutil.rmtree(od)
    os.makedirs(od, exist_ok=True)
    if not quiet:
        print(f"hcc: building the game library ({lib_path(code)})", file=sys.stderr)
    objs = []
    for src in sources():
        if src.endswith(".c"):
            objs += hzc816.compile_split(src, od, "2", incs=[HERE], code=code)
        else:
            o = os.path.join(od, os.path.splitext(os.path.basename(src))[0] + ".o")
            hzc816.assemble(src, o, incs=[os.path.join(SDKC, "include")], code=code)
            objs.append(o)
    lib = lib_path(code)
    if os.path.exists(lib):
        os.remove(lib)
    hzc816.run([hzc816.tool("ar65"), "a", lib] + objs, "ar65")
    return lib


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


def lib_for(code="small"):
    """the library for a code model, (re)built if needed -> its path"""
    hzc816.ensure_lib(code)
    if stale(code):
        with hzc816.locked("hgame-" + code):
            if stale(code):
                build(code)
    return lib_path(code)


if __name__ == "__main__":
    a = sys.argv[1:]
    codes = list(hzc816.CODES)
    if "--code" in a:
        codes = [a[a.index("--code") + 1]]
    try:
        for c in codes:
            if "--force" in a:
                hzc816.ensure_lib(c)
                build(c)
            else:
                lib_for(c)
    except hzc816.HccError as e:
        sys.exit(f"hgbuild: {e}")
