"""Peephole optimisation of the generated 65816 code, branch relaxation and output.

Passes (repeated until nothing changes):
  * register-content tracking (A, X, Y): drop loads of a value a register already holds
    and stores of a value memory already holds (keeping loads whose N/Z flags are used);
  * dead stores to direct-page registers (the code generator's liveness markers);
  * jumps to the next label, branches over a jump, rep/sep pairs, clc+adc #1 -> inc;
then conditional branches out of range become an inverted branch over a JMP."""
import re

from .gen import DP_NAMES, INV

BRANCH = {'beq', 'bne', 'bcc', 'bcs', 'bmi', 'bpl', 'bvc', 'bvs', 'bra'}
SETS_NZ = {'lda', 'ldx', 'ldy', 'and', 'ora', 'eor', 'adc', 'sbc', 'cmp', 'cpx', 'cpy', 'inc',
           'dec', 'inx', 'iny', 'dex', 'dey', 'asl', 'lsr', 'rol', 'ror', 'tax', 'tay', 'txa',
           'tya', 'tsc', 'tdc', 'txy', 'tyx', 'pla', 'plx', 'ply', 'xba', 'plp', 'rep', 'sep'}
READS_NZ = {'beq', 'bne', 'bmi', 'bpl', 'php'}
SETS_C = {'adc', 'sbc', 'cmp', 'cpx', 'cpy', 'asl', 'lsr', 'rol', 'ror', 'clc', 'sec', 'plp',
          'rep', 'sep', 'xce'}
READS_C = {'bcc', 'bcs', 'adc', 'sbc', 'rol', 'ror', 'php'}
SETS_V = {'adc', 'sbc', 'bit', 'clv', 'plp', 'rep', 'sep'}
READS_V = {'bvc', 'bvs', 'php'}
WRITES_A = {'lda', 'and', 'ora', 'eor', 'adc', 'sbc', 'txa', 'tya', 'tsc', 'tdc', 'pla', 'xba'}
RMW = {'inc', 'dec', 'asl', 'lsr', 'rol', 'ror', 'tsb', 'trb'}
END = {'rts', 'rtl', 'jmp', 'jml', 'brl', 'bra', 'rti'}


def is_dp(o):
    return any(o == n or o.startswith(n + '+') for n in DP_NAMES)


def plain(o):
    """a trackable memory operand: direct page, absolute (no index), or stack-relative"""
    if not o or o[0] in '#([' or o == 'a':
        return False
    if o.endswith(',x') or o.endswith(',y'):
        return False
    return True


_OVL_SR = re.compile(r'(\d+),s')
_OVL_DP = re.compile(r'([A-Za-z_]\w*)(?:\+(\d+))?')


def overlaps(o):
    """the plain operands whose word shares one byte with o's word (an unaligned access:
    gen.py reads the word at byte 1 or 3 of a 32-bit register): a store to o changes
    them too"""
    m = _OVL_SR.fullmatch(o or '')
    if m:
        n = int(m.group(1))
        return {f'{n - 1},s', f'{n + 1},s'}
    m = _OVL_DP.fullmatch(o or '')
    if m:
        name, n = m.group(1), int(m.group(2) or 0)
        r = {f'{name}+{n + 1}'}
        if n == 1:
            r |= {name, f'{name}+0'}
        elif n > 1:
            r.add(f'{name}+{n - 1}')
        return r
    return set()


def peephole(lines, opt=True):
    if not opt:
        return relax(lines)

    def rounds():
        for _ in range(8):
            ch = False
            ch |= track(lines)
            ch |= dead_dp(lines)
            ch |= dead_a(lines)
            ch |= simple(lines)
            if not ch:
                break
    rounds()
    n = 0
    while n < 8 and xpromote(lines):
        n += 1
        rounds()
    if dead_a_cmp(lines):
        rounds()
    return relax(lines)


def ins_at(lines, i):
    return lines[i] if 0 <= i < len(lines) else None


def flags_needed(lines, i, which):
    """are flags (N/Z: 'nz', carry: 'c') set by instruction i read later?"""
    reads = {'nz': READS_NZ, 'c': READS_C, 'v': READS_V}[which]
    sets = {'nz': SETS_NZ, 'c': SETS_C, 'v': SETS_V}[which]
    for l in lines[i + 1:]:
        if l[0] in ('L', 'ASM'):
            return False
        if l[0] != 'I':
            continue
        m = l[1]
        if m in reads:
            return True
        if m in sets or m in END or m in ('jsr', 'jsl'):
            return False
    return False


