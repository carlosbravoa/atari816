#!/usr/bin/env python3
"""doccheck.py - is the SDK's manual complete? (make -C sdk/c check runs it)

    python3 sdk/tools/doccheck.py [--list] [--verbose]
    python3 sdk/tools/doccheck.py --write-syscalls     (sdk/docs/c/syscalls.md again)

The manual is every .md file under sdk/docs. This check fails (exit 1) when something
a programmer can call or run is mentioned nowhere in it:

  1. every function declared in a public header (sdk/c/include/*.h, the C library's
     sdk/c/cc816/include/*.h), and every function-like macro of those headers whose
     name starts with hz_, hg_, HZ_, HG_ or ui_ (HZ_U24, HG_RGB, ...);
  2. every public header by its name (hgame.h, stdio.h, ...);
  3. every option that the help (-h) of hcc, cc816.py, run816.py, hzapp.py, host16.py,
     inputscript.py and emu816 lists, and hzapp.py's commands; for run816.py and emu816
     also the options their sources take that their help leaves out;
  4. every tool: each .py and .sh file of sdk/tools, sdk/c/tools, sdk/c/game and
     sdk/c/game/tools by its file name;
  5. sdk/docs/c/syscalls.md, the index of the hz_ functions, is what hzsys.h gives now
     (it is generated: python3 sdk/tools/doccheck.py --write-syscalls).

"Mentioned" means the name appears as a whole word (an option: as a whole option,
`--fixups`, not `--fixups-x`). It does not prove that the text is right; it proves that
nothing public was added without a line in the manual.

Names that are deliberately not in the manual are in ALLOW below, each with the reason.
Names that start with an underscore are the implementation's (C reserves them) and are
not checked. --list prints what is checked; --verbose also where each name was found.
"""
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDK = os.path.dirname(HERE)
REPO = os.path.dirname(SDK)

# ---- the allow-list: public-looking names that the manual leaves out on purpose.
# Keep it short; every entry says why. A name here that the manual does mention, or that
# no header declares any more, is reported too (so the list does not rot).
#   "name": "why it is not in the manual",          (a function or macro)
#   "hcc --option": "why",                          (a tool's option)
# Empty at Horizon 0.31: every public name is documented (hui.h's hui_rowtramp, the
# internal trampoline behind HUI_ROWCB, is named in c/apps.md, "How the library gets
# into a program").
ALLOW = {}

# options that are synonyms printed on the same help line as one that is checked, or
# patterns, not options a user types as they are
OPTION_PATTERNS = {
    "-Wno-NAME", "-WNAME",
}

TOOLS = {
    # tool: (command line for its help, prefix used in the help's usage lines)
    "hcc": [sys.executable, os.path.join(SDK, "c", "bin", "hcc"), "-h"],
    "cc816.py": [sys.executable, os.path.join(SDK, "c", "cc816", "cc816.py"), "--help"],
    "run816.py": [sys.executable, os.path.join(SDK, "tools", "run816.py"), "-h"],
    "hzapp.py": [sys.executable, os.path.join(SDK, "tools", "hzapp.py"), "-h"],
    "host16.py": [sys.executable, os.path.join(SDK, "c", "tools", "host16.py"), "-h"],
    "inputscript.py": [sys.executable, os.path.join(SDK, "tools", "inputscript.py"), "-h"],
}
EMU = os.environ.get("EMU") or os.path.join(REPO, "emu", "emu816")

fails = []


