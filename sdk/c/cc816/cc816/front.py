"""Front end: pycparser AST -> IR (ir.py), with types, constant folding and the
Horizon memory model:

  * every data pointer is a 16-bit offset in the code bank (DBR); __far pointers are
    32 bits (offset, bank, 0) and are read with [dp],y;
  * a local scalar whose address is never taken is a virtual register (the register
    allocator puts it in the direct page or in a hardware-stack slot);
  * arrays, structures and address-taken locals live in the function's frame on the
    software stack (code bank, pointer __sp in the direct page): &local is a near pointer.
"""
import re

from pycparser import c_ast

from .ctypes816 import (CError, Unsupported, ICE, where, T, VoidT, IntT, PtrT, ArrT, StructT, FuncT,
                        Field, VOID, BOOL, CHAR, SCHAR, UCHAR, SHORT, USHORT, INT, UINT,
                        LONG, ULONG, LLONG, ULLONG, FLOAT, DOUBLE, LDOUBLE, promote,
                        arith_conv, same, cname, compatible, vsz, MODEL)
from .ir import V, Imm, Sym, Frame, FrameSlot, Ins, Block, Func
from . import fp
from .fp import FV
from .diag import Diag

FAR_QUAL = '_Atomic'      # the preprocessor maps __far to _Atomic (pycparser knows it)
NEAR_QUAL = '__cc816_near'  # ... and __near to __cc816_near (cc816's own keyword)


class RV:
    """an rvalue: operand + type. For a structure: the operand is its address."""
    __slots__ = ('op', 't')

    def __init__(self, op, t):
        self.op = op
        self.t = t

    def __repr__(self): return f'RV({self.op!r}:{self.t!r})'


class LV:
    """an lvalue: kind 'reg' (op = V) or 'mem' (base, idx, off); bit-fields: fld"""
    __slots__ = ('kind', 'op', 'base', 'idx', 'off', 't', 'fld', 'vol', 'post', 'farobj',
                 'nnidx')

    def __init__(self, kind, t, op=None, base=None, idx=None, off=0, fld=None):
        self.farobj = False  # inside a __far object (in one bank: [base],y with a 16-bit Y)
        # idx is made of subscripts of array objects alone, each without a positive
        # constant part (a[i], a[i][j], s.m[i], p->m[i]: C wants each such index in its
        # array, so 0 or more): the load or store says so (ilo 0, gen.addr)
        self.nnidx = False
        self.kind = kind
        self.t = t
        self.op = op
        self.base = base
        self.idx = idx
        self.off = off
        self.fld = fld
        self.vol = t.volatile
        self.post = None     # (V, step): a deferred pointer post-increment (*p++)


class Sy:
    """a name in scope"""
    __slots__ = ('kind', 't', 'v', 'asm', 'slot', 'base', 'cval', 'used', 'coord', 'name',
                 'defined', 'param', 'local')

    def __init__(self, kind, t, v=None, asm=None, slot=None, base=None):
        self.used = False    # read or written somewhere (-Wunused-variable)
        self.coord = None    # where it was declared
        self.name = None
        self.defined = False # a global: defined here (an initialiser, or a function body)
        self.param = False
        self.local = False   # a block-scope object (not extern)
        self.kind = kind     # 'global' 'reg' 'mem' 'enum' 'typedef'
        self.t = t
        self.v = v           # V (reg) / value (enum)
        self.asm = asm       # assembler name (global)
        self.slot = slot     # FrameSlot (mem)
        self.base = base     # address operand of a memory object (Frame / V for a struct param)
        self.cval = None     # a const scalar's value (its initialiser), read as a constant


class DataObj:
    def __init__(self, name, section, items, size, export):
        self.name = name
        self.section = section   # 'DATA' 'RODATA' 'BSS'
        self.items = items       # list of ('b', bytes) / ('w', sym, off) / ('f', sym, off)
        self.size = size
        self.export = export
        self.far = False         # a __far object in a bank of its own (segment FD_name)


def mangle(name):
    return '_' + name


class Unit:
    def __init__(self):
        self.funcs = []
        self.data = []
        self.externs = set()
        self.exports = set()
        self.defined = set()
        self.warnings = []
        self.asm = []            # file-scope asm: (the number of functions before it, text)
        self.farsyms = set()     # the __far objects' names (their address is a far one)
        self.fardata = False     # __far objects in banks of their own (the large model)


