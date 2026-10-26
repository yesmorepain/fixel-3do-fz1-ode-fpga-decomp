# Design: how the original is built inside

The internal structure of Fixel's design, at block level, as reconstructed in the clean HDL (`hdl/`, see
`hdl/README.md`). Behaviour is in [fpga.md](fpga.md) and [interfaces.md](interfaces.md); this page explains why it
behaves that way.

> **Not tested on hardware.** The structure was read from the decoded netlist and the clean HDL is proved
> equivalent to it only in simulation and on a zero-delay formal model ([verification.md](verification.md)).

> **Unofficial.** This page and `hdl/` describe Fixel's design (licence "TBD"); they are a reconstruction, not
> affiliated with or endorsed by Fixel.

## Block map

| Block | HDL module | Clock | Contents |
|---|---|---|---|
| Pins, PLL, output enables | `ode_fpga_top` | oscillator, PLL | pin mapping, PLL x 47/8, tri-state drivers |
| Core | `ode_fpga_core` | PLL | control register, status snapshot, buffer wiring, handshake outputs |
| SPI slave | `ode_spi_slave`, `ode_aload_shift` | SCK and PLL | receive shift register, bit counter, synchronisers, opcode decoder, transmit register |
| Command input | `ode_cmd_in` | PLL, gated strobe | write-strobe detector, byte counter, 0x08 rule, GPIO21 |
| 3DO reads | `ode_cd_read` | PLL (both edges) | read-strobe detector, buffer read strobes, data-bus output register and drive |
| Buffers | `ode_fifo_ptr`, `ode_ram512x8`, `ode_ram2048x8` | per buffer | pointer logic and block-RAM wrappers |
| Pacing | `ode_pacer` | oscillator | 19-bit counter and the 2048-cycle window |

## Clock domains

```
oscillator (12 MHz) -----------> pacing counter, PLL reference
PLL x47/8 (70.5 MHz) ----------> almost everything; data-bus output register on the falling edge
SPI SCK -----------------------> receive shift register (rising), bit counter and transmit register (falling)
command write strobe ----------> command buffer write side (a gated clock: strobe AND NOT GPIO21)
slow internal clock -----------> 19 output-enable flip-flops that switch the outputs on after configuration
```

Signals cross from SCK to the PLL domain through two-flip-flop synchronisers (SS and "8 bits done"); the 3DO
strobes are synchronised the same way. The pacing window goes straight into the CDDTEN- logic without a
synchroniser [sim]; CDDTEN- is an asynchronous signal to the 3DO anyway [inference].

## Buffers: one FIFO template, used three times

All three buffers use the same dual-clock FIFO pointer scheme: binary read and write pointers with one extra wrap
bit, a Gray-coded copy of each, two-flip-flop synchronisers carrying each Gray pointer to the other side, and
registered empty and full flags computed from the next pointer value. This is the textbook asynchronous FIFO
design (as in Cummings' well-known paper). It is used even for the reply and sector buffers, whose two sides both
run on the PLL clock, which is why their empty flags lag by three cycles [guess: a generated FIFO template].
Address widths: 3 bits (command), 6 (reply), 11 (sector).

- Each buffer is one block RAM (512 x 8 with only 8 or 64 addresses used), or, for the sector buffer, four block
  RAMs in 2048 x 2 mode side by side. The original feeds the four with one address through the block-RAM address
  cascade; the clean HDL wires the address to each.
- The command buffer's write side is clocked by the gated write strobe itself, which is the source of race 2.
  Its read side, and its reset at the end of every 0x01 packet, are in the PLL domain.
- The 0x01 packet reads the command RAM one step behind the bytes it shifts out, through a holding register:
  hence the stale byte before the 7 command bytes.

## Command byte counter

A one-hot shift register with eight stages counts accepted write strobes. GPIO21 is its last stage, or its
second stage when the first byte (held in an 8-bit opcode register that loads only on the first byte) is 0x08.
GPIO21 also gates the write clock, which is what stops further bytes. The counter restarts on GPIO22 or when
GPIO21 is high and the command buffer is empty. All flip-flops power up at 0, so the counter's "first byte" stage
is 0 until the first GPIO22 pulse sets it. [sim]

## SPI transmit register

iCE40 flip-flops have no asynchronous parallel load, so iCEcube2 built one per bit from three parts: a flip-flop
with asynchronous set, one with asynchronous reset, and a latch (one LUT feeding back into itself) that remembers
which of the two holds the loaded value. During the load pulse the set or reset input forces the chosen
flip-flop and the latch selects it; afterwards both flip-flops shift on falling SCK and the latch keeps
selecting. The load pulse comes one PLL cycle after "byte done" or SS falling. [sim]

The clean HDL describes this as a plain latch; the build (`tools/build/build.sh`, define `ICE40_LUT_LATCH`) uses the
same feedback LUT as the original. In zero-delay gate-level simulation that LUT loop can oscillate forever; the
gate-level simulations therefore use the latch form ([verification.md](verification.md)).

## Opcode register and ports

The first received byte of a packet is stored in an opcode register, which is set to FF on every SS edge and on
GPIO22. Five registered flags decode bits 2-0 (ports 1, 2, 4, 5, 6); all are 0 when bits 7-2 are all 1. Because
the flags are registered one cycle after the opcode arrives, and the transmit register is loaded on that same
edge, byte 1 of every packet is the status byte, and bit 4 of that byte in a 0x01 packet is race 1.

## Deviations of the clean HDL from the original

| Item | Original | Clean HDL |
|---|---|---|
| Output-enable clock | slow internal clock (IceStorm calls it SMCCLK) | the oscillator (no primitive exposes SMCCLK); effect: none after the first clock [guess] |
| Sector-RAM addressing | block-RAM address cascade | address wired to all four RAMs |
| Transmit latches | feedback LUTs | plain latches (feedback LUTs in the build) |
| 19 output-enable flip-flops | 19 copies | one register |
