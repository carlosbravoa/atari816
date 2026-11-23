#!/usr/bin/env python3
"""genfuzz.py - random self-checking C programs for cc816, checked against the host gcc.

    genfuzz.py OUTDIR COUNT [SEED] [--features all|basic|LIST]

--features: a comma-separated list of the shapes of genfeat.py (basic struct bitfield fptr
vararg far switch spill ptr globals); all (the default) puts the original functions and 2-4
of the others in each program; basic alone writes the same programs as before (the same seeds).

Each program has a few functions over int8/uint8/int16/uint16/int32/uint32 values:
arithmetic, logic, shifts, division, compares, conditionals, casts, local and global
arrays, a packed structure, address-taken locals, pointers, loops with induction
variables, switch, a recursive helper. Every operation is written with explicit casts
through macros, so that one source has the same meaning with a 16-bit int (the target)
and a 32-bit int (the host):

    target: OP_T(a, b) = (T)((T)(a) op (T)(b))
    host:   OP_T(a, b) = (T)((W)(T)(a) op (W)(T)(b))      W = int64_t / uint64_t

The host build (gcc -fwrapv) prints each function's checksum; the target program gets
those values built in and returns 0 when all match (else the number of the first
function that differs, and prints the two values).
"""
import os
import random
import subprocess
import sys

TYPES = {'i8': ('int8_t', 8, True), 'u8': ('uint8_t', 8, False), 'i16': ('int16_t', 16, True),
         'u16': ('uint16_t', 16, False), 'i32': ('int32_t', 32, True), 'u32': ('uint32_t', 32, False)}
OPS = {'add': '+', 'sub': '-', 'mul': '*', 'and': '&', 'or': '|', 'xor': '^'}
CMPS = {'lt': '<', 'le': '<=', 'gt': '>', 'ge': '>=', 'eq': '==', 'ne': '!='}


def header(host):
    out = ['#include <stdint.h>', '#include <stdio.h>']
    for t, (ct, bits, signed) in TYPES.items():
        W = 'int64_t' if signed else 'uint64_t'
        for op, sym in OPS.items():
            if host:
                out.append(f'#define {op.upper()}_{t}(a, b) (({ct})(({W})({ct})(a) {sym} ({W})({ct})(b)))')
            else:
                out.append(f'#define {op.upper()}_{t}(a, b) (({ct})(({ct})(a) {sym} ({ct})(b)))')
        for op, sym in CMPS.items():
            if host:
                out.append(f'#define {op.upper()}_{t}(a, b) ((int16_t)(({W})({ct})(a) {sym} ({W})({ct})(b)))')
            else:
                out.append(f'#define {op.upper()}_{t}(a, b) ((int16_t)(({ct})(a) {sym} ({ct})(b)))')
        m = bits - 1
        if host:
            out.append(f'#define SHL_{t}(a, n) (({ct})(({W})({ct})(a) << ((n) & {m})))')
            out.append(f'#define SHR_{t}(a, n) (({ct})(({W})({ct})(a) >> ((n) & {m})))')
            out.append(f'#define NEG_{t}(a) (({ct})(-({W})({ct})(a)))')
            out.append(f'#define COM_{t}(a) (({ct})(~({W})({ct})(a)))')
        else:
            out.append(f'#define SHL_{t}(a, n) (({ct})(({ct})(a) << ((n) & {m})))')
            out.append(f'#define SHR_{t}(a, n) (({ct})(({ct})(a) >> ((n) & {m})))')
            out.append(f'#define NEG_{t}(a) (({ct})(-({ct})(a)))')
            out.append(f'#define COM_{t}(a) (({ct})(~({ct})(a)))')
        # division by a function (the divisor is evaluated once): no /0, no MIN / -1
        if host:
            out.append(f'static {ct} div_{t}({ct} a, {ct} b) {{ if (b == 0{" || b == -1" if signed else ""}) b = 7; '
                       f'return ({ct})(({W})a / ({W})b); }}')
            out.append(f'static {ct} mod_{t}({ct} a, {ct} b) {{ if (b == 0{" || b == -1" if signed else ""}) b = 7; '
                       f'return ({ct})(({W})a % ({W})b); }}')
        else:
            out.append(f'static {ct} div_{t}({ct} a, {ct} b) {{ if (b == 0{" || b == -1" if signed else ""}) b = 7; '
                       f'return ({ct})(a / b); }}')
            out.append(f'static {ct} mod_{t}({ct} a, {ct} b) {{ if (b == 0{" || b == -1" if signed else ""}) b = 7; '
                       f'return ({ct})(a % b); }}')
    # (p[WIX(u)]: an unsigned index meant as a negative one: wraps through a near pointer;
    # the host's and the far data model's pointers do not wrap)
    out.append('#define WIX(u) ((int16_t)(u))' if host else
               '#ifdef __CC816_FAR_DATA__\n#define WIX(u) ((int16_t)(u))\n#else\n#define WIX(u) (u)\n#endif')
    out.append('static uint32_t H;')
    out.append('static void mix(uint32_t v) { H = (uint32_t)(H * 31u + v); H ^= H >> 7; }')
    return '\n'.join(out)