def strip_c(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def header_names(path):
    """the functions a header declares or defines (inline), and its function-like
    macros"""
    t = strip_c(open(path, encoding="latin-1").read())
    t = re.sub(r"\\\n", " ", t)
    macros = set(re.findall(r"^[ \t]*#[ \t]*define[ \t]+(\w+)\(", t, flags=re.M))
    t = re.sub(r"^[ \t]*#[^\n]*", "", t, flags=re.M)
    funcs = set()
    depth = 0
    buf = ""
    for ch in t:
        if ch == "{":
            if depth == 0:
                # a function's body: NAME(...) {   (not struct/union/enum bodies)
                m = re.search(r"\b([A-Za-z_]\w*)\s*\(((?:[^()]|\([^()]*\))*)\)\s*$", buf)
                if m and not re.search(r"\b(struct|union|enum)\b[^;]*$", buf[:m.start()]):
                    funcs.add(m.group(1))
            depth += 1
            buf = ""
        elif ch == "}":
            depth -= 1
            buf = ""
        elif depth == 0:
            if ch == ";":
                d = " ".join(buf.split())
                if not d.startswith("typedef"):
                    # a declaration NAME(...): the first identifier followed by '(' that
                    # is not inside a pointer declarator ('(*name)(...)' is a variable)
                    m = re.match(r"[^()]*?\b([A-Za-z_]\w*)\s*\(", d)
                    if m and not re.match(r"\s*\*", d[m.end():]):
                        if m.group(1) not in ("__attribute__", "__declspec"):
                            funcs.add(m.group(1))
                buf = ""
            else:
                buf += ch
    return funcs, macros


def public_headers():
    return sorted(glob.glob(os.path.join(SDK, "c", "include", "*.h")) +
                  glob.glob(os.path.join(SDK, "c", "cc816", "include", "*.h")))


def manual():
    texts = {}
    for p in sorted(glob.glob(os.path.join(SDK, "docs", "**", "*.md"), recursive=True)):
        texts[os.path.relpath(p, REPO)] = open(p, encoding="utf-8").read()
    return texts


def help_options(name, cmd):
    """the options a tool's help lists: those at the start of a help line (the option
    column, up to two spaces) and those in its usage lines"""
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        fails.append(f"{name}: no help ({e})")
        return set(), ""
    out = r.stdout.decode("latin-1")
    opts = set()
    for line in out.splitlines():
        m = re.match(r"^\s{1,8}(-.*)$", line)
        col = None
        if m:
            col = re.split(r"\S\s{2,}", m.group(1) + "  ", maxsplit=1)[0]
            col = m.group(1)[:len(col) + 1]
        elif re.search(r"\b" + re.escape(name) + r"\b", line):
            col = line                  # a usage line
        if col is None:
            continue
        for o in re.findall(r"(?<![\w-])(--?[A-Za-z][\w-]*)", col):
            o = o.rstrip("-")
            if o in OPTION_PATTERNS:
                continue
            opts.add(o)
    return opts, out


def emu_options():
    """emu816's options: every one its source takes (strcmp(a, "--x"): also those its
    help leaves out), and its usage text (emu816 --help) when it is built"""
    src = open(os.path.join(REPO, "emu", "main.c"), encoding="latin-1").read()
    opts = set(re.findall(r'strcmp\(\w+, "(--[\w-]+)"\)', src))
    if os.path.exists(EMU):
        opts |= help_options("emu816", [EMU, "--help"])[0]
    return opts


def run816_source_options():
    """the options run816.py's own parser takes (some are not in its help)"""
    src = open(os.path.join(SDK, "tools", "run816.py"), encoding="latin-1").read()
    opts = set(re.findall(r"w == '(--[\w-]+)'", src))
    for tup in re.findall(r"w in \(([^)]*)\)", src):
        opts |= set(re.findall(r"'(--[\w-]+)'", tup))
    return opts


def word_in(name, words):
    return name in words


# ---- sdk/docs/c/syscalls.md: the index of the hz_ syscall functions, made from hzsys.h
SYSCALLS_MD = os.path.join(SDK, "docs", "c", "syscalls.md")


def gh_slug(heading):
    """GitHub's anchor for a heading (also the site generator's)"""
    s = heading.strip().lower()
    s = re.sub(r"[^\w\- ]", "", s)
    return s.replace(" ", "-")


def syscall_sections():
    """name -> (file, anchor) of each '### $NN name (SYS_X)' heading of the assembly
    reference (the first one when a call is described twice)"""
    out = {}
    ref = os.path.join(SDK, "docs", "reference")
    for f in sorted(os.listdir(ref)):
        if not f.endswith(".md"):
            continue
        for line in open(os.path.join(ref, f), encoding="utf-8"):
            m = re.match(r"### (\$[0-9A-F]{2} (\w+) \(SYS_\w+\))\s*$", line)
            if m and m.group(2) not in out:
                out[m.group(2)] = (f, gh_slug(m.group(1)))
    return out


def syscalls_page():
    """the text of sdk/docs/c/syscalls.md, from hzsys.h's comments and prototypes"""
    hdr = open(os.path.join(SDK, "c", "include", "hzsys.h"), encoding="latin-1").read()
    m = re.search(r"(\d+) syscalls, (\d+) C functions", hdr)
    nsys, nfun = (m.group(1), m.group(2)) if m else ("?", "?")
    secs = syscall_sections()
    rows = []
    for c, proto in re.findall(r"/\*\*(.*?)\*/\s*\n([^\n;]+;)", hdr, flags=re.S):
        c = " ".join(c.replace("*", " ").split())
        mm = re.match(r"(\w+) \((SYS_\w+), \$([0-9A-F]{2})\): (.*?)\s*\[(.*)\]$", c)
        if not mm:
            continue
        name, const, num, what, regs = mm.groups()
        fname = re.search(r"\b(hz_\w+)\s*\(", proto).group(1)
        f, anchor = secs.get(name, (None, None))
        link = f"[{name}](../reference/{f}#{anchor})" if f else name
        rows.append((int(num, 16), fname, proto.strip(), num, link, const,
                     what.replace("|", "\\|"), regs.replace("|", "\\|")))
    rows.sort(key=lambda r: (r[0], r[1]))
    out = [
        "# Syscalls from C: every hz_ function",
        "",
        "<!-- GENERATED by sdk/tools/doccheck.py --write-syscalls from sdk/c/include/hzsys.h:",
        "     do not edit; make -C sdk/c check fails when this page and the header differ. -->",
        "",
        f"`horizon.h` includes `hzsys.h`: {nsys} syscalls as {nfun} C functions, one line each",
        "below, in the order of their numbers. The first column is the C prototype exactly as the",
        "header has it; the link goes to the syscall's section in the assembly reference, which",
        "has the details (registers, blocks, errors, examples). How the functions return and set",
        "`hz_errno`, `hz_x` and `hz_y`, the parameter blocks and the helpers that are not",
        "syscalls: [reference.md](reference.md), \"Syscalls from C\".",
        "",
        "The last column says how the arguments travel (A, X, Y, XY for a pointer; `out:` the",
        "registers a call leaves in `hz_x` / `hz_y`).",
        "",
        "| Function | No. | Syscall | What | Registers |",
        "| --- | --- | --- | --- | --- |",
    ]
    for _, fname, proto, num, link, const, what, regs in rows:
        out.append(f"| `{proto}` | ${num} | {link} (`{const}`) | {what} | {regs} |")
    out.append("")
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    listing = "--list" in args
    verbose = "--verbose" in args
    if "--write-syscalls" in args:
        with open(SYSCALLS_MD, "w", encoding="utf-8") as f:
            f.write(syscalls_page())
        print("wrote " + os.path.relpath(SYSCALLS_MD, REPO))
        return 0
    if not os.path.exists(SYSCALLS_MD) or \
            open(SYSCALLS_MD, encoding="utf-8").read() != syscalls_page():
        fails.append(os.path.relpath(SYSCALLS_MD, REPO) + " differs from hzsys.h: "
                     "python3 sdk/tools/doccheck.py --write-syscalls")
    texts = manual()
    alltext = "\n".join(texts.values())
    words = set(re.findall(r"[A-Za-z_][\w]*", alltext))
    optwords = set(re.findall(r"(?<![\w-])(--?[A-Za-z][\w-]*)", alltext))
    optwords |= {o.rstrip("-") for o in optwords}

    def where(name):
        return [p for p, t in texts.items() if re.search(r"(?<![\w-])" + re.escape(name) +
                                                         r"(?![\w])", t)]

    checked = {}

    # 1, 2: headers
    for h in public_headers():
        base = os.path.basename(h)
        checked.setdefault("header", []).append(base)
        funcs, macros = header_names(h)
        for f in sorted(funcs):
            if not f.startswith("_"):
                checked.setdefault("function " + base, []).append(f)
        for m in sorted(macros):
            if re.match(r"(hz_|hg_|HZ_|HG_|ui_|UI_|hui_|HUI_)", m):
                checked.setdefault("macro " + base, []).append(m)

    missing = []
    for kind, names in checked.items():
        for n in names:
            if kind == "header":
                ok = n in alltext
            else:
                ok = word_in(n, words)
            if listing:
                print(f"{kind}: {n}" + (f"  {where(n)}" if verbose and ok else ""))
            if not ok and n not in ALLOW:
                missing.append(f"{kind}: {n}")

    # 3: tools' options
    for tool, cmd in TOOLS.items():
        opts, out = help_options(tool, cmd)
        if tool == "run816.py":
            opts |= run816_source_options()
        if tool == "hzapp.py":
            for sub in ("pack", "list", "check", "icon"):
                if not re.search(r"hzapp(\.py)? " + sub + r"\b", alltext):
                    missing.append(f"hzapp.py command: {sub}")
        for o in sorted(opts):
            if listing:
                print(f"option {tool}: {o}")
            if o not in optwords and f"{tool} {o}" not in ALLOW:
                missing.append(f"option {tool}: {o}")
    for o in sorted(emu_options()):
        if listing:
            print(f"option emu816: {o}")
        if o not in optwords and f"emu816 {o}" not in ALLOW:
            missing.append(f"option emu816: {o}")

    # 4: tools by name
    for d in (os.path.join(SDK, "tools"), os.path.join(SDK, "c", "tools"),
              os.path.join(SDK, "c", "game"), os.path.join(SDK, "c", "game", "tools")):
        for f in sorted(os.listdir(d)):
            if f.endswith((".py", ".sh")):
                if listing:
                    print(f"tool: {f}")
                if f not in alltext and f not in ALLOW:
                    missing.append(f"tool: {os.path.relpath(os.path.join(d, f), REPO)}")

    # the allow-list itself: an entry the manual mentions now is stale
    for n in sorted(ALLOW):
        nn = n.split(" ", 1)[-1]
        if nn in words or nn in optwords:
            missing.append(f"allow-list entry {n!r} is documented now: remove it")

    for m in missing:
        print("UNDOCUMENTED  " + m)
    for f in fails:
        print("ERROR  " + f)
    n = sum(len(v) for v in checked.values())
    print(f"DOC CHECK: {n} names, {len(missing)} undocumented, {len(fails)} errors: " +
          ("PASSED" if not missing and not fails else "FAILED"))
    return 1 if missing or fails else 0


if __name__ == "__main__":
    sys.exit(main())
