"""IR optimisation passes: CFG clean-up, constant and copy propagation with folding and
algebraic simplification, strength reduction of multiplies/divides by constants and of
induction-variable multiplies in loops (array indexing), dead-code removal."""
from .ir import V, Imm, Sym, Frame, Ins, Block
from .front import fold
from . import fp

COMMUT = {'add', 'mul', 'and', 'or', 'xor'}
SWAPCC = {'eq': 'eq', 'ne': 'ne', 'ult': 'ugt', 'ugt': 'ult', 'ule': 'uge', 'uge': 'ule',
          'slt': 'sgt', 'sgt': 'slt', 'sle': 'sge', 'sge': 'sle'}
ARITH = {'add', 'sub', 'mul', 'udiv', 'sdiv', 'umod', 'smod', 'and', 'or', 'xor', 'shl',
         'ushr', 'sshr'}


def const(o):
    return isinstance(o, (Imm, Sym, Frame))


# ---------------------------------------------------------------------- CFG
def preds(f):
    for b in f.blocks:
        b.preds = []
    for b in f.blocks:
        for s in b.succ():
            s.preds.append(b)


def cleanup_cfg(f):
    changed = True
    while changed:
        changed = False
        # every block must end with a terminator (falls through to the next otherwise)
        for i, b in enumerate(f.blocks):
            if not b.term:
                nxt = f.blocks[i + 1] if i + 1 < len(f.blocks) else None
                if nxt is None:
                    b.ins.append(Ins('ret', a=None))
                else:
                    b.ins.append(Ins('jmp', t=nxt))
        # jump threading: a block that only jumps
        fwd = {}
        for b in f.blocks:
            if len(b.ins) == 1 and b.ins[0].op == 'jmp' and b.ins[0].x['t'] is not b and b is not f.blocks[0]:
                fwd[b] = b.ins[0].x['t']

        def res(t):
            seen = set()
            while t in fwd and t not in seen:
                seen.add(t)
                t = fwd[t]
            return t
        for b in f.blocks:
            t = b.term
            if t.op == 'jmp':
                n = res(t.x['t'])
                if n is not t.x['t']:
                    t.x['t'] = n
                    changed = True
            elif t.op == 'br':
                for k in ('t', 'f'):
                    n = res(t.x[k])
                    if n is not t.x[k]:
                        t.x[k] = n
                        changed = True
                if t.x['t'] is t.x['f']:
                    b.ins[-1] = Ins('jmp', t=t.x['t'])
                    changed = True
            elif t.op == 'sw':
                t.x['cases'] = [(v, res(l)) for v, l in t.x['cases']]
                t.x['default'] = res(t.x['default'])
        # unreachable blocks
        reach = set()
        stack = [f.blocks[0]]
        while stack:
            b = stack.pop()
            if b in reach:
                continue
            reach.add(b)
            stack.extend(b.succ())
        nb = [b for b in f.blocks if b in reach]
        if len(nb) != len(f.blocks):
            changed = True
        f.blocks = nb
        # merge a block into its only predecessor that jumps to it
        preds(f)
        for b in list(f.blocks):
            if b is f.blocks[0] or len(b.preds) != 1:
                continue
            p = b.preds[0]
            if p is b or p.term.op != 'jmp' or p not in f.blocks:
                continue
            p.ins.pop()
            p.ins.extend(b.ins)
            f.blocks.remove(b)
            for s in b.succ():
                s.preds = [p if x is b else x for x in s.preds]
            changed = True
            break
    preds(f)