class Gen:
    def __init__(self, rnd):
        self.r = rnd

    def const(self, t):
        ct, bits, signed = TYPES[t]
        r = self.r.random()
        if r < 0.3:
            v = self.r.choice([0, 1, 2, 3, 7, 8, 15, 16, 31, 100, 127, 128, 255, 256, 1000])
        elif r < 0.5:
            v = (1 << bits) - self.r.choice([1, 2, 128, 256])
        else:
            v = self.r.getrandbits(bits)
        v &= (1 << bits) - 1
        if signed and v >> (bits - 1):
            v -= 1 << bits
        if bits == 32:
            if signed and v == -(1 << 31):
                return f'(({ct})-2147483647L - 1)'
            return f'(({ct}){v}{"L" if signed else "UL"})'
        return f'(({ct}){v})'

    def leaf(self, t, vars_):
        r = self.r.random()
        cands = [n for n, vt in vars_ if vt == t]
        if r < 0.25 or not vars_:
            return self.const(t)
        if r < 0.7 and cands:
            return self.r.choice(cands)
        n, vt = self.r.choice(vars_)
        return f'(({TYPES[t][0]}){n})'

    def expr(self, t, vars_, d):
        if d <= 0 or self.r.random() < 0.2:
            return self.leaf(t, vars_)
        k = self.r.random()
        if k < 0.45:
            op = self.r.choice(list(OPS))
            return f'{op.upper()}_{t}({self.expr(t, vars_, d - 1)}, {self.expr(t, vars_, d - 1)})'
        if k < 0.55:
            op = self.r.choice(['SHL', 'SHR'])
            return f'{op}_{t}({self.expr(t, vars_, d - 1)}, {self.expr("u8", vars_, d - 2)})'
        if k < 0.62:
            op = self.r.choice(['div', 'mod'])
            return f'{op}_{t}({self.expr(t, vars_, d - 1)}, {self.expr(t, vars_, d - 1)})'
        if k < 0.72:
            ct = self.r.choice(list(TYPES))
            op = self.r.choice(list(CMPS))
            return f'(({TYPES[t][0]}){op.upper()}_{ct}({self.expr(ct, vars_, d - 1)}, {self.expr(ct, vars_, d - 1)}))'
        if k < 0.78:
            return f'{self.r.choice(["NEG", "COM"])}_{t}({self.expr(t, vars_, d - 1)})'
        if k < 0.86:
            ct = self.r.choice(list(TYPES))
            c = self.cond(vars_, d - 1)
            return f'({c} ? {self.expr(t, vars_, d - 1)} : {self.expr(t, vars_, d - 1)})'
        ct = self.r.choice(list(TYPES))
        return f'(({TYPES[t][0]}){self.expr(ct, vars_, d - 1)})'

    def cond(self, vars_, d):
        ct = self.r.choice(list(TYPES))
        op = self.r.choice(list(CMPS))
        c = f'{op.upper()}_{ct}({self.expr(ct, vars_, d)}, {self.expr(ct, vars_, d)})'
        r = self.r.random()
        if r < 0.15 and d > 0:
            c = f'({c} && {self.cond(vars_, d - 1)})'
        elif r < 0.3 and d > 0:
            c = f'({c} || {self.cond(vars_, d - 1)})'
        elif r < 0.4:
            c = f'!{c}'
        return c

    def func(self, idx):
        r = self.r
        L = []
        nv = r.randint(3, 7)
        vars_ = []
        L.append(f'static uint32_t f{idx}(void)')
        L.append('{')
        L.append('    int16_t i, j;')
        for k in range(nv):
            t = r.choice(list(TYPES))
            vars_.append((f'v{k}', t))
            L.append(f'    {TYPES[t][0]} v{k} = {self.const(t)};')
        at = r.choice(list(TYPES))
        L.append(f'    {TYPES[at][0]} la[8];')
        taken = r.choice(vars_)
        L.append(f'    {TYPES[taken[1]][0]} *pv = &{taken[0]};')
        L.append('    struct S *ps = &gs[1];')
        L.append('    H = 0;')
        L.append('    for (i = 0; i < 8; i++)')
        L.append(f'        la[i] = ({TYPES[at][0]}){self.expr(at, vars_ + [("i", "i16")], 2)};')
        for _ in range(r.randint(4, 9)):
            k = r.random()
            n, t = r.choice(vars_)
            if k < 0.35:
                L.append(f'    {n} = {self.expr(t, vars_, 4)};')
            elif k < 0.45:
                L.append(f'    if ({self.cond(vars_, 2)}) {n} = {self.expr(t, vars_, 3)}; '
                         f'else {n} = {self.expr(t, vars_, 2)};')
            elif k < 0.55:
                st = r.choice(['i8', 'u8', 'i16', 'u16', 'i32', 'u32'])
                fld = {'i8': 'a', 'u8': 'b', 'i16': 'c', 'u16': 'd', 'i32': 'e', 'u32': 'f'}[st]
                L.append(f'    ps->{fld} = {self.expr(st, vars_, 3)};')
                L.append(f'    {n} = ({TYPES[t][0]})ADD_{st}(gs[1].{fld}, ps[-1].{fld});')
            elif k < 0.65:
                g = r.choice(list(TYPES))
                L.append(f'    for (i = 0; i < 10; i++) {{ ga_{g}[i * 3 + 1] = {self.expr(g, vars_ + [("i", "i16")], 2)}; '
                         f'{n} = ({TYPES[t][0]})ADD_{g}({n}, ga_{g}[i * 3]); }}')
            elif k < 0.72:
                L.append(f'    for (j = 0; j < 8; j++) {{ if (EQ_{at}(la[j], 0)) continue; '
                         f'{n} = ({TYPES[t][0]})XOR_{at}({n}, la[j]); if (GT_i16(j, 5)) break; }}')
            elif k < 0.79:
                L.append(f'    *pv = {self.expr(taken[1], vars_, 3)};')
                L.append(f'    {n} = ({TYPES[t][0]})ADD_{taken[1]}(*pv, {taken[0]});')
            elif k < 0.86:
                cs = sorted(set(r.randint(0, 12) for _ in range(r.randint(2, 7))))
                L.append(f'    switch (({TYPES["u8"][0]})({self.expr("u8", vars_, 2)}) % 13) {{')
                for c in cs:
                    L.append(f'    case {c}: {n} = {self.expr(t, vars_, 2)};' + (' break;' if r.random() < 0.7 else ''))
                L.append(f'    default: {n} = COM_{t}({n});')
                L.append('    }')
            elif k < 0.92:
                L.append(f'    {n} = ({TYPES[t][0]})rec({self.expr("u8", vars_, 2)} & 7, {self.expr("i16", vars_, 2)});')
            else:
                L.append(f'    while (NE_{t}({n}, 0) && GT_i16(i, 0)) {{ {n} = SHR_{t}({n}, 1); i--; }}')
        for n, t in vars_:
            L.append(f'    mix((uint32_t){n});')
        L.append('    for (i = 0; i < 8; i++) mix((uint32_t)la[i]);')
        L.append('    return H;')
        L.append('}')
        return '\n'.join(L)

    def program(self, nf):
        r = self.r
        G = []
        G.append('struct S { int8_t a; uint8_t b; int16_t c; uint16_t d; int32_t e; uint32_t f; };')
        G.append('static struct S gs[3] = { {1, 2, 3, 4, 5, 6}, {-1, 200, -300, 40000u, -70000L, 3000000000UL}, {0} };')
        for t, (ct, bits, signed) in TYPES.items():
            vals = ', '.join(self.const(t) for _ in range(31))
            G.append(f'static {ct} ga_{t}[31] = {{ {vals} }};')
        G.append('static int16_t rec(uint16_t n, int16_t x) { if (n == 0) return x; '
                 'return (int16_t)ADD_i16(rec(n - 1, (int16_t)XOR_i16(x, n)), MUL_i16(n, 3)); }')
        F = [self.func(k) for k in range(nf)]
        return '\n'.join(G), F


