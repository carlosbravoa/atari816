#!/usr/bin/env python3
"""abicheck.py - check the SDK reference against the Horizon sources.

    abicheck.py [--horizon DIR] [--ref DIR] [--list]

Reads
  HORIZON/user/horizon.inc   the SYS_* numbers and the other constants (WD_*, WE_*, ...)
  HORIZON/user/ui.inc        the controls library's constants (UT_*, UA_*, CT_*, ...)
  HORIZON/kernel/syscall.s   the kernel's syscall table (which numbers are implemented)
  HORIZON/kernel/k2.s        (0.18) k2_tab: the syscalls from $91 on (syscall.s sends them there)
  HORIZON/ABI.md             the syscall table of the ABI document
  REF/*.md                   the SDK reference (default: sdk/docs/reference)
  the skill's references     sdk/skill/atari-816-dev/references/*.md ("| $NN | SYS_X |")

and fails (exit 1) when
  - a SYS_* constant of horizon.inc is not documented in the reference with that number;
  - a syscall heading in the reference ("### $NN name (SYS_NAME)") has a number the
    kernel does not implement, or names a SYS_ constant with another number;
  - a syscall the kernel implements is not in the reference;
  - a constant table row in the reference ("| `NAME` | value |" with NAME defined in
    horizon.inc or ui.inc) has another value than the include file.
Differences between ABI.md and the kernel are printed as notes (not failures: ABI.md
belongs to the kernel owners).
--list prints the syscall table (number, name, constant, implemented) and exits.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def num(s):
    s = s.strip()
    if s.startswith('$'):
        return int(s[1:], 16)
    if s.lower().startswith('0x'):
        return int(s, 16)
    return int(s)


def inc_constants(path):
    """NAME = value lines whose value is a plain number (or a sum of earlier ones)."""
    out = {}
    for ln in open(path, encoding='latin-1'):
        m = re.match(r'\s*([A-Z][A-Z0-9_]*)\s*=\s*([^;]+)', ln)
        if not m:
            continue
        name, expr = m.group(1), m.group(2).strip()
        expr2 = re.sub(r'\$([0-9A-Fa-f]+)', lambda x: str(int(x.group(1), 16)), expr)
        expr2 = re.sub(r'\b([A-Z][A-Z0-9_]*)\b',
                       lambda x: str(out[x.group(1)]) if x.group(1) in out else x.group(0), expr2)
        if re.fullmatch(r'[0-9+\-*()<| ]+', expr2):
            try:
                out[name] = eval(expr2)
            except Exception:
                pass
    return out


def kernel_table(path):
    txt = open(path, encoding='latin-1').read()
    start = txt.index('sys_tab:')
    end = start + re.search(r'^NSYS\s*=', txt[start:], flags=re.M).start()
    # (0.18) the table ends with ".repeat K2_NSYS - $91 / .word .loword(sys_k2)": those
    # numbers are dispatched by k2_tab in kernel/k2.s (the second code segment)
    # (BASIC 2.0: entries may follow it, from K2_NSYS on: the block stands for its numbers)
    k2n = 0x91
    kdefs = os.path.join(os.path.dirname(path), 'kdefs.inc')
    if os.path.exists(kdefs):
        m = re.search(r'^K2_NSYS\s*=\s*\$([0-9A-Fa-f]+)', open(kdefs, encoding='latin-1').read(), flags=re.M)
        if m:
            k2n = int(m.group(1), 16)
    body = re.sub(r'\.repeat\s+K2_NSYS\b.*?\.endrepeat', ' .loword(sys_k2)' * (k2n - 0x91),
                  txt[start:end], flags=re.S)
    names = re.findall(r'\.loword\((sys_\w+)\)', body)
    out = {i: n for i, n in enumerate(names) if n not in ('sys_nosys', 'sys_k2')}
    out.update(k2_table(os.path.dirname(path)))
    return out


def k2_table(kdir):
    """kernel/k2.s's k2_tab: "k2_tab: .addr k2_a, k2_b ..." from syscall $91 on."""
    path = os.path.join(kdir, 'k2.s')
    if not os.path.exists(path):
        return {}
    txt = open(path, encoding='latin-1').read()
    m = re.search(r'^k2_tab:(.*?)^\s*\.assert', txt, flags=re.S | re.M)
    if not m:
        return {}
    first = int(re.search(r'k2_tab\s*-\s*\$([0-9A-Fa-f]+)', txt).group(1), 16)
    rows = re.findall(r'\.addr\s+([^;\n]*)', m.group(1))
    names = [n.strip() for r in rows for n in r.split(',') if n.strip()]
    return {first + i: n for i, n in enumerate(names)}


def abi_table(path):
    out = {}
    for ln in open(path, encoding='utf-8'):
        m = re.match(r'\|\s*\$([0-9A-Fa-f]{2})\s*\|\s*([a-z_0-9]+)\s*\|', ln)
        if m:
            out[int(m.group(1), 16)] = m.group(2)
    return out


