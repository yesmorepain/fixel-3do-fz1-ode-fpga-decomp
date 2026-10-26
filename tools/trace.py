#!/usr/bin/env python3
"""Trace drivers (back) or loads (fwd) of a net in build/fpga_pins.v.
Usage: trace.py back NET [depth]   |   trace.py fwd NET [depth]"""
import re, sys
src = open('build/fpga_pins.v').read().splitlines()
drv, uses = {}, {}
for ln in src:
    m = re.match(r'\s*(?:/\*.*?\*/\s*)?assign (\w+)\s*=\s*(.*);', ln) or \
        re.match(r'.*?(?:else if \([^)]*\) |\) )(\w+) <= (.*);', ln)
    if not m: continue
    lhs = m.group(1)
    drv.setdefault(lhs, []).append(ln.strip())
    for t in set(re.findall(r'\b(n\d+|pin_\d+)\b', ln)):
        if t != lhs: uses.setdefault(t, set()).add(lhs)
def back(n, d, seen, ind=0):
    for ln in drv.get(n, ['<no driver>']): print('  ' * ind + ln[:160])
    if d == 0 or n in seen: return
    seen.add(n)
    for ln in drv.get(n, []):
        rhs = ln.split('=', 1)[1] if 'assign' in ln else ln
        for t in dict.fromkeys(re.findall(r'\b(n\d+|pin_\d+)\b', rhs)):
            if t not in seen: back(t, d - 1, seen, ind + 1)
def fwd(n, d, seen, ind=0):
    for u in sorted(uses.get(n, ())):
        if u in seen: continue
        seen.add(u)
        for ln in drv.get(u, []): print('  ' * ind + ln[:160])
        if d > 1: fwd(u, d - 1, seen, ind + 1)
mode, net = sys.argv[1], sys.argv[2]
depth = int(sys.argv[3]) if len(sys.argv) > 3 else 2
(back if mode == 'back' else fwd)(net, depth, set())