def main():
    args = sys.argv[1:]
    feats = 'all'
    if '--features' in args:
        i = args.index('--features')
        feats = args[i + 1]
        del args[i:i + 2]
    if len(args) < 2:
        sys.exit(__doc__)
    import genfeat
    feats = genfeat.FEATURES if feats == 'all' else feats.split(',')
    for f in feats:
        if f not in genfeat.FEATURES + genfeat.EXTRA_FEATURES:
            sys.exit(f'unknown feature {f}: {", ".join(genfeat.FEATURES + genfeat.EXTRA_FEATURES)}')
    out, count = args[0], int(args[1])
    seed = int(args[2]) if len(args) > 2 else 1
    os.makedirs(out, exist_ok=True)
    host_dir = os.path.join(out, 'host')
    os.makedirs(host_dir, exist_ok=True)
    made = 0
    for n in range(count):
        rnd = random.Random(seed * 100003 + n)
        if feats == ['basic']:
            # the original shape (the same programs as before --features)
            g = Gen(rnd)
            nf = rnd.randint(3, 6)
            glob, funcs = g.program(nf)
            pick, far = [], False
        else:
            g = genfeat.FGen(rnd)
            glob, funcs, pick = g.program_feats(feats)
            nf = len(funcs)
            far = g.uses_far
        body = glob + '\n' + '\n'.join(funcs)
        hpre = '#include <stdarg.h>\n#include <string.h>\n#include <stddef.h>\n#define __far\n' \
            'static unsigned char hz_fbuf[65536];\nstatic void *hz_far_alloc(void) { return hz_fbuf; }\n' \
            'static void hz_far_free(void *p) { (void)p; }\n' \
            '#define PACKED __attribute__((packed))\n' \
            'typedef float dbl;\n'
        tpre = '#include <stdarg.h>\n#include <string.h>\n' + ('#include <horizon.h>\n' if far else '') + \
            '#define PACKED\ntypedef double dbl;\n'
        tag = f'/* genfuzz seed {seed} program {n}: {",".join(pick) or "basic"} */\n'
        hsrc = tag + hpre + header(True) + '\n' + body + '\nint main(void) {\n' + \
            ''.join(f'    printf("%lu\\n", (unsigned long)f{k}());\n' for k in range(nf)) + '    return 0;\n}\n'
        hc = os.path.join(host_dir, f'h{n:04d}.c')
        open(hc, 'w').write(hsrc)
        exe = os.path.join(host_dir, f'h{n:04d}')
        r = subprocess.run(['gcc', '-O1', '-fwrapv', '-fno-strict-aliasing', '-w', '-msse2',
                            '-mfpmath=sse', '-ffp-contract=off', '-o', exe, hc],
                           capture_output=True, text=True)
        if r.returncode:
            print(f'host compile failed for {n}: {r.stderr[:300]}', file=sys.stderr)
            continue
        hr = subprocess.run([exe], capture_output=True, text=True)
        vals = hr.stdout.split()
        if hr.returncode or len(vals) != nf:
            print(f'host run failed for {n}: exit {hr.returncode}', file=sys.stderr)
            continue
        tmain = ['int main(void)', '{', '    uint32_t got;']
        for k, v in enumerate(vals):
            tmain.append(f'    got = f{k}();')
            tmain.append(f'    if (got != {v}UL) {{ printf("f{k}: %lu, want {v}\\n", (unsigned long)got); return {k + 1}; }}')
        tmain += ['    return 0;', '}']
        tsrc = tag + tpre + header(False) + '\n' + body + '\n' + '\n'.join(tmain) + '\n'
        open(os.path.join(out, f'fz{n:04d}.c'), 'w').write(tsrc)
        made += 1
    print(f'{made} programs in {out}')


if __name__ == '__main__':
    main()
