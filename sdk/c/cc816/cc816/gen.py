"""65816 code generation: IR (after register allocation) -> ca65 assembly lines.

Lines are tuples: ('L', label) / ('I', mnemonic, operand) / ('LIVE', set of DP words) /
('D', directive text, size). The peephole pass (peep.py) cleans them up and relaxes
branches; out() prints them.

Conventions (see README): JSR/RTS, 16-bit A/X/Y on entry and exit, D = 0, DBR = code
bank. Arguments pushed right to left on the hardware stack (bank 0), popped by the
caller; result in A (16 bits) or A = low, X = high (32 bits). Scratch registers __rg+0..
are caller-saved, __rg+SCR.. callee-saved."""
from .ir import V, Imm, Sym, Frame
from .regalloc import SCR, CS

DP_NAMES = ('__rg', '__sp', '__rv', '__h0', '__h1', '__h2', '__h3', '__cbank')
INV = {'beq': 'bne', 'bne': 'beq', 'bcc': 'bcs', 'bcs': 'bcc', 'bmi': 'bpl', 'bpl': 'bmi',
       'bvc': 'bvs', 'bvs': 'bvc'}
# floating point (rt/cc816/fp_*.s): operands in __h0 (and __h1), the result in __h0 (__fcmp:
# A). The ...r entries take the operands the other way round (__h0 = b, __h1 = a).
FBIN = {'fadd': '__fadd', 'fsub': '__fsub', 'fmul': '__fmul', 'fdiv': '__fdiv',
        'fcmp': '__fcmp'}
FUN = {'ltof': '__ltof', 'ultof': '__ultof', 'ftol': '__ftol', 'ftoul': '__ftoul'}
# instructions whose code reads their operands before it changes __h0: a float result the
# next one of these uses (and nothing after it) is read from __h0, never stored
H0_READERS = {'st', 'ret', 'mov', 'call', 'and', 'or', 'xor'}


def hexw(v):
    return f'${v & 0xFFFF:04X}'


