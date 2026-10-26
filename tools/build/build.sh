#!/bin/sh
# Build check of the clean HDL: yosys synth_ice40 + nextpnr-ice40 (iCE5LP4K "u4k", SG48) + icepack.
# Usage: sh tools/build/build.sh   -> build/hw/ (ode_fpga.json, .asc, .bin, logs)
#        GOLDEN=1 sh tools/build/build.sh -> build/hw_golden/: the decoded netlist through the same flow (timing
#        yardstick; needs build/formal/gold.v from tools/formal/formal.sh)
#        NEXTPNR_ARGS="--seed 2 ...", YOSYS_ARGS="-device u ..." pass extra options; OUT=dir overrides the output dir.
#        Defaults: the best of tools/build/sweep.sh 2026-10-26 (yosys -device u -nocarry, nextpnr
#        --placer-heap-timingweight 25 --seed 9). tools/build/sweep.sh tries a grid of these options (tool settings only; the HDL is not changed).
# --ignore-loops: the 8 transmit-load latches are LUT loops, as in the original. --timing-allow-fail: the bitstream
# is written even if the timing estimate misses the 70.5 MHz target (12 MHz oscillator x 47/8).
# NOT TESTED ON HARDWARE. The bitstream is derived from Fixel's design: private, and not to be loaded on an ODE
# in place of the official one. Timing figures are nextpnr estimates.
set -e
# Tools (yosys, IceStorm, iverilog, nextpnr-ice40, yosys-abc) from PATH, or set OSS_CAD=<OSS CAD Suite dir>
[ -n "$OSS_CAD" ] && PATH=$OSS_CAD/bin:$PATH
cd "$(dirname "$0")/../.."
if [ -n "$GOLDEN" ]; then
  B=${OUT:-build/hw_golden}; mkdir -p $B
  python3 tools/build/mkgolden_hw.py build/formal/gold.v $B/golden.v >/dev/null
  SRC="$B/golden.v"; TOP=golden_top
else
  B=${OUT:-build/hw}; mkdir -p $B
  SRC="-DICE40_LUT_LATCH hdl/ode_fpga_top.v hdl/ode_fpga_core.v hdl/ode_spi_slave.v hdl/ode_cdbus.v hdl/ode_fifo.v"
  TOP=ode_fpga_top
fi
yosys -q -l $B/yosys.log -p "read_verilog $SRC; synth_ice40 ${YOSYS_ARGS--device u -nocarry} -top $TOP -json $B/ode_fpga.json" >/dev/null 2>&1 ||
  { grep -A3 ERROR $B/yosys.log; exit 1; }
nextpnr-ice40 --u4k --package sg48 --pcf hdl/ode_fpga.pcf --json $B/ode_fpga.json --asc $B/ode_fpga.asc \
  --ignore-loops --timing-allow-fail --pre-pack tools/build/clocks.py -l $B/nextpnr.log ${NEXTPNR_ARGS---placer-heap-timingweight 25 --seed 9} >/dev/null 2>&1 ||
  { grep -E 'ERROR' $B/nextpnr.log | tail -5; exit 1; }
icepack $B/ode_fpga.asc $B/ode_fpga.bin
echo "$B:"
grep -A8 'Device utilisation' $B/nextpnr.log | tail -7 | grep -E 'ICESTORM_(LC|RAM|PLL)|SB_IO|SB_GB'
grep -E 'Max frequency for clock' $B/nextpnr.log | tail -4
