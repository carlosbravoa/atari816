"""Register allocation: virtual registers -> direct-page locations or hardware-stack slots.

Direct page (bank 0, D = 0):
  __rg+0  .. __rg+SCR-1      scratch registers: caller-saved (any call may change them)
  __rg+SCR .. __rg+SCR+CS-1  callee-saved registers: a function saves the ones it uses
Hardware stack (bank 0, addressed n,s): the frame of slots, the incoming arguments.

A value live across a call goes to a callee-saved register when it is used often
(a loop), else to a stack slot; parameters stay in their incoming argument slot unless
they are used often enough to pay for a copy to the direct page."""
from .ir import V, Imm
from .opt import liveness

SCR = 48       # bytes of scratch registers
# 32-bit ops whose code reads each word of an operand before it writes that word of the
# result (two-word ripple: add, sub, logic; helpers through __h0/__h1; shifts)
SAME_OK = {'add', 'sub', 'and', 'or', 'xor', 'mul', 'udiv', 'sdiv', 'umod', 'smod', 'shl',
           'ushr', 'sshr', 'neg', 'com', 'fadd', 'fsub', 'fmul', 'fdiv', 'ltof', 'ultof',
           'ftol', 'ftoul', 'addlo'}
CS = 48        # bytes of callee-saved registers


def allocate(f):
    lin, lout = liveness(f)
    allv = set(f.params)
    inter = {}
    across = set()

    def addi(a, b):
        if a is b:
            return
        inter.setdefault(a, set()).add(b)
        inter.setdefault(b, set()).add(a)
    moves = []
    twice = set()        # live across a setjmp call (it returns twice)
    sameor = []          # (d, u, weight): coalesce, else they interfere
    weight = {}
    # interference and weights
    for b in f.blocks:
        live = set(lout[b])
        w = 8 ** min(b.depth, 5)
        for ins in reversed(b.ins):
            ds = ins.defs()
            us = ins.uses()
            for v in ds + us:
                allv.add(v)
                weight[v] = weight.get(v, 0) + w
            if ins.op == 'call' or ins.op == 'cop' or ins.op == 'asm':
                for v in live:
                    if v not in ds:
                        across.add(v)
                        if ins.x.get('twice'):
                            twice.add(v)
            for d in ds:
                for v in live:
                    if ins.op == 'mov' and v is ins.a:
                        continue
                    addi(d, v)
                if ins.op != 'mov' and (d.size >= 4 or any(u.size >= 4 for u in us)):
                    for u in us:
                        if ins.op in SAME_OK and d.size >= 4 and u.size == d.size and u is not d:
                            # a 32-bit op that reads each word of u before it writes that
                            # word of d: d may take u's place (never a part of it)
                            sameor.append((d, u, w))
                        else:
                            addi(d, u)
                inter.setdefault(d, set())
            if ins.op == 'mov' and isinstance(ins.a, V) and isinstance(ins.d, V) and ins.a.size == ins.d.size:
                moves.append((ins.d, ins.a, w))
            for d in ds:
                live.discard(d)
            for u in us:
                live.add(u)
        # values live at the entry of the first block: parameters (and undefined ones)
    entry_live = lin[f.blocks[0]] if f.blocks else set()
    params = [p for p in f.params if isinstance(p, V)]
    for p in params:
        for q in params:
            addi(p, q)
        for v in entry_live:
            addi(p, v)
    for v in entry_live:
        for u in entry_live:
            addi(u, v)

    # a value live across setjmp must hold its place until longjmp comes back: from the
    # setjmp to any later call that may longjmp, which the flow graph does not show.
    # It shares its location with nothing (a callee-saved register gets its value at the
    # setjmp back from the jmp_buf; a stack slot keeps the last one).
    for v in twice:
        for u in allv:
            addi(v, u)

    # coalescing (union-find), heaviest moves first
    parent = {}
    moves += [(d, u, w) for d, u, w in sameor]

    def find(v):
        while parent.get(v, v) is not v:
            v = parent[v]
        return v
    for d, a, w in sorted(moves, key=lambda m: -m[2]):
        rd, ra = find(d), find(a)
        if rd is ra:
            continue
        if ra in inter.get(rd, ()):
            continue
        if rd.param is not None and ra.param is not None:
            continue
        # merge rd into ra (keep a parameter as the representative)
        if rd.param is not None:
            rd, ra = ra, rd
        parent[rd] = ra
        for n in inter.pop(rd, set()):
            inter[n].discard(rd)
            if n is not ra:
                inter[n].add(ra)
                inter.setdefault(ra, set()).add(n)
        weight[ra] = weight.get(ra, 0) + weight.get(rd, 0)
        if rd in across:
            across.add(ra)
    # the 32-bit op pairs not coalesced must not share a word
    for d, u, _ in sameor:
        rd, ru = find(d), find(u)
        if rd is not ru:
            inter.setdefault(rd, set()).add(ru)
            inter.setdefault(ru, set()).add(rd)
    groups = {}
    for v in allv:
        groups.setdefault(find(v), []).append(v)
    reps = list(groups)

    # allocation
    loc = {}
    slots_end = 0
    used_cs = set()

    def overlaps(a, b):
        return a[0] < b[1] and b[0] < a[1]

    def busy(v, space):
        r = []
        for n in inter.get(v, ()):
            l = loc.get(n)
            if l and l[0] == space:
                r.append((l[1], l[1] + n.size))
        return r

    def pick(v, space, lo, hi, align=2):
        b = busy(v, space)
        p = lo
        while p + v.size <= hi:
            rng = (p, p + v.size)
            if not any(overlaps(rng, x) for x in b):
                return p
            p += align
        return None
    # a variable an asm statement names (%[name]) lives in a callee-saved register, so
    # that the text can use the scratch ones freely: those first
    asmv = {find(v) for v in allv if v.pinned == 'asm'}
    farbase = {find(i.x['base']) for b in f.blocks for i in b.ins
               if i.op in ('ld', 'st') and isinstance(i.x.get('base'), V) and
               i.x['base'].size == 4}
    order = sorted(reps, key=lambda v: (v not in asmv, -(weight.get(v, 0)), v.id))
    for v in order:
        w = weight.get(v, 0)
        acr = v in across
        if v in asmv:
            p = pick(v, 'dp', SCR, SCR + CS)
            if p is None:
                from .ctypes816 import CError
                raise CError(f"too many variables named in asm statements in "
                             f"{getattr(f, 'cname', f.name)} (they share 48 bytes of "
                             f"registers)")
            loc[v] = ('dp', p)
            for k in range(p, p + v.size, 2):
                used_cs.add(k)
            continue
        if v.param is not None:
            # (a value read and written a few times outside loops is as quick in its
            # argument slot, n,s, as in the direct page: the copy would cost more; not a
            # far pointer, whose [dp],y needs the direct page)
            if acr and w < 16 or not acr and (w < 3 or w < 8 and v not in farbase):
                loc[v] = ('home', v.param)
                continue
        if not acr:
            p = pick(v, 'dp', 0, SCR)
            if p is not None:
                loc[v] = ('dp', p)
                continue
        if acr and w >= 16 or not acr:
            p = pick(v, 'dp', SCR, SCR + CS)
            if p is not None:
                loc[v] = ('dp', p)
                for k in range(p, p + v.size, 2):
                    used_cs.add(k)
                continue
        if v.param is not None:
            loc[v] = ('home', v.param)
            continue
        p = pick(v, 'sr', 0, 1 << 15)
        loc[v] = ('sr', p)
        slots_end = max(slots_end, p + v.size)
    for v in allv:
        r = find(v)
        v.loc = loc[r]
        v.weight = weight.get(r, 0)
    # parameters whose register is not their home: copied in by the prologue
    f.param_copies = [(p, p.loc) for p in params if p.loc[0] != 'home']
    f.frame_size = slots_end
    f.saved = sorted(used_cs)
    return f


