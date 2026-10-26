# How the findings were obtained and checked

From the official `update.ode` to a decoded netlist, simulations, a clean HDL description, formal equivalence
proofs and a build check. The tools are in `tools/`; generated output goes to `build/` (not kept in the repository).

> **Not tested on hardware.** Every check on this page is a simulation, a proof on a zero-delay model, or a tool
> estimate. "Equivalent" below always means equivalent in that model. Nothing has run on a real ODE or 3DO.

## Pipeline

```
update.ode rev 1.0 ── tools/extract_bitstream.py ──> original/fpga_bitstream.bin (71,338 B, hashes checked)
      ── tools/unpack.sh (IceStorm: iceunpack, icebox_vlog, icebox_explain) ──> build/fpga.asc, fpga_pins.v
      ── tools/mksim.py (two fixes, below) ──> build/sim/chip_sim.v: the simulatable reference netlist
      ── testbenches tools/sim/tb_*.v (run.sh) ──> behaviour, pin roles, timing         [fpga.md, interfaces.md]
      ── clean HDL hdl/ ── co-simulation, register map, formal proof, build check       [this page]
```

Tool set: OSS CAD Suite 2026-10-07 (yosys 0.69, nextpnr-ice40 with u4k support, IceStorm, Icarus Verilog, ABC).

## Decoding the bitstream

- The file offset of the bitstream inside `update.ode` and its hash are fixed; `extract_bitstream.py` checks both
  the input and the output SHA-256.
- IceStorm reads the iCE5LP4K ("u4k") bitstream, with one quirk: two global-buffer connections come out swapped
  (iCEcube2 and IceStorm disagree on which extra bit is which), so the netlist shows the oscillator and PLL
  global nets as undriven and an input on unused pin 20. `mksim.py` reconnects them (oscillator -> its global,
  PLL output -> main clock) and removes the phantom input. Strong inference from nextpnr test builds.
- IceStorm also ignores the block-RAM address cascade bits, which leaves three sector RAMs with zero addresses.
  `mksim.py` wires them to the cascade source; confirmed by reading back 2048 bytes in order.
- `tools/fflist.py`, `ffsimp.py` and `trace.py` list flip-flops with their simplified next-state logic and trace
  nets backwards and forwards; the findings in these docs were made with these and the testbenches.

## Testbenches (reference netlist)

| Testbench | Covers |
|---|---|
| `tb_spi.v` | SPI ports, status byte, control register, 2048-byte sector write |
| `tb_cmd.v` | 3DO command writes, status and data reads, pin roles |
| `tb_buf.v` | buffer pointers, empty/full flags, overflow |
| `tb_wr.v` | command byte counter, opcode 0x08, GPIO21, read-side timing |
| `tb_s4.v` | control bits, 75 Hz window, GPIO20 (longer, ~40 s) |
| `tb_rnd.v` | random SPI packets, 3DO bus operations and GPIO22 pulses (`+seed=N`) |

Clocks: 12 MHz oscillator (marked on the board), 70.5 MHz PLL, 1 MHz slow internal clock (a guess; it only times the
output enable).

## Clean HDL and co-simulation

The clean HDL (`hdl/`, Verilog, about 500 lines) describes the same design readably; its block structure is in
[design.md](design.md). `tools/sim/cosim.sh TB` runs a testbench with the reference netlist driving the pins and
the clean core alongside it, and compares every pin driver (value and enable) after each change.

- Result: 0 mismatches on all testbenches and random seeds, except the two hardware races ([fpga.md](fpga.md)).
  Race 1 is classified automatically; race 2 shows up as mismatches in random seeds 1 and 4, traced to the
  command write clock.
- The comparator was checked by deliberately breaking the clean HDL (wrong reply depth, no 0x08 rule, no status
  hold): each change was caught.
- `DUMP=1` writes a full waveform of both designs; `HDL=dir` runs a modified copy; `NORUN=1` builds only, so
  several seeds can run in parallel.

## Register map

`tools/eqmap.py` matches every flip-flop and latch of the reference netlist to a register bit of the clean HDL with
the same (or inverted) value history over several waveforms. 318 of 330 match. The rest are the transmit-register
set/reset flip-flops, which differ only in states that are never selected, and the race-1 latch. 32 never change
in any test (output enables, upper sector-pointer bits, the pacing counter's top bit), so simulation cannot pair
them; the formal proof does not need the map. `--check` finds the first register where two designs diverge, which
is how race 2 was traced.

## Formal equivalence

`tools/formal/formal.sh` proves that every pin driver of the clean HDL equals the reference netlist's, for every
possible input sequence:

- The reference netlist's eight feedback-LUT latches are rewritten as latches after checking each LUT's truth
  table (`mkformal.py`).
- The block RAMs are cut out: their inputs (write event, address, data, read event, address, clocks) must be equal
  in both designs, and their outputs become shared free inputs. The PLL is removed; its output and every other
  clock and asynchronous input are free inputs.
- yosys builds a miter of both designs and converts all clocks, asynchronous resets and latches into one global
  step (`clk2fflogic`); ABC's `dprove` (register correspondence plus induction) proves the miter's output is never
  1.
- Assumptions: every flip-flop and latch starts at 0 (iCE40 flip-flops do; the original's feedback-LUT latches
  have an unknown power-up value until the first SPI byte loads them); zero delay, so no glitches, routing delays
  or metastability. That is why neither race is covered by the proof.
- Result: equivalent, in under a second. Check of the check: 8 deliberate one-line changes (0x08 rule, status
  hold, port-6 byte, CDMDCHG, two read strobes, reply data and write enable) are all found not equivalent; a change
  to the pacing counter is undecided (160,000-cycle depth).

## Build check

`tools/build/build.sh` synthesises the clean HDL with yosys and places and routes it with nextpnr for the
iCE5LP4K-SG48 (`hdl/ode_fpga.pcf`), then packs a bitstream. It fits: about 503-522 of 3,520 logic cells, 6 block
RAMs, the PLL, 28 IOs. The bitstream has never been loaded onto anything.

- **Timing estimate.** nextpnr reports at best 42.3 MHz for the main clock against the 70.5 MHz the original runs
  at. `tools/build/sweep.sh` tried 128 tool-setting combinations; the original netlist, put through the same flow
  (`GOLDEN=1`), reaches 42.1 MHz, so the clean HDL is not slower than the original logic. The original as built by
  iCEcube2 reaches about 65 MHz on its slowest path in IceStorm's conservative timing model: iCEcube2's synthesis
  arranged the logic in fewer levels. Closing the gap would mean restructuring the HDL, which was not done, to
  keep it faithful.
- **Synthesis check.** The synthesised gate netlist is proved equivalent to the original in the same formal flow
  (`GATELEVEL=1`; `latchify.py` turns its feedback LUTs back into latches), with 3 deliberate gate changes caught,
  and passes the co-simulations (random seeds as the RTL, race 2 included). Place and route does not change logic
  and was not checked separately.

## What remains unknown without hardware

- That the 12 MHz oscillator marked on the board really feeds pin 37 (its position says so; not traced). The
  frequency itself agrees with the 75 Hz counter.
- The board around the FPGA: level shifters, whether CDEN- gates the data-bus driver, what pins 23, 25, 34 and 36
  drive, the CDRST- path.
- How the two races resolve on real silicon, and whether the RP2040 always catches the 14 ns GPIO21 pulse.
- Whether a bitstream built from the clean HDL by open tools meets timing on the board.
