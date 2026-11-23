"""The intermediate representation.

A function is a list of basic blocks; a block is a list of instructions ending with a
terminator (br, jmp, ret, switch). Values live in virtual registers (V, 2 or 4 bytes) that
the register allocator maps to direct-page locations or hardware-stack slots. Operands:
V, Imm (a constant), Sym (the address of a global + offset, a link-time constant),
Frame (the address of an object in the function's software-stack frame).

Instructions (Ins.op):
  mov d a                      d = a
  add sub mul and or xor       d = a op b            (size = d.size)
  udiv sdiv umod smod
  shl ushr sshr                d = a shift b         (b is a 16-bit count)
  neg com                      d = -a, ~a
  zx sx                        d(4) = a(2) zero / sign extended
  tr                           d(2) = low word of a(4)
  x8u x8s                      d(2) = low byte of a, zero / sign extended
  ld  d base idx off sz sgn    d = *(base + idx + off), sz 1/2/4 bytes
  st  base idx off sz a        *(base + idx + off) = a
  call d tgt args              args: list of operands (pushed right to left)
  br  cc a b Lt Lf             compare and branch (cc: eq ne ult ule ugt uge slt sle sgt sge)
  set d cc a b                 d(2) = 1 if a cc b else 0 (a, b 2 or 4 bytes; opt.setcc)
  jmp L
  ret a
  sw  a cases default          jump table / compare chain: cases = [(value, label)];
                               ranges = [(lo, hi, label)] (GNU case ranges, tested first)
  copy dst src n               memcpy of n bytes between near addresses
  fcopy dst src n              the same between far addresses (32-bit operands: __fcopy)
  zero dst n                   memset 0
  vastart d                    d(4) = far address of the first variadic argument
  cop d n a x y                syscall: COP #n with A, X, Y -> d (A)
  asm text vars                inline assembly; vars: the V it names (%[name]), each used
                               and changed by it (they live in direct-page registers)
"""


class V:
    __slots__ = ('id', 'size', 'name', 'loc', 'param', 'weight', 'across', 'pinned')

    def __init__(self, id, size, name=None):
        self.id = id
        self.size = size
        self.name = name
        self.loc = None      # ('dp', off) / ('sr', off) / ('home', off) after allocation
        self.param = None    # incoming argument stack offset (from the first argument)
        self.weight = 0
        self.across = False
        self.pinned = None

    def __repr__(self):
        return f'%{self.name or ""}{self.id}' + ('L' if self.size == 4 else '')


class Imm:
    __slots__ = ('val', 'size')

    def __init__(self, val, size=2):
        self.size = size
        self.val = val & ((1 << (8 * size)) - 1)

    def __repr__(self): return f'#{self.val}'

    def __eq__(self, o): return isinstance(o, Imm) and o.val == self.val and o.size == self.size

    def __hash__(self): return hash((self.val, self.size))


class Sym:
    __slots__ = ('name', 'off', 'size')

    def __init__(self, name, off=0):
        self.name = name
        self.off = off
        self.size = 2

    def __repr__(self): return f'&{self.name}' + (f'+{self.off}' if self.off else '')

    def __eq__(self, o): return isinstance(o, Sym) and o.name == self.name and o.off == self.off

    def __hash__(self): return hash((self.name, self.off))


class Frame:
    """address of a software-stack frame object"""
    __slots__ = ('slot', 'off', 'size')

    def __init__(self, slot, off=0):
        self.slot = slot     # FrameSlot
        self.off = off
        self.size = 2

    def __repr__(self): return f'&[{self.slot.name}]' + (f'+{self.off}' if self.off else '')

    def __eq__(self, o): return isinstance(o, Frame) and o.slot is self.slot and o.off == self.off

    def __hash__(self): return hash((id(self.slot), self.off))


class FrameSlot:
    def __init__(self, name, size):
        self.name = name
        self.size = size
        self.off = None      # offset from __sp after the prologue