def track(lines):
    """forward register-content tracking. A, X, Y each hold a set of operands known to
    equal the register (immediates, direct page, absolute, stack-relative). At a label the
    state is the intersection of the states of every jump to it and of the fall-through
    (iterated to a fixpoint, so loop heads keep what both the entry and the back edge
    agree on)."""
    lab_in = {}
    for _ in range(8):
        rec = {}
        _walk(lines, lab_in, rec)
        new = {}
        for L, sts in rec.items():
            st = sts[0]
            for x in sts[1:]:
                st = tuple(p & q for p, q in zip(st, x))
            new[L] = st
        if new == lab_in:
            break
        lab_in = new
    else:
        lab_in = None            # no fixpoint: every label starts with nothing known
    out, changed = _walk(lines, lab_in, None)
    if changed:
        lines[:] = out
    return changed


EMPTY = (frozenset(), frozenset(), frozenset())


def _walk(lines, lab_in, rec, xstates=None):
    """one pass; lab_in: label -> state (a label absent = not reached yet: top), or
    None (conservative: nothing known at any label)"""
    changed = False
    A, X, Y = set(), set(), set()
    first_label = True
    fall = False
    dead = False         # in code not (yet) known to be reachable
    Z = set()            # memory known to be zero (straight-line only)
    m8 = False
    fa = False           # N/Z reflect the 16-bit A
    A16 = None           # A's 16-bit contents saved at sep (None: changed in 8-bit mode)
    A8 = set()           # operands whose low byte A's low byte equals (8-bit mode)
    out = []
    i = 0
    n = len(lines)

    def drop(pred):
        for R in (A, X, Y):
            for o in [o for o in R if pred(o)]:
                R.discard(o)

    def absolute(o):
        return not o.startswith('#') and not is_dp(o) and not o.endswith(',s')
    while i < n:
        l = lines[i]
        i += 1
        if l[0] == 'L':
            if first_label:
                st = EMPTY
                first_label = False
            elif lab_in is None:
                st = EMPTY
            else:
                cur = None if (dead or not fall) else (frozenset(A), frozenset(X), frozenset(Y))
                if cur is not None and rec is not None:
                    rec.setdefault(l[1], []).append(cur)
                st = lab_in.get(l[1])
                if st is None:
                    st = cur
                elif cur is not None:
                    st = tuple(p & q for p, q in zip(st, cur))
            dead = st is None
            if dead:
                st = EMPTY
            A, X, Y = set(st[0]), set(st[1]), set(st[2])
            Z = set()
            m8 = False
            fa = False
            fall = True
            out.append(l)
            continue
        if l[0] == 'ASM':
            # inline assembly: nothing known after it (registers, memory), flow goes on
            A, X, Y = set(), set(), set()
            Z = set()
            m8 = False
            fa = False
            A16, A8 = None, set()
            fall = True
            out.append(l)
            continue
        if l[0] == 'D':
            if rec is not None and l[1].startswith('.addr '):
                rec.setdefault(l[1][6:], []).append(EMPTY)
            A, X, Y = set(), set(), set()
            m8 = False
            fa = False
            fall = False
            out.append(l)
            continue
        if l[0] != 'I':
            out.append(l)
            continue
        m, o = l[1], l[2]
        if xstates is not None:
            xstates[i - 1] = (set(X), set(A), dead)
        if rec is not None and not dead and (m in BRANCH or m in ('jmp', 'brl')) and not o.startswith('('):
            rec.setdefault(o, []).append((frozenset(A), frozenset(X), frozenset(Y)))
        fall = m not in END
        prev_fa = fa
        if m in ('lda', 'and', 'ora', 'eor', 'adc', 'sbc', 'txa', 'tya', 'pla', 'tax', 'tay') and not m8:
            fa = True
        elif m in SETS_NZ or m in ('jsr', 'jsl', 'cop', 'bit', 'tsb', 'trb', 'mvn', 'mvp') or m8:
            fa = False
        if m8 and m == 'lda' and o in A8 and (plain(o) or o.startswith('#')) and \
                not flags_needed(lines, i - 1, 'nz'):
            changed = True
            continue
        if m8 and (m in WRITES_A or m in ('inc', 'dec', 'asl', 'lsr', 'rol', 'ror') and o in ('a', '')):
            A16 = None
            A8 = set()
            if m == 'lda' and (plain(o) or o.startswith('#')):
                A8 = {o}
        if m in ('pha', 'pla', 'phx', 'plx', 'phy', 'ply', 'pei', 'pea', 'tcs', 'jsr', 'jsl', 'phd', 'php',
                 'plp', 'phb', 'plb', 'phk'):
            if m == 'pei' and not m8 and o[1:-1] in A:
                l = ('I', 'pha', '')
                m, o = 'pha', ''
                changed = True
            drop(lambda x: x.endswith(',s'))
        if m == 'sep':
            if o == '#$20':
                if m8:
                    changed = True
                    continue
                m8 = True
                A16 = set(A)
                A8 = set(A)
                A = set()
            out.append(l)
            continue
        if m == 'rep':
            if o == '#$20':
                if not m8:
                    changed = True
                    continue
                m8 = False
                A = set(A16) if A16 is not None else set()
                A16 = None
                A8 = set()
            out.append(l)
            continue
        trackable = plain(o) or o.startswith('#')
        if m in ('lda', 'ldx', 'ldy') and not m8 and o in Z and \
                not any(o in R for R in (A, X, Y)):
            l = ('I', m, '#$0000')
            o = '#$0000'
            changed = True
        if (m in ('sta', 'stx', 'sty', 'stz') or m in RMW) and plain(o):
            ov = overlaps(o)
            Z -= ov
            for S in (A, X, Y):
                S -= ov
        if m == 'stz' and not m8 and plain(o):
            Z.add(o)
        elif m in ('sta', 'stx', 'sty', 'stz') or m in RMW:
            Z.discard(o)
            if not plain(o):
                Z.clear()
        if m in ('jsr', 'jsl', 'cop', 'mvn', 'mvp'):
            Z.clear()
        if m in ('lda', 'ldx', 'ldy') and (m != 'lda' or not m8):
            R = {'lda': A, 'ldx': X, 'ldy': Y}[m]
            if trackable and o in R and (not flags_needed(lines, i - 1, 'nz') or
                                         (m == 'lda' and prev_fa)):
                changed = True
                fa = prev_fa
                continue
            if trackable and not m8 and not o.startswith('#'):
                tr = None
                if m == 'ldx' and o in A:
                    tr, R2 = 'tax', A
                elif m == 'ldy' and o in A:
                    tr, R2 = 'tay', A
                elif m == 'lda' and o in X:
                    tr, R2 = 'txa', X
                elif m == 'lda' and o in Y:
                    tr, R2 = 'tya', Y
                if tr:
                    out.append(('I', tr, ''))
                    R.clear()
                    R |= R2
                    changed = True
                    continue
            out.append(l)
            R.clear()
            if trackable:
                R.add(o)
            continue
        if m in ('sta', 'stx', 'sty', 'stz'):
            R = {'sta': A, 'stx': X, 'sty': Y, 'stz': None}[m]
            if R is not None and not (m8 and m == 'sta') and plain(o) and o in R:
                changed = True
                continue
            out.append(l)
            if plain(o):
                for S in (A, X, Y):
                    if S is not R:
                        S.discard(o)
                if R is not None and not (m8 and m == 'sta'):
                    R.add(o)
                elif R is A:
                    A.discard(o)
            else:
                drop(absolute)
            continue
        out.append(l)
        if m in RMW and o and o != 'a':
            if plain(o):
                drop(lambda x: x == o)
            else:
                drop(absolute)
            continue
        if m in ('mvn', 'mvp'):
            drop(absolute)
            A, X, Y = set(), set(), set()
            continue
        if m == 'tax':
            X = set(A) if not m8 else set()
        elif m == 'tay':
            Y = set(A) if not m8 else set()
        elif m == 'txa':
            if not m8:
                A = set(X)
            else:
                A = set()
        elif m == 'tya':
            A = set(Y) if not m8 else set()
        elif m == 'tyx':
            X = set(Y)
        elif m == 'txy':
            Y = set(X)
        elif m in WRITES_A or m in ('inc', 'dec', 'asl', 'lsr', 'rol', 'ror') and o in ('a', ''):
            A = set()
        if m in ('inx', 'dex', 'plx'):
            X = set()
        if m in ('iny', 'dey', 'ply'):
            Y = set()
        if m in ('jsr', 'jsl', 'cop', 'jmp', 'rts', 'rtl', 'brl', 'bra'):
            A, X, Y = set(), set(), set()
            if m in ('jsr', 'jsl'):
                drop(absolute)
    return out, changed


