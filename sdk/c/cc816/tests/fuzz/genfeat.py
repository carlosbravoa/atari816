"""genfeat.py - the feature shapes of genfuzz.py (genfuzz.py ... --features LIST).

Each feature writes one more checksum function fN (static uint32_t fN(void): H = 0, ...,
mix(...), return H) and the globals and helpers it needs, named F<N>_... so that several
features live in one program. The same rules as genfuzz.py: every operation's meaning is
the same with a 16-bit int (cc816) and a 32-bit int (gcc): explicit casts and the width
macros, only operations whose low bits do not depend on the promoted width (+ - * & | ^ <<)
in compound assignments of mixed types, division only through div_T/mod_T or by 1..8 in the
same type, no structure layout in the checksums.

    basic     genfuzz.py's original functions
    struct    structure copies, nested members, by value to and from functions
    bitfield  bit-fields of every width in unsigned char / int / long units
    fptr      function pointers: tables, arguments, results, in structures
    vararg    variadic functions with va_arg of int / long / pointer, vsprintf / vsnprintf
    far       __far pointers into a bank of hz_far_alloc and to near objects
    switch    dense, sparse, signed, long, nested switches, fall-through, default anywhere
    spill     3-4 deep loops with 15-30 live locals of mixed widths, deep expressions
    ptr       ++/-- of every width through pointers, pointer differences and compares,
              ?: with side effects, comma, recursion, big locals, static locals
    globals   initialised globals of every type, arrays of structures with pointers
    float     (not in "all": --features basic,float) float and double (dbl: double on the
              target, float in the host build: cc816's double is a float) arithmetic,
              compares, conversions both ways (guarded: no out-of-range conversion),
              ++/--, compound assignments, float arrays, structures, globals with
              initialisers, pointers, parameters and results, variadic doubles,
              sprintf %f %e %g; checked bit for bit (NaNs as one) against gcc's SSE
              single precision
"""
from genfuzz import TYPES, OPS, CMPS, Gen

FEATURES = ['basic', 'struct', 'bitfield', 'fptr', 'vararg', 'far', 'switch', 'spill', 'ptr',
            'globals']
EXTRA_FEATURES = ['float']          # chosen by name only (all keeps its old programs)
AVOID_KNOWN = False     # True: leave out the shapes of the compiler bugs in regress/ (while they are open)
LOWOPS = ['add', 'sub', 'mul', 'and', 'or', 'xor']      # low bits independent of the width
CSYM = {'add': '+', 'sub': '-', 'mul': '*', 'and': '&', 'or': '|', 'xor': '^'}


def tn(t):
    return TYPES[t][0]


def nbits(t):
    return TYPES[t][1]


def issigned(t):
    return TYPES[t][2]


def tsize(t):
    return TYPES[t][1] // 8


def trange(t):
    b = nbits(t)
    return (-(1 << (b - 1)), (1 << (b - 1)) - 1) if issigned(t) else (0, (1 << b) - 1)


def wrap(t, v):
    b = nbits(t)
    v &= (1 << b) - 1
    if issigned(t) and v >> (b - 1):
        v -= 1 << b
    return v


def lit(t, v):
    v = wrap(t, v)
    if nbits(t) == 32:
        if issigned(t):
            return '(-2147483647L - 1)' if v == -(1 << 31) else f'{v}L'
        return f'{v}UL'
    return str(v)


