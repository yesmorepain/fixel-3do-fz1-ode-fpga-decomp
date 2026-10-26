#!/usr/bin/env python3
"""Register map golden netlist -> clean HDL, by matching value histories in co-sim waveform dumps.

Usage: python3 tools/eqmap.py [VCD ...] [--all] [--diff GOLDEN CLEAN] > build/eqmap.txt
       python3 tools/eqmap.py VCD --check build/eqmap.txt   (first divergence of every unique pair, earliest first)
  VCDs from `DUMP=1 sh tools/sim/cosim.sh TB +vcd=PATH` (default build/sim/cosim_dump.vcd).

Each golden flip-flop (tools/fflist.py), plus the golden LUT-loop latches, is matched to every clean signal bit
(regs first, then wires) whose value history is identical (=) or inverted (~) from the end of the first pin 43
pulse on (before it the reference IO regs hold x). A golden FF that is x until its first clock is compared from
then on; x copied along a shift chain matches anything. With several VCDs the candidate sets are intersected.
Output per golden net: `nXXX  =clean.path[bit] ~clean.other ...` (or UNMATCHED), then a summary.
--all also lists wire matches for nets that already match a reg. --diff prints where one pair differs (first VCD).
A match is evidence from simulation only; the formal check (tools/formal) confirms it.
"""
import re
import subprocess
import sys
from collections import defaultdict

args = sys.argv[1:]
show_all = '--all' in args
if show_all:
    args.remove('--all')
diff = None
if '--diff' in args:
    i = args.index('--diff')
    diff = args[i + 1:i + 3]
    del args[i:i + 3]
check = None
if '--check' in args:
    i = args.index('--check')
    check = args[i + 1]
    del args[i:i + 2]
vcds = args or ['build/sim/cosim_dump.vcd']

LATCHES = ['n592', 'n629', 'n615', 'n596', 'n440', 'n575', 'n455', 'n375']
ffl = subprocess.run([sys.executable, 'tools/fflist.py'], capture_output=True, text=True, check=True).stdout
golden_ffs = re.findall(r'^(n\d+):', ffl, re.M) + LATCHES
gset = set(golden_ffs)
inv = {'0': '1', '1': '0', 'x': 'x'}


def rebase(h, tb):
    """History h seen from time tb on (value at tb first)."""
    out = []
    for tt, v in h:
        if tt <= tb:
            out = [(tb, v)]
        elif out[-1][1] != v:
            out.append((tt, v))
    return tuple(out)


def merged(h, c):
    """(time, golden value, clean value) at every change point of either history."""
    i = j = 0
    out = []
    while i < len(h) or j < len(c):
        tt = min(x[0] for x in (h[i] if i < len(h) else None, c[j] if j < len(c) else None) if x)
        while i < len(h) and h[i][0] == tt:
            i += 1
        while j < len(c) and c[j][0] == tt:
            j += 1
        out.append((tt, h[i - 1][1], c[j - 1][1]))
    return out


def load(vcd):
    """Returns (t0, golden {net: history}, clean [(name, kind, history)])."""
    f = open(vcd)
    ids = defaultdict(list)
    scope = []
    for line in f:
        w = line.split()
        if not w:
            continue
        if w[0] == '$scope':
            scope.append(w[2])
        elif w[0] == '$upscope':
            scope.pop()
        elif w[0] == '$var':
            msb = lsb = 0
            if len(w) > 6 and w[5].startswith('['):
                r = w[5][1:-1].split(':')
                msb, lsb = int(r[0]), int(r[-1])
            ids[w[3]].append(('.'.join(scope), w[4], int(w[2]), msb, lsb, w[1]))
        elif w[0] == '$enddefinitions':
            break
    want, gcode, pin43 = {}, {}, None
    for code, vs in ids.items():
        for (sc, name, width, msb, lsb, kind) in vs:
            if sc.endswith('.golden') and name == 'pin_43':
                pin43 = code
                want[code] = 1
            if sc.endswith('.golden') and name in gset:
                want[code] = width
                gcode[name] = code
            elif '.clean' in sc and '.ram' not in sc and 'ram_' not in sc:
                want[code] = width
    hist = defaultdict(list)
    t = 0
    for line in f:
        c = line[0]
        if c == '#':
            t = int(line[1:])
        elif c in '01xzXZ':
            code = line[1:].strip()
            if code in want:
                hist[code].append((t, c.lower()))
        elif c in 'bB':
            v, code = line[1:].split()
            if code in want:
                hist[code].append((t, v.lower()))
    h = hist[pin43]
    t0 = next(tt for (tt, v), (_, pv) in zip(h[1:], h) if v == '0' and pv == '1')

    def bits_of(code, width):
        out = [[] for _ in range(width)]
        for (tt, v) in hist[code]:
            if len(v) < width:
                v = (v[0] if v[0] in 'xz' else '0') * (width - len(v)) + v
            for k in range(width):
                b = v[width - 1 - k]
                b = 'x' if b in 'xz' else b
                if tt <= t0:
                    out[k][:1] = [(t0, b)]
                elif not out[k] or out[k][-1][1] != b:
                    out[k].append((tt, b))
        return [tuple(o) for o in out]

    clean = []
    for code, vs in ids.items():
        for (sc, name, width, msb, lsb, kind) in vs:
            if '.clean' not in sc or code not in want:
                continue
            path = sc[sc.index('.clean') + 1:] + '.' + name
            for k, hh in enumerate(bits_of(code, width)):
                clean.append((path + ('[%d]' % (min(msb, lsb) + k) if width > 1 else ''), kind, hh))
    golden = {g: bits_of(gcode[g], 1)[0] for g in gcode}
    return t0, golden, clean


