# FZ-1 ODE FPGA: the gateware of Fixel's 3DO optical drive emulator, decoded and described

This project analyses the FPGA bitstream inside the firmware of Fixel's internal optical drive emulator (ODE) for
the Panasonic 3DO FZ-1, hardware Rev B (Raspberry Pi RP2040 + Lattice iCE5LP4K). No source for the gateware was
ever published, so the official bitstream was decoded with open-source tools and simulated. The result is a
documented description of what the FPGA does, a clean and readable HDL equivalent, and the tools to reproduce all
of it from the official firmware file. The ODE firmware ([fixel-3do-fz1-ode-decomp](https://github.com/yesmorepain/fixel-3do-fz1-ode-decomp)) and the menu disc
([fixel-3do-fz1-ode-menu-decomp](https://github.com/yesmorepain/fixel-3do-fz1-ode-menu-decomp)) are separate projects; the firmware project's
[docs/firmware.md](https://github.com/yesmorepain/fixel-3do-fz1-ode-decomp/blob/main/docs/firmware.md) ("What the FPGA does") summarises the findings that matter for
the firmware.

> **Not tested on hardware.** Every FPGA finding here comes from decoding and simulating the official bitstream.
> Nothing about the FPGA (pins, timing, behaviour, or the HDL in this project) has been measured or run on a real
> ODE or 3DO. Where this README or the docs say "equivalent" or "proved", they mean in simulation or on a
> zero-delay formal model.

> **Not affiliated with or endorsed by Fixel.** This is independent reverse-engineering work for preservation and
> interoperability. The FZ-1 ODE is out of production, and its licence was never settled ("TBD").

## What this is good for (and what it is not)

**Useful without hardware testing:**

- **A precise description of the original.** The bus protocol, buffer sizes, status flags, the 75 Hz pacing and the
  RP2040 handshake signals were read from the official bitstream and checked in simulation, not guessed. That makes
  it a reference for anyone writing a replacement drive emulator, a new ODE design, or ODE firmware.
- **Corrections and findings.** The analysis corrected earlier assumptions in the firmware documentation and found
  two timing races in the original design.
- **A readable design.** The clean HDL (about 500 lines of Verilog) is proved equivalent to the decoded original on
  a zero-delay model, so it can be read instead of the netlist.

**What still needs real hardware:**

- Simulation can show that a description matches the original bitstream. It cannot confirm the bitstream's own
  assumptions about the board: the pin roles and the timing margins against a real 3DO.
- Gateware rebuilt from the clean HDL with open-source tools has never run on an ODE. The open tools' timing
  estimate for it is well below the original's clock (see below), and the two races may resolve differently.

In short: trustworthy as a description, unproven as a drop-in replacement.

## One device, three projects

Fixel's FZ-1 ODE has three programmed parts, and each is covered by its own project. Together they describe
everything Fixel programmed into the device, layer by layer, from the menu on the TV screen down to the timing on
the console's CD-ROM bus.

```
 3DO console                                ODE board (Rev B)
┌──────────────────────┐   CD-ROM bus   ┌──────────────┐   SPI + GPIO   ┌──────────────────┐   microSD / USB
│ Menu disc (boot.iso) │ ─────────────> │ FPGA         │ ─────────────> │ RP2040 firmware  │ ─────────────> disc images
│ LaunchMe, ode driver │ <───────────── │ (gateware)   │ <───────────── │ (update.ode)     │
└──────────────────────┘  7-byte cmds,  └──────────────┘  packets,      └──────────────────┘
      menu project        status, data    FPGA project    handshakes      firmware project
```

| Project | Layer | What it explains | State |
|---|---|---|---|
| **[Menu](https://github.com/yesmorepain/fixel-3do-fz1-ode-menu-decomp)** | Software on the 3DO | What the user sees and does: browsing, the play queue, saves, updates. It reaches the ODE only through 7-byte commands sent via its `ode` driver | Rebuilds byte for byte from reconstructed C; a menu disc with a rebuilt LaunchMe has booted on an FZ-1 |
| **[FPGA](https://github.com/yesmorepain/fixel-3do-fz1-ode-fpga-decomp)** | Gateware between the console and the RP2040 | How bytes cross the 3DO bus: buffers, handshakes, status, 75 Hz pacing, timing | Decoded and documented; a clean HDL version is proved equivalent on a zero-delay model. **Not tested on hardware** |
| **[Firmware](https://github.com/yesmorepain/fixel-3do-fz1-ode-decomp)** | Software on the RP2040 | What each command means: reading disc images, answering the console, update and recovery | Rebuilds from reconstructed C, mostly byte-identical; tested on a Rev B board |

This repository is the **FPGA** project.

How they fit together:

- **Menu and firmware** share the ODE command set: the menu sends the commands, the firmware's
  `docs/commands.md` defines them. Every command the menu uses is documented on the firmware side.
- **Firmware and FPGA** share the SPI packet protocol and the GPIO handshake lines. The FPGA analysis explains what
  the firmware's FPGA accesses actually do, and corrected the firmware documentation in places (GPIO20 in CD-audio
  mode, what the GPIO22 reset clears, that the reset after configuration is required).
- **FPGA and console** share the 3DO drive bus. The FPGA's behaviour was checked against the 3DO technical guide,
  the FZ-1 service manual and the open SataTo3DO drive emulator.

What the whole adds up to: every part can be rebuilt from Fixel's official, freely available files, and each
finding is labelled by how well it is proven. That makes it a record for preserving and repairing an
out-of-production device, a reference for anyone building a replacement drive emulator or new ODE firmware, and a
safe starting point for changes.

What is still missing: the hardware design. Fixel's hardware repository is empty, so what is known about the board
comes from the bitstream, the firmware and the part markings (for example the two 12 MHz clocks). The FPGA side
also still needs confirmation on real hardware.

## Status

| Part | Status |
|---|---|
| Bitstream decoding | Complete (Project IceStorm; two decoder quirks for this device worked around, see docs/verification.md) |
| Behaviour | Pins, buffers, control and status, reset, pacing and handshakes established in simulation; checked against the FZ-1 technical guide and service manual, the open SataTo3DO drive emulator and the firmware |
| Clean HDL (`hdl/`) | Co-simulation: no differences from the decoded original apart from the two hardware races. Formal proof: all pin drivers equivalent (zero-delay model) |
| Build with open tools | Synthesises and places on the iCE5LP4K-SG48 (about 520 of 3,520 logic cells). Timing estimate 42 MHz against the original's 70.5 MHz; the decoded original gets the same estimate in the same flow. Never loaded onto hardware |
| Hardware testing | **None** |

## The FPGA in one paragraph

The FPGA sits between the 3DO's parallel CD-ROM bus and the RP2040's SPI port. It holds three buffers: 7-byte
commands from the 3DO (the RP2040 is told by GPIO21), up to 64 status bytes and up to 2048 sector bytes from the
RP2040 (offered to the 3DO with CDSTEN- and CDDTEN-). A control byte drives the media-change line and switches on
a 75 Hz pacing gate for CD audio; GPIO22 resets everything. There are no other timers and no CD logic. Details:
[docs/fpga.md](docs/fpga.md).

## Documentation

| Doc | Contents |
|---|---|
| [docs/fpga.md](docs/fpga.md) | what the FPGA does: pins, clocks, buffers, control and status, reset, lock-ups, races |
| [docs/interfaces.md](docs/interfaces.md) | signal-level behaviour and timing of the RP2040 SPI port and the 3DO CD bus |
| [docs/design.md](docs/design.md) | how the design is built inside, block by block, as in the clean HDL |
| [docs/verification.md](docs/verification.md) | how the findings were obtained and checked: simulation, formal proofs, build check |
| [hdl/README.md](hdl/README.md) | the clean HDL: files, checks, deviations from the original |
| [references/README.md](references/README.md) | the documents used and how each finding was checked against them |

## Requirements

- Python 3 (any operating system); `sympy` for `tools/ffsimp.py` only (`pip install -r requirements.txt`).
- A POSIX shell and the open FPGA tools: Project IceStorm, yosys (with `yosys-abc`), nextpnr-ice40 with iCE5LP4K
  ("u4k") support, and Icarus Verilog. The OSS CAD Suite contains all of them; put its `bin` on `PATH`, or set
  `OSS_CAD=<suite directory>`. Developed with the 2026-10-07 suite.
- Fixel's official firmware file `update.ode` rev 1.0 (not included):
  <https://github.com/fixelsan/3do-ode-firmware/releases> (145,676 bytes, sha256
  `5e98519d83c22605031a182acb6ecb3f4391aef2b922b02ec4ccb38918cf2fec`).

## Usage

```
python3 tools/extract_bitstream.py path/to/update.ode   # checks the file, writes original/fpga_bitstream.bin
sh tools/unpack.sh                                      # decode with IceStorm -> build/
sh tools/sim/run.sh cmd                                 # simulate the decoded original (spi|cmd|buf|wr|s4)
sh tools/sim/cosim.sh rnd +seed=8                       # original and clean HDL side by side (spi|cmd|buf|wr|s4|rnd)
sh tools/formal/formal.sh                               # prove the clean HDL equivalent -> "Networks are equivalent"
sh tools/build/build.sh                                 # optional: build the clean HDL with yosys + nextpnr
```

Everything generated goes to `build/`. The build writes a bitstream to `build/hw/`; it is untested, and loading it
onto an ODE in place of the official one is at your own risk and not recommended.

## Repository contents

| Path | What |
|---|---|
| `hdl/` | Clean HDL (Verilog): `ode_fpga_top.v` (pins, PLL), `ode_fpga_core.v`, `ode_spi_slave.v`, `ode_cdbus.v`, `ode_fifo.v`; `ode_fpga.pcf` (pin constraints); `README.md` |
| `tools/extract_bitstream.py` | Check the official `update.ode` and extract the bitstream |
| `tools/unpack.sh`, `tools/mksim.py` | Decode the bitstream with IceStorm; make the decoded netlist simulatable (device quirks fixed) |
| `tools/fflist.py`, `tools/ffsimp.py`, `tools/trace.py` | Inspect the decoded netlist: flip-flops and their next-state logic, net tracing |
| `tools/sim/` | Testbenches for the decoded original (`run.sh`, `tb_*.v`) and the lockstep co-simulation with the clean HDL (`cosim.sh`, `mkcosim.py`, `cosim_dump.v`) |
| `tools/eqmap.py` | Map the original's flip-flops to the clean HDL's registers from waveforms; find the first divergence |
| `tools/formal/` | Formal equivalence check (`formal.sh`, `mkformal.py`, `latchify.py`) |
| `tools/build/` | Build check with yosys + nextpnr (`build.sh`, `sweep.sh`, `clocks.py`, `mkgolden_hw.py`) |
| `docs/` | The documentation above |
| `original/`, `references/` | Placeholders: where the official file and the external documents go |

## What is not included

- Fixel's `update.ode`, the bitstream extracted from it, and anything generated from it (decoded netlists,
  waveforms, built bitstreams). `tools/extract_bitstream.py` recreates the bitstream from the official release.
- The reference documents (FZ-1 manuals and schematics, Lattice data sheet, SataTo3DO files); `references/README.md`
  lists where they come from.

## Credits

- **Fixel** (Felix Lazarev) designed the ODE, its firmware and this gateware.
- Project IceStorm, yosys, nextpnr and ABC (YosysHQ and contributors; ABC from UC Berkeley), and Icarus Verilog,
  which made decoding, simulating and checking a closed bitstream possible.
- FCare's SataTo3DO (MIT): an open implementation of the same 3DO drive protocol, used as a reference.
- 3dodev.com for preserving the FZ-1 manuals, schematics and technical guide.

## Licence

The tools in `tools/` are original work of this project and are released under the MIT licence (see `LICENSE`).
The clean HDL in `hdl/` and the design description in `docs/design.md` are a reconstruction of Fixel's design,
whose licence is "TBD"; the MIT licence does not cover them. Nothing in this repository grants any rights to
Fixel's design or firmware.