class FGen(Gen):
    def __init__(self, rnd):
        super().__init__(rnd)
        self.G = []          # globals and helpers
        self.uses_far = False

    # ------------------------------------------------------------------ helpers
    def rval(self, t):
        b = nbits(t)
        x = self.r.random()
        if x < 0.3:
            v = self.r.choice([0, 1, 2, 3, 7, 8, 15, 16, 31, 100, 127, 128, 255, 256, 1000])
        elif x < 0.5:
            v = (1 << b) - self.r.choice([1, 2, 128, 256])
        else:
            v = self.r.getrandbits(b)
        return wrap(t, v)

    def scalars(self, L, n, start=0):
        vs = []
        for k in range(start, start + n):
            t = self.r.choice(list(TYPES))
            vs.append((f'v{k}', t))
            L.append(f'    {tn(t)} v{k} = {self.const(t)};')
        return vs

    def assign(self, n, t, vars_, d=3):
        return f'    {n} = {self.expr(t, vars_, d)};'

    def head(self, idx):
        return [f'static uint32_t f{idx}(void)', '{', '    int16_t i, j;']

    def tail(self, L, vars_):
        for n, t in vars_:
            L.append(f'    mix((uint32_t){n});')
        L.append('    return H;')
        L.append('}')
        return '\n'.join(L)

    # ------------------------------------------------------------------ basic globals
    def base_globals(self):
        G = []
        G.append('struct S { int8_t a; uint8_t b; int16_t c; uint16_t d; int32_t e; uint32_t f; };')
        G.append('static struct S gs[3] = { {1, 2, 3, 4, 5, 6}, {-1, 200, -300, 40000u, -70000L, 3000000000UL}, {0} };')
        for t, (ct, bits, signed) in TYPES.items():
            vals = ', '.join(self.const(t) for _ in range(31))
            G.append(f'static {ct} ga_{t}[31] = {{ {vals} }};')
        G.append('static int16_t rec(uint16_t n, int16_t x) { if (n == 0) return x; '
                 'return (int16_t)ADD_i16(rec(n - 1, (int16_t)XOR_i16(x, n)), MUL_i16(n, 3)); }')
        return G

    # ------------------------------------------------------------------ struct
    def struct_types(self, pfx, n, maxsize=40):
        r = self.r
        ts = []
        for k in range(n):
            budget = r.choice([1, 2, 3, 4, 5, 7, 9, 11, 13, 17, 21, 24, 31, 37, 40])
            budget = min(budget, maxsize)
            fields = []
            size = 0
            while size < budget:
                rem = budget - size
                fname = f'm{len(fields)}'
                c = r.random()
                nest = [j for j, tt in enumerate(ts) if tt['size'] <= rem]
                arr = [x for x in TYPES if 2 * tsize(x) <= rem]
                if c < 0.25 and nest:
                    j = r.choice(nest)
                    fields.append(('n', fname, j))
                    size += ts[j]['size']
                elif c < 0.45 and arr:
                    et = r.choice(arr)
                    cnt = r.randint(2, min(6, rem // tsize(et)))
                    fields.append(('a', fname, et, cnt))
                    size += tsize(et) * cnt
                else:
                    t = r.choice([x for x in TYPES if tsize(x) <= rem])
                    fields.append(('s', fname, t))
                    size += tsize(t)
            ts.append({'name': f'{pfx}S{k}', 'fields': fields, 'size': size})
        return ts

    def lvals(self, ts, ti, base, arrow=False):
        sep = '->' if arrow else '.'
        out = []
        for f in ts[ti]['fields']:
            if f[0] == 's':
                out.append((f'{base}{sep}{f[1]}', f[2]))
            elif f[0] == 'a':
                out += [(f'{base}{sep}{f[1]}[{i}]', f[2]) for i in range(f[3])]
            else:
                out += self.lvals(ts, f[2], f'{base}{sep}{f[1]}')
        return out

    def sublvals(self, ts, ti, base, arrow=False):
        sep = '->' if arrow else '.'
        out = [(f'(*{base})' if arrow else base, ti)]
        for f in ts[ti]['fields']:
            if f[0] == 'n':
                out += self.sublvals(ts, f[2], f'{base}{sep}{f[1]}')
        return out

    def sinit(self, ts, ti):
        parts = []
        for f in ts[ti]['fields']:
            if f[0] == 's':
                parts.append(lit(f[2], self.rval(f[2])))
            elif f[0] == 'a':
                parts.append('{ ' + ', '.join(lit(f[2], self.rval(f[2])) for _ in range(f[3])) + ' }')
            else:
                parts.append(self.sinit(ts, f[2]))
        return '{ ' + ', '.join(parts) + ' }'

    def struct_helpers(self, ts):
        r = self.r
        G = self.G
        for ti, st in enumerate(ts):
            nm = st['name']
            body = ' '.join(f'{tn(f[2])} {f[1]};' if f[0] == 's' else
                            f'{tn(f[2])} {f[1]}[{f[3]}];' if f[0] == 'a' else
                            f'struct {ts[f[2]]["name"]} {f[1]};' for f in st['fields'])
            G.append(f'struct {nm} {{ {body} }};')
            # sum
            S = [f'static uint32_t sum_{nm}(const struct {nm} *p)', '{', '    uint32_t h = 1;', '    uint16_t i;',
                 '    i = 0;']
            F = [f'static void fill_{nm}(struct {nm} *p, uint16_t s)', '{', '    uint16_t i;', '    i = 0;']
            for f in st['fields']:
                K = r.getrandbits(32) | 1
                C = r.getrandbits(32)
                if f[0] == 's':
                    S.append(f'    h = h * 31u + (uint32_t)p->{f[1]};')
                    F.append(f'    p->{f[1]} = ({tn(f[2])})ADD_u32(MUL_u32(s, {K}UL), {C}UL);')
                elif f[0] == 'a':
                    S.append(f'    for (i = 0; i < {f[3]}; i++) h = h * 31u + (uint32_t)p->{f[1]}[i];')
                    F.append(f'    for (i = 0; i < {f[3]}; i++) p->{f[1]}[i] = ({tn(f[2])})ADD_u32(MUL_u32(ADD_u32(s, i), {K}UL), {C}UL);')
                else:
                    S.append(f'    h = h * 31u + sum_{ts[f[2]]["name"]}(&p->{f[1]});')
                    F.append(f'    fill_{ts[f[2]]["name"]}(&p->{f[1]}, (uint16_t)ADD_u32(s, {C & 0xFFFF}u));')
            S += ['    return h;', '}']
            F += ['}']
            G.append('\n'.join(S))
            G.append('\n'.join(F))
            G.append(f'static struct {nm} mk_{nm}(uint16_t s) {{ struct {nm} t; fill_{nm}(&t, s); return t; }}')
            G.append(f'static struct {nm} (*mkp_{nm})(uint16_t) = mk_{nm};')
            n, t = r.choice(self.lvals(ts, ti, 't'))
            G.append(f'static struct {nm} id_{nm}(struct {nm} t, int16_t k) {{ {n} = ({tn(t)})ADD_{t}({n}, k); return t; }}')
            n, t = r.choice(self.lvals(ts, ti, 't'))
            G.append(f'static uint32_t bv_{nm}(struct {nm} t, int16_t k) {{ {n} = ({tn(t)})k; '
                     f'return sum_{nm}(&t) ^ (uint32_t)k; }}')

    def feat_struct(self, idx):
        r = self.r
        pfx = f'F{idx}_'
        ts = self.struct_types(pfx, r.randint(2, 4))
        self.struct_helpers(ts)
        G = self.G
        used = sorted(r.sample(range(len(ts)), min(len(ts), r.randint(1, 3))))
        if len(ts) >= 2:
            a, b = r.sample(range(len(ts)), 2)
            na, nb = ts[a]['name'], ts[b]['name']
            G.append(f'static uint32_t two_{pfx}(int8_t a, struct {na} t, int32_t b, struct {nb} u) '
                     f'{{ return sum_{na}(&t) * 3u + sum_{nb}(&u) + (uint32_t)a + (uint32_t)b; }}')
            two = (a, b)
        else:
            two = None
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(2, 4))
        sobj = {}      # type -> struct lvalues
        reads = []
        writes = []
        for ti in range(len(ts)):
            sobj[ti] = []
        for ti in used:
            nm = ts[ti]['name']
            G.append(f'static struct {nm} g{nm}[3] = {{ ' + ', '.join(self.sinit(ts, ti) for _ in range(3)) + ' };')
            L.append(f'    struct {nm} a{ti}, b{ti}, c{ti}[4];')
            L.append(f'    struct {nm} *p{ti} = &c{ti}[{r.randint(0, 3)}], *q{ti} = &g{nm}[{r.randint(0, 2)}];')
            for base, arrow in ([(f'a{ti}', False), (f'b{ti}', False), (f'p{ti}', True), (f'q{ti}', True)] +
                                [(f'c{ti}[{k}]', False) for k in range(4)] +
                                [(f'g{nm}[{k}]', False) for k in range(3)]):
                for x, tj in self.sublvals(ts, ti, base, arrow):
                    sobj[tj].append(x)
                lv = self.lvals(ts, ti, base, arrow)
                writes += lv
                reads += r.sample(lv, min(len(lv), 3))
        L.append('    H = 0;')
        for ti in used:
            nm = ts[ti]['name']
            L.append(f'    fill_{nm}(&a{ti}, {r.getrandbits(16)}u);')
            L.append(f'    fill_{nm}(&b{ti}, {r.getrandbits(16)}u);')
            L.append(f'    for (i = 0; i < 4; i++) fill_{nm}(&c{ti}[i], (uint16_t)ADD_u16(MUL_u16(i, {r.getrandbits(16)}u), {r.getrandbits(8)}));')
        allv = vars_ + reads
        types_ = [tj for tj in sobj if len(sobj[tj]) >= 2]
        for _ in range(r.randint(8, 16)):
            k = r.random()
            tj = r.choice(types_)
            nm = ts[tj]['name']
            X, Y, Z = (r.choice(sobj[tj]) for _ in range(3))
            if tj in used and r.random() < 0.2:
                X = f'c{tj}[AND_u8({self.expr("u8", allv, 1)}, 3)]'
            n, t = r.choice(vars_)
            if k < 0.22:
                L.append(f'    {X} = {Y};')
            elif k < 0.3:
                L.append(f'    {X} = mk_{nm}({self.expr("u16", allv, 2)});')
            elif k < 0.4:
                c = r.random()
                if c < 0.4:
                    L.append(f'    {X} = id_{nm}({Y}, {self.expr("i16", allv, 2)});')
                elif c < 0.7:
                    L.append(f'    {X} = id_{nm}(id_{nm}({Y}, {self.expr("i16", allv, 1)}), {self.expr("i16", allv, 1)});')
                else:
                    L.append(f'    {X} = id_{nm}(mk_{nm}({self.expr("u16", allv, 1)}), {self.expr("i16", allv, 1)});')
            elif k < 0.44:
                L.append(f'    {n} = ({tn(t)})bv_{nm}({Y}, {self.expr("i16", allv, 2)});')
            elif k < 0.48:
                L.append(self.struct_extra(ts, tj, nm, used, sobj, vars_, allv, X, Y, n, t))
            elif k < 0.52 and two and sobj[two[0]] and sobj[two[1]]:
                a, b = two
                ya, yb = r.choice(sobj[a]), r.choice(sobj[b])
                L.append(f'    {n} = ({tn(t)})two_{pfx}({self.expr("i8", allv, 1)}, {ya}, {self.expr("i32", allv, 1)}, {yb});')
            elif k < 0.7:
                w, wt = r.choice(writes)
                L.append(self.assign(w, wt, allv, 3))
            elif k < 0.78:
                w, wt = r.choice(writes)
                op = r.choice(LOWOPS)
                L.append(f'    {w} = {op.upper()}_{wt}({w}, {self.expr(wt, allv, 2)});')
            elif k < 0.84:
                L.append(f'    mix(sum_{nm}(&{Y}));')
            elif k < 0.88:
                # X = Y = Z: X and Y must not be the same object (not through p / q either)
                plain = [x for x in sobj[tj] if '*' not in x and '->' not in x]
                if len(plain) >= 2:
                    X, Y = r.sample(plain, 2)
                    L.append(f'    {X} = {Y} = {Z};')
            elif k < 0.92:
                L.append(f'    {X} = {self.cond(allv, 1)} ? {Y} : {Z};')
            elif k < 0.96 and tj in used:
                w, wt = r.choice(self.lvals(ts, tj, f'c{tj}[i]'))
                L.append(f'    for (i = 0; i < 3; i++) {{ c{tj}[i] = c{tj}[i + 1]; '
                         f'{w} = {self.expr(wt, allv + [("i", "i16")], 2)}; }}')
            else:
                if tj in used:
                    L.append(f'    p{tj} = &c{tj}[AND_u8({self.expr("u8", allv, 1)}, 3)];')
                n2, t2 = r.choice(vars_)
                L.append(f'    {n2} = {self.expr(t2, allv, 2)};')
        for ti in used:
            nm = ts[ti]['name']
            L.append(f'    mix(sum_{nm}(&a{ti})); mix(sum_{nm}(&b{ti}));')
            L.append(f'    for (i = 0; i < 4; i++) mix(sum_{nm}(&c{ti}[i]));')
            L.append(f'    for (i = 0; i < 3; i++) mix(sum_{nm}(&g{nm}[i]));')
        return self.tail(L, vars_)

    # ------------------------------------------------------------------ bit-fields
    def struct_extra(self, ts, tj, nm, used, sobj, vars_, allv, X, Y, n, t):
        r = self.r
        c = r.random()
        if c < 0.2:
            w, wt = r.choice(self.lvals(ts, tj, f'mk_{nm}({self.expr("u16", allv, 1)})'))
            return f'    {n} = ({tn(t)}){w};'
        if c < 0.35:
            w, wt = r.choice(self.lvals(ts, tj, f'id_{nm}({Y}, {self.expr("i16", allv, 1)})'))
            return f'    {n} = ({tn(t)}){w};'
        if c < 0.45:
            plain = [x for x in sobj[tj] if '*' not in x and '->' not in x and x != Y]
            if plain:
                w, wt = r.choice(self.lvals(ts, tj, f'({r.choice(plain)} = {Y})'))
                return f'    {n} = ({tn(t)}){w};'
        if c < 0.6:
            return f'    {X} = mkp_{nm}({self.expr("u16", allv, 2)});'
        if c < 0.8 and tj in used:
            cnd = r.choice(['((i + j) & 1)', '(i < j)', '(i != j)', '((i ^ j) == 2)'])
            return (f'    for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) if ({cnd}) c{tj}[i] = c{tj}[j];')
        if tj in used:
            w, wt = r.choice(self.lvals(ts, tj, f'(p{tj} + 1)', True))
            return (f'    p{tj} = &c{tj}[1]; {n} = ({tn(t)}){w}; p{tj}[-1] = p{tj}[2]; '
                    f'p{tj}[1] = *p{tj}; p{tj} = &c{tj}[{r.randint(0, 3)}];')
        return f'    {X} = {Y};'

    UNITS = [('unsigned char', 8, False), ('unsigned int', 16, False), ('unsigned', 16, False),
             ('signed int', 16, True), ('int', 16, True), ('unsigned long', 32, False),
             ('signed long', 32, True), ('long', 32, True)]

    def feat_bitfield(self, idx):
        r = self.r
        pfx = f'F{idx}_'
        nm = f'{pfx}B'
        fields = []      # (name, decl, semtype, lo, hi) ; name None for unnamed
        decl = []
        for k in range(r.randint(2, 8)):
            c = r.random()
            if c < 0.1:
                t = r.choice(list(TYPES))
                lo, hi = trange(t)
                fields.append((f'n{k}', t, lo, hi))
                decl.append(f'{tn(t)} n{k};')
                continue
            unit, ub, sg = r.choice(self.UNITS)
            w = r.randint(1, ub if ub < 32 else (16 if r.random() < 0.7 else 32))
            if c < 0.16:
                decl.append(f'{unit} : {r.choice([0, w])};')
                continue
            sem = ('i' if sg else 'u') + ('8' if w <= 8 else '16' if w <= 16 else '32')
            lo, hi = (-(1 << (w - 1)), (1 << (w - 1)) - 1) if sg else (0, (1 << w) - 1)
            fields.append((f'b{k}', sem, lo, hi))
            decl.append(f'{unit} b{k} : {w};')
        if not fields:
            fields.append(('b9', 'u8', 0, 7))
            decl.append('unsigned b9 : 3;')
        self.G.append(f'struct {nm} {{ {" ".join(decl)} }};')

        def init():
            return '{ ' + ', '.join(lit(s, r.randint(lo, hi)) for _, s, lo, hi in fields) + ' }'
        self.G.append(f'static struct {nm} g{nm}[2] = {{ {init()}, {init()} }};')
        self.G.append(f'static uint32_t sum_{nm}(const struct {nm} *p) {{ uint32_t h = 3; ' +
                      ' '.join(f'h = h * 31u + (uint32_t)({tn(s)})p->{f};' for f, s, _, _ in fields) + ' return h; }')
        f, s, _, _ = r.choice(fields)
        self.G.append(f'static uint32_t bv_{nm}(struct {nm} t, int16_t k) {{ t.{f} = ({tn(s)})k; t.{f}++; '
                      f'return sum_{nm}(&t); }}')
        self.G.append(f'static struct {nm} mk_{nm}(int16_t k) {{ struct {nm} t; ' +
                      ' '.join(f'{"t." + f} = ({tn(s)})MUL_i16(k, {r.randint(1, 999)});' for f, s, _, _ in fields) +
                      ' return t; }')
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(2, 5))
        L.append(f'    struct {nm} x = {init()}, y, *pb = &g{nm}[{r.randint(0, 1)}], ba[4];')
        L.append('    H = 0;')
        L.append('    y = x;')
        L.append(f'    for (i = 0; i < 4; i++) {{ ba[i] = g{nm}[i & 1]; ba[i].{r.choice(fields)[0]}++; }}')
        objs = ['x', 'y', f'g{nm}[0]', f'g{nm}[1]', '(*pb)', 'ba[0]', 'ba[3]']
        lv = []
        for o in objs:
            for f, s, _, _ in fields:
                lv.append((f'{o}.{f}' if o != '(*pb)' else f'pb->{f}', s))
        allv = vars_ + r.sample(lv, min(len(lv), 8))
        for _ in range(r.randint(8, 18)):
            k = r.random()
            w, wt = r.choice(lv)
            n, t = r.choice(vars_)
            if k < 0.25:
                L.append(self.assign(w, wt, allv, 3))
            elif k < 0.45:
                op = r.choice(LOWOPS)
                rt = r.choice(list(TYPES))
                L.append(f'    {w} {CSYM[op]}= ({tn(rt)})({self.expr(rt, allv, 2)});')
            elif k < 0.5:
                L.append(f'    {w} {r.choice(["<<", ">>"])}= {r.randint(0, 7)};')
            elif k < 0.62:
                c = r.choice([f'{w}++', f'{w}--', f'++{w}', f'--{w}'])
                if r.random() < 0.6:
                    L.append(f'    {n} = ({tn(t)})({c});')
                else:
                    L.append(f'    {c};')
            elif k < 0.68:
                op = r.choice(LOWOPS)
                x = f'{w} {CSYM[op]}= ({tn(wt)})({self.expr(wt, allv, 1)})'
                # regress/002: the value of an assignment to a bit-field is not converted
                L.append(f'    {x};' if AVOID_KNOWN else f'    {n} = ({tn(t)})({x});')
            elif k < 0.76:
                a, b = r.sample(objs, 2)
                L.append(f'    {a} = {b};')
            elif k < 0.82:
                L.append(f'    {n} = ({tn(t)})bv_{nm}({r.choice(objs)}, {self.expr("i16", allv, 2)});')
            elif k < 0.86:
                L.append(f'    {r.choice(objs)} = mk_{nm}({self.expr("i16", allv, 2)});')
            elif k < 0.92:
                f, s, _, _ = r.choice(fields)
                f2, s2, _, _ = r.choice(fields)
                op = r.choice(LOWOPS)
                L.append(f'    for (i = 0; i < 4; i++) {{ ba[i].{f} {CSYM[op]}= ({tn(s)})ADD_i16(i, {self.expr("i16", allv, 1)}); '
                         f'ba[(i + 1) & 3].{f2}++; {n} = ({tn(t)})ADD_{t}({n}, ba[i].{f}); }}')
            else:
                L.append(self.assign(n, t, allv, 3))
        for o in objs[:4]:
            L.append(f'    mix(sum_{nm}(&{o}));')
        L.append(f'    for (i = 0; i < 4; i++) mix(sum_{nm}(&ba[i]));')
        return self.tail(L, vars_)

    # ------------------------------------------------------------------ function pointers
    def feat_fptr(self, idx):
        r = self.r
        P = f'F{idx}_'
        p1, p2, rt = (r.choice(list(TYPES)) for _ in range(3))
        nh = r.randint(3, 6)
        G = self.G
        for k in range(nh):
            G.append(f'static {tn(rt)} {P}h{k}({tn(p1)} a, {tn(p2)} b) {{ return {self.expr(rt, [("a", p1), ("b", p2)], 3)}; }}')
        G.append(f'typedef {tn(rt)} (*{P}fp)({tn(p1)}, {tn(p2)});')
        tab = [f'{"&" if r.random() < 0.3 else ""}{P}h{r.randrange(nh)}' for _ in range(nh)]
        tab[0] = f'{P}h0'
        G.append(f'static {P}fp {P}tab[{nh}] = {{ {", ".join(tab)} }};')
        G.append(f'static {tn(rt)} {P}apply({P}fp f, {tn(p1)} a, {tn(p2)} b) {{ return f(a, b); }}')
        G.append(f'static {tn(rt)} {P}apply2({tn(rt)} (*f)({tn(p1)}, {tn(p2)}), {tn(p1)} a, {tn(p2)} b, uint8_t n) '
                 f'{{ {tn(rt)} s = 0; while (n--) {{ s = ADD_{rt}(s, (*f)(a, b)); a = ADD_{p1}(a, 1); }} return s; }}')
        G.append(f'static {P}fp {P}pick(uint8_t k) {{ return {P}tab[k % {nh}]; }}')
        na = r.randint(2, 4)
        for k in range(na):
            G.append(f'static void {P}act{k}(int16_t *p) {{ *p = {self.expr("i16", [("*p", "i16")], 2)}; }}')
        G.append(f'static void (*{P}acts[{na}])(int16_t *) = {{ {", ".join(f"{P}act{k}" for k in range(na))} }};')
        G.append(f'static struct {{ {P}fp f; int16_t k; }} {P}st[3] = {{ ' +
                 ', '.join(f'{{ {P}h{r.randrange(nh)}, {r.randint(-500, 500)} }}' for _ in range(3)) + ' };')
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(3, 5))
        L.append(f'    {P}fp fp = {P}tab[{r.randrange(nh)}];')
        L.append(f'    int16_t w = {r.randint(-999, 999)};')
        L.append('    H = 0;')
        allv = vars_ + [('w', 'i16')]

        def args():
            return f'{self.expr(p1, allv, 2)}, {self.expr(p2, allv, 2)}'
        for _ in range(r.randint(6, 14)):
            k = r.random()
            n, t = r.choice(vars_)
            if k < 0.15:
                L.append(f'    {n} = ({tn(t)}){P}tab[AND_u8({self.expr("u8", allv, 2)}, 7) % {nh}]({args()});')
            elif k < 0.25:
                L.append(f'    fp = {P}tab[{r.randrange(nh)}]; {n} = ({tn(t)})fp({args()});')
            elif k < 0.32:
                L.append(f'    {n} = ({tn(t)})(*fp)({args()});')
            elif k < 0.42:
                f = r.choice(['fp', f'{P}h{r.randrange(nh)}', f'{P}tab[{r.randrange(nh)}]', f'{P}pick({self.expr("u8", allv, 1)})'])
                L.append(f'    {n} = ({tn(t)}){P}apply({f}, {args()});')
            elif k < 0.48:
                L.append(f'    {n} = ({tn(t)}){P}apply2({P}tab[{r.randrange(nh)}], {args()}, {r.randint(0, 4)});')
            elif k < 0.56:
                L.append(f'    {n} = ({tn(t)}){P}pick({self.expr("u8", allv, 2)})({args()});')
            elif k < 0.62:
                L.append(f'    fp = {P}pick({self.expr("u8", allv, 1)});')
            elif k < 0.68:
                L.append(f'    mix((uint32_t)(fp == {P}tab[{r.randrange(nh)}])); mix((uint32_t)(fp != {P}h{r.randrange(nh)}));')
            elif k < 0.76:
                c = r.randrange(3)
                L.append(f'    {P}st[{c}].f = {P}h{r.randrange(nh)}; {n} = ({tn(t)}){P}st[{c}].f(({tn(p1)}){P}st[{c}].k, {self.expr(p2, allv, 1)});')
            elif k < 0.84:
                L.append(f'    {P}acts[AND_u8({self.expr("u8", allv, 1)}, 3) % {na}](&w);')
            elif k < 0.9:
                L.append(f'    fp = {self.cond(allv, 1)} ? {P}h{r.randrange(nh)} : {P}tab[{r.randrange(nh)}];')
            else:
                L.append(self.assign(n, t, allv, 3))
        L.append('    mix((uint32_t)w);')
        L.append(f'    mix((uint32_t)fp({args()}));')
        return self.tail(L, vars_)

    # ------------------------------------------------------------------ variadic
    KINDS = {'i': ('i16', '(int)', 'int'), 'u': ('u16', '(unsigned)', 'unsigned'),
             'l': ('i32', '(int32_t)', 'int32_t'), 'L': ('u32', '(uint32_t)', 'uint32_t'),
             'c': ('u8', '(int)', 'int')}

    def feat_vararg(self, idx):
        r = self.r
        P = f'F{idx}_'
        G = self.G
        cases = (" case 'i': h = h * 31u + (uint32_t)(int16_t)va_arg(ap, int); break;"
                 " case 'u': h = h * 31u + (uint32_t)(uint16_t)va_arg(ap, unsigned); break;"
                 " case 'l': h = h * 31u + (uint32_t)va_arg(ap, int32_t); break;"
                 " case 'L': h = h * 33u + va_arg(ap, uint32_t); break;"
                 " case 'c': h = h * 31u + (uint32_t)(uint8_t)va_arg(ap, int); break;"
                 " case 'p': h = h * 31u + (uint32_t)*va_arg(ap, int16_t *); break;"
                 " case 'q': { int32_t *q = va_arg(ap, int32_t *); *q = ADD_i32(*q, (int32_t)h); h = h * 31u + (uint32_t)*q; } break;"
                 " case 's': { const char *s = va_arg(ap, const char *); while (*s) h = h * 31u + (uint8_t)*s++; } break;")
        G.append(f'static uint32_t {P}vin(int16_t n, const char *k, va_list ap) {{ uint32_t h = 5; int16_t i; '
                 f'for (i = 0; i < n; i++) {{ switch (k[i]) {{{cases} }} }} return h; }}')
        G.append(f'static uint32_t {P}vsum(int16_t n, const char *k, ...) {{ va_list ap; uint32_t h = 7; int16_t i; '
                 f'va_start(ap, k); for (i = 0; i < n; i++) {{ switch (k[i]) {{{cases} }} }} va_end(ap); return h; }}')
        G.append(f'static uint32_t (*{P}vp)(int16_t, const char *, ...);')
        G.append(f'static uint32_t {P}vfwd(int32_t z, const char *k, ...) {{ va_list ap, aq; uint32_t h; '
                 f'va_start(ap, k); va_copy(aq, ap); h = {P}vin((int16_t)strlen(k), k, ap); '
                 f'h ^= {P}vin((int16_t)strlen(k), k, aq) * 3u; va_end(aq); va_end(ap); return h + (uint32_t)z; }}')
        G.append(f'static int16_t {P}fmt(char *buf, const char *f, ...) {{ va_list ap; int16_t n; '
                 f'va_start(ap, f); n = (int16_t)vsprintf(buf, f, ap); va_end(ap); return n; }}')
        G.append(f'static int16_t {P}fmtn(char *buf, uint16_t sz, const char *f, ...) {{ va_list ap; int16_t n; '
                 f'va_start(ap, f); n = (int16_t)vsnprintf(buf, (size_t)sz, f, ap); va_end(ap); return n; }}')
        G.append(f'static const char {P}str[] = "{r.choice(["abc", "", "Hello, world", "x", "0123456789"])}";')
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(3, 5))
        L.append(f'    int16_t pw = {r.randint(-30000, 30000)};')
        L.append(f'    int32_t pl = {r.randint(-2**31, 2**31 - 1)}L;')
        L.append('    char buf[160];')
        L.append('    const char *s;')
        L.append('    H = 0;')
        L.append('    buf[0] = 0;')
        L.append(f'    {P}vp = {P}vsum;')
        allv = vars_ + [('pw', 'i16'), ('pl', 'i32')]

        def arglist(kinds):
            out = []
            for c in kinds:
                if c == 'p':
                    out.append(r.choice(['&pw', '&ga_i16[3]', '&gs[1].c']))
                elif c == 'q':
                    out.append(r.choice(['&pl', '&ga_i32[5]']))
                elif c == 's':
                    out.append(r.choice([f'{P}str', '"zq"', '""']))
                else:
                    t, cast, _ = self.KINDS[c]
                    out.append(f'{cast}{self.expr(t, allv, 2)}')
            return out
        for _ in range(r.randint(5, 10)):
            k = r.random()
            n, t = r.choice(vars_)
            if k < 0.35:
                kinds = ''.join(r.choice('iiullLcpqs') for _ in range(r.randint(0, 8 if r.random() < 0.7 else 16)))
                fn = r.choice([f'{P}vsum', f'{P}vsum', f'{P}vp', f'(*{P}vp)'])
                L.append(f'    {n} = ({tn(t)}){fn}({len(kinds)}, "{kinds}"{"".join(", " + a for a in arglist(kinds))});')
            elif k < 0.5:
                kinds = ''.join(r.choice('iulLcps') for _ in range(r.randint(1, 6)))
                L.append(f'    {n} = ({tn(t)}){P}vfwd({self.expr("i32", allv, 1)}, "{kinds}"{"".join(", " + a for a in arglist(kinds))});')
            elif k < 0.85:
                fmt, args = self.format()
                if r.random() < 0.6:
                    L.append(f'    mix((uint32_t){P}fmt(buf, "{fmt}"{"".join(", " + a for a in args)}));')
                else:
                    L.append(f'    mix((uint32_t){P}fmtn(buf, {r.choice([0, 1, 2, 5, 9, 17, 40, 160])}, "{fmt}"{"".join(", " + a for a in args)}));')
                L.append('    for (s = buf; *s; s++) mix((uint8_t)*s);')
            else:
                L.append(self.assign(n, t, allv, 3))
        L.append('    mix((uint32_t)pw); mix((uint32_t)pl);')
        return self.tail(L, vars_)

    def format(self):
        r = self.r
        allv = []
        fmt = []
        args = []
        for _ in range(r.randint(1, 6)):
            if r.random() < 0.3:
                fmt.append(r.choice(['a', '-', ' ', ':', 'xy', '%%', '[', '=']))
            flags = ''.join(r.sample(['-', '0', '+', ' '], r.randint(0, 2))) if r.random() < 0.4 else ''
            width = str(r.randint(1, 9)) if r.random() < 0.4 else ''
            prec = f'.{r.randint(0, 6)}' if r.random() < 0.2 else ''
            conv = r.choice(['d', 'i', 'u', 'x', 'X', 'o', 'ld', 'lu', 'lx', 'lX', 'c', 's', 'hd', 'hu', '#x', 'hhu', 'hhd'])
            if conv == '#x':
                flags = '#' + flags.replace('0', '')
                conv = 'x'
            if conv == 'c':
                fmt.append(f'%{flags.replace("0", "").replace("+", "").replace(" ", "")}{width}c')
                args.append(f'(int)(uint8_t)ADD_u8(AND_u8({self.expr("u8", allv, 1)}, 31), 65)')
                continue
            if conv == 's':
                fmt.append(f'%{flags.replace("0", "").replace("+", "").replace(" ", "")}{width}{prec}s')
                args.append(r.choice(['"abc"', '""', '"Hello"', f'ga_i8 ? "q" : "r"']))
                continue
            fmt.append(f'%{flags}{width}{prec}{conv}')
            if conv in ('d', 'i', 'hd'):
                args.append(f'(int){self.expr("i16", allv, 1)}')
            elif conv in ('u', 'x', 'X', 'o', 'hu'):
                args.append(f'(unsigned){self.expr("u16", allv, 1)}')
            elif conv == 'hhu':
                args.append(f'(unsigned){self.expr("u8", allv, 1)}')
            elif conv == 'hhd':
                args.append(f'(int){self.expr("i8", allv, 1)}')
            elif conv == 'ld':
                args.append(f'(long){self.expr("i32", allv, 1)}')
            else:
                args.append(f'(unsigned long){self.expr("u32", allv, 1)}')
        return ''.join(fmt), args

    # ------------------------------------------------------------------ far pointers
    def feat_far(self, idx):
        r = self.r
        self.uses_far = True
        P = f'F{idx}_'
        G = self.G
        G.append(f'static uint32_t {P}fsum(const uint8_t __far *p, uint16_t n) {{ uint32_t h = 0; '
                 f'while (n--) h = h * 31u + *p++; return h; }}')
        G.append(f'static void {P}fset(int16_t __far *p, int16_t i, int16_t v) {{ p[i] = v; }}')
        G.append(f'static int32_t {P}fget(int32_t __far *p, uint16_t i) {{ return p[i]; }}')
        G.append(f'static int16_t __far *{P}fadv(int16_t __far *p, int16_t n) {{ return p + n; }}')
        G.append(f'static uint8_t __far *{P}gfp;')
        G.append(f'static int16_t {P}gnear[8] = {{ {", ".join(str(r.randint(-32768, 32767)) for _ in range(8))} }};')
        G.append(f'static uint32_t {P}gl = {r.getrandbits(32)}UL;')
        G.append(f'struct {P}FS {{ int16_t a; uint8_t b; int32_t c; uint16_t d; }} PACKED;   /* laid over bytes */')
        wins = [0, r.choice([0x7FE0, 0x8000 - 32, 0x1234, 0x7FC0, 0x8000]), 0xFFC0]
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(3, 5))
        L.append('    uint8_t __far *fb;')
        L.append('    uint16_t u;')
        L.append('    int16_t loc[8];')
        L.append(f'    int16_t __far *fl = (int16_t __far *)loc;')
        L.append(f'    uint32_t __far *fg = (uint32_t __far *)&{P}gl;')
        # typed pointers into the windows: (name, type, window, byte offset in the window, count)
        ptrs = []
        for k in range(r.randint(3, 6)):
            t = r.choice(list(TYPES))
            w = r.randrange(3)
            o = r.randint(0, 7)
            cnt = (64 - o) // tsize(t)
            ptrs.append((f'p{k}', t, w, o, cnt))
            L.append(f'    {tn(t)} __far *p{k};')
        for t in TYPES:
            L.append(f'    {tn(t)} __far *q_{t};')
        L.append(f'    struct {P}FS __far *fs;')
        L.append(f'    struct {P}FS fsl;')
        L.append('    H = 0;')
        L.append('    fb = hz_far_alloc();')
        L.append('    if (!fb) return 1;')
        for w in wins:
            L.append(f'    for (u = 0; u < 64; u++) fb[{w}u + u] = (uint8_t)ADD_u8(MUL_u8(u, {r.randint(1, 255) | 1}), {r.randint(0, 255)});')
        L.append(f'    for (u = 0; u < 8; u++) loc[u] = (int16_t)MUL_i16(u, {r.randint(-999, 999)});')
        for n, t, w, o, cnt in ptrs:
            L.append(f'    {n} = ({tn(t)} __far *)(fb + {wins[w] + o}u);')
        L.append(f'    fs = (struct {P}FS __far *)(fb + {wins[r.randrange(3)] + r.randint(0, 64 - 18)}u);')
        L.append('    fsl.a = fs[1].a; fsl.b = fs[1].b; fsl.c = fs[1].c; fsl.d = fs[1].d;' if AVOID_KNOWN else '    fsl = fs[1];')
        reads = [('fl[%d]' % r.randrange(8), 'i16'), ('*fg', 'u32'), ('fs->c', 'i32'), ('fs[1].a', 'i16'), ('fs->b', 'u8')]
        for n, t, w, o, cnt in ptrs:
            reads.append((f'{n}[{r.randrange(cnt)}]', t))
            reads.append((f'*{n}', t))
        allv = vars_ + reads
        for _ in range(r.randint(8, 16)):
            k = r.random()
            n, t, w, o, cnt = r.choice(ptrs)
            v, vt = r.choice(vars_)
            c = r.randrange(cnt)
            if k < 0.15:
                L.append(f'    {n}[{c}] = {self.expr(t, allv, 2)};')
            elif k < 0.22:
                op = r.choice(LOWOPS)
                L.append(f'    {n}[{c}] {CSYM[op]}= ({tn(t)}){self.expr(t, allv, 2)};')
            elif k < 0.3:
                x = r.choice([f'{n}[{c}]++', f'--{n}[{c}]', f'(*{n})--', f'++*{n}'])
                L.append(f'    {v} = ({tn(vt)})({x});')
            elif k < 0.4:
                ix = r.choice([f'(uint16_t){self.expr("u16", allv, 1)} % {cnt}u',
                               f'(uint32_t){self.expr("u32", allv, 1)} % {cnt}u',
                               f'(uint8_t){self.expr("u8", allv, 1)} % {cnt}'])
                if r.random() < 0.5:
                    L.append(f'    {v} = ({tn(vt)}){n}[{ix}];')
                else:
                    L.append(f'    {n}[{ix}] = {self.expr(t, allv, 2)};')
            elif k < 0.48 and cnt >= 2:
                h = cnt // 2
                ix = r.choice([f'mod_i16({self.expr("i16", allv, 1)}, {h})', f'(int32_t)mod_i16({self.expr("i16", allv, 1)}, {h})',
                               f'(int8_t)mod_i8({self.expr("i8", allv, 1)}, {min(h, 127)})'])
                L.append(f'    q_{t} = {n} + {h}; {v} = ({tn(vt)})q_{t}[{ix}]; q_{t}[{ix}] = {self.expr(t, allv, 1)};')
            elif k < 0.58:
                a = r.randrange(cnt)
                b = r.randint(0, a)
                c2 = r.randint(0, cnt - 1 - (a - b) - 1) if cnt - (a - b) >= 2 else 0
                L.append(f'    q_{t} = {n} + {a}; q_{t} -= {b}; q_{t} += {c2}; {v} = ({tn(vt)})*q_{t}++; '
                         f'*q_{t}-- = {self.expr(t, allv, 1)}; mix((uint32_t)*q_{t});'
                         if cnt - (a - b) - c2 >= 2 else
                         f'    q_{t} = {n} + {a}; q_{t} -= {b}; {v} = ({tn(vt)})*q_{t};')
            elif k < 0.66:
                a, b = r.randrange(cnt), r.randrange(cnt)
                L.append(f'    q_{t} = &{n}[{a}]; mix((uint32_t)(q_{t} > {n} + {b})); mix((uint32_t)(q_{t} <= &{n}[{b}])); '
                         f'mix((uint32_t)(q_{t} == {n} + {b})); mix((uint32_t)(int16_t)(q_{t} - {n})); '
                         f'mix((uint32_t)(int16_t)(&{n}[{b}] - q_{t}));')
            elif k < 0.72:
                c = r.randrange(8)
                L.append(f'    fl[{c}] = {self.expr("i16", allv, 2)}; {v} = ({tn(vt)})ADD_i16(loc[{c}], fl[{r.randrange(8)}]); '
                         f'{P}fset(fl, {r.randrange(8)}, (int16_t){v});')
            elif k < 0.76:
                L.append(f'    *fg = {self.expr("u32", allv, 2)}; {v} = ({tn(vt)}){P}gl;')
            elif k < 0.82:
                L.append(f'    fs->{r.choice("abcd")} = {self.expr(r.choice(["i16", "u8", "i32"]), allv, 2)}; '
                         f'fs[1].c = ADD_i32(fs[1].c, fs->a); {v} = ({tn(vt)})ADD_u16(fs->d, fs[1].b);')
            elif k < 0.86:
                if tsize(t) == 4 and t == 'i32':
                    L.append(f'    {v} = ({tn(vt)}){P}fget({n}, {c});')
                else:
                    w2 = wins[r.randrange(3)]
                    L.append(f'    {v} = ({tn(vt)}){P}fsum(fb + {w2}u + {r.randint(0, 40)}u, {r.randint(0, 24)});')
            elif k < 0.9:
                L.append(f'    fb[65535u] = {self.expr("u8", allv, 1)}; {v} = ({tn(vt)})ADD_u8(fb[65535u], fb[{r.randint(0xFFC0, 0xFFFE)}u]);')
            elif k < 0.97:
                c = r.random()
                o1, o2 = wins[r.randrange(3)] + r.randint(0, 63), wins[r.randrange(3)] + r.randint(0, 63)
                if c < 0.3:
                    # ptrdiff_t is 16 bits in cc816: a difference only when it fits
                    L.append(f'    mix((uint32_t)(fb + {o1}u < fb + {o2}u)); mix((uint32_t)(fb + {o1}u >= fb + {o2}u));' +
                             (f' mix((uint32_t)(int16_t)((fb + {o1}u) - (fb + {o2}u)));' if abs(o1 - o2) <= 32767 else ''))
                elif c < 0.6 and not AVOID_KNOWN:      # regress/003: structure copies through far pointers
                    a, b = r.sample(['fs[0]', 'fs[1]', 'fsl'], 2)
                    L.append(f'    {a} = {b}; fsl.c = ADD_i32(fsl.c, {self.expr("i32", allv, 1)}); {v} = ({tn(vt)})ADD_i32(fs->c, fs[1].a);')
                elif c < 0.8:
                    w = wins[r.randrange(3)]
                    i0 = r.randint(0, 31)
                    d = r.randint(-i0, 31 - i0)
                    L.append(f'    {v} = ({tn(vt)})ADD_i16(*{P}fadv((int16_t __far *)(fb + {w}u), {i0}), '
                             f'{P}fadv((int16_t __far *)(fb + {w}u) + {i0}, {d})[0]);')
                else:
                    w = wins[r.randrange(3)]
                    L.append(f'    {P}gfp = fb + {w}u; {P}gfp[{r.randint(0, 63)}] = {self.expr("u8", allv, 1)}; '
                             f'{v} = ({tn(vt)}){P}gfp[{r.randint(0, 63)}];')
            else:
                L.append(self.assign(v, vt, allv, 3))
        for w in wins:
            L.append(f'    mix({P}fsum(fb + {w}u, 64));')
        L.append('    for (u = 0; u < 8; u++) mix((uint32_t)loc[u]);')
        L.append(f'    mix({P}gl);')
        L.append('    hz_far_free(fb);')
        return self.tail(L, vars_)

    # ------------------------------------------------------------------ switch
    def case_body(self, n, t, allv, depth):
        r = self.r
        c = r.random()
        if c < 0.15 and depth > 0:
            sub = self.switch_stmt(allv, depth - 1, indent='')
            return sub
        if c < 0.5:
            return f'{n} = {OPS_UP(r)}_{t}({n}, {self.const(t)});'
        return f'{n} = {self.expr(t, allv, 2)};'

    def switch_stmt(self, allv, depth, indent='    ', loopvar=None):
        r = self.r
        st = r.choice(list(TYPES))
        lo, hi = trange(st)
        shape = r.random()
        vals = set()
        if shape < 0.45:
            n = r.randint(5, 40 if nbits(st) > 8 or not issigned(st) else 30)
            c = r.random()
            if c < 0.3:
                base = lo
            elif c < 0.5:
                base = hi - n + 1
            elif c < 0.7 and issigned(st):
                base = -r.randint(1, n)
            else:
                base = r.randint(lo, hi - n + 1)
            vals = set(range(base, base + n))
        else:
            n = r.randint(3, 12)
            vals = {lo, hi} if r.random() < 0.5 else set()
            while len(vals) < n:
                vals.add(self.rval(st))
        vals = sorted(vals)
        base = vals[0]
        if loopvar:
            sel = f'({tn(st)})ADD_{st}({lit(st, base - 2)}, MUL_{st}({loopvar}, {r.choice([1, 1, 1, 2, 3, 7])}))'
        else:
            sel = f'({tn(st)})({self.expr(st, allv, 2)})'
        cases = [f'case {lit(st, v)}:' for v in vals]
        dpos = r.random()
        if dpos < 0.25:
            di = None
        elif dpos < 0.45:
            di = 0
        elif dpos < 0.8:
            di = r.randint(0, len(cases))
        else:
            di = len(cases)
        items = list(cases)
        if di is not None:
            items.insert(di, 'default:')
        out = [f'switch ({sel}) {{']
        vs = [x for x in allv if x[0].startswith('v')]
        for it in items:
            n, t = r.choice(vs)
            body = self.case_body(n, t, allv, depth)
            if loopvar and r.random() < 0.08:
                body = f'{n} = ADD_{t}({n}, 1); continue;'
            brk = ' break;' if r.random() < 0.7 else ''
            if r.random() < 0.15 and it != 'default:' and it is not items[-1]:
                out.append(f'{it}')        # empty: falls into the next label
                continue
            out.append(f'{it} {body}{brk}')
        out.append('}')
        return ' '.join(out)

    def feat_switch(self, idx):
        r = self.r
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(3, 6))
        L.append('    H = 0;')
        for _ in range(r.randint(2, 4)):
            if r.random() < 0.6:
                n = r.randint(6, 46)
                L.append(f'    for (i = 0; i < {n}; i++) {{ {self.switch_stmt(vars_ + [("i", "i16")], 1, loopvar="i")} '
                         f'mix((uint32_t){r.choice(vars_)[0]}); }}')
            else:
                L.append('    ' + self.switch_stmt(vars_, 1))
            n, t = r.choice(vars_)
            L.append(self.assign(n, t, vars_, 2))
        return self.tail(L, vars_)

    # ------------------------------------------------------------------ spill
    def feat_spill(self, idx):
        r = self.r
        P = f'F{idx}_'
        self.G.append(f'static int32_t {P}call3(int16_t a, int32_t b, uint8_t c) '
                      f'{{ return ADD_i32(MUL_i32(a, {r.randint(-99, 99)}), XOR_i32(b, c)); }}')
        a8 = ['i8', 'i16', 'i32', 'u8', 'u16', 'u32', 'i8', 'i32']
        r.shuffle(a8)
        self.many = (f'{P}many', a8)
        prm = [(chr(97 + q), t) for q, t in enumerate(a8)]
        self.G.append(f'static int32_t {P}many(' + ', '.join(f'{tn(t)} {n}' for n, t in prm) + ') { return ' +
                      f'(int32_t){self.expr("i32", prm, 4)}; }}')
        L = self.head(idx)
        L.append('    int16_t k, m;')
        vars_ = self.scalars(L, r.randint(15, 30))
        L.append('    H = 0;')
        loops = [('i', r.randint(2, 3)), ('j', r.randint(1, 3)), ('k', r.randint(2, 3))]
        if r.random() < 0.5:
            loops.append(('m', 2))
        lv = []

        def stmts(n, ind):
            allv = vars_ + lv
            for _ in range(n):
                s = self.spill_stmt(vars_, allv, P)
                L.append(ind + s)
        for d, (v, cnt) in enumerate(loops):
            ind = '    ' * (d + 1)
            L.append(f'{ind}for ({v} = 0; {v} < {cnt}; {v}++) {{')
            lv.append((v, 'i16'))
            stmts(r.randint(1, 3), ind + '    ')
        for d in range(len(loops) - 1, -1, -1):
            ind = '    ' * (d + 1)
            stmts(r.randint(0, 2), ind + '    ')
            L.append(f'{ind}}}')
        return self.tail(L, vars_)

    def spill_stmt(self, vars_, allv, P):
        r = self.r
        k = r.random()
        (a, ta), (b, tb), (c, tc) = r.sample(vars_, 3)
        if k < 0.3:
            return f'{a} = {self.expr(ta, allv, r.randint(3, 5))};'
        if k < 0.5:
            op = r.choice(LOWOPS)
            if r.random() < 0.5:
                return f'{a} {CSYM[op]}= {b};'
            return f'{a} {CSYM[op]}= ({tn(tb)})({self.expr(tb, allv, 2)});'
        if k < 0.57:
            m = {8: 15, 16: 15, 32: 31}[nbits(ta)]
            if r.random() < 0.5:
                return f'{a} {r.choice(["<<", ">>"])}= {r.randint(0, m)};'
            return f'{a} {r.choice(["<<", ">>"])}= AND_u8({self.expr("u8", allv, 1)}, {m});'
        if k < 0.62:
            return f'{a} {r.choice("/%")}= ({tn(ta)})(AND_u8({self.expr("u8", allv, 1)}, 7) + 1);'
        if k < 0.67:
            fn, a8 = self.many
            return f'{a} = ({tn(ta)}){fn}(' + ', '.join(f'({tn(t)}){self.expr(t, allv, 1)}' for t in a8) + ');'
        if k < 0.72:
            return f'{a} = ({tn(ta)}){P}call3(({tn("i16")}){b}, ({tn("i32")}){self.expr("i32", allv, 2)}, (uint8_t){c});'
        if k < 0.8:
            return r.choice([f'{a}++;', f'--{a};', f'{a} = ({tn(ta)})({b}++);', f'{a} = ({tn(ta)})(--{b});'])
        if k < 0.88:
            av = [x for x in allv if x[0] not in (a, b, c)]
            return f'{a} = {self.cond(av, 1)} ? ({tn(ta)})({b}++) : ({tn(ta)})({c} += {self.const(tc)});'
        if k < 0.94:
            av = [x for x in allv if x[0] != a]
            return f'{a} = ({b} = {self.expr(tb, av, 2)}, ({tn(ta)})ADD_{tb}({b}, {c}));'
        return f'{a} = ({tn(ta)})rec(AND_u8({self.expr("u8", allv, 1)}, 7), {self.expr("i16", allv, 2)});'

    # ------------------------------------------------------------------ pointers, ++/--, big locals, statics
    def feat_ptr(self, idx):
        r = self.r
        P = f'F{idx}_'
        G = self.G
        G.append(f'static int32_t {P}rec3(int16_t n, int32_t acc, uint8_t k, int16_t *cnt) {{ (*cnt)++; '
                 f'if (n <= 0) return acc; '
                 f'if ((n & 1) == 0) return {P}rec3(n - 1, ADD_i32(acc, MUL_i32(n, k)), (uint8_t)(k + {r.randint(1, 9)}), cnt); '
                 f'return XOR_i32({P}rec3(n - 2, SUB_i32(acc, k), (uint8_t)(k ^ {r.randint(1, 255)}), cnt), n); }}')
        G.append(f'static void {P}bump(int16_t *a, int32_t *b, uint8_t *c, int16_t k) {{ *a = ADD_i16(*a, k); '
                 f'*b = XOR_i32(*b, MUL_i32(*a, {r.randint(2, 99)})); *c = (uint8_t)ADD_u8(*c, *a); }}')
        G.append(f'static uint16_t {P}stl(int16_t x) {{ static uint16_t c = {r.randint(0, 65535)}u; '
                 f'static int32_t acc = {r.randint(-99999, 99999)}L; static uint8_t tab[4] = {{ 1, 2, 3, 4 }}; '
                 f'c = (uint16_t)ADD_u16(MUL_u16(c, 5), 1); acc = ADD_i32(acc, MUL_i32(c, x)); tab[c & 3]++; '
                 f'return (uint16_t)(c ^ (uint16_t)acc ^ tab[x & 3]); }}')
        nbig = r.randint(60, 220)
        G.append(f'struct {P}Big {{ int32_t x[{r.randint(10, 40)}]; uint8_t t[{r.randint(10, 60)}]; int16_t k; }};')
        G.append(f'static uint32_t {P}bigsum(const struct {P}Big *p) {{ uint32_t h = (uint32_t)p->k; uint16_t i; '
                 f'for (i = 0; i < sizeof(p->x) / sizeof(p->x[0]); i++) h = h * 31u + (uint32_t)p->x[i]; '
                 f'for (i = 0; i < sizeof(p->t); i++) h = h * 31u + p->t[i]; return h; }}')
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(3, 6))
        for t in TYPES:
            L.append(f'    {tn(t)} a_{t}[6], *p_{t} = &a_{t}[2];')
        L.append(f'    int16_t big[{nbig}], cnt = 0;')
        L.append(f'    struct {P}Big bs, bs2;')
        L.append(f'    int16_t ai = {r.randint(-999, 999)}; int32_t al = {r.randint(-99999, 99999)}L; uint8_t ac = {r.randint(0, 255)};')
        L.append('    H = 0;')
        for t in TYPES:
            L.append(f'    for (i = 0; i < 6; i++) a_{t}[i] = ({tn(t)})MUL_{t}(ADD_{t}(i, {self.const(t)}), {self.const(t)});')
        L.append(f'    for (i = 0; i < {nbig}; i++) big[i] = (int16_t)MUL_i16(i, {r.randint(-999, 999)});')
        L.append(f'    for (i = 0; i < (int16_t)(sizeof(bs.x) / sizeof(bs.x[0])); i++) bs.x[i] = MUL_i32(i, {r.randint(-99999, 99999)}L);')
        L.append(f'    for (i = 0; i < (int16_t)sizeof(bs.t); i++) bs.t[i] = (uint8_t)(i * 3);')
        L.append('    bs.k = 7;')
        reads = [(f'a_{t}[{r.randrange(6)}]', t) for t in TYPES] + [(f'p_{t}[{r.randint(-2, 3)}]', t) for t in TYPES] + \
            [('ai', 'i16'), ('al', 'i32'), ('ac', 'u8'), (f'big[{r.randrange(nbig)}]', 'i16')]
        allv = vars_ + reads
        for _ in range(r.randint(8, 16)):
            k = r.random()
            t = r.choice(list(TYPES))
            (n, nt), (n2, nt2), (n3, nt3) = r.sample(vars_, 3) if len(vars_) >= 3 else (vars_[0], vars_[1], vars_[-1])
            pa = f'p_{t}'
            if k < 0.2:
                x = r.choice([f'(*{pa})++', f'++*{pa}', f'(*{pa})--', f'--*{pa}', f'{pa}[1]++', f'--{pa}[-1]',
                              f'a_{t}[{r.randrange(6)}]++', f'++a_{t}[{r.randrange(6)}]', f'a_{t}[{r.randrange(6)}]--',
                              f'*{pa}++', f'*--{pa}', f'*{pa}--', f'*++{pa}'])
                L.append(f'    {n} = ({tn(nt)})({x});')
                if '++' + pa in x or pa + '++' in x or '--' + pa in x or pa + '--' in x:
                    L.append(f'    {pa} = &a_{t}[2];')
            elif k < 0.3:
                a, b = r.randrange(6), r.randrange(6)
                L.append(f'    {n} = ({tn(nt)})(&a_{t}[{a}] - &a_{t}[{b}]); {n2} = ({tn(nt2)})({pa} - a_{t}); '
                         f'mix((uint32_t)(&a_{t}[{a}] < {pa})); mix((uint32_t)({pa} >= &a_{t}[{b}])); '
                         f'mix((uint32_t)(&a_{t}[AND_u8({self.expr("u8", allv, 1)}, 3)] != {pa}));')
            elif k < 0.4:
                av = [x for x in allv if x[0] not in (n, n2, n3)]
                L.append(f'    {n} = {self.cond(av, 1)} ? ({tn(nt)})({n2}++) : ({tn(nt)})({n3} {r.choice("+-^")}= {self.const(nt3)});')
            elif k < 0.48:
                av = [x for x in allv if x[0] != n]
                L.append(f'    {n} = ({n2} = {self.expr(nt2, av, 2)}, {n3} = ({tn(nt3)})ADD_{nt2}({n2}, 1), ({tn(nt)})ADD_{nt3}({n3}, {n2}));')
            elif k < 0.55:
                L.append(f'    cnt = 0; {n} = ({tn(nt)}){P}rec3(AND_i16({self.expr("i16", allv, 1)}, 15), {self.expr("i32", allv, 1)}, '
                         f'{self.expr("u8", allv, 1)}, &cnt); mix((uint32_t)cnt);')
            elif k < 0.63:
                L.append(f'    {P}bump(&ai, &al, &ac, {self.expr("i16", allv, 2)}); {n} = {self.expr(nt, allv, 2)};')
            elif k < 0.68:
                L.append(f'    {n} = ({tn(nt)}){P}stl({self.expr("i16", allv, 1)});')
            elif k < 0.76:
                c = r.randrange(nbig)
                L.append(f'    big[{c}] = {self.expr("i16", allv, 2)}; big[(uint16_t){self.expr("u16", allv, 1)} % {nbig}u] += big[{r.randrange(nbig)}]; '
                         f'{n} = ({tn(nt)})big[{c}];')
            elif k < 0.82:
                L.append(f'    bs.x[{r.randint(0, 9)}] = {self.expr("i32", allv, 2)}; bs.t[{r.randint(0, 9)}]++; bs2 = bs; '
                         f'bs2.k = (int16_t){n}; mix({P}bigsum(&bs2));')
            elif k < 0.9:
                op = r.choice(LOWOPS)
                L.append(f'    {pa}[{r.randint(-2, 3)}] {CSYM[op]}= ({tn(t)}){self.expr(t, allv, 2)};')
            else:
                L.append(self.assign(n, nt, allv, 3))
        for t in TYPES:
            L.append(f'    for (i = 0; i < 6; i++) mix((uint32_t)a_{t}[i]);')
        L.append(f'    for (i = 0; i < {nbig}; i++) mix((uint32_t)big[i]);')
        L.append(f'    mix({P}bigsum(&bs)); mix((uint32_t)ai); mix((uint32_t)al); mix((uint32_t)ac);')
        return self.tail(L, vars_)

    # ------------------------------------------------------------------ globals
    def feat_globals(self, idx):
        r = self.r
        P = f'F{idx}_'
        G = self.G
        words = ['', 'a', 'abc', 'Hello', 'zz\\x7f', 'tab\\there', 'q\\"x']
        s0 = r.choice(words)
        G.append(f'static const char {P}s0[] = "{s0}";')
        G.append(f'static char {P}msg[12] = "{r.choice(words[:5])}";')
        sc = []
        for t in TYPES:
            G.append(f'static {tn(t)} {P}g_{t} = {lit(t, self.rval(t))};')
            sc.append((f'{P}g_{t}', t))
        G.append(f'static int16_t {P}g2d[3][4] = {{ ' + ', '.join('{ ' + ', '.join(str(r.randint(-32768, 32767)) for _ in range(4)) + ' }' for _ in range(3)) + ' };')
        G.append(f'static uint8_t {P}gb[] = {{ {", ".join(str(r.randint(0, 255)) for _ in range(r.randint(1, 9)))} }};')
        G.append(f'static const int32_t {P}gc[4] = {{ {", ".join(lit("i32", self.rval("i32")) for _ in range(r.randint(1, 4)))} }};')
        G.append(f'struct {P}GT {{ const char *name; int16_t *pv; int32_t n; uint8_t k; struct {P}GT *next; }};')
        # regress/001: a row of a 2-D array (g2d[2]) as an address constant is refused
        pv = [f'&{P}g_i16', f'&{P}g2d[1][2]', '&ga_i16[4]', f'{P}g2d[2]' if not AVOID_KNOWN else f'&{P}g2d[2][0]',
              '&gs[0].c']
        names = [f'"{r.choice(words)}"', f'{P}s0', f'{P}msg', f'{P}s0 + 1' if s0 and r.random() < 0.5 else '"x"']
        nt = 4
        ent = []
        for k in range(nt):
            nxt = f'&{P}gt[{(k + 1) % nt}]' if r.random() < 0.8 else '0'
            ent.append(f'{{ {r.choice(names)}, {r.choice(pv)}, {lit("i32", self.rval("i32"))}, {r.randint(0, 255)}, {nxt} }}')
        G.append(f'static struct {P}GT {P}gt[{nt}] = {{ {", ".join(ent)} }};')
        G.append(f'static int16_t *{P}gp[3] = {{ {", ".join(r.choice(pv) for _ in range(3))} }};')
        G.append(f'static const char *{P}gn[] = {{ {", ".join(r.choice(names) for _ in range(3))} }};')
        G.append(f'static struct {P}GT *{P}gtp = &{P}gt[{r.randrange(nt)}];')
        G.append(f'static uint32_t {P}walk(const struct {P}GT *p, int16_t n) {{ uint32_t h = 0; const char *s; '
                 f'while (p && n-- > 0) {{ for (s = p->name; *s; s++) h = h * 31u + (uint8_t)*s; '
                 f'h = h * 31u + (uint32_t)*p->pv + (uint32_t)p->n + p->k; p = p->next; }} return h; }}')
        L = self.head(idx)
        vars_ = self.scalars(L, r.randint(2, 4))
        L.append('    const char *s;')
        L.append('    H = 0;')
        allv = vars_ + sc + [(f'{P}g2d[{r.randrange(3)}][{r.randrange(4)}]', 'i16'), (f'{P}gb[0]', 'u8'),
                             (f'{P}gc[0]', 'i32'), (f'*{P}gp[{r.randrange(3)}]', 'i16'), (f'{P}gtp->n', 'i32'),
                             (f'{P}gt[{r.randrange(nt)}].k', 'u8')]
        L.append(f'    mix({P}walk({P}gtp, 6));')
        L.append(f'    for (i = 0; i < 3; i++) for (s = {P}gn[i]; *s; s++) mix((uint8_t)*s);')
        L.append(f'    for (i = 0; i < 3; i++) for (j = 0; j < 4; j++) mix((uint32_t){P}g2d[i][j]);')
        L.append(f'    for (i = 0; i < (int16_t)sizeof({P}gb); i++) mix({P}gb[i]);')
        L.append(f'    for (i = 0; i < 4; i++) mix((uint32_t){P}gc[i]);')
        for _ in range(r.randint(5, 10)):
            k = r.random()
            n, t = r.choice(vars_ + sc)
            if k < 0.4:
                L.append(self.assign(n, t, allv, 3))
            elif k < 0.55:
                L.append(f'    *{P}gp[{r.randrange(3)}] = {self.expr("i16", allv, 2)};')
            elif k < 0.65:
                L.append(f'    {P}gt[{r.randrange(nt)}].pv = {r.choice(pv)}; {P}gtp = {P}gtp->next ? {P}gtp->next : &{P}gt[0];')
            elif k < 0.75:
                L.append(f'    {P}msg[{r.randint(0, 10)}] = (char)ADD_u8(AND_u8({self.expr("u8", allv, 1)}, 63), 32); {P}msg[11] = 0;')
            elif k < 0.85:
                L.append(f'    {P}gt[{r.randrange(nt)}].n = {self.expr("i32", allv, 2)}; {P}gt[{r.randrange(nt)}].k += {r.randint(0, 255)};')
            else:
                L.append(f'    mix({P}walk(&{P}gt[{r.randrange(nt)}], {r.randint(1, 9)}));')
        L.append(f'    mix({P}walk({P}gtp, 6));')
        L.append(f'    for (s = {P}msg; *s; s++) mix((uint8_t)*s);')
        L.append(f'    for (i = 0; i < 3; i++) for (j = 0; j < 4; j++) mix((uint32_t){P}g2d[i][j]);')
        return self.tail(L, vars_ + sc)

    # ------------------------------------------------------------------ program
    def program_feats(self, feats):
        r = self.r
        G = self.base_globals()
        F = []
        extra = [f for f in feats if f != 'basic']
        pick = []
        if extra == ['float']:
            pick = ['float'] * r.randint(2, 3)
        elif extra:
            pick = r.sample(extra, min(len(extra), r.randint(2, 4)))
        nb = (r.randint(1, 2) if extra else r.randint(3, 6)) if 'basic' in feats else 0
        idx = 0
        order = ['basic'] * nb + pick
        r.shuffle(order)
        for f in order:
            if f == 'basic':
                F.append(self.func(idx))
            else:
                F.append(getattr(self, 'feat_' + f)(idx))
            idx += 1
        return '\n'.join(G + self.G), F, pick


