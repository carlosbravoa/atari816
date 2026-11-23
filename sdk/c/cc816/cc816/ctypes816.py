"""C types for the 65816 Horizon model.

char 8 (unsigned by default, as the SDK), short/int 16, long 32, long long 64, near data pointers 16
(an offset in the code bank = DBR), far pointers 32 (offset, bank, 0), function pointers
16 (code bank), float, double and long double 32 (IEEE 754 single precision, all three).
Structures are packed (no padding), as the SDK's parameter blocks need.
"""
import re

# the data model of the compile (driver.compile_c sets it): far_data, the far data model
# (hcc --data far: plain data pointers are far)
MODEL = {'far_data': False}


def where(coord):
    """'file:line:col' of a pycparser Coord (or '')"""
    if coord is None:
        return ''
    if isinstance(coord, str):
        return coord
    f = getattr(coord, 'file', None)
    ln = getattr(coord, 'line', None)
    col = getattr(coord, 'column', None)
    if f is None:
        return str(coord)
    if not ln:
        return f
    return f'{f}:{ln}:{col}' if col else f'{f}:{ln}'


class CError(Exception):
    """a compile error: 'file:line:col: error: message' (or 'error: message' without a
    place). Several errors of one file: the lines joined by newlines."""
    def __init__(self, msg, coord=None):
        self.msg = msg
        self.coord = coord
        w = where(coord)
        if not w and re.match(r'^\S+:\d+(:\d+)?: error: ', msg):
            super().__init__(msg)       # already placed ('file:line: error: ...')
            self.msg = msg.split(': error: ', 1)[1]
        else:
            super().__init__(f'{w}: error: {msg}' if w else f'error: {msg}')


class Unsupported(CError):
    """what cc816 does not have (long long, variable-length arrays, ...)"""
    pass


class ICE(CError):
    """an internal compiler error (a fault of cc816, not of the program); msg is the
    whole line"""
    def __init__(self, msg):
        Exception.__init__(self, msg)
        self.msg = msg
        self.coord = None


class T:
    kind = '?'
    const = False
    volatile = False
    far = False          # a pointer to this type is a far pointer
    near = False         # (__near) a pointer to this type is a near one (the far data model)

    def qual(self, const=False, volatile=False, far=False, near=False):
        if not (const or volatile or far or near):
            return self
        t = self.copy()
        t.const = self.const or const
        t.volatile = self.volatile or volatile
        t.far = self.far or far
        t.near = (self.near or near) and not t.far
        return t

    def unqual(self):
        if not (self.const or self.volatile or self.far or self.near):
            return self
        t = self.copy()
        t.const = t.volatile = t.far = t.near = False
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
    def is_float(self): return self.kind == 'float'
    @property
    def is_scalar(self): return self.kind in ('int', 'ptr', 'float')
    @property
    def is_arith(self): return self.kind in ('int', 'float')


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


class FloatT(T):
    """float, double, long double: one format (IEEE 754 single, 32 bits); the name only
    tells them apart (_Generic)"""
    kind = 'float'
    size = 4

    def __init__(self, name):
        self.name = name

    def __repr__(self): return self.name

    @property
    def rank(self): return {'float': 1, 'double': 2}.get(self.name, 3)


class PtrT(T):
    kind = 'ptr'

    def __init__(self, to, far=False, near=False):
        self.to = to
        # the far data model (hcc --data far): a data pointer is far unless __near; a
        # function pointer is the main-bank entry (16 bits) in every model
        self.isfar = far or to.far or (MODEL['far_data'] and not near and not to.near and
                                       not to.is_func)
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

    _n = 0

    def __init__(self, tag, union):
        StructT._n += 1
        self.uid = StructT._n    # the same structure (copies made by qualifiers keep it)
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
LLONG = IntT(8, True, 'long long')
ULLONG = IntT(8, False, 'unsigned long long')
FLOAT = FloatT('float')
DOUBLE = FloatT('double')
LDOUBLE = FloatT('long double')


