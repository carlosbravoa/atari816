"""65816 code generation: IR (after register allocation) -> ca65 assembly lines.

Lines are tuples: ('L', label) / ('I', mnemonic, operand) / ('LIVE', set of DP words) /
('D', directive text, size). The peephole pass (peep.py) cleans them up and relaxes
branches; out() prints them.

Conventions (see README): JSR/RTS, 16-bit A/X/Y on entry and exit, D = 0, DBR = code
bank. Arguments pushed right to left on the hardware stack (bank 0), popped by the
caller; result in A (16 bits) or A = low, X = high (32 bits). Scratch registers __rg+0..
are caller-saved, __rg+SCR.. callee-saved."""
import re

from .ir import V, Imm, Sym, Frame
from .regalloc import SCR, CS

# the software stack's check at a function's entry (gen): on for every frame of at least
# this many bytes (cc816's sscheck option; 0 turns it off: hcc --no-stack-check)
SSCHECK = 1
DP_NAMES = ('__rg', '__sp', '__rv', '__h0', '__h1', '__h2', '__h3', '__cbank')
INV = {'beq': 'bne', 'bne': 'beq', 'bcc': 'bcs', 'bcs': 'bcc', 'bmi': 'bpl', 'bpl': 'bmi',
       'bvc': 'bvs', 'bvs': 'bvc'}
# floating point (rt/fp_*.s): operands in __h0 (and __h1), the result in __h0 (__fcmp:
# A). The ...r entries take the operands the other way round (__h0 = b, __h1 = a).
FBIN = {'fadd': '__fadd', 'fsub': '__fsub', 'fmul': '__fmul', 'fdiv': '__fdiv',
        'fcmp': '__fcmp'}
FUN = {'ltof': '__ltof', 'ultof': '__ultof', 'ftol': '__ftol', 'ftoul': '__ftoul'}
# instructions whose code reads their operands before it changes __h0: a float result the
# next one of these uses (and nothing after it) is read from __h0, never stored
H0_READERS = {'st', 'ret', 'mov', 'call', 'and', 'or', 'xor'}


def hexw(v):
    return f'${v & 0xFFFF:04X}'


def asm_size(text):
    """at most how many bytes an inline assembly text assembles to (for branch
    relaxation): 4 a line (the longest instruction), the data directives counted"""
    n = 0
    for ln in text.split('\n'):
        ln = ln.split(';', 1)[0].strip()
        if ':' in ln and not ln.startswith('.'):
            head, _, rest = ln.partition(':')
            if re.fullmatch(r'@?[A-Za-z_][\w]*|', head.strip()):
                ln = rest.strip()
        if not ln:
            continue
        w = ln.split(None, 1)
        d = w[0].lower()
        arg = w[1] if len(w) > 1 else ''
        items = arg.count(',') + 1
        if d in ('.byte', '.byt', '.db'):
            n += sum(len(x.strip()) - 2 if x.strip()[:1] == '"' else 1 for x in arg.split(','))
        elif d in ('.word', '.addr', '.dw'):
            n += 2 * items
        elif d in ('.faraddr',):
            n += 3 * items
        elif d in ('.dword', '.dd'):
            n += 4 * items
        elif d in ('.res', '.ds'):
            try:
                n += int(arg.split(',')[0].strip().replace('$', '0x'), 0)
            except ValueError:
                n += 256
        elif d.startswith('.'):
            n += 0 if d in ('.a8', '.a16', '.i8', '.i16', '.export', '.import', '.importzp',
                            '.exportzp', '.global', '.globalzp', '.local', '.segment',
                            '.macro', '.endmacro', '.endmac', '.if', '.endif', '.else',
                            '.p816', '.smart') else 64
        else:
            n += 4
    return n


_MAGIC = {}