# the 65816's stack-relative addressing (n,s and (n,s),y) has an 8-bit offset: a frame
# whose slots, saved registers, return address and arguments lie further than this from
# the stack pointer cannot be reached there
SR_MAX = 255


def sr_reach(lines):
    """the largest n of an n,s or (n,s),y operand in generated lines (0: none)"""
    m = 0
    for l in lines:
        if l[0] == 'I' and l[2]:
            o = l[2]
            if o.startswith('('):
                o = o[1:]
            if o.endswith(',s') or o.endswith(',s),y'):
                n = o.split(',', 1)[0]
                if n.isdigit():
                    m = max(m, int(n))
    return m


def demote_spills(f, keep):
    """a frame too big for n,s: the values allocated to hardware-stack slots at offset
    `keep` or above (allocate() put the heaviest first, at the lowest offsets) move to one
    region of the software-stack frame, laid out as their slots were (values that shared
    a slot did not interfere: they share it there too). Each use becomes a load of the
    value into a new virtual register just before the instruction, each definition a
    store just after; allocate() must run again. -> the number of values moved."""
    from .ir import Frame, FrameSlot, Ins
    moved = {}
    seen = set()
    for b in f.blocks:
        for ins in b.ins:
            for v in ins.uses() + ins.defs():
                if id(v) in seen:
                    continue
                seen.add(id(v))
                if v.loc and v.loc[0] == 'sr' and v.loc[1] + v.size > keep and \
                        v.param is None and v.pinned is None:
                    moved[v] = v.loc[1]
    if not moved:
        return 0
    size = max(off + v.size for v, off in moved.items())
    slot = FrameSlot(f'spill{len(f.slots)}', size)
    f.slots.append(slot)
    for b in f.blocks:
        out = []
        for ins in b.ins:
            loads = {}

            def use(o):
                if isinstance(o, V) and o in moved:
                    t = loads.get(o)
                    if t is None:
                        t = loads[o] = f.newv(o.size, o.name)
                        out.append(Ins('ld', t, base=Frame(slot, moved[o]), idx=None, off=0,
                                       sz=o.size, sgn=False, vol=False))
                    return t
                return o
            ins.subst(use)
            stores = []
            if isinstance(ins.d, V) and ins.d in moved:
                v = ins.d
                t = f.newv(v.size, v.name)
                ins.d = t
                stores.append(Ins('st', a=t, base=Frame(slot, moved[v]), idx=None, off=0,
                                  sz=v.size, vol=False))
            out.append(ins)
            out.extend(stores)
        b.ins = out
    return len(moved)