# ---------------------------------------------------------------------- float
FCMPS = ['<', '<=', '>', '>=', '==', '!=']


def flit(v):
    t = f'{v:.9g}'
    if not any(c in t for c in '.en'):
        t += '.0'
    return t + 'f'


def fconst(r):
    """a float constant (f suffix: single precision on the host too)"""
    k = r.random()
    if k < 0.3:
        return r.choice(['0.0f', '-0.0f', '1.0f', '-1.0f', '0.5f', '2.0f', '3.0f', '10.0f',
                         '0.1f', '100.0f', '1e10f', '-1e-10f', '1.5e-40f', '3.4e38f',
                         '0x1.8p-3f', '0x1p-126f', '255.0f', '65535.0f', '-32768.0f', '7.0f'])
    if k < 0.6:
        return flit(r.randint(-1000, 1000) / r.choice([1, 2, 4, 8, 10, 3]))
    if k < 0.9:
        return flit(r.uniform(-1, 1) * 10 ** r.uniform(-6, 6))
    import struct
    b = r.getrandbits(32) & 0xBFFFFFFF          # no inf/NaN patterns from here
    return flit(struct.unpack('<f', struct.pack('<I', b))[0])


class FloatMixin:
    def float_helpers(self):
        if getattr(self, 'fhelpers', False):
            return
        self.fhelpers = True
        G = self.G
        G.append('static uint32_t FZ_fb(float x) { union { float f; uint32_t u; } v; v.f = x; '
                 'if ((v.u & 0x7FFFFFFFu) > 0x7F800000u) v.u = 0x7FC00000u; return v.u; }')
        G.append('static int32_t FZ_i32(float x) { return x > -2147483520.0f && x < 2147483520.0f ? (int32_t)x : (int32_t)12345; }')
        G.append('static uint32_t FZ_u32(float x) { return x > -1.0f && x < 4294967040.0f ? (uint32_t)x : (uint32_t)77; }')
        G.append('static int16_t FZ_i16(float x) { return x > -32769.0f && x < 32768.0f ? (int16_t)x : (int16_t)99; }')
        G.append('static uint16_t FZ_u16(float x) { return x > -1.0f && x < 65536.0f ? (uint16_t)x : (uint16_t)98; }')
        G.append('static int8_t FZ_i8(float x) { return x > -129.0f && x < 128.0f ? (int8_t)x : (int8_t)97; }')
        G.append('static uint8_t FZ_u8(float x) { return x > -1.0f && x < 256.0f ? (uint8_t)x : (uint8_t)96; }')
        G.append('static float FZ_cn(float x) { union { float f; uint32_t u; } v; v.f = x; '
                 'if ((v.u & 0x7FFFFFFFu) > 0x7F800000u) v.u = 0x7FC00000u; return v.f; }')
        G.append('#define FZ_OK16(x) ((x) > -32769.0f && (x) < 32768.0f)')
        G.append('#define FZ_OK32(x) ((x) > -2147483520.0f && (x) < 2147483520.0f)')
        G.append('static float FZ_vsum(int16_t n, ...) { va_list ap; float s = 0.0f; va_start(ap, n); '
                 'while (n-- > 0) s = s * 0.5f + (float)va_arg(ap, double); va_end(ap); return s; }')

    def fexpr(self, fv, iv, d):
        """a float expression over float variables fv and integer variables iv (no side
        effects)"""
        r = self.r
        if d <= 0 or r.random() < 0.15:
            k = r.random()
            if k < 0.45 and fv:
                return r.choice(fv)
            if k < 0.7 or not iv:
                return fconst(r)
            n, t = r.choice(iv)
            return f'(float)({tn(t)}){n}'
        k = r.random()
        if k < 0.5:
            op = r.choice('+-*/' if r.random() < 0.8 else '**+-')
            return f'({self.fexpr(fv, iv, d - 1)} {op} {self.fexpr(fv, iv, d - 1)})'
        if k < 0.58:
            return f'(- {self.fexpr(fv, iv, d - 1)})'
        if k < 0.68:
            return f'({self.fcond(fv, iv, d - 1)} ? {self.fexpr(fv, iv, d - 1)} : {self.fexpr(fv, iv, d - 1)})'
        if k < 0.78 and iv:
            t = r.choice(list(TYPES))
            return f'(float){self.expr(t, iv, d - 1)}'
        if k < 0.85:
            return f'(dbl)({self.fexpr(fv, iv, d - 1)})'
        if k < 0.92 and hasattr(self, 'fcalls'):
            f, ar = r.choice(self.fcalls)
            args = [self.fexpr(fv, iv, d - 2) if a == 'f' else self.expr('i16', iv, 1) for a in ar]
            return f'{f}({", ".join(args)})'
        return f'({self.fexpr(fv, iv, d - 1)} * {fconst(r)})'

    def fcond(self, fv, iv, d):
        r = self.r
        k = r.random()
        if k < 0.6:
            c = f'({self.fexpr(fv, iv, d)} {r.choice(FCMPS)} {self.fexpr(fv, iv, d)})'
        elif k < 0.75:
            c = f'({self.fexpr(fv, iv, d)})'           # nonzero (NaN is true, -0 false)
        elif k < 0.85:
            c = f'!({self.fexpr(fv, iv, d)})'
        else:
            c = self.cond(iv, max(d - 1, 0)) if iv else '1'
        if r.random() < 0.2 and d > 0:
            c = f'({c} {r.choice(["&&", "||"])} {self.fcond(fv, iv, d - 1)})'
        return c

    def fconv(self, n, t, fe):
        return f'    {n} = ({tn(t)})FZ_{t}({fe});'

    def feat_float(self, idx):
        r = self.r
        P = f'F{idx}_'
        G = self.G
        self.float_helpers()
        nfa = r.randint(4, 9)
        G.append(f'static float {P}ga[{nfa}] = {{ {", ".join(fconst(r) for _ in range(r.randint(1, nfa)))} }};')
        G.append(f'static dbl {P}gd = {fconst(r)};')
        G.append(f'static const float {P}kc = {fconst(r)};')
        G.append(f'struct {P}S {{ float x; int16_t k; dbl y; uint8_t c; float z[2]; }};')
        G.append(f'static struct {P}S {P}gs[2] = {{ {{ {fconst(r)}, {r.randint(-99, 99)}, {fconst(r)}, 7, {{ {fconst(r)}, {fconst(r)} }} }}, '
                 f'{{ {fconst(r)}, 3 }} }};')
        # helpers with float parameters and results
        G.append(f'static float {P}h1(float a, dbl b, int16_t c) {{ return a * b - (float)c * {fconst(r)}; }}')
        G.append(f'static dbl {P}h2(dbl a) {{ return a > {fconst(r)} ? a / {fconst(r)} : a + {fconst(r)}; }}')
        G.append(f'static float {P}rec(int16_t n, float x) {{ n &= 15; return n == 0 ? x : {P}rec(n - 1, x * {fconst(r)} + (float)n); }}')
        G.append(f'static struct {P}S {P}mk(float a, int16_t k) {{ struct {P}S s; s.x = a; s.k = k; s.y = a * 0.5f; s.c = (uint8_t)k; '
                 f's.z[0] = -a; s.z[1] = (float)k; return s; }}')
        G.append(f'static float {P}sx(struct {P}S s) {{ return s.x + s.y - s.z[1] + (float)s.c; }}')
        G.append(f'static float (*{P}fp)(float, dbl, int16_t) = {P}h1;')
        self.fcalls = [(f'{P}h1', 'ffi'), (f'{P}h2', 'f'), (f'{P}rec', 'if'), (f'(*{P}fp)', 'ffi'),
                       ('FZ_vsum', None)]
        self.fcalls = [(f, a) for f, a in self.fcalls if a]
        L = self.head(idx)
        ivars = self.scalars(L, r.randint(2, 4))
        nf = r.randint(3, 6)
        fvars = []
        for k in range(nf):
            L.append(f'    {"float" if k == 0 or r.random() < 0.7 else "dbl"} f{k} = {self.fexpr(fvars, ivars, 2)};')
            fvars.append(f'f{k}')
        L.append('    float fa[6], *pf = &f0;')
        L.append(f'    struct {P}S st = {P}gs[0], *ps = &{P}gs[1];')
        L.append('    char buf[200];')
        L.append('    const char *s;')
        L.append('    H = 0;')
        L.append(f'    for (i = 0; i < 6; i++) fa[i] = {self.fexpr(fvars, ivars + [("i", "i16")], 2)};')
        allf = fvars + ['fa[3]', '*pf', 'st.x', 'ps->y', f'{P}ga[1]', f'{P}gd', f'{P}kc', 'st.z[1]']
        wr = fvars + ['fa[2]', '*pf', 'st.x', 'ps->y', f'{P}ga[0]', f'{P}gd', 'st.z[0]', 'pf[0]']
        for _ in range(r.randint(7, 14)):
            k = r.random()
            if k < 0.25:
                L.append(f'    {r.choice(wr)} = {self.fexpr(allf, ivars, 3)};')
            elif k < 0.37:
                L.append(f'    {r.choice(wr)} {r.choice(["+=", "-=", "*=", "/="])} {self.fexpr(allf, ivars, 2)};')
            elif k < 0.43:
                v = r.choice(fvars + ['fa[1]', 'st.x'])
                L.append(f'    {r.choice(["++" + v, v + "++", "--" + v, v + "--"])};')
                L.append(f'    mix(FZ_fb({v}++)); mix(FZ_fb(--{v}));')
            elif k < 0.55:
                n, t = r.choice(ivars)
                L.append(self.fconv(n, t, self.fexpr(allf, ivars, 2)))
            elif k < 0.6:
                v = r.choice(fvars)
                n, t = r.choice(ivars)
                L.append(f'    if (FZ_OK16({v})) {n} = ({tn(t)})(int16_t){v}; else {n} = ({tn(t)})FZ_OK32({v});')
            elif k < 0.67:
                L.append(f'    if ({self.fcond(allf, ivars, 2)}) {r.choice(wr)} = {self.fexpr(allf, ivars, 2)}; '
                         f'else mix(FZ_fb({self.fexpr(allf, ivars, 2)}));')
            elif k < 0.72:
                a, b = self.fexpr(allf, ivars, 2), self.fexpr(allf, ivars, 2)
                L.append(f'    {{ float x = {a}, y = {b}; mix((uint32_t)((x < y) | (x <= y) << 1 | (x > y) << 2 | '
                         f'(x >= y) << 3 | (x == y) << 4 | (x != y) << 5 | (!x) << 6 | ((_Bool)y) << 7)); }}')
            elif k < 0.77:
                c = fconst(r)
                L.append(f'    {{ float t; int16_t n = 0; for (t = {self.fexpr(allf, ivars, 1)}; t < {c} && n < 9; t += 1.25f, n++) '
                         f'fa[n % 6] = fa[(n + 1) % 6] * t + {c}; mix((uint32_t)n); mix(FZ_fb(t)); }}')
            elif k < 0.82:
                g = r.choice(list(TYPES))
                n, t = r.choice(ivars)
                L.append(f'    {r.choice(wr)} = (float)ga_{g}[{r.randint(0, 30)}] + (dbl){n};')
            elif k < 0.86:
                L.append(f'    st = {P}mk({self.fexpr(allf, ivars, 2)}, {self.expr("i16", ivars, 1)}); mix(FZ_fb({P}sx(st)));')
                L.append(f'    {P}gs[1] = st; mix(FZ_fb({P}gs[1].z[0]));')
            elif k < 0.9:
                args = [self.fexpr(allf, ivars, 1) for _ in range(r.randint(0, 5))]
                L.append(f'    mix(FZ_fb(FZ_vsum({len(args)}{"".join(", " + a for a in args)})));')
            elif k < 0.95:
                fmt, args = self.ffmt(allf, ivars)
                L.append(f'    mix((uint32_t)sprintf(buf, "{fmt}"{"".join(", " + a for a in args)}));')
                L.append('    for (s = buf; *s; s++) mix((uint8_t)*s);')
            else:
                L.append(f'    {{ int16_t t = (int16_t)({self.expr("i16", ivars, 1)} & 0xFF); t += (float)(int16_t)({self.expr("i16", ivars, 1)} & 0xFF) * 0.5f; '
                         f't *= 1.5f; mix((uint32_t)t); }}')
        for v in fvars + ['fa[0]', 'fa[5]', 'st.x', 'st.y', 'st.z[1]', f'{P}ga[0]', f'{P}gd',
                          f'{P}gs[1].y']:
            L.append(f'    mix(FZ_fb({v}));')
        return self.tail(L, ivars)

    def ffmt(self, allf, ivars):
        r = self.r
        fmt, args = [], []
        for _ in range(r.randint(1, 3)):
            flags = ''.join(c for c in '-+ #0' if r.random() < 0.15)
            w = str(r.randint(1, 20)) if r.random() < 0.3 else ''
            p = '.' + str(r.randint(0, 12)) if r.random() < 0.6 else ''
            fmt.append(f'%{flags}{w}{p}{r.choice("feEgG")}|')
            # (a NaN printed as one NaN: gcc folds 0/0 to +NaN, its SSE code gives -NaN)
            args.append(f'(double)FZ_cn({self.fexpr(allf, ivars, 2)})')
        return ''.join(fmt), args


FGen.__bases__ = FGen.__bases__ + (FloatMixin,)


def OPS_UP(r):
    return r.choice(LOWOPS).upper()