class Gen:
    def __init__(self, f, unit, opts):
        self.f = f
        self.unit = unit
        self.opts = opts
        self.out = []
        self.push = 0
        self.nlab = 0
        self.helpers = set()
        self.bnum = {}
        self.res = None          # a V whose value is only in __h0 (its store was skipped)
        self.h0v = None          # a V whose value __h0 holds now
        self.pend = None

    # ------------------------------------------------------------------ emit
    def I(self, m, o=''):
        self.out.append(('I', m, o))

    def L(self, l):
        self.out.append(('L', l))

    def newlab(self):
        self.nlab += 1
        return f'L{self.f.name[1:]}_{self.nlab}'

    def blab(self, b):
        n = self.bnum.get(b)
        if n is None:
            n = self.bnum[b] = len(self.bnum)
        return f'L{self.f.name[1:]}_b{n}'

    def helper(self, name):
        self.helpers.add(name)
        self.I('jsr', name)

    # ------------------------------------------------------------------ operands
    def vaddr(self, v, part=0):
        """operand text for word `part` of a V"""
        if v is self.res:
            return f'__h0+{2 * part}'
        kind, off = v.loc
        if kind == 'dp':
            return f'__rg+{off + 2 * part}'
        if kind == 'sr':
            return f'{1 + self.push + off + 2 * part},s'
        if kind == 'home':
            return f'{1 + self.push + self.F + self.C + 2 + off + 2 * part},s'
        raise AssertionError(v.loc)

    def is_dp(self, o):
        return isinstance(o, V) and o.loc[0] == 'dp'

    def src(self, o, part=0):
        """operand text readable by lda/adc/cmp/...; None for Frame (needs computing)"""
        if isinstance(o, Imm):
            return '#' + hexw(o.val >> (16 * part))
        if isinstance(o, Sym):
            if part:
                return '#0'
            return f'#{o.name}' + (f'+{o.off}' if o.off > 0 else (f'-{-o.off}' if o.off < 0 else ''))
        if isinstance(o, V):
            return self.vaddr(o, part)
        return None

    def symoff(self, name, off):
        return name + (f'+{off}' if off > 0 else (f'-{-off}' if off < 0 else ''))

    def lda(self, o, part=0):
        if isinstance(o, Frame):
            self.I('lda', '__sp')
            k = o.slot.off + o.off
            if k:
                self.I('clc')
                self.I('adc', '#' + hexw(k))
            return
        if isinstance(o, V) and o.size == 2 and part == 1:
            self.I('lda', '#0')
            return
        if isinstance(o, Sym) and part == 1:
            self.I('lda', '#0')
            return
        self.I('lda', self.src(o, part))

    def sta(self, d, part=0):
        self.I('sta', self.vaddr(d, part))

    def stz(self, d, part=0):
        if d.loc[0] == 'dp':
            self.I('stz', self.vaddr(d, part))
        else:
            self.I('lda', '#0')
            self.I('sta', self.vaddr(d, part))

    def ldx(self, o):
        s = self.src(o) if not isinstance(o, Frame) else None
        if s is None or s.endswith(',s'):
            self.lda(o)
            self.I('tax')
        else:
            self.I('ldx', s)

    def ldy(self, o):
        s = self.src(o) if not isinstance(o, Frame) else None
        if s is None or s.endswith(',s'):
            self.lda(o)
            self.I('tay')
        else:
            self.I('ldy', s)

    def opsrc(self, o, part=0):
        """a second operand for adc/and/...: materialise a Frame address in __h3"""
        if isinstance(o, Frame):
            self.I('pha')
            self.push += 2
            self.lda(o)
            self.I('sta', '__h3')
            self.I('pla')
            self.push -= 2
            return '__h3'
        if isinstance(o, V) and o.size == 2 and part == 1:
            return '#0'
        return self.src(o, part)

    # ------------------------------------------------------------------ function
    def gen(self):
        f = self.f
        self.F = f.frame_size
        self.C = 2 * len(f.saved)
        soff = 0
        for s in f.slots:
            s.off = soff
            soff += s.size
        self.S = soff
        out = self.out
        if not f.static:
            pass
        self.L(f.name)
        for k in f.saved:
            self.I('pei', f'(__rg+{k})')
        self.push = 0
        if self.F:
            if self.F <= 8:
                for _ in range(self.F // 2):
                    self.I('pha')
            else:
                self.I('tsc')
                self.I('sec')
                self.I('sbc', '#' + hexw(self.F))
                self.I('tcs')
        if self.S:
            self.I('lda', '__sp')
            self.I('sec')
            self.I('sbc', '#' + hexw(self.S))
            self.I('sta', '__sp')
        for p, loc in f.param_copies:
            home = f'{1 + self.F + self.C + 2 + p.param},s'
            for part in range(p.size // 2):
                self.I('lda', f'{1 + self.F + self.C + 2 + p.param + 2 * part},s')
                self.sta(p, part)
        self.exit_label = f'L{f.name[1:]}_exit'
        self.nret = sum(1 for b in f.blocks for i in b.ins if i.op == 'ret')
        from .opt import liveness
        self.lin, self.lout = liveness(f)
        blocks = f.blocks
        for bi, b in enumerate(blocks):
            self.next = blocks[bi + 1] if bi + 1 < len(blocks) else None
            if bi > 0:
                self.L(self.blab(b))
            # what is live after each instruction (for keeping float results in __h0)
            live = set(self.lout[b])
            self.live_after = [None] * len(b.ins)
            for k in range(len(b.ins) - 1, -1, -1):
                self.live_after[k] = frozenset(live)
                for d in b.ins[k].defs():
                    live.discard(d)
                for u in b.ins[k].uses():
                    live.add(u)
            self.h0v = None
            for k, ins in enumerate(b.ins):
                self.cur_k, self.cur_b = k, b
                self.res, self.pend = self.pend, None
                if ins.is_term:
                    live = set()
                    for v in self.lout[b] | set(ins.uses()):
                        if v.loc[0] == 'dp':
                            for k in range(0, v.size, 2):
                                live.add(v.loc[1] + k)
                    self.out.append(('LIVE', live))
                getattr(self, 'g_' + ins.op)(ins)
                assert self.push == 0 or ins.op != 'call', 'push imbalance'
                if ins.op not in FBIN and ins.op not in FUN:
                    self.h0v = None
                self.res = None
        if self.need_exit:
            self.L(self.exit_label)
            self.epilogue()
        return self.out

    need_exit = False

    def epilogue(self, size=None):
        clob = self.S or self.F > 8 or self.C
        if clob:
            self.I('sta', '__rv')
        if self.S:
            self.I('lda', '__sp')
            self.I('clc')
            self.I('adc', '#' + hexw(self.S))
            self.I('sta', '__sp')
        if self.F:
            if self.F <= 8:
                for _ in range(self.F // 2):
                    self.I('ply')
            else:
                if not clob:
                    self.I('tay')
                self.I('tsc')
                self.I('clc')
                self.I('adc', '#' + hexw(self.F))
                self.I('tcs')
                if not clob:
                    self.I('tya')
        for k in reversed(self.f.saved):
            self.I('pla')
            self.I('sta', f'__rg+{k}')
        if clob:
            self.I('lda', '__rv')
        self.I('rts')

    # ------------------------------------------------------------------ instructions
    def g_mov(self, i):
        d, a = i.d, i.a
        for p in range(d.size // 2):
            if isinstance(a, Imm) and (a.val >> (16 * p)) & 0xFFFF == 0:
                self.stz(d, p)
                continue
            self.lda(a, p)
            self.sta(d, p)

    def g_add(self, i):
        d, a, b = i.d, i.a, i.b
        if d.size == 2:
            if isinstance(b, Imm) and b.val in (1, 2, 0xFFFF, 0xFFFE) and a is d and d.loc[0] == 'dp':
                m = 'inc' if b.val in (1, 2) else 'dec'
                for _ in range(1 if b.val in (1, 0xFFFF) else 2):
                    self.I(m, self.vaddr(d))
                return
            if isinstance(a, Imm) and not isinstance(b, Imm):
                a, b = b, a
            self.lda(a)
            if a is b and isinstance(a, V):
                self.I('asl', 'a')
            elif isinstance(b, Imm) and b.val in (1, 2, 0xFFFF, 0xFFFE):
                m = 'inc' if b.val in (1, 2) else 'dec'
                for _ in range(1 if b.val in (1, 0xFFFF) else 2):
                    self.I(m, 'a')
            else:
                s = self.opsrc(b)
                self.I('clc')
                self.I('adc', s)
            self.sta(d)
            return
        self.I('clc')
        for p in (0, 1):
            self.lda(a, p)
            self.I('adc', self.opsrc(b, p))
            self.sta(d, p)

    def g_sub(self, i):
        d, a, b = i.d, i.a, i.b
        if d.size == 2:
            if isinstance(a, Imm) and a.val == 0:
                return self.g_neg(type(i)('neg', d, b))
            self.lda(a)
            s = self.opsrc(b)
            self.I('sec')
            self.I('sbc', s)
            self.sta(d)
            return
        self.I('sec')
        for p in (0, 1):
            self.lda(a, p)
            self.I('sbc', self.opsrc(b, p))
            self.sta(d, p)

    def logic(self, i, m):
        d, a, b = i.d, i.a, i.b
        for p in range(d.size // 2):
            if isinstance(b, Imm):
                k = (b.val >> (16 * p)) & 0xFFFF
                if m == 'and' and k == 0:
                    self.stz(d, p)
                    continue
                if m == 'and' and k == 0xFFFF or m in ('ora', 'eor') and k == 0:
                    self.lda(a, p)
                    self.sta(d, p)
                    continue
            self.lda(a, p)
            self.I(m, self.opsrc(b, p))
            self.sta(d, p)

    def g_and(self, i):
        self.logic(i, 'and')

    def g_or(self, i):
        self.logic(i, 'ora')

    def g_xor(self, i):
        self.logic(i, 'eor')

    def g_com(self, i):
        for p in range(i.d.size // 2):
            self.lda(i.a, p)
            self.I('eor', '#$FFFF')
            self.sta(i.d, p)

    def g_neg(self, i):
        d, a = i.d, i.a
        if d.size == 2:
            self.lda(a)
            self.I('eor', '#$FFFF')
            self.I('inc', 'a')
            self.sta(d)
            return
        self.I('sec')
        for p in (0, 1):
            self.I('lda', '#0')
            self.I('sbc', self.opsrc(a, p))
            self.sta(d, p)

    # --- shifts
    def g_shl(self, i):
        self.shift(i, 'shl')

    def g_ushr(self, i):
        self.shift(i, 'ushr')

    def g_sshr(self, i):
        self.shift(i, 'sshr')

    def shift(self, i, kind):
        d, a, b = i.d, i.a, i.b
        if d.size == 4:
            return self.shift32(i, kind)
        if isinstance(b, Imm):
            k = b.val & 0xFFFF
            if k >= 16:
                if kind == 'sshr':
                    self.lda(a)
                    self.I('asl', 'a')
                    self.I('lda', '#0')
                    self.I('adc', '#$FFFF')
                    self.I('eor', '#$FFFF')
                    self.sta(d)
                else:
                    self.stz(d)
                return
            self.lda(a)
            self.shift_a(kind, k)
            self.sta(d)
            return
        # variable count: an inline loop with X
        self.ldx(b)
        self.lda(a)
        self.I('cpx', '#0')
        done = self.newlab()
        loop = self.newlab()
        self.I('beq', done)
        self.L(loop)
        if kind == 'shl':
            self.I('asl', 'a')
        elif kind == 'ushr':
            self.I('lsr', 'a')
        else:
            self.I('cmp', '#$8000')
            self.I('ror', 'a')
        self.I('dex')
        self.I('bne', loop)
        self.L(done)
        self.sta(d)

    def shift_a(self, kind, k):
        if k >= 8:
            if kind == 'shl':
                self.I('xba')
                self.I('and', '#$FF00')
            elif kind == 'ushr':
                self.I('xba')
                self.I('and', '#$00FF')
            else:
                self.I('xba')
                self.I('and', '#$00FF')
                self.I('eor', '#$0080')
                self.I('sec')
                self.I('sbc', '#$0080')
            k -= 8
        for _ in range(k):
            if kind == 'shl':
                self.I('asl', 'a')
            elif kind == 'ushr':
                self.I('lsr', 'a')
            else:
                self.I('cmp', '#$8000')
                self.I('ror', 'a')

    def shift32(self, i, kind):
        d, a, b = i.d, i.a, i.b
        if isinstance(b, Imm):
            k = b.val & 0xFFFF
            if k >= 32:
                if kind == 'sshr':
                    self.lda(a, 1)
                    self.I('asl', 'a')
                    self.I('lda', '#0')
                    self.I('adc', '#$FFFF')
                    self.I('eor', '#$FFFF')
                    self.sta(d, 0)
                    self.sta(d, 1)
                else:
                    self.stz(d, 0)
                    self.stz(d, 1)
                return
            if k >= 16:
                if kind == 'shl':
                    self.lda(a, 0)
                    self.shift_a('shl', k - 16)
                    self.sta(d, 1)
                    self.stz(d, 0)
                elif kind == 'ushr':
                    self.lda(a, 1)
                    self.shift_a('ushr', k - 16)
                    self.sta(d, 0)
                    self.stz(d, 1)
                else:
                    self.lda(a, 1)
                    self.shift_a('sshr', k - 16)
                    self.sta(d, 0)
                    self.I('asl', 'a')
                    self.I('lda', '#0')
                    self.I('adc', '#$FFFF')
                    self.I('eor', '#$FFFF')
                    self.sta(d, 1)
                return
            # k < 16: through __h0 in the direct page
            self.lda(a, 0)
            self.I('sta', '__h0')
            self.lda(a, 1)
            if k == 0:
                self.I('sta', '__h0+2')
            else:
                for n in range(k):
                    if kind == 'shl':
                        if n == 0:
                            self.I('sta', '__h0+2')
                        self.I('asl', '__h0')
                        self.I('rol', '__h0+2')
                    else:
                        if n == 0:
                            pass
                        if kind == 'ushr':
                            self.I('lsr', 'a')
                        else:
                            self.I('cmp', '#$8000')
                            self.I('ror', 'a')
                        self.I('ror', '__h0')
                if kind != 'shl':
                    self.I('sta', '__h0+2')
            self.I('lda', '__h0')
            self.sta(d, 0)
            self.I('lda', '__h0+2')
            self.sta(d, 1)
            return
        self.lda(a, 0)
        self.I('sta', '__h0')
        self.lda(a, 1)
        self.I('sta', '__h0+2')
        self.ldx(b)
        self.helper({'shl': '__shl32', 'ushr': '__shr32', 'sshr': '__sar32'}[kind])
        self.I('lda', '__h0')
        self.sta(d, 0)
        self.I('lda', '__h0+2')
        self.sta(d, 1)

    # --- multiply / divide
    def g_mul(self, i):
        d, a, b = i.d, i.a, i.b
        if d.size == 2:
            if isinstance(b, Imm) and self.mul_const(d, a, b.val):
                return
            self.lda(b)
            self.I('tax')
            self.lda(a)
            self.helper('__mul16')
            self.sta(d)
            return
        self.call32('__mul32', i)

    def g_mulu(self, i):
        self.mul1632(i, '__umul1632')

    def g_muls(self, i):
        self.mul1632(i, '__smul1632')

    def mul1632(self, i, h):
        self.lda(i.a)
        self.I('sta', '__h0')
        self.lda(i.b)
        self.I('sta', '__h1')
        self.helper(h)
        self.I('lda', '__h0')
        self.sta(i.d, 0)
        self.I('lda', '__h0+2')
        self.sta(i.d, 1)

    def mul_const(self, d, a, k):
        """x * k by shifts and adds (k with few one-bits)"""
        if bin(k).count('1') > 4 or isinstance(a, Frame):
            return False
        s = self.src(a)
        bits = bin(k)[3:]
        self.lda(a)
        for c in bits:
            self.I('asl', 'a')
            if c == '1':
                self.I('clc')
                self.I('adc', s)
        self.sta(d)
        return True

    def divmod16(self, i, h):
        self.ldx(i.b)
        self.lda(i.a)
        self.helper(h)
        self.sta(i.d)

    def g_udiv(self, i):
        if i.d.size == 2:
            return self.divmod16(i, '__udiv16')
        self.call32('__udiv32', i)

    def g_sdiv(self, i):
        if i.d.size == 2:
            return self.divmod16(i, '__sdiv16')
        self.call32('__sdiv32', i)

    def g_umod(self, i):
        if i.d.size == 2:
            return self.divmod16(i, '__umod16')
        self.call32('__umod32', i)

    def g_smod(self, i):
        if i.d.size == 2:
            return self.divmod16(i, '__smod16')
        self.call32('__smod32', i)

    # --- floating point (rt/cc816/fp_*.s): the operands in __h0 (and __h1), the result
    # in __h0 (__fcmp: A), as the 32-bit helpers. A chain of float operations keeps its
    # value in __h0: an operand __h0 already holds is not loaded again (the previous
    # result as the second operand: the ...r entry), and a result only the next
    # instruction uses is not stored (that instruction reads __h0)
    def g_fadd(self, i):
        self.fop(i)

    g_fsub = g_fmul = g_fdiv = g_fcmp = g_ltof = g_ultof = g_ftol = g_ftoul = g_fadd

    def fload(self, reg, o):
        for p in (0, 1):
            if isinstance(o, Imm) and (o.val >> (16 * p)) & 0xFFFF == 0 or \
                    isinstance(o, (V, Sym)) and o.size == 2 and p == 1:
                self.I('stz', f'{reg}+{2 * p}')
                continue
            self.lda(o, p)
            self.I('sta', f'{reg}+{2 * p}')

    def dpv(self, o):
        """o is a V in a direct-page register (not one living in __h0 only)"""
        return isinstance(o, V) and o is not self.res and o.loc[0] == 'dp'

    def fop(self, i):
        a, b, op = i.a, i.b, i.op
        h0 = self.h0v if isinstance(self.h0v, V) else None
        helper = FBIN.get(op) or FUN[op]
        if b is not None and a is not h0 and b is not h0 and (self.dpv(a) or self.dpv(b)):
            # the ...i entry: X and Y the operands' direct-page addresses, A the result's
            # (fp_ind.s): 12 bytes for a + b in registers, against 27
            if self.dpv(a):
                self.I('ldx', '#' + self.vaddr(a))
            else:
                self.fload('__h0', a)
                self.I('ldx', '#__h0')
            if self.dpv(b):
                self.I('ldy', '#' + self.vaddr(b))
            else:
                self.fload('__h1', b)
                self.I('ldy', '#__h1')
            d = i.d
            if op == 'fcmp':
                self.helper(helper + 'i')
                self.sta(d)
                self.h0v = None
                return
            keep = self.keep_h0(d)
            store = not keep and not self.dpv(d)
            self.I('lda', '#__h0' if keep or store else '#' + self.vaddr(d))
            self.helper(helper + 'i')
            if keep:
                self.pend = d
            elif store:
                self.I('lda', '__h0')
                self.sta(d, 0)
                self.I('lda', '__h0+2')
                self.sta(d, 1)
            self.h0v = d
            return
        if b is not None and h0 is not None and b is h0 and a is not h0:
            helper += 'r'                       # (a, b) = (__h1, __h0): the ...r entry
            if self.dpv(a):
                self.I('ldx', '#' + self.vaddr(a))
                helper += 'x'                   # a from its register (fp_ind.s)
            else:
                self.fload('__h1', a)
        else:
            if a is not h0 or h0 is None:
                self.fload('__h0', a)
            if b is not None:
                if a is h0 and h0 is not None and self.dpv(b):
                    self.I('ldx', '#' + self.vaddr(b))
                    helper += 'x'               # b from its register (fp_ind.s)
                else:
                    self.fload('__h1', b)       # (b may be __h0 itself: x * x)
        self.helper(helper)
        self.h0v = None
        d = i.d
        if op == 'fcmp':
            self.sta(d)
            return
        if self.keep_h0(d):
            self.pend = d                       # the next instruction reads __h0
        else:
            self.I('lda', '__h0')
            self.sta(d, 0)
            self.I('lda', '__h0+2')
            self.sta(d, 1)
        self.h0v = d

    def keep_h0(self, d):
        """may the float result d stay in __h0 only: the next instruction of the block
        takes it from there and nothing after uses it"""
        b, k = self.cur_b, self.cur_k
        if k + 1 >= len(b.ins):
            return False
        nx = b.ins[k + 1]
        if d in self.live_after[k + 1] or d not in nx.uses():
            return False
        if nx.op in FBIN:
            return nx.a is d or nx.b is d
        if nx.op in FUN:
            return nx.a is d
        if nx.op in ('st', 'ret', 'mov'):
            return nx.a is d and nx.x.get('base') is not d and nx.x.get('idx') is not d
        if nx.op in ('and', 'or', 'xor'):
            return nx.d is not None and nx.d.size == 4
        if nx.op == 'call':
            return nx.x['tgt'] is not d
        return False

    def call32(self, h, i):
        for r, o in (('__h0', i.a), ('__h1', i.b)):
            if o is None:
                continue
            for p in (0, 1):
                if isinstance(o, Imm) and (o.val >> (16 * p)) & 0xFFFF == 0 or \
                        isinstance(o, (V, Sym)) and o.size == 2 and p == 1:
                    self.I('stz', f'{r}+{2 * p}')
                    continue
                self.lda(o, p)
                self.I('sta', f'{r}+{2 * p}')
        self.helper(h)
        self.I('lda', '__h0')
        self.sta(i.d, 0)
        self.I('lda', '__h0+2')
        self.sta(i.d, 1)

    # --- conversions
    def g_zx(self, i):
        self.lda(i.a)
        self.sta(i.d, 0)
        self.stz(i.d, 1)

    def g_sx(self, i):
        self.lda(i.a)
        self.sta(i.d, 0)
        self.I('asl', 'a')
        self.I('lda', '#0')
        self.I('adc', '#$FFFF')
        self.I('eor', '#$FFFF')
        self.sta(i.d, 1)

    def g_tr(self, i):
        self.lda(i.a, 0)
        self.sta(i.d)

    def g_x8u(self, i):
        self.lda(i.a)
        self.I('and', '#$00FF')
        self.sta(i.d)

    def g_x8s(self, i):
        self.lda(i.a)
        self.I('and', '#$00FF')
        self.I('eor', '#$0080')
        self.I('sec')
        self.I('sbc', '#$0080')
        self.sta(i.d)

    def g_mkfar(self, i):
        """a near address -> far: the code bank as the high word (0 for a null pointer)"""
        self.lda(i.a)
        self.sta(i.d, 0)
        if isinstance(i.a, (Sym, Frame)):
            self.I('lda', '__cbank')
        else:
            skip = self.newlab()
            self.I('beq', skip)
            self.I('lda', '__cbank')
            self.L(skip)
        self.sta(i.d, 1)

    # --- memory
    def addr(self, base, idx, off):
        """set up X/Y for an access; returns a function part -> operand text.
        May clobber A."""
        if isinstance(base, Sym):
            name = base.name
            o = base.off + off
            if idx is None:
                return lambda p: self.symoff(name, o + 2 * p)
            if isinstance(idx, Imm):
                return lambda p: self.symoff(name, o + idx.val + 2 * p)
            self.ldx(idx)
            return lambda p: self.symoff(name, o + 2 * p) + ',x'
        if isinstance(base, Frame):
            k = base.slot.off + base.off + off
            if idx is None:
                self.I('ldy', '#' + hexw(k))
            else:
                self.add_to_y(idx, k)
            return self.yseq('(__sp),y', k if idx is None else None)
        if isinstance(base, V) and (off < 0 or off >= 0x8000) and idx is None:
            # a negative offset must not become a Y index (it would carry into the next
            # bank): add it to the pointer
            for p in range(base.size // 2):
                self.lda(base, p)
                if p == 0:
                    self.I('clc')
                    self.I('adc', '#' + hexw(off))
                else:
                    self.I('adc', '#' + hexw(-1 if off < 0 else 0))
                self.I('sta', f'__h2+{2 * p}')
            self.I('ldy', '#$0000')
            return self.yseq('[__h2],y' if base.size == 4 else '(__h2),y', 0)
        if isinstance(base, V) and base.size == 4:
            if base.loc[0] == 'dp':
                ptr = self.vaddr(base)
            else:
                self.lda(base, 0)
                self.I('sta', '__h2')
                self.lda(base, 1)
                self.I('sta', '__h2+2')
                ptr = '__h2'
            if idx is None:
                self.I('ldy', '#' + hexw(off))
            else:
                self.add_to_y(idx, off)
            return self.yseq(f'[{ptr}],y', off if idx is None else None)
        if isinstance(base, V):
            if base.loc[0] == 'dp':
                ind = f'({self.vaddr(base)}),y'
            else:
                ind = None
            if idx is None:
                self.I('ldy', '#' + hexw(off))
            else:
                self.add_to_y(idx, off)
            if ind is None:
                # (sr,s),y: the offset must account for pushes at use time
                return self.yseq_sr(base, off if idx is None else None)
            return self.yseq(ind, off if idx is None else None)
        raise AssertionError(f'address base {base!r}')

    def add_to_y(self, idx, k):
        if k == 0:
            self.ldy(idx)
            return
        self.lda(idx)
        self.I('clc')
        self.I('adc', '#' + hexw(k))
        self.I('tay')

    def yseq(self, text, k):
        state = {'p': 0}

        def part(p):
            while state['p'] < p:
                self.I('iny')
                self.I('iny')
                state['p'] += 1
            return text
        return part

    def yseq_sr(self, base, k):
        state = {'p': 0}

        def part(p):
            while state['p'] < p:
                self.I('iny')
                self.I('iny')
                state['p'] += 1
            return f'({self.vaddr(base)}),y'
        return part

    def g_ld(self, i):
        d = i.d
        sz = i.x['sz']
        acc = self.addr(i.x['base'], i.x['idx'], i.x['off'])
        if sz == 4:
            self.I('lda', acc(0))
            self.sta(d, 0)
            self.I('lda', acc(1))
            self.sta(d, 1)
            return
        base = i.x['base']
        if sz == 1 and ((isinstance(base, V) and base.size == 4) or i.x.get('vol')):
            # a byte through a far pointer, or a volatile byte: an 8-bit read (a 16-bit
            # one would also read the next byte: past the end of a bank, an I/O register)
            self.I('sep', '#$20')
            self.I('lda', acc(0))
            self.I('rep', '#$20')
        else:
            self.I('lda', acc(0))
        if sz == 1:
            self.I('and', '#$00FF')
            if i.x.get('sgn'):
                self.I('eor', '#$0080')
                self.I('sec')
                self.I('sbc', '#$0080')
        self.sta(d)

    def g_st(self, i):
        sz = i.x['sz']
        a = i.a
        acc = self.addr(i.x['base'], i.x['idx'], i.x['off'])
        if sz == 1:
            self.I('sep', '#$20')
            t = acc(0)
            if isinstance(a, Imm) and a.val & 0xFF == 0 and not t.startswith('(') and not t.startswith('['):
                self.I('stz', t)
            else:
                self.lda8(a)
                self.I('sta', t)
            self.I('rep', '#$20')
            return
        for p in range(2 if sz == 4 else 1):
            t = acc(p)
            if isinstance(a, Imm) and (a.val >> (16 * p)) & 0xFFFF == 0 and \
                    not t.startswith('(') and not t.startswith('['):
                self.I('stz', t)
                continue
            self.lda(a, p)
            self.I('sta', t)

    def lda8(self, a):
        if isinstance(a, Imm):
            self.I('lda', f'#${a.val & 0xFF:02X}')
        elif isinstance(a, Sym):
            self.I('lda', f'#<({self.symoff(a.name, a.off)})')
        elif isinstance(a, Frame):
            self.I('rep', '#$20')
            self.lda(a)
            self.I('sep', '#$20')
        else:
            self.I('lda', self.src(a))

    def g_copy(self, i):
        n = i.x['n']
        if n == 0:
            return
        src, dst = i.a, i.b
        self.ldy_addr(dst)
        self.I('phy')
        self.push += 2
        self.ldy_addr(src)
        self.I('tyx')
        self.I('ply')
        self.push -= 2
        self.I('lda', '#' + hexw(n - 1))
        self.I('mvn', f'#^{self.f.name}, #^{self.f.name}')

    def g_fcopy(self, i):
        """n bytes between far addresses: __fcopy (MVN built with both banks)"""
        for r, o in (('__h0', i.b), ('__h1', i.a)):
            for p in (0, 1):
                self.lda(o, p)
                self.I('sta', f'{r}+{2 * p}')
        self.I('lda', '#' + hexw(i.x['n']))
        self.helper('__fcopy')

    def ldy_addr(self, o):
        if isinstance(o, Frame):
            self.lda(o)
            self.I('tay')
        else:
            self.ldy(o)

    def g_zero(self, i):
        n = i.x['n']
        dst = i.a
        if n <= 8 and isinstance(dst, (Frame, Sym)):
            acc = self.addr(dst, None, 0)
            for p in range(n // 2):
                t = acc(p)
                if t.startswith('('):
                    self.I('lda', '#0')
                    self.I('sta', t)
                else:
                    self.I('stz', t)
            if n & 1:
                acc2 = self.addr(dst, None, n - 1)
                self.I('sep', '#$20')
                self.I('lda', '#0')
                self.I('sta', acc2(0))
                self.I('rep', '#$20')
            return
        self.ldy_addr(dst)
        self.I('tya')
        self.I('tax')
        self.I('sep', '#$20')
        self.I('lda', '#0')
        self.I('sta', 'a:0,x')
        self.I('rep', '#$20')
        if n > 1:
            self.I('iny')
            self.I('lda', '#' + hexw(n - 2))
            self.I('mvn', f'#^{self.f.name}, #^{self.f.name}')

    def g_vastart(self, i):
        self.I('tsc')
        self.I('clc')
        self.I('adc', '#' + hexw(1 + self.push + self.F + self.C + 2 + self.f.argsize))
        self.sta(i.d, 0)
        self.stz(i.d, 1)

    def g_cop(self, i):
        x = i.x
        self.lda(x['ra'])
        self.I('pha')
        self.push += 2
        self.ldx(x['rx'])
        self.ldy(x['ry'])
        self.I('pla')
        self.push -= 2
        self.I('cop', f'#${x["n"]:02X}')
        self.sta(i.d)

    def g_asm(self, i):
        self.out.append(('D', i.x['text'], 0))

    # --- calls
    def g_call(self, i):
        args = i.x['args']
        n = 0
        for a in reversed(args):
            for p in reversed(range(a.size // 2 if a.size >= 2 else 1)):
                self.pusharg(a, p)
                n += 2
        tgt = i.x['tgt']
        if isinstance(tgt, Sym) and tgt.off == 0:
            self.I('jsr', tgt.name)
        else:
            self.lda(tgt)
            self.I('sta', '__fpt')
            self.I('ldx', '#0')
            self.I('jsr', '(__fpt,x)')
            self.helpers.add('__fpt')
        if n:
            if n <= 6:
                for _ in range(n // 2):
                    self.I('ply')
            else:
                self.I('tay')
                self.I('tsc')
                self.I('clc')
                self.I('adc', '#' + hexw(n))
                self.I('tcs')
                self.I('tya')
            self.push -= n
        if i.d is not None:
            if i.d.size == 4:
                self.sta(i.d, 0)
                if i.d.loc[0] == 'dp':
                    self.I('stx', self.vaddr(i.d, 1))
                else:
                    self.I('txa')
                    self.sta(i.d, 1)
            else:
                self.sta(i.d)

    def pusharg(self, a, p):
        if isinstance(a, Imm):
            self.I('pea', hexw(a.val >> (16 * p)))
        elif isinstance(a, Sym):
            self.I('pea', self.symoff(a.name, a.off) if p == 0 else '0')
        elif isinstance(a, V) and a.loc[0] == 'dp':
            if a.size == 2 and p == 1:
                self.I('pea', '0')
            else:
                self.I('pei', f'({self.vaddr(a, p)})')
        else:
            self.lda(a, p)
            self.I('pha')
        self.push += 2

    # --- control flow
    def jump_to(self, b):
        if b is self.next:
            return
        self.I('jmp', self.blab(b))

    def g_jmp(self, i):
        self.jump_to(i.x['t'])

    def g_ret(self, i):
        a = i.a
        if a is not None:
            if a.size == 4:
                if isinstance(a, V) and a.loc[0] == 'dp':
                    self.I('ldx', self.vaddr(a, 1))
                else:
                    self.lda(a, 1)
                    self.I('tax')
                self.lda(a, 0)
            else:
                self.lda(a)
        last = self.next is None
        if last and not self.need_exit:
            self.epilogue()
            return
        self.need_exit = True
        self.I('jmp', self.exit_label)

    def branch(self, m, t, f):
        """branch mnemonic m to block t, else to block f"""
        if t is self.next:
            self.I(INV[m], self.blab(f))
            return
        self.I(m, self.blab(t))
        self.jump_to(f)

    def g_br(self, i):
        cc = i.x['cc']
        a, b = i.a, i.b
        t, f = i.x['t'], i.x['f']
        if a.size == 4 or b.size == 4:
            return self.br32(i)
        if cc in ('eq', 'ne'):
            self.lda(a)
            if not (isinstance(b, Imm) and b.val == 0):
                self.I('cmp', self.opsrc(b))
            self.branch('beq' if cc == 'eq' else 'bne', t, f)
            return
        if cc in ('ugt', 'ule'):
            if isinstance(b, Imm):         # b = $FFFF (other constants were simplified)
                self.jump_to(t if cc == 'ule' else f)
                return
            a, b = b, a
            cc = {'ugt': 'ult', 'ule': 'uge'}[cc]
        if cc in ('ult', 'uge'):
            self.lda(a)
            self.I('cmp', self.opsrc(b))
            self.branch('bcc' if cc == 'ult' else 'bcs', t, f)
            return
        # signed
        if cc in ('sgt', 'sle'):
            a, b = b, a
            cc = {'sgt': 'slt', 'sle': 'sge'}[cc]
        if isinstance(b, Imm) and b.val == 0:
            self.lda(a)
            self.branch('bmi' if cc == 'slt' else 'bpl', t, f)
            return
        if isinstance(b, Imm):
            self.lda(a)
            self.I('eor', '#$8000')
            self.I('cmp', '#' + hexw(b.val ^ 0x8000))
            self.branch('bcc' if cc == 'slt' else 'bcs', t, f)
            return
        self.lda(a)
        self.I('sec')
        self.I('sbc', self.opsrc(b))
        ok = self.newlab()
        self.I('bvc', ok)
        self.I('eor', '#$8000')
        self.L(ok)
        self.branch('bmi' if cc == 'slt' else 'bpl', t, f)

    def br32(self, i):
        cc = i.x['cc']
        a, b = i.a, i.b
        t, f = i.x['t'], i.x['f']
        if cc in ('eq', 'ne'):
            if isinstance(b, Imm) and b.val == 0:
                self.lda(a, 0)
                self.I('ora', self.opsrc(a, 1))
                self.branch('beq' if cc == 'eq' else 'bne', t, f)
                return
            self.lda(a, 0)
            self.I('cmp', self.opsrc(b, 0))
            self.I('bne', self.blab(f if cc == 'eq' else t))
            self.lda(a, 1)
            self.I('cmp', self.opsrc(b, 1))
            self.branch('beq' if cc == 'eq' else 'bne', t, f)
            return
        if cc in ('ugt', 'ule', 'sgt', 'sle'):
            a, b = b, a
            cc = {'ugt': 'ult', 'ule': 'uge', 'sgt': 'slt', 'sle': 'sge'}[cc]
        self.lda(a, 0)
        self.I('cmp', self.opsrc(b, 0))
        self.lda(a, 1)
        self.I('sbc', self.opsrc(b, 1))
        if cc[0] == 'u':
            self.branch('bcc' if cc == 'ult' else 'bcs', t, f)
            return
        ok = self.newlab()
        self.I('bvc', ok)
        self.I('eor', '#$8000')
        self.L(ok)
        self.branch('bmi' if cc == 'slt' else 'bpl', t, f)

    def g_sw(self, i):
        a = i.a
        cases = i.x['cases']
        dflt = i.x['default']
        if a.size == 4:
            for v, l in cases:
                nxt = self.newlab()
                self.lda(a, 0)
                self.I('cmp', '#' + hexw(v))
                self.I('bne', nxt)
                self.lda(a, 1)
                self.I('cmp', '#' + hexw(v >> 16))
                self.I('beq', self.blab(l))
                self.L(nxt)
            self.I('jmp', self.blab(dflt))
            return
        if not cases:
            self.jump_to(dflt)
            return
        vals = sorted(v for v, _ in cases)
        lo, hi = vals[0], vals[-1]
        rng = hi - lo + 1
        if len(cases) >= 5 and rng <= 3 * len(cases) + 4:
            tab = self.newlab()
            self.lda(a)
            if lo:
                self.I('sec')
                self.I('sbc', '#' + hexw(lo))
            self.I('cmp', '#' + hexw(rng))
            self.I('bcs', self.blab(dflt))
            self.I('asl', 'a')
            self.I('tax')
            self.I('jmp', f'({tab},x)')
            m = {v: l for v, l in cases}
            self.L(tab)
            for k in range(lo, hi + 1):
                l = m.get(k, dflt)
                self.out.append(('D', f'.addr {self.blab(l)}', 2))
            return
        self.lda(a)
        for v, l in cases:
            self.I('cmp', '#' + hexw(v))
            self.I('beq', self.blab(l))
        self.jump_to(dflt)
