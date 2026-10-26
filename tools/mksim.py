#!/usr/bin/env python3
"""Make a simulation-ready netlist from build/fpga_pins.v (icebox_vlog -l -s output).

Usage: python3 tools/mksim.py [build/fpga_pins.v] [build/sim/chip_sim.v]

Fixes for the u4k global-buffer quirk (docs/verification.md), which leaves three global nets undriven:
  n3  (glb2) <- new input pin_37 (GBIN, oscillator input; PLL reference via one LUT)
  n5  (glb7) <- new input sim_pll_clk (PLLOUTGLOBAL, x47/8 of pin_37; the testbench supplies it)
  n11        <- new input sim_osc_clk (IPCON slf_op_5, internal oscillator guess; only clocks the OE power-up regs)
The phantom input pin_20 is removed.
EBR address cascade (icebox_vlog ignores the RamCascade bits): ramt tiles 19_12 (CBIT 5,7), 19_10 and 19_8
(CBIT 4-7) and 19_6 (CBIT 4,6) pass ram40_19_11's WADDR/RADDR down to ram40_19_9/7/5, whose own address inputs
are unrouted (icebox shows all zero). The sim connects them to 19_11's address nets (inference from the bit pattern).
Nothing else is changed.
"""
import os
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else 'build/fpga_pins.v'
dst = sys.argv[2] if len(sys.argv) > 2 else 'build/sim/chip_sim.v'
t = open(src).read()

hdr = re.search(r'module chip \((.*?)\);', t, re.S)
assert hdr and 'input pin_20, ' in hdr.group(1), 'unexpected port list'
ports = hdr.group(1).replace('input pin_20, ', '')
ports = 'input pin_37, input sim_pll_clk, input sim_osc_clk, ' + ports
t = t[:hdr.start()] + 'module chip (' + ports + ');' + t[hdr.end():]

# ANSI ports may not be redeclared as wires (iverilog is strict): drop pin_* from the wire lists
def strip_pins(m):
    names = [x for x in m.group(1).split(', ') if not x.startswith('pin_')]
    return 'wire %s;' % ', '.join(names) if names else ''
t = re.sub(r'^wire (.*);$', strip_pins, t, flags=re.M)
assert len(re.findall(r'\bpin_20\b', t)) == 0, 'pin_20 still used'
for n in ('n3', 'n5', 'n11'):
    assert not re.search(r'assign %s\b' % n, t), n + ' already driven'

zero = '{' + ', '.join(["1'b0"] * 11) + '}'
src_addr = {}
m = re.search(r'\) ram40_19_11 \(\n  \.WADDR\((\{.*?\})\),\n  \.RADDR\((\{.*?\})\),', t)
assert m and zero not in m.groups(), 'ram40_19_11 addresses not found'
for r in ('ram40_19_5', 'ram40_19_7', 'ram40_19_9'):
    old = ') %s (\n  .WADDR(%s),\n  .RADDR(%s),' % (r, zero, zero)
    assert old in t, r + ': expected unrouted addresses'
    t = t.replace(old, ') %s (\n  .WADDR(%s),  // cascade from 19_11\n  .RADDR(%s),' % (r, m.group(1), m.group(2)))

fix = ('\n// mksim.py: u4k global fixes\nassign n3 = pin_37;\nassign n5 = sim_pll_clk;\n'
       'assign n11 = sim_osc_clk;\n')
i = t.index('\nreg ')
t = t[:i] + fix + t[i:]

os.makedirs(os.path.dirname(dst), exist_ok=True)
open(dst, 'w').write(t)
print('wrote', dst)