def fixpoint(lines):
    lab_in = {}
    for _ in range(8):
        rec = {}
        _walk(lines, lab_in, rec)
        new = {}
        for L, sts in rec.items():
            st = sts[0]
            for x in sts[1:]:
                st = tuple(p & q for p, q in zip(st, x))
            new[L] = st
        if new == lab_in:
            return lab_in
        lab_in = new
    return None


X_TOUCH = {'ldx', 'stx', 'inx', 'dex', 'tax', 'txa', 'txy', 'tyx', 'txs', 'tsx', 'phx', 'plx',
           'cpx', 'jsr', 'jsl', 'cop', 'mvn', 'mvp', 'brk', 'rts', 'rtl', 'rti'}


def xpromote(lines):
    """keep a loop's index register (a __rg word) in X for the whole loop"""
    lab = {l[1]: k for k, l in enumerate(lines) if l[0] == 'L'}
    regions = []
    for e, l in enumerate(lines):
        if l[0] == 'I' and (l[1] in BRANCH or l[1] in ('jmp', 'brl')) and l[2] in lab and lab[l[2]] < e:
            regions.append((lab[l[2]], e))
    if not regions:
        return False
    lab_in = fixpoint(lines)
    if lab_in is None:
        return False
    xs = {}
    _walk(lines, lab_in, None, xs)
    regions.sort(key=lambda r: r[1] - r[0])
    for h, e in regions:
        body = range(h + 1, e + 1)
        inside = {lines[k][1] for k in body if lines[k][0] == 'L'} | {lines[h][1]}
        # no jump into the loop from outside (except the fall-through into its head)
        ok = True
        for k, l in enumerate(lines):
            if h <= k <= e:
                continue
            if l[0] == 'I' and l[2] in inside and (l[1] in BRANCH or l[1] in ('jmp', 'brl')):
                ok = False
                break
            if l[0] == 'D' and l[1].startswith('.addr ') and l[1][6:] in inside:
                ok = False
                break
        if not ok or h == 0 or lines[h - 1][0] == 'I' and lines[h - 1][1] in END:
            continue
        cands = {}
        for k in body:
            l = lines[k]
            if l[0] in ('D', 'ASM'):
                ok = False
                break
            if l[0] != 'I':
                continue
            m, o = l[1], l[2]
            if m in X_TOUCH and m != 'ldx':
                ok = False
                break
            if m == 'ldx':
                if _rg(o) is None:
                    ok = False
                    break
                cands.setdefault(o, 0)
        if not ok or len(cands) != 1:
            continue
        v = next(iter(cands))
        ov = overlaps(v)
        for k in body:
            l = lines[k]
            if l[0] == 'I' and any(x in ov for x in re.split(r'[\[\](),]', l[2] or '')):
                ok = False
                break
        for k in body:
            l = lines[k]
            if l[0] != 'I':
                continue
            m, o = l[1], l[2]
            if v in (o or '') and not (o == v and m in ('ldx', 'lda', 'sta', 'inc', 'dec', 'stz')):
                ok = False
                break
            if (o or '').endswith(',x') or (o or '').endswith(',x)'):
                st = xs.get(k)
                if st is None or st[2] or v not in st[0]:
                    ok = False
                    break
        if not ok:
            continue
        # transform
        new = []
        for k, l in enumerate(lines):
            if k == h:
                new.append(('I', 'ldx', v))
            if h < k <= e and l[0] == 'I':
                m, o = l[1], l[2]
                if o == v:
                    rp = {'ldx': None, 'lda': ('txa', ''), 'sta': ('tax', ''), 'inc': ('inx', ''),
                          'dec': ('dex', ''), 'stz': ('ldx', '#$0000')}[m]
                    if rp:
                        new.append(('I',) + rp)
                    continue
                if (m in BRANCH or m in ('jmp', 'brl')) and o not in inside:
                    new.append(('I', 'stx', v))
            new.append(l)
            if k == e:
                new.append(('I', 'stx', v))
        lines[:] = new
        return True
    return False