# ---------------------------------------------------------------------- local propagation
def simplify(ins):
    """algebraic simplification of one instruction (in place / returns a replacement)"""
    op = ins.op
    if op in COMMUT and const(ins.a) and not const(ins.b):
        ins.a, ins.b = ins.b, ins.a
    if op in ARITH:
        a, b = ins.a, ins.b
        size = ins.d.size
        if isinstance(a, Imm) and isinstance(b, Imm):
            v = fold(op, a.val, b.val if op not in ('shl', 'ushr', 'sshr') else b.val & 0xFFFF, size)
            if v is not None:
                return Ins('mov', ins.d, Imm(v, size))
        if isinstance(b, Imm):
            k = b.val
            m = (1 << (8 * size)) - 1
            if op in ('add', 'sub', 'or', 'xor', 'shl', 'ushr', 'sshr') and k == 0:
                return Ins('mov', ins.d, a)
            if op == 'mul' and k == 1 or op in ('udiv', 'sdiv') and k == 1:
                return Ins('mov', ins.d, a)
            if op in ('mul', 'and') and k == 0:
                return Ins('mov', ins.d, Imm(0, size))
            if op == 'and' and k == m:
                return Ins('mov', ins.d, a)
            if op == 'or' and k == m:
                return Ins('mov', ins.d, Imm(m, size))
            if op == 'mul' and k & (k - 1) == 0:
                return Ins('shl', ins.d, a, Imm(k.bit_length() - 1))
            if op == 'udiv' and k & (k - 1) == 0:
                return Ins('ushr', ins.d, a, Imm(k.bit_length() - 1))
            if op == 'umod' and k & (k - 1) == 0:
                return Ins('and', ins.d, a, Imm(k - 1, size))
            if op in ('shl', 'ushr') and k >= 8 * size:
                return Ins('mov', ins.d, Imm(0, size))
            if op == 'sub' and size == 2 and not isinstance(a, Imm):
                return Ins('add', ins.d, a, Imm((-k) & m, size))
        if isinstance(a, Imm) and a.val == 0 and op in ('shl', 'ushr', 'sshr', 'udiv', 'sdiv', 'umod', 'smod'):
            return Ins('mov', ins.d, Imm(0, size))
        if op == 'sub' and a is b:
            return Ins('mov', ins.d, Imm(0, size))
        if op in ('xor',) and a is b:
            return Ins('mov', ins.d, Imm(0, size))
        if op in ('and', 'or') and a is b:
            return Ins('mov', ins.d, a)
    if op in fp.OPS and isinstance(ins.a, Imm) and isinstance(ins.b, Imm):
        return Ins('mov', ins.d, Imm(fp.OPS[op](ins.a.val, ins.b.val), 4))
    if op == 'fmul' and (ins.b == Imm(0x40000000, 4) or ins.a == Imm(0x40000000, 4)):
        # x * 2.0 = x + x, exactly (NaN, infinities, zeros, denormals alike): an add is
        # three times quicker than a multiply
        x = ins.a if ins.b == Imm(0x40000000, 4) else ins.b
        return Ins('fadd', ins.d, x, x)
    if op in ('ltof', 'ultof', 'ftol', 'ftoul') and isinstance(ins.a, Imm):
        v = ins.a.val
        if op == 'ltof':
            r = fp.from_int(v - (1 << 32) if v >> 31 else v)
        elif op == 'ultof':
            r = fp.from_int(v)
        else:
            r = fp.to_int(v, signed=op == 'ftol')
        return Ins('mov', ins.d, Imm(r, 4))
    if op == 'fcmp' and isinstance(ins.a, Imm) and isinstance(ins.b, Imm):
        return Ins('mov', ins.d, Imm(fp.cmp(ins.a.val, ins.b.val)))
    if op in ('zx', 'sx', 'tr', 'x8u', 'x8s', 'neg', 'com') and isinstance(ins.a, Imm):
        v = ins.a.val
        if op == 'sx' and v & 0x8000:
            v |= 0xFFFF0000
        elif op == 'tr':
            v &= 0xFFFF
        elif op == 'x8u':
            v &= 0xFF
        elif op == 'x8s':
            v &= 0xFF
            if v & 0x80:
                v |= 0xFF00
        elif op == 'neg':
            v = -v
        elif op == 'com':
            v = ~v
        return Ins('mov', ins.d, Imm(v, ins.d.size))
    if op in ('zx', 'tr') and isinstance(ins.a, Sym) and op == 'tr':
        return Ins('mov', ins.d, ins.a)
    if op == 'br':
        a, b = ins.a, ins.b
        if const(a) and not const(b):
            ins.a, ins.b = b, a
            ins.x['cc'] = SWAPCC[ins.x['cc']]
            a, b = ins.a, ins.b
        if isinstance(a, Imm) and isinstance(b, Imm):
            r = cmp(ins.x['cc'], a.val, b.val, a.size)
            return Ins('jmp', t=ins.x['t'] if r else ins.x['f'])
        if a is b:
            r = ins.x['cc'] in ('eq', 'ule', 'uge', 'sle', 'sge')
            return Ins('jmp', t=ins.x['t'] if r else ins.x['f'])
        cc = ins.x['cc']
        if isinstance(b, Imm):
            m = (1 << (8 * b.size)) - 1
            k = b.val
            # x <= k -> x < k+1 ; x > k -> x >= k+1 (a cheaper test on the 65816)
            if cc == 'ule' and k < m:
                ins.x['cc'], ins.b = 'ult', Imm(k + 1, b.size)
            elif cc == 'ugt' and k < m:
                ins.x['cc'], ins.b = 'uge', Imm(k + 1, b.size)
            elif cc == 'ult' and k == 1:
                ins.x['cc'], ins.b = 'eq', Imm(0, b.size)
            elif cc == 'uge' and k == 1:
                ins.x['cc'], ins.b = 'ne', Imm(0, b.size)
            elif cc == 'sle' and k != (m >> 1):
                ins.x['cc'], ins.b = 'slt', Imm(k + 1, b.size)
            elif cc == 'sgt' and k != (m >> 1):
                ins.x['cc'], ins.b = 'sge', Imm(k + 1, b.size)
            elif cc == 'ult' and k == 0:
                return Ins('jmp', t=ins.x['f'])
            elif cc == 'uge' and k == 0:
                return Ins('jmp', t=ins.x['t'])
            elif cc == 'ugt' and k == 0:
                ins.x['cc'] = 'ne'
            elif cc == 'ule' and k == 0:
                ins.x['cc'] = 'eq'
    return ins