class Front:
    def __init__(self, filename='?', diag=None, implicit_int=(), attrs=None):
        self.diag = diag or Diag()
        self.attrs = attrs or {}     # GNU attributes the driver found: name -> set of
                                     # function names (noreturn, naked)
        self.nasm = 0
        self.loc = None              # the place of the statement / expression being done
        self.implicit_int = {(c.file, c.line, c.column) for c in implicit_int}
        self.noreturn_blocks = set()
        self.sw_seen = {}
        self.noreturn_names = set(NORETURN) | set(self.attrs.get('noreturn', ()))
        self.unit = Unit()
        self.unit.warnings = self.diag.warnings
        self.scopes = [{}]
        self.tags = [{}]
        self.strings = {}
        self.nstatic = 0
        self.fn = None
        self.filename = filename
        self.global_types = {}
        self.in_params = False
        self.nlit = 0
        self.uses_float = False      # the unit uses floating point
        self.calls_printf = False    # ... and calls a printf (links printf's %f) ...
        self.calls_scanf = False     # ... or a scanf (scanf's %f)
        self.uses_ll = False         # the unit uses long long (printf's and scanf's %lld)
        # a printf's or a scanf's constant format had a float conversion (%f %e %g %a) or
        # a long long one (%lld, %jd)
        self.fmt_float_printf = self.fmt_float_scanf = False
        self.fmt_ll_printf = self.fmt_ll_scanf = False

    # ------------------------------------------------------------------ errors
    def place_of(self, node):
        c = getattr(node, 'coord', None) if node is not None else None
        return c if c is not None else self.loc

    def err(self, msg, node=None):
        raise CError(msg, self.place_of(node))

    def unsup(self, msg, node=None):
        """a feature cc816 does not have: 'cc816 does not support X' (msg: X and what to
        do instead)"""
        raise Unsupported(f'cc816 does not support {msg}', self.place_of(node))

    def warn(self, msg, node=None, name='other'):
        self.diag.warning(self.place_of(node) or self.filename, msg, name)

    def record(self, e):
        """an error found: noted, and the compile goes on (more errors are reported)"""
        if isinstance(e, ICE):
            raise e
        if isinstance(e, _Silent):
            return
        coord = e.coord
        if coord is None:
            m = _PLACED.match(str(e))
            if m:
                self.diag.error(m.group(1), m.group(2), isinstance(e, Unsupported))
                return
            coord = self.loc
        self.diag.error(coord or self.filename, e.msg, isinstance(e, Unsupported))
        if len(self.diag.errors) >= 100:
            raise _TooMany()

    # ------------------------------------------------------------------ scopes
    def push(self):
        self.scopes.append({})
        self.tags.append({})

    def pop(self):
        sc = self.scopes.pop()
        self.tags.pop()
        for name, sy in sc.items():
            if sy.local and not sy.used and not sy.param and sy.coord is not None and \
                    sy.kind in ('reg', 'mem', 'global') and not name.startswith('__'):
                self.diag.warning(sy.coord, f"unused variable '{name}'", 'unused-variable')

    def lookup(self, name):
        for s in reversed(self.scopes):
            if name in s:
                sy = s[name]
                if sy.kind == 'error':
                    raise _Silent()
                sy.used = True
                return sy
        return None

    def lookup_tag(self, name):
        for s in reversed(self.tags):
            if name in s:
                return s[name]
        return None

    def bind(self, name, sy):
        self.scopes[-1][name] = sy

    # ------------------------------------------------------------------ types
    def base_type(self, node, quals=()):
        if isinstance(node, c_ast.IdentifierType):
            names = sorted(node.names)
            n = [x for x in node.names]
            if len(n) == 1 and self.lookup(n[0]) and self.lookup(n[0]).kind == 'typedef':
                return self.lookup(n[0]).t
            s = set(n)
            longs = n.count('long')
            if 'float' in s or 'double' in s:
                if '_Complex' in s or '_Imaginary' in s:
                    self.unsup('complex numbers (_Complex)', node)
                if 'float' in s:
                    return FLOAT
                return LDOUBLE if longs else DOUBLE
            if longs >= 2 or '__int64' in s:
                return ULLONG if 'unsigned' in s else LLONG
            for w in s:
                if w in ('__int128', '__int128_t', '__uint128_t'):
                    self.unsup(f'128-bit integers ({w}): long long is 64 bits', node)
                if w in ('_Complex', '_Imaginary'):
                    self.unsup('complex numbers (_Complex)', node)
            if 'void' in s:
                return VOID
            if '_Bool' in s:
                return BOOL
            uns = 'unsigned' in s
            if 'char' in s:
                return UCHAR if uns else (SCHAR if 'signed' in s else CHAR)
            if 'short' in s:
                return USHORT if uns else SHORT
            if longs == 1:
                return ULONG if uns else LONG
            if s & {'int', 'signed', 'unsigned'} or not s:
                return UINT if uns else INT
            if len(n) == 1:
                self.err(f"unknown type name '{n[0]}'", node)
            self.err(f'unknown type {" ".join(names)}', node)
        if isinstance(node, (c_ast.Struct, c_ast.Union)):
            return self.struct_type(node)
        if isinstance(node, c_ast.Enum):
            return self.enum_type(node)
        if isinstance(node, c_ast.TypeOf):
            if isinstance(node.expr, c_ast.Typename):
                return self.decl_type(node.expr)
            return self.typeof(node.expr)
        if type(node).__name__ == 'BitIntType':
            self.unsup('_BitInt', node)
        self.unsup(f'the type {type(node).__name__}', node)

    def _tag_seen(self, node):
        """the type a definition node already gave: `struct s {...} a, b;` shares one
        node among its declarators, which must not define it twice"""
        memo = self.__dict__.setdefault('_tag_nodes', {})
        hit = memo.get(id(node))
        return hit[1] if hit is not None and hit[0] is node else None

    def _tag_keep(self, node, t):
        self.__dict__.setdefault('_tag_nodes', {})[id(node)] = (node, t)
        return t

    def struct_type(self, node):
        if node.decls is not None:
            seen = self._tag_seen(node)
            if seen is not None:
                return seen
            return self._tag_keep(node, self._struct_type(node))
        return self._struct_type(node)

    def _struct_type(self, node):
        union = isinstance(node, c_ast.Union)
        st = None
        if node.name:
            if node.decls is None:
                st = self.lookup_tag(node.name)
                if st is None:
                    st = StructT(node.name, union)
                    self.tags[-1][node.name] = st
                return st
            st = self.tags[-1].get(node.name)
            if st is not None and st.complete and not getattr(st, 'defining', False):
                self.err(f"redefinition of '{'union' if union else 'struct'} {node.name}'",
                         node)
            if st is not None and st.is_struct and st.union != union:
                self.err(f"'{node.name}' defined as the wrong kind of tag (struct and "
                         f"union)", node)
            if st is None or st.complete:
                st = StructT(node.name, union)
                self.tags[-1][node.name] = st
        else:
            st = StructT(None, union)
        fields = []
        off = 0
        size = 0
        bitunit = None     # (offset, size, used bits)
        names = set()
        decls = node.decls or []
        for k, d in enumerate(decls):
            if isinstance(d, c_ast.StaticAssert):
                self.static_assert(d)
                continue
            try:
                t, w = self.member_type(d, k, decls, union, names)
            except CError as e:
                self.record(e)
                continue
            if w is not None:
                usz = max(t.size, 1)
                if w == 0:
                    if bitunit:
                        off = bitunit[0] + bitunit[1]
                    bitunit = None
                    continue
                if union:
                    fields.append(Field(d.name, t, 0, w, 0))
                    size = max(size, usz)
                    continue
                if bitunit is None or bitunit[1] != usz or bitunit[2] + w > usz * 8:
                    if bitunit:
                        off = bitunit[0] + bitunit[1]
                    bitunit = [off, usz, 0]
                fields.append(Field(d.name, t, bitunit[0], w, bitunit[2]))
                bitunit[2] += w
                size = max(size, bitunit[0] + bitunit[1])
                continue
            if bitunit:
                off = bitunit[0] + bitunit[1]
                bitunit = None
            if union:
                fields.append(Field(d.name, t, 0))
                size = max(size, t.size)
            else:
                fields.append(Field(d.name, t, off))
                off += t.size
                size = off
        if bitunit:
            size = max(size, bitunit[0] + bitunit[1])
        st.fields = fields
        st.size = size
        if size >= 0x10000:
            self.err(f"the structure is {size:,} bytes: an object is at most 65,535 bytes "
                     f"in cc816", node)
        return st

    def member_type(self, d, k, decls, union, names):
        """a member's type and bit-field width (None: not a bit-field), checked"""
        t = self.decl_type(d.type)
        if d.name is not None:
            if d.name in names:
                self.err(f"duplicate member '{d.name}'", d)
            names.add(d.name)
        if t.is_func:
            self.err(f"member '{d.name}' declared as a function (a pointer to one, "
                     f"'(*{d.name})(...)', is allowed)", d)
        if d.bitsize is not None:
            w = self.const_int(d.bitsize)
            if not t.is_int:
                self.err(f"bit-field '{d.name}' has a type that is not an integer "
                         f"({cname(t)})", d)
            usz = max(t.size, 1)
            if t.is_int and t.size == 8:
                self.unsup(f"a long long bit-field ('{d.name}'): declare it long or unsigned "
                           f"long (up to 32 bits)", d)
            if w < 0:
                self.err(f"negative width in bit-field '{d.name}'", d)
            if w > 8 * usz:
                more = ' (int is 16 bits in cc816: declare it long or unsigned long ' \
                       'for up to 32)' if usz == 2 else ''
                self.err(f"width of bit-field '{d.name}' ({w} bits) exceeds its type "
                         f"({cname(t)}, {8 * usz} bits){more}", d)
            if w == 0 and d.name is not None:
                self.err(f"zero width for bit-field '{d.name}'", d)
            return t, w
        if t.is_arr and t.n is None:
            if k != len(decls) - 1 or union:
                self.err(f"flexible array member '{d.name}' not at the end of the "
                         f"structure", d)
            t = ArrT(t.elem, 0)      # flexible array member
        if t.is_void:
            self.err(f"member '{d.name}' declared void", d)
        if not t.is_arr and t.size == 0 and not t.is_struct:
            self.err(f"member '{d.name}' has an incomplete type ({cname(t)})", d)
        if t.is_struct and not t.complete:
            self.err(f"member '{d.name}' has an incomplete type ({cname(t)}: the "
                     f"structure is declared but not defined)", d)
        return t, None

    def enum_type(self, node):
        if node.values:
            seen = self._tag_seen(node)
            if seen is not None:
                return seen
            return self._tag_keep(node, self._enum_type(node))
        return self._enum_type(node)

    def _enum_type(self, node):
        if node.values:
            if node.name and ('enum ' + node.name) in self.tags[-1]:
                self.err(f"redefinition of 'enum {node.name}'", node)
            val = 0
            lo = hi = 0
            for e in node.values.enumerators:
                if e.value is not None:
                    val = self.const_int(e.value)
                if not -0x80000000 <= val <= 0xFFFFFFFF:
                    self.err(f"the value of '{e.name}' ({val}) does not fit 32 bits", e)
                prev = self.scopes[-1].get(e.name)
                if prev is not None:
                    self.err(f"redeclaration of '{e.name}'", e)
                # an enumerator's type: int when its value fits, else the smallest
                # that holds it (a GNU extension: C wants int)
                et = INT if -0x8000 <= val <= 0x7FFF else UINT if 0 <= val <= 0xFFFF else \
                    LONG if val <= 0x7FFFFFFF else ULONG
                sy = Sy('enum', et, v=val)
                sy.coord = e.coord
                self.bind(e.name, sy)
                lo, hi = min(lo, val), max(hi, val)
                val += 1
            if lo < 0:
                t = INT if lo >= -0x8000 and hi <= 0x7FFF else LONG
            else:
                t = UINT if hi <= 0xFFFF else ULONG
            if node.name:
                self.tags[-1]['enum ' + node.name] = t
            return t
        if node.name:
            t = self.lookup_tag('enum ' + node.name)
            if t is not None:
                return t
        return INT

    def decl_type(self, node):
        """type of a declarator tree (TypeDecl / PtrDecl / ArrayDecl / FuncDecl / Typename)"""
        if isinstance(node, (c_ast.Typename, c_ast.Decl)):
            return self.decl_type(node.type)
        if isinstance(node, c_ast.TypeDecl):
            t = self.base_type(node.type)
            q = node.quals or []
            if NEAR_QUAL in q:
                return t.qual('const' in q, 'volatile' in q, FAR_QUAL in q, True)
            return t.qual('const' in q, 'volatile' in q, FAR_QUAL in q)
        if isinstance(node, c_ast.PtrDecl):
            to = self.decl_type(node.type)
            q = node.quals or []
            if 'lead:' + FAR_QUAL in q or 'lead:' + NEAR_QUAL in q:
                # __far / __near before the '*' (`void (__far *f)(void)`, Watcom's and
                # Microsoft's): of a data pointer, the same as `T __far *`
                if to.is_func:
                    self.warn("'__far' on a function pointer is ignored (a function pointer "
                              "is the function's entry in the main bank in every model)",
                              node, 'far-function')
                elif 'lead:' + FAR_QUAL in q:
                    to = to.qual(far=True)
                else:
                    to = to.qual(near=True)
            p = PtrT(to)
            if NEAR_QUAL in q:
                return p.qual('const' in q, 'volatile' in q, FAR_QUAL in q, True)
            return p.qual('const' in q, 'volatile' in q, FAR_QUAL in q)
        if isinstance(node, c_ast.ArrayDecl):
            el = self.decl_type(node.type)
            n = None
            if node.dim is not None:
                if isinstance(node.dim, c_ast.ID) and node.dim.name == '*':
                    return ArrT(el, None)
                n = self.const_eval(node.dim)
                if isinstance(n, FV):
                    self.err('the size of an array is not an integer', node)
                if n is None:
                    if self.in_params:
                        return ArrT(el, None)
                    # (an undeclared name in the size is that, not a variable length: the
                    # Xargon port's numobjkinds without x_obj.h)
                    stack = [node.dim]
                    while stack:
                        d = stack.pop()
                        if isinstance(d, c_ast.ID) and self.lookup(d.name) is None:
                            self.undeclared(d.name, d)
                        if not isinstance(d, (c_ast.Typename, c_ast.FuncCall)):
                            stack.extend(c for _, c in d.children())
                    self.unsup('variable-length arrays: give the array a constant size, '
                               'or take the memory from malloc', node)
                if n < 0:
                    self.err(f'the size of an array is negative ({n})', node)
            if el.is_void:
                self.err('an array of void', node)
            if el.is_func:
                self.err('an array of functions (an array of function pointers, '
                         '(*a[N])(...), is allowed)', node)
            if el.is_struct and not el.complete:
                self.err(f'an array of an incomplete type ({cname(el)})', node)
            if n is not None and el.size * n >= 0x10000:
                self.err(f'the array is {el.size * n:,} bytes: an object is at most 65,535 '
                         f'bytes in cc816 (a bigger table can live in its own bank: '
                         f'hz_far_alloc and a __far pointer)', node)
            a = ArrT(el, n)
            # (an array of __far elements is a __far object: &a is a far pointer too)
            if el.near and not el.far:
                return a.qual(near=True)
            return a.qual(far=True) if el.far else a
        if isinstance(node, c_ast.FuncDecl):
            ret = self.decl_type(node.type)
            if ret.is_arr:
                self.err('a function cannot return an array', node)
            if ret.is_func:
                self.err('a function cannot return a function', node)
            params = []
            variadic = False
            proto = node.args is not None
            if node.args:
              saved = self.in_params
              self.in_params = True
              try:
                for p in node.args.params:
                    if isinstance(p, c_ast.EllipsisParam):
                        variadic = True
                        continue
                    if isinstance(p, c_ast.ID):      # K&R identifier list
                        params.append((p.name, INT))
                        proto = False
                        continue
                    pt = self.decl_type(p.type)
                    if pt.is_void:
                        continue
                    params.append((getattr(p, 'name', None), self.param_adjust(pt)))
              finally:
                self.in_params = saved
            return FuncT(ret, params, variadic, proto)
        if isinstance(node, (c_ast.IdentifierType, c_ast.Struct, c_ast.Union, c_ast.Enum)):
            return self.base_type(node)
        self.unsup(f'declarator {type(node).__name__}', node)

    def param_adjust(self, t):
        if t.is_arr:
            return PtrT(t.elem)
        if t.is_func:
            return PtrT(t)
        return t

    def typeof(self, e):
        return self.expr_type(e)

    # ------------------------------------------------------------------ constants
    def const_int(self, node):
        v = self.const_eval(node)
        if v is None or not isinstance(v, int):
            self.err('constant expression expected', node)
        return v

    def const_eval(self, e):
        """integer constant expression -> int, or None (not constant)"""
        if isinstance(e, c_ast.Constant):
            return self.constant(e)[0] if e.type != 'string' else None
        if isinstance(e, c_ast.ID):
            s = self.lookup(e.name)
            if s and s.kind == 'enum':
                return s.v
            return None
        if isinstance(e, c_ast.UnaryOp):
            if e.op == 'sizeof':
                return self.sizeof(e.expr)
            if e.op == '_Alignof':
                return 1
            if e.op == '&':
                # offsetof: &((T *)0)->member (and members of members, elements)
                k = self.offset_const(e.expr)
                return k & 0xFFFF if k is not None else None
            v = self.const_eval(e.expr)
            if v is None:
                return None
            t = self.expr_type(e)
            if isinstance(v, FV) or t.is_float:
                if e.op == '!':
                    return int(not v)
                if not t.is_float or e.op not in ('-', '+'):
                    return None
                v = self.wrap(v, t)
                return FV(v.bits ^ fp.SIGN) if e.op == '-' else v
            r = {'-': lambda: -v, '+': lambda: v, '~': lambda: ~v, '!': lambda: int(not v)}.get(e.op)
            return self.wrap(r(), t) if r else None
        if isinstance(e, c_ast.BinaryOp):
            a = self.const_eval(e.left)
            if e.op == '&&' and a == 0:
                return 0
            if e.op == '||' and a not in (None, 0):
                return 1
            b = self.const_eval(e.right)
            if a is None or b is None:
                return None
            t = self.expr_type(e)
            lt = promote(self.expr_type(e.left))
            ct = arith_conv(self.expr_type(e.left), self.expr_type(e.right)) \
                if not (decay(self.expr_type(e.left)).is_ptr or decay(self.expr_type(e.right)).is_ptr) \
                else UINT
            if (ct.is_float or isinstance(a, FV) or isinstance(b, FV)) and e.op not in ('&&', '||'):
                if not ct.is_float:
                    return None
                fa, fb = self.wrap(a, ct).bits, self.wrap(b, ct).bits
                if e.op in ('<', '>', '<=', '>=', '==', '!='):
                    c = fp.cmp(fa, fb)
                    return int({'<': c == -1, '>': c == 1, '<=': c in (-1, 0), '>=': c in (0, 1),
                                '==': c == 0, '!=': c != 0}[e.op])
                f = {'+': fp.add, '-': fp.sub, '*': fp.mul, '/': fp.div}.get(e.op)
                return self.wrap(FV(f(fa, fb)), t) if f else None
            if e.op in ('<', '>', '<=', '>=', '==', '!='):
                a, b = self.wrap(a, ct), self.wrap(b, ct)
            elif e.op in ('/', '%', '>>'):
                a = self.wrap(a, ct if e.op != '>>' else lt)
                b = self.wrap(b, ct) if e.op != '>>' else b
            if e.op in ('<<', '>>') and isinstance(b, int) and (b < 0 or b >= 8 * lt.size):
                self.warn(f'shift count ({b}) is negative or not less than the width of '
                          f'{cname(lt)} ({8 * lt.size} bits in cc816)', e,
                          'shift-count-overflow')
            if e.op in ('<<', '>>') and isinstance(b, int) and b < 0:
                return None         # (a negative count: left to the code, as C leaves it)
            try:
                r = {'+': lambda: a + b, '-': lambda: a - b, '*': lambda: a * b,
                     '/': lambda: _cdiv(a, b), '%': lambda: _cmod(a, b),
                     '<<': lambda: a << b, '>>': lambda: a >> b,
                     '&': lambda: a & b, '|': lambda: a | b, '^': lambda: a ^ b,
                     '<': lambda: int(a < b), '>': lambda: int(a > b), '<=': lambda: int(a <= b),
                     '>=': lambda: int(a >= b), '==': lambda: int(a == b), '!=': lambda: int(a != b),
                     '&&': lambda: int(bool(a and b)), '||': lambda: int(bool(a or b))}[e.op]()
            except ZeroDivisionError:
                return None
            w = self.wrap(r, t)
            if t.is_int and not t.is_bool and t.signed and w != r and (
                    e.op in ('+', '-', '*') or (e.op == '<<' and r >> (8 * t.size) and
                                                b < 8 * lt.size)):
                self.warn(f'integer overflow in a constant expression: the result {r} does '
                          f'not fit {cname(t)} ({8 * t.size} bits in cc816; it becomes {w})',
                          e, 'overflow')
            return w
        if isinstance(e, c_ast.TernaryOp):
            c = self.const_eval(e.cond)
            if c is None:
                return None
            v = self.const_eval(e.iftrue if c else e.iffalse)
            if v is None:
                return None
            t = decay(self.expr_type(e))
            if t.is_float or isinstance(v, FV):
                return self.wrap(v, t) if t.is_arith else None
            return v
        if isinstance(e, c_ast.Cast):
            v = self.const_eval(e.expr)
            t = self.decl_type(e.to_type)
            if v is None or not (t.is_int or t.is_ptr or t.is_float):
                return None
            if isinstance(v, FV) and t.is_ptr:
                return None
            return self.wrap(v, t)
        return None

    def offset_const(self, e):
        """the address of a member of a structure at a constant address (offsetof's
        &((T *)0)->m) -> int, or None"""
        if isinstance(e, c_ast.StructRef):
            if e.type == '->':
                if not isinstance(e.name, c_ast.Cast):
                    return None
                base = self.const_eval(e.name.expr)
                st = self.decl_type(e.name.to_type)
                if not isinstance(base, int) or not st.is_ptr:
                    return None
                st = st.to
            else:
                base = self.offset_const(e.name)
                if base is None:
                    return None
                st = self.expr_type(e.name)
            if not st.is_struct or not st.complete:
                return None
            r = st.field(e.field.name)
            if not r:
                self.err(f"no member named '{e.field.name}' in '{cname(st)}'", e)
            return base + r[1]
        if isinstance(e, c_ast.ArrayRef):
            base = self.offset_const(e.name)
            k = self.const_eval(e.subscript)
            if base is None or not isinstance(k, int):
                return None
            return base + k * self.expr_type(e).size
        return None

    def wrap(self, v, t):
        if t.is_float:
            return v if isinstance(v, FV) else FV(fp.from_int(v))
        if isinstance(v, FV):
            if t.is_int and t.is_bool:
                return int(bool(v))
            if not t.is_int:
                return v
            # as the runtime converts: __ftoul for unsigned long, __ftol for the rest
            v = fp.to_int(v.bits, bits=64 if t.size == 8 else 32,
                          signed=not (t.size >= 4 and not t.signed))
        if t.is_ptr:
            return v & ((1 << (8 * t.size)) - 1)
        if not t.is_int:
            return v
        if t.is_bool:
            return int(bool(v))
        bits = 8 * t.size
        v &= (1 << bits) - 1
        if t.signed and v >> (bits - 1):
            v -= 1 << bits
        return v

    def constant(self, e):
        """Constant node -> (value, type)"""
        s = e.value
        if e.type == 'char' or s.startswith("'") or s[:2] in ("L'", "u'", "U'") or \
                s[:3] == "u8'":
            pre = s[:s.index("'")]
            body = s[len(pre) + 1:-1]
            if pre in ('L', 'u', 'U'):
                et = {'L': WCHAR, 'u': CHAR16, 'U': CHAR32}[pre]
                b = unescape_wide(body, et.size)
                if len(b) != 1:
                    self.warn('a wide character constant of more than one character: the '
                              'first is taken', e, 'multichar')
                return (b[0] if b else 0), (et if et.size == 4 else INT)
            b = unescape(body)
            if len(b) > 2:
                self.warn('a character constant of more than two characters (an int holds '
                          'two in cc816)', e, 'multichar')
            v = b[0] if len(b) == 1 else int.from_bytes(bytes(b[-2:]), 'big')
            if CHAR.signed and len(b) == 1 and v > 127:
                v -= 256            # (with -fsigned-char '\xff' is -1, as gcc)
            return v, INT
        if e.type == 'string':
            return None, None
        hexa = s.lower().startswith('0x')
        if e.type in ('float', 'double', 'long double') or (not hexa and ('.' in s or 'e' in s.lower())) \
                or (hexa and ('.' in s or 'p' in s.lower())):
            self.uses_float = True
            t = s
            typ = DOUBLE
            if t[-1] in 'fF':
                typ, t = FLOAT, t[:-1]
            elif t[-1] in 'lL':
                typ, t = LDOUBLE, t[:-1]
            try:
                return FV(fp.parse(t)), typ
            except (ValueError, ZeroDivisionError):
                self.err(f'bad floating constant {s}', e)
        t = s.lower()
        suf = ''
        while t and t[-1] in 'ul':
            suf = t[-1] + suf
            t = t[:-1]
        if t in ('0x', '0b', ''):
            # (0x with no digits: the robustness test's changed programs met it)
            self.err(f'bad integer constant {s}', e)
        if t.startswith('0x'):
            v = int(t[2:], 16)
            dec = False
        elif t.startswith('0b'):
            v = int(t[2:], 2)
            dec = False
        elif t.startswith('0') and len(t) > 1:
            v = int(t, 8)
            dec = False
        else:
            v = int(t)
            dec = True
        u = 'u' in suf
        lng = suf.count('l')            # 0, 1 (l) or 2 (ll)
        # the first type that holds the value (C99 6.4.4.1): a decimal constant without
        # u stays signed, an octal or hexadecimal one may become unsigned
        if not lng and not u and v <= 0x7FFF:
            return v, INT
        if not lng and (u or not dec) and v <= 0xFFFF:
            return v, UINT
        if lng < 2 and not u and v <= 0x7FFFFFFF:
            return v, LONG
        if lng < 2 and (u or not dec) and v <= 0xFFFFFFFF:
            return v, ULONG
        if not u and v <= 0x7FFFFFFFFFFFFFFF:
            return v, LLONG
        if (u or not dec) and v <= 0xFFFFFFFFFFFFFFFF:
            return v, ULLONG
        if v <= 0xFFFFFFFFFFFFFFFF:
            self.warn(f'the integer constant {s} is so large that it is unsigned (it does not '
                      f'fit long long)', e, 'overflow')
            return v, ULLONG
        self.err(f'the integer constant {s} is too large for 64 bits', e)

    def sizeof(self, e):
        if isinstance(e, c_ast.Typename):
            t = self.decl_type(e)
        else:
            t = self.expr_type(e)
        if t.is_func:
            return 1
        if t.is_struct and not t.complete:
            self.err('sizeof an incomplete type', e)
        return t.size

    # ------------------------------------------------------------------ expr types
    def far_lvalue(self, e):
        """the lvalue e lies in far memory reached through a far pointer"""
        if isinstance(e, c_ast.StructRef):
            if e.type == '->':
                return decay(self.expr_type(e.name)).isfar
            return self.far_lvalue(e.name)
        if isinstance(e, c_ast.ArrayRef):
            bt = decay(self.expr_type(e.name))
            if not bt.is_ptr:
                bt = decay(self.expr_type(e.subscript))
            return bt.is_ptr and bt.isfar
        if isinstance(e, c_ast.UnaryOp) and e.op == '*':
            return decay(self.expr_type(e.expr)).isfar
        return False

    def expr_type(self, e):
        """the type of an expression without generating code"""
        if isinstance(e, c_ast.Constant):
            if e.type == 'string':
                return self.str_type(e)
            return self.constant(e)[1]
        if isinstance(e, c_ast.ID):
            s = self.lookup(e.name)
            if s is None:
                if e.name == '__func__':
                    return ArrT(CHAR, len(self.fn.name) + 1 if self.fn else 1)
                self.undeclared(e.name, e)
            return s.t
        if isinstance(e, c_ast.Cast):
            return self.decl_type(e.to_type)
        if isinstance(e, c_ast.UnaryOp):
            if e.op in ('sizeof', '_Alignof'):
                return UINT
            t = self.expr_type(e.expr)
            if e.op == '&':
                return PtrT(t, far=self.far_lvalue(e.expr))
            if e.op == '*':
                t = decay(t)
                if t.is_ptr:
                    return t.to
                if t.is_func:
                    return t
                self.err(f"'*' needs a pointer, not {cname(t)}", e)
            if e.op == '!':
                return INT
            if e.op in ('-', '+', '~'):
                return promote(t)
            return t
        if isinstance(e, c_ast.BinaryOp):
            op = e.op
            if op in ('&&', '||', '<', '>', '<=', '>=', '==', '!='):
                return INT
            lt = decay(self.expr_type(e.left))
            rt = decay(self.expr_type(e.right))
            if op in ('<<', '>>'):
                return promote(lt)
            if op == '+' and lt.is_ptr:
                return lt
            if op == '+' and rt.is_ptr:
                return rt
            if op == '-' and lt.is_ptr:
                return INT if rt.is_ptr else lt
            if not (lt.is_arith and rt.is_arith):
                self.err(f'invalid operands to {op} ({cname(lt)} and {cname(rt)})', e)
            return arith_conv(lt, rt)
        if isinstance(e, c_ast.Assignment):
            return self.expr_type(e.lvalue).unqual()
        if isinstance(e, c_ast.TernaryOp):
            a = decay(self.expr_type(e.iftrue))
            b = decay(self.expr_type(e.iffalse))
            if a.is_arith and b.is_arith:
                return arith_conv(a, b)
            if a.is_ptr and (b.is_int):
                return a
            if b.is_ptr and a.is_int:
                return b
            if a.is_ptr and b.is_ptr and a.to.is_void:
                return b
            return a
        if isinstance(e, c_ast.FuncCall):
            if isinstance(e.name, c_ast.ID) and e.name.name in BUILTINS:
                return BUILTINS[e.name.name]
            if isinstance(e.name, c_ast.ID) and self.lookup(e.name.name) is None:
                return INT
            ft = decay(self.expr_type(e.name))
            if ft.is_ptr:
                ft = ft.to
            if not ft.is_func:
                self.err('calling a non-function', e)
            return ft.ret
        if isinstance(e, c_ast.ArrayRef):
            a = decay(self.expr_type(e.name))
            if a.is_ptr:
                return a.to
            b = decay(self.expr_type(e.subscript))
            if b.is_ptr:
                return b.to
            self.err(f'a subscript ([]) of something that is not an array or a pointer '
                     f'({cname(a)})', e)
        if isinstance(e, c_ast.StructRef):
            t = self.expr_type(e.name)
            if e.type == '->':
                t = decay(t)
                if not t.is_ptr:
                    self.err(f"'->' needs a pointer to a structure, not {cname(t)}"
                             + (" (use '.')" if t.is_struct else ''), e)
                t = t.to
            self.check_member_base(t, e)
            f = t.field(e.field.name)
            if not f:
                self.err(f"no member named '{e.field.name}' in {cname(t)}", e)
            ft = f[0].type
            return ft.qual(t.const, t.volatile)
        if isinstance(e, c_ast.ExprList):
            return self.expr_type(e.exprs[-1])
        if isinstance(e, c_ast.CompoundLiteral):
            t = self.decl_type(e.type)
            if t.is_arr and t.n is None:
                t = ArrT(t.elem, self.init_count(t, e.init))
            return t
        if isinstance(e, c_ast.GenericSelection):
            return self.expr_type(self.generic_pick(e))
        if isinstance(e, c_ast.Compound):
            items = e.block_items or []
            if not items:
                return VOID
            last = items[-1]
            if isinstance(last, (c_ast.Decl, c_ast.DeclList, c_ast.Typedef)) or \
                    type(last).__name__ in STATEMENTS:
                return VOID
            # the declarations before it, for the names it uses (types only)
            self.push()
            try:
                for x in items[:-1]:
                    for d in (x.decls if isinstance(x, c_ast.DeclList) else [x]):
                        if isinstance(d, c_ast.Typedef) or (
                                isinstance(d, c_ast.Decl) and 'typedef' in (d.storage or [])):
                            self.typedef(d)
                        elif isinstance(d, c_ast.Decl) and d.name:
                            t = self.decl_type(d.type)
                            if t.is_arr and t.n is None and d.init is not None:
                                t = ArrT(t.elem, self.init_count(t, d.init))
                            self.bind(d.name, Sy('reg', t))
                return decay(self.expr_type(last))
            finally:
                self.scopes.pop()
                self.tags.pop()
        self.unsup(f'the expression {type(e).__name__}', e)

    # ------------------------------------------------------------------ strings
    def str_parts(self, e):
        """a string literal (adjacent ones joined: pycparser gives "a" "b" as one value)
        -> (element type, [the parts' (prefix, text)])"""
        s = e.value
        i = 0
        parts = []
        while i < len(s):
            if s[i] in 'LuU8':
                j = i
                while s[j] != '"':
                    j += 1
                pre = s[i:j]
                i = j
                continue
            if s[i] == '"':
                j = i + 1
                while s[j] != '"':
                    j += 2 if s[j] == '\\' else 1
                k = i - 1
                pre = ''
                while k >= 0 and s[k] in 'LuU8':
                    pre = s[k] + pre
                    k -= 1
                parts.append((pre, s[i + 1:j]))
                i = j + 1
            else:
                i += 1
        pres = {p for p, _ in parts if p and p != 'u8'}
        if len(pres) > 1:
            self.err('a string literal joins two different wide kinds (L, u, U)', e)
        kind = pres.pop() if pres else ''
        elem = {'': CHAR, 'L': WCHAR, 'u': CHAR16, 'U': CHAR32}[kind]
        return elem, parts

    def strvals(self, e):
        """a string literal's elements (bytes for "...", code points for L"...", u"...",
        U"...": the source is UTF-8), without the terminating 0"""
        elem, parts = self.str_parts(e)
        out = []
        for pre, text in parts:
            if elem.size == 1:
                out += unescape(text)
            else:
                out += unescape_wide(text, elem.size)
        return out

    def str_elem(self, e):
        return self.str_parts(e)[0]

    def str_type(self, e):
        return ArrT(self.str_elem(e), len(self.strvals(e)) + 1)

    def strbytes(self, e):
        """a string literal's bytes (wide elements little-endian), without the
        terminating 0"""
        elem = self.str_elem(e)
        vals = self.strvals(e)
        if elem.size == 1:
            return vals
        out = []
        for v in vals:
            out += list(v.to_bytes(elem.size, 'little'))
        return out

    def string_sym(self, e):
        b = bytes(self.strbytes(e)) + b'\0' * self.str_elem(e).size
        if b not in self.strings:
            name = f'L_S{len(self.strings)}'
            self.strings[b] = name
            o = DataObj(name, 'RODATA', [('b', list(b))], len(b), False)
            if MODEL['far_data']:
                # (the far data model: a string literal lives in far data, reached with
                # long addressing; a library's (split) stay in the main bank)
                self.unit.farsyms.add(name)
                o.far = self.unit.fardata
            self.unit.data.append(o)
        return self.strings[b]

    # ================================================================== top level
    def translate(self, ast):
        try:
            for ext in ast.ext:
                self.loc = getattr(ext, 'coord', None)
                try:
                    if isinstance(ext, c_ast.FuncDef):
                        self.funcdef(ext)
                    elif isinstance(ext, c_ast.Decl):
                        self.global_decl(ext)
                    elif isinstance(ext, c_ast.Typedef):
                        self.typedef(ext)
                    elif isinstance(ext, c_ast.StaticAssert):
                        self.static_assert(ext)
                    elif isinstance(ext, c_ast.Pragma):
                        self.pragma(ext)
                    elif isinstance(ext, c_ast.FuncCall) and isinstance(ext.name, c_ast.ID) \
                            and ext.name.name in ('__cc816_asm', '__cc816_asm_ops'):
                        text = self.asm_text(ext, top=True)
                        self.unit.asm.append((len(self.unit.funcs), text))
                    else:
                        self.unsup(f'{type(ext).__name__} at file scope', ext)
                except CError as e:
                    self.record(e)
                    self.fn = None
                    del self.scopes[1:]
                    del self.tags[1:]
        except _TooMany:
            self.diag.errors.append(f'{self.filename}: error: too many errors, stopped')
        self.end_of_unit()
        u = self.unit
        u.externs -= u.defined
        u.uses_float = self.uses_float
        u.float_printf = self.uses_float and self.calls_printf or self.fmt_float_printf
        u.float_scanf = self.uses_float and self.calls_scanf or self.fmt_float_scanf
        u.ll_printf = self.uses_ll and self.calls_printf or self.fmt_ll_printf
        u.ll_scanf = self.uses_ll and self.calls_scanf or self.fmt_ll_scanf
        return u

    def end_of_unit(self):
        """what can only be checked once the whole file is read: the sizes of tentative
        definitions (a structure defined after them)"""
        for o in self.unit.data:
            t = getattr(o, 'ctype', None)
            if t is None:
                continue
            if t.is_struct and not t.complete:
                n = getattr(o.node, 'name', None) or o.name
                self.diag.error(self.place_of(o.node) or self.filename,
                                f"storage size of '{n}' is not known ({cname(t)} is declared "
                                f"but not defined)")
            elif t.is_arr and t.n is None:
                o.size = t.elem.size
            else:
                o.size = t.size
            if t.is_struct or t.is_arr:
                self.note_float(t)

    def static_assert(self, d):
        v = self.const_eval(d.cond)
        if not isinstance(v, int):
            self.err('_Static_assert needs an integer constant expression', d)
        if not v:
            m = self.strbytes(d.message) if d.message is not None else None
            self.err('static assertion failed' +
                     (f': "{bytes(m).decode("latin-1")}"' if m is not None else ''), d)

    def note_float(self, t):
        """the unit uses floating point when it defines a float object or computes with
        one (a prototype alone, as in stdlib.h, does not count)"""
        if not self.uses_float and _has_float(t):
            self.uses_float = True
        if not self.uses_ll and _has_float(t, ll=True):
            self.uses_ll = True

    def typedef(self, d):
        t = self.decl_type(d.type)
        self.bind(d.name, Sy('typedef', t))

    def global_decl(self, d):
        if d.name is None:      # struct/enum declaration only
            self.decl_type(d.type)
            return
        t = self.decl_type(d.type)
        st = d.storage or []
        prev = self.scopes[0].get(d.name)
        asm = mangle(d.name)
        if prev is not None and prev.kind in ('enum', 'typedef'):
            self.err(f"'{d.name}' redeclared as a different kind of name (it is "
                     f"{'an enumerator' if prev.kind == 'enum' else 'a typedef'})", d)
        if t.is_func:
            if prev is not None and prev.kind == 'global' and not prev.t.is_func:
                self.err(f"'{d.name}' redeclared as a different kind of name (a variable "
                         f"before)", d)
            if prev is not None and prev.kind == 'global' and not compatible(prev.t, t):
                self.err(f"conflicting types for '{d.name}': {cname(t)}, and before "
                         f"{cname(prev.t)}{_at(prev)}", d)
            if prev is None or prev.kind != 'global':
                sy = Sy('global', t, asm=asm)
                sy.coord, sy.name = d.coord, d.name
                self.bind(d.name, sy)
                if '_Noreturn' in (d.funcspec or []):
                    self.noreturn_names.add(d.name)
            elif not prev.t.proto and t.proto:
                prev.t = t
            if 'static' not in st:
                self.unit.externs.add(asm)
            return
        if t.is_void:
            self.err(f"variable '{d.name}' declared void", d)
        if d.init is not None and 'extern' in st:
            self.warn(f"'{d.name}' is declared extern and given a value (it is defined "
                      f"here)", d, 'extern-initializer')
        if t.is_arr and t.n is None and d.init is not None:
            t = ArrT(t.elem, self.init_count(t, d.init))
        if prev is not None and prev.kind == 'global':
            if prev.t.is_func:
                self.err(f"'{d.name}' redeclared as a different kind of name (a function "
                         f"before)", d)
            if not compatible(prev.t.unqual(), t.unqual()):
                self.err(f"conflicting types for '{d.name}': {cname(t)}, and before "
                         f"{cname(prev.t)}{_at(prev)}", d)
            if prev.defined and d.init is not None:
                self.err(f"redefinition of '{d.name}'{_at(prev)}", d)
            if prev.t.is_arr and t.is_arr and t.n is None:
                t = prev.t
        sy = Sy('global', t, asm=asm)
        sy.coord, sy.name = d.coord, d.name
        sy.defined = d.init is not None or (prev is not None and prev.defined)
        self.bind(d.name, sy)
        self.const_value(sy, t, d.init)
        if 'extern' in st and d.init is None:
            self.unit.externs.add(asm)
            return
        if 'typedef' in st:
            return
        export = 'static' not in st
        self.define_data(asm, t, d.init, export, d)

    def const_value(self, sy, t, init):
        """a const (not volatile) integer or float object with a constant initialiser:
        reads of it are that constant (the object is still defined, for &x)"""
        if init is None or not t.const or t.volatile or not (t.is_int or t.is_float):
            return
        if isinstance(init, c_ast.InitList):
            if len(init.exprs) != 1:
                return
            init = init.exprs[0]
        try:
            v = self.const_eval(init)
        except CError:
            return
        if v is None or not isinstance(v, (int, FV)) or (t.is_int and t.is_bool):
            return
        sy.cval = self.wrap(v, t)

    def define_data(self, asm, t, init, export, node):
        if asm in self.unit.defined:
            # a tentative definition followed by a real one: keep the one with data
            if init is None:
                for o in self.unit.data:
                    if o.name == asm and getattr(o, 'ctype', None) is not None and \
                            not (t.is_arr and t.n is None):
                        o.ctype = t     # int a[]; int a[10];: the size is the last one
                return
            self.unit.data = [o for o in self.unit.data if o.name != asm]
        self.unit.defined.add(asm)
        if export:
            self.unit.exports.add(asm)
        self.note_float(t)
        if t.is_arr and t.n is None:
            t = ArrT(t.elem, 1)
        far = self.unit.fardata and _far_place(t)
        if far or (MODEL['far_data'] and _far_place(t)):
            self.unit.farsyms.add(asm)
        if init is None:
            o = DataObj(asm, 'BSS', [], t.size, export)
            o.ctype, o.node = t, node     # its size again at the end (a structure
            o.far = far                   # completed later)
            self.unit.data.append(o)
            return
        if t.is_struct and not t.complete:
            self.err(f"'{getattr(node, 'name', None) or asm}' has an incomplete type "
                     f"({cname(t)})", node)
        img = Image(t.size)
        self.static_init(img, 0, t, init)
        sec = 'RODATA' if _is_const(t) else 'DATA'
        o = DataObj(asm, sec, img.items(), t.size, export)
        o.far = far
        self.unit.data.append(o)

    def str_init(self, t, init):
        """the string literal that initialises the array t (char a[] = "x", or {"x"}),
        or None"""
        if isinstance(init, c_ast.InitList) and len(init.exprs) == 1:
            init = init.exprs[0]
        if isinstance(init, c_ast.Constant) and init.type == 'string' and t.elem.is_int:
            es = self.str_elem(init).size
            if t.elem.size == es:
                return init
            self.err(f'an array of {cname(t.elem)} initialised with a string of '
                     f'{cname(self.str_elem(init))}', init)
        return None

    def init_count(self, t, init):
        s0 = self.str_init(t, init)
        if s0 is not None:
            return len(self.strvals(s0)) + 1
        if isinstance(init, c_ast.InitList):
            mx = [-1]

            def cb(off, et, e, fld):
                mx[0] = max(mx[0], off)
            self.list_init(init.exprs, 0, cb, 0, ArrT(t.elem, None), static=False)
            es = t.elem.size or 1
            return mx[0] // es + 1 if mx[0] >= 0 else 0
        self.err('array size from an initialiser of this kind', init)

    # --- static initialisers -> byte image with relocations
    def static_init(self, img, off, t, init):
        if (t.is_arr or t.is_struct) and isinstance(init, c_ast.CompoundLiteral) and \
                isinstance(init.init, c_ast.InitList):
            lt = self.decl_type(init.type)
            if (lt.is_struct and t.is_struct and same(lt, t)) or \
                    (lt.is_arr and t.is_arr and compatible(lt.elem, t.elem)):
                init = init.init        # (struct S g = (struct S){...}: GNU C)
        if (t.is_arr or t.is_struct) and (isinstance(init, c_ast.InitList) or
                                          (t.is_arr and self.str_init(t, init))):
            img.clear(off, t.size)      # (an initialiser that overrides an earlier one)
        if t.is_arr:
            s0 = self.str_init(t, init)
            if s0 is not None:
                b = self.strbytes(s0)
                es = t.elem.size
                if t.n is not None and len(b) > t.n * es:
                    self.warn(f'the string is longer than the array ({len(b) // es} '
                              f'characters for {t.n})', s0, 'excess-initializers')
                n = t.n * es if t.n is not None else len(b) + es
                for i, c in enumerate(b[:n]):
                    img.byte(off + i, c)
                return
            if not isinstance(init, c_ast.InitList):
                self.err(f"an array is initialised with a list in braces ({{...}}) or a "
                         f"string, not with {cname(self.expr_type(init))}", init)
            n = self.list_init(init.exprs, 0, img, off, t, static=True)
            if n < len(init.exprs):
                self.warn('excess elements in the array initialiser', init.exprs[n],
                          'excess-initializers')
            return
        if t.is_struct:
            if isinstance(init, c_ast.InitList):
                n = self.list_init(init.exprs, 0, img, off, t, static=True)
                if n < len(init.exprs):
                    self.warn('excess elements in the structure initialiser', init.exprs[n],
                              'excess-initializers')
                return
            it = self.expr_type(init)
            if it.is_struct and same(it, t):
                self.err('a static structure is initialised with a constant list in braces '
                         '({...}), not with another structure', init)
            self.err(f"incompatible types when initialising {cname(t)} with {cname(it)}",
                     init)
        if isinstance(init, c_ast.InitList):
            if not init.exprs:
                return
            init = init.exprs[0]
        self.static_scalar(img, off, t, init)

    def static_scalar(self, img, off, t, e):
        img.clear(off, max(t.size, 1))      # (a value given again replaces the first)
        self.check_assign(t, self.expr_type(e), e, 'initialization')
        v = self.const_eval(e)
        if t.is_float:
            self.note_float(t)
            if v is None:
                self.err('the initialiser is not a constant: a global or static variable takes constants only (numbers, addresses of globals and statics, sizeof); give it its value in a function', e)
            if not isinstance(v, (int, FV)):
                self.err('initialiser of a float is not a number', e)
            v = self.wrap(v, t).bits
            for i in range(4):
                img.byte(off + i, (v >> (8 * i)) & 0xFF)
            return
        if isinstance(v, FV) and t.is_ptr:
            self.err('a floating-point value as a pointer', e)
        if v is not None:
            if t.is_ptr and t.isfar:
                img.word(off, v & 0xFFFF)
                img.word(off + 2, (v >> 16) & 0xFFFF)
                return
            v = self.wrap(v, t)
            for i in range(t.size):
                img.byte(off + i, (v >> (8 * i)) & 0xFF)
            return
        a = self.addr_const(e)
        if a is None:
            self.err('the initialiser is not a constant: a global or static variable takes constants only (numbers, addresses of globals and statics, sizeof); give it its value in a function', e)
        sym, aoff = a
        if t.size == 4:
            img.reloc(off, ('f', sym, aoff))
        elif t.size == 2:
            img.reloc(off, ('w', sym, aoff))
        else:
            self.err('address constant in a byte', e)

    def addr_const(self, e):
        """address constant -> (asm symbol, offset) or None"""
        if isinstance(e, c_ast.Cast):
            return self.addr_const(e.expr)
        if isinstance(e, c_ast.Constant) and e.type == 'string':
            return self.string_sym(e), 0
        if isinstance(e, c_ast.ID):
            s = self.lookup(e.name)
            if s and s.kind == 'global' and (s.t.is_arr or s.t.is_func):
                self.unit.externs.add(s.asm)
                return s.asm, 0
            return None
        if isinstance(e, c_ast.UnaryOp) and e.op == '&':
            return self.lval_const(e.expr)
        if isinstance(e, (c_ast.ArrayRef, c_ast.StructRef)):
            # an array element or member that is itself an array (a[2] of int a[3][4]):
            # it decays to its address, a constant when the object is static
            try:
                t = self.expr_type(e)
            except CError:
                return None
            if t.is_arr:
                return self.lval_const(e)
            return None
        if isinstance(e, c_ast.CompoundLiteral) and self.fn is None:
            t = self.decl_type(e.type)
            if t.is_arr:
                return self.static_literal(e), 0
        if isinstance(e, c_ast.BinaryOp) and e.op in ('+', '-'):
            a = self.addr_const(e.left)
            if a is not None:
                k = self.const_eval(e.right)
                if not isinstance(k, int):
                    return None
                t = decay(self.expr_type(e.left))
                sz = t.to.size if t.is_ptr and not t.to.is_void else 1
                return a[0], a[1] + (k * sz if e.op == '+' else -k * sz)
            if e.op == '+':
                a = self.addr_const(e.right)
                k = self.const_eval(e.left)
                if a is not None and isinstance(k, int):
                    t = decay(self.expr_type(e.right))
                    return a[0], a[1] + k * (t.to.size if t.is_ptr else 1)
        return None

    def lval_const(self, e):
        if isinstance(e, c_ast.ID):
            s = self.lookup(e.name)
            if s and s.kind == 'global':
                self.unit.externs.add(s.asm)
                return s.asm, 0
            return None
        if isinstance(e, c_ast.ArrayRef):
            a = self.lval_const(e.name) if not decay(self.expr_type(e.name)).is_ptr or \
                self.expr_type(e.name).is_arr else self.addr_const(e.name)
            k = self.const_eval(e.subscript)
            if a is None or not isinstance(k, int):
                return None
            return a[0], a[1] + k * self.expr_type(e).size
        if isinstance(e, c_ast.StructRef):
            if e.type == '.':
                a = self.lval_const(e.name)
                st = self.expr_type(e.name)
            else:
                a = self.addr_const(e.name)
                st = self.expr_type(e.name).to
            if a is None:
                return None
            f, foff = st.field(e.field.name)
            return a[0], a[1] + foff
        if isinstance(e, c_ast.Constant) and e.type == 'string':
            return self.string_sym(e), 0
        if isinstance(e, c_ast.CompoundLiteral) and self.fn is None:
            return self.static_literal(e), 0
        return None

    def static_literal(self, e):
        t = self.decl_type(e.type)
        if t.is_arr and t.n is None:
            t = ArrT(t.elem, self.init_count(t, e.init))
        self.nlit += 1
        name = f'L_lit{self.nlit}'
        self.define_data(name, t, e.init, False, e)
        return name

    def list_init(self, exprs, i, img, off, t, static, top=True):
        """initialise an aggregate t at off from exprs[i:], with brace elision.
        Returns the index of the first unused expression. Static: into img; otherwise
        img is a callback store(off, type, expr, field).
        top: exprs is t's own brace list (its designators name t's members); False: the
        elements t takes from an outer list (brace elision), which end at a designator;
        'first': the same, but the first one is a designator into t (.a.b = 1, 2: the 2
        goes on in a)."""
        def desig_ok(k):
            return top is True or (top == 'first' and k == i0)
        i0 = i
        if t.is_arr:
            n = t.n
            es = t.elem.size
            k = 0
            while i < len(exprs):
                x = exprs[i]
                if isinstance(x, c_ast.NamedInitializer):
                    if not desig_ok(i):
                        return i
                    d = x.name[0]
                    if not isinstance(d, c_ast.ArrayDesignator):
                        self.err(f"a member designator (.{getattr(d, 'name', '?')}) in the "
                                 f"initialiser of an array", x)
                    if isinstance(d.expr, c_ast.BinaryOp) and d.expr.op == '...':
                        # [lo ... hi] = x (GNU): x for each element (a local's x is
                        # computed for each)
                        lo, hi = self.const_int(d.expr.left), self.const_int(d.expr.right)
                        if hi < lo:
                            self.err(f'an empty range [{lo} ... {hi}] in the initialiser', x)
                        if lo < 0 or (n is not None and hi >= n):
                            self.err(f'the range [{lo} ... {hi}] in the initialiser is '
                                     f'outside the array (0 to '
                                     f'{n - 1 if n is not None else "..."})', x)
                        for k in range(lo, hi + 1):
                            j = self.init_designated(x, exprs, i, img, off + k * es, t.elem,
                                                     static)
                        i = j
                        k = hi + 1
                        continue
                    k = self.const_int(d.expr)
                    if k < 0 or (n is not None and k >= n):
                        self.err(f'the array index {k} in the initialiser is outside the '
                                 f'array (0 to {n - 1 if n is not None else "..."})', x)
                    i = self.init_designated(x, exprs, i, img, off + k * es, t.elem, static)
                    k += 1
                    continue
                if n is not None and k >= n:
                    break
                i = self.init_elem(exprs, i, img, off + k * es, t.elem, static)
                k += 1
            return i
        if t.is_struct:
            fields = [f for f in t.fields if f.name is not None or f.type.is_struct]
            k = 0
            while i < len(exprs):
                x = exprs[i]
                if isinstance(x, c_ast.NamedInitializer):
                    if not desig_ok(i):
                        return i
                    d = x.name[0]
                    if not isinstance(d, c_ast.ID):
                        self.err(f'an array designator ([...]) in the initialiser of '
                                 f'{cname(t)}', x)
                    names = [f.name for f in fields]
                    if d.name in names:
                        k = names.index(d.name)
                        f = fields[k]
                        if f.bits is not None:
                            self.init_field(img, off, f, x.expr, static)
                            i += 1
                        else:
                            i = self.init_designated(x, exprs, i, img, off + f.offset,
                                                     f.type, static)
                        k += 1
                    else:
                        # a member of an anonymous structure or union member
                        r = t.field(d.name)
                        if not r:
                            self.err(f"no member named '{d.name}' in {cname(t)}", x)
                        f = r[0]
                        if f.bits is not None:
                            self.init_field(img, off + r[1] - f.offset, f, x.expr, static)
                            i += 1
                        else:
                            i = self.init_designated(x, exprs, i, img, off + r[1], f.type,
                                                     static)
                        # (the positional ones after it go on after the anonymous member)
                        for kk, ff in enumerate(fields):
                            if ff.name is None and ff.type.is_struct and ff.type.field(d.name):
                                k = kk + 1
                    if t.union and not (i < len(exprs) and
                                        isinstance(exprs[i], c_ast.NamedInitializer)):
                        # (a union takes one value; designators after it choose again:
                        # {.b = 8, .a = 7} into an anonymous structure sets both)
                        return i
                    continue
                if k >= len(fields):
                    break
                f = fields[k]
                if f.bits is not None:
                    self.init_field(img, off, f, x, static)
                    i += 1
                else:
                    i = self.init_elem(exprs, i, img, off + f.offset, f.type, static)
                k += 1
                if t.union:
                    break
            return i
        self.init_one(img, off, t, exprs[i], static)
        return i + 1

    def init_designated(self, x, exprs, i, img, off, t, static):
        """exprs[i] is x, a designated initialiser for the member or element t at off:
        initialised, and the positional values after it that go on inside t (.b.x = 3,
        4: the 4 is b.y). -> the index after them"""
        if len(x.name) > 1:
            sub = [c_ast.NamedInitializer(x.name[1:], x.expr, x.coord)] + exprs[i + 1:]
            return i + self.list_init(sub, 0, img, off, t, static, top='first')
        e = x.expr
        if (t.is_arr or t.is_struct) and not isinstance(e, c_ast.InitList):
            if t.is_arr and self.str_init(t, e) is not None:
                self.init_one(img, off, t, e, static)
                return i + 1
            if t.is_struct and not static and same(self.expr_type(e), t):
                self.init_one(img, off, t, e, static)
                return i + 1
            sub = [e] + exprs[i + 1:]
            return i + self.list_init(sub, 0, img, off, t, static, top=False)
        self.init_one(img, off, t, e, static)
        return i + 1

    def init_field(self, img, off, f, e, static):
        if f.bits is None:
            self.init_one(img, off + f.offset, f.type, e, static)
            return
        if isinstance(e, c_ast.InitList):
            e = e.exprs[0]
        if static:
            v = self.const_eval(e)
            if v is None:
                self.err('bit-field initialiser is not a constant', e)
            v = self.wrap(v, f.type)
            img.bits(off + f.offset, f.type.size, f.bitpos, f.bits, v)
        else:
            img(off, None, e, f)

    def init_elem(self, exprs, i, img, off, t, static):
        x = exprs[i]
        if (t.is_struct or t.is_arr) and isinstance(x, c_ast.CompoundLiteral) and \
                isinstance(x.init, c_ast.InitList):
            lt = self.decl_type(x.type)
            if (lt.is_struct and t.is_struct and same(lt, t)) or \
                    (lt.is_arr and t.is_arr and compatible(lt.elem, t.elem)):
                # (an element given as a compound literal of its own type: its list, so
                # that a static one stays a constant (GNU C))
                self.init_one(img, off, t, x.init, static)
                return i + 1
        if (t.is_arr or t.is_struct) and not isinstance(x, c_ast.InitList):
            if t.is_arr and isinstance(x, c_ast.Constant) and x.type == 'string':
                self.init_one(img, off, t, x, static)
                return i + 1
            if t.is_struct and not static and same(self.expr_type(x), t):
                self.init_one(img, off, t, x, static)
                return i + 1
            return self.list_init(exprs, i, img, off, t, static, top=False)
        self.init_one(img, off, t, x, static)
        return i + 1

    def init_one(self, img, off, t, e, static):
        if static:
            self.static_init(img, off, t, e)
        else:
            img(off, t, e, None)

    # ================================================================== functions
    def funcdef(self, fd):
        d = fd.decl
        name = d.name
        self.loc = d.coord
        c = d.coord
        if c is not None and (c.file, c.line, c.column) in self.implicit_int:
            self.diag.error(c, f"the function '{name}' has no return type: write 'int "
                               f"{name}(...)' (C99 has no implicit int)")
        ft = self.decl_type(d.type)
        if not ft.is_func:
            self.err(f"'{name}' is not a function, but is followed by a body", d)
        if fd.param_decls:      # K&R definitions
            kr = {}
            names = [n for n, _ in ft.params]
            for p in fd.param_decls:
                if p.name not in names:
                    self.err(f"declaration for parameter '{p.name}' but no such parameter",
                             p)
                kr[p.name] = self.param_adjust(self.decl_type(p.type))
            ft.params = [(n, kr.get(n, INT)) for n, _ in ft.params]
        if ft.ret.is_struct and not ft.ret.complete:
            self.err(f"the return type {cname(ft.ret)} is incomplete (declared but not "
                     f"defined)", d)
        storage = d.storage or []
        static = 'static' in storage
        funcspec = d.funcspec or []
        asm = mangle(name)
        prev = self.scopes[0].get(name)
        if prev is not None and prev.kind == 'global':
            if prev.defined:
                self.err(f"redefinition of '{name}'{_at(prev)}", d)
            if not prev.t.is_func:
                self.err(f"'{name}' redeclared as a different kind of name (a variable "
                         f"before)", d)
            if not compatible(prev.t, ft):
                self.err(f"conflicting types for '{name}': {cname(ft)}, and before "
                         f"{cname(prev.t)}{_at(prev)}", d)
        elif prev is not None and prev.kind in ('enum', 'typedef'):
            self.err(f"'{name}' redeclared as a different kind of name", d)
        if 'inline' in funcspec and 'extern' not in storage and not static and \
                (prev is None or prev.kind != 'global'):
            # a C99 inline definition (in a header, included by several files): private
            # to the file, so the files do not define it twice
            static = True
        if '_Noreturn' in funcspec:
            self.noreturn_names.add(name)
        sy = Sy('global', ft, asm=asm)
        sy.coord, sy.name, sy.defined = d.coord, name, True
        self.bind(name, sy)
        self.unit.defined.add(asm)
        if not static:
            self.unit.exports.add(asm)
        f = Func(asm, static)
        f.ctype = ft
        f.coord = d.coord
        if name in self.attrs.get('naked', ()):
            return self.naked_function(f, fd, name)
        f.cname = name
        f.variadic = ft.variadic
        self.fn = f
        self.labels = {}
        self.brk = []
        self.cont = []
        self.switches = []
        self.depth = 0
        self.addr_taken = set()
        _scan_addr(fd.body, self.addr_taken)
        self.cur = None
        self.newblock('entry')
        self.label_goto = {}
        self.label_used = set()
        self.push()
        # the hidden structure-return pointer comes first
        argoff = 0
        if ft.ret.is_struct:
            v = f.newv(2, 'sret')
            v.param = argoff
            argoff += 2
            f.params.append(v)
            self.sret = v
        else:
            self.sret = None
        self.note_float(ft.ret)
        seen = set()
        for pname, pt in ft.params:
            self.note_float(pt)
            if pname is not None:
                if pname in seen:
                    self.err(f"redefinition of parameter '{pname}'", d)
                seen.add(pname)
            if pt.is_struct and not pt.complete:
                self.err(f"parameter '{pname}' has an incomplete type ({cname(pt)})", d)
            if pt.is_struct:
                v = f.newv(2, (pname or 'p'))
                v.param = argoff
                argoff += 2
                f.params.append(v)
                if pname:
                    sy = Sy('mem', pt, base=v)
                    sy.param = True
                    self.bind(pname, sy)
                continue
            size = vsz(pt)
            v = f.newv(size, pname or 'p')
            v.param = argoff
            argoff += size
            f.params.append(v)
            if pname is None:
                continue
            if pname in self.addr_taken or pt.volatile:
                slot = self.new_slot(pname, pt.size)
                self.store(Frame(slot), None, 0, pt, v)
                sy = Sy('mem', pt, slot=slot, base=Frame(slot))
            else:
                if pt.is_int and pt.size == 1:
                    # a char argument comes as an int: make it a valid char value
                    self.emit(Ins('x8s' if pt.signed else 'x8u', v, v))
                sy = Sy('reg', pt, v=v)
            sy.param = True
            self.bind(pname, sy)
        f.argsize = argoff
        self.compound(fd.body, newscope=False)
        if self.cur is not None and not self.cur.term and not ft.ret.is_void and \
                name != 'main' and id(self.cur) not in self.noreturn_blocks and \
                self.reachable(self.cur):
            c = fd.body.coord
            end = getattr(self, 'compound_end', {}).get((c.file, c.line, c.column), c) \
                if c is not None else None
            self.diag.warning(end or self.filename, f"control reaches the end of the non-void "
                              f"function '{name}' (a return is missing)", 'return-type')
        if self.cur is not None and not (self.cur.term):
            if name == 'main':
                self.emit(Ins('ret', a=Imm(0)))
            else:
                self.emit(Ins('ret', a=Imm(0, vsz(ft.ret)) if not ft.ret.is_void and not ft.ret.is_struct else None))
        self.pop()
        for lname, (blk, defined) in self.labels.items():
            if not defined:
                self.diag.error(self.label_goto.get(lname) or self.place_of(fd),
                                f"label '{lname}' used but not defined")
            elif lname not in self.label_used:
                self.diag.warning(getattr(blk, 'coord', None), f"label '{lname}' defined "
                                  f"but not used", 'unused-label')
        f.blocks = [b for b in f.blocks]
        self.unit.funcs.append(f)
        self.fn = None

    def naked_function(self, f, fd, name):
        """__attribute__((naked)): the body is asm statements only, put out as they are
        after the function's label (no prologue, no epilogue: the text returns itself)"""
        texts = []
        for item in fd.body.block_items or []:
            if isinstance(item, c_ast.FuncCall) and isinstance(item.name, c_ast.ID) and \
                    item.name.name in ('__cc816_asm', '__cc816_asm_ops'):
                texts.append(self.asm_text(item, top=True))
            elif not isinstance(item, c_ast.EmptyStatement):
                self.err(f"the naked function '{name}' may hold asm statements only (it has "
                         f"no prologue or epilogue: its assembly reads the arguments at "
                         f"3,s ... and ends with rts)", item)
        f.cname = name
        f.naked = '\n'.join(texts)
        self.unit.funcs.append(f)
        self.fn = None

    def reachable(self, blk):
        """blk can be reached from the function's entry (a call of a function that does
        not return, exit() and the like, ends a path)"""
        k = 0
        while k + 1 < len(self.fn.blocks) and not self.fn.blocks[k].ins:
            k += 1              # (the empty entry block runs into the first one)
        entry = self.fn.blocks[k]
        seen = {id(entry)}
        todo = [entry]
        while todo:
            b = todo.pop()
            if b is blk:
                return True
            if id(b) in self.noreturn_blocks:
                continue
            for n in b.succ():
                if id(n) not in seen:
                    seen.add(id(n))
                    todo.append(n)
        return False

    def new_slot(self, name, size):
        s = FrameSlot(name, max(size, 1))
        self.fn.slots.append(s)
        return s

    # ------------------------------------------------------------------ blocks
    def newblock(self, hint='L'):
        b = Block(f'{hint}')
        b.depth = self.depth
        self.fn.blocks.append(b)
        return b

    def mkblock(self, hint='L'):
        b = Block(hint)
        b.depth = self.depth
        return b

    def place(self, b):
        """make b the current block (fall through from the current one)"""
        if self.cur is not None and not self.cur.term:
            self.cur.ins.append(Ins('jmp', t=b))
        b.depth = self.depth
        self.fn.blocks.append(b)
        self.cur = b

    def emit(self, ins):
        if self.cur is None or self.cur.term:
            # unreachable code: put it in a fresh block (removed later)
            b = self.mkblock('dead')
            self.fn.blocks.append(b)
            self.cur = b
        self.cur.ins.append(ins)
        if ins.op == 'call':
            self.fn.has_calls = True
        return ins

    def jump(self, b):
        self.emit(Ins('jmp', t=b))

    def newv(self, size, name=None):
        return self.fn.newv(size, name)

    # ------------------------------------------------------------------ statements
    def compound(self, node, newscope=True):
        if newscope:
            self.push()
        for s in node.block_items or []:
            self.stmt_safe(s)
        if newscope:
            self.pop()

    def stmt_safe(self, s):
        """a statement; an error in it is noted and the next statement is done (the
        state the statement had changed is put back)"""
        state = (len(self.scopes), len(self.brk), len(self.cont), len(self.switches),
                 self.depth)
        try:
            self.stmt(s)
        except CError as e:
            self.record(e)
            ns, nb, nc, nw, self.depth = state
            while len(self.scopes) > ns:
                self.scopes.pop()
                self.tags.pop()
            del self.brk[nb:]
            del self.cont[nc:]
            del self.switches[nw:]
            self.cur = None
            if isinstance(s, c_ast.Decl) and s.name and s.name not in self.scopes[-1]:
                self.bind_dummy(s.name)

    def undeclared(self, name, e):
        if self.fn is not None and len(self.scopes) > 1:
            self.bind_dummy(name, 1)
            self.err(f"'{name}' undeclared (first use in this function)", e)
        self.err(f"'{name}' undeclared", e)

    def bind_dummy(self, name, scope=-1):
        """a name whose declaration had an error (or that is undeclared): its uses stop
        their statement without more messages (the error was said once)"""
        sy = Sy('error', INT)
        sy.used = True
        self.scopes[scope][name] = sy

    def stmt(self, s):
        if getattr(s, 'coord', None) is not None:
            self.loc = s.coord
        m = getattr(self, 'st_' + type(s).__name__, None)
        if m is None:
            if isinstance(s, (c_ast.Assignment, c_ast.UnaryOp, c_ast.BinaryOp, c_ast.FuncCall,
                              c_ast.ID, c_ast.Constant, c_ast.TernaryOp, c_ast.Cast,
                              c_ast.ArrayRef, c_ast.StructRef, c_ast.ExprList)):
                self.expr_stmt(s)
                return
            self.unsup(f'statement {type(s).__name__}', s)
        m(s)

    def st_Compound(self, s):
        self.compound(s)

    def st_EmptyStatement(self, s):
        pass

    def st_Pragma(self, s):
        self.pragma(s)

    def pragma(self, s):
        text = (s.string or '').strip()
        words = text.split()
        if words[:2] == ['cc816', 'internal_error_test']:
            # (tests/diag: the internal compiler error path, on purpose)
            raise ZeroDivisionError('a test of the internal compiler error message')
        head = re.match(r'[A-Za-z_]\w*', text)
        head = head.group(0) if head else ''
        if head in ('once', 'GCC', 'clang', 'STDC', 'cc816', 'push_macro', 'pop_macro',
                    'ident', 'message', 'warning', 'disable_message', 'enable_message',
                    'off', 'on', 'library', 'comment', 'inline_depth', 'inline_recursion',
                    'intrinsic', 'function', 'region', 'endregion', 'optimize') or not head:
            # (harmless: they change no code; Watcom's messages and options)
            return
        if head == 'pack':
            # structures are always packed: pack(1), pack(), pack(push, 1), pack(pop)
            # are what cc816 does anyway; a bigger alignment it cannot give
            m = re.search(r'\d+', text)
            if m and int(m.group(0)) > 1:
                self.warn(f'#pragma {text}: cc816 packs every structure (no padding): an '
                          f'alignment of {m.group(0)} is not honoured', s, 'unknown-pragmas')
            return
        if head == 'aux':
            m = re.match(r'aux\s+([A-Za-z_]\w*)', text)
            name = m.group(1) if m else '?'
            if '=' in text:
                self.warn(f"#pragma aux {name} = ...: Watcom inline code is ignored: "
                          f"'{name}' needs a C body (or an asm statement)", s,
                          'unknown-pragmas')
            else:
                self.warn(f"#pragma aux {name}: Watcom's calling convention for it is "
                          f"ignored (cc816 has one: arguments on the stack)", s,
                          'unknown-pragmas')
            return
        self.warn(f'#pragma {text}: unknown, ignored', s, 'unknown-pragmas')

    def st_StaticAssert(self, s):
        self.static_assert(s)

    def st_Typedef(self, s):
        self.typedef(s)

    def st_DeclList(self, s):
        for d in s.decls:
            self.st_Decl(d)

    def st_Decl(self, d):
        st = d.storage or []
        if 'typedef' in st:
            self.typedef(d)
            return
        if d.name is None:
            self.decl_type(d.type)
            return
        t = self.decl_type(d.type)
        prev = self.scopes[-1].get(d.name)
        if prev is not None and prev.kind == 'error':
            prev = None             # (an earlier error's stand-in: no redefinition)
        if t.is_func or 'extern' in st:
            if d.init is not None:
                self.err(f"'{d.name}' is declared extern inside a function and has a "
                         f"value", d)
            if prev is not None and prev.kind != 'global':
                self.err(f"'{d.name}' redeclared as a different kind of name (a local "
                         f"variable here){_at(prev)}", d)
            g = self.scopes[0].get(d.name)
            if g is not None and g.kind == 'global':
                if not compatible(g.t.unqual(), t.unqual()):
                    self.err(f"conflicting types for '{d.name}': {cname(t)}, and before "
                             f"{cname(g.t)}{_at(g)}", d)
                self.bind(d.name, g)
            else:
                asm = mangle(d.name)
                sy = Sy('global', t, asm=asm)
                sy.coord, sy.name = d.coord, d.name
                self.bind(d.name, sy)
                # (also visible at file scope from now on, as C's linkage says)
                self.scopes[0].setdefault(d.name, sy)
                self.unit.externs.add(asm)
            return
        if prev is not None:
            what = 'parameter' if prev.param else 'variable'
            self.err(f"redefinition of '{d.name}' (a {what} of that name in the same "
                     f"block){_at(prev)}", d)
        if t.is_void:
            self.err(f"variable '{d.name}' declared void", d)
        if t.is_arr and t.n is None:
            if d.init is None:
                self.err(f"array '{d.name}' has no size (and no initialiser to count)", d)
            t = ArrT(t.elem, self.init_count(t, d.init))
        if 'static' in st:
            self.nstatic += 1
            asm = f'{self.fn.name}__{d.name}_{self.nstatic}'
            sy = Sy('global', t, asm=asm)
            sy.coord, sy.name, sy.local = d.coord, d.name, True
            self.bind(d.name, sy)
            self.const_value(sy, t, d.init)
            self.define_data(asm, t, d.init, False, d)
            return
        if t.is_struct and not t.complete:
            self.err(f"storage size of '{d.name}' is not known ({cname(t)} is declared but "
                     f"not defined)", d)
        self.note_float(t)
        if t.is_arr or t.is_struct or d.name in self.addr_taken or t.volatile:
            slot = self.new_slot(d.name, t.size)
            sy = Sy('mem', t, slot=slot, base=Frame(slot))
            sy.coord, sy.name, sy.local = d.coord, d.name, True
            self.bind(d.name, sy)
            if d.init is not None:
                self.local_init(Frame(slot), t, d.init, d)
            return
        v = self.newv(vsz(t), d.name)
        sy = Sy('reg', t, v=v)
        sy.coord, sy.name, sy.local = d.coord, d.name, True
        self.bind(d.name, sy)
        if d.init is not None:
            init = d.init
            if isinstance(init, c_ast.InitList):
                if not init.exprs:
                    init = c_ast.Constant('int', '0', init.coord)
                else:
                    if len(init.exprs) > 1:
                        self.warn(f"excess elements in the initialiser of '{d.name}' (a "
                                  f"scalar)", init.exprs[1], 'excess-initializers')
                    init = init.exprs[0]
            self.assign_to(LV('reg', t, op=v), init, 'initialization')

    def local_init(self, base, t, init, node=None):
        if t.is_arr or (t.is_struct and isinstance(init, c_ast.InitList)):
            s = self.str_init(t, init) if t.is_arr else None
            if s is not None:
                b = self.strbytes(s)
                es = t.elem.size
                if len(b) > t.n * es:
                    self.warn(f'the string is longer than the array ({len(b) // es} '
                              f'characters for {t.n})', s, 'excess-initializers')
                n = min(len(b) + es, t.size)
                sym = self.string_sym(s)
                self.copy_mem(Sym(sym), base, n)
                if t.size > n:
                    self.emit(Ins('zero', a=_addoff(base, n), n=t.size - n))
                return
            if not isinstance(init, c_ast.InitList):
                self.err(f"an array is initialised with a list in braces ({{...}}) or a "
                         f"string, not with {cname(self.expr_type(init))}", init)
            self.emit(Ins('zero', a=base, n=t.size))

            written = []        # (offset, size) stored so far: an initialiser that
                                # overrides one (.a = {1, 2}, .a = {3}) clears first

            def overlaps(o, n):
                return any(o < wo + wn and wo < o + n for wo, wn in written)

            def store(off, et, e, fld):
                if fld is not None:
                    lv = LV('mem', fld.type, base=base, off=off + fld.offset, fld=fld)
                    self.assign_to(lv, e)
                    written.append((off + fld.offset, fld.type.size))
                    return
                if isinstance(e, c_ast.InitList) or (et.is_arr and self.str_init(et, e)):
                    if (et.is_arr or et.is_struct) and overlaps(off, et.size):
                        # (a whole aggregate given again: what was there goes)
                        self.emit(Ins('zero', a=_addoff(base, off), n=et.size))
                        written[:] = [(wo, wn) for wo, wn in written
                                      if not (off <= wo and wo + wn <= off + et.size)]
                if isinstance(e, c_ast.InitList):
                    if et.is_arr or et.is_struct:
                        self.list_init(e.exprs, 0, store, off, et, static=False)
                        return
                    e = e.exprs[0] if e.exprs else c_ast.Constant('int', '0')
                if et.is_arr:
                    s = self.str_init(et, e)
                    if s is None:
                        self.err(f'an array ({cname(et)}) is initialised with a list in '
                                 f'braces or a string', e)
                    b = self.strbytes(s)
                    n = min(len(b) + et.elem.size, et.size)
                    self.copy_mem(Sym(self.string_sym(s)), _addoff(base, off), n)
                    written.append((off, n))
                    return
                lv = LV('mem', et, base=base, off=off)
                v = self.const_eval(e)
                if v is not None and et.is_scalar and not overlaps(off, et.size) and (
                        self.wrap(v, et).bits == 0 if et.is_float else
                        (isinstance(v, int) and v == 0)):
                    return
                self.assign_to(lv, e, 'initialization')
                written.append((off, et.size))
            n = self.list_init(init.exprs, 0, store, 0, t, static=False)
            if n < len(init.exprs):
                self.warn('excess elements in the initialiser', init.exprs[n],
                          'excess-initializers')
            return
        if isinstance(init, c_ast.InitList):
            init = init.exprs[0]
        self.assign_to(LV('mem', t, base=base, off=0), init, 'initialization')

    def st_If(self, s):
        c = self.const_eval(s.cond)
        if c is not None and not _has_labels(s.iffalse if c else s.iftrue):
            # (the branch not taken is left out, unless a label or a case is in it: a
            # goto or the switch can enter it)
            if c:
                self.stmt(s.iftrue)
            elif s.iffalse is not None:
                self.stmt(s.iffalse)
            return
        lt = self.mkblock('then')
        lend = self.mkblock('endif')
        lf = self.mkblock('else') if s.iffalse is not None else lend
        self.cond(s.cond, lt, lf)
        self.place(lt)
        self.stmt(s.iftrue)
        if s.iffalse is not None:
            self.jump(lend)
            self.place(lf)
            self.stmt(s.iffalse)
        self.place(lend)

    def loop(self, cond, body, nxt, post_test=False, init=None):
        self.push()
        if init is not None:
            if isinstance(init, c_ast.DeclList):
                self.st_DeclList(init)
            else:
                self.expr_stmt(init)
        lbody = self.mkblock('loop')
        lcont = self.mkblock('cont')
        lend = self.mkblock('endloop')
        ltest = self.mkblock('test')
        c = self.const_eval(cond) if cond is not None else 1
        if post_test:
            self.jump(lbody)
        elif c == 0:
            self.jump(lend)
        else:
            # rotated loop: test before the first iteration, then at the bottom
            if c is None:
                self.cond(cond, lbody, lend)
            else:
                self.jump(lbody)
        self.depth += 1
        self.brk.append(lend)
        self.cont.append(lcont)
        self.place(lbody)
        self.stmt(body)
        self.place(lcont)
        if nxt is not None:
            self.expr_stmt(nxt)
        self.place(ltest)
        if c is None:
            self.cond(cond, lbody, lend)
        elif c:
            self.jump(lbody)
        else:
            self.jump(lend)
        self.brk.pop()
        self.cont.pop()
        self.depth -= 1
        self.place(lend)
        self.pop()

    def st_While(self, s):
        self.loop(s.cond, s.stmt, None)

    def st_DoWhile(self, s):
        self.loop(s.cond, s.stmt, None, post_test=True)

    def st_For(self, s):
        self.loop(s.cond, s.stmt, s.next, init=s.init)

    def st_Break(self, s):
        if not self.brk:
            self.err("a 'break' not within a loop or a switch", s)
        self.jump(self.brk[-1])

    def st_Continue(self, s):
        if not self.cont:
            self.err("a 'continue' not within a loop", s)
        self.jump(self.cont[-1])

    def st_Return(self, s):
        ft = self.fn.ctype
        rt = ft.ret
        name = self.fn.cname
        if s.expr is None:
            if not rt.is_void and name != 'main':
                self.warn(f"'return' with no value in the function '{name}', which returns "
                          f"{cname(rt)}", s, 'return-type')
            self.emit(Ins('ret', a=None))
            return
        if rt.is_void:
            r = self.rv(s.expr)
            if not r.t.is_void:
                self.warn(f"'return' with a value in the function '{name}', which returns "
                          f"void", s, 'return-type')
            self.emit(Ins('ret', a=None))
            return
        if rt.is_struct:
            v = self.rv(s.expr)
            self.check_assign(rt, v.t, s.expr, 'return')
            self.copy_mem(v.op, self.sret, rt.size)
            self.emit(Ins('ret', a=self.sret))
            return
        r = self.rv(s.expr)
        self.check_assign(rt, r.t, s.expr, 'return')
        v = self.convert(r, rt)
        self.emit(Ins('ret', a=v.op))

    def st_Label(self, s):
        if s.name in self.labels and self.labels[s.name][1]:
            self.err(f"duplicate label '{s.name}'", s)
        b = self.label_block(s.name)
        b.coord = s.coord
        self.labels[s.name] = (b, True)
        self.place(b)
        self.stmt(s.stmt)

    def label_block(self, name):
        if name in self.labels:
            return self.labels[name][0]
        b = self.mkblock('lbl_' + name)
        self.labels[name] = (b, False)
        return b

    def st_Goto(self, s):
        b = self.label_block(s.name)
        self.label_goto.setdefault(s.name, s.coord)
        self.label_used.add(s.name)
        self.jump(b)

    def st_Switch(self, s):
        if not self.expr_type(s.cond).is_int:
            self.err(f'switch on a value that is not an integer '
                     f'({cname(self.expr_type(s.cond))})', s)
        v = self.convert(self.rv(s.cond), promote(self.expr_type(s.cond)))
        t = v.t
        val = v.op
        if isinstance(val, V):
            pass
        else:
            nv = self.newv(vsz(t))
            self.emit(Ins('mov', nv, val))
            val = nv
        sw = Ins('sw', a=val, cases=[], default=None, signed=t.signed)
        self.sw_seen[id(sw)] = {}
        self.emit(sw)
        lend = self.mkblock('endsw')
        self.switches.append((sw, t))
        self.brk.append(lend)
        self.cur = None
        self.stmt(s.stmt)
        self.brk.pop()
        self.switches.pop()
        if sw.x['default'] is None:
            sw.x['default'] = lend
        self.place(lend)

    def st_Case(self, s):
        if not self.switches:
            self.err("a 'case' label not within a switch statement", s)
        sw, t = self.switches[-1]
        if isinstance(s.expr, c_ast.BinaryOp) and s.expr.op == '...':
            return self.case_range(s, sw, t)
        v = self.const_eval(s.expr)
        if not isinstance(v, int):
            self.err("a 'case' label needs an integer constant", s)
        k = self.wrap(v, t)
        if k in self.sw_seen[id(sw)]:
            self.err(f'duplicate case value {k} (also at line {self.sw_seen[id(sw)][k].line})'
                     if getattr(self.sw_seen[id(sw)][k], 'line', None) else f'duplicate case value {k}', s)
        if k != v and self.wrap(v, LONG) == v:
            self.warn(f'the case value {v} does not fit the switch\'s type ({cname(t)}): it '
                      f'is {k}', s, 'overflow')
        self.sw_seen[id(sw)][k] = s.coord
        b = self.mkblock('case')
        sw.x['cases'].append((k & ((1 << (8 * t.size)) - 1), b))
        self.place(b)
        for x in s.stmts or []:
            self.stmt(x)

    def case_range(self, s, sw, t):
        """case lo ... hi: (GNU): a few values become cases (a jump table can take them);
        a wider range of a 16-bit switch is one test (gen.py), of a 32- or 64-bit one at
        most 256 cases"""
        lo, hi = self.const_eval(s.expr.left), self.const_eval(s.expr.right)
        if not isinstance(lo, int) or not isinstance(hi, int):
            self.err("a 'case' range needs integer constants", s)
        lo, hi = self.wrap(lo, t), self.wrap(hi, t)
        seen = self.sw_seen[id(sw)]
        b = self.mkblock('case')
        if hi < lo:
            self.warn(f'an empty case range ({lo} ... {hi})', s, 'other')
        elif hi - lo < 32 or t.size > 2:
            if hi - lo >= 256:
                self.unsup(f'a case range of more than 256 values in a switch on a '
                           f'{cname(t)}: test the range with an if', s)
            for k in range(lo, hi + 1):
                if k in seen:
                    self.err(f'duplicate case value {k} (in the range {lo} ... {hi})', s)
                seen[k] = s.coord
                sw.x['cases'].append((k & ((1 << (8 * t.size)) - 1), b))
        else:
            for k in list(seen):
                if lo <= k <= hi:
                    self.err(f'duplicate case value {k} (in the range {lo} ... {hi})', s)
            for rlo, rhi, _ in sw.x.setdefault('ranges', []):
                if not (hi < rlo or rhi < lo):
                    self.err(f'the case range {lo} ... {hi} overlaps another', s)
            sw.x['ranges'].append((lo, hi, b))
        self.place(b)
        for x in s.stmts or []:
            self.stmt(x)

    def st_Default(self, s):
        if not self.switches:
            self.err("a 'default' label not within a switch statement", s)
        sw, t = self.switches[-1]
        if sw.x['default'] is not None:
            self.err("multiple default labels in one switch", s)
        b = self.mkblock('default')
        sw.x['default'] = b
        self.place(b)
        for x in s.stmts or []:
            self.stmt(x)

    # ------------------------------------------------------------------ expression statements
    def expr_stmt(self, e):
        if isinstance(e, c_ast.UnaryOp) and e.op in ('p++', 'p--', '++', '--'):
            self.incdec(e, want=False)
            return
        if isinstance(e, c_ast.Assignment):
            self.assignment(e, want=False)
            return
        if isinstance(e, c_ast.ExprList):
            for x in e.exprs:
                self.expr_stmt(x)
            return
        if isinstance(e, c_ast.Cast) and self.decl_type(e.to_type).is_void:
            self.expr_stmt(e.expr)
            return
        if isinstance(e, c_ast.TernaryOp):
            lt, lf, le = self.mkblock('t'), self.mkblock('f'), self.mkblock('e')
            self.cond(e.cond, lt, lf)
            self.place(lt)
            self.expr_stmt(e.iftrue)
            self.jump(le)
            self.place(lf)
            self.expr_stmt(e.iffalse)
            self.place(le)
            return
        if isinstance(e, c_ast.BinaryOp) and e.op in ('&&', '||'):
            lt, le = self.mkblock('t'), self.mkblock('e')
            if e.op == '&&':
                self.cond(e.left, lt, le)
            else:
                self.cond(e.left, le, lt)
            self.place(lt)
            self.expr_stmt(e.right)
            self.place(le)
            return
        self.rv(e)

    # ================================================================== expressions
    def rv(self, e, dst=None):
        """evaluate e -> RV (arrays and functions decay to pointers)"""
        r = self.rv_nodecay(e, dst)
        t = r.t
        if t.is_arr:
            pt = PtrT(t.elem)
            return RV(self.far_op(r.op, pt), pt)
        if t.is_func:
            return RV(r.op, PtrT(t))
        return r

    def far_op(self, op, pt):
        """the far data model: the address op (a near one: a symbol, a frame object, a
        16-bit value) as the far pointer the type pt says it is (4 bytes)"""
        if MODEL['far_data'] and pt.is_ptr and pt.isfar and (
                isinstance(op, (Sym, Frame)) or (isinstance(op, V) and op.size == 2)):
            d = self.newv(4)
            self.emit(Ins('mkfar', d, op))
            return d
        return op

    def is_far_addr(self, o):
        """o is the address of far memory: a far pointer, or (far data) a far symbol"""
        return (isinstance(o, V) and o.size == 4) or (
            MODEL['far_data'] and isinstance(o, Sym) and o.name in self.unit.farsyms)

    def rv_nodecay(self, e, dst=None):
        if getattr(e, 'coord', None) is not None:
            self.loc = e.coord
        m = getattr(self, 'ex_' + type(e).__name__, None)
        if m is None:
            self.unsup(f'expression {type(e).__name__}', e)
        return m(e, dst)

    def to_dst(self, r, dst):
        if dst is not None and r.op is not dst:
            if dst.size != r.op.size and r.t.is_float:
                return r                # (int e = 97.0;) the conversion that follows moves it
            if dst.size != r.op.size and r.op.size in (2, 4, 8) and not r.t.is_struct:
                # a 16-bit value into a 32-bit register (long x = i; long y = -1;): widened
                # by its own type, as convert() would; a 32-bit one into 16 bits: its low word
                self.widen_into(r, dst)
                return RV(dst, r.t)
            self.emit(Ins('mov', dst, r.op))
            return RV(dst, r.t)
        return r

    def widen_into(self, r, dst):
        op, t = r.op, r.t
        if dst.size < op.size:
            self.emit(Ins('tr', dst, op))
            return
        near = (t.is_ptr and not t.isfar) or t.is_arr or t.is_func
        if isinstance(op, Imm):
            v = op.val
            if t.is_int and t.signed and v >> (8 * op.size - 1):
                v -= 1 << (8 * op.size)
            if near and v:
                self.mkfar_into(dst, op)
                return
            self.emit(Ins('mov', dst, Imm(v, dst.size)))
            return
        if near or isinstance(op, (Sym, Frame)):
            self.mkfar_into(dst, op)
            return
        self.emit(Ins('sx' if t.is_int and t.signed else 'zx', dst, op))

    def far_addr(self, s):
        """the far address of the __far object s (a global) -> a 4-byte value. In the
        large code model a program's __far objects are in banks of their own (hcc places
        them: segment FD_name); else in the code bank, as any object"""
        self.unit.farsyms.add(s.asm)
        d = self.newv(4)
        self.emit(Ins('mkfar', d, Sym(s.asm)))
        return d

    def mkfar_into(self, dst, op):
        """a near address -> dst (4 bytes: far; 8: the far address zero-extended)"""
        if dst.size == 4:
            self.emit(Ins('mkfar', dst, op))
            return
        f = self.newv(4)
        self.emit(Ins('mkfar', f, op))
        self.emit(Ins('zx', dst, f))

    def ex_Constant(self, e, dst):
        if e.type == 'string':
            sym = self.string_sym(e)
            return RV(Sym(sym), self.str_type(e))
        v, t = self.constant(e)
        return self.to_dst(RV(self.cimm(v, t), t), dst)

    def cimm(self, c, t):
        """a constant value of type t (an int, or an FV for a float type) -> Imm"""
        if t.is_float:
            self.uses_float = True
            return Imm(self.wrap(c, t).bits, 4)
        if isinstance(c, FV):
            c = self.wrap(c, t)
        if t.size == 8:
            self.uses_ll = True
        return Imm(c, t.size if t.size in (1, 2, 4, 8) else 2)

    def ex_ID(self, e, dst):
        s = self.lookup(e.name)
        if s is None:
            if e.name == '__func__':
                return self.ex_Constant(c_ast.Constant('string', '"' + self.fn.cname + '"'), dst)
            self.undeclared(e.name, e)
        if s.kind == 'enum':
            return self.to_dst(RV(self.cimm(s.v, s.t), s.t), dst)
        if s.kind == 'global':
            if s.cval is not None:
                return self.to_dst(RV(self.cimm(s.cval, s.t.unqual()), s.t.unqual()), dst)
            self.unit.externs.add(s.asm)
            if s.t.is_arr and _far_place(s.t):
                if MODEL['far_data']:
                    # (far data: the address of a far object is its symbol, reached with
                    # long addressing; rv() makes the far pointer when it decays)
                    self.unit.farsyms.add(s.asm)
                    return RV(Sym(s.asm), s.t)
                return RV(self.far_addr(s), s.t)
            if s.t.is_func or s.t.is_arr:
                return RV(Sym(s.asm), s.t)
        if s.kind == 'reg':
            return self.to_dst(RV(s.v, s.t), dst)
        if s.kind == 'mem' and (s.t.is_arr or s.t.is_struct):
            return RV(s.base, s.t)
        return self.load(self.lval(e), dst)

    # --- lvalues
    def lval(self, e):
        if isinstance(e, c_ast.ID):
            s = self.lookup(e.name)
            if s is None:
                self.undeclared(e.name, e)
            if s.kind == 'reg':
                return LV('reg', s.t, op=s.v)
            if s.kind == 'mem':
                return LV('mem', s.t, base=s.base, off=0)
            if s.kind == 'global':
                self.unit.externs.add(s.asm)
                if not s.t.is_func and _far_place(s.t) and MODEL['far_data']:
                    # (far data: long addressing, f:name, gen.py)
                    self.unit.farsyms.add(s.asm)
                    return LV('mem', s.t, base=Sym(s.asm), off=0)
                if not s.t.is_func and _far_obj(s.t):
                    lv = LV('mem', s.t, base=self.far_addr(s), off=0)
                    lv.farobj = True
                    return lv
                return LV('mem', s.t, base=Sym(s.asm), off=0)
            if s.kind == 'enum':
                self.err(f"'{e.name}' is an enumeration constant, which cannot be assigned "
                         f"or have its address taken", e)
            self.err(f"'{e.name}' is not a variable (a type name?)", e)
        if isinstance(e, c_ast.UnaryOp) and e.op == '*':
            x = e.expr
            if isinstance(x, c_ast.UnaryOp) and x.op in ('p++', 'p--') and isinstance(x.expr, c_ast.ID):
                s = self.lookup(x.expr.name)
                if s is not None and s.kind == 'reg' and s.t.is_ptr and \
                        s.t.to.is_scalar and s.t.to.size in (1, 2, 4):
                    # *p++: access through p, then step p (no copy of the old pointer; a
                    # far p too: a 32-bit step)
                    lv = LV('mem', s.t.to, base=s.v, off=0)
                    lv.post = (s.v, s.t.to.size if x.op == 'p++' else -s.t.to.size)
                    return lv
            p = self.rv(e.expr)
            if not p.t.is_ptr:
                self.err(f"'*' needs a pointer, not {cname(p.t)}", e)
            return self.mem_at(p.op, p.t.to, p.t.isfar)
        if isinstance(e, c_ast.ArrayRef):
            return self.subscript(e)
        if isinstance(e, c_ast.StructRef):
            if e.type == '->':
                p = self.rv(e.name)
                if not p.t.is_ptr:
                    self.err(f"'->' needs a pointer to a structure, not {cname(p.t)}"
                             + (" (use '.')" if p.t.is_struct else ''), e)
                self.check_member_base(p.t.to, e)
                base = self.mem_at(p.op, p.t.to, p.t.isfar)
                st = p.t.to
            else:
                base = self.lval_or_struct(e.name)
                st = base.t
            self.check_member_base(st, e)
            r = st.field(e.field.name)
            if not r:
                self.err(f"no member named '{e.field.name}' in {cname(st)}", e)
            f, foff = r
            ft = f.type.qual(st.const, st.volatile)
            lv = LV('mem', ft, base=base.base, idx=base.idx, off=base.off + foff,
                    fld=f if f.bits is not None else None)
            lv.vol = lv.vol or base.vol
            lv.nnidx = base.nnidx
            lv.farobj = base.farobj and e.type == '.'
            return lv
        if isinstance(e, c_ast.CompoundLiteral):
            t = self.expr_type(e)
            slot = self.new_slot('lit', t.size)
            self.local_init(Frame(slot), t, e.init)
            return LV('mem', t, base=Frame(slot), off=0)
        if isinstance(e, c_ast.Cast):
            # (T)x as an lvalue: a GNU extension; allow pointer reinterpretation
            lv = self.lval(e.expr)
            lv.t = self.decl_type(e.to_type)
            return lv
        if isinstance(e, c_ast.Constant) and e.type == 'string':
            return LV('mem', self.str_type(e), base=Sym(self.string_sym(e)), off=0)
        if isinstance(e, c_ast.FuncCall) or isinstance(e, c_ast.Assignment) or \
                isinstance(e, c_ast.TernaryOp) or isinstance(e, c_ast.ExprList):
            r = self.rv_nodecay(e)
            if r.t.is_struct:
                return self.mem_at(r.op, r.t, False)
        self.err('lvalue required: this cannot be assigned or have its address taken (a '
                 'variable, an array element, *p or a member can)', e)

    def check_member_base(self, t, e):
        if not t.is_struct:
            self.err(f"a member ('{e.field.name}') of something that is not a structure or a "
                     f"union ({cname(t)})" + (" (use '->' for a pointer)"
                                               if t.is_ptr and e.type == '.' else ''), e)
        if not t.complete:
            self.err(f"a member ('{e.field.name}') of an incomplete type: {cname(t)} is "
                     f"declared but not defined here", e)

    def lval_or_struct(self, e):
        """an lvalue of structure type, or a structure rvalue (a call result) as memory"""
        if isinstance(e, (c_ast.FuncCall, c_ast.TernaryOp, c_ast.Assignment, c_ast.ExprList)):
            r = self.rv_nodecay(e)
            return self.mem_at(r.op, r.t, False)
        return self.lval(e)

    def mem_at(self, addr, t, far):
        """memory at address operand addr"""
        if isinstance(addr, Imm):
            if far:
                v = self.newv(4)
                self.emit(Ins('mov', v, addr))
                return LV('mem', t, base=v, off=0)
            return LV('mem', t, base=Sym('__abs0', 0), off=addr.val)
        if isinstance(addr, Sym):
            return LV('mem', t, base=Sym(addr.name), off=addr.off)
        if isinstance(addr, Frame):
            return LV('mem', t, base=Frame(addr.slot), off=addr.off)
        return LV('mem', t, base=addr, off=0)

    def subscript(self, e):
        at = decay(self.expr_type(e.name))
        it = decay(self.expr_type(e.subscript))
        arr, idx = e.name, e.subscript
        if not at.is_ptr:
            arr, idx = idx, arr
            at = it
        if not at.is_ptr:
            self.err(f'a subscript ([]) of something that is not an array or a pointer '
                     f'({cname(decay(self.expr_type(e.name)))})', e)
        if not decay(self.expr_type(idx)).is_int:
            self.err(f'an array subscript is not an integer '
                     f'({cname(decay(self.expr_type(idx)))})', e)
        if at.to.is_void:
            self.err("a subscript of a 'void *' (cast it to a pointer to the elements' type)",
                     e)
        if at.to.is_struct and not at.to.complete:
            self.err(f'a subscript of a pointer to an incomplete type ({cname(at.to)})', e)
        el = at.to
        size = el.size if not el.is_void else 1
        # constant part of the index: a[i + 3] -> base + i*size, offset 3*size
        koff = 0
        while isinstance(idx, c_ast.BinaryOp) and idx.op in ('+', '-') and self.const_eval(idx.right) is not None:
            k = self.const_eval(idx.right)
            koff += k if idx.op == '+' else -k
            idx = idx.left
        kv = self.const_eval(idx)
        # (a[d + 1] with d = -1: the index register holds d alone, $FFFF, and the base is
        # a + 1: gen.addr adds the two in 16 bits unless d is known non-negative (an index
        # register carries into the next bank: r040, the Prince of Persia port)
        # the base address: an array (a variable, an element of an array of arrays, a
        # member) as an lvalue, its element's index added to its own (a[i][j]: one 16-bit
        # index); else a pointer's value
        isarr = isinstance(arr, (c_ast.ID, c_ast.ArrayRef, c_ast.StructRef)) and \
            self.expr_type(arr).is_arr and \
            not (isinstance(arr, c_ast.ID) and not self.lookup(arr.name))
        if isarr:
            base = self.lval(arr)
        else:
            p = self.rv(arr)
            base = self.mem_at(p.op, el, p.t.isfar)
        if kv is not None:
            lv = LV('mem', el, base=base.base, idx=base.idx, off=base.off + (kv + koff) * size)
            lv.farobj = base.farobj
            lv.nnidx = base.nnidx
            return lv
        iv = self.convert(self.rv(idx), INT if self.expr_type(idx).signed else UINT)
        sc = self.scale(iv.op, size)
        if isinstance(base.base, V) and base.base.size == 4 and not base.farobj and \
                base.idx is not None:
            # (through a far pointer, an earlier unsigned index goes into the pointer first)
            z = self.newv(4)
            self.emit(Ins('zx', z, base.idx))
            nv = self.newv(4)
            self.emit(Ins('add', nv, base.base, z))
            base = LV('mem', base.t, base=nv, off=base.off)
        if base.idx is not None:
            nv = self.newv(2)
            self.emit(Ins('add', nv, base.idx, sc))
            sc = nv
        if isinstance(base.base, V) and base.base.size == 4 and \
                not base.farobj and iv.t.signed and MODEL['far_data']:
            # (far data: a far pointer + a signed index: the index added to the offset
            # alone, as DOS's far pointers do (the element is in the pointer's object, so
            # in its bank): 20 cycles less than widening the index to 32 bits and adding).
            # The constant part of the index goes into the offset too: p[d + 1] with
            # d = -1 at a bank's start would put p + d out of the bank (the offset wraps
            # to $FFFE, and [p],y with Y = 2 carries into the next bank)
            if koff:
                k = self.newv(2)
                self.emit(Ins('add', k, sc, Imm((koff * size) & 0xFFFF)))
                sc = k
            nv = self.newv(4)
            self.emit(Ins('addlo', nv, base.base, sc))
            return LV('mem', el, base=nv, off=base.off)
        if isinstance(base.base, V) and base.base.size == 4 and \
                not base.farobj and iv.t.signed:
            # far pointer + a signed index: a 32-bit step (the index may be negative)
            z = self.newv(4)
            self.emit(Ins('sx' if iv.t.signed else 'zx', z, sc))
            nv = self.newv(4)
            self.emit(Ins('add', nv, base.base, z))
            return LV('mem', el, base=nv, off=base.off + koff * size)
        # (a far pointer + an unsigned index, and any index into a __far object, which lies
        # in one bank: the index in Y, [pointer],y; the Xargon port's 2-D board)
        lv = LV('mem', el, base=base.base, idx=sc, off=base.off + koff * size)
        lv.farobj = base.farobj
        # (an array object's index: 0 or more; without a positive constant part (a[d + 1]:
        # d may be -1) the part in the register is 0 or more too)
        lv.nnidx = isarr and koff <= 0 and (base.idx is None or base.nnidx)
        return lv

    def scale(self, op, size):
        if size == 1:
            return op
        if isinstance(op, Imm):
            return Imm(op.val * size)
        v = self.newv(2)
        self.emit(Ins('mul', v, op, Imm(size)))
        return v

    # --- loads and stores
    def finish(self, lv):
        if lv.post is not None:
            v, k = lv.post
            self.emit(Ins('add', v, v, Imm(k, v.size) if v.size == 4 else Imm(k & 0xFFFF)))
            lv.post = None

    def load(self, lv, dst=None, final=True):
        r = self.load1(lv, dst)
        if final:
            self.finish(lv)
        return r

    def load1(self, lv, dst=None):
        t = lv.t
        if t.is_void:
            self.err("a 'void' value is read (through a 'void *': cast it to a pointer to the "
                     "type it points to)")
        if t.is_struct and not t.complete:
            self.err(f'a value of an incomplete type ({cname(t)}) is used')
        if lv.kind == 'reg':
            return self.to_dst(RV(lv.op, t), dst)
        if t.is_arr or t.is_struct or t.is_func:
            return RV(self.addr_of(lv), t)
        if lv.fld is not None:
            return self.load_bits(lv, dst)
        size = t.size
        d = dst if dst is not None and dst.size == vsz(t) else self.newv(vsz(t))
        self.emit(Ins('ld', d, base=lv.base, idx=lv.idx, off=lv.off, sz=size,
                      sgn=t.is_int and t.signed, vol=lv.vol, **_nn(lv)))
        return self.to_dst(RV(d, t), dst)

    def store(self, base, idx, off, t, val, vol=False, lv=None):
        self.emit(Ins('st', a=val, base=base, idx=idx, off=off, sz=t.size, vol=vol,
                      **(_nn(lv) if lv is not None else {})))

    def load_bits(self, lv, dst):
        f = lv.fld
        ut = UINT if f.type.size <= 2 else ULONG
        sz = f.type.size
        w = self.newv(4 if sz == 4 else 2)
        self.emit(Ins('ld', w, base=lv.base, idx=lv.idx, off=lv.off, sz=sz, sgn=False, vol=lv.vol,
                      **_nn(lv)))
        bits = 8 * (4 if sz == 4 else 2)
        r = w
        if f.type.signed:
            if bits - f.bitpos - f.bits:
                r2 = self.newv(w.size)
                self.emit(Ins('shl', r2, r, Imm(bits - f.bitpos - f.bits)))
                r = r2
            r3 = self.newv(w.size)
            self.emit(Ins('sshr', r3, r, Imm(bits - f.bits)))
            r = r3
        else:
            if f.bitpos:
                r2 = self.newv(w.size)
                self.emit(Ins('ushr', r2, r, Imm(f.bitpos)))
                r = r2
            if f.bits < bits:
                r3 = self.newv(w.size)
                self.emit(Ins('and', r3, r, Imm((1 << f.bits) - 1, w.size)))
                r = r3
        rt = promote(f.type) if f.type.size < 4 else f.type
        return self.to_dst(RV(r, rt), dst)

    def store_bits(self, lv, val):
        f = lv.fld
        sz = f.type.size
        vs = 4 if sz == 4 else 2
        mask = ((1 << f.bits) - 1)
        w = self.newv(vs)
        self.emit(Ins('ld', w, base=lv.base, idx=lv.idx, off=lv.off, sz=sz, sgn=False, vol=lv.vol,
                      **_nn(lv)))
        a = self.newv(vs)
        self.emit(Ins('and', a, w, Imm(~(mask << f.bitpos), vs)))
        v = self.conv_op(val, vs)
        b = self.newv(vs)
        self.emit(Ins('and', b, v, Imm(mask, vs)))
        if f.bitpos:
            c = self.newv(vs)
            self.emit(Ins('shl', c, b, Imm(f.bitpos)))
            b = c
        o = self.newv(vs)
        self.emit(Ins('or', o, a, b))
        self.emit(Ins('st', a=o, base=lv.base, idx=lv.idx, off=lv.off, sz=sz, vol=lv.vol,
                      **_nn(lv)))

    def bits_value(self, r, f):
        """the value a bit-field holds after r was stored in it: r cut to the field's width
        (sign-extended for a signed field): the value of the assignment"""
        size = 4 if f.type.size == 4 else 2
        t = (LONG if f.type.signed else ULONG) if size == 4 else (INT if f.type.signed else UINT)
        v = RV(self.conv_op(r, size), t)
        bits = 8 * size
        if f.bits >= bits:
            return v
        if f.type.signed:
            v = self.binop('shl', v.op, Imm(bits - f.bits), t)
            return self.binop('sshr', v.op, Imm(bits - f.bits), t)
        return self.binop('and', v.op, Imm((1 << f.bits) - 1, size), t)

    def copy_mem(self, src, dst, n):
        """a structure copy: MVN in the code bank, or through far addresses (any banks)
        when either side is a far pointer"""
        if self.is_far_addr(src) or self.is_far_addr(dst):
            def far(o):
                if o.size == 4:
                    return o
                d = self.newv(4)
                self.emit(Ins('mkfar', d, o))
                return d
            self.emit(Ins('fcopy', a=far(src), b=far(dst), n=n))
            return
        self.emit(Ins('copy', a=src, b=dst, n=n))

    def conv_op(self, r, size):
        """operand of r resized to size bytes (2/4) by its type"""
        if r.op.size == size:
            return r.op
        return self.convert(r, ULLONG if size == 8 else ULONG if size == 4 else UINT).op

    def addr_of(self, lv):
        if lv.kind == 'reg':
            self.err('address of a register variable')
        base, idx, off = lv.base, lv.idx, lv.off
        if self.is_far_addr(base) and isinstance(base, Sym):
            # (far data: a far object's element or member: its far address)
            f = self.newv(4)
            self.emit(Ins('mkfar', f, _addoff(base, off)))
            base, off = f, 0
        if isinstance(base, V) and base.size == 4:
            a = base
            if idx is not None:
                z = self.newv(4)
                self.emit(Ins('zx', z, idx))
                n = self.newv(4)
                self.emit(Ins('add', n, a, z))
                a = n
            if off:
                n = self.newv(4)
                self.emit(Ins('add', n, a, Imm(off, 4)))
                a = n
            return a
        if isinstance(base, V):
            a = base
            if off:
                a = self.newv(2)
                self.emit(Ins('add', a, base, Imm(off & 0xFFFF)))
        else:
            a = _addoff(base, off)
        if idx is not None:
            v = self.newv(2)
            self.emit(Ins('add', v, a, idx))
            return v
        return a

    def assign_to(self, lv, e, what='assignment'):
        """lv = e; returns the RV stored"""
        t = lv.t
        if t.is_arr:
            self.err(f"assignment to an array ({cname(t)}): copy the elements (memcpy, a "
                     f"loop), or put the array in a structure", e)
        if t.is_func:
            self.err('assignment to a function', e)
        if t.is_struct:
            src = self.rv_nodecay(e)
            self.check_assign(t, src.t, e, what)
            self.copy_mem(src.op, self.addr_of(lv), t.size)
            return RV(self.addr_of(lv), t)
        if lv.kind == 'reg':
            r = self.rv(e, dst=lv.op if not (t.is_int and t.size == 1) else None)
            self.check_assign(t, r.t, e, what)
            r = self.convert(r, t.unqual(), dst=lv.op)
            return r
        r = self.rv(e)
        self.check_assign(t, r.t, e, what)
        r = self.convert(r, t.unqual())
        if lv.fld is not None:
            self.store_bits(lv, r)
            return self.bits_value(r, lv.fld)
        self.store(lv.base, lv.idx, lv.off, t, r.op, lv.vol, lv=lv)
        self.finish(lv)
        return r

    def ex_Assignment(self, e, dst):
        return self.assignment(e, want=True, dst=dst)

    def check_const(self, lv, target, how, node):
        """lv must be writable: not const"""
        if lv.t.const:
            if isinstance(target, c_ast.ID):
                self.err(f"{how} of the read-only variable '{target.name}' (it is const)",
                         node)
            self.err(f"{how} of a read-only location (its type is {cname(lv.t)})", node)

    def check_assign(self, dt, st, e, what):
        """the value e (of type st) given to a dt (an assignment, an initialisation, an
        argument, a return): errors for what C refuses, warnings for what it converts
        without a cast. what: 'assignment', 'initialization', 'return' or
        ('argument', n, function name)"""
        st = decay(st)
        dt = dt.unqual() if not dt.is_ptr else dt
        D, S = cname(dt.unqual()), cname(st.unqual())
        if isinstance(what, tuple):
            lead = f"passing argument {what[1]} of '{what[2]}'"
            bad = f"incompatible type for argument {what[1]} of '{what[2]}': {D} expected, " \
                  f"not {S}"
        elif what == 'return':
            lead = f"returning {S} from a function that returns {D}"
            bad = f"incompatible types when returning {S}: the function returns {D}"
        elif what == 'initialization':
            lead = f"initialising {D} with {S}"
            bad = f"incompatible types when initialising {D} with {S}"
        else:
            lead = f"assigning {S} to {D}"
            bad = f"incompatible types when assigning {S} to {D}"
        if st.is_void:
            self.err(f'a void value is used ({lead[0].lower() + lead[1:]})', e)
        if dt.is_struct or st.is_struct:
            if dt.is_struct and st.is_struct and same(dt.unqual(), st.unqual()):
                return
            self.err(bad, e)
        if dt.is_arith and st.is_arith:
            if dt.is_int and not dt.is_bool and st.is_int:
                self.check_overflow(dt, st, e)
            return
        if dt.is_ptr and st.is_ptr:
            if not (dt.to.is_void or st.to.is_void) and \
                    not compatible(dt.to.unqual(), st.to.unqual()):
                self.warn(f'{lead}: incompatible pointer types', e, 'incompatible-pointer-types')
            if (st.to.const and not dt.to.const) or (st.to.volatile and not dt.to.volatile):
                q = 'const' if st.to.const and not dt.to.const else 'volatile'
                self.warn(f"{lead} discards the '{q}' qualifier of the pointer's target", e,
                          'discarded-qualifiers')
            if st.isfar and not dt.isfar:
                self.warn(f"{lead}: a far pointer given to a near one loses its bank (only the "
                          f"offset is kept: declare the target __far too)", e, 'far-pointer')
            return
        if dt.is_ptr and st.is_int:
            v = self.const_eval(e)
            if isinstance(v, int) and v == 0:
                return
            self.warn(f'{lead} makes a pointer from an integer without a cast', e,
                      'int-conversion')
            return
        if dt.is_int and st.is_ptr:
            if dt.is_bool:
                return
            self.warn(f'{lead} makes an integer from a pointer without a cast', e,
                      'int-conversion')
            return
        self.err(bad, e)

    def check_overflow(self, dt, st, e):
        """a constant that a conversion to dt changes (gcc's -Woverflow)"""
        v = self.const_eval(e)
        if not isinstance(v, int):
            return
        n = 8 * dt.size
        w = self.wrap(v, dt)
        if w == v:
            return
        if dt.signed:
            if st.size == dt.size:
                return          # (int)0xFFFFu: the same bits
        elif -(1 << (n - 1)) <= v < (1 << n):
            return              # (unsigned char)-1: the same bits
        more = ' (int is 16 bits in cc816: use long)' if dt.size == 2 and dt.signed else \
            (' (unsigned int is 16 bits in cc816: use unsigned long)' if dt.size == 2 else '')
        self.warn(f'the conversion to {cname(dt)} changes the value {v} to {w}{more}', e,
                  'overflow')

    def assignment(self, e, want, dst=None):
        lv = self.lval(e.lvalue)
        self.check_const(lv, e.lvalue, 'assignment', e)
        if e.op == '=':
            r = self.assign_to(lv, e.rvalue)
            return self.to_dst(RV(r.op, lv.t.unqual()), dst) if want else None
        op = e.op[:-1]
        # compound: lv = lv op rhs (lv evaluated once)
        cur = self.load(lv, final=False)
        rhs = self.rv(e.rvalue)
        target = lv.op if lv.kind == 'reg' and not (lv.t.is_int and lv.t.size == 1) else None
        if lv.t.is_ptr and op in ('+', '-'):
            if not rhs.t.is_int:
                self.err(f'invalid operands to {e.op} ({cname(lv.t)}, {cname(rhs.t)})', e)
            res = self.ptr_arith(op, cur, rhs, dst=target)
        else:
            if not (cur.t.is_arith and rhs.t.is_arith):
                self.err(f'invalid operands to {e.op} ({cname(cur.t)} and {cname(rhs.t)})', e)
            at = arith_conv(cur.t, rhs.t) if op not in ('<<', '>>') else promote(cur.t)
            same_size = target is not None and vsz(at) == target.size
            res = self.arith(op, cur, rhs, e, dst=target if same_size else None)
            res = self.convert(res, lv.t.unqual(), dst=target)
        if lv.kind == 'reg':
            if res.op is not lv.op:
                res = self.convert(res, lv.t.unqual(), dst=lv.op)
        elif lv.fld is not None:
            self.store_bits(lv, res)
            res = self.bits_value(res, lv.fld)
        else:
            res = self.convert(res, lv.t.unqual())
            self.store(lv.base, lv.idx, lv.off, lv.t, res.op, lv.vol, lv=lv)
            self.finish(lv)
        return self.to_dst(RV(res.op, lv.t.unqual()), dst) if want else None

    def incdec(self, e, want, dst=None):
        lv = self.lval(e.expr)
        t = lv.t
        self.check_const(lv, e.expr, 'increment' if '+' in e.op else 'decrement', e)
        if not t.is_scalar:
            self.err(f"wrong type argument to {'increment' if '+' in e.op else 'decrement'} "
                     f"({cname(t)})", e)
        if t.is_ptr and t.to.is_struct and not t.to.complete:
            self.err(f'arithmetic on a pointer to an incomplete type ({cname(t.to)})', e)
        if t.is_float:
            return self.incdec_float(e, lv, want, dst)
        step = t.to.size if t.is_ptr else 1
        if t.is_ptr and t.to.is_void:
            step = 1
        post = e.op.startswith('p')
        op = 'add' if '+' in e.op else 'sub'
        size = vsz(t)
        if lv.kind == 'reg':
            old = None
            if want and post:
                old = self.newv(size)
                self.emit(Ins('mov', old, lv.op))
            if t.is_int and t.is_bool:
                # (a _Bool: ++ makes it 1; -- flips it: 1 - 1 = 0, 0 - 1 = -1, true)
                if op == 'add':
                    self.emit(Ins('mov', lv.op, Imm(1)))
                else:
                    self.emit(Ins('xor', lv.op, lv.op, Imm(1)))
            else:
                self.emit(Ins(op, lv.op, lv.op, Imm(step, size)))
            if t.is_int and t.size == 1 and not t.is_bool:
                self.emit(Ins('x8s' if t.signed else 'x8u', lv.op, lv.op))
            if not want:
                return None
            return self.to_dst(RV(old if post else lv.op, t.unqual()), dst)
        cur = self.load(lv, final=False)
        nv = self.newv(size)
        if t.is_int and t.is_bool:
            if op == 'add':
                self.emit(Ins('mov', nv, Imm(1)))
            else:
                self.emit(Ins('xor', nv, cur.op, Imm(1)))
        else:
            self.emit(Ins(op, nv, cur.op, Imm(step, size)))
        if lv.fld is not None:
            self.store_bits(lv, RV(nv, t))
            if want and not post:
                return self.load(lv, dst)
        else:
            self.store(lv.base, lv.idx, lv.off, t, nv, lv.vol, lv=lv)
            self.finish(lv)
        if not want:
            return None
        if post:
            return self.to_dst(RV(cur.op, promote(t) if t.is_int else t), dst)
        r = RV(nv, t.unqual())
        if t.is_int and t.size == 1:
            r = self.convert(RV(nv, INT), t)
        return self.to_dst(r, dst)

    def incdec_float(self, e, lv, want, dst):
        """++ and -- of a float: x + 1.0 / x - 1.0"""
        t = lv.t.unqual()
        post = e.op.startswith('p')
        irop = 'fadd' if '+' in e.op else 'fsub'
        cur = self.load(lv, final=False)
        old = cur.op
        if lv.kind == 'reg' and want and post:
            old = self.newv(4)
            self.emit(Ins('mov', old, cur.op))
        nv = lv.op if lv.kind == 'reg' else self.newv(4)
        self.emit(Ins(irop, nv, cur.op, Imm(0x3F800000, 4)))
        if lv.kind != 'reg':
            self.store(lv.base, lv.idx, lv.off, t, nv, lv.vol, lv=lv)
            self.finish(lv)
        if not want:
            return None
        return self.to_dst(RV(old if post else nv, t), dst)

    def ex_UnaryOp(self, e, dst):
        op = e.op
        if op in ('p++', 'p--', '++', '--'):
            return self.incdec(e, want=True, dst=dst)
        if op == 'sizeof':
            return self.to_dst(RV(Imm(self.sizeof(e.expr)), UINT), dst)
        if op == '_Alignof':
            return RV(Imm(1), UINT)
        if op == '&':
            if isinstance(e.expr, c_ast.UnaryOp) and e.expr.op == '*':
                r = self.rv(e.expr.expr)
                return self.to_dst(r, dst)
            t = self.expr_type(e.expr)
            if isinstance(e.expr, c_ast.ID):
                s = self.lookup(e.expr.name)
                if s and s.kind == 'global' and s.t.is_func:
                    self.unit.externs.add(s.asm)
                    return RV(Sym(s.asm), PtrT(s.t))
            lv = self.lval(e.expr)
            # an object reached through a far pointer (&p->m, &p[i].m, &(*p).m): its
            # address is far (4 bytes) and its type says so (a near parameter or variable
            # given it now gets -Wfar-pointer; it lost the bank silently before)
            far = self.far_lvalue(e.expr) or (isinstance(lv.base, V) and lv.base.size == 4)
            pt = PtrT(t, far=far)
            return self.to_dst(RV(self.far_op(self.addr_of(lv), pt), pt), dst)
        if op == '*':
            pt = decay(self.expr_type(e.expr))
            if pt.is_ptr and pt.to.is_func:
                return self.rv(e.expr, dst)
            if pt.is_func:
                return self.rv(e.expr, dst)
            return self.load(self.lval(e), dst)
        if op == '!':
            c = self.const_eval(e)
            if c is not None:
                return self.to_dst(RV(Imm(c), INT), dst)
            return self.bool_value(e, dst)
        if op == '+':
            r = self.rv(e.expr)
            return self.convert(r, promote(r.t), dst=dst)
        if op in ('-', '~'):
            c = self.const_eval(e)
            t = self.expr_type(e)
            if c is not None:
                return self.to_dst(RV(self.cimm(c, t), t), dst)
            if not t.is_arith or (op == '~' and not t.is_int):
                self.err(f'invalid operand to unary {op} ({cname(t)})', e)
            r = self.convert(self.rv(e.expr), t)
            d = dst if dst is not None and dst.size == r.op.size else self.newv(r.op.size)
            if t.is_float:              # -x: the sign bit flipped (also of 0 and NaN)
                self.emit(Ins('xor', d, r.op, Imm(fp.SIGN, 4)))
            else:
                self.emit(Ins('neg' if op == '-' else 'com', d, r.op))
            return self.to_dst(RV(d, t), dst)
        self.unsup(f'unary operator {op}', e)

    def ex_Cast(self, e, dst):
        t = self.decl_type(e.to_type)
        if t.is_void:
            self.expr_stmt(e.expr)
            return RV(Imm(0), VOID)
        c = self.const_eval(e)
        if c is not None and (t.is_int or t.is_ptr or t.is_float):
            return self.to_dst(RV(self.cimm(c, t), t), dst)
        r = self.rv(e.expr)
        if r.t.is_ptr and r.t.isfar and t.is_ptr and not t.isfar:
            self.warn(f'a cast of a far pointer ({cname(r.t)}) to a near one ({cname(t)}): only '
                      f'its offset is kept, the bank is lost', e, 'far-cast')
        return self.convert(r, t, dst=dst)

    def convert(self, r, t, dst=None):
        """convert RV r to type t (scalar)"""
        st = r.t
        if t.is_void:
            return r
        if t.is_struct or st.is_struct:
            if t.is_struct and st.is_struct:
                return r
            self.err(f'cannot convert {cname(st)} to {cname(t)}', self.loc)
        if t.is_arr:
            t = PtrT(t.elem)
        if t.is_float or st.is_float:
            return self.convert_float(r, t, dst)
        op = r.op
        tsize = t.size
        if t.is_int and t.is_bool:
            if isinstance(op, Imm):
                return self.to_dst(RV(Imm(1 if op.val else 0), t), dst)
            if st.is_int and st.is_bool and op.size == 2:
                # a _Bool value is 0 or 1 already (as gcc takes it)
                return self.to_dst(RV(op, t), dst)
            d = dst if dst is not None else self.newv(2)
            lt, lf, le = self.mkblock(), self.mkblock(), self.mkblock()
            self.emit(Ins('br', a=op, b=Imm(0, op.size), cc='ne', t=lt, f=lf))
            self.place(lt)
            self.emit(Ins('mov', d, Imm(1)))
            self.jump(le)
            self.place(lf)
            self.emit(Ins('mov', d, Imm(0)))
            self.place(le)
            return RV(d, t)
        # a near pointer (an offset in the code bank) widened to 32 bits (a far pointer or
        # a long) gets the code bank as its high word: (unsigned long)p is p's full
        # address, so HZ_BANK(p) is the code bank. A null pointer stays 0.
        near_src = (st.is_ptr and not st.isfar) or st.is_arr or st.is_func
        vt = vsz(t)                     # the register size of the result: 2, 4 or 8

        def dv(size):
            return dst if dst is not None and dst.size == size else self.newv(size)
        if isinstance(op, Imm):
            v = op.val
            if st.is_int and st.signed and op.size < 8:
                v = self.wrap(v, IntT(op.size, True))
            if tsize >= 4 and near_src and op.size == 2 and (t.is_ptr or t.is_int):
                if v == 0:
                    return self.to_dst(RV(Imm(0, vt), t), dst)
                d = dv(vt)
                self.mkfar_into(d, op)
                return self.to_dst(RV(d, t), dst)
            return self.to_dst(RV(Imm(self.wrap(v, t) if t.is_int else v, vt), t), dst)
        if isinstance(op, (Sym, Frame)):
            if tsize >= 4:
                d = dv(vt)
                self.mkfar_into(d, op)
                return self.to_dst(RV(d, t), dst)
            if tsize == 1:
                d = dv(2)
                self.emit(Ins('x8u', d, op))
                return self.to_dst(RV(d, t), dst)
            return self.to_dst(RV(op, t), dst)
        ssize = op.size
        if tsize >= 4 and near_src and ssize == 2:
            d = dv(vt)
            self.mkfar_into(d, op)
            return self.to_dst(RV(d, t), dst)
        if vt > 2 and vt >= ssize:
            if ssize == vt:
                return self.to_dst(RV(op, t), dst)
            d = dv(vt)
            signed = st.is_int and st.signed
            self.emit(Ins('sx' if signed else 'zx', d, op))
            return self.to_dst(RV(d, t), dst)
        if ssize > vt:
            d = dv(vt)
            self.emit(Ins('tr', d, op))
            op = d
            if tsize >= 2:
                return self.to_dst(RV(d, t), dst)
        if tsize == 1:
            if st.is_int and st.size == 1 and st.signed == t.signed:
                return self.to_dst(RV(op, t), dst)
            d = dv(2)
            self.emit(Ins('x8s' if t.signed else 'x8u', d, op))
            return self.to_dst(RV(d, t), dst)
        return self.to_dst(RV(op, t), dst)

    def convert_float(self, r, t, dst=None):
        """conversions to and from float: helpers __ltof __ultof __ftol __ftoul (C's
        truncation toward zero); to _Bool: x != 0 (a NaN is true, -0.0 false)"""
        self.uses_float = True
        st = r.t
        op = r.op
        if t.is_float and st.is_float:
            return self.to_dst(RV(op, t), dst)
        if not (t.is_arith and st.is_arith):
            self.err(f'cannot convert {cname(st)} to {cname(t)}', self.loc)
        if isinstance(op, Imm):
            if t.is_float:
                v = op.val
                if st.signed:
                    v = self.wrap(v, IntT(op.size, True))
                return self.to_dst(RV(Imm(fp.from_int(v), 4), t), dst)
            v = self.wrap(FV(op.val), t)
            return self.to_dst(RV(Imm(v, vsz(t)), t), dst)
        if t.is_float and op.size == 8:
            # a long long -> float: lib/llconv.c
            return self.ll_helper('__ulltof' if not st.signed else '__lltof', op, 4, t, dst)
        if t.is_int and t.size == 8:
            return self.ll_helper('__ftoll' if t.signed else '__ftoull', op, 8, t, dst)
        if t.is_float:
            # an integer -> float: through a 32-bit value
            if op.size == 4:
                src = op
                h = 'ultof' if not st.signed else 'ltof'
            else:
                src = self.newv(4)
                self.emit(Ins('sx' if st.signed else 'zx', src, op))
                h = 'ltof'
            d = dst if dst is not None and dst.size == 4 else self.newv(4)
            self.emit(Ins(h, d, src))
            return self.to_dst(RV(d, t), dst)
        # float -> an integer
        if t.is_bool:
            m = self.newv(4)
            self.emit(Ins('and', m, op, Imm(0x7FFFFFFF, 4)))
            return self.convert(RV(m, ULONG), t, dst)
        if t.size == 4:
            d = dst if dst is not None and dst.size == 4 else self.newv(4)
            self.emit(Ins('ftol' if t.signed else 'ftoul', d, op))
            return self.to_dst(RV(d, t), dst)
        l = self.newv(4)
        self.emit(Ins('ftol', l, op))
        return self.convert(RV(l, LONG), t, dst)

    def ll_helper(self, name, op, size, t, dst):
        """a conversion between long long and float: a call of the library's C function
        (lib/llconv.c)"""
        asm = mangle(name)
        self.unit.externs.add(asm)
        d = dst if dst is not None and dst.size == size else self.newv(size)
        self.emit(Ins('call', d, tgt=Sym(asm), args=[op]))
        return self.to_dst(RV(d, t), dst)

    def ex_BinaryOp(self, e, dst):
        op = e.op
        c = self.const_eval(e)
        if c is not None:
            t = self.expr_type(e)
            return self.to_dst(RV(self.cimm(c, t), t), dst)
        if op in ('&&', '||', '<', '>', '<=', '>=', '==', '!='):
            return self.bool_value(e, dst)
        lt = decay(self.expr_type(e.left))
        rt = decay(self.expr_type(e.right))
        if lt.is_struct or rt.is_struct or lt.is_void or rt.is_void:
            self.err(f'invalid operands to {op} ({cname(lt)} and {cname(rt)})', e)
        if op in ('+', '-') and (lt.is_ptr or rt.is_ptr):
            if lt.is_float or rt.is_float:
                self.err(f'invalid operands to {op} ({cname(lt)}, {cname(rt)})', e)
            if op == '-' and rt.is_ptr and not lt.is_ptr:
                self.err(f'an integer minus a pointer ({cname(lt)} - {cname(rt)})', e)
            a = self.rv(e.left)
            b = self.rv(e.right)
            return self.ptr_arith(op, a, b, dst)
        a = self.rv(e.left)
        b = self.rv(e.right)
        return self.arith(op, a, b, e, dst)

    def arith(self, op, a, b, node, dst=None):
        if a.t.is_float or b.t.is_float:
            if op not in ('+', '-', '*', '/') or not (a.t.is_arith and b.t.is_arith):
                self.err(f'invalid operands to {op} ({cname(a.t)}, {cname(b.t)})', node)
            t = arith_conv(a.t, b.t)
            a = self.convert(a, t)
            b = self.convert(b, t)
            irop = {'+': 'fadd', '-': 'fsub', '*': 'fmul', '/': 'fdiv'}[op]
            if isinstance(a.op, Imm) and isinstance(b.op, Imm):
                return self.to_dst(RV(Imm(fp.OPS[irop](a.op.val, b.op.val), 4), t), dst)
            d = dst if dst is not None and dst.size == 4 else self.newv(4)
            self.emit(Ins(irop, d, a.op, b.op))
            return self.to_dst(RV(d, t), dst)
        if op in ('<<', '>>'):
            if not a.t.is_int or not b.t.is_int:
                self.err(f'invalid operands to {op} ({cname(a.t)}, {cname(b.t)})', node)
            t = promote(a.t)
            if isinstance(b.op, Imm):
                k = self.wrap(b.op.val, promote(b.t)) if b.t.signed else b.op.val
                if k < 0 or k >= 8 * t.size:
                    self.warn(f'shift count ({k}) is negative or not less than the width of '
                              f'{cname(t)} ({8 * t.size} bits in cc816)', node,
                              'shift-count-overflow')
            a = self.convert(a, t)
            b = self.convert(b, UINT)
            irop = 'shl' if op == '<<' else ('sshr' if t.signed else 'ushr')
            return self.binop(irop, a.op, b.op, t, dst)
        if not a.t.is_int or not b.t.is_int:
            self.err(f'invalid operands to {op} ({cname(a.t)}, {cname(b.t)})', node)
        t = arith_conv(a.t, b.t)
        a = self.convert(a, t)
        b = self.convert(b, t)
        if op in ('/', '%') and isinstance(b.op, Imm) and b.op.val == 0:
            self.warn('division by zero', node, 'div-by-zero')
        irop = {'+': 'add', '-': 'sub', '*': 'mul', '&': 'and', '|': 'or', '^': 'xor',
                '/': 'sdiv' if t.signed else 'udiv', '%': 'smod' if t.signed else 'umod'}[op]
        return self.binop(irop, a.op, b.op, t, dst)

    def binop(self, irop, a, b, t, dst=None):
        size = vsz(t)
        if isinstance(a, Imm) and isinstance(b, Imm):
            v = fold(irop, a.val, b.val, size)
            if v is not None:
                return self.to_dst(RV(Imm(v, size), t), dst)
        # address constants
        if irop in ('add', 'sub') and isinstance(b, Imm) and isinstance(a, (Sym, Frame)) and size == 2:
            k = b.val if irop == 'add' else -b.val
            k = k - 0x10000 if k >= 0x8000 else k
            return self.to_dst(RV(_addoff(a, k), t), dst)
        d = dst if dst is not None and dst.size == size else self.newv(size)
        self.emit(Ins(irop, d, a, b))
        return self.to_dst(RV(d, t), dst)

    def ptr_arith(self, op, a, b, dst=None):
        for p in (a, b):
            if p.t.is_ptr and p.t.to.is_struct and not p.t.to.complete:
                self.err(f'arithmetic on a pointer to an incomplete type ({cname(p.t.to)})')
            if p.t.is_ptr and p.t.to.is_func:
                self.err(f'arithmetic on a function pointer ({cname(p.t)})')
        if a.t.is_ptr and b.t.is_ptr:
            if op != '-':
                self.err(f'adding two pointers ({cname(a.t)} and {cname(b.t)})')
            if not (a.t.to.is_void or b.t.to.is_void) and \
                    not compatible(a.t.to.unqual(), b.t.to.unqual()):
                self.err(f'subtracting pointers to different types ({cname(a.t)} and '
                         f'{cname(b.t)})')
            size = a.t.to.size or 1
            da = a.op if a.op.size == 2 else self.convert(a, UINT).op
            db = b.op if b.op.size == 2 else self.convert(b, UINT).op
            r = self.binop('sub', da, db, INT)
            if size > 1:
                if size & (size - 1) == 0:
                    r = self.binop('sshr', r.op, Imm(size.bit_length() - 1), INT, dst)
                else:
                    r = self.binop('sdiv', r.op, Imm(size), INT, dst)
            return self.to_dst(r, dst)
        if b.t.is_ptr:
            a, b = b, a
        pt = a.t
        size = pt.to.size if not pt.to.is_void else 1
        if pt.to.is_func:
            size = 1
        if pt.isfar and b.t.is_int and b.t.size == 4 and (
                isinstance(b.op, Imm) or MODEL['far_data']):
            # a far pointer plus a long (p + 39999: a decimal constant over 32,767 is a
            # long): the whole 32-bit value, not its low word as an int (which made
            # 39999 -25537)
            if isinstance(b.op, Imm):
                k = self.wrap(b.op.val, b.t) * size
                return self.binop('add', a.op, Imm(-k if op == '-' else k, 4), pt, dst)
            z = b.op
            if size > 1:
                z = self.binop('mul', z, Imm(size, 4), b.t).op
            return self.binop('add' if op == '+' else 'sub', a.op, z, pt, dst)
        i = self.convert(b, INT if b.t.signed else UINT)
        if isinstance(i.op, Imm):
            # (an unsigned index is zero-extended: far + 65535u is 65,535 bytes on)
            k = (self.wrap(i.op.val, INT) if i.t.signed else i.op.val) * size
            if op == '-':
                k = -k
            if pt.isfar:
                return self.binop('add', a.op, Imm(k, 4), pt, dst)
            return self.binop('add', a.op, Imm(k & 0xFFFF), pt, dst)
        sc = self.scale(i.op, size)
        if pt.isfar:
            # (an unsigned index is zero-extended: far + 40000u goes forwards)
            z = self.newv(4)
            self.emit(Ins('sx' if i.t.signed else 'zx', z, sc))
            return self.binop('add' if op == '+' else 'sub', a.op, z, pt, dst)
        return self.binop('add' if op == '+' else 'sub', a.op, sc, pt, dst)

    def bool_value(self, e, dst):
        d = dst if dst is not None and dst.size == 2 else self.newv(2)
        lt, lf, le = self.mkblock('bt'), self.mkblock('bf'), self.mkblock('be')
        self.cond(e, lt, lf)
        self.place(lt)
        self.emit(Ins('mov', d, Imm(1)))
        self.jump(le)
        self.place(lf)
        self.emit(Ins('mov', d, Imm(0)))
        self.place(le)
        return self.to_dst(RV(d, INT), dst)

    def ex_TernaryOp(self, e, dst):
        c = self.const_eval(e.cond)
        if c is not None and _has_labels(e.iffalse if c else e.iftrue):
            c = None
        t = self.expr_type(e)
        if t.is_arr:
            t = PtrT(t.elem)
        if c is not None:
            r = self.rv(e.iftrue if c else e.iffalse)
            return self.convert(r, t, dst=dst) if not t.is_void else r
        if t.is_void:
            self.expr_stmt(e)
            return RV(Imm(0), VOID)
        if t.is_struct:
            d = self.newv(2)
        else:
            size = vsz(t)
            d = dst if dst is not None and dst.size == size else self.newv(size)
        lt, lf, le = self.mkblock('ct'), self.mkblock('cf'), self.mkblock('ce')
        self.cond(e.cond, lt, lf)
        self.place(lt)
        r = self.rv(e.iftrue)
        r = self.convert(r, t, dst=d) if not t.is_struct else self.to_dst(r, d)
        self.jump(le)
        self.place(lf)
        r = self.rv(e.iffalse)
        r = self.convert(r, t, dst=d) if not t.is_struct else self.to_dst(r, d)
        self.place(le)
        return self.to_dst(RV(d, t), dst)

    def ex_Compound(self, e, dst):
        """a statement expression ({ ...; value; }) (GNU): the value of its last
        statement"""
        items = e.block_items or []
        self.push()
        try:
            for x in items[:-1]:
                self.stmt(x)
            r = RV(Imm(0), VOID)
            if items:
                last = items[-1]
                if isinstance(last, (c_ast.Decl, c_ast.DeclList, c_ast.Typedef)) or \
                        type(last).__name__ in STATEMENTS:
                    self.stmt(last)
                else:
                    r = self.rv_nodecay(last, dst)
                    if r.t.is_arr or r.t.is_func:
                        r = RV(r.op, decay(r.t))
        finally:
            self.pop()
        return r

    def ex_ExprList(self, e, dst):
        for x in e.exprs[:-1]:
            self.expr_stmt(x)
        return self.rv_nodecay(e.exprs[-1], dst)

    def ex_ArrayRef(self, e, dst):
        return self.load(self.lval(e), dst)

    def ex_StructRef(self, e, dst):
        return self.load(self.lval(e), dst)

    def ex_GenericSelection(self, e, dst):
        return self.rv_nodecay(self.generic_pick(e), dst)

    def generic_pick(self, e):
        t = decay(self.expr_type(e.expr)).unqual()
        dflt = None
        for a in e.associations:
            if a.type is None:
                dflt = a.expr
                continue
            at = self.decl_type(a.type).unqual()
            if type_eq(at, t):
                return a.expr
        if dflt is None:
            self.err('_Generic: no association matches', e)
        return dflt

    def ex_CompoundLiteral(self, e, dst):
        lv = self.lval(e)
        return self.load(lv, dst)

    def ex_FuncCall(self, e, dst):
        name = e.name.name if isinstance(e.name, c_ast.ID) else None
        args = e.args.exprs if e.args else []
        if name in ('__cc816_asm', '__cc816_asm_ops'):
            self.asm_stmt(e)
            return RV(Imm(0), VOID)
        if name in BUILTINS:
            return self.builtin(name, args, e, dst)
        if name is not None and self.lookup(name) is None:
            if name.startswith('__builtin_'):
                self.unsup(f'the GCC built-in function {name}', e)
            self.warn(f"implicit declaration of the function '{name}' (include its header, "
                      f"or declare it; its result is taken as an int)", e,
                      'implicit-function-declaration')
            asm = mangle(name)
            sy = Sy('global', FuncT(INT, [], False, False), asm=asm)
            sy.name, sy.coord = name, e.coord
            self.scopes[0][name] = sy
            self.unit.externs.add(asm)
        f = self.rv(e.name)
        ft = f.t.to if f.t.is_ptr else f.t
        if not ft.is_func:
            what = f"'{name}'" if name else 'the called object'
            self.err(f'{what} is not a function or a function pointer (its type is '
                     f'{cname(f.t)})', e)
        if ft.ret.is_struct and not ft.ret.complete:
            self.err(f'calling a function with an incomplete return type ({cname(ft.ret)})',
                     e)
        self.note_float(ft.ret)
        if name in PRINTF_NAMES or name in SCANF_NAMES:
            # a constant format links exactly the conversions it has (%f: the float ones,
            # %lld: the long long ones); any other format, what the unit may need
            kinds = self.format_kinds(name, args)
            scan = name in SCANF_NAMES
            if kinds is None:
                if scan:
                    self.calls_scanf = True
                else:
                    self.calls_printf = True
            else:
                if 'f' in kinds:
                    self.uses_float = True
                    setattr(self, 'fmt_float_scanf' if scan else 'fmt_float_printf', True)
                if 'll' in kinds:
                    self.uses_ll = True
                    setattr(self, 'fmt_ll_scanf' if scan else 'fmt_ll_printf', True)
        ops = []
        sret = None
        if ft.ret.is_struct:
            slot = self.new_slot('ret', ft.ret.size)
            sret = Frame(slot)
            ops.append(sret)
        params = ft.params
        fname = name or 'the function'
        if ft.proto and not ft.variadic and len(args) > len(params):
            self.err(f"too many arguments to the function {_q(name)}: {len(args)} given, it "
                     f"takes {len(params)}", e)
        if ft.proto and len(args) < len(params):
            self.err(f"too few arguments to the function {_q(name)}: {len(args)} given, it "
                     f"takes {len(params)}{' or more' if ft.variadic else ''}", e)
        if name in FORMATS and ft.variadic:
            self.check_format(name, args, e)
        for i, a in enumerate(args):
            r = self.rv(a)
            if r.t.is_void:
                self.err(f"a void value given as argument {i + 1} of {_q(name)}", a)
            if i < len(params) and ft.proto:
                self.check_assign(params[i][1], r.t, a, ('argument', i + 1, fname))
            self.note_float(r.t)
            if ft.variadic and i >= len(params):
                # a float among a variadic function's arguments: most likely for a printf
                # (a wrapper), a float pointer for a scanf
                if r.t.is_float or r.t.is_int and r.t.size == 8:
                    self.calls_printf = True
                elif r.t.is_ptr and (r.t.to.is_float or r.t.to.is_int and r.t.to.size == 8):
                    self.calls_scanf = True
            if i < len(params) and ft.proto:
                pt = params[i][1]
            else:
                pt = promote(r.t) if r.t.is_int else r.t
                if MODEL['far_data'] and pt.is_ptr and not pt.isfar and not pt.to.is_func:
                    # (far data: a near pointer among the variable arguments goes as a
                    # far one, as a float goes as a double: va_arg(ap, char *) reads 4)
                    pt = PtrT(pt.to, far=True)
            if pt.is_struct and ft.variadic and i >= len(params):
                # a variadic argument: the structure's bytes themselves on the stack
                # (va_arg(ap, struct s) reads them there), in words, the last one padded
                if not r.t.is_struct or not same(r.t.unqual(), pt.unqual()):
                    self.err(f'argument {i + 1} of {_q(name)} is not a structure', a)
                base = self.mem_at(r.op, pt, r.op.size == 4)
                for k in range(0, pt.size, 2):
                    w = self.newv(2)
                    self.emit(Ins('ld', w, base=base.base, idx=base.idx, off=base.off + k,
                                  sz=2 if k + 1 < pt.size else 1, sgn=False, vol=False))
                    ops.append(w)
                continue
            if pt.is_struct:
                # by value: a private copy in the caller's frame, passed by address
                slot = self.new_slot('arg', pt.size)
                self.copy_mem(r.op, Frame(slot), pt.size)
                ops.append(Frame(slot))
                continue
            r = self.convert(r, pt if not (pt.is_int and pt.size == 1) else promote(pt))
            op = r.op
            if isinstance(op, Imm) and op.size == 1:
                op = Imm(op.val, 2)
            ops.append(op)
        rt = ft.ret
        d = None
        if not rt.is_void and not rt.is_struct:
            size = vsz(rt)
            d = dst if dst is not None and dst.size == size and not (rt.is_int and rt.size == 1) else self.newv(size)
        tgt = f.op
        ci = self.emit(Ins('call', d, tgt=tgt, args=ops))
        if name in SETJMP_NAMES and isinstance(tgt, Sym):
            ci.x['twice'] = True        # setjmp returns twice (regalloc.py)
            self.fn.returns_twice = True
        if name in self.noreturn_names:
            self.noreturn_blocks.add(id(self.cur))
        if rt.is_struct:
            return RV(sret, rt)
        if d is None:
            return RV(Imm(0), VOID)
        r = RV(d, rt)
        if rt.is_int and rt.size == 1:
            # a char result comes back in A as a 16-bit value: normalise it
            nd = dst if dst is not None and dst.size == 2 else self.newv(2)
            self.emit(Ins('x8s' if rt.signed else 'x8u', nd, d))
            r = RV(nd, rt)
        return self.to_dst(r, dst)

    # ------------------------------------------------------------------ inline assembly
    def asm_text(self, e, top=False, fn_vars=None):
        """the text of an asm statement with %[name] put in: a global's (or a static's or a
        function's) assembler name, an enumerator's value; a local or a parameter in a
        register becomes the placeholder \x00k\x00 (fn_vars[k] is its V; gen.py puts
        its register there). top: at file scope (globals only)"""
        if e.name.name == '__cc816_asm_ops':
            self.unsup("GNU asm operands (the ': output : input : clobbers' lists): name C "
                       "variables in the text with %[name] instead (docs/c/reference.md, "
                       "\"Inline assembly\")", e)
        lit = e.args.exprs[0]
        if self.str_elem(lit).size != 1:
            self.err('the text of an asm statement is a plain string ("...")', lit)
        text = bytes(self.strbytes(lit)).decode('latin-1')

        def put(m):
            n = m.group(1)
            sy = self.lookup(n)
            if sy is None:
                self.err(f"'{n}' undeclared (named in an asm statement as %[{n}])", e)
            if sy.kind == 'enum':
                return str(sy.v)
            if sy.kind == 'global':
                if sy.cval is None or not sy.t.const:
                    self.unit.externs.add(sy.asm)
                else:
                    self.unit.externs.add(sy.asm)
                return sy.asm
            if top or fn_vars is None:
                self.err(f"%[{n}]: only globals, statics, functions and enumerators can be "
                         f"named here", e)
            if sy.kind == 'reg':
                v = sy.v
                v.pinned = 'asm'
                if v not in fn_vars:
                    fn_vars.append(v)
                return f'\x00{fn_vars.index(v)}\x00'
            if sy.kind == 'mem':
                what = 'an array' if sy.t.is_arr else 'a structure' if sy.t.is_struct else \
                    'a volatile variable' if sy.t.volatile else \
                    'a variable whose address is taken'
                self.err(f"%[{n}]: '{n}' is {what}, kept on the software stack, which one "
                         f"operand cannot reach: take its address in a pointer variable "
                         f"('p = {'' if sy.t.is_arr else '&'}{n};') and use (%[p]),y", e)
            self.err(f"%[{n}]: '{n}' is not a variable", e)
        return re.sub(r'%\[\s*([A-Za-z_]\w*)\s*\]', put, text)

    def asm_stmt(self, e):
        """an asm statement in a function: its text as it is, the variables it names
        (%[name]) in direct-page registers (regalloc.py), used and changed by it"""
        if self.fn is None:
            self.err('an asm statement outside a function', e)
        vars_ = []
        text = self.asm_text(e, fn_vars=vars_)
        self.nasm += 1
        self.emit(Ins('asm', text=text, vars=vars_, n=self.nasm))
        for sy in self.scopes_vars(vars_):
            if sy.t.is_int and sy.t.size == 1:
                # (a char variable the assembly wrote: made a valid char value again)
                self.emit(Ins('x8s' if sy.t.signed else 'x8u', sy.v, sy.v))
            elif sy.t.is_int and sy.t.is_bool:
                pass

    def scopes_vars(self, vars_):
        out = []
        for sc in reversed(self.scopes):
            for sy in sc.values():
                if sy.kind == 'reg' and sy.v in vars_ and sy not in out:
                    out.append(sy)
        return out

    def format_kinds(self, name, args):
        """the conversions of a printf's or a scanf's constant format: a set of 'f' (a
        floating-point one) and 'll' (a long long one); None when the format is not a
        string constant (or the call has none)"""
        fi = FMT_ARG.get(name)
        if fi is None or len(args) <= fi:
            return None
        f = args[fi]
        if not (isinstance(f, c_ast.Constant) and f.type == 'string'):
            return None
        try:
            fmt = bytes(self.strbytes(f)).decode('latin-1')
        except CError:
            return None
        scan = name in SCANF_NAMES
        rx = _SCANF_CONV if scan else _PRINTF_CONV
        out = set()
        pos = 0
        while True:
            k = fmt.find('%', pos)
            if k < 0:
                return out
            m = rx.match(fmt, k)
            if not m:
                return None             # (one the library may still know: be safe)
            pos = m.end()
            conv, ln = m.group('conv'), m.group('len') or ''
            if conv in 'fFeEgGaA':
                out.add('f')
            elif ln in ('ll', 'j', 'q') and conv in 'diouxXn':
                out.add('ll')

    def check_format(self, name, args, e):
        """a printf's or a scanf's format string against its arguments (-Wformat): the
        sizes matter most here (int is 16 bits, long 32: %d with a long prints wrong)"""
        fi = FORMATS[name]
        if len(args) <= fi:
            return
        f = args[fi]
        if not (isinstance(f, c_ast.Constant) and f.type == 'string'):
            return
        fmt = bytes(self.strbytes(f)).decode('latin-1')
        rest = args[fi + 1:]
        scan = 'scanf' in name
        rx = _SCANF_CONV if scan else _PRINTF_CONV
        n = 0           # the arguments used

        def arg(want, conv):
            nonlocal n
            if n >= len(rest):
                n += 1
                return None
            a = rest[n]
            n += 1
            try:
                t = decay(self.expr_type(a))
            except CError:
                return None
            return a, t, fi + n + 1

        pos = 0
        while True:
            k = fmt.find('%', pos)
            if k < 0:
                break
            m = rx.match(fmt, k)
            if not m:
                self.warn(f"{name}: an unfinished conversion at the end of the format, or "
                          f"one cc816's {name} does not know", f, 'format')
                return
            pos = m.end()
            conv, ln = m.group('conv'), m.group('len') or ''
            spec = m.group(0)
            if conv == '%':
                continue
            if not scan:
                for star in (m.group('width'), m.group('prec')):
                    if star == '*':
                        r = arg('int', spec)
                        if r and not (r[1].is_int and promote(r[1]).size == 2):
                            self.warn(f"{name}: '*' in '{spec}' takes an int, but argument "
                                      f"{r[2]} is {cname(r[1])}", r[0], 'format')
            elif m.group('supp'):
                continue
            r = arg(conv, spec)
            if r is None:
                self.warn(f"{name}: too few arguments for the format ('{spec}' has none)", e,
                          'format')
                return
            a, t, num = r
            msg = self.format_mismatch(scan, conv, ln, t)
            if msg:
                self.warn(f"{name}: '{spec}' {msg}, but argument {num} is {cname(t)}", a,
                          'format')
        if n < len(rest):
            self.warn(f"{name}: too many arguments for the format ({len(rest)} given, the "
                      f"format uses {n})", rest[n], 'format')

    def format_mismatch(self, scan, conv, ln, t):
        """what the conversion expects when t does not match it (or None)"""
        if not scan:
            pt = promote(t) if t.is_int else t
            if conv in 'diouxXc':
                if conv == 'c':
                    ln = ''
                want = 8 if ln in ('ll', 'j', 'q', 'L') else 4 if ln == 'l' else 2
                if not pt.is_int or pt.size != want:
                    if pt.is_int and pt.size == 8:
                        return f"takes {'an int' if want == 2 else 'a long'}, not a long " \
                               f"long (use %ll{conv})"
                    if want == 8:
                        return 'takes a long long'
                    if pt.is_int and pt.size == 4:
                        return f"takes {'an int' if conv in 'di' else 'an unsigned int'} " \
                               f"(16 bits in cc816; use %l{conv} for a long)"
                    if pt.is_int and pt.size == 2:
                        return f"takes a long (32 bits; use %{conv} for an int)"
                    return 'takes ' + ('a long' if want == 4 else 'an int')
                return None
            if conv in 'fFeEgGaA':
                return None if pt.is_float else 'takes a double (or a float)'
            if conv == 's':
                if pt.is_ptr and not pt.isfar and pt.to.is_int and pt.to.size == 1:
                    return None
                if MODEL['far_data']:   # (far data: any string, a near one goes far)
                    return None if pt.is_ptr and pt.to.is_int and pt.to.size == 1 else \
                        'takes a char * (a string)'
                if pt.is_ptr and pt.isfar:
                    return 'takes a near char * (a far string must be copied into the ' \
                           'code bank first: hz_far_copy)'
                return 'takes a char * (a string)'
            if conv == 'p':
                if pt.is_ptr and (not pt.isfar or MODEL['far_data']):
                    return None
                if pt.is_ptr:
                    return 'takes a near pointer (print a far one with %lx and (unsigned ' \
                           'long)p)'
                return 'takes a pointer'
            if conv == 'n':
                return None if pt.is_ptr and pt.to.is_int else 'takes an int *'
            return None
        # scanf: every conversion but %% takes a pointer
        conv = conv[0]
        if not t.is_ptr:
            return 'takes a pointer (&variable)'
        to = t.to
        if conv in 'diouxXn':
            want = {'hh': 1, 'h': 2, 'l': 4, 'll': 8, 'j': 8, 'q': 8, 'L': 8}.get(ln, 2)
            if not to.is_int or to.size != want:
                names = {1: 'a char *', 2: 'a short * or an int *' if ln == 'h' else
                         'an int * (16 bits)', 4: 'a long *', 8: 'a long long *'}
                return f'takes {names[want]}'
            return None
        if conv in 'fFeEgGaA':
            return None if to.is_float else 'takes a float * (double * with %l)'
        if conv in 'sc[':
            return None if to.is_int and to.size == 1 else 'takes a char *'
        if conv == 'p':
            return None if to.is_ptr else 'takes a void **'
        return None

    def builtin(self, name, args, e, dst):
        if name in ('__builtin_va_start', '__va_start'):
            lv = self.lval(args[0])
            d = self.newv(4)
            self.emit(Ins('vastart', d))
            self.store(lv.base, lv.idx, lv.off, lv.t, d, lv=lv) if lv.kind == 'mem' else \
                self.emit(Ins('mov', lv.op, d))
            return RV(Imm(0), VOID)
        if name == '__cop':
            n = self.const_int(args[0])
            ops = [self.convert(self.rv(a), UINT).op for a in args[1:4]]
            d = dst if dst is not None and dst.size == 2 else self.newv(2)
            self.emit(Ins('cop', d, n=n, ra=ops[0], rx=ops[1], ry=ops[2]))
            return self.to_dst(RV(d, UINT), dst)
        if name in ('__builtin_fbits', '__builtin_bitsf'):
            # a float's bits as an unsigned long, and back: the same 32 bits, no code
            if len(args) != 1:
                self.err(f'{name} takes one argument', e)
            r = self.rv(args[0])
            want = FLOAT if name == '__builtin_fbits' else ULONG
            if not (r.t.is_arith or r.t.is_ptr) or (r.t.is_ptr and r.t.size != 4):
                self.err(f'{name} of {cname(r.t)}', e)
            r = self.convert(r, want)
            self.uses_float = True
            return self.to_dst(RV(r.op, BUILTINS[name]), dst)
        if name == '__cbank':
            d = self.newv(2)
            self.emit(Ins('ld', d, base=Sym('__cbank'), idx=None, off=0, sz=2, sgn=False, vol=False))
            return self.to_dst(RV(d, UINT), dst)
        self.unsup(f'builtin {name}', e)

    # ------------------------------------------------------------------ conditions
    def cond(self, e, lt, lf):
        """branch to lt if e is true, else lf (compare-and-branch fusion)"""
        c = self.const_eval(e)
        if c is not None:
            self.jump(lt if c else lf)
            return
        if isinstance(e, c_ast.UnaryOp) and e.op == '!':
            self.cond(e.expr, lf, lt)
            return
        if isinstance(e, c_ast.BinaryOp):
            op = e.op
            if op == '&&':
                mid = self.mkblock('and')
                self.cond(e.left, mid, lf)
                self.place(mid)
                self.cond(e.right, lt, lf)
                return
            if op == '||':
                mid = self.mkblock('or')
                self.cond(e.left, lt, mid)
                self.place(mid)
                self.cond(e.right, lt, lf)
                return
            if op in ('&', '|') and _is_truth(e.left) and _is_truth(e.right) and \
                    _pure(e.right, self):
                # (a < b & c < d): both sides 0 or 1 and the right one without side
                # effects: the same as && / ||, without making the two values
                self.cond(c_ast.BinaryOp('&&' if op == '&' else '||', e.left, e.right,
                                         e.coord), lt, lf)
                return
            if op in ('<', '>', '<=', '>=', '==', '!='):
                lt_ = decay(self.expr_type(e.left))
                rt_ = decay(self.expr_type(e.right))
                self.check_compare(e, lt_, rt_)
                a = self.rv(e.left)
                b = self.rv(e.right)
                if lt_.is_float or rt_.is_float:
                    if not (lt_.is_arith and rt_.is_arith):
                        self.err(f'comparison of {cname(lt_)} and {cname(rt_)}', e)
                    t = arith_conv(lt_, rt_)
                    ao = self.convert(a, t).op
                    bo = self.convert(b, t).op
                    self.float_branch(op, ao, bo, lt, lf)
                    return
                if lt_.is_ptr or rt_.is_ptr:
                    signed = False
                    size = max(a.op.size, b.op.size)
                    if size == 4:
                        a = RV(self.conv_op(a, 4), a.t)
                        b = RV(self.conv_op(b, 4), b.t)
                    ao, bo = a.op, b.op
                else:
                    t = arith_conv(a.t, b.t)
                    signed = t.signed
                    if signed and self.nonneg(e.left, lt_, t) and self.nonneg(e.right, rt_, t):
                        # (both sides 0 or more: an unsigned char promoted to int, a
                        # constant: the unsigned compare is the same, and cheaper)
                        signed = False
                    ao = self.convert(a, t).op
                    bo = self.convert(b, t).op
                cc = {'<': 'lt', '>': 'gt', '<=': 'le', '>=': 'ge', '==': 'eq', '!=': 'ne'}[op]
                if cc not in ('eq', 'ne'):
                    cc = ('s' if signed else 'u') + cc
                self.emit(Ins('br', a=ao, b=bo, cc=cc, t=lt, f=lf))
                return
        if isinstance(e, c_ast.Assignment) and e.op == '=':
            self.warn('an assignment used as a condition: write == to compare, or put the '
                      'assignment in parentheses ((a = b) != 0)', e, 'parentheses')
        r = self.rv(e)
        if r.t.is_struct:
            self.err(f'a structure ({cname(r.t)}) used as a condition', e)
        if r.t.is_void:
            self.err('a void value used as a condition', e)
        op = r.op
        if r.t.is_float:                # x != 0: any bit but the sign (-0.0 is false)
            if isinstance(op, Imm):
                self.jump(lt if op.val & 0x7FFFFFFF else lf)
                return
            m = self.newv(4)
            self.emit(Ins('and', m, op, Imm(0x7FFFFFFF, 4)))
            op = m
        self.emit(Ins('br', a=op, b=Imm(0, op.size), cc='ne', t=lt, f=lf))


    def nonneg(self, e, et, t):
        """e (of type et), converted to the type t of a compare, is never negative: a
        constant of 0 or more, or an unsigned integer narrower than t"""
        v = self.const_eval(e)
        if isinstance(v, int):
            return 0 <= v < (1 << (8 * t.size - 1))
        return et.is_int and not et.signed and et.size < t.size

    def check_compare(self, e, lt, rt):
        """warnings for a comparison: one whose result its types decide (a char compared
        with -1 or 256, an int with 40000, an unsigned with < 0), and errors for operands
        that cannot be compared"""
        if lt.is_struct or rt.is_struct:
            self.err(f'invalid operands to {e.op} ({cname(lt)} and {cname(rt)})', e)
        if lt.is_ptr and rt.is_ptr:
            if not (lt.to.is_void or rt.to.is_void) and \
                    not compatible(lt.to.unqual(), rt.to.unqual()):
                self.warn(f'comparison of distinct pointer types ({cname(lt)} and '
                          f'{cname(rt)})', e, 'incompatible-pointer-types')
            return
        if (lt.is_ptr and rt.is_int) or (lt.is_int and rt.is_ptr):
            other = e.right if lt.is_ptr else e.left
            v = self.const_eval(other)
            if not (isinstance(v, int) and v == 0):
                self.warn(f'comparison between a pointer and an integer ({cname(lt)} and '
                          f'{cname(rt)})', e, 'int-conversion')
            return
        if not (lt.is_int and rt.is_int):
            return
        a, b = self.const_eval(e.left), self.const_eval(e.right)
        if (a is None) == (b is None):
            return
        op = e.op
        if a is not None:       # the constant on the right
            var, k, vt = e.right, a, rt
            op = {'<': '>', '>': '<', '<=': '>=', '>=': '<='}.get(op, op)
        else:
            var, k, vt = e.left, b, lt
        if not isinstance(k, int):
            return
        ct = arith_conv(lt, rt)
        vt0 = _value_type(var, self)
        if vt0 is not None and vt0.is_int and vt0.size < vt.size:
            vt = vt0
        if vt.is_bool:
            lo, hi = 0, 1
        else:
            n = 8 * vt.size
            lo, hi = (-(1 << (n - 1)), (1 << (n - 1)) - 1) if vt.signed else (0, (1 << n) - 1)
        if ct.signed or (not vt.signed and ct.size >= vt.size):
            pass                # the values keep their meaning in ct
        else:
            return              # a signed value converted to unsigned: every value
        kk = self.wrap(k, ct)
        if not ct.signed and vt.signed:
            return
        f = {'<': lambda x: x < kk, '>': lambda x: x > kk, '<=': lambda x: x <= kk,
             '>=': lambda x: x >= kk, '==': lambda x: x == kk, '!=': lambda x: x != kk}[op]
        if op in ('==', '!='):
            if lo <= kk <= hi:
                return
            res = op == '!='
        else:
            r_lo, r_hi = f(lo), f(hi)
            if r_lo != r_hi:
                return
            res = r_lo
        # (a constant the type cannot hold: on by default, the porting mistake of int
        # being 16 bits, or char unsigned; the edges, x <= 32767, u >= 0: -Wall)
        name = 'type-limits' if vt.size == 1 or not lo <= kk <= hi else 'tautological-compare'
        what = f"'{var.name}'" if isinstance(var, c_ast.ID) else 'the value'
        note = ''
        if vt is CHAR or (vt.is_int and vt.name == 'char'):
            note = ' (plain char is unsigned in cc816: use int, or signed char)' \
                if not vt.signed else ''
        elif vt.size == 2 and vt.is_int:
            note = ' (int is 16 bits in cc816)' if vt.signed else \
                ' (unsigned int is 16 bits in cc816)'
        self.warn(f"comparison is always {'true' if res else 'false'}: {what} is "
                  f"{cname(vt)}, {lo} to {hi}{note}", e, name)

    def float_branch(self, op, a, b, lt, lf):
        """a float compare: __fcmp gives -1 (a < b), 0 (equal), 1 (a > b) or 2 (unordered,
        a NaN: every relation false but !=)"""
        self.uses_float = True
        if isinstance(a, Imm) and isinstance(b, Imm):
            c = fp.cmp(a.val, b.val)
            r = {'<': c == -1, '>': c == 1, '<=': c in (-1, 0), '>=': c in (0, 1),
                 '==': c == 0, '!=': c != 0}[op]
            self.jump(lt if r else lf)
            return
        d = self.newv(2)
        self.emit(Ins('fcmp', d, a, b))
        cc, k = {'<': ('slt', 0), '>': ('eq', 1), '<=': ('slt', 1), '>=': ('ult', 2),
                 '==': ('eq', 0), '!=': ('ne', 0)}[op]
        self.emit(Ins('br', a=d, b=Imm(k), cc=cc, t=lt, f=lf))


