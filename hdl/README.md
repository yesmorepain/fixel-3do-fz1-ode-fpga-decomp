# Clean HDL of the FZ-1 ODE FPGA

**NOT TESTED ON HARDWARE.** Nothing here has run on an ODE; a test bitstream has been built but never loaded. Every
check below was done in simulation or on a formal model of the zero-delay netlist. Unofficial reconstruction of
Fixel's design (licence "TBD"); not affiliated with or endorsed by Fixel. Background: docs/.

## Block map

| File | Module | What it does |
|---|---|---|
| ode_fpga_top.v | ode_fpga_top | SG48 pins, PLL (osc x 47/8), output enables, pins 23/36 = SCK copy, 25/34/45 = 1 |
| ode_fpga_core.v | ode_fpga_core | control register + status snapshot, the three FIFOs, H register, handshake outputs |
| ode_spi_slave.v | ode_spi_slave | SPI mode 0 receive, port decoder (0x01-0x06), transmit register |
| | ode_aload_shift | transmit shift register with async load (set-FF / clear-FF / latch per bit, as iCEcube2 builds it) |
| ode_cdbus.v | ode_cmd_in | 3DO command writes: byte counter, 0x08 rule, GPIO21 |
| | ode_cd_read | 3DO reads: CDHRD- sync, FIFO read strobes, CDD output register and drive |
| ode_fifo.v | ode_fifo_ptr | dual-clock FIFO pointers (binary + Gray, 2-FF sync), depth 8 / 64 / 2048 |
| | ode_ram512x8, ode_ram2048x8 | SB_RAM40_4K wrappers |
| | ode_pacer | 75 Hz window (160,001 osc cycles, 2048-cycle window) |

## Checks (simulation and formal model only)

- Co-simulation, `sh tools/sim/cosim.sh [spi|cmd|buf|wr|s4|rnd]`: pin drivers of netlist and clean core compared
  after every change. 0 mismatches except the races below.
- Register map, `python3 tools/eqmap.py VCD...` (VCDs from `DUMP=1 sh tools/sim/cosim.sh TB +vcd=PATH`):
  318 of 330 golden FFs/latches have a clean register bit with an identical or inverted history. The other 12 are
  the transmit set/clear FFs and the bit-4 latch: they differ only in states that are not selected (don't-care) or
  in the bit-4 race. 32 golden FFs never change in any test (19 OE regs = oe_ready; sector read-pointer MSBs,
  pacer bit 18), so their pairing is not determined by simulation.
- Formal, `sh tools/formal/formal.sh`: ABC `dprove` proves every pin driver (enable and value) equal for all input
  sequences, with all clocks and async inputs free (yosys clk2fflogic, one global step). It does not need the
  register map. Assumptions: all FFs and latches start at 0 (iCE40 FFs do; the golden LUT-loop latches have an
  unknown power-up value); block RAMs are cut-points (their write event, address, data, read event, address and
  clocks are proved equal, then their read data are shared inputs); zero-delay model, so no glitches, routing
  delays or metastability. Mutation check: 8 single-line changes (0x08 rule, status hold, port-6 byte, CDMDCHG,
  two read-strobe changes, reply RAM data and write enable) are all found NOT EQUIVALENT; a pacer change is UNDECIDED
  (160,000-cycle counter, too deep for BMC).

## Build (yosys + nextpnr; no hardware)

`sh tools/build/build.sh` -> build/hw/ode_fpga.bin (private; never load it on an ODE in place of the official one).
Pins: hdl/ode_fpga.pcf. The 8 transmit-load latches are built as feedback LUTs like the original
(`-DICE40_LUT_LATCH`; simulation and formal use the plain latch), so nextpnr runs with `--ignore-loops`.
Result 2026-10-26: fits (about 503-522 of 3520 logic cells, 6/20 RAMs, the PLL, 28 IOs). nextpnr timing estimate
for the PLL clock: 42.3 MHz at best against a 70.5 MHz target (12 MHz oscillator x 47/8).
`tools/build/sweep.sh` (128 builds, tool settings only) gets the original netlist (`GOLDEN=1`) to 42.1 MHz in the
same flow, so the clean HDL is not slower than the original logic. The original as placed by iCEcube2 reaches about
65 MHz on its slowest path in icetime's conservative model: the difference is how the synthesiser structured the
logic. Closing it would need restructuring the HDL, which was not done (the HDL stays faithful). Post-synthesis gate
netlists (build/hw/postsyn, postsyn_nc) pass the co-sim: 0 mismatches apart from race 2 (random seed 1, same as
the RTL). Gate-level sims use the latchified netlist (build/hw/postsyn_nc_formal): with the feedback LUTs the
zero-delay LUT model can oscillate forever (simulation artefact, docs/design.md). The build-default one is also proved
equivalent to the original netlist: `GATELEVEL=1 HDL=build/hw/postsyn_nc_formal sh tools/formal/formal.sh`
(feedback LUTs turned back into latches by tools/formal/latchify.py; zero-delay model; 3 gate mutants caught).

## Deviations from the original

- Output-enable power-up registers: the original clocks them from an internal clock IceStorm calls SMCCLK; the
  top uses the oscillator (no primitive exposes SMCCLK). Effect (guess): none after the first clock.
- 2048-byte RAM: the original passes addresses through the EBR cascade; the wrapper wires the address to all four
  RAMs (equivalent in simulation and as formal cut-points).
- Transmit-load latches: plain latches in the HDL; the build uses feedback LUTs (`ICE40_LUT_LATCH`), as the original.
- Power-up values: the clean registers have explicit `= 0` initialisers matching iCE40 FFs.

## Hardware races (not differences between the two designs)

Both appear only with real delays; in the zero-delay models the evaluation order decides, so the formal proof
covers neither.
1. SO bit 4 of the byte after a 0x01 opcode: the transmit load ends on the clock edge that sets the port flag
   (status bit 4 = 0 vs. H bit 4). The firmware ignores that byte.
2. Gated command-FIFO write clock (strobe & !GPIO21): if a 3DO strobe ends on the edge where GPIO21 drops, the
   clock can glitch and step the write pointer without a counted byte (co-sim seeds 1 and 4).

Note: the co-sim comparator does not label race 2 itself; seeds 1 and 4 report its SO mismatches as plain
mismatches.
