"""Front end: pycparser AST -> IR (ir.py), with types, constant folding and the
Horizon memory model:

  * every data pointer is a 16-bit offset in the code bank (DBR); __far pointers are
    32 bits (offset, bank, 0) and are read with [dp],y;
  * a local scalar whose address is never taken is a virtual register (the register
    allocator puts it in the direct page or in a hardware-stack slot);
  * arrays, structures and address-taken locals live in the function's frame on the
    software stack (code bank, pointer __sp in the direct page): &local is a near pointer.
"""
from pycparser import c_ast

from .ctypes816 import (CError, Unsupported, T, VoidT, IntT, PtrT, ArrT, StructT, FuncT,
                        Field, VOID, BOOL, CHAR, SCHAR, UCHAR, SHORT, USHORT, INT, UINT,
                        LONG, ULONG, promote, arith_conv, same)
from .ir import V, Imm, Sym, Frame, FrameSlot, Ins, Block, Func

FAR_QUAL = '_Atomic'      # the preprocessor maps __far to _Atomic (pycparser knows it)


class RV:
    """an rvalue: operand + type. For a structure: the operand is its address."""
    __slots__ = ('op', 't')

    def __init__(self, op, t):
        self.op = op
        self.t = t

    def __repr__(self): return f'RV({self.op!r}:{self.t!r})'


class LV:
    """an lvalue: kind 'reg' (op = V) or 'mem' (base, idx, off); bit-fields: fld"""
    __slots__ = ('kind', 'op', 'base', 'idx', 'off', 't', 'fld', 'vol', 'post')

    def __init__(self, kind, t, op=None, base=None, idx=None, off=0, fld=None):
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
    __slots__ = ('kind', 't', 'v', 'asm', 'slot', 'base')

    def __init__(self, kind, t, v=None, asm=None, slot=None, base=None):
        self.kind = kind     # 'global' 'reg' 'mem' 'enum' 'typedef'
        self.t = t
        self.v = v           # V (reg) / value (enum)
        self.asm = asm       # assembler name (global)
        self.slot = slot     # FrameSlot (mem)
        self.base = base     # address operand of a memory object (Frame / V for a struct param)


class DataObj:
    def __init__(self, name, section, items, size, export):
        self.name = name
        self.section = section   # 'DATA' 'RODATA' 'BSS'
        self.items = items       # list of ('b', bytes) / ('w', sym, off) / ('f', sym, off)
        self.size = size
        self.export = export


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