def cmp(cc, a, b, size):
    bits = 8 * size

    def s(v):
        return v - (1 << bits) if v >> (bits - 1) else v
    if cc.startswith('s'):
        a, b = s(a), s(b)
        cc = cc[1:]
    elif cc.startswith('u'):
        cc = cc[1:]
    return {'eq': a == b, 'ne': a != b, 'lt': a < b, 'le': a <= b, 'gt': a > b, 'ge': a >= b}[cc]


def local_prop(f):
    """per block: constant and copy propagation, folding; address-mode folding
    (p = &sym[i] -> sym,x; p = q + k -> (q),y), byte stores of a narrowed value, and
    16 x 16 -> 32 multiplies of extended values"""
    changed = False
    for b in f.blocks:
        known = {}   # V -> operand (Imm / Sym / Frame / V)
        addr = {}    # V -> (base, idx, off): V == base + idx + off
        narrow = {}  # V -> V: V = x8u/x8s(src)
        ext = {}     # V(4) -> ('sx'|'zx', V(2))
        loads = {}   # (base, idx, off, sz, sgn) -> V holding that memory value
        out = []

        def kill(d):
            for m in (known, addr, narrow, ext):
                m.pop(d, None)
            for k in [k for k, v in known.items() if v is d]:
                del known[k]
            for k in [k for k, v in addr.items() if d is v[0] or d is v[1]]:
                del addr[k]
            for k in [k for k, v in narrow.items() if v is d]:
                del narrow[k]
            for k in [k for k, v in ext.items() if v[1] is d]:
                del ext[k]
            for k in [k for k, v in loads.items() if v is d or k[0] is d or k[1] is d]:
                del loads[k]
        for ins in b.ins:
            def sub(o):
                if isinstance(o, V) and o in known:
                    r = known[o]
                    if r.size == o.size:
                        return r
                return o
            before = repr(ins)
            ins.subst(sub)
            n = simplify(ins)
            # address-mode folding for loads and stores through a pointer register
            if n.op in ('ld', 'st') and isinstance(n.x['base'], V) and n.x['base'] in addr and \
                    n.x['base'].size == 2:
                base, idx, off = addr[n.x['base']]
                if n.x['idx'] is None or idx is None:
                    noff = n.x['off'] + off
                    if not isinstance(base, V) or 0 <= noff < 0x8000:
                        n.x['base'], n.x['off'] = base, noff
                        if idx is not None:
                            n.x['idx'] = idx
            if n.op == 'st' and n.x['sz'] == 1 and isinstance(n.a, V) and n.a in narrow:
                n.a = narrow[n.a]
            if n.op == 'mul' and n.d.size == 4:
                ea = ext.get(n.a) if isinstance(n.a, V) else None
                eb = ext.get(n.b) if isinstance(n.b, V) else None
                if ea and isinstance(n.b, Imm):
                    k = n.b.val
                    if ea[0] == 'zx' and k <= 0xFFFF or ea[0] == 'sx' and (k <= 0x7FFF or k >= 0xFFFF8000):
                        eb = (ea[0], Imm(k & 0xFFFF))
                if ea and eb and ea[0] == eb[0]:
                    n = Ins('mulu' if ea[0] == 'zx' else 'muls', n.d, ea[1], eb[1])
            if n.op == 'ld' and not n.x.get('vol'):
                key = (n.x['base'], n.x['idx'], n.x['off'], n.x['sz'], n.x.get('sgn'))
                prev = loads.get(key)
                if prev is not None and prev.size == n.d.size and prev is not n.d:
                    n = Ins('mov', n.d, prev)
            if n.op in ('st', 'call', 'copy', 'fcopy', 'zero', 'cop', 'asm') or \
                    (n.op == 'ld' and n.x.get('vol')):
                loads.clear()
            if n is not ins or repr(n) != before:
                changed = True
            ins = n
            for d in ins.defs():
                kill(d)
            if ins.op == 'ld' and not ins.x.get('vol') and ins.d not in (ins.x['base'], ins.x['idx']):
                loads[(ins.x['base'], ins.x['idx'], ins.x['off'], ins.x['sz'], ins.x.get('sgn'))] = ins.d
            d = ins.d
            if ins.op == 'mov' and isinstance(d, V) and d.size == ins.a.size and \
                    (const(ins.a) or (isinstance(ins.a, V) and ins.a is not d)):
                known[d] = ins.a
            if ins.op == 'add' and isinstance(d, V) and d.size == 2:
                a, bb = ins.a, ins.b
                if isinstance(a, Sym) and isinstance(bb, V):
                    a, bb = bb, a
                if isinstance(a, V) and a is not d and isinstance(bb, (Sym, Frame)):
                    addr[d] = (Sym(bb.name) if isinstance(bb, Sym) else Frame(bb.slot), a, bb.off)
                elif isinstance(a, V) and a is not d and isinstance(bb, Imm) and bb.val < 0x8000:
                    if a in addr and addr[a][1] is None:
                        addr[d] = (addr[a][0], None, addr[a][2] + bb.val)
                    else:
                        addr[d] = (a, None, bb.val)
            if ins.op in ('x8u', 'x8s') and isinstance(ins.a, V) and ins.a is not d:
                narrow[d] = ins.a
            if ins.op in ('sx', 'zx') and isinstance(ins.a, V) and ins.a is not d:
                ext[d] = (ins.op, ins.a)
            out.append(ins)
            if ins.is_term:
                break
        b.ins = out
    return changed


