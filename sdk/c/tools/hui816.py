"""hui816.py - the controls library (hui.h) for C programs.

ld65 links Horizon's controls library and ulib straight into the program, as Horizon's own
assembly programs have them: build/ui/small/ (build/ui/large/ for the large code model)
holds ui.lib (horizon/user/ui*.s, assembled as Horizon's Makefile does), ulib.lib
(horizon/user/ulib.s) and hui816.lib (the shims tools/genhui.py writes from ui/hui.tab,
ui/lib/*.s and ui/huirt.c), rebuilt whenever a
source is newer. A program links only the shims it calls and the library routines they
need; the library's zero page goes beside cc816's registers (ld65 places it). No block, no
bank-byte list: cc816's pointers are offsets in the code bank, where the library works.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDKC = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import hzc816  # noqa: E402
from hzc816 import HccError  # noqa: E402

LIB816 = os.path.join(SDKC, "ui", "lib")


def outdir(code=None):
    return os.path.join(os.environ.get("HZ_BUILD") or os.path.join(SDKC, "build"), "ui",
                        "large" if hzc816.is_large(code) else "small")


def user_dir():
    return os.path.join(hzc816.horizon_dir(), "user")


def ui_sources():
    u = user_dir()
    return sorted(os.path.join(u, f) for f in os.listdir(u)
                  if f.startswith("ui") and f.endswith(".s"))


def inputs():
    u = user_dir()
    files = ui_sources() + [os.path.join(u, f) for f in ("ui.inc", "horizon.inc",
                                                          "version.inc", "icons.inc", "ulib.s")]
    files += [os.path.join(LIB816, f) for f in os.listdir(LIB816)]
    files += [os.path.join(SDKC, "ui", f) for f in ("hui.tab", "huirt.c")]
    files += [os.path.join(HERE, "genhui.py"), os.path.abspath(__file__),
              os.path.join(hzc816.RT, "model.inc")]
    return files


def stale(code=None):
    stamp = os.path.join(outdir(code), "stamp")
    if not os.path.exists(stamp):
        return True
    t = os.path.getmtime(stamp)
    return any(os.path.getmtime(f) > t for f in inputs())


def build(quiet=False, code=None):
    import genhui
    large = hzc816.is_large(code)
    u = user_dir()
    if not os.path.exists(os.path.join(u, "ui.inc")):
        raise HccError(f"the Horizon tree is not at {hzc816.horizon_dir()} (set HORIZON): the "
                       f"controls library is built from its sources")
    d = outdir(code)
    od = os.path.join(d, "obj")
    if os.path.exists(od):
        shutil.rmtree(od)
    os.makedirs(od)
    if not quiet:
        print(f"hcc: building the controls library ({d})", file=sys.stderr)
    ca65, ar65 = hzc816.cc65_tool("ca65"), hzc816.cc65_tool("ar65")

    def asm(src, sub="", model=False):
        # (Horizon's own ui*.s and ulib.s as they are; the shims and ui/lib for the model)
        o = os.path.join(od, sub + os.path.splitext(os.path.basename(src))[0] + ".o")
        hzc816.run([ca65, "--cpu", "65816", "-g", "-I", u, "-I", LIB816, "-I", hzc816.RT] +
                (["-D", "__CC816_LARGE__=1"] if model and large else []) + ["-o", o, src],
                f"assembling {src}")
        return o

    def lib(name, objs):
        p = os.path.join(d, name)
        if os.path.exists(p):
            os.remove(p)
        hzc816.run([ar65, "a", p] + objs, "ar65")

    lib("ui.lib", [asm(s) for s in ui_sources()])
    lib("ulib.lib", [asm(os.path.join(u, "ulib.s"))])
    fns, vars_, _ = genhui.parse_table()
    objs = [asm(s, "s_", True) for s in genhui.write_shims816(os.path.join(d, "shims"), fns,
                                                               vars_, large)]
    objs += [asm(os.path.join(LIB816, f), "l_", True) for f in sorted(os.listdir(LIB816))
             if f.endswith(".s")]
    o = os.path.join(od, "huirt.o")
    if large:
        objs += hzc816.compile_split(os.path.join(SDKC, "ui", "huirt.c"), od, code="large")
        o = None
    else:
        hzc816.compile_c(os.path.join(SDKC, "ui", "huirt.c"), o, code="small")
    if o:
        objs.append(o)
    lib("hui816.lib", objs)
    open(os.path.join(d, "stamp"), "w").write("ok\n")


def link_inputs(code=None):
    """the libraries, in the order ld65 needs them"""
    if stale(code):
        with hzc816.locked("hui-" + ("large" if hzc816.is_large(code) else "small")):
            if stale(code):
                build(code=code)
    d = outdir(code)
    return [os.path.join(d, n) for n in ("hui816.lib", "ui.lib", "ulib.lib")]
