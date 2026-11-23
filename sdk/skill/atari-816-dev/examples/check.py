#!/usr/bin/env python3
"""check.py - the agent skill's self-test (make -C sdk/c test runs it).

    python3 sdk/skill/atari-816-dev/examples/check.py [--horizon DIR] [--no-run]

1. Each example (console, window, game) is built and run with its own `make test`
   (sdk/c/c.mk: the emulator, its input script, the --expect lines, the file check).
2. The skill's text (SKILL.md, references/*.md) is checked against the SDK:
   - every C name it mentions (hz_*, hg_*, ui_*, HZ_*, HG_*, UI_*) is in a header of
     sdk/c/include (or, for assembly names, in horizon/user/*.inc);
   - every option it gives to hcc or run816.py is one the tool's help lists;
   - every repository path it names (sdk/..., ports/..., horizon/..., emu/...,
     references/..., examples/...) exists.
Prints PASS / FAIL lines; exit 1 when anything failed. --no-run: only part 2.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SDK = os.path.dirname(os.path.dirname(SKILL))
REPO = os.path.dirname(SDK)
EXAMPLES = ("console", "window", "game")

fails = 0


def report(ok, what):
    global fails
    print(("PASS  " if ok else "FAIL  ") + what, flush=True)
    if not ok:
        fails += 1


def run_examples(horizon):
    for ex in EXAMPLES:
        d = os.path.join(HERE, ex)
        subprocess.run(["make", "--no-print-directory", "-C", d, "clean"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        r = subprocess.run(["make", "--no-print-directory", "-C", d, "test",
                            "HORIZON=" + horizon], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        out = r.stdout.decode("latin-1")
        report(r.returncode == 0, f"example {ex}: make test" +
               ("" if r.returncode == 0 else "\n" + out[-1500:]))


def skill_texts():
    files = [os.path.join(SKILL, "SKILL.md")]
    rd = os.path.join(SKILL, "references")
    files += sorted(os.path.join(rd, f) for f in os.listdir(rd) if f.endswith(".md"))
    return {f: open(f, encoding="utf-8").read() for f in files}


def known_names():
    names = set()
    for d, exts in ((os.path.join(SDK, "c", "include"), (".h",)),
                    (os.path.join(SDK, "c", "cc816", "include"), (".h",)),
                    (os.path.join(REPO, "horizon", "user"), (".inc",))):
        for f in os.listdir(d):
            if f.endswith(exts):
                names |= set(re.findall(r"\b\w+\b", open(os.path.join(d, f),
                                                           encoding="latin-1").read()))
    # the ports' platform layers (porting.md names their files and functions), the
    # environment variables hcc's help lists
    for port in os.listdir(os.path.join(REPO, "ports")):
        for root, _, files in os.walk(os.path.join(REPO, "ports", port)):
            for f in files:
                if f.endswith((".c", ".h", ".s")):
                    names.add(os.path.splitext(f)[0])
                    names |= set(re.findall(r"\b\w+\b", open(os.path.join(root, f),
                                                               encoding="latin-1").read()))
    names |= set(re.findall(r"\$(HZ_\w+)", open(os.path.join(SDK, "c", "bin", "hcc")).read()))
    names.add("hz_NAME")                # (hz_NAME: the pattern of the syscall functions)
    return names


def tool_options(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return set(re.findall(r"(?<![\w-])(--?[a-zA-Z][\w-]*)", r.stdout.decode("latin-1"))) | \
        {"-h", "--help"}


def code_spans(text):
    """the text of inline code and code blocks"""
    out = re.findall(r"```[^\n]*\n(.*?)```", text, re.S)
    rest = re.sub(r"```.*?```", "", text, flags=re.S)
    out += re.findall(r"`([^`\n]+)`", rest)
    return out


def check_text():
    texts = skill_texts()
    names = known_names()
    hcc = tool_options([sys.executable, os.path.join(SDK, "c", "bin", "hcc"), "-h"])
    run816 = tool_options([sys.executable, os.path.join(SDK, "tools", "run816.py"), "-h"])
    for path, text in texts.items():
        rel = os.path.relpath(path, SKILL)
        bad = []
        # C (and assembly) names of the SDK
        for n in sorted(set(re.findall(r"\b(?:hz|hg|ui|HZ|HG|UI)_\w+", text))):
            if n not in names and not n.endswith("_"):
                bad.append(f"name {n}")
        # tool options, on the lines that call the tool
        for span in code_spans(text):
            for line in span.splitlines():
                for tool, opts in (("hcc", hcc), ("run816.py", run816)):
                    m = re.search(r"\b" + re.escape(tool) + r"\b(.*)", line)
                    if not m:
                        continue
                    args = re.sub(r"'[^']*'|\"[^\"]*\"", "", m.group(1))
                    for o in re.findall(r"(?<![\w/.=-])(--[a-z][\w-]*)", args):
                        if o not in opts:
                            bad.append(f"{tool} option {o}")
        # paths
        for p in sorted(set(re.findall(
                r"(?<![\w./-])((?:sdk|ports|horizon|emu|references|examples)/[\w./-]*\w)",
                text))):
            base = SKILL if p.startswith(("references/", "examples/")) else REPO
            if not glob_ok(base, p) and not glob_ok(os.path.join(REPO, "ports"), "*/" + p):
                bad.append(f"path {p}")
        report(not bad, f"{rel}: names, options and paths" +
               ("" if not bad else ": not found: " + ", ".join(sorted(set(bad)))))


def glob_ok(base, p):
    import glob
    return bool(glob.glob(os.path.join(base, p)))


def main():
    a = sys.argv[1:]
    horizon = os.environ.get("HORIZON") or os.path.join(REPO, "horizon")
    run = True
    i = 0
    while i < len(a):
        if a[i] == "--horizon" and i + 1 < len(a):
            horizon = a[i + 1]
            i += 2
        elif a[i] == "--no-run":
            run = False
            i += 1
        else:
            sys.exit(__doc__)
    if run:
        run_examples(os.path.abspath(horizon))
    check_text()
    print("SKILL CHECK " + ("PASSED" if not fails else f"FAILED ({fails})"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
