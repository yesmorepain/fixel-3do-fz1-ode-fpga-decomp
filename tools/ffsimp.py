#!/usr/bin/env python3
"""Simplified next-state logic of flip-flops (or any net) in the sim netlist, as a function of leaf nets.

Usage: python3 tools/ffsimp.py [--all] [--max N] NET ...

Leaves: FF outputs, pins, RAM outputs, PLL outputs, and nets on a combinational loop (marked as leaves the
second time they are reached). Each FF is printed as "q: clock, async ...; d = <SOP>" with any enable folded in.
Needs sympy (requirements.txt). --max limits the support size (default 16; larger cones print unsimplified).
"""
import re
import sys
import sympy

args = sys.argv[1:]
maxsup = 16
if '--max' in args:
    i = args.index('--max'); maxsup = int(args[i + 1]); del args[i:i + 2]
leaves = set()
while '--leaf' in args:
    i = args.index('--leaf'); leaves.update(args[i + 1].split(',')); del args[i:i + 2]
doall = '--all' in args
args = [a for a in args if a != '--all']
t = open('build/sim/chip_sim.v').read()

comb = {}
for m in re.finditer(r'^(?:/\*[^*]*\*/ )?assign (n\d+|pin_\d+)\s*=\s*(?:/\*[^*]*\*/)?\s*(.*?);$', t, re.M):
    if '1\'bz' not in m.group(2):
        comb[m.group(1)] = m.group(2).strip()
ffs = {}
pat = re.compile(r'always @\((pos|neg)edge (\w+)(?:, posedge (\w+))?\)\s*(?:if \((\w+)\) (\w+) <= (1\'b[01]); else )?'
                 r'(?:if \(([^)]*)\) )?(\w+) <= (.*?);$', re.M)
for m in pat.finditer(t):
    edge, clk, arst, _, _, rval, en, q, d = m.groups()
    ffs[q] = (edge, clk, arst, rval, en, d.strip())
for m in re.finditer(r'always @\((pos|neg)edge (\w+)\) (n\d+) <= (\w+);', t):
    ffs.setdefault(m.group(3), (m.group(1), m.group(2), None, None, None, m.group(4)))

def tokens(s):
    return re.findall(r"1'b[01]|\w+|[()?:!&|^~]", s)

class P:
    """Parse a netlist expression into a Python expression over big-int truth-table columns (M = all-ones)."""
    def __init__(self, s, leaf):
        self.t = tokens(s); self.i = 0; self.leaf = leaf
    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None
    def eat(self, x=None):
        v = self.t[self.i]; assert x is None or v == x, (x, v, self.t); self.i += 1; return v
    def expr(self):
        c = self.orx()
        if self.peek() == '?':
            self.eat('?'); a = self.expr(); self.eat(':'); b = self.expr()
            return '((%s)&(%s)|(M^(%s))&(%s))' % (c, a, c, b)
        return c
    def orx(self):
        v = self.xorx()
        while self.peek() == '|':
            self.eat(); v = '(%s)|(%s)' % (v, self.xorx())
        return v
    def xorx(self):
        v = self.andx()
        while self.peek() == '^':
            self.eat(); v = '(%s)^(%s)' % (v, self.andx())
        return v
    def andx(self):
        v = self.un()
        while self.peek() == '&':
            self.eat(); v = '(%s)&(%s)' % (v, self.un())
        return v
    def un(self):
        x = self.eat()
        if x in ('!', '~'):
            return '(M^(%s))' % self.un()
        if x == '(':
            v = self.expr(); self.eat(')'); return v
        if x in ("1'b0", '0'):
            return '0'
        if x in ("1'b1", '1'):
            return 'M'
        return self.leaf(x)

memo = {}
cut = [False]
def build(net, path):
    """Python expression for net; leaves become V['name']. Results with a loop cut inside are not memoised."""
    if net in ffs or net not in comb or (net in leaves and path):
        return "V['%s']" % net
    if net in path:
        cut[0] = True
        return "V['%s']" % net
    if net in memo:
        return memo[net]
    saved = cut[0]; cut[0] = False
    e = '(%s)' % P(comb[net], lambda x: build(x, path | {net})).expr()
    if not cut[0]:
        memo[net] = e
    cut[0] = cut[0] or saved
    return e

def evaluate(e):
    names = sorted(set(re.findall(r"V\['(\w+)'\]", e)), key=lambda s: (s[0] != 'n', int(re.sub(r'\D', '', s) or 0), s))
    n = len(names)
    if n > maxsup:
        return None, names
    rows = 1 << n
    M = (1 << rows) - 1
    V = {}
    for k, nm in enumerate(names):
        # column k: bit r set when bit k of row index r is 1
        blk = (1 << (1 << k)) - 1
        pat = 0
        period = 1 << (k + 1)
        for base in range(0, rows, period):
            pat |= blk << (base + (1 << k))
        V[nm] = pat
    tt = eval(e, {'M': M, 'V': V})
    return tt & M, names

def show(e):
    tt, names = evaluate(e)
    if tt is None:
        return '<support %d: %s>' % (len(names), ' '.join(names))
    n = len(names); rows = 1 << n
    ones = [r for r in range(rows) if tt >> r & 1]
    if not ones:
        return '0'
    if len(ones) == rows:
        return '1'
    # drop variables the function does not depend on
    used = [k for k in range(n) if any((tt >> r & 1) != (tt >> (r ^ (1 << k)) & 1) for r in range(rows))]
    syms = [sympy.Symbol(names[k]) for k in used]
    mins = sorted({sum(((r >> k) & 1) << (len(used) - 1 - j) for j, k in enumerate(used)) for r in ones})
    f = sympy.SOPform(syms, [[(m >> (len(used) - 1 - j)) & 1 for j in range(len(used))] for m in mins])
    return str(f).replace('~', '!')

def describe(q):
    if q in ffs:
        edge, clk, arst, rval, en, d = ffs[q]
        h = '%s: %sedge %s' % (q, edge, clk)
        if arst:
            h += ', async %s -> %s' % (arst, rval[-1])
        e = P(d, lambda x: build(x, frozenset())).expr()
        if en and en != "1'b1":
            ee = P(en, lambda x: build(x, frozenset())).expr()
            e = '((%s)&(%s)|(M^(%s))&V[\'%s\'])' % (ee, e, ee, q)
        print(h + '\n    d = ' + show(e), flush=True)
    else:
        print('%s (comb) = %s' % (q, show(build(q, frozenset()))), flush=True)

for q in (sorted(ffs, key=lambda s: int(s[1:])) if doall else args):
    describe(q)