def dead_a_cmp(lines):
    """txa ; cmp #k -> cpx #k (tya -> cpy) when A is not read afterwards"""
    changed = False
    for k in range(len(lines) - 2):
        l, c = lines[k], lines[k + 1]
        if l[0] == 'I' and l[1] in ('txa', 'tya') and c[0] == 'I' and c[1] == 'cmp' and \
                c[2].startswith('#') and not a_live_after(lines, k + 1):
            lines[k] = ('I', 'cpx' if l[1] == 'txa' else 'cpy', c[2])
            lines[k + 1] = ('LIVE', set())
            changed = True
    return changed


def a_live_after(lines, k, depth=0):
    """is A read after instruction k before being overwritten? (follows branches)"""
    lab = None
    seen = set()
    stack = [k + 1]
    while stack:
        j = stack.pop()
        while j < len(lines):
            if j in seen:
                break
            seen.add(j)
            l = lines[j]
            if l[0] in ('D', 'ASM'):
                return True
            if l[0] != 'I':
                j += 1
                continue
            m, o = l[1], l[2]
            if m in READS_A or m in ('inc', 'dec', 'asl', 'lsr', 'rol', 'ror') and o in ('a', '') \
                    or m in ('sep', 'rep') or (o or '').startswith('('):
                if m not in ('sep', 'rep') or True:
                    return True
            if m in OVERWRITES_A:
                break
            if m in BRANCH or m in ('jmp', 'brl'):
                if lab is None:
                    lab = {x[1]: n for n, x in enumerate(lines) if x[0] == 'L'}
                if o not in lab:
                    return True
                stack.append(lab[o])
                if m in ('jmp', 'brl', 'bra'):
                    break
            j += 1
        else:
            return True
    return False