def ref_entries(refdir):
    heads, rows = [], []
    for f in sorted(glob.glob(os.path.join(refdir, '*.md'))):
        for no, ln in enumerate(open(f, encoding='utf-8'), 1):
            m = re.match(r'#{2,4}\s+\$([0-9A-Fa-f]{2})\s+([a-z_0-9]+)\s+\((SYS_\w+|no constant)\)', ln)
            if m:
                heads.append((os.path.basename(f), no, int(m.group(1), 16), m.group(2), m.group(3)))
            m = re.match(r'\|\s*\$([0-9A-Fa-f]{2})\s*\|\s*([a-z_0-9]+)\s*\|\s*(SYS_\w+|\(none\))\s*\|', ln)
            if m:
                heads.append((os.path.basename(f), no, int(m.group(1), 16), m.group(2),
                              'no constant' if m.group(3) == '(none)' else m.group(3)))
            m = re.match(r'\|\s*`([A-Z][A-Z0-9_]*)`\s*\|\s*(\$[0-9A-Fa-f]+|\d+)\s*\|', ln)
            if m:
                rows.append((os.path.basename(f), no, m.group(1), num(m.group(2))))
    return heads, rows


def main():
    a = sys.argv[1:]
    hz = os.environ.get('HORIZON') or os.path.join(HERE, '..', '..', 'horizon')
    ref = os.path.join(HERE, '..', 'docs', 'reference')
    skill = os.path.join(HERE, '..', 'skill', 'atari-816-dev', 'references')
    lst = False
    i = 0
    while i < len(a):
        if a[i] == '--horizon': hz = a[i + 1]; i += 2
        elif a[i] == '--ref': ref = a[i + 1]; i += 2
        elif a[i] == '--list': lst = True; i += 1
        elif a[i] in ('-h', '--help'): print(__doc__); return 0
        else: sys.exit(f'abicheck: unknown argument {a[i]}')
    inc = inc_constants(os.path.join(hz, 'user', 'horizon.inc'))
    uic = inc_constants(os.path.join(hz, 'user', 'ui.inc'))
    sysc = {v: k for k, v in inc.items() if k.startswith('SYS_')}
    sysn = {k: v for k, v in inc.items() if k.startswith('SYS_')}
    kern = kernel_table(os.path.join(hz, 'kernel', 'syscall.s'))
    abi = abi_table(os.path.join(hz, 'ABI.md'))

    if lst:
        print(f'{"#":4} {"ABI.md name":14} {"constant":16} kernel handler')
        for n in sorted(set(kern) | set(sysc) | set(abi)):
            print(f'${n:02X}  {abi.get(n, "-"):14} {sysc.get(n, "-"):16} {kern.get(n, "(not implemented)")}')
        return 0

    fails, notes = [], []
    heads, rows = ref_entries(ref)
    documented = {}
    for f, no, n, name, const in heads:
        documented.setdefault(n, []).append((f, no, name, const))
        if n not in kern:
            fails.append(f'{f}:{no}: ${n:02X} {name}: the kernel has no syscall ${n:02X}')
        elif n in abi and abi[n] != name:
            fails.append(f'{f}:{no}: ${n:02X} is called {abi[n]} in ABI.md, not {name}')
        if const != 'no constant':
            if const not in sysn:
                fails.append(f'{f}:{no}: {const} is not in horizon.inc')
            elif sysn[const] != n:
                fails.append(f'{f}:{no}: {const} is ${sysn[const]:02X} in horizon.inc, not ${n:02X}')
        elif n in sysc:
            fails.append(f'{f}:{no}: ${n:02X} has the constant {sysc[n]} in horizon.inc')
    for c, n in sorted(sysn.items(), key=lambda x: x[1]):
        if not any(e[3] == c for e in documented.get(n, [])):
            fails.append(f'horizon.inc: {c} = ${n:02X} is not documented in the reference')
    for n, h in sorted(kern.items()):
        if n not in documented:
            fails.append(f'kernel: syscall ${n:02X} ({h}) is not documented in the reference')
    # the skill's cheat sheet: | $NN | SYS_NAME | rows
    for f in sorted(glob.glob(os.path.join(skill, '*.md'))):
        for no, ln in enumerate(open(f, encoding='utf-8'), 1):
            m = re.match(r'\|\s*\$([0-9A-Fa-f]{2})\s*\|\s*(SYS_\w+)\s*\|', ln)
            if m:
                n, c = int(m.group(1), 16), m.group(2)
                if sysn.get(c) != n:
                    fails.append(f'skill {os.path.basename(f)}:{no}: {c} is not ${n:02X} in horizon.inc')
    for f, no, name, v in rows:
        src = inc if name in inc else uic if name in uic else None
        if src is None:
            continue
        if src[name] != v:
            fails.append(f'{f}:{no}: {name} = {v} here, {src[name]} in the include file')
    # ABI.md against the kernel (notes)
    for n in sorted(set(kern) | set(abi)):
        if n in kern and n not in abi:
            notes.append(f'ABI.md: syscall ${n:02X} ({kern[n]}) is implemented but not in the table')
        if n in abi and n not in kern:
            notes.append(f'ABI.md: ${n:02X} {abi[n]} is in the table but not implemented')
    for n in sorted(kern):
        if n not in sysc:
            notes.append(f'horizon.inc: no SYS_ constant for ${n:02X} ({abi.get(n, kern[n])})')

    for x in notes:
        print('note:', x)
    for x in fails:
        print('FAIL:', x)
    print(f'abicheck: {len(heads)} syscalls documented, {len(rows)} constants checked, '
          f'{len(kern)} implemented by the kernel, {len(sysn)} SYS_ constants: '
          + ('FAILED' if fails else 'OK'))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
