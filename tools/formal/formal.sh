#!/bin/sh
# Formal equivalence check: decoded netlist (build/sim/chip_sim.v) vs. clean HDL (hdl/), all pin drivers.
# Usage: sh tools/formal/formal.sh   (regenerates build/sim/chip_sim.v, writes build/formal/)
# Flow: mkformal.py (golden LUT-loop latches, common ports) -> yosys per design (flatten, PLL removed, block RAMs cut
# into free read data + write/read obligations) -> miter of both -> clk2fflogic (every clock and async input becomes a
# sampled signal of one global step) -> AIGER -> ABC dprove (signal correspondence + induction, then other engines).
# Result is a statement about the zero-delay model only: no glitches, routing delays or metastability.
set -e
# Tools (yosys, IceStorm, iverilog, nextpnr-ice40, yosys-abc) from PATH, or set OSS_CAD=<OSS CAD Suite dir>
[ -n "$OSS_CAD" ] && PATH=$OSS_CAD/bin:$PATH
cd "$(dirname "$0")/../.."
HDL=${HDL:-hdl}
python3 tools/mksim.py build/fpga_pins.v build/sim/chip_sim.v >/dev/null
python3 tools/formal/mkformal.py build/sim/chip_sim.v build/formal
B=build/formal
CUT='proc; flatten; delete t:SB_PLL40_CORE; select -module %s t:SB_RAM40_4K; expose -evert -sep __; select -clear; opt_clean'
yosys -q -l $B/gold.log -p "read_verilog -lib +/ice40/cells_sim.v; read_verilog $B/gold.v; hierarchy -top gold;
  $(printf "$CUT" gold); rename gold gold_cut; write_verilog -noattr $B/gold_cut.v" >/dev/null 2>&1
# GATELEVEL=1: $HDL holds a synthesised core (SB_LUT4/SB_DFF* cells, feedback LUTs turned into latches by
# tools/formal/latchify.py): the cell models are read as logic, only the RAMs stay black boxes.
CELLS='read_verilog -lib +/ice40/cells_sim.v'
[ -n "$GATELEVEL" ] && CELLS='read_verilog -D NO_ICE40_DEFAULT_ASSIGNMENTS +/ice40/cells_sim.v; blackbox SB_RAM40_4K'
yosys -q -l $B/gate.log -p "$CELLS; read_verilog $B/gate.v $HDL/ode_fpga_core.v $HDL/ode_spi_slave.v $HDL/ode_cdbus.v $HDL/ode_fifo.v; hierarchy -top gate;
  $(printf "$CUT" gate); rename gate gate_cut; write_verilog -noattr $B/gate_cut.v" >/dev/null
sed -i 's/^module gold_cut/module gold/' $B/gold_cut.v
sed -i 's/^module gate_cut/module gate/' $B/gate_cut.v
yosys -q -l $B/miter.log -p "read_verilog $B/gold_cut.v $B/gate_cut.v $B/wrap.v;
  hierarchy -check; proc; miter -equiv -flatten -make_assert gold_w gate_w miter; hierarchy -top miter;
  clk2fflogic; opt_clean; setundef -zero -init; dffunmap; setundef -zero -undriven; techmap; opt -fast; abc -g AND; opt_clean;
  stat; write_aiger -zinit -map $B/miter.aig.map $B/miter.aig" >/dev/null
grep -A3 'Number of cells' $B/miter.log | tail -4 || true
# run in $B: ABC writes by-products (e.g. sm01.aig) into the current directory
(cd $B && yosys-abc -c "read_aiger miter.aig; print_stats; ${ABC:-dprove -v}") | tee $B/abc.log | tail -15
