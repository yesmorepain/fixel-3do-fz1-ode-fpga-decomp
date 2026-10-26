#!/bin/sh
# Lockstep co-simulation: decoded netlist (reference) vs. clean HDL (hdl/), driven by an existing testbench.
# Usage: [DUMP=1] sh tools/sim/cosim.sh [spi|cmd|s4|buf|wr|rnd] [vvp args]
# DUMP=1 adds tools/sim/cosim_dump.v (full VCD of both designs for tools/eqmap.py; +vcd=PATH).
# Builds a wrapper module `chip` (same ports as the netlist) holding both designs; the reference drives the pins,
# the clean core only listens, and every output (with its enable) is compared 1 ps after any change.
# Mismatches print "COSIM MISMATCH"; the summary line at $finish gives the count.
set -e
# Tools (yosys, IceStorm, iverilog, nextpnr-ice40, yosys-abc) from PATH, or set OSS_CAD=<OSS CAD Suite dir>
[ -n "$OSS_CAD" ] && PATH=$OSS_CAD/bin:$PATH
cd "$(dirname "$0")/../.."
HDL=${HDL:-hdl}
TB=spi; case "$1" in spi|cmd|s4|buf|wr|rnd) TB=$1; shift;; esac
python3 tools/mksim.py build/fpga_pins.v build/sim/chip_sim.v >/dev/null
sed 's/^module chip (/module chip_ref (/' build/sim/chip_sim.v > build/sim/chip_ref.v
python3 tools/sim/mkcosim.py tools/sim/tb_$TB.v build/sim/cosim_wrap.v
OUT=build/sim/cosim_$TB; EXTRA=
if [ -n "$DUMP" ]; then OUT=build/sim/cosim_${TB}_dump; EXTRA="-s cosim_dump tools/sim/cosim_dump.v"; fi
iverilog -g2012 $IVFLAGS -o $OUT -s tb -s cosim_report $EXTRA tools/sim/tb_$TB.v build/sim/cosim_wrap.v \
  build/sim/chip_ref.v $HDL/ode_fpga_core.v $HDL/ode_spi_slave.v $HDL/ode_cdbus.v $HDL/ode_fifo.v \
  "$(yosys-config --datdir)/ice40/cells_sim.v"
[ -n "$NORUN" ] && exit 0   # NORUN=1: build only (e.g. to run several seeds of $OUT in parallel)
vvp -n $OUT "$@"
