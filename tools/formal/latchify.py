#!/usr/bin/env python3
"""Turn the transmit-load feedback LUTs of a synthesised netlist back into latches, for the formal check.

Usage: python3 tools/formal/latchify.py IN.v OUT.v
A feedback LUT is an SB_LUT4 with LUT_INIT 16'h00ac, I3 = 0 and O wired to I1: O = I2 ? I0 : O, i.e. a latch with
enable I2 and data I0 (truth table checked here). Each becomes `always @* if (I2) q = I0; assign O = q;`.
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
pat = re.compile(r"  SB_LUT4 #\(\n    \.LUT_INIT\(16'h([0-9a-f]{4})\)\n  \) (\S+)  \(\n"
                 r"    \.I0\((.*?)\),\n    \.I1\((.*?)\),\n    \.I2\((.*?)\),\n    \.I3\((.*?)\),\n    \.O\((.*?)\)\n  \);\n")
k = [0]


def lut(i0, i1, i2, init):
    return (int(init, 16) >> (i0 | i1 << 1 | i2 << 2)) & 1


def rep(m):
    init, name, i0, i1, i2, i3, o = m.groups()
    if i1.strip() != o.strip():
        return m.group(0)
    assert i3 == "1'h0", name
    assert all(lut(a, b, c, init) == (a if c else b) for a in (0, 1) for b in (0, 1) for c in (0, 1)), name
    k[0] += 1
    q = '\\latchify_q%d ' % k[0]
    return '  reg %s;\n  always @* if (%s) %s = %s;   // latchify: feedback LUT %s\n  assign %s = %s;\n' % (
        q, i2, q, i0, name, o, q)
t = pat.sub(rep, t)
open(dst, 'w').write(t)
print('%s: %d feedback LUTs -> latches' % (dst, k[0]))