def _rg(o):
    mm = re.fullmatch(r'__rg\+(\d+)', o or '')
    return int(mm.group(1)) if mm else None


def _rg_all(o):
    r = []
    for mm in re.finditer(r'__rg\+(\d+)', o or ''):
        k = int(mm.group(1))
        r.append(k - (k & 1))
        if k & 1:
            r.append(k + 1)         # (an unaligned word: two registers' bytes)
        if o.startswith('[') or o.startswith('#'):
            # [__rg+k],y reads a 24-bit pointer; #__rg+k is the address of a 32-bit float
            # given to a helper in X, Y or A (gen.py's ...i and ...x entries): both words
            r.append(k - (k & 1) + 2)
    return r


def _uses_defs(m, o):
    """__rg words used / defined by an instruction"""
    if not o or '__rg' not in o:
        return (), ()
    if m in ('sta', 'stz', 'stx', 'sty'):
        k = _rg(o)
        if k is not None and not k & 1:
            return (), (k,)
    return tuple(_rg_all(o)), ()


def dead_dp(lines):
    """remove stores to __rg registers whose value is never read (liveness over the
    function's assembly: labels, branches, fall-through)"""
    from .regalloc import SCR, CS
    ALL = frozenset(range(0, SCR + CS, 2))
    AT_RTS = frozenset(range(SCR, SCR + CS, 2))
    n = len(lines)
    lab = {}
    for k, l in enumerate(lines):
        if l[0] == 'L':
            lab[l[1]] = k
    succ = []
    for k, l in enumerate(lines):
        s = []
        if l[0] == 'I':
            m, o = l[1], l[2]
            if m in BRANCH or m in ('jmp', 'brl'):
                if o in lab:
                    s.append(lab[o])
                else:
                    s.append(-1)          # unknown target: everything live
            if m not in END:
                s.append(k + 1)
            if m in ('rts', 'rtl'):
                s = [-2]
        elif l[0] in ('D', 'ASM'):
            s = [-1]            # (inline assembly: every register taken as live)
        else:
            s = [k + 1]
        succ.append(s)
    live_in = [frozenset()] * (n + 1)
    changed = True
    ud = [(_uses_defs(l[1], l[2]) if l[0] == 'I' else ((), ())) for l in lines]
    while changed:
        changed = False
        for k in range(n - 1, -1, -1):
            out = set()
            for s in succ[k]:
                if s == -1:
                    out |= ALL
                elif s == -2:
                    out |= AT_RTS
                elif s < n:
                    out |= live_in[s]
                else:
                    out |= ALL
            u, d = ud[k]
            inn = (out - set(d)) | set(u)
            if inn != live_in[k]:
                live_in[k] = frozenset(inn)
                changed = True
    keep = []
    removed = False
    for k, l in enumerate(lines):
        if l[0] == 'I' and ud[k][1]:
            out = set()
            for s in succ[k]:
                out |= ALL if s == -1 or s >= n else (AT_RTS if s == -2 else live_in[s])
            if ud[k][1][0] not in out:
                removed = True
                continue
        keep.append(l)
    if removed:
        lines[:] = keep
    return removed