def thread_const_branches(f):
    """a block that only tests v against a constant, entered from a block that has
    just set v to a constant: jump straight to the outcome"""
    preds(f)
    changed = False
    for b in f.blocks:
        if len(b.ins) != 1 or b.ins[0].op != 'br':
            continue
        t = b.ins[0]
        if not isinstance(t.a, V) or not isinstance(t.b, Imm):
            continue
        for p in list(b.preds):
            pt = p.term
            if pt is None or pt.op != 'jmp' or pt.x['t'] is not b:
                continue
            k = None
            for ins in reversed(p.ins[:-1]):
                if t.a in ins.defs():
                    if ins.op == 'mov' and isinstance(ins.a, Imm) and ins.a.size == t.b.size:
                        k = ins.a.val
                    break
            if k is None:
                continue
            r = cmp(t.x['cc'], k, t.b.val, t.b.size)
            pt.x['t'] = t.x['t'] if r else t.x['f']
            changed = True
    if changed:
        cleanup_cfg(f)
    return changed


# ---------------------------------------------------------------------- liveness
def liveness(f):
    """live_in / live_out sets per block (of V)"""
    use, defs = {}, {}
    for b in f.blocks:
        u, d = set(), set()
        for ins in b.ins:
            for x in ins.uses():
                if x not in d:
                    u.add(x)
            for x in ins.defs():
                d.add(x)
        use[b], defs[b] = u, d
    lin = {b: set() for b in f.blocks}
    lout = {b: set() for b in f.blocks}
    changed = True
    order = list(reversed(f.blocks))
    while changed:
        changed = False
        for b in order:
            o = set()
            for s in b.succ():
                o |= lin[s]
            i = use[b] | (o - defs[b])
            if o != lout[b] or i != lin[b]:
                lout[b], lin[b] = o, i
                changed = True
    return lin, lout


def dead_selfuse(f):
    """a value used only to compute itself (an induction variable left after test
    replacement) is dead: remove its definitions"""
    other = set()
    defs = {}
    for b in f.blocks:
        for ins in b.ins:
            ds = ins.defs()
            for u in ins.uses():
                if u not in ds or ins.side_effect:
                    other.add(u)
            for d in ds:
                defs.setdefault(d, []).append(ins)
    dead = [v for v in defs if v not in other and v.param is None and
            not any(i.side_effect for i in defs[v])]
    if not dead:
        return False
    ds = set(dead)
    for b in f.blocks:
        b.ins = [i for i in b.ins if not (set(i.defs()) & ds)]
    return True