def type_eq(a, b):
    if a.kind != b.kind:
        return False
    if a.is_int:
        return a.size == b.size and a.signed == b.signed and a.name == b.name
    if a.is_float:
        return a.name == b.name
    if a.is_ptr:
        return a.to.const == b.to.const and a.to.volatile == b.to.volatile and type_eq(a.to, b.to)
    if a.is_struct:
        return a.uid == b.uid
    if a.is_arr:
        return a.n == b.n and type_eq(a.elem, b.elem)
    if a.is_func:
        return type_eq(a.ret, b.ret) and len(a.params) == len(b.params)
    return True


WCHAR = IntT(2, False, 'wchar_t')         # L"...": unsigned int (16 bits, the BMP)
CHAR16 = IntT(2, False, 'char16_t')       # u"..."
CHAR32 = IntT(4, False, 'char32_t')       # U"..."


BUILTINS = {'__builtin_va_start': VOID, '__va_start': VOID, '__cop': UINT, '__cbank': UINT,
            '__builtin_fbits': ULONG, '__builtin_bitsf': FLOAT}


def _has_float(t, ll=False):
    """a float anywhere in t (an array's elements, a structure's members); ll: a long
    long instead"""
    seen = set()
    while True:
        if t.is_float and not ll or ll and t.is_int and t.size == 8:
            return True
        if t.is_arr:
            t = t.elem
            continue
        if t.is_ptr and ll:     # (scanf("%lld", &x): a pointer to one)
            return t.to.is_int and t.to.size == 8
        if t.is_struct and t.complete and id(t) not in seen:
            seen.add(id(t))
            return any(_has_float(f.type, ll) for f in t.fields)
        return False