def magic16(k, hi):
    """(pre, M, s, add) such that, for every x in 0..hi, x / k (unsigned, k not a power of
    two) is t >> s with t = ((x >> pre) * M) >> 16 (add: (t + (((x >> pre) - t) >> 1)) >>
    (s - 1), a 17-bit multiplier's form); M < 65536. Every x is tried (cached): a candidate
    is taken only when it is exact for all of them. None when there is none."""
    key = (k, hi)
    if key in _MAGIC:
        return _MAGIC[key]
    r = None
    tz = (k & -k).bit_length() - 1
    for add in (False, True):
        for pre in ((0, tz) if tz else (0,)):
            kk = k >> pre
            for s in range(1 if add else 0, 17):
                M = -(-(1 << (16 + s)) // kk) - ((1 << 16) if add else 0)
                if not 0 < M < 0x10000:
                    continue
                ok = True
                for x in range(hi + 1):
                    y = x >> pre
                    t = (y * M) >> 16
                    q = (t + ((y - t) >> 1)) >> (s - 1) if add else t >> s
                    if q != x // k:
                        ok = False
                        break
                if ok:
                    r = (pre, M, s, add)
                    break
            if r:
                break
        if r:
            break
    _MAGIC[key] = r
    return r


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
        # the large code model (hcc --code large): JSL/RTL, the return address 3 bytes, a
        # function's 16-bit address (a pointer) its entry in the main bank, __T<name>
        self.large = bool(opts.get('large'))
        self.RA = 3 if self.large else 2       # the return address's size
        self.funcnames = getattr(unit, 'funcnames', ()) if self.large else ()
        self.far_model = bool(getattr(unit, 'far_model', False))

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
        self.I('jsl' if self.large else 'jsr', name)

    def hname(self, name):
        """a symbol as a value: in the large model a function's is its main-bank entry"""
        return '__T' + name if name in self.funcnames else name

    def farsym(self, name):
        """the far data model: the object name is reached by long addressing (it lies in
        far data, or may: front.py's farsyms)"""
        return self.far_model and name in self.unit.farsyms

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
            return f'{1 + self.push + self.F + self.C + self.RA + off + 2 * part},s'
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
            return f'#{self.hname(o.name)}' + (f'+{o.off}' if o.off > 0 else (f'-{-o.off}' if o.off < 0 else ''))
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
        if isinstance(o, V) and 2 * part >= o.size:
            self.I('lda', '#0')
            return
        if isinstance(o, Sym) and part >= 1:
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
        if isinstance(o, V) and 2 * part >= o.size:
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
            chk = self.opts.get('sscheck', SSCHECK)
            if chk and self.S >= chk:
                # the software stack's check: below its lowest address (__hz_sslo, the
                # guard zone's start: the heap is under it) is an overflow, which
                # ___hz_sovf (rt/crt0.s) reports with the function's name; JSR/JSL there
                # with the frame's size and the name after it, never returns (10 cycles
                # when the frame fits)
                ovf, ok = self.newlab(), self.newlab()
                self.I('bcc', ovf)
                self.I('cmp', '___hz_sslo')
                self.I('bcs', ok)
                self.helpers.add('___hz_sslo')
                name = getattr(f, 'cname', f.name.lstrip('_'))
                self.L(ovf)
                self.helper('___hz_sovf')
                self.out.append(('D', f'.word {hexw(self.S)}', 2))
                self.out.append(('D', f'.byte "{name}", 0', len(name) + 1))
                self.L(ok)
            self.I('sta', '__sp')
        for p, loc in f.param_copies:
            for part in range(p.size // 2):
                self.I('lda', f'{1 + self.F + self.C + self.RA + p.param + 2 * part},s')
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
        self.I('rtl' if self.large else 'rts')

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
        for p in range(d.size // 2):
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
        for p in range(d.size // 2):
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
        for p in range(d.size // 2):
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
        if d.size == 8:
            return self.shift64(i, kind)
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
            return self.shift32c(kind, b.val & 0xFFFF, a, d)
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

    def bsrc(self, o, b):
        """the operand text for the (unaligned) word at byte b of a 32-bit V in the direct
        page or on the hardware stack, else None"""
        if not isinstance(o, V) or o.size != 4 or o is self.res or o.loc is None:
            return None
        kind, off = o.loc
        if kind == 'dp':
            return f'__rg+{off + b}'
        if kind == 'sr':
            return f'{1 + self.push + off + b},s'
        if kind == 'home':
            return f'{1 + self.push + self.F + self.C + self.RA + off + b},s'
        return None

    def shift32c(self, kind, k, a, d, h0=False):
        """a 32-bit shift of a by the constant k into the V d (d may be a: every word of a
        is read before d is written). h0: the value is in __h0 instead of a. 16 or more: a
        word move; then 8 or more: a byte (an unaligned word load); then k % 8 bit steps,
        one word in A and the other in __h0"""
        if h0:
            def ld(p):
                self.I('lda', '__h0+2' if p else '__h0')

            def bt(n):
                return f'__h0+{n}'
        else:
            def ld(p):
                self.lda(a, p)

            def bt(n):
                return self.bsrc(a, n)
        # (the bit tricks keep the carry between two loads: not a Frame's address)
        plain = h0 or isinstance(a, (V, Imm))
        if k >= 32:
            if kind == 'sshr':
                ld(1)
                self.sign_word()
                self.sta(d, 0)
                self.sta(d, 1)
            else:
                self.stz(d, 0)
                self.stz(d, 1)
            return
        if k >= 16:
            if kind == 'shl':
                ld(0)
                self.shift_a('shl', k - 16)
                self.sta(d, 1)
                self.stz(d, 0)
            elif kind == 'ushr':
                ld(1)
                self.shift_a('ushr', k - 16)
                self.sta(d, 0)
                self.stz(d, 1)
            else:
                ld(1)
                self.shift_a('sshr', k - 16)
                self.sta(d, 0)
                self.sign_word()
                self.sta(d, 1)
            return
        if k == 7 and kind == 'shl' and plain:
            # (x >> 1) << 8, x's bit 0 into bit 7 (x * 128: 48 cycles, not 85)
            lo = self.newlab()
            ld(1)
            self.I('lsr', 'a')
            self.I('sta', '__h0+2')
            ld(0)
            self.I('ror', 'a')
            self.I('sta', '__h0')
            self.I('xba')
            self.I('and', '#$FF00')
            self.I('bcc', lo)
            self.I('ora', '#$0080')
            self.L(lo)
            self.I('tay')
            self.I('lda', '__h0+1')
            self.sta(d, 1)
            self.I('tya')
            self.sta(d, 0)
            return
        if k == 15 and kind == 'shl' and plain:
            # (x >> 1) << 16, x's bit 0 into bit 15
            ld(1)
            self.I('lsr', 'a')
            ld(0)
            self.I('ror', 'a')
            self.sta(d, 1)
            self.I('lda', '#0')
            self.I('ror', 'a')
            self.sta(d, 0)
            return
        if k == 7 and plain:
            # (x << 1) >> 8: bytes 1-2 of x << 1 the low word; byte 3 and the bit shifted
            # out (x's sign) the high one
            hi = self.newlab()
            ld(0)
            self.I('asl', 'a')
            self.I('sta', '__h0')
            ld(1)
            self.I('rol', 'a')
            self.I('sta', '__h0+2')
            self.I('xba')
            self.I('and', '#$00FF')
            self.I('bcc', hi)
            self.I('ora', '#$0100' if kind == 'ushr' else '#$FF00')
            self.L(hi)
            self.I('tay')
            self.I('lda', '__h0+1')
            self.sta(d, 0)
            self.I('tya')
            self.sta(d, 1)
            return
        if k == 15 and plain:
            # (x << 1) >> 16
            ld(0)
            self.I('asl', 'a')
            ld(1)
            self.I('rol', 'a')
            self.sta(d, 0)
            self.I('lda', '#0')
            if kind == 'ushr':
                self.I('rol', 'a')
            else:
                self.I('adc', '#$FFFF')
                self.I('eor', '#$FFFF')
            self.sta(d, 1)
            return
        b1 = bt(1) if k >= 8 else None
        if kind == 'shl':
            if b1 is not None:
                # bytes 1-2 become the high word, byte 0 the high byte of the low one
                self.I('lda', b1)
                self.I('tay')
                ld(0)
                self.I('xba')
                self.I('and', '#$FF00')
                self.I('sta', '__h0')
                self.I('tya')
                k -= 8
            else:
                ld(0)
                self.I('sta', '__h0')
                ld(1)
            for _ in range(k):
                self.I('asl', '__h0')
                self.I('rol', 'a')
        else:
            if b1 is not None:
                # bytes 1-2 become the low word, byte 3 (extended) the high one
                self.I('lda', b1)
                self.I('sta', '__h0')
                self.I('lda', bt(3))
                self.I('and', '#$00FF')
                if kind == 'sshr':
                    self.I('eor', '#$0080')
                    self.I('sec')
                    self.I('sbc', '#$0080')
                k -= 8
            else:
                ld(0)
                self.I('sta', '__h0')
                ld(1)
            for _ in range(k):
                if kind == 'ushr':
                    self.I('lsr', 'a')
                else:
                    self.I('cmp', '#$8000')
                    self.I('ror', 'a')
                self.I('ror', '__h0')
        self.sta(d, 1)
        self.I('lda', '__h0')
        self.sta(d, 0)

    def sign_word(self):
        """A = $FFFF when bit 15 of A is set, else 0"""
        self.I('asl', 'a')
        self.I('lda', '#0')
        self.I('adc', '#$FFFF')
        self.I('eor', '#$FFFF')

    def shift64(self, i, kind):
        """64-bit shifts: by a multiple of 16, word moves; by another constant or a
        variable, __shl64 / __shr64 / __sar64 (__h0..__h1 shifted by X)"""
        d, a, b = i.d, i.a, i.b
        if isinstance(b, Imm) and (b.val & 0xFFFF) % 16 == 0:
            k = (b.val & 0xFFFF) // 16
            if k >= 4:
                if kind == 'sshr':
                    self.lda(a, 3)
                    self.sign_word()
                    for p in range(4):
                        self.sta(d, p)
                else:
                    for p in range(4):
                        self.stz(d, p)
                return
            if kind == 'shl':           # high words first (d may be a)
                for p in range(3, -1, -1):
                    if p - k >= 0:
                        self.lda(a, p - k)
                        self.sta(d, p)
                    else:
                        self.stz(d, p)
                return
            for p in range(4):          # low words first
                if p + k <= 3:
                    self.lda(a, p + k)
                    self.sta(d, p)
                elif kind == 'ushr':
                    self.stz(d, p)
                else:
                    self.lda(a, 3)
                    self.sign_word()
                    for q in range(p, 4):
                        self.sta(d, q)
                    break
            return
        self.load_h(a, '__h0', 4)
        if isinstance(b, Imm) and (b.val & 0xFFFF) <= 3:
            # by 1 to 3: inline, a bit at a time through __h0..__h1
            for _ in range(b.val & 0xFFFF):
                if kind == 'shl':
                    self.I('asl', '__h0')
                    for p in (1, 2, 3):
                        self.I('rol', f'__h0+{2 * p}')
                    continue
                if kind == 'ushr':
                    self.I('lsr', '__h0+6')
                else:
                    self.I('lda', '__h0+6')
                    self.I('cmp', '#$8000')
                    self.I('ror', '__h0+6')
                for p in (2, 1, 0):
                    self.I('ror', f'__h0+{2 * p}' if p else '__h0')
            self.store_h(d, '__h0')
            return
        self.ldx(b)
        self.helper({'shl': '__shl64', 'ushr': '__shr64', 'sshr': '__sar64'}[kind])
        self.store_h(d, '__h0')

    def load_h(self, o, reg, words):
        """o (extended with zeros as needed) into the direct page from reg"""
        for p in range(words):
            w = f'{reg}+{2 * p}' if p else reg
            if isinstance(o, Imm) and (o.val >> (16 * p)) & 0xFFFF == 0 or \
                    isinstance(o, (V, Sym)) and 2 * p >= o.size:
                self.I('stz', w)
                continue
            self.lda(o, p)
            self.I('sta', w)

    def store_h(self, d, reg):
        for p in range(d.size // 2):
            self.I('lda', f'{reg}+{2 * p}' if p else reg)
            self.sta(d, p)

    def call64(self, h, i):
        """a 64-bit helper: a in __h0..__h1, b in __h2..__h3, the result in __h0..__h1"""
        self.load_h(i.a, '__h0', 4)
        self.load_h(i.b, '__h2', 4)
        self.helper(h)
        self.store_h(i.d, '__h0')

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
        if d.size == 8:
            return self.call64('__mul64', i)
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

    @staticmethod
    def naf(k):
        """k's digits (-1, 0, 1), the highest first, with the fewest non-zero ones (the
        non-adjacent form: 31 = 32 - 1 is 1 0 0 0 0 -1)"""
        out = []
        while k:
            if k & 1:
                z = 2 - (k & 3)
                k -= z
            else:
                z = 0
            out.append(z)
            k >>= 1
        return out[::-1]

    def mul_const(self, d, a, k):
        """x * k by shifts and adds or subtracts (k with few non-zero digits in the binary
        or the non-adjacent form: x * 31 = x * 32 - x; an array of 31-byte structures)"""
        if isinstance(a, Frame):
            return False
        k &= 0xFFFF
        if k == 0:
            return False
        digits = [int(c) for c in bin(k)[2:]]
        nf = self.naf(k)
        if sum(1 for z in nf if z) < sum(digits):
            digits = nf
        if sum(1 for z in digits if z) > 4:
            return False
        s = self.src(a)
        self.lda(a)
        for z in digits[1:]:
            self.I('asl', 'a')
            if z == 1:
                self.I('clc')
                self.I('adc', s)
            elif z == -1:
                self.I('sec')
                self.I('sbc', s)
        self.sta(d)
        return True

    # Division by constants. C truncates toward zero; a remainder has the sign of the
    # dividend. Signed x / 2^n is (x + (x < 0 ? 2^n - 1 : 0)) >> n, arithmetically;
    # x % 2^n is x & (2^n - 1) for x >= 0, else -((-x) & (2^n - 1)) (x = INT_MIN too: -x
    # is INT_MIN again, whose low bits are 0). A 16-bit divide by another constant is a
    # multiply by its reciprocal (magic16: checked for every dividend when chosen).
    def sdiv_pow2(self, i):
        """a signed 16-bit x / 2^n or x / -2^n (n 1-14): no call (the Xargon port: every
        position / 16)"""
        k = i.b.val & 0xFFFF
        neg = bool(k & 0x8000)
        if neg:
            k = 0x10000 - k
        if k < 2 or k & (k - 1) or k >= 0x8000:
            return False
        n = k.bit_length() - 1
        pos = self.newlab()
        self.lda(i.a)
        self.I('cmp', '#$8000')         # (carry: negative)
        self.I('bcc', pos)
        self.I('adc', f'#{k - 2}')      # (+ k - 1 with the carry)
        self.L(pos)
        self.shift_a('sshr', n)
        if neg:
            self.I('eor', '#$FFFF')
            self.I('inc', 'a')
        self.sta(i.d)
        return True

    def smod_pow2(self, i):
        """a signed 16-bit x % 2^n or x % -2^n (n 1-15)"""
        k = i.b.val & 0xFFFF
        if k & 0x8000 and k != 0x8000:
            k = 0x10000 - k
        if k < 2 or k & (k - 1):
            return False
        neg, done = self.newlab(), self.newlab()
        self.lda(i.a)
        self.I('bmi', neg)
        self.I('and', '#' + hexw(k - 1))
        self.I('bra', done)
        self.L(neg)
        self.I('eor', '#$FFFF')
        self.I('inc', 'a')
        self.I('and', '#' + hexw(k - 1))
        self.I('eor', '#$FFFF')
        self.I('inc', 'a')
        self.L(done)
        self.sta(i.d)
        return True

    def sdiv32_pow2(self, i):
        """a signed 32-bit x / 2^n or x / -2^n (n 1-30): the bias added in __h0, the
        arithmetic shift from there (the SkyRoads port: long / 512, / 16)"""
        k = i.b.val & 0xFFFFFFFF
        neg = bool(k & 0x80000000)
        if neg:
            k = 0x100000000 - k
        if k < 2 or k & (k - 1) or k >= 0x80000000 or not isinstance(i.a, V):
            return False
        n = k.bit_length() - 1
        a, d = i.a, i.d
        pos, join = self.newlab(), self.newlab()
        self.lda(a, 1)
        self.I('bpl', pos)
        self.I('clc')
        self.lda(a, 0)
        self.I('adc', '#' + hexw(k - 1))
        self.I('sta', '__h0')
        self.lda(a, 1)
        self.I('adc', '#' + hexw((k - 1) >> 16))
        self.I('bra', join)
        self.L(pos)
        self.lda(a, 0)
        self.I('sta', '__h0')
        self.lda(a, 1)
        self.L(join)
        self.I('sta', '__h0+2')
        self.shift32c('sshr', n, None, d, h0=True)
        if neg:
            self.I('sec')
            for p in (0, 1):
                self.I('lda', '#0')
                self.I('sbc', self.vaddr(d, p))
                self.sta(d, p)
        return True

    def smod32_pow2(self, i):
        """a signed 32-bit x % 2^n or x % -2^n (n 1-31)"""
        k = i.b.val & 0xFFFFFFFF
        if k & 0x80000000 and k != 0x80000000:
            k = 0x100000000 - k
        if k < 2 or k & (k - 1) or not isinstance(i.a, V):
            return False
        m = k - 1
        a, d = i.a, i.d
        pos, done = self.newlab(), self.newlab()
        self.lda(a, 1)
        self.I('bpl', pos)
        # -((-x) & m)
        self.I('sec')
        self.I('lda', '#0')
        self.I('sbc', self.opsrc(a, 0))
        self.I('and', '#' + hexw(m))
        self.I('sta', '__h0')
        self.I('lda', '#0')
        self.I('sbc', self.opsrc(a, 1))
        self.I('and', '#' + hexw(m >> 16))
        self.I('sta', '__h0+2')
        self.I('sec')
        self.I('lda', '#0')
        self.I('sbc', '__h0')
        self.sta(d, 0)
        self.I('lda', '#0')
        self.I('sbc', '__h0+2')
        self.sta(d, 1)
        self.I('bra', done)
        self.L(pos)
        self.lda(a, 0)
        self.I('and', '#' + hexw(m))
        self.sta(d, 0)
        self.lda(a, 1)
        self.I('and', '#' + hexw(m >> 16))
        self.sta(d, 1)
        self.L(done)
        return True

    def mulc_a(self, k, s):
        """A = A * k (16 bits), A's value also in the operand s: shifts and adds or
        subtracts (the binary or the non-adjacent form, the fewer non-zero digits)"""
        digits = [int(c) for c in bin(k)[2:]]
        nf = self.naf(k)
        if sum(1 for z in nf if z) < sum(digits):
            digits = nf
        for z in digits[1:]:
            self.I('asl', 'a')
            if z == 1:
                self.I('clc')
                self.I('adc', s)
            elif z == -1:
                self.I('sec')
                self.I('sbc', s)

    def div16_const(self, i, signed, mod):
        """a 16-bit x / k or x % k, k a constant other than a power of two: the quotient
        is (|x| * M) >> (16 + s) (M and s from magic16, exact for every dividend), the
        multiply inline (M is known); a remainder x - q * k"""
        if isinstance(i.a, Imm):
            return False
        k = i.b.val & 0xFFFF
        a, d = i.a, i.d
        negk = False
        if signed and k & 0x8000:
            if k == 0x8000:
                return False
            k, negk = 0x10000 - k, True
        if k < 3 or not k & (k - 1):
            return False
        if not signed and k >= 0x8000:
            # the quotient is 0 or 1
            self.lda(a)
            self.I('cmp', '#' + hexw(k))
            if mod:
                done = self.newlab()
                self.I('bcc', done)
                self.I('sbc', '#' + hexw(k))
                self.L(done)
            else:
                self.I('lda', '#0')
                self.I('rol', 'a')
            self.sta(d)
            return True
        mg = magic16(k, 0x8000 if signed else 0xFFFF)
        if mg is None:
            return False
        pre, M, sh, add = mg
        self.lda(a)
        if signed:
            pos = self.newlab()
            self.I('bpl', pos)
            self.I('eor', '#$FFFF')
            self.I('inc', 'a')
            self.L(pos)
        for _ in range(pre):
            self.I('lsr', 'a')
        self.I('sta', '__h0')
        # t = (x * M) >> 16 inline, M's bits from the lowest: a one adds x, then every bit
        # halves the 17-bit sum (carry and A); each halving's dropped bit only floors,
        # so t is exact (about 8 cycles a one-bit, 2 a zero)
        first = True
        for bit in range(16):
            if not (M >> bit) & 1:
                if not first:
                    self.I('lsr', 'a')
                continue
            if not first:
                self.I('clc')
                self.I('adc', '__h0')
                self.I('ror', 'a')
            else:
                self.I('lsr', 'a')      # (t = x, halved: no carry)
                first = False
        if add:
            # (t + ((x - t) >> 1)) >> (s - 1): the 17-bit multiplier's form
            self.I('sta', '__h1')
            self.I('lda', '__h0')
            self.I('sec')
            self.I('sbc', '__h1')
            self.I('lsr', 'a')
            self.I('clc')
            self.I('adc', '__h1')
            sh -= 1
        self.shift_a('ushr', sh)
        # A = |x| / k
        if mod:
            self.I('sta', '__h1')
            self.mulc_a(k, '__h1')
            self.I('sta', '__h1')
            self.lda(a)
            if signed:
                # x < 0: x + q * k, else x - q * k (the remainder takes x's sign)
                neg, done = self.newlab(), self.newlab()
                self.I('bmi', neg)
                self.I('sec')
                self.I('sbc', '__h1')
                self.I('bra', done)
                self.L(neg)
                self.I('clc')
                self.I('adc', '__h1')
                self.L(done)
            else:
                self.I('sec')
                self.I('sbc', '__h1')
            self.sta(d)
            return True
        if signed:
            keep, done = self.newlab(), self.newlab()
            self.I('tay')
            self.lda(a)
            self.I('bmi' if negk else 'bpl', keep)
            self.I('tya')
            self.I('eor', '#$FFFF')
            self.I('inc', 'a')
            self.I('bra', done)
            self.L(keep)
            self.I('tya')
            self.L(done)
        self.sta(d)
        return True

    def divmod16(self, i, h):
        self.ldx(i.b)
        self.lda(i.a)
        self.helper(h)
        self.sta(i.d)

    def g_udiv(self, i):
        if i.d.size == 2:
            if isinstance(i.b, Imm) and self.div16_const(i, False, False):
                return
            return self.divmod16(i, '__udiv16')
        if i.d.size == 8:
            return self.call64('__udiv64', i)
        self.call32('__udiv32', i)

    def g_sdiv(self, i):
        if i.d.size == 2:
            if isinstance(i.b, Imm) and (self.sdiv_pow2(i) or self.div16_const(i, True, False)):
                return
            return self.divmod16(i, '__sdiv16')
        if i.d.size == 8:
            return self.call64('__sdiv64', i)
        if isinstance(i.b, Imm) and self.sdiv32_pow2(i):
            return
        self.call32('__sdiv32', i)

    def g_umod(self, i):
        if i.d.size == 2:
            if isinstance(i.b, Imm) and self.div16_const(i, False, True):
                return
            return self.divmod16(i, '__umod16')
        if i.d.size == 8:
            return self.call64('__umod64', i)
        self.call32('__umod32', i)

    def g_smod(self, i):
        if i.d.size == 2:
            if isinstance(i.b, Imm) and (self.smod_pow2(i) or self.div16_const(i, True, True)):
                return
            return self.divmod16(i, '__smod16')
        if i.d.size == 8:
            return self.call64('__smod64', i)
        if isinstance(i.b, Imm) and self.smod32_pow2(i):
            return
        self.call32('__smod32', i)

    # --- floating point (rt/fp_*.s): the operands in __h0 (and __h1), the result
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
        n = i.a.size // 2
        for p in range(n):
            self.lda(i.a, p)
            self.sta(i.d, p)
        for p in range(n, i.d.size // 2):
            self.stz(i.d, p)

    def g_sx(self, i):
        n = i.a.size // 2
        for p in range(n):
            self.lda(i.a, p)
            self.sta(i.d, p)
        self.sign_word()
        for p in range(n, i.d.size // 2):
            self.sta(i.d, p)

    def g_tr(self, i):
        for p in range(i.d.size // 2):
            self.lda(i.a, p)
            self.sta(i.d, p)

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
        if isinstance(i.a, Sym) and (getattr(self.unit, 'fardata', False) or self.far_model) \
                and i.a.name in self.unit.farsyms:
            # a __far object in a bank of its own (the large model): its offset, and its
            # bank, which hcc's link patches (the bank byte is recorded: driver.far_lines)
            a = self.symoff(i.a.name, i.a.off)
            self.I('lda', f'#.loword({a})')
            self.sta(i.d, 0)
            self.I('lda', f'#^({a})')
            self.sta(i.d, 1)
            return
        self.lda(i.a)
        self.sta(i.d, 0)
        if False:
            pass
        elif isinstance(i.a, (Sym, Frame)):
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
        if isinstance(base, Imm):
            # a constant address (the optimiser put a constant pointer's value here)
            v = base.val
            if base.size == 4:
                self.I('lda', '#' + hexw(v & 0xFFFF))
                self.I('sta', '__h2')
                self.I('lda', '#' + hexw((v >> 16) & 0xFFFF))
                self.I('sta', '__h2+2')
                if idx is None:
                    self.I('ldy', '#' + hexw(off))
                else:
                    self.add_to_y(idx, off)
                return self.yseq('[__h2],y', off if idx is None else None)
            base = Sym('__abs0', v & 0xFFFF)
        if isinstance(base, Sym):
            name = base.name
            o = base.off + off
            # (the far data model: a far object by long addressing, f:name and
            # f:name,x: one byte and one cycle more than absolute addressing)
            fa = 'f:' if self.farsym(name) else ''
            if idx is None:
                return lambda p: fa + self.symoff(name, o + 2 * p)
            if isinstance(idx, Imm):
                return lambda p: fa + self.symoff(name, o + idx.val + 2 * p)
            self.ldx(idx)
            return lambda p: fa + self.symoff(name, o + 2 * p) + ',x'
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
        if sz >= 4:
            for p in range(sz // 2):
                self.I('lda', acc(p))
                self.sta(d, p)
            return
        base = i.x['base']
        if sz == 1 and ((isinstance(base, V) and base.size == 4) or i.x.get('vol') or
                        (isinstance(base, Sym) and self.farsym(base.name))):
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
            if isinstance(a, Imm) and a.val & 0xFF == 0 and not t.startswith('(') and \
                    not t.startswith('[') and not t.startswith('f:'):
                self.I('stz', t)
            else:
                self.lda8(a)
                self.I('sta', t)
            self.I('rep', '#$20')
            return
        for p in range(max(sz // 2, 1)):
            t = acc(p)
            if isinstance(a, Imm) and (a.val >> (16 * p)) & 0xFFFF == 0 and \
                    not t.startswith('(') and not t.startswith('[') and not t.startswith('f:'):
                self.I('stz', t)
                continue
            self.lda(a, p)
            self.I('sta', t)

    def lda8(self, a):
        if isinstance(a, Imm):
            self.I('lda', f'#${a.val & 0xFF:02X}')
        elif isinstance(a, Sym):
            self.I('lda', f'#<({self.symoff(self.hname(a.name), a.off)})')
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
        self.I('mvn', self.mvn_banks())

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
                if t.startswith('(') or t.startswith('f:'):
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
            self.I('mvn', self.mvn_banks())

    def mvn_banks(self):
        """MVN's banks: the data bank's (the main bank's: a symbol there in the large model,
        where the function may sit in another bank)"""
        b = '__fpt' if self.large else self.f.name
        return f'#^{b}, #^{b}'

    def g_vastart(self, i):
        self.I('tsc')
        self.I('clc')
        self.I('adc', '#' + hexw(1 + self.push + self.F + self.C + self.RA + self.f.argsize))
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
        """inline assembly: the text with the registers of the variables it names put in,
        after a label of its own (the text's @labels are local to it), then .a16 / .i16
        again for the code after it"""
        vs = i.x.get('vars') or []
        text = re.sub('\x00(\\d+)\x00', lambda m: self.vaddr(vs[int(m.group(1))]), i.x['text'])
        lines = [f'L{self.f.name[1:]}_asm{i.x.get("n", 0)}:'] + text.split('\n') + \
            ['\t.a16', '\t.i16']
        self.out.append(('ASM', '\n'.join(lines), asm_size(text)))

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
            self.I('jsl' if self.large else 'jsr', tgt.name)
        elif self.large:
            # through a pointer: __icall (crt0.s, main bank) jumps to it, JMP (__fpt,X)
            self.lda(tgt)
            self.I('sta', '__fpt')
            self.I('jsl', '__icall')
            self.helpers.add('__fpt')
            self.helpers.add('__icall')
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
            if i.d.size == 8:
                self.store_h(i.d, '__h0')      # a long long result: in __h0..__h1
            elif i.d.size == 4:
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
            self.I('pea', self.symoff(self.hname(a.name), a.off) if p == 0 else '0')
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
            if a.size == 8:
                self.load_h(a, '__h0', 4)      # a long long result: in __h0..__h1
            elif a.size == 4:
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
        if a.size == 8 or b.size == 8:
            return self.br64(i)
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

    def g_set(self, i):
        """d = a cc b as 0 / 1 (opt.setcc), without branches where it can: the carry of a
        compare (unsigned), the sign of the difference (signed), a nonzero test (eq, ne)
        rotated into A"""
        cc, a, b = i.x['cc'], i.a, i.b
        size = max(a.size, b.size)
        n = size // 2
        if isinstance(a, (Imm, Sym, Frame)) and not isinstance(b, (Imm, Sym, Frame)):
            a, b = b, a
            cc = {'ult': 'ugt', 'ugt': 'ult', 'ule': 'uge', 'uge': 'ule', 'slt': 'sgt',
                  'sgt': 'slt', 'sle': 'sge', 'sge': 'sle'}.get(cc, cc)
        if isinstance(b, Imm):
            # x <= k -> x < k + 1, x > k -> x >= k + 1 (k not the largest value)
            m = (1 << (8 * size)) - 1
            k = b.val
            if cc in ('ule', 'ugt') and k < m:
                cc, b = ('ult' if cc == 'ule' else 'uge'), Imm(k + 1, b.size)
            elif cc in ('sle', 'sgt') and k != m >> 1:
                cc, b = ('slt' if cc == 'sle' else 'sge'), Imm((k + 1) & m, b.size)
        if cc in ('ugt', 'ule', 'sgt', 'sle'):
            a, b = b, a
            cc = {'ugt': 'ult', 'ule': 'uge', 'sgt': 'slt', 'sle': 'sge'}[cc]
        flip = False
        if cc in ('eq', 'ne'):
            # A = 0 exactly when a == b; then C = (A != 0)
            if isinstance(b, Imm) and b.val == 0:
                self.lda(a, 0)
                for p in range(1, n):
                    self.I('ora', self.opsrc(a, p))
            else:
                if n > 1:
                    self.lda(a, 1)
                    self.I('eor', self.opsrc(b, 1))
                    self.I('sta', '__h0')
                self.lda(a, 0)
                self.I('eor', self.opsrc(b, 0))
                if n > 1:
                    self.I('ora', '__h0')
            self.I('cmp', '#$0001')
            self.I('lda', '#0')
            self.I('rol', 'a')
            flip = cc == 'eq'
        elif cc in ('ult', 'uge'):
            # the carry of a - b: set when a >= b
            self.lda(a, 0)
            self.I('cmp', self.opsrc(b, 0))
            for p in range(1, n):
                self.lda(a, p)
                self.I('sbc', self.opsrc(b, p))
            self.I('lda', '#0')
            self.I('rol', 'a')
            flip = cc == 'ult'
        else:
            # slt / sge: the sign of a - b (corrected for an overflow) into the carry
            if isinstance(b, Imm) and b.val == 0:
                self.lda(a, n - 1)
            elif n == 1 and isinstance(b, Imm):
                # biased: a ^ $8000 >= k ^ $8000 unsigned (the carry)
                self.lda(a)
                self.I('eor', '#$8000')
                self.I('cmp', '#' + hexw(b.val ^ 0x8000))
                self.I('lda', '#0')
                self.I('rol', 'a')
                if cc == 'slt':
                    self.I('eor', '#$0001')
                self.sta(i.d)
                return
            else:
                self.lda(a, 0)
                if n == 1:
                    self.I('sec')
                    self.I('sbc', self.opsrc(b, 0))
                else:
                    self.I('cmp', self.opsrc(b, 0))
                    for p in range(1, n):
                        self.lda(a, p)
                        self.I('sbc', self.opsrc(b, p))
                ok = self.newlab()
                self.I('bvc', ok)
                self.I('eor', '#$8000')
                self.L(ok)
            self.I('asl', 'a')
            self.I('lda', '#0')
            self.I('rol', 'a')
            flip = cc == 'sge'
        if flip:
            self.I('eor', '#$0001')
        self.sta(i.d)

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
        if cc in ('slt', 'sge') and isinstance(b, Imm) and b.val == 0 and not isinstance(a, Imm):
            # x < 0, x >= 0: the high word's sign
            self.lda(a, 1)
            self.branch('bmi' if cc == 'slt' else 'bpl', t, f)
            return
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

    def br64(self, i):
        """a 64-bit compare and branch, inline: eq / ne word by word, the others a
        subtraction's carry (unsigned) or sign and overflow (signed)"""
        cc = i.x['cc']
        a, b = i.a, i.b
        t, f = i.x['t'], i.x['f']
        if cc in ('eq', 'ne'):
            if isinstance(b, Imm) and b.val == 0:
                self.lda(a, 0)
                for p in (1, 2, 3):
                    self.I('ora', self.opsrc(a, p))
                self.branch('beq' if cc == 'eq' else 'bne', t, f)
                return
            for p in range(3):
                self.lda(a, p)
                self.I('cmp', self.opsrc(b, p))
                self.I('bne', self.blab(f if cc == 'eq' else t))
            self.lda(a, 3)
            self.I('cmp', self.opsrc(b, 3))
            self.branch('beq' if cc == 'eq' else 'bne', t, f)
            return
        if cc in ('ugt', 'ule', 'sgt', 'sle'):
            a, b = b, a
            cc = {'ugt': 'ult', 'ule': 'uge', 'sgt': 'slt', 'sle': 'sge'}[cc]
        self.lda(a, 0)
        self.I('cmp', self.opsrc(b, 0))
        for p in (1, 2, 3):
            self.lda(a, p)
            self.I('sbc', self.opsrc(b, p))
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
        for lo, hi, l in i.x.get('ranges', ()):
            # a GNU case range of a 16-bit switch: a - lo < hi - lo + 1, unsigned
            self.lda(a)
            if hi - lo + 1 >= 0x10000:
                self.I('jmp', self.blab(l))
                continue
            if lo & 0xFFFF:
                self.I('sec')
                self.I('sbc', '#' + hexw(lo))
            self.I('cmp', '#' + hexw(hi - lo + 1))
            self.I('bcc', self.blab(l))
        if a.size >= 4:
            n = a.size // 2
            for v, l in cases:
                nxt = self.newlab()
                for p in range(n):
                    self.lda(a, p)
                    self.I('cmp', '#' + hexw(v >> (16 * p)))
                    self.I('bne' if p < n - 1 else 'beq', nxt if p < n - 1 else self.blab(l))
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