def dce(f):
    changed = True
    any_ = False
    if dead_selfuse(f):
        any_ = True
    while changed:
        changed = False
        lin, lout = liveness(f)
        for b in f.blocks:
            live = set(lout[b])
            keep = []
            for ins in reversed(b.ins):
                ds = ins.defs()
                if ds and not ins.side_effect and not (set(ds) & live):
                    changed = True
                    any_ = True
                    continue
                if ins.op == 'mov' and ins.d is ins.a:
                    changed = True
                    continue
                for d in ds:
                    live.discard(d)
                for u in ins.uses():
                    live.add(u)
                keep.append(ins)
            b.ins = list(reversed(keep))
    return any_


# ---------------------------------------------------------------------- loops
def dominators(f):
    blocks = f.blocks
    idx = {b: i for i, b in enumerate(blocks)}
    allb = set(blocks)
    dom = {b: set(allb) for b in blocks}
    dom[blocks[0]] = {blocks[0]}
    changed = True
    while changed:
        changed = False
        for b in blocks[1:]:
            ps = [p for p in b.preds]
            n = set(allb)
            for p in ps:
                n &= dom[p]
            n = n | {b}
            if not ps:
                n = {b}
            if n != dom[b]:
                dom[b] = n
                changed = True
    return dom


def natural_loops(f):
    preds(f)
    dom = dominators(f)
    loops = {}
    for b in f.blocks:
        for s in b.succ():
            if s in dom[b]:            # back edge b -> s
                body = loops.setdefault(s, {s})
                stack = [b]
                while stack:
                    x = stack.pop()
                    if x not in body:
                        body.add(x)
                        stack.extend(x.preds)
    return loops


def set_depths(f):
    loops = natural_loops(f)
    for b in f.blocks:
        b.depth = sum(1 for body in loops.values() if b in body)
    return loops


def strength_reduce(f):
    """induction variables: in a loop where i changes only by i += c, an expression
    t = i * k (or i << s) becomes a variable j kept equal to i * k: j += c * k next to every
    i += c, initialised in a preheader. Then, if i is used only by its updates, the compare
    i < n (n constant) and the multiply, the compare is rewritten on j and i dies."""
    loops = set_depths(f)
    changed = False
    for head, body in loops.items():
        # the loop's entry edges: from outside blocks into head
        outside = [p for p in head.preds if p not in body]
        if len(outside) != 1:
            continue
        pre = outside[0]
        if pre.term.op != 'jmp' and len(pre.succ()) != 1:
            # a conditional entry (rotated loop): insert a preheader block
            ph = Block(head.label + '_pre')
            ph.depth = pre.depth
            ph.ins = [Ins('jmp', t=head)]
            t = pre.term
            for k in ('t', 'f'):
                if t.x.get(k) is head:
                    t.x[k] = ph
            if t.op == 'jmp':
                t.x['t'] = ph
            f.blocks.insert(f.blocks.index(head), ph)
            pre = ph
        # basic induction variables: every def inside the loop is v = v + Imm
        defs = {}
        for b in body:
            for ins in b.ins:
                for d in ins.defs():
                    defs.setdefault(d, []).append(ins)
        ivs = {}
        for v, ds in defs.items():
            if v.size != 2:
                continue
            if all(i.op == 'add' and i.a is v and i.d is v and isinstance(i.b, Imm) for i in ds):
                ivs[v] = ds
        if not ivs:
            continue
        # candidate multiplies: t = iv * k / iv << s, inside the loop
        for b in body:
            for n, ins in enumerate(b.ins):
                if ins.op not in ('mul', 'shl') or ins.a not in ivs or not isinstance(ins.b, Imm):
                    continue
                if ins.d.size != 2:
                    continue
                iv = ins.a
                k = ins.b.val if ins.op == 'mul' else 1 << ins.b.val
                if k in (0, 1):
                    continue
                j = f.newv(2, (iv.name or 'iv') + 'x')
                # j = iv * k in the preheader; j += c*k after every update of iv
                pre.ins.insert(len(pre.ins) - 1, Ins(ins.op, j, iv, ins.b))
                for upd in ivs[iv]:
                    for bb in body:
                        if upd in bb.ins:
                            p = bb.ins.index(upd)
                            bb.ins.insert(p + 1, Ins('add', j, j, Imm((upd.b.val * k) & 0xFFFF)))
                b.ins[b.ins.index(ins)] = Ins('mov', ins.d, j)
                changed = True
                f.sr_pairs = getattr(f, 'sr_pairs', []) + [(iv, j, k, body)]
    if changed:
        lftr(f)
    return changed


