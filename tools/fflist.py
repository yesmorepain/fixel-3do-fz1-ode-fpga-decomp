#!/usr/bin/env python3
"""List every flip-flop of the sim netlist with its clock, async reset and next-state logic expanded through LUTs.

Usage: python3 tools/fflist.py [build/sim/chip_sim.v] [--depth N] [NET ...]

Expansion stops at FF outputs, pins, RAM outputs and the PLL; other nets are inlined up to --depth levels
(default 4). Output: one block per FF, sorted by name; give NET names to list only those FFs.
"""
import re
import sys

args = [a for a in sys.argv[1:]]
depth = 4
if '--depth' in args:
    i = args.index('--depth')
    depth = int(args[i + 1])
    del args[i:i + 2]
src = 'build/sim/chip_sim.v'
if args and args[0].endswith('.v'):
    src = args.pop(0)
only = set(args)
t = open(src).read()

comb = {}   # net -> expression (string)
for m in re.finditer(r'^assign (n\d+)\s*=\s*(?:/\*[^*]*\*/)?\s*(.*?);$', t, re.M):
    comb[m.group(1)] = m.group(2).strip()

ffs = {}    # q -> (clk, rst, rstval, d)
pat = re.compile(r'always @\((pos|neg)edge (\w+)(?:, posedge (\w+))?\)\s*(?:if \((\w+)\) (\w+) <= (1\'b[01]); else )?'
                 r'(?:if \(([^)]*)\) )?(\w+) <= (.*?);$', re.M)
for m in pat.finditer(t):
    edge, clk, arst, _, _, rval, en, q, d = m.groups()
    ffs[q] = ('%sedge %s' % (edge, clk), arst, rval, en, d.strip())
# IO cell regs written as "reg nX; always @(posedge clk) nX <= d;"
for m in re.finditer(r'always @\((pos|neg)edge (\w+)\) (n\d+) <= (\w+);', t):
    ffs.setdefault(m.group(3), ('%sedge %s' % (m.group(1), m.group(2)), None, None, None, m.group(4)))

def expand(e, lvl):
    if lvl <= 0:
        return e
    def rep(m):
        n = m.group(0)
        if n in ffs or n not in comb:
            return n
        x = comb[n]
        if re.fullmatch(r'\w+|1\'b[01]', x):
            return expand(x, lvl)
        return '(' + expand(x, lvl - 1) + ')'
    return re.sub(r'\bn\d+\b', rep, e)

for q in sorted(ffs, key=lambda s: int(s[1:]) if s[1:].isdigit() else 0):
    if only and q not in only:
        continue
    clk, arst, rval, en, d = ffs[q]
    head = '%s: %s' % (q, clk)
    if arst:
        head += ', async %s -> %s' % (arst, rval[-1])
    if en and en != "1'b1":
        head += ', en %s' % expand(en, depth)
    print(head)
    print('    d = %s' % expand(d, depth))
