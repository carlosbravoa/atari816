#!/usr/bin/env python3
"""solitair_gen.py OUT.inc - Solitaire's self-test scripts (user/sol_tscript.inc).

A model of the same rules as user/sol_game.s (deal generator, shuffle, dealing, legal
moves, scoring, undo, the trivial-finish test, the checksum) plays known deals:
winning lines found by small solvers (FreeCell; Klondike draw 1), with refused moves and
undo / redo mixed in, score and checksum check points, and a draw-3 game with turn-overs.
It writes them as the byte script that `solitair -t` replays (see user/sol_test.s), and
the FreeCell win as `tshow`, the moves `solitair -s` shows in the window (picture session).
Run it after a change of the rules; the output is checked in."""
import sys, heapq, random

M32 = 0xFFFFFFFF
DOWN = 0x80
STOCK, WASTE, FOUND, TAB, CELL = 1, 2, 3, 4, 5

def rank(c): return (c & 0x7F) % 13
def suit(c): return (c & 0x7F) // 13
def red(c): return suit(c) in (1, 2)

class Game:
    def __init__(self, game, draw3, deal):
        self.game, self.draw3, self.deal_no = game, draw3, deal
        if game == 0:
            self.types = [STOCK, WASTE] + [FOUND] * 4 + [TAB] * 7
        else:
            self.types = [CELL] * 4 + [FOUND] * 4 + [TAB] * 8
        self.p = [[] for _ in self.types]
        self.hist, self.score, self.moves = [], 0, 0
        x = (deal * 0x9E3779B1 + 0x6D2B79F5) & M32
        self.rng = x or 1
        for _ in range(8): self.xs()
        deck = list(range(52))
        for i in range(51, 0, -1):
            j = self.rand_n(i + 1)
            deck[i], deck[j] = deck[j], deck[i]
        k = 0
        if game == 0:
            for r in range(7):
                for c in range(r, 7):
                    self.p[6 + c].append(deck[k] | (0 if c == r else DOWN)); k += 1
            while k < 52:
                self.p[0].append(deck[k] | DOWN); k += 1
        else:
            for i in range(52): self.p[8 + i % 8].append(deck[i])

    def xs(self):
        x = self.rng
        x ^= (x << 13) & M32; x ^= x >> 17; x ^= (x << 5) & M32
        self.rng = x
    def rand_n(self, n):
        self.xs()
        return ((self.rng >> 16) * n) >> 16

    def can_move(self, ms, mi, md):
        if ms == md or ms >= len(self.p) or md >= len(self.p): return False
        src, dst = self.p[ms], self.p[md]
        n = len(src) - mi
        if n <= 0: return False
        c = src[mi]
        if c & DOWN: return False
        ts, td = self.types[ms], self.types[md]
        if ts == STOCK: return False
        if ts == FOUND and self.game: return False
        if ts in (WASTE, CELL, FOUND) and n != 1: return False
        if ts == TAB:
            for k in range(mi, len(src) - 1):
                a, b = src[k], src[k + 1]
                if b & DOWN or red(a) == red(b) or rank(b) + 1 != rank(a): return False
        if td == FOUND:
            if n != 1: return False
            if not dst: return rank(c) == 0
            return suit(dst[-1]) == suit(c) and rank(dst[-1]) + 1 == rank(c)
        if td == CELL: return n == 1 and not dst
        if td != TAB: return False
        if dst:
            t = dst[-1]
            if t & DOWN or red(t) == red(c) or rank(c) + 1 != rank(t): return False
        elif self.game == 0:
            return rank(c) == 12
        if self.game == 0: return True
        cap = sum(1 for i in range(4) if not self.p[i]) + 1
        for i in range(8, 16):
            if not self.p[i] and i != md: cap *= 2
        return n <= cap

    def addscore(self, d):
        if self.score + d < 0: d = -self.score
        self.score += d
        return d

    def do_move(self, ms, mi, md):
        src = self.p[ms]
        cards = src[mi:]
        del src[mi:]
        self.p[md].extend(cards)
        f = 0
        if self.game == 0 and self.types[ms] == TAB and src and src[-1] & DOWN:
            src[-1] &= 0x7F; f = 1
        d = 0
        if self.game == 0:
            if self.types[md] == FOUND and self.types[ms] != FOUND: d += 10
            if self.types[ms] == FOUND: d -= 10
            if self.types[ms] == WASTE and self.types[md] == TAB: d += 5
            if f: d += 5
        d = self.addscore(d)
        self.hist.append((1, ms, md, len(cards), f, d)); self.moves += 1

    def draw_stock(self):
        if self.game: return False
        st, wa = self.p[0], self.p[1]
        if not st:
            if not wa: return False
            n = len(wa)
            while wa: st.append(wa.pop() | DOWN)
            d = self.addscore(-20)
            self.hist.append((3, 0, 1, n, 0, d)); self.moves += 1
            return True
        k = min(3 if self.draw3 else 1, len(st))
        for _ in range(k): wa.append(st.pop() & 0x7F)
        self.hist.append((2, 0, 1, k, 0, 0)); self.moves += 1
        return True

    def undo(self):
        if not self.hist: return False
        kind, ms, md, n, f, d = self.hist.pop()
        self.moves -= 1; self.score -= d
        if kind == 1:
            if f: self.p[ms][-1] |= DOWN
            cards = self.p[md][-n:]; del self.p[md][-n:]
            self.p[ms].extend(cards)
        elif kind == 2:
            for _ in range(n): self.p[0].append(self.p[1].pop() | DOWN)
        else:
            for _ in range(n): self.p[1].append(self.p[0].pop() & 0x7F)
        return True

    def all_home(self):
        return sum(len(self.p[i]) for i in range(len(self.p)) if self.types[i] == FOUND) == 52
    def trivial(self):
        if self.game == 0 and (self.p[0] or self.p[1]): return False
        for i, t in enumerate(self.types):
            if t != TAB: continue
            pl = self.p[i]
            for k, c in enumerate(pl):
                if c & DOWN: return False
                if k + 1 < len(pl) and (pl[k + 1] & DOWN or rank(pl[k + 1]) > rank(c)): return False
        return True
    def found_for(self, ms, mi):
        base = 2 if self.game == 0 else 4
        for md in range(base, base + 4):
            if self.can_move(ms, mi, md): return md
        return None
    def auto_pick(self):
        best = None
        for i, t in enumerate(self.types):
            if t in (FOUND, STOCK) or not self.p[i]: continue
            c = self.p[i][-1]
            if c & DOWN: continue
            if best is not None and rank(c) >= best[0]: continue
            md = self.found_for(i, len(self.p[i]) - 1)
            if md is not None: best = (rank(c), i, len(self.p[i]) - 1, md)
        return best
    def checksum(self):
        h = 0
        for pl in self.p:
            h = (h * 31 + len(pl)) & 0xFFFF
            for c in pl: h = (h * 31 + c) & 0xFFFF
        return h
    def key(self):
        return tuple(tuple(pl) for pl in self.p)

