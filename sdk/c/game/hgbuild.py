#!/usr/bin/env python3
"""hgbuild.py - build hgame, the game library (sdk/c/game): build/game/cc816/libhgame.lib
(cc816: the C files and cc816/*.s, ca65) and build/game/large/libhgame.a (vbcc's large
model: the C files and *.s, vasm).

    python3 sdk/c/game/hgbuild.py [--force] [--cc cc816|vbcc]   (make -C sdk/c/game)

bin/hcc calls lib_for(model) to link it by itself when a C source includes <hgame.h>,
<conio.h> or <joystick.h> (or with hcc --game); it is rebuilt whenever one of its sources,
its headers or the SDK's C library is newer than it. With vbcc: the large model only.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(SDKC, "tools"))
import hzc  # noqa: E402
import hzc816  # noqa: E402

HEADERS = ("hgame.h", "conio.h", "joystick.h")
_USES = re.compile(r'^\s*#\s*include\s*[<"](?:hgame|conio|joystick)\.h[>"]', re.M)


def outdir(model="large"):
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"),
                        "game", model)


def lib_path(model="large"):
    """model: cc816, cc816l (cc816's large code model, hcc --code large), large (vbcc)"""
    return os.path.join(outdir(model), "libhgame.a" if model == "large" else "libhgame.lib")


def sources(model="large"):
    """the C files, and the assembly for the compiler: cc816/*.s (ca65) or *.s (vasm)"""
    srcs = [os.path.join(HERE, f) for f in os.listdir(HERE) if f.endswith(".c")]
    if model in ("cc816", "cc816l"):
        d = os.path.join(HERE, "cc816")
        srcs += [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".s")]
    else:
        srcs += [os.path.join(HERE, f) for f in os.listdir(HERE) if f.endswith(".s")]
    return sorted(srcs)


def inputs(model="large"):
    files = sources(model) + [os.path.join(HERE, "hg_int.h"), os.path.abspath(__file__)]
    files += [os.path.join(SDKC, "include", h) for h in HEADERS + ("horizon.h", "hzsys.h")]
    if model in ("cc816", "cc816l"):
        files += hzc816.compiler_files() + [os.path.join(hzc816.RT, "model.inc")]
    return [f for f in files if os.path.exists(f)]


def stale(model="large"):
    lib = lib_path(model)
    if not os.path.exists(lib):
        return True
    t = os.path.getmtime(lib)
    return any(os.path.getmtime(f) > t for f in inputs(model))


def build(model="large", quiet=False):
    if model not in ("large", "cc816", "cc816l"):
        raise hzc.HccError("hgame (hgame.h, conio.h, joystick.h) is for the large model")
    od = os.path.join(outdir(model), "obj")
    if os.path.exists(od):
        import shutil
        shutil.rmtree(od)
    os.makedirs(od, exist_ok=True)
    if not quiet:
        print(f"hcc: building the game library ({lib_path(model)})", file=sys.stderr)
    objs = []
    for src in sources(model):
        o = os.path.join(od, os.path.splitext(os.path.basename(src))[0] + ".o")
        if model in ("cc816", "cc816l"):
            code = "large" if model == "cc816l" else "small"
            if src.endswith(".c"):
                objs += hzc816.compile_split(src, od, "2", incs=[HERE], code=code)
                continue
            else:
                hzc816.assemble(src, o, incs=[os.path.join(SDKC, "include")], code=code)
        elif src.endswith(".c"):
            hzc.compile_c(src, o, model, opt="1", incs=[HERE])
        else:
            hzc.assemble(src, o, model, incs=[os.path.join(SDKC, "include")])
        objs.append(o)
    if model in ("cc816", "cc816l"):
        lib = lib_path(model)
        if os.path.exists(lib):
            os.remove(lib)
        hzc.run([hzc816.tool("ar65"), "a", lib] + objs, "ar65")
    else:
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
    if model in ("cc816", "cc816l"):
        hzc816.ensure_lib("large" if model == "cc816l" else "small")
    else:
        hzc.ensure_lib(model)
    if stale(model):
        with hzc816.locked("hgame-" + model):
            if stale(model):
                build(model)
    return lib_path(model)


if __name__ == "__main__":
    a = sys.argv[1:]
    ccs = ["cc816", "cc816l", "large"]
    if "--cc" in a:
        ccs = ["cc816", "cc816l"] if a[a.index("--cc") + 1] == "cc816" else ["large"]
    try:
        for m in ccs:
            if "--force" in a or stale(m):
                lib_for(m) if not ("--force" in a) else (
                    hzc816.ensure_lib("large" if m == "cc816l" else "small")
                    if m.startswith("cc816") else hzc.ensure_lib(m), build(m))
    except hzc.HccError as e:
        sys.exit(f"hgbuild: {e}")