READS_A = {'sta', 'adc', 'sbc', 'and', 'ora', 'eor', 'cmp', 'bit', 'tax', 'tay', 'pha',
           'xba', 'tcs', 'tcd', 'mvn', 'mvp', 'jsr', 'jsl', 'rts', 'cop', 'rtl'}
OVERWRITES_A = {'lda', 'pla', 'txa', 'tya', 'tsc', 'tdc'}


def dead_a(lines):
    """an lda whose value is overwritten before any read (flags unused) is removed"""
    pend = None
    rm = set()
    for k, l in enumerate(lines):
        if l[0] != 'I':
            if l[0] in ('L', 'D', 'ASM'):
                pend = None
            continue
        m, o = l[1], l[2]
        if m in OVERWRITES_A:
            if pend is not None and not flags_needed(lines, pend, 'nz'):
                rm.add(pend)
            pend = k if m == 'lda' else None
            continue
        if m in READS_A or m in BRANCH or m in END or m in ('sep', 'rep') or \
                (m in ('asl', 'lsr', 'rol', 'ror', 'inc', 'dec') and o in ('a', '')):
            pend = None
            continue
    if rm:
        lines[:] = [l for k, l in enumerate(lines) if k not in rm]
        return True
    return False


_PI = __import__('itertools').count()


def _inc32(lines, i):
    """lines[i:i + 7]: clc ; lda R ; adc #$0001 ; sta R ; lda R+2 ; adc #$0000 ; sta R+2 with
    R a direct-page register"""
    w = lines[i:i + 7]
    if any(x[0] != 'I' for x in w):
        return False
    ms = [x[1] for x in w]
    if ms != ['clc', 'lda', 'adc', 'sta', 'lda', 'adc', 'sta']:
        return False
    r, r2 = _rg(w[1][2]), _rg(w[4][2])
    return r is not None and r2 == r + 2 and w[3][2] == w[1][2] and w[6][2] == w[4][2] and \
        w[2][2] == '#$0001' and w[5][2] == '#$0000'