def same(a, b):
    """compatible enough (for pointer comparisons, conditional operands)"""
    if a.kind != b.kind:
        return False
    if a.is_int:
        return a.size == b.size and a.signed == b.signed
    if a.is_float:
        return True
    if a.is_ptr:
        return a.to.is_void or b.to.is_void or same(a.to, b.to)
    if a.is_struct:
        return a.uid == b.uid or (a.tag == b.tag and a.tag is not None)
    return True


def vsz(t):
    """the size of the virtual register that holds a scalar of type t: 2, 4 or 8"""
    return 8 if t.size == 8 else 4 if t.size == 4 else 2


def promote(t):
    """integer promotions"""
    if t.is_int and t.size < 2:
        return INT
    return t.unqual() if t.is_int else t


def arith_conv(a, b):
    """usual arithmetic conversions (int 16, long 32; a floating operand wins: double over
    float, all one format)"""
    if not (a.is_arith and b.is_arith):
        raise CError(f'invalid operands ({cname(a)} and {cname(b)}): numbers are needed here')
    if a.is_float or b.is_float:
        r = max((t for t in (a, b) if t.is_float), key=lambda t: t.rank)
        return r.unqual()
    a, b = promote(a), promote(b)
    if a.size == 8 or b.size == 8:
        if (a.size == 8 and not a.signed) or (b.size == 8 and not b.signed):
            return ULLONG
        return LLONG            # (long long holds every unsigned long)
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


def cname(t):
    """a type as C writes it, for messages: 'unsigned char', 'char *', 'struct s',
    'int (*)(int)', 'long [4]'"""
    q = ('const ' if t.const else '') + ('volatile ' if t.volatile else '')
    if t.is_ptr:
        far = ' __far' if t.isfar else ''
        to = t.to
        if MODEL['far_data']:           # (far is the default: the near ones are named)
            far = ' __near' if not t.isfar and not to.is_func else ''
        tail = ' const' if t.const else ''
        if to.is_func:
            return f'{cname(to.ret)} (*{far.strip()}{tail})({_params(to)})'
        if to.is_arr:
            return f'{cname(to.elem)} (*{far.strip()})[{to.n if to.n is not None else ""}]'
        return f'{cname(to)}{far} *{tail.strip()}'.rstrip()
    if t.is_arr:
        return f'{cname(t.elem)} [{t.n if t.n is not None else ""}]'
    if t.is_func:
        return f'{cname(t.ret)} ({_params(t)})'
    if t.is_struct:
        kind = 'union' if t.union else 'struct'
        return q + (f'{kind} {t.tag}' if t.tag else f'{kind} (anonymous)')
    if t.is_void:
        return q + 'void'
    name = getattr(t, 'name', repr(t))
    return q + {'unsigned': 'unsigned int'}.get(name, name)


def _params(f):
    if not f.proto:
        return ''
    ps = [cname(p) for _, p in f.params] + (['...'] if f.variadic else [])
    return ', '.join(ps) or 'void'


def compatible(a, b, strict_sign=False):
    """a and b are compatible enough for a prototype and its definition, or for pointer
    targets: the same kind and size (signedness only when strict_sign), the same
    structure, compatible targets / elements / parameters"""
    if a.kind != b.kind:
        return False
    if a.is_int:
        return a.size == b.size and (not strict_sign or a.signed == b.signed)
    if a.is_float or a.is_void:
        return True
    if a.is_ptr:
        if a.isfar != b.isfar:
            return False
        if a.to.is_void or b.to.is_void:
            return True
        return compatible(a.to, b.to, strict_sign)
    if a.is_struct:
        return a.uid == b.uid or (a.tag is not None and a.tag == b.tag and a.union == b.union)
    if a.is_arr:
        return (a.n is None or b.n is None or a.n == b.n) and compatible(a.elem, b.elem,
                                                                         strict_sign)
    if a.is_func:
        if not compatible(a.ret, b.ret, strict_sign):
            return False
        if a.proto and b.proto:
            if len(a.params) != len(b.params) or a.variadic != b.variadic:
                return False
            return all(compatible(x.unqual(), y.unqual(), strict_sign)
                       for (_, x), (_, y) in zip(a.params, b.params))
        return True
    return True
