"""C types for the 65816 Horizon model.

char 8 (unsigned by default, as the SDK), short/int 16, long 32, near data pointers 16
(an offset in the code bank = DBR), far pointers 32 (offset, bank, 0), function pointers
16 (code bank). Structures are packed (no padding), as the SDK's parameter blocks need.
"""


class CError(Exception):
    def __init__(self, msg, coord=None):
        self.msg = msg
        self.coord = coord
        super().__init__(f'{coord}: {msg}' if coord else msg)


class Unsupported(CError):
    pass


class T:
    kind = '?'
    const = False
    volatile = False
    far = False          # a pointer to this type is a far pointer

    def qual(self, const=False, volatile=False, far=False):
        if not (const or volatile or far):
            return self
        t = self.copy()
        t.const = self.const or const
        t.volatile = self.volatile or volatile
        t.far = self.far or far
        return t

    def unqual(self):
        if not (self.const or self.volatile or self.far):
            return self
        t = self.copy()
        t.const = t.volatile = t.far = False
        return t

    def copy(self):
        t = object.__new__(type(self))
        t.__dict__.update(self.__dict__)
        return t

    # predicates
    @property
    def is_int(self): return self.kind == 'int'
    @property
    def is_ptr(self): return self.kind == 'ptr'
    @property
    def is_arr(self): return self.kind == 'arr'
    @property
    def is_func(self): return self.kind == 'func'
    @property
    def is_struct(self): return self.kind == 'struct'
    @property
    def is_void(self): return self.kind == 'void'
    @property
    def is_scalar(self): return self.kind in ('int', 'ptr')
    @property
    def is_arith(self): return self.kind == 'int'


class VoidT(T):
    kind = 'void'
    size = 0

    def __repr__(self): return 'void'


class IntT(T):
    kind = 'int'

    def __init__(self, size, signed, name=None, is_bool=False):
        self.size = size
        self.signed = signed
        self.name = name or f'{"s" if signed else "u"}{size * 8}'
        self.is_bool = is_bool

    def __repr__(self): return self.name

    @property
    def rank(self): return self.size


class PtrT(T):
    kind = 'ptr'

    def __init__(self, to, far=False):
        self.to = to
        self.isfar = far or to.far
        self.size = 4 if self.isfar else 2

    def __repr__(self): return f'{self.to!r}{" far" if self.isfar else ""}*'


class ArrT(T):
    kind = 'arr'

    def __init__(self, elem, n):
        self.elem = elem
        self.n = n

    @property
    def size(self):
        if self.n is None:
            return 0
        return self.elem.size * self.n

    def __repr__(self): return f'{self.elem!r}[{self.n}]'


class Field:
    def __init__(self, name, type, offset, bits=None, bitpos=0):
        self.name = name
        self.type = type
        self.offset = offset
        self.bits = bits         # bit-field width or None
        self.bitpos = bitpos


class StructT(T):
    kind = 'struct'

    def __init__(self, tag, union):
        self.tag = tag
        self.union = union
        self.fields = None       # None = incomplete
        self.size = 0

    @property
    def complete(self): return self.fields is not None

    def field(self, name):
        for f in self.fields or ():
            if f.name == name:
                return f, f.offset
            if f.name is None and f.type.is_struct:      # anonymous member
                r = f.type.field(name)
                if r:
                    return r[0], f.offset + r[1]
        return None

    def __repr__(self): return f'{"union" if self.union else "struct"} {self.tag}'


class FuncT(T):
    kind = 'func'
    size = 1

    def __init__(self, ret, params, variadic, proto):
        self.ret = ret
        self.params = params     # list of (name, type)
        self.variadic = variadic
        self.proto = proto       # has a prototype

    def __repr__(self): return f'fn({", ".join(repr(t) for _, t in self.params)}) -> {self.ret!r}'


VOID = VoidT()
BOOL = IntT(1, False, '_Bool', True)
CHAR = IntT(1, False, 'char')          # plain char is unsigned (as the SDK)
SCHAR = IntT(1, True, 'signed char')
UCHAR = IntT(1, False, 'unsigned char')
SHORT = IntT(2, True, 'short')
USHORT = IntT(2, False, 'unsigned short')
INT = IntT(2, True, 'int')
UINT = IntT(2, False, 'unsigned')
LONG = IntT(4, True, 'long')
ULONG = IntT(4, False, 'unsigned long')


def same(a, b):
    """compatible enough (for pointer comparisons, conditional operands)"""
    if a.kind != b.kind:
        return False
    if a.is_int:
        return a.size == b.size and a.signed == b.signed
    if a.is_ptr:
        return a.to.is_void or b.to.is_void or same(a.to, b.to)
    if a.is_struct:
        return a is b or (a.tag == b.tag and a.tag is not None)
    return True


def promote(t):
    """integer promotions"""
    if t.is_int and t.size < 2:
        return INT
    return t.unqual() if t.is_int else t


def arith_conv(a, b):
    """usual arithmetic conversions (int 16, long 32)"""
    a, b = promote(a), promote(b)
    if a.size == 4 or b.size == 4:
        if (a.size == 4 and not a.signed) or (b.size == 4 and not b.signed):
            return ULONG
        if a.size == 4 and b.size == 4:
            return LONG
        # long vs unsigned int: long can hold every unsigned int
        return LONG
    if not a.signed or not b.signed:
        return UINT
    return INT
