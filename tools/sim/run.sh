#!/bin/sh
# Build the simulation netlist and run a testbench. Usage: sh tools/sim/run.sh [spi|cmd|s4|buf|wr] [+vcd]
# tb_spi: RP2040 SPI ports only; tb_cmd: 3DO-side command write/status/data read; tb_s4: control bits, 75 Hz window, GPIO20; tb_wr: command byte counter, GPIO21, read side. IVFLAGS="-P tb.X=.." overrides.
set -e
# Tools (yosys, IceStorm, iverilog, nextpnr-ice40, yosys-abc) from PATH, or set OSS_CAD=<OSS CAD Suite dir>
[ -n "$OSS_CAD" ] && PATH=$OSS_CAD/bin:$PATH
cd "$(dirname "$0")/../.."
TB=spi; case "$1" in spi|cmd|s4|buf|wr) TB=$1; shift;; esac
python3 tools/mksim.py build/fpga_pins.v build/sim/chip_sim.v
iverilog -g2012 $IVFLAGS -o build/sim/tb_$TB -s tb tools/sim/tb_$TB.v build/sim/chip_sim.v \
  "$(yosys-config --datdir)/ice40/cells_sim.v"
vvp -n build/sim/tb_$TB "$@"