LLONG_U = ULLONG

SETJMP_NAMES = {'setjmp', '_setjmp', 'sigsetjmp', '__sigsetjmp'}

PRINTF_NAMES = {'printf', 'fprintf', 'sprintf', 'snprintf', 'vprintf', 'vfprintf', 'vsprintf',
                'vsnprintf'}
SCANF_NAMES = {'scanf', 'fscanf', 'sscanf', 'vscanf', 'vfscanf', 'vsscanf'}


def _nn(lv):
    """a load's or store's ilo when its index is an array object's (LV.nnidx)"""
    return {'ilo': 0} if lv.nnidx and isinstance(lv.idx, V) else {}


def decay(t):
    if t.is_arr:
        return PtrT(t.elem)
    if t.is_func:
        return PtrT(t)
    return t


def _addoff(a, k):
    if k == 0:
        return a
    if isinstance(a, Sym):
        return Sym(a.name, a.off + k)
    if isinstance(a, Frame):
        return Frame(a.slot, a.off + k)
    raise CError('internal: offset of a non-constant address')


def _cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def _cmod(a, b):
    return a - b * _cdiv(a, b)


def fold(op, a, b, size):
    bits = 8 * size
    m = (1 << bits) - 1
    if op in ('shl', 'ushr', 'sshr') and not 0 <= b < 64:
        return None

    def s(v):
        v &= m
        return v - (1 << bits) if v >> (bits - 1) else v
    try:
        r = {'add': lambda: a + b, 'sub': lambda: a - b, 'mul': lambda: a * b,
             'and': lambda: a & b, 'or': lambda: a | b, 'xor': lambda: a ^ b,
             'udiv': lambda: (a & m) // (b & m), 'umod': lambda: (a & m) % (b & m),
             'sdiv': lambda: _cdiv(s(a), s(b)), 'smod': lambda: _cmod(s(a), s(b)),
             'shl': lambda: a << b, 'ushr': lambda: (a & m) >> b, 'sshr': lambda: s(a) >> b}[op]()
    except ZeroDivisionError:
        return None
    return r & m