def simple(lines):
    changed = False
    out = []
    i = 0
    n = len(lines)
    labels_used = set()
    for l in lines:
        if l[0] == 'I' and (l[1] in BRANCH or l[1] in ('jmp', 'brl')):
            labels_used.add(l[2])
        if l[0] == 'D' and l[1].startswith('.addr '):
            labels_used.add(l[1][6:])
    tails = {}
    for k, l in enumerate(lines):
        if l[0] != 'L':
            continue
        body = []
        j = k + 1
        while j < n and lines[j][0] == 'L':
            j += 1
        while j < n and len(body) <= 6:
            x = lines[j]
            if x[0] != 'I' or x[1] in BRANCH or x[1] in ('jmp', 'brl'):
                break
            body.append(x)
            if x[1] in ('rts', 'rtl'):
                tails[l[1]] = body
                break
            j += 1
    while i < n:
        l = lines[i]
        # jmp/bra to the label right after (skipping liveness markers)
        if l[0] == 'I' and l[1] in ('jmp', 'bra', 'brl') or l[0] == 'I' and l[1] in BRANCH:
            j = i + 1
            while j < n and lines[j][0] == 'LIVE':
                j += 1
            labs = set()
            while j < n and lines[j][0] == 'L':
                labs.add(lines[j][1])
                j += 1
            if l[2] in labs:
                changed = True
                i += 1
                continue
            # bxx L1 ; jmp L2 ; L1:  ->  b!xx L2
            if l[1] in INV and i + 1 < n and lines[i + 1][0] == 'I' and lines[i + 1][1] == 'jmp' and \
                    not lines[i + 1][2].startswith('('):
                k = i + 2
                labs = set()
                while k < n and lines[k][0] == 'L':
                    labs.add(lines[k][1])
                    k += 1
                if l[2] in labs:
                    out.append(('I', INV[l[1]], lines[i + 1][2]))
                    i += 2
                    changed = True
                    continue
        # a 32-bit register + 1 (a far pointer's p++): clc ; lda R ; adc #1 ; sta R ;
        # lda R+2 ; adc #0 ; sta R+2  ->  inc R ; bne L ; inc R+2 ; L:  (A, the carry and
        # the flags unused after)
        if l == ('I', 'clc', '') and i + 6 < n and _inc32(lines, i) and \
                not a_live_after(lines, i + 6) and not flags_needed(lines, i + 6, 'c') and \
                not flags_needed(lines, i + 6, 'nz'):
            r, r2 = lines[i + 1][2], lines[i + 4][2]
            lab = f'Lpi{next(_PI)}'
            out += [('I', 'inc', r), ('I', 'bne', lab), ('I', 'inc', r2), ('L', lab)]
            i += 7
            changed = True
            continue
        # rep #$20 ; sep #$20 (or the reverse) -> nothing
        if l[0] == 'I' and l[1] in ('rep', 'sep') and l[2] == '#$20' and i + 1 < n and \
                lines[i + 1][0] == 'I' and lines[i + 1][1] in ('rep', 'sep') and \
                lines[i + 1][1] != l[1] and lines[i + 1][2] == '#$20':
            i += 2
            changed = True
            continue
        # clc ; adc #$0001 -> inc a (carry out unused)
        if l[0] == 'I' and l[1] in ('clc', 'sec') and i + 1 < n and lines[i + 1][0] == 'I' and \
                lines[i + 1][1] == ('adc' if l[1] == 'clc' else 'sbc') and \
                lines[i + 1][2] in ('#$0001', '#$0002') and not flags_needed(lines, i + 1, 'c') \
                and not flags_needed(lines, i + 1, 'v'):
            m = 'inc' if l[1] == 'clc' else 'dec'
            out.append(('I', m, 'a'))
            if lines[i + 1][2] == '#$0002':
                out.append(('I', m, 'a'))
            i += 2
            changed = True
            continue
        # sta R ; lda Y ; [clc] ; adc R  ->  sta R ; [clc] ; adc Y   (A = R already)
        if l[0] == 'I' and l[1] == 'sta' and i + 2 < n and lines[i + 1][0] == 'I' and \
                lines[i + 1][1] == 'lda' and lines[i + 1][2] != l[2]:
            j = i + 2
            pre = []
            if lines[j][0] == 'I' and lines[j][1] == 'clc':
                pre = [lines[j]]
                j += 1
            if j < n and lines[j][0] == 'I' and lines[j][2] == l[2] and \
                    lines[j][1] in (('adc',) if pre else ('and', 'ora', 'eor')):
                out.append(l)
                out.extend(pre)
                out.append(('I', lines[j][1], lines[i + 1][2]))
                i = j + 1
                changed = True
                continue
        # jmp L where L is a short tail ending in rts: copy the tail
        if l[0] == 'I' and l[1] == 'jmp' and l[2] in tails:
            out.extend(tails[l[2]])
            i += 1
            changed = True
            continue
        out.append(l)
        i += 1
    # unused internal labels are kept (cheap); remove code after an unconditional end
    res = []
    dead = False
    for l in out:
        if l[0] in ('L', 'D', 'ASM'):
            dead = False
            res.append(l)
            continue
        if dead and l[0] == 'I':
            changed = True
            continue
        res.append(l)
        if l[0] == 'I' and l[1] in ('jmp', 'bra', 'brl', 'rts', 'rtl'):
            dead = True
    if changed:
        lines[:] = res
    return changed