class Front:
    def __init__(self, filename='?'):
        self.unit = Unit()
        self.scopes = [{}]
        self.tags = [{}]
        self.strings = {}
        self.nstatic = 0
        self.fn = None
        self.filename = filename
        self.global_types = {}
        self.in_params = False
        self.nlit = 0

    # ------------------------------------------------------------------ errors
    def err(self, msg, node=None):
        raise CError(msg, getattr(node, 'coord', None))

    def unsup(self, msg, node=None):
        raise Unsupported(msg, getattr(node, 'coord', None))

    def warn(self, msg, node=None):
        self.unit.warnings.append(f'{getattr(node, "coord", "")}: warning: {msg}')

    # ------------------------------------------------------------------ scopes
    def push(self):
        self.scopes.append({})
        self.tags.append({})

    def pop(self):
        self.scopes.pop()
        self.tags.pop()

    def lookup(self, name):
        for s in reversed(self.scopes):
            if name in s:
                return s[name]
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
                self.unsup('floating point (float/double) is not supported', node)
            if longs >= 2:
                return LLONG_U if 'unsigned' in s else LLONG
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
            self.err(f'unknown type {" ".join(names)}', node)
        if isinstance(node, (c_ast.Struct, c_ast.Union)):
            return self.struct_type(node)
        if isinstance(node, c_ast.Enum):
            return self.enum_type(node)
        if isinstance(node, c_ast.TypeOf):
            return self.typeof(node.expr)
        self.unsup(f'type {type(node).__name__}', node)

    def struct_type(self, node):
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
            if st is None or st.complete:
                st = StructT(node.name, union)
                self.tags[-1][node.name] = st
        else:
            st = StructT(None, union)
        fields = []
        off = 0
        size = 0
        bitunit = None     # (offset, size, used bits)
        for d in node.decls:
            if isinstance(d, c_ast.StaticAssert):
                continue
            t = self.decl_type(d.type)
            if d.bitsize is not None:
                w = self.const_int(d.bitsize)
                if not t.is_int:
                    self.err('bit-field of a non-integer type', d)
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
            if t.is_arr and t.n is None:
                t = ArrT(t.elem, 0)      # flexible array member
            if not t.is_arr and t.size == 0 and not t.is_struct:
                self.err('incomplete field type', d)
            if t.is_struct and not t.complete:
                self.err(f'incomplete field type {t!r}', d)
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
        return st

    def enum_type(self, node):
        if node.values:
            val = 0
            neg = False
            for e in node.values.enumerators:
                if e.value is not None:
                    val = self.const_int(e.value)
                neg = neg or val < 0
                self.bind(e.name, Sy('enum', INT, v=val))
                val += 1
            t = INT if neg else UINT
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
            return t.qual('const' in q, 'volatile' in q, FAR_QUAL in q)
        if isinstance(node, c_ast.PtrDecl):
            to = self.decl_type(node.type)
            q = node.quals or []
            p = PtrT(to)
            return p.qual('const' in q, 'volatile' in q, FAR_QUAL in q)
        if isinstance(node, c_ast.ArrayDecl):
            el = self.decl_type(node.type)
            n = None
            if node.dim is not None:
                if isinstance(node.dim, c_ast.ID) and node.dim.name == '*':
                    return ArrT(el, None)
                n = self.const_eval(node.dim)
                if n is None:
                    if self.in_params:
                        return ArrT(el, None)
                    self.unsup('variable-length array', node)
            return ArrT(el, n)
        if isinstance(node, c_ast.FuncDecl):
            ret = self.decl_type(node.type)
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
            v = self.const_eval(e.expr)
            if v is None:
                return None
            t = self.expr_type(e)
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
            ct = arith_conv(self.expr_type(e.left), self.expr_type(e.right))
            if e.op in ('<', '>', '<=', '>=', '==', '!='):
                a, b = self.wrap(a, ct), self.wrap(b, ct)
            elif e.op in ('/', '%', '>>'):
                a = self.wrap(a, ct if e.op != '>>' else lt)
                b = self.wrap(b, ct) if e.op != '>>' else b
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
            return self.wrap(r, t)
        if isinstance(e, c_ast.TernaryOp):
            c = self.const_eval(e.cond)
            if c is None:
                return None
            return self.const_eval(e.iftrue if c else e.iffalse)
        if isinstance(e, c_ast.Cast):
            v = self.const_eval(e.expr)
            t = self.decl_type(e.to_type)
            if v is None or not (t.is_int or t.is_ptr):
                return None
            return self.wrap(v, t)
        return None

    def wrap(self, v, t):
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
        if e.type == 'char' or s.startswith("'") or s[:2] in ("L'", "u'", "U'"):
            if s[0] != "'":
                s = s[1:]
            b = unescape(s[1:-1])
            v = b[0] if len(b) == 1 else int.from_bytes(bytes(b[:2]), 'big')
            return (v - 256 if v > 127 and len(b) == 1 and False else v), INT
        if e.type == 'string':
            return None, None
        if e.type in ('float', 'double') or ('.' in s and not s.lower().startswith('0x')) or \
                (('e' in s.lower()) and not s.lower().startswith('0x')):
            self.unsup('floating point constant', e)
        t = s.lower()
        suf = ''
        while t and t[-1] in 'ul':
            suf = t[-1] + suf
            t = t[:-1]
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
        if 'll' in suf:
            self.unsup('long long is not supported (a long long constant)', e)
        u = 'u' in suf
        lng = 'l' in suf
        if not lng and not u and v <= 0x7FFF:
            return v, INT
        if not lng and (u or not dec) and v <= 0xFFFF:
            return v, UINT
        if not u and v <= 0x7FFFFFFF:
            return v, LONG
        if v <= 0xFFFFFFFF:
            return v, ULONG
        self.unsup('integer constant too large for 32 bits', e)

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
    def expr_type(self, e):
        """the type of an expression without generating code"""
        if isinstance(e, c_ast.Constant):
            if e.type == 'string':
                return ArrT(CHAR, len(self.strbytes(e)) + 1)
            return self.constant(e)[1]
        if isinstance(e, c_ast.ID):
            s = self.lookup(e.name)
            if s is None:
                if e.name == '__func__':
                    return ArrT(CHAR, len(self.fn.name) + 1 if self.fn else 1)
                self.err(f'undeclared identifier {e.name}', e)
            return s.t
        if isinstance(e, c_ast.Cast):
            return self.decl_type(e.to_type)
        if isinstance(e, c_ast.UnaryOp):
            if e.op in ('sizeof', '_Alignof'):
                return UINT
            t = self.expr_type(e.expr)
            if e.op == '&':
                return PtrT(t)
            if e.op == '*':
                t = decay(t)
                if t.is_ptr:
                    return t.to
                if t.is_func:
                    return t
                self.err('dereferencing a non-pointer', e)
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
            return arith_conv(lt, rt)
        if isinstance(e, c_ast.Assignment):
            return self.expr_type(e.lvalue).unqual()
        if isinstance(e, c_ast.TernaryOp):
            a = decay(self.expr_type(e.iftrue))
            b = decay(self.expr_type(e.iffalse))
            if a.is_int and b.is_int:
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
            self.err('subscript of a non-array', e)
        if isinstance(e, c_ast.StructRef):
            t = self.expr_type(e.name)
            if e.type == '->':
                t = decay(t)
                if not t.is_ptr:
                    self.err('-> on a non-pointer', e)
                t = t.to
            if not t.is_struct or not t.complete:
                self.err(f'member of a non-structure ({t!r})', e)
            f = t.field(e.field.name)
            if not f:
                self.err(f'no member {e.field.name} in {t!r}', e)
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
            self.unsup('statement expressions (GNU)', e)
        self.unsup(f'expression {type(e).__name__}', e)

    # ------------------------------------------------------------------ strings
    def strbytes(self, e):
        s = e.value
        out = []
        # adjacent literals are concatenated by pycparser into one value "a" "b" -> "ab"
        i = 0
        parts = []
        while i < len(s):
            if s[i] in 'LuU8':
                i += 1
                continue
            if s[i] == '"':
                j = i + 1
                while s[j] != '"':
                    j += 2 if s[j] == '\\' else 1
                parts.append(s[i + 1:j])
                i = j + 1
            else:
                i += 1
        for p in parts:
            out += unescape(p)
        return out

    def string_sym(self, e):
        b = bytes(self.strbytes(e)) + b'\0'
        if b not in self.strings:
            name = f'L_S{len(self.strings)}'
            self.strings[b] = name
            self.unit.data.append(DataObj(name, 'RODATA', [('b', list(b))], len(b), False))
        return self.strings[b]

    # ================================================================== top level
    def translate(self, ast):
        for ext in ast.ext:
            if isinstance(ext, c_ast.FuncDef):
                self.funcdef(ext)
            elif isinstance(ext, c_ast.Decl):
                self.global_decl(ext)
            elif isinstance(ext, c_ast.Typedef):
                self.typedef(ext)
            elif isinstance(ext, (c_ast.Pragma, c_ast.StaticAssert)):
                pass
            else:
                self.unsup(f'top-level {type(ext).__name__}', ext)
        u = self.unit
        u.externs -= u.defined
        return u

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
        if not t.is_func:
            _check_ll(t, d, self)
        if t.is_func:
            if prev is None or prev.kind != 'global':
                self.bind(d.name, Sy('global', t, asm=asm))
            elif not prev.t.proto and t.proto:
                prev.t = t
            if 'static' not in st:
                self.unit.externs.add(asm)
            return
        if t.is_arr and t.n is None and d.init is not None:
            t = ArrT(t.elem, self.init_count(t, d.init))
        if prev is not None and prev.kind == 'global' and prev.t.is_arr and t.is_arr and t.n is None:
            t = prev.t
        sy = Sy('global', t, asm=asm)
        self.bind(d.name, sy)
        if 'extern' in st and d.init is None:
            self.unit.externs.add(asm)
            return
        if 'typedef' in st:
            return
        export = 'static' not in st
        self.define_data(asm, t, d.init, export, d)

    def define_data(self, asm, t, init, export, node):
        if asm in self.unit.defined:
            # a tentative definition followed by a real one: keep the one with data
            if init is None:
                return
            self.unit.data = [o for o in self.unit.data if o.name != asm]
        self.unit.defined.add(asm)
        if export:
            self.unit.exports.add(asm)
        if t.is_arr and t.n is None:
            t = ArrT(t.elem, 1)
        if init is None:
            self.unit.data.append(DataObj(asm, 'BSS', [], t.size, export))
            return
        img = Image(t.size)
        self.static_init(img, 0, t, init)
        sec = 'RODATA' if t.const and not _has_nonconst_inner(t) else 'DATA'
        self.unit.data.append(DataObj(asm, sec, img.items(), t.size, export))

    def init_count(self, t, init):
        if isinstance(init, c_ast.Constant) and init.type == 'string':
            return len(self.strbytes(init)) + 1
        if isinstance(init, c_ast.InitList):
            if len(init.exprs) == 1 and isinstance(init.exprs[0], c_ast.Constant) and \
                    init.exprs[0].type == 'string' and t.elem.is_int and t.elem.size == 1:
                return len(self.strbytes(init.exprs[0])) + 1
            mx = [-1]

            def cb(off, et, e, fld):
                mx[0] = max(mx[0], off)
            self.list_init(init.exprs, 0, cb, 0, ArrT(t.elem, None), static=False)
            es = t.elem.size or 1
            return mx[0] // es + 1 if mx[0] >= 0 else 0
        self.err('array size from an initialiser of this kind', init)

    # --- static initialisers -> byte image with relocations
    def static_init(self, img, off, t, init):
        if t.is_arr:
            if isinstance(init, c_ast.Constant) and init.type == 'string' or \
                    (isinstance(init, c_ast.InitList) and len(init.exprs) == 1 and
                     isinstance(init.exprs[0], c_ast.Constant) and init.exprs[0].type == 'string'
                     and t.elem.is_int and t.elem.size == 1):
                if isinstance(init, c_ast.InitList):
                    init = init.exprs[0]
                b = self.strbytes(init)
                n = t.n if t.n is not None else len(b) + 1
                for i, c in enumerate(b[:n]):
                    img.byte(off + i, c)
                return
            if not isinstance(init, c_ast.InitList):
                self.err('array initialiser must be a list', init)
            self.list_init(init.exprs, 0, img, off, t, static=True)
            return
        if t.is_struct:
            if isinstance(init, c_ast.InitList):
                self.list_init(init.exprs, 0, img, off, t, static=True)
                return
            self.unsup('structure initialised from an expression (static)', init)
        if isinstance(init, c_ast.InitList):
            if not init.exprs:
                return
            init = init.exprs[0]
        self.static_scalar(img, off, t, init)

    def static_scalar(self, img, off, t, e):
        v = self.const_eval(e)
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
            self.err('initialiser is not a constant', e)
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
        if isinstance(e, c_ast.CompoundLiteral) and self.fn is None:
            t = self.decl_type(e.type)
            if t.is_arr:
                return self.static_literal(e), 0
        if isinstance(e, c_ast.BinaryOp) and e.op in ('+', '-'):
            a = self.addr_const(e.left)
            if a is not None:
                k = self.const_eval(e.right)
                if k is None:
                    return None
                t = decay(self.expr_type(e.left))
                sz = t.to.size if t.is_ptr and not t.to.is_void else 1
                return a[0], a[1] + (k * sz if e.op == '+' else -k * sz)
            if e.op == '+':
                a = self.addr_const(e.right)
                k = self.const_eval(e.left)
                if a is not None and k is not None:
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
            if a is None or k is None:
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

    def list_init(self, exprs, i, img, off, t, static):
        """initialise an aggregate t at off from exprs[i:], with brace elision.
        Returns the index of the first unused expression. Static: into img; otherwise
        img is a callback store(off, type, expr)."""
        if t.is_arr:
            n = t.n
            k = 0
            while i < len(exprs) and (n is None or k < n or isinstance(exprs[i], c_ast.NamedInitializer)):
                x = exprs[i]
                if isinstance(x, c_ast.NamedInitializer):
                    d = x.name[0]
                    if not isinstance(d, c_ast.ArrayDesignator):
                        return i
                    k = self.const_int(d.expr)
                    if len(x.name) > 1:
                        sub = c_ast.InitList([c_ast.NamedInitializer(x.name[1:], x.expr)])
                        self.init_one(img, off + k * t.elem.size, t.elem, sub, static)
                    else:
                        self.init_one(img, off + k * t.elem.size, t.elem, x.expr, static)
                    i += 1
                    k += 1
                    continue
                i = self.init_elem(exprs, i, img, off + k * t.elem.size, t.elem, static)
                k += 1
            return i
        if t.is_struct:
            fields = [f for f in t.fields if f.name is not None or f.type.is_struct]
            k = 0
            while i < len(exprs) and (k < len(fields) or isinstance(exprs[i], c_ast.NamedInitializer)):
                x = exprs[i]
                if isinstance(x, c_ast.NamedInitializer):
                    d = x.name[0]
                    if isinstance(d, c_ast.ID):
                        names = [f.name for f in fields]
                        if d.name not in names:
                            # an anonymous member's field
                            r = t.field(d.name)
                            if not r:
                                self.err(f'no member {d.name}', x)
                            f = r[0]
                            self.init_field(img, off + r[1] - f.offset, f, x.expr if len(x.name) == 1 else
                                            c_ast.InitList([c_ast.NamedInitializer(x.name[1:], x.expr)]), static)
                            i += 1
                            continue
                        k = names.index(d.name)
                        f = fields[k]
                        sub = x.expr if len(x.name) == 1 else c_ast.InitList([c_ast.NamedInitializer(x.name[1:], x.expr)])
                        self.init_field(img, off, f, sub, static)
                        i += 1
                        k += 1
                        if t.union:
                            return i
                        continue
                    return i
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
            img.bits(off + f.offset, f.type.size, f.bitpos, f.bits, v)
        else:
            img(off, None, e, f)

    def init_elem(self, exprs, i, img, off, t, static):
        x = exprs[i]
        if (t.is_arr or t.is_struct) and not isinstance(x, c_ast.InitList):
            if t.is_arr and isinstance(x, c_ast.Constant) and x.type == 'string':
                self.init_one(img, off, t, x, static)
                return i + 1
            if t.is_struct and not static and same(self.expr_type(x), t):
                self.init_one(img, off, t, x, static)
                return i + 1
            return self.list_init(exprs, i, img, off, t, static)
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
        ft = self.decl_type(d.type)
        if fd.param_decls:      # K&R definitions
            kr = {}
            for p in fd.param_decls:
                kr[p.name] = self.param_adjust(self.decl_type(p.type))
            ft.params = [(n, kr.get(n, INT)) for n, _ in ft.params]
        name = d.name
        static = 'static' in (d.storage or [])
        asm = mangle(name)
        prev = self.scopes[0].get(name)
        if prev is not None and prev.kind == 'global' and prev.t.is_func and 'static' not in (d.storage or []):
            pass
        self.bind(name, Sy('global', ft, asm=asm))
        self.unit.defined.add(asm)
        if not static:
            self.unit.exports.add(asm)
        f = Func(asm, static)
        f.ctype = ft
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
        _check_ll(ft.ret, fd, self)
        for pname, pt in ft.params:
            _check_ll(pt, fd, self)
            if pt.is_struct:
                v = f.newv(2, (pname or 'p'))
                v.param = argoff
                argoff += 2
                f.params.append(v)
                if pname:
                    self.bind(pname, Sy('mem', pt, base=v))
                continue
            size = 4 if pt.size == 4 else 2
            v = f.newv(size, pname or 'p')
            v.param = argoff
            argoff += size
            f.params.append(v)
            if pname is None:
                continue
            if pname in self.addr_taken or pt.volatile:
                slot = self.new_slot(pname, pt.size)
                self.store(Frame(slot), None, 0, pt, v)
                self.bind(pname, Sy('mem', pt, slot=slot, base=Frame(slot)))
            else:
                if pt.is_int and pt.size == 1:
                    # a char argument comes as an int: make it a valid char value
                    self.emit(Ins('x8s' if pt.signed else 'x8u', v, v))
                self.bind(pname, Sy('reg', pt, v=v))
        f.argsize = argoff
        self.compound(fd.body, newscope=False)
        if self.cur is not None and not (self.cur.term):
            if name == 'main':
                self.emit(Ins('ret', a=Imm(0)))
            else:
                self.emit(Ins('ret', a=Imm(0, 4 if ft.ret.size == 4 else 2) if not ft.ret.is_void and not ft.ret.is_struct else None))
        self.pop()
        for lname, (blk, defined) in self.labels.items():
            if not defined:
                self.err(f'label {lname} used but not defined', fd)
        f.blocks = [b for b in f.blocks]
        self.unit.funcs.append(f)
        self.fn = None

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
            self.stmt(s)
        if newscope:
            self.pop()

    def stmt(self, s):
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
        pass

    def st_StaticAssert(self, s):
        pass

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
        if not t.is_func:
            _check_ll(t, d, self)
        if t.is_func or 'extern' in st:
            g = self.scopes[0].get(d.name)
            if g is not None and g.kind == 'global':
                self.bind(d.name, g)
            else:
                asm = mangle(d.name)
                self.bind(d.name, Sy('global', t, asm=asm))
                self.unit.externs.add(asm)
            return
        if t.is_arr and t.n is None:
            if d.init is None:
                self.err('array of unknown size', d)
            t = ArrT(t.elem, self.init_count(t, d.init))
        if 'static' in st:
            self.nstatic += 1
            asm = f'{self.fn.name}__{d.name}_{self.nstatic}'
            self.bind(d.name, Sy('global', t, asm=asm))
            self.define_data(asm, t, d.init, False, d)
            return
        if t.is_struct and not t.complete:
            self.err(f'variable of incomplete type {t!r}', d)
        if t.is_arr or t.is_struct or d.name in self.addr_taken or t.volatile:
            slot = self.new_slot(d.name, t.size)
            sy = Sy('mem', t, slot=slot, base=Frame(slot))
            self.bind(d.name, sy)
            if d.init is not None:
                self.local_init(Frame(slot), t, d.init)
            return
        v = self.newv(4 if t.size == 4 else 2, d.name)
        self.bind(d.name, Sy('reg', t, v=v))
        if d.init is not None:
            init = d.init
            if isinstance(init, c_ast.InitList):
                init = init.exprs[0]
            self.assign_to(LV('reg', t, op=v), init)

    def local_init(self, base, t, init):
        if t.is_arr or (t.is_struct and isinstance(init, c_ast.InitList)):
            if t.is_arr and t.elem.size == 1 and (
                    (isinstance(init, c_ast.Constant) and init.type == 'string') or
                    (isinstance(init, c_ast.InitList) and len(init.exprs) == 1 and
                     isinstance(init.exprs[0], c_ast.Constant) and init.exprs[0].type == 'string')):
                s = init if isinstance(init, c_ast.Constant) else init.exprs[0]
                b = self.strbytes(s)
                n = min(len(b) + 1, t.n)
                sym = self.string_sym(s)
                self.emit(Ins('copy', a=Sym(sym), b=base, n=n))
                if t.n > n:
                    self.emit(Ins('zero', a=_addoff(base, n), n=t.n - n))
                return
            if not isinstance(init, c_ast.InitList):
                self.err('aggregate initialiser must be a list', init)
            self.emit(Ins('zero', a=base, n=t.size))

            def store(off, et, e, fld):
                if fld is not None:
                    lv = LV('mem', fld.type, base=base, off=off + fld.offset, fld=fld)
                    self.assign_to(lv, e)
                    return
                if isinstance(e, c_ast.InitList):
                    if et.is_arr or et.is_struct:
                        self.list_init(e.exprs, 0, store, off, et, static=False)
                        return
                    e = e.exprs[0] if e.exprs else c_ast.Constant('int', '0')
                if et.is_arr:
                    s = e
                    b = self.strbytes(s)
                    n = min(len(b) + 1, et.n)
                    self.emit(Ins('copy', a=Sym(self.string_sym(s)), b=_addoff(base, off), n=n))
                    return
                lv = LV('mem', et, base=base, off=off)
                v = self.const_eval(e)
                if v is not None and v == 0 and et.is_scalar:
                    return
                self.assign_to(lv, e)
            self.list_init(init.exprs, 0, store, 0, t, static=False)
            return
        if isinstance(init, c_ast.InitList):
            init = init.exprs[0]
        self.assign_to(LV('mem', t, base=base, off=0), init)

    def st_If(self, s):
        c = self.const_eval(s.cond)
        if c is not None:
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
            self.err('break outside a loop or switch', s)
        self.jump(self.brk[-1])

    def st_Continue(self, s):
        if not self.cont:
            self.err('continue outside a loop', s)
        self.jump(self.cont[-1])

    def st_Return(self, s):
        ft = self.fn.ctype
        if s.expr is None:
            self.emit(Ins('ret', a=None))
            return
        rt = ft.ret
        if rt.is_void:
            self.rv(s.expr)
            self.emit(Ins('ret', a=None))
            return
        if rt.is_struct:
            v = self.rv(s.expr)
            self.emit(Ins('copy', a=v.op, b=self.sret, n=rt.size))
            self.emit(Ins('ret', a=self.sret))
            return
        v = self.convert(self.rv(s.expr), rt)
        self.emit(Ins('ret', a=v.op))

    def st_Label(self, s):
        b = self.label_block(s.name)
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
        self.jump(b)

    def st_Switch(self, s):
        v = self.convert(self.rv(s.cond), promote(self.expr_type(s.cond)))
        t = v.t
        val = v.op
        if isinstance(val, V):
            pass
        else:
            nv = self.newv(t.size if t.size == 4 else 2)
            self.emit(Ins('mov', nv, val))
            val = nv
        sw = Ins('sw', a=val, cases=[], default=None, signed=t.signed)
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
            self.err('case outside a switch', s)
        sw, t = self.switches[-1]
        k = self.wrap(self.const_int(s.expr), t)
        b = self.mkblock('case')
        sw.x['cases'].append((k & ((1 << (8 * t.size)) - 1), b))
        self.place(b)
        for x in s.stmts or []:
            self.stmt(x)

    def st_Default(self, s):
        sw, t = self.switches[-1]
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
            return RV(r.op, PtrT(t.elem))
        if t.is_func:
            return RV(r.op, PtrT(t))
        return r

    def rv_nodecay(self, e, dst=None):
        m = getattr(self, 'ex_' + type(e).__name__, None)
        if isinstance(e, c_ast.Compound):
            self.unsup('statement expressions (GNU)', e)
        if m is None:
            self.unsup(f'expression {type(e).__name__}', e)
        return m(e, dst)

    def to_dst(self, r, dst):
        if dst is not None and r.op is not dst:
            self.emit(Ins('mov', dst, r.op))
            return RV(dst, r.t)
        return r

    def ex_Constant(self, e, dst):
        if e.type == 'string':
            sym = self.string_sym(e)
            return RV(Sym(sym), ArrT(CHAR, len(self.strbytes(e)) + 1))
        v, t = self.constant(e)
        return self.to_dst(RV(Imm(v, t.size), t), dst)

    def ex_ID(self, e, dst):
        s = self.lookup(e.name)
        if s is None:
            if e.name == '__func__':
                return self.ex_Constant(c_ast.Constant('string', '"' + self.fn.cname + '"'), dst)
            self.err(f'undeclared identifier {e.name}', e)
        if s.kind == 'enum':
            return self.to_dst(RV(Imm(s.v), INT), dst)
        if s.kind == 'global':
            self.unit.externs.add(s.asm)
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
                self.err(f'undeclared identifier {e.name}', e)
            if s.kind == 'reg':
                return LV('reg', s.t, op=s.v)
            if s.kind == 'mem':
                return LV('mem', s.t, base=s.base, off=0)
            if s.kind == 'global':
                self.unit.externs.add(s.asm)
                return LV('mem', s.t, base=Sym(s.asm), off=0)
            self.err(f'{e.name} is not an lvalue', e)
        if isinstance(e, c_ast.UnaryOp) and e.op == '*':
            x = e.expr
            if isinstance(x, c_ast.UnaryOp) and x.op in ('p++', 'p--') and isinstance(x.expr, c_ast.ID):
                s = self.lookup(x.expr.name)
                if s is not None and s.kind == 'reg' and s.t.is_ptr and not s.t.isfar and \
                        s.t.to.is_scalar and s.t.to.size in (1, 2, 4):
                    # *p++: access through p, then step p (no copy of the old pointer)
                    lv = LV('mem', s.t.to, base=s.v, off=0)
                    lv.post = (s.v, s.t.to.size if x.op == 'p++' else -s.t.to.size)
                    return lv
            p = self.rv(e.expr)
            if not p.t.is_ptr:
                self.err('dereferencing a non-pointer', e)
            return self.mem_at(p.op, p.t.to, p.t.isfar)
        if isinstance(e, c_ast.ArrayRef):
            return self.subscript(e)
        if isinstance(e, c_ast.StructRef):
            if e.type == '->':
                p = self.rv(e.name)
                if not p.t.is_ptr or not p.t.to.is_struct:
                    self.err('-> needs a pointer to a structure', e)
                base = self.mem_at(p.op, p.t.to, p.t.isfar)
                st = p.t.to
            else:
                base = self.lval_or_struct(e.name)
                st = base.t
            if not st.is_struct or not st.complete:
                self.err('member of a non-structure', e)
            r = st.field(e.field.name)
            if not r:
                self.err(f'no member {e.field.name} in {st!r}', e)
            f, foff = r
            ft = f.type.qual(st.const, st.volatile)
            lv = LV('mem', ft, base=base.base, idx=base.idx, off=base.off + foff,
                    fld=f if f.bits is not None else None)
            lv.vol = lv.vol or base.vol
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
            return LV('mem', ArrT(CHAR, len(self.strbytes(e)) + 1), base=Sym(self.string_sym(e)), off=0)
        if isinstance(e, c_ast.FuncCall) or isinstance(e, c_ast.Assignment) or \
                isinstance(e, c_ast.TernaryOp) or isinstance(e, c_ast.ExprList):
            r = self.rv_nodecay(e)
            if r.t.is_struct:
                return self.mem_at(r.op, r.t, False)
        self.err('not an lvalue', e)

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
            self.err('subscript of a non-array', e)
        el = at.to
        size = el.size if not el.is_void else 1
        # constant part of the index: a[i + 3] -> base + i*size, offset 3*size
        koff = 0
        while isinstance(idx, c_ast.BinaryOp) and idx.op in ('+', '-') and self.const_eval(idx.right) is not None:
            k = self.const_eval(idx.right)
            koff += k if idx.op == '+' else -k
            idx = idx.left
        kv = self.const_eval(idx)
        # the base address
        if isinstance(arr, c_ast.ID) and self.lookup(arr.name) and self.lookup(arr.name).t.is_arr:
            base = self.lval(arr)
        else:
            p = self.rv(arr)
            base = self.mem_at(p.op, el, p.t.isfar)
        if kv is not None:
            return LV('mem', el, base=base.base, idx=base.idx, off=base.off + (kv + koff) * size)
        iv = self.convert(self.rv(idx), INT if self.expr_type(idx).signed else UINT)
        sc = self.scale(iv.op, size)
        if base.idx is not None:
            nv = self.newv(2)
            self.emit(Ins('add', nv, base.idx, sc))
            sc = nv
        if isinstance(base.base, V) and base.base.size == 4:
            # far pointer + index
            z = self.newv(4)
            self.emit(Ins('sx' if iv.t.signed else 'zx', z, sc))
            nv = self.newv(4)
            self.emit(Ins('add', nv, base.base, z))
            return LV('mem', el, base=nv, off=base.off + koff * size)
        return LV('mem', el, base=base.base, idx=sc, off=base.off + koff * size)

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
            self.emit(Ins('add', v, v, Imm(k & 0xFFFF)))
            lv.post = None

    def load(self, lv, dst=None, final=True):
        r = self.load1(lv, dst)
        if final:
            self.finish(lv)
        return r

    def load1(self, lv, dst=None):
        t = lv.t
        if lv.kind == 'reg':
            return self.to_dst(RV(lv.op, t), dst)
        if t.is_arr or t.is_struct or t.is_func:
            return RV(self.addr_of(lv), t)
        if lv.fld is not None:
            return self.load_bits(lv, dst)
        size = t.size
        d = dst if dst is not None and dst.size == (4 if size == 4 else 2) else self.newv(4 if size == 4 else 2)
        self.emit(Ins('ld', d, base=lv.base, idx=lv.idx, off=lv.off, sz=size,
                      sgn=t.is_int and t.signed, vol=lv.vol))
        return self.to_dst(RV(d, t), dst)

    def store(self, base, idx, off, t, val, vol=False):
        self.emit(Ins('st', a=val, base=base, idx=idx, off=off, sz=t.size, vol=vol))

    def load_bits(self, lv, dst):
        f = lv.fld
        ut = UINT if f.type.size <= 2 else ULONG
        sz = f.type.size
        w = self.newv(4 if sz == 4 else 2)
        self.emit(Ins('ld', w, base=lv.base, idx=lv.idx, off=lv.off, sz=sz, sgn=False, vol=lv.vol))
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
        self.emit(Ins('ld', w, base=lv.base, idx=lv.idx, off=lv.off, sz=sz, sgn=False, vol=lv.vol))
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
        self.emit(Ins('st', a=o, base=lv.base, idx=lv.idx, off=lv.off, sz=sz, vol=lv.vol))

    def conv_op(self, r, size):
        """operand of r resized to size bytes (2/4) by its type"""
        if r.op.size == size:
            return r.op
        return self.convert(r, ULONG if size == 4 else UINT).op

    def addr_of(self, lv):
        if lv.kind == 'reg':
            self.err('address of a register variable')
        base, idx, off = lv.base, lv.idx, lv.off
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

    def assign_to(self, lv, e):
        """lv = e; returns the RV stored"""
        t = lv.t
        if t.is_struct:
            src = self.rv_nodecay(e)
            if not src.t.is_struct:
                self.err('assigning a non-structure to a structure', e)
            self.emit(Ins('copy', a=src.op, b=self.addr_of(lv), n=t.size))
            return RV(self.addr_of(lv), t)
        if lv.kind == 'reg':
            r = self.rv(e, dst=lv.op if not (t.is_int and t.size == 1) else None)
            r = self.convert(r, t.unqual(), dst=lv.op)
            return r
        r = self.convert(self.rv(e), t.unqual())
        if lv.fld is not None:
            self.store_bits(lv, r)
            return r
        self.store(lv.base, lv.idx, lv.off, t, r.op, lv.vol)
        self.finish(lv)
        return r

    def ex_Assignment(self, e, dst):
        return self.assignment(e, want=True, dst=dst)

    def assignment(self, e, want, dst=None):
        lv = self.lval(e.lvalue)
        if lv.t.const and False:
            self.warn('assignment to const', e)
        if e.op == '=':
            r = self.assign_to(lv, e.rvalue)
            return self.to_dst(RV(r.op, lv.t.unqual()), dst) if want else None
        op = e.op[:-1]
        # compound: lv = lv op rhs (lv evaluated once)
        cur = self.load(lv, final=False)
        rhs = self.rv(e.rvalue)
        target = lv.op if lv.kind == 'reg' and not (lv.t.is_int and lv.t.size == 1) else None
        if lv.t.is_ptr and op in ('+', '-'):
            res = self.ptr_arith(op, cur, rhs, dst=target)
        else:
            at = arith_conv(cur.t, rhs.t) if op not in ('<<', '>>') else promote(cur.t)
            same_size = target is not None and (4 if at.size == 4 else 2) == target.size
            res = self.arith(op, cur, rhs, e, dst=target if same_size else None)
            res = self.convert(res, lv.t.unqual(), dst=target)
        if lv.kind == 'reg':
            if res.op is not lv.op:
                res = self.convert(res, lv.t.unqual(), dst=lv.op)
        elif lv.fld is not None:
            self.store_bits(lv, res)
        else:
            res = self.convert(res, lv.t.unqual())
            self.store(lv.base, lv.idx, lv.off, lv.t, res.op, lv.vol)
            self.finish(lv)
        return self.to_dst(RV(res.op, lv.t.unqual()), dst) if want else None

    def incdec(self, e, want, dst=None):
        lv = self.lval(e.expr)
        t = lv.t
        step = t.to.size if t.is_ptr else 1
        if t.is_ptr and t.to.is_void:
            step = 1
        post = e.op.startswith('p')
        op = 'add' if '+' in e.op else 'sub'
        size = 4 if t.size == 4 else 2
        if lv.kind == 'reg':
            old = None
            if want and post:
                old = self.newv(size)
                self.emit(Ins('mov', old, lv.op))
            self.emit(Ins(op, lv.op, lv.op, Imm(step, size)))
            if t.is_int and t.size == 1:
                self.emit(Ins('x8s' if t.signed else 'x8u', lv.op, lv.op))
            if not want:
                return None
            return self.to_dst(RV(old if post else lv.op, t.unqual()), dst)
        cur = self.load(lv, final=False)
        nv = self.newv(size)
        self.emit(Ins(op, nv, cur.op, Imm(step, size)))
        if lv.fld is not None:
            self.store_bits(lv, RV(nv, t))
            if want and not post:
                return self.load(lv, dst)
        else:
            self.store(lv.base, lv.idx, lv.off, t, nv, lv.vol)
            self.finish(lv)
        if not want:
            return None
        if post:
            return self.to_dst(RV(cur.op, promote(t) if t.is_int else t), dst)
        r = RV(nv, t.unqual())
        if t.is_int and t.size == 1:
            r = self.convert(RV(nv, INT), t)
        return self.to_dst(r, dst)

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
            return self.to_dst(RV(self.addr_of(lv), PtrT(t)), dst)
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
                return self.to_dst(RV(Imm(c, t.size), t), dst)
            r = self.convert(self.rv(e.expr), t)
            d = dst if dst is not None and dst.size == r.op.size else self.newv(r.op.size)
            self.emit(Ins('neg' if op == '-' else 'com', d, r.op))
            return self.to_dst(RV(d, t), dst)
        self.unsup(f'unary operator {op}', e)

    def ex_Cast(self, e, dst):
        t = self.decl_type(e.to_type)
        _check_ll(t, e, self)
        if t.is_void:
            self.expr_stmt(e.expr)
            return RV(Imm(0), VOID)
        c = self.const_eval(e)
        if c is not None and (t.is_int or t.is_ptr):
            return self.to_dst(RV(Imm(c, t.size if t.size in (1, 2, 4) else 2), t), dst)
        r = self.rv(e.expr)
        return self.convert(r, t, dst=dst)

    def convert(self, r, t, dst=None):
        """convert RV r to type t (scalar)"""
        st = r.t
        if t.is_void:
            return r
        if t.is_struct or st.is_struct:
            if t.is_struct and st.is_struct:
                return r
            self.err(f'cannot convert {st!r} to {t!r}')
        if t.is_arr:
            t = PtrT(t.elem)
        op = r.op
        tsize = t.size
        if t.is_int and t.is_bool:
            if isinstance(op, Imm):
                return self.to_dst(RV(Imm(1 if op.val else 0), t), dst)
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
        if isinstance(op, Imm):
            v = op.val
            if st.is_int and st.signed and op.size < 4:
                v = self.wrap(v, IntT(op.size, True))
            if t.is_ptr and t.isfar and st.is_ptr and not st.isfar:
                d = dst if dst is not None and dst.size == 4 else self.newv(4)
                self.emit(Ins('mkfar', d, op))
                return self.to_dst(RV(d, t), dst)
            return self.to_dst(RV(Imm(self.wrap(v, t) if t.is_int else v, 4 if tsize == 4 else 2), t), dst)
        if isinstance(op, (Sym, Frame)):
            if t.is_ptr and t.isfar:
                d = dst if dst is not None and dst.size == 4 else self.newv(4)
                self.emit(Ins('mkfar', d, op))
                return self.to_dst(RV(d, t), dst)
            if tsize == 4:
                d = dst if dst is not None and dst.size == 4 else self.newv(4)
                self.emit(Ins('zx', d, op))
                return self.to_dst(RV(d, t), dst)
            if tsize == 1:
                d = dst if dst is not None and dst.size == 2 else self.newv(2)
                self.emit(Ins('x8u', d, op))
                return self.to_dst(RV(d, t), dst)
            return self.to_dst(RV(op, t), dst)
        ssize = op.size
        if t.is_ptr and t.isfar and st.is_ptr and not st.isfar:
            d = dst if dst is not None and dst.size == 4 else self.newv(4)
            self.emit(Ins('mkfar', d, op))
            return self.to_dst(RV(d, t), dst)
        if tsize == 4:
            if ssize == 4:
                return self.to_dst(RV(op, t), dst)
            d = dst if dst is not None and dst.size == 4 else self.newv(4)
            signed = st.is_int and st.signed
            self.emit(Ins('sx' if signed else 'zx', d, op))
            return self.to_dst(RV(d, t), dst)
        if ssize == 4:
            d = dst if dst is not None and dst.size == 2 else self.newv(2)
            self.emit(Ins('tr', d, op))
            op = d
            if tsize == 2:
                return self.to_dst(RV(d, t), dst)
        if tsize == 1:
            if st.is_int and st.size == 1 and st.signed == t.signed:
                return self.to_dst(RV(op, t), dst)
            d = dst if dst is not None and dst.size == 2 else self.newv(2)
            self.emit(Ins('x8s' if t.signed else 'x8u', d, op))
            return self.to_dst(RV(d, t), dst)
        return self.to_dst(RV(op, t), dst)

    def ex_BinaryOp(self, e, dst):
        op = e.op
        c = self.const_eval(e)
        if c is not None:
            t = self.expr_type(e)
            return self.to_dst(RV(Imm(c, t.size), t), dst)
        if op in ('&&', '||', '<', '>', '<=', '>=', '==', '!='):
            return self.bool_value(e, dst)
        lt = decay(self.expr_type(e.left))
        rt = decay(self.expr_type(e.right))
        if op in ('+', '-') and (lt.is_ptr or rt.is_ptr):
            a = self.rv(e.left)
            b = self.rv(e.right)
            return self.ptr_arith(op, a, b, dst)
        a = self.rv(e.left)
        b = self.rv(e.right)
        return self.arith(op, a, b, e, dst)

    def arith(self, op, a, b, node, dst=None):
        if op in ('<<', '>>'):
            t = promote(a.t)
            a = self.convert(a, t)
            b = self.convert(b, UINT)
            irop = 'shl' if op == '<<' else ('sshr' if t.signed else 'ushr')
            return self.binop(irop, a.op, b.op, t, dst)
        if not a.t.is_int or not b.t.is_int:
            self.err(f'invalid operands to {op} ({a.t!r}, {b.t!r})', node)
        t = arith_conv(a.t, b.t)
        a = self.convert(a, t)
        b = self.convert(b, t)
        irop = {'+': 'add', '-': 'sub', '*': 'mul', '&': 'and', '|': 'or', '^': 'xor',
                '/': 'sdiv' if t.signed else 'udiv', '%': 'smod' if t.signed else 'umod'}[op]
        return self.binop(irop, a.op, b.op, t, dst)

    def binop(self, irop, a, b, t, dst=None):
        size = 4 if t.size == 4 else 2
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
        if a.t.is_ptr and b.t.is_ptr:
            if op != '-':
                self.err('adding two pointers')
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
        i = self.convert(b, INT if b.t.signed else UINT)
        if isinstance(i.op, Imm):
            k = self.wrap(i.op.val, INT) * size
            if op == '-':
                k = -k
            if pt.isfar:
                return self.binop('add', a.op, Imm(k, 4), pt, dst)
            return self.binop('add', a.op, Imm(k & 0xFFFF), pt, dst)
        sc = self.scale(i.op, size)
        if pt.isfar:
            z = self.newv(4)
            self.emit(Ins('sx', z, sc))
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
            size = 4 if t.size == 4 else 2
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
        if name in BUILTINS:
            return self.builtin(name, args, e, dst)
        if name is not None and self.lookup(name) is None:
            self.warn(f'implicit declaration of {name}', e)
            asm = mangle(name)
            self.scopes[0][name] = Sy('global', FuncT(INT, [], False, False), asm=asm)
            self.unit.externs.add(asm)
        f = self.rv(e.name)
        ft = f.t.to if f.t.is_ptr else f.t
        if not ft.is_func:
            self.err('calling a non-function', e)
        ops = []
        sret = None
        if ft.ret.is_struct:
            slot = self.new_slot('ret', ft.ret.size)
            sret = Frame(slot)
            ops.append(sret)
        params = ft.params
        if ft.proto and not ft.variadic and len(args) != len(params):
            self.err(f'{name or "function"} takes {len(params)} arguments, {len(args)} given', e)
        if ft.proto and len(args) < len(params):
            self.err(f'too few arguments to {name or "function"}', e)
        for i, a in enumerate(args):
            r = self.rv(a)
            if i < len(params) and ft.proto:
                pt = params[i][1]
            else:
                pt = promote(r.t) if r.t.is_int else r.t
            if pt.is_struct:
                # by value: a private copy in the caller's frame, passed by address
                slot = self.new_slot('arg', pt.size)
                self.emit(Ins('copy', a=r.op, b=Frame(slot), n=pt.size))
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
            size = 4 if rt.size == 4 else 2
            d = dst if dst is not None and dst.size == size and not (rt.is_int and rt.size == 1) else self.newv(size)
        tgt = f.op
        self.emit(Ins('call', d, tgt=tgt, args=ops))
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

    def builtin(self, name, args, e, dst):
        if name in ('__builtin_va_start', '__va_start'):
            lv = self.lval(args[0])
            d = self.newv(4)
            self.emit(Ins('vastart', d))
            self.store(lv.base, lv.idx, lv.off, lv.t, d) if lv.kind == 'mem' else \
                self.emit(Ins('mov', lv.op, d))
            return RV(Imm(0), VOID)
        if name == '__cop':
            n = self.const_int(args[0])
            ops = [self.convert(self.rv(a), UINT).op for a in args[1:4]]
            d = dst if dst is not None and dst.size == 2 else self.newv(2)
            self.emit(Ins('cop', d, n=n, ra=ops[0], rx=ops[1], ry=ops[2]))
            return self.to_dst(RV(d, UINT), dst)
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
            if op in ('<', '>', '<=', '>=', '==', '!='):
                lt_ = decay(self.expr_type(e.left))
                rt_ = decay(self.expr_type(e.right))
                a = self.rv(e.left)
                b = self.rv(e.right)
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
                    ao = self.convert(a, t).op
                    bo = self.convert(b, t).op
                cc = {'<': 'lt', '>': 'gt', '<=': 'le', '>=': 'ge', '==': 'eq', '!=': 'ne'}[op]
                if cc not in ('eq', 'ne'):
                    cc = ('s' if signed else 'u') + cc
                self.emit(Ins('br', a=ao, b=bo, cc=cc, t=lt, f=lf))
                return
        r = self.rv(e)
        if r.t.is_struct:
            self.err('a structure used as a condition', e)
        op = r.op
        self.emit(Ins('br', a=op, b=Imm(0, op.size), cc='ne', t=lt, f=lf))


def type_eq(a, b):
    if a.kind != b.kind:
        return False
    if a.is_int:
        return a.size == b.size and a.signed == b.signed and a.name == b.name
    if a.is_ptr:
        return a.to.const == b.to.const and a.to.volatile == b.to.volatile and type_eq(a.to, b.to)
    if a.is_struct:
        return a is b
    if a.is_arr:
        return a.n == b.n and type_eq(a.elem, b.elem)
    if a.is_func:
        return type_eq(a.ret, b.ret) and len(a.params) == len(b.params)
    return True


LLONG = IntT(8, True, 'long long')
LLONG_U = IntT(8, False, 'unsigned long long')


def _check_ll(t, node, f):
    while t.is_arr or t.is_ptr:
        if t.is_ptr:
            return
        t = t.elem
    if t.is_int and t.size == 8:
        f.unsup('long long is not supported', node)


BUILTINS = {'__builtin_va_start': VOID, '__va_start': VOID, '__cop': UINT, '__cbank': UINT}


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
            out.append(int(s[i + 1:j], 16) & 0xFF)
            i = j
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


def _has_nonconst_inner(t):
    return False


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