def unescape_wide(s, size):
    """the text of a wide string (L"...", u"...", U"...") -> its code points: the source is
    UTF-8 (read as Latin-1 bytes); \\x, octal, \\u and \\U escapes give values directly"""
    out = []
    i = 0
    lim = (1 << (8 * size)) - 1
    raw = []

    def flush():
        if raw:
            txt = bytes(raw).decode('utf-8', 'replace')
            for ch in txt:
                c = ord(ch)
                if size == 2 and c > 0xFFFF:          # (a UTF-16 pair for u"")
                    c -= 0x10000
                    out.extend([0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF)])
                else:
                    out.append(c & lim)
            raw.clear()
    simple = {'n': 10, 't': 9, 'r': 13, 'a': 7, 'b': 8, 'f': 12, 'v': 11, '\\': 92,
              "'": 39, '"': 34, '?': 63, 'e': 27}
    while i < len(s):
        c = s[i]
        if c != '\\':
            raw.append(ord(c) & 0xFF)
            i += 1
            continue
        flush()
        i += 1
        c = s[i]
        if c == 'x':
            j = i + 1
            while j < len(s) and s[j] in '0123456789abcdefABCDEF':
                j += 1
            out.append(_hexval(s[i + 1:j], '\\x') & lim)
            i = j
        elif c in 'uU':
            n = 4 if c == 'u' else 8
            out.append(_hexval(s[i + 1:i + 1 + n], '\\' + c) & lim)
            i += 1 + n
        elif c in '01234567':
            j = i
            while j < len(s) and j < i + 3 and s[j] in '01234567':
                j += 1
            out.append(int(s[i:j], 8) & lim)
            i = j
        else:
            out.append(simple.get(c, ord(c)))
            i += 1
    flush()
    return out