def lftr(f):
    """linear-function test replacement: iv used only in its updates and in compares with a
    constant -> compare j (= iv * k) with constant * k instead (unsigned, no overflow)."""
    for iv, j, k, body in getattr(f, 'sr_pairs', []):
        uses = []
        for b in body:
            for ins in b.ins:
                if iv in ins.uses():
                    uses.append((b, ins))
        ok = True
        cmps = []
        for b, ins in uses:
            if ins.op == 'add' and ins.a is iv and ins.d is iv:
                continue
            if b in body and ins.op in ('mul', 'shl') and ins.a is iv and ins.d is j:
                continue
            if ins.op == 'br' and b in body and ins.a is iv and isinstance(ins.b, Imm) and \
                    ins.x['cc'] in ('ult', 'uge') and ins.b.val * k <= 0xFFFF:
                cmps.append(ins)
                continue
            if b not in body and ins.op in ('mul', 'shl') and ins.a is iv and \
                    any(ins.d is jj for ii, jj, _, _ in f.sr_pairs if ii is iv):
                continue
            ok = False
            break
        if not ok or not cmps:
            continue
        # iv must also be dead after the loop (it is not live into any exit target)
        lin, lout = liveness(f)
        exits = set()
        for b in body:
            for s in b.succ():
                if s not in body:
                    exits.add(s)
        if any(iv in lin[e] for e in exits):
            continue
        for ins in cmps:
            ins.a = j
            ins.b = Imm(ins.b.val * k)
    f.sr_pairs = []


def iv_unsigned(f):
    """for (i = c0; i < K; i += c) with 0 <= c0, 0 < c, K + c <= 32768 and i changed in
    the loop only by i += c: i stays in 0..K+c-1, so a signed compare of i with a
    constant is the same as an unsigned one (cheaper on the 65816)"""
    loops = natural_loops(f)
    changed = False
    for head, body in loops.items():
        outside = [p for p in head.preds if p not in body]
        defs = {}
        for b in body:
            for ins in b.ins:
                for d in ins.defs():
                    defs.setdefault(d, []).append(ins)
        for v, ds in defs.items():
            if v.size != 2 or not all(i.op == 'add' and i.a is v and isinstance(i.b, Imm) and
                                      0 < i.b.val < 0x100 for i in ds):
                continue
            # the value on entry: the last definition in each outside predecessor chain
            ok = True
            for p in outside:
                c0 = entry_const(p, v)
                if c0 is None or c0 >= 0x8000:
                    ok = False
            if not ok or not outside:
                continue
            step = max(i.b.val for i in ds)
            for b in body:
                t = b.term
                if t is not None and t.op == 'br' and t.a is v and isinstance(t.b, Imm) and \
                        t.x['cc'] in ('slt', 'sge') and 0 < t.b.val and t.b.val + step <= 0x8000:
                    # in the loop, v < bound + step; outside entry values were checked
                    t.x['cc'] = 'u' + t.x['cc'][1:]
                    changed = True
    return changed


def entry_const(b, v, depth=0):
    """the constant v holds at the end of block b (walking up single predecessors)"""
    for ins in reversed(b.ins):
        if v in ins.defs():
            if ins.op == 'mov' and isinstance(ins.a, Imm):
                return ins.a.val
            return None
    if depth < 4 and len(b.preds) == 1:
        return entry_const(b.preds[0], v, depth + 1)
    return None


# ---------------------------------------------------------------------- driver
def optimise(f, level=2):
    cleanup_cfg(f)
    for _ in range(4):
        c1 = local_prop(f)
        c3 = thread_const_branches(f)
        c2 = dce(f)
        cleanup_cfg(f)
        if not (c1 or c2 or c3):
            break
    if level >= 2:
        preds(f)
        iv_unsigned(f)
        if strength_reduce(f):
            for _ in range(3):
                c1 = local_prop(f)
                c2 = dce(f)
                cleanup_cfg(f)
                if not (c1 or c2):
                    break
    set_depths(f)