# ---------------------------------------------------------------- solvers
def legal_moves(g):
    out = []
    n = len(g.p)
    for ms in range(n):
        for mi in range(len(g.p[ms])):
            for md in range(n):
                if g.can_move(ms, mi, md): out.append((ms, mi, md))
    return out

def fc_key(g):
    cells = tuple(sorted(tuple(pl) for pl in g.p[0:4]))
    tabs = tuple(sorted(tuple(pl) for pl in g.p[8:16]))
    return (cells, tuple(len(pl) for pl in g.p[4:8]), tabs)

def fc_h(g):
    home = sum(len(g.p[i]) for i in range(4, 8))
    h = (52 - home) * 4
    for i in range(8, 16):
        pl = g.p[i]
        # cards above a lower card of the same column
        for k in range(len(pl)):
            for m in range(k + 1, len(pl)):
                if rank(pl[m]) > rank(pl[k]): h += 1; break
    h += sum(1 for i in range(4) if g.p[i]) * 2
    return h

def solve_freecell(deal, limit=200000):
    import copy
    g0 = Game(1, 0, deal)
    start = fc_key(g0)
    seen = {start}
    cnt = 0
    heap = [(fc_h(g0), 0, cnt, [])]
    while heap and cnt < limit:
        _, depth, _, path = heapq.heappop(heap)
        g = Game(1, 0, deal)
        for m in path: g.do_move(*m)
        if g.all_home(): return path
        if g.trivial():
            gg = Game(1, 0, deal)
            for m in path: gg.do_move(*m)
            rest = []
            while True:
                b = gg.auto_pick()
                if not b: break
                rest.append(b[1:]); gg.do_move(*b[1:])
            if gg.all_home(): return path + rest
        for m in legal_moves(g):
            ms, mi, md = m
            if g.types[md] == TAB and not g.p[md] and mi == 0: continue   # whole column to empty
            g.do_move(*m)
            k = fc_key(g)
            if k not in seen:
                seen.add(k); cnt += 1
                heapq.heappush(heap, (fc_h(g) + (depth + 1) // 4, depth + 1, cnt, path + [m]))
            g.undo()
    return None

def kl_h(g):
    home = sum(len(g.p[i]) for i in range(2, 6))
    down = sum(1 for i in range(6, 13) for c in g.p[i] if c & DOWN)
    return (52 - home) * 3 + down * 5 + len(g.p[0]) + len(g.p[1])

def solve_klondike(deal, limit=60000):
    g0 = Game(0, 0, deal)
    seen = {g0.key()}
    cnt = 0
    heap = [(kl_h(g0), 0, cnt, [])]
    while heap and cnt < limit:
        _, depth, _, path = heapq.heappop(heap)
        g = Game(0, 0, deal)
        for m in path:
            if m == 'D': g.draw_stock()
            else: g.do_move(*m)
        if g.trivial():
            rest = []
            while True:
                b = g.auto_pick()
                if not b: break
                rest.append(b[1:]); g.do_move(*b[1:])
            if g.all_home(): return path + rest
        cand = []
        for m in legal_moves(g):
            ms, mi, md = m
            if g.types[ms] == FOUND: continue
            if g.types[ms] == TAB and mi == 0 and g.types[md] == TAB and not g.p[md]: continue
            cand.append(m)
        cand.append('D')
        for m in cand:
            if m == 'D':
                if not g.draw_stock(): continue
            else: g.do_move(*m)
            k = g.key()
            if k not in seen:
                seen.add(k); cnt += 1
                heapq.heappush(heap, (kl_h(g) + depth // 8, depth + 1, cnt, path + [m]))
            g.undo()
    return None

# ---------------------------------------------------------------- the script
class Script:
    def __init__(self): self.b = []
    def name(self, s): self.b += [ord('T')] + list(s.encode()) + [0]
    def new(self, g): self.b += [ord('N'), g.game, g.draw3, g.deal_no & 255, g.deal_no >> 8]
    def move(self, ms, mi, md, ok): self.b += [ord('M'), ms, mi, md, int(ok)]
    def draw(self, ok): self.b += [ord('D'), int(ok)]
    def undo(self): self.b += [ord('U')]
    def auto(self): self.b += [ord('A')]
    def triv(self, t): self.b += [ord('I'), int(t)]
    def won(self): self.b += [ord('W')]
    def score(self, s): self.b += [ord('S'), s & 255, (s >> 8) & 255]
    def sum(self, h): self.b += [ord('K'), h & 255, h >> 8]

def play(sc, g, path, rnd, label):
    """the path's moves, with refused attempts, undo / redo and check points"""
    sc.name(label)
    sc.new(g)
    sc.sum(g.checksum())
    for k, m in enumerate(path):
        if rnd.random() < 0.3:                          # a refused move first
            for _ in range(50):
                ms, md = rnd.randrange(len(g.p)), rnd.randrange(len(g.p))
                mi = rnd.randrange(len(g.p[ms]) + 1)
                if not g.can_move(ms, mi, md):
                    sc.move(ms, mi, md, False); break
        if m == 'D':
            sc.draw(g.draw_stock())
        else:
            assert g.can_move(*m), (label, k, m)
            sc.move(*m, True); g.do_move(*m)
        if rnd.random() < 0.15:                         # undo and do it again
            sc.undo(); g.undo()
            if m == 'D': sc.draw(g.draw_stock())
            else: sc.move(*m, True); g.do_move(*m)
        if k % 10 == 9:
            sc.score(g.score); sc.sum(g.checksum())
        if g.trivial() and not g.all_home():
            sc.triv(True)
            sc.auto()
            while True:
                b = g.auto_pick()
                if not b: break
                g.do_move(*b[1:])
            break
    sc.won() if g.all_home() else None
    sc.score(g.score); sc.sum(g.checksum())
    return g

def main():
    rnd = random.Random(816)
    sc = Script()
    # FreeCell: a winning line
    fdeal = None
    for d in range(1, 60):
        p = solve_freecell(d)
        if p: fdeal, fpath = d, p; break
    g = play(sc, Game(1, 0, fdeal), fpath, rnd, f'FreeCell deal {fdeal}: won')
    assert g.all_home()
    # Klondike draw 1: a winning line
    for d in range(1, 400):
        p = solve_klondike(d)
        if p: kdeal, kpath = d, p; break
    g = play(sc, Game(0, 0, kdeal), kpath, rnd, f'Klondike deal {kdeal}, draw 1: won')
    assert g.all_home()
    # Klondike draw 3: draws, turn-overs, some moves, undo all
    g = Game(0, 1, 77)
    sc.name('Klondike deal 77, draw 3: stock, score, undo')
    sc.new(g)
    n = 0
    for step in range(120):
        ms = [m for m in legal_moves(g) if g.types[m[0]] != FOUND]
        if ms and rnd.random() < 0.5:
            m = rnd.choice(ms); sc.move(*m, True); g.do_move(*m)
        else:
            sc.draw(g.draw_stock())
        n += 1
        if n % 15 == 0: sc.score(g.score); sc.sum(g.checksum())
    sc.triv(g.trivial())
    while g.hist:
        sc.undo(); g.undo()
    sc.score(0); sc.sum(Game(0, 1, 77).checksum())
    # FreeCell: supermove limits
    g = Game(1, 0, 5)
    sc.name('FreeCell deal 5: moves of runs, free cells, refusals')
    sc.new(g)
    for step in range(200):
        lm = legal_moves(g)
        bad = [(rnd.randrange(16), rnd.randrange(8), rnd.randrange(16)) for _ in range(20)]
        bad = [b for b in bad if not g.can_move(*b)]
        if bad: sc.move(*bad[0], False)
        if not lm: break
        m = rnd.choice(lm); sc.move(*m, True); g.do_move(*m)
        if step % 20 == 19: sc.sum(g.checksum())
    sc.sum(g.checksum())
    out = ['; generated by tests/solitair_gen.py - do not edit',
           f'; FreeCell deal {fdeal} ({len(fpath)} moves), Klondike deal {kdeal} ({len(kpath)} moves)',
           'tscript:']
    b = sc.b + [0]
    for i in range(0, len(b), 16):
        out.append('        .byte   ' + ', '.join(f'${x:02X}' for x in b[i:i + 16]))
    out.append(f'TSHOWDEAL = {fdeal}')
    out.append('tshow:                                  ; the FreeCell win: src, index, dst')
    sb = [x for m in fpath for x in m] + [255]
    for i in range(0, len(sb), 15):
        out.append('        .byte   ' + ', '.join(f'${x:02X}' for x in sb[i:i + 15]))
    open(sys.argv[1], 'w').write('\n'.join(out) + '\n')
    print(f'FreeCell deal {fdeal}: {len(fpath)} moves; Klondike deal {kdeal}: {len(kpath)} moves; script {len(b)} bytes')

main()