def _hexval(digits, esc):
    """the value of an escape's hexadecimal digits (an error when there are none)"""
    try:
        return int(digits, 16)
    except ValueError:
        raise CError(f'{esc} used with no hexadecimal digits after it')


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c != '\\':
            out += list(c.encode('latin-1', 'replace'))
            i += 1
            continue
        i += 1
        c = s[i]
        simple = {'n': 10, 't': 9, 'r': 13, '0': 0, 'a': 7, 'b': 8, 'f': 12, 'v': 11,
                  '\\': 92, "'": 39, '"': 34, '?': 63, 'e': 27}
        if c == 'x':
            j = i + 1
            while j < len(s) and s[j] in '0123456789abcdefABCDEF':
                j += 1
            out.append(_hexval(s[i + 1:j], '\\x') & 0xFF)
            i = j
        elif c in 'uU':                     # a universal character: its UTF-8
            n = 4 if c == 'u' else 8
            out += list(chr(_hexval(s[i + 1:i + 1 + n], '\\' + c) % 0x110000).encode(
                'utf-8', 'replace'))
            i += 1 + n
        elif c in '01234567':
            j = i
            while j < len(s) and j < i + 3 and s[j] in '01234567':
                j += 1
            out.append(int(s[i:j], 8) & 0xFF)
            i = j
        else:
            out.append(simple.get(c, ord(c)))
            i += 1
    return out