class Ins:
    __slots__ = ('op', 'd', 'a', 'b', 'x')

    def __init__(self, op, d=None, a=None, b=None, **x):
        self.op = op
        self.d = d
        self.a = a
        self.b = b
        self.x = x

    def __repr__(self):
        s = self.op
        if self.d is not None:
            s += f' {self.d!r} ='
        if self.a is not None:
            s += f' {self.a!r}'
        if self.b is not None:
            s += f', {self.b!r}'
        if self.x:
            s += ' ' + ' '.join(f'{k}={v!r}' for k, v in self.x.items())
        return s

    # --- uses / defs (virtual registers) ---
    def uses(self):
        r = []
        for o in (self.a, self.b):
            if isinstance(o, V):
                r.append(o)
        if self.op in ('ld', 'st'):
            for k in ('base', 'idx'):
                o = self.x.get(k)
                if isinstance(o, V):
                    r.append(o)
        elif self.op == 'call':
            for o in self.x['args']:
                if isinstance(o, V):
                    r.append(o)
            t = self.x['tgt']
            if isinstance(t, V):
                r.append(t)
        elif self.op in ('copy', 'zero', 'fcopy'):
            pass
        elif self.op == 'cop':
            for k in ('ra', 'rx', 'ry'):
                o = self.x.get(k)
                if isinstance(o, V):
                    r.append(o)
        elif self.op == 'asm':
            r.extend(self.x.get('vars') or ())
        return r

    def defs(self):
        if self.op == 'asm':
            return list(self.x.get('vars') or ())
        return [self.d] if isinstance(self.d, V) else []

    def subst(self, f):
        """replace operands: f(operand) -> operand (uses only)"""
        if self.a is not None:
            self.a = f(self.a)
        if self.b is not None:
            self.b = f(self.b)
        if self.op in ('ld', 'st'):
            for k in ('base', 'idx'):
                if self.x.get(k) is not None:
                    self.x[k] = f(self.x[k])
        elif self.op == 'call':
            self.x['args'] = [f(o) for o in self.x['args']]
            self.x['tgt'] = f(self.x['tgt'])
        elif self.op == 'cop':
            for k in ('ra', 'rx', 'ry'):
                if self.x.get(k) is not None:
                    self.x[k] = f(self.x[k])

    @property
    def is_term(self):
        return self.op in ('br', 'jmp', 'ret', 'sw')

    @property
    def side_effect(self):
        return self.op in ('st', 'call', 'br', 'jmp', 'ret', 'sw', 'copy', 'zero', 'fcopy', 'cop',
                           'asm') or \
            (self.op == 'ld' and self.x.get('vol'))

    def succ(self):
        if self.op == 'br':
            return [self.x['t'], self.x['f']]
        if self.op == 'jmp':
            return [self.x['t']]
        if self.op == 'sw':
            return [l for _, _, l in self.x.get('ranges', ())] + \
                [l for _, l in self.x['cases']] + [self.x['default']]
        return []


class Block:
    def __init__(self, label):
        self.label = label
        self.ins = []
        self.depth = 0       # loop nesting depth (for spill weights)
        self.preds = []

    @property
    def term(self):
        return self.ins[-1] if self.ins and self.ins[-1].is_term else None

    def succ(self):
        t = self.term
        return t.succ() if t else []

    def __repr__(self): return f'<{self.label}>'


class Func:
    def __init__(self, name, static):
        self.name = name
        self.static = static
        self.blocks = []
        self.nv = 0
        self.params = []      # V or ('mem', FrameSlot, V) per parameter
        self.slots = []       # FrameSlot
        self.variadic = False
        self.argsize = 0
        self.has_calls = False

    def newv(self, size, name=None):
        self.nv += 1
        return V(self.nv, size, name)

    def dump(self):
        out = [f'func {self.name}:']
        for b in self.blocks:
            out.append(f' {b.label}: (depth {b.depth})')
            for i in b.ins:
                out.append(f'    {i!r}')
        return '\n'.join(out)
