#!/usr/bin/env python3
"""Make the decoded netlist buildable by yosys/nextpnr, as a timing yardstick for the clean HDL build.

Usage: python3 tools/build/mkgolden_hw.py build/formal/gold.v build/hw_golden/golden.v
Input: mkformal.py's gold.v (LUT loops already rewritten as latches). Changes: the PLL output drives the main clock
again (PLLOUTGLOBAL, instead of the sim input), the OE power-up clock is the oscillator (as in the clean top), each
latch becomes a feedback LUT (O = en ? d : O) like the original, and the e_/v_ pin outputs become tristate pins.
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
t = t.replace('assign n5 = sim_pll_clk;', '').replace('assign n11 = sim_osc_clk;', 'assign n11 = pin_37;')
t = t.replace('.PLLOUTCORE(n630),', '.PLLOUTCORE(n630),\n  .PLLOUTGLOBAL(n5),')
k = [0]


def latch(m):
    q, en, d = m.group(1), m.group(2), m.group(3)
    k[0] += 1
    return ('wire %s, ld%d = %s;\nSB_LUT4 #(.LUT_INIT(16\'h00ac)) loop%d (.O(%s), .I0(ld%d), .I1(%s), .I2(%s), .I3(1\'b0));'
            % (q, k[0], d, k[0], q, k[0], q, en))
t = re.sub(r'^reg (n\d+); always @\* if \((n\d+)\) \1 = (.*?);   //.*$', latch, t, flags=re.M)
assert k[0] == 8, k
# ports: e_/v_ pairs -> tristate pins
hdr = re.search(r'module gold \((.*?)\);', t, re.S)
ports = hdr.group(1)
drv = sorted(set(re.findall(r'output e_(pin_\d+)', ports)))
ins = [p for p in re.findall(r'input (\w+)', ports) if p not in ('sim_pll_clk', 'sim_osc_clk')]
bidir = [p for p in drv if p in ins]
new = ['input %s' % p for p in ins if p not in bidir] + ['inout %s' % p for p in bidir] + \
      ['output %s' % p for p in drv if p not in bidir]
t = t[:hdr.start()] + 'module golden_top (%s);' % ', '.join(new) + t[hdr.end():]
for p in drv:
    t = re.sub(r'assign e_%s = (\w+); assign v_%s = \1 & (\w+);' % (p, p),
               lambda m, p=p: "assign %s = %s ? %s : 1'bz;" % (p, m.group(1), m.group(2)), t)
assert 'e_pin' not in t
open(dst, 'w').write(t)
print('wrote', dst)