class Image:
    """a static data image: bytes + relocations"""

    def __init__(self, size):
        self.b = [0] * size
        self.rel = {}

    def byte(self, off, v):
        if off < len(self.b):
            self.b[off] = v & 0xFF

    def word(self, off, v):
        self.byte(off, v)
        self.byte(off + 1, v >> 8)

    def bits(self, off, usize, pos, w, v):
        cur = int.from_bytes(bytes(self.b[off:off + usize]), 'little')
        m = ((1 << w) - 1) << pos
        cur = (cur & ~m) | ((v << pos) & m)
        for i in range(usize):
            self.byte(off + i, cur >> (8 * i))

    def reloc(self, off, r):
        self.rel[off] = r

    def clear(self, off, n):
        for i in range(off, min(off + n, len(self.b))):
            self.b[i] = 0
        for k in [k for k in self.rel if off <= k < off + n]:
            del self.rel[k]

    def items(self):
        out = []
        i = 0
        cur = []
        while i < len(self.b):
            if i in self.rel:
                if cur:
                    out.append(('b', cur))
                    cur = []
                r = self.rel[i]
                out.append(r)
                i += 4 if r[0] == 'f' else 2
                continue
            cur.append(self.b[i])
            i += 1
        if cur:
            out.append(('b', cur))
        return out


