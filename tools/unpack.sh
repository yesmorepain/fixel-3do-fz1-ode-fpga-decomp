#!/bin/sh
# Unpack original/fpga_bitstream.bin into build/ with Project IceStorm (from the OSS CAD Suite).
# Usage: sh tools/unpack.sh
# Outputs (all git-ignored): fpga.asc, fpga.explain, fpga_pins.v (netlist, pin-numbered, no comments),
# fpga_pins_commented.v (same with wire/tile comments), fpga_stat.txt.
# Note: icebox reads the two u4k pad-to-global extra bits with the bank swapped (docs/verification.md), so the netlist shows glb_netwk_2 / glb_netwk_7 without a driver. icebox_asc2hlc fails on u4k.
set -e
# Tools (yosys, IceStorm, iverilog, nextpnr-ice40, yosys-abc) from PATH, or set OSS_CAD=<OSS CAD Suite dir>
[ -n "$OSS_CAD" ] && PATH=$OSS_CAD/bin:$PATH
cd "$(dirname "$0")/.."
mkdir -p build
iceunpack original/fpga_bitstream.bin build/fpga.asc
icebox_explain build/fpga.asc > build/fpga.explain
icebox_vlog -l -s build/fpga.asc > build/fpga_pins.v
icebox_vlog -l build/fpga.asc > build/fpga_pins_commented.v
icebox_stat build/fpga.asc > build/fpga_stat.txt
cat build/fpga_stat.txt