def match(t0, golden, clean):
    """{golden net: (set of (sign, clean name, kind), constant?, changes)}"""
    by_start = {}

    def clean_at(tb):
        if tb not in by_start:
            d = {}
            for n, k, h in clean:
                d.setdefault(rebase(h, tb), []).append((n, k))
            by_start[tb] = d
        return by_start[tb]

    res = {}
    for g, h in golden.items():
        tg = next((tt for tt, v in h if v != 'x'), h[-1][0])   # x until its first clock or reset
        h = rebase(h, tg)
        hi = tuple((tt, inv[v]) for tt, v in h)
        d = clean_at(tg)
        m = set([('=',) + x for x in d.get(h, [])] + [('~',) + x for x in d.get(hi, [])])
        if not m and any(v == 'x' for _, v in h):
            # x copied along a shift chain before the first full byte: x matches anything
            tx = next(tt for tt, v in h[::-1] if v == 'x')
            tx = next(tt for tt, v in h if tt > tx)
            hx = rebase(h, tx)
            hxi = tuple((tt, inv[v]) for tt, v in hx)
            cand = set(n for n, k in clean_at(tx).get(hx, []) + clean_at(tx).get(hxi, []))
            for n, k, c in clean:
                if n in cand:
                    pr = merged(h, rebase(c, tg))
                    if all(x == 'x' or x == y for _, x, y in pr):
                        m.add(('=', n, k))
                    elif all(x == 'x' or x == inv[y] for _, x, y in pr):
                        m.add(('~', n, k))
        res[g] = (m, len(set(v for _, v in h)) == 1, len(h) - 1)
    return res


if diff:
    t0, golden, clean = load(vcds[0])
    g = golden[diff[0]]
    c = next(h for n, k, h in clean if n == diff[1])
    tg = next((tt for tt, v in g if v != 'x'), g[-1][0])
    bad = [x for x in merged(rebase(g, tg), rebase(c, tg)) if x[1] != x[2]]
    print('# %s from %d ps: %d differing change points; first (time golden clean): %s'
          % (vcds[0], tg, len(bad), '  '.join('%d %s %s' % x for x in bad[:8])))
    sys.exit()

if check:
    t0, golden, clean = load(vcds[0])
    cl = {n: h for n, k, h in clean}
    out = []
    for line in open(check):
        w = line.split()
        if not w or w[0].startswith('#') or w[1] == 'UNMATCHED':
            continue
        cands = [x for x in w[1:] if x[:1] in '=~' and x[1:].startswith('clean.')]
        if len(cands) != 1 or w[0] not in golden:
            continue
        sign, n = cands[0][0], cands[0][1:].replace('clean.', '', 1)
        n = 'clean.' + n
        g = golden[w[0]]
        tg = next((tt for tt, v in g if v != 'x'), g[-1][0])
        c = cl[n] if sign == '=' else tuple((tt, inv[v]) for tt, v in cl[n])
        bad = [x for x in merged(rebase(g, tg), rebase(c, tg)) if x[1] != x[2] and x[1] != 'x']
        if bad:
            out.append((bad[0][0], w[0], sign + n, len(bad)))
    for x in sorted(out)[:25]:
        print('%d ps  %-6s %-32s %d differing points' % x)
    print('# %d pairs diverge' % len(out))
    sys.exit()

total = {}
allregs = set()
for vcd in vcds:
    t0, golden, clean = load(vcd)
    allregs |= set(n for n, k, h in clean if k == 'reg')
    print('# %s: start %d ps' % (vcd, t0))
    for g, (m, const, nch) in match(t0, golden, clean).items():
        if g not in total:
            total[g] = [m, const, nch]
        else:
            total[g][0] &= m
            total[g][1] &= const
            total[g][2] += nch

used = set()
unmatched = []
for g in golden_ffs:
    if g not in total:
        print('%-6s NOT IN DUMP' % g)
        unmatched.append(g)
        continue
    m, const, nch = total[g]
    m = sorted(m, key=lambda x: (x[2] != 'reg', x[1]))
    regs = [x for x in m if x[2] == 'reg']
    shown = m if (show_all or not regs) else regs
    used |= set(n for _, n, k in regs)
    if not m:
        unmatched.append(g)
    tag = ' (constant)' if const else ' (%d changes)' % nch
    print('%-6s %s%s' % (g, '  '.join(s + n + ('' if k == 'reg' else '/w') for s, n, k in shown) or 'UNMATCHED', tag))

print('# matched %d of %d golden FFs/latches; unmatched: %s'
      % (len(golden_ffs) - len(unmatched), len(golden_ffs), ' '.join(unmatched) or '-'))
orphan = sorted(allregs - used)
print('# clean reg bits with no golden match (%d): %s' % (len(orphan), ' '.join(orphan) or '-'))