def _far_obj(t):
    """a __far object (its type, or its arrays' elements, __far)"""
    while t.is_arr:
        if t.far:
            return True
        t = t.elem
    return t.far


def _near_obj(t):
    """a __near object (the far data model)"""
    while t.is_arr:
        if t.near:
            return True
        t = t.elem
    return t.near


def _far_place(t):
    """an object of type t is placed in far data (and reached by long addressing): a
    __far one; in the far data model also a constant one, unless __near (docs/c/
    reference.md, "Where objects live"). The rule depends on the type alone, so a file
    that only declares the object reaches it as the defining file placed it"""
    if not MODEL['far_data']:
        return _far_obj(t)
    if _near_obj(t):
        return False
    return _far_obj(t) or _is_const(t)


def _is_const(t):
    """a constant object (an array of constants too): read-only data"""
    while t.is_arr:
        if t.const:
            return True
        t = t.elem
    return t.const


def _flat_count(t):
    """number of scalars in t (for brace elision counting)"""
    if t.is_arr:
        return (t.n or 0) * _flat_count(t.elem)
    if t.is_struct:
        return sum(_flat_count(f.type) for f in t.fields if f.name is not None) or 1
    return 1


def _scan_addr(node, out):
    """names whose address is taken (&name) anywhere in the function"""
    if node is None:
        return
    if isinstance(node, c_ast.UnaryOp) and node.op == '&':
        x = node.expr
        while isinstance(x, (c_ast.StructRef, c_ast.ArrayRef)) and \
                not (isinstance(x, c_ast.StructRef) and x.type == '->'):
            x = x.name
        if isinstance(x, c_ast.ID):
            out.add(x.name)
    for _, c in node.children():
        _scan_addr(c, out)


_PLACED = re.compile(r'^(\S+?:\d+(?::\d+)?): error: (.*)$', re.S)


class _TooMany(Exception):
    pass


class _Silent(CError):
    """a use of a name whose declaration had an error: the statement stops, quietly"""
    def __init__(self):
        super().__init__('(an earlier error)')


NORETURN = {'exit', 'abort', '_Exit', 'quick_exit', 'longjmp', '__assert_fail'}


def _at(sy):
    """' (line N)' of a symbol's earlier declaration, for messages"""
    c = getattr(sy, 'coord', None)
    return f' (declared at line {c.line})' if c is not None and getattr(c, 'line', None) else ''


STATEMENTS = {'If', 'While', 'DoWhile', 'For', 'Switch', 'Return', 'Break', 'Continue',
              'Goto', 'Label', 'Case', 'Default', 'Compound', 'EmptyStatement', 'Pragma',
              'StaticAssert'}


def _has_labels(node):
    """a label, a case or a default in node (a goto or a switch can jump into it)"""
    if node is None:
        return False
    if isinstance(node, (c_ast.Label, c_ast.Case, c_ast.Default)):
        return True
    for _, c in node.children():
        if _has_labels(c):
            return True
    return False


def _is_truth(e):
    """an expression whose value is 0 or 1: a comparison, !, && or ||"""
    return isinstance(e, c_ast.BinaryOp) and e.op in ('<', '>', '<=', '>=', '==', '!=', '&&',
                                                      '||') or \
        isinstance(e, c_ast.UnaryOp) and e.op == '!'


def _pure(e, f):
    """an expression without side effects (no call, assignment, ++ or --, volatile
    read)"""
    if isinstance(e, (c_ast.FuncCall, c_ast.Assignment, c_ast.Compound)):
        return False
    if isinstance(e, c_ast.UnaryOp) and e.op in ('++', '--', 'p++', 'p--'):
        return False
    if not isinstance(e, (c_ast.ID, c_ast.Constant, c_ast.BinaryOp, c_ast.UnaryOp,
                          c_ast.ArrayRef, c_ast.StructRef, c_ast.Cast, c_ast.TernaryOp)):
        return False
    if isinstance(e, (c_ast.ID, c_ast.ArrayRef, c_ast.StructRef)) or \
            isinstance(e, c_ast.UnaryOp) and e.op == '*':
        try:
            if f.expr_type(e).volatile:
                return False
        except CError:
            return False
    return all(_pure(c, f) for _, c in e.children() if not isinstance(c, c_ast.Typename))


def _value_type(e, f):
    """the type of the value an expression holds before the promotions: a char variable,
    a char assignment ((c = getchar()) is a char)"""
    try:
        if isinstance(e, c_ast.Cast):
            return f.decl_type(e.to_type)
        if isinstance(e, (c_ast.ID, c_ast.Assignment, c_ast.ArrayRef, c_ast.StructRef)) or \
                (isinstance(e, c_ast.UnaryOp) and e.op == '*'):
            t = f.expr_type(e)
            return t if t.is_int else None
    except CError:
        return None
    return None


def _q(name):
    return f"'{name}'" if name else '(through a pointer)'


# the format argument's index of the printf and scanf functions (-Wformat)
# the format's argument of every printf and scanf (the v ones too)
FMT_ARG = {'printf': 0, 'fprintf': 1, 'sprintf': 1, 'snprintf': 2, 'vprintf': 0,
           'vfprintf': 1, 'vsprintf': 1, 'vsnprintf': 2, 'scanf': 0, 'fscanf': 1,
           'sscanf': 1, 'vscanf': 0, 'vfscanf': 1, 'vsscanf': 1}
FORMATS = {'printf': 0, 'fprintf': 1, 'sprintf': 1, 'snprintf': 2, 'dprintf': 1,
           'cprintf': 0, 'scanf': 0, 'fscanf': 1, 'sscanf': 1}
_PRINTF_CONV = re.compile(r"%(?P<flags>[-+ #0']*)(?P<width>\*|\d+)?(?:\.(?P<prec>\*|\d*))?"
                          r"(?P<len>hh|h|ll|l|L|z|j|t|q)?(?P<conv>[diouxXcsfFeEgGaApn%])")
_SCANF_CONV = re.compile(r"%(?P<supp>\*)?(?P<width>\d+)?(?P<len>hh|h|ll|l|L|z|j|t|q)?"
                         r"(?P<conv>\[\^?\]?[^\]]*\]|[diouxXcsfFeEgGaApn%])")
