# How the FPGA works

What the Lattice iCE5LP4K on Fixel's FZ-1 ODE (Rev B) does, as found by decoding and simulating the bitstream in the
official `update.ode` rev 1.0. The signal-level protocol and timing are in [interfaces.md](interfaces.md); how the
findings were obtained and checked is in [verification.md](verification.md).

> **Not tested on hardware.** Everything here comes from decoding the official bitstream and simulating it. None of
> it has been measured or tried on a real ODE or 3DO: not the pin roles, not the timing, not the behaviour.

Labels, as in the firmware docs: **[sim+doc]** shown in simulation and agreeing with an independent document (3DO
technical guide, FZ-1 service manual, or the open SataTo3DO drive emulator); **[sim]** shown in simulation or the
netlist only; **[inference]** derived from facts, not shown directly; **[guess]** plausible, unverified.

## What it is for

The 3DO talks to its CD-ROM drive over a parallel bus: 8 data lines plus strobes and handshakes, all timed by the
console. The RP2040 cannot serve that bus fast enough in software while it also reads the microSD card or USB
drive, so the FPGA sits between the two. It is a buffer and handshake engine, nothing more: no decoding, no CD
logic, no timers apart from one pacing counter.

```
            3DO CD bus (via level shifters)                  RP2040
   CDD0-7, CDHWR-, CDEN-, CDCMD- ---> [command FIFO 8 B] ---> SPI 0x01   GPIO21 = command ready
   CDD0-7 <--- CDHRD-, CDCMD- low <--- [reply FIFO 64 B] <--- SPI 0x02   CDSTEN- low while not empty
   CDD0-7 <--- CDHRD-, CDCMD- high <-- [sector FIFO 2 KB] <-- SPI 0x05   CDDTEN- (= GPIO20) low while not empty
   CDMDCHG <------------------------- [control register] <-- SPI 0x04   status byte: SPI 0x03 / byte 1 of any packet
                                       GPIO22 pulse: reset everything
```

## Device and clocks

| Item | Finding | Label |
|---|---|---|
| Device | iCE5LP4K, SG48 package; iCEcube2 2020.12, built Aug 19 2022 (the firmware one day later) | bitstream header |
| Loading | by the RP2040 in SPI slave mode on every boot (firmware `fpga_init`); nothing is stored on the FPGA side | firmware |
| Resources | about 472 LUTs (13 %), 312 flip-flops, 6 of 20 block RAMs, the PLL, 27 IOs | [sim] (bitstream statistics) |
| Oscillator | external, pin 37: 12 MHz. The oscillator beside the FPGA on a Rev B board (Y1) is marked "12.0", and the pacing counter wraps every 160,001 cycles, which is 1/75 s (the CD 1x sector rate) exactly at 12 MHz | marking read on the board + [sim]; that Y1 feeds pin 37: [inference] (position, not traced) |
| Main clock | PLL x 47/8 of the oscillator: 70.5 MHz (period 14.2 ns). The PLL's lock output is not used | PLL settings [sim]; 70.5 MHz follows from the 12 MHz oscillator |
| Other clocks | SPI SCK (receive, bit counter and transmit register); a low-speed internal clock that only times the power-up output enable [guess: internal oscillator] | [sim] |

## Pins

SG48 package pin numbers. 3DO signal names from the FZ-1 technical guide; direction from the FPGA's point of view.

| Pin | Signal | Dir | Function | Label |
|---|---|---|---|---|
| 6, 9, 10, 11, 12, 13, 18, 19 | CDD0 ... CDD7 | in/out | 3DO data bus | [sim+doc] |
| 48 | CDEN- | in | qualifies every 3DO strobe | [sim+doc] |
| 47 | CDHWR- | in | 3DO write strobe (command bytes) | [sim+doc] |
| 46 | CDHRD- | in | 3DO read strobe (status and data bytes) | [sim+doc] |
| 3 | CDCMD- | in | low = command/status, high = data | [sim+doc] |
| 4 | CDSTEN- | out | low = status (reply) bytes waiting | [sim+doc] |
| 44 | CDDTEN- | out | low = sector data waiting | [sim+doc] |
| 2 | CDMDCHG | out | media change; low while control bit 0 is set | [sim+doc] |
| 45 | CDWAIT- | out | constant 1 (never asserted) | [inference] |
| 14, 15, 16, 17 | SPI SO, SCK, SS, SI | out, in, in, in | RP2040 SPI1 (also the configuration port) | [sim] + firmware |
| 42 | GPIO21 | out | command ready | [sim] + firmware |
| 38 | GPIO20 | out | same signal as CDDTEN- | [sim] + firmware |
| 43 | GPIO22 | in | reset pulse (active high) | [sim] + firmware |
| 37 | oscillator | in | clock input (global buffer pin) | [sim] |
| 23, 36 | ? | out | copies of SCK; use on the board unknown | [sim] |
| 25, 34 | ? | out | constant 1; use on the board unknown | [sim] |

CDRST- (drive reset from the console) does not reach any FPGA input. The 3DO side is 5 V TTL and the FPGA's IOs
are 3.3 V, so the board must have level shifters [sim+doc: documents give the levels]; how they are wired (in
particular whether CDEN- gates the data-bus driver) is unknown without tracing the board.