# ---------------------------------------------------------------------- sizes, relaxation
IMPLIED = {'clc', 'sec', 'cld', 'sed', 'cli', 'sei', 'clv', 'tax', 'tay', 'txa', 'tya', 'tsc',
           'tcs', 'tcd', 'tdc', 'txy', 'tyx', 'txs', 'tsx', 'inx', 'iny', 'dex', 'dey', 'pha',
           'pla', 'phx', 'plx', 'phy', 'ply', 'php', 'plp', 'phb', 'plb', 'phd', 'pld', 'phk',
           'rts', 'rtl', 'rti', 'xba', 'xce', 'nop', 'wai', 'stp'}


def isize(m, o, m8):
    if m in IMPLIED:
        return 1
    if m in BRANCH:
        return 2
    if m in ('brl', 'per'):
        return 3
    if m in ('jsr', 'jmp'):
        return 3
    if m in ('jsl', 'jml'):
        return 4
    if m in ('mvn', 'mvp'):
        return 3
    if m in ('rep', 'sep', 'cop', 'brk', 'wdm'):
        return 2
    if m == 'pea':
        return 3
    if m == 'pei':
        return 2
    if o in ('a', ''):
        return 1
    if o.startswith('#'):
        if m in ('ldx', 'ldy', 'cpx', 'cpy'):
            return 3
        return 2 if m8 else 3
    if o.endswith(',s') or o.endswith(',s),y'):
        return 2
    if o.startswith('(') or o.startswith('['):
        inner = o[1:].split(')')[0].split(']')[0].split(',')[0]
        return 2 if is_dp(inner) else 3
    base = o.split(',')[0]
    if base.startswith('a:'):
        return 3
    if base.startswith('f:'):
        return 4
    return 2 if is_dp(base) else 3


_relaxed = [0]
# how far a BRL is trusted to reach (its range is -32768..32767; isize's estimates of the
# code between may be a little off: the rest is margin)
BRL_REACH = 30000


def relax(lines):
    """conditional branches whose target is out of reach: inverted branch over a BRL.
    Every branch out of reach is relaxed in each pass; a relaxed branch is longer, which
    may push others out of reach: passes repeat until none is (each pass relaxes at least
    one branch, so this ends)."""
    while True:
        pos = {}
        addr = 0
        m8 = False
        sizes = []
        for l in lines:
            if l[0] == 'L':
                pos[l[1]] = addr
                sizes.append(0)
                continue
            if l[0] in ('D', 'ASM'):
                sizes.append(l[2])
                addr += l[2]
                if l[0] == 'ASM':
                    m8 = False
                continue
            if l[0] != 'I':
                sizes.append(0)
                continue
            if l[1] == 'sep' and l[2] == '#$20':
                m8 = True
            elif l[1] == 'rep' and l[2] == '#$20':
                m8 = False
            s = isize(l[1], l[2], m8 and l[1] not in ('sep',))
            sizes.append(s)
            addr += s
        bad = []
        far = []
        addr = 0
        for k, l in enumerate(lines):
            here = addr
            addr += sizes[k]
            if l[0] == 'I' and l[1] in BRANCH and l[2] in pos:
                d = pos[l[2]] - (here + 2)
                if not -128 <= d <= 127:
                    bad.append(k)
            elif l[0] == 'I' and l[1] == 'brl' and l[2] in pos:
                # a BRL reaches 32 KB either way; in a function bigger than that (the
                # sizes here are estimates: a margin) it becomes a JMP, which reaches the
                # whole bank and has the same size (a function never crosses its bank)
                d = pos[l[2]] - (here + 3)
                if not -BRL_REACH <= d <= BRL_REACH:
                    far.append(k)
        for k in far:
            lines[k] = ('I', 'jmp', lines[k][2])
        if not bad:
            return lines
        for k in reversed(bad):
            l = lines[k]
            if l[1] == 'bra':
                lines[k] = ('I', 'brl', l[2])
            else:
                _relaxed[0] += 1
                skip = f'{l[2]}_r{_relaxed[0]}'
                lines[k:k + 1] = [('I', INV[l[1]], skip), ('I', 'brl', l[2]), ('L', skip)]


def text(lines):
    out = []
    for l in lines:
        if l[0] == 'L':
            out.append(f'{l[1]}:')
        elif l[0] == 'I':
            out.append(f'\t{l[1]}\t{l[2]}' if l[2] else f'\t{l[1]}')
        elif l[0] == 'D':
            out.append(f'\t{l[1]}')
        elif l[0] == 'ASM':
            out.append(l[1])
    return '\n'.join(out)