## The three buffers

All three are first-in-first-out buffers in block RAM. A byte that does not fit is dropped (never overwrites
older bytes); reading an empty buffer does not move it. [sim]

| Buffer | Size | Filled by | Emptied by | Flags |
|---|---|---|---|---|
| Command | 7 bytes per command (8-byte RAM) | 3DO writes: CDHWR- with CDEN- and CDCMD- low | SPI 0x01 | GPIO21 |
| Reply | 64 bytes | SPI 0x02 | 3DO reads: CDHRD- with CDEN- and CDCMD- low | CDSTEN-, status bit 6 |
| Sector | 2048 bytes | SPI 0x05 | 3DO reads: CDHRD- with CDEN- low and CDCMD- high | CDDTEN-/GPIO20, status bits 7 and 5 |

- **Command buffer.** A byte counter allows 7 bytes, then raises GPIO21 and ignores further write strobes until the
  RP2040 has read the command. CDEN- going high between bytes does not end a command: 3 + 3 + 1 bytes make one
  command. The end of every 0x01 packet empties the buffer, read or not. [sim]
- **Opcode 0x08.** If the first byte is 0x08 (ABORT), GPIO21 rises after that byte alone, but only for one main
  clock cycle (about 14 ns), and the remaining 6 bytes are counted as a new command. The firmware's ABORT handler
  pulses GPIO22, which puts the count right. Why 0x08 is special: unknown [guess: a 1-byte abort in an older
  protocol idea]. [sim]
- **Reply and sector buffers.** Only GPIO22 empties them; two 0x02 packets simply queue. A sector longer than 2048
  bytes must be sent in two parts (the firmware waits for status bit 5 to clear). [sim]

## Control register and status byte

The control register is written by SPI 0x04 (low 4 bits kept). [sim]

| Bit | Effect |
|---|---|
| 0 | CDMDCHG low (the firmware holds 1 for 100 ms after a disc change or reset request) [sim+doc] |
| 1 | pacing: CDDTEN- may go low only in a 2048-cycle window every 160,001 oscillator cycles (170.7 µs every 1/75 s). The firmware sets it for CD audio. The 3DO can still read outside the window; only the "data waiting" signal is gated [sim; "1x CD pacing" as its purpose: inference] |
| 2, 3 | stored and echoed in the status byte, no other effect [sim] |

The status byte is what the FPGA sends back as byte 1 of every SPI packet, and for every byte of a packet whose
first byte selects no port (the firmware uses 0x03):

| Bit | Meaning |
|---|---|
| 7 | sector buffer empty |
| 6 | reply buffer empty |
| 5 | sector buffer full (exactly 2048 unread bytes) |
| 4 | 0 (but see "Races" below for byte 1 of a 0x01 packet) |
| 3-0 | control register |

Bits 7, 6 and 5 hold their previous value while a 0x04 control byte is being stored. There is no status bit for
a waiting command (that is GPIO21 only) or for reply-buffer overflow. [sim]

## Reset and power-up

- **GPIO22** (pin 43) is an asynchronous active-high reset of the data path: all three buffers, the command byte
  counter, the command opcode register and the control register. [sim]
- **Power-up.** All flip-flops start at 0, which leaves the command byte counter stopped: without one GPIO22 pulse
  after configuration, 7 command bytes are stored but GPIO21 never rises. The firmware sends that pulse, so it is
  required, not optional. [sim]
- All outputs are tri-stated until the first edge of the slow internal clock after configuration. [sim]
- **No timers or watchdogs.** Apart from the 75 Hz pacing counter there is no counter, timeout or state that grows
  with time; every state machine is event-driven. So no FPGA counter can explain a freeze after a fixed playing
  time. [sim]

## Lock-ups and how they clear

Every path that can leave the FPGA stuck is cleared by a GPIO22 pulse. [sim; likelihood on hardware: unknown]

| Situation | Effect |
|---|---|
| An SPI 0x01 read before the 7th command byte | flushes the bytes but keeps the count: the next command is mis-framed. The firmware only reads 0x01 after a GPIO21 interrupt, so it never does this |
| GPIO21 high but the command is never read (firmware loses the interrupt) | all later command bytes are ignored; no new GPIO21 edge |
| The 14 ns GPIO21 pulse of opcode 0x08 is missed | the next command completes the count; one command is lost until the ABORT handler's GPIO22 |
| GPIO22 while the 3DO is writing a command | the remaining bytes count as a new command |

## Races (timing-dependent behaviour)

Two places depend on the exact order of signals arriving on the same clock edge. On hardware, routing delays decide
the outcome; simulation cannot. [sim]

1. **Bit 4 of byte 1 of a 0x01 packet** can be status bit 4 (0) or bit 4 of the stale byte that follows it. The
   firmware ignores this byte.
2. **Command write clock.** The command buffer's write clock is the write strobe gated by "not GPIO21". If a 3DO
   write strobe ends on the clock edge where GPIO21 falls, the clock can glitch and store a byte that was not
   counted, shifting the next command. Seen in random simulations (seeds 1 and 4); how often it can happen with a
   real 3DO: unknown.
