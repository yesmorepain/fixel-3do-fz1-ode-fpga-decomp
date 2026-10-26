# Interfaces: the RP2040 SPI port and the 3DO CD bus

Signal-level behaviour and timing of the FPGA's two sides. What the blocks do is in [fpga.md](fpga.md). Pin numbers
are SG48 package pins (table in fpga.md). Times use the 12 MHz oscillator (marked "12.0" on the board; see fpga.md), i.e. a 70.5 MHz
main clock (14.2 ns per cycle).

> **Not tested on hardware.** All of this comes from simulating the decoded official bitstream. Times are
> zero-delay simulation figures in main-clock cycles: real pad, routing and level-shifter delays come on top.

Labels: **[sim+doc]**, **[sim]**, **[inference]**, **[guess]** as in [fpga.md](fpga.md).

## A complete command, end to end

```
3DO                         FPGA                                   RP2040 (firmware)
CDHWR- x7 (CDEN-, CDCMD- low) -> command buffer; 7th byte: GPIO21 high -> IRQ
                                                                    SPI 0x01: reads the 7 bytes
                               end of 0x01 packet: buffer emptied,
                               GPIO21 low
                                                                    data command: waits for GPIO20 high,
                                                                    SPI 0x05: up to 2048 bytes
                               end of 0x05 packet: CDDTEN- low   <-
CDHRD- x n (CDCMD- high)    <- sector bytes; last byte: CDDTEN- high
                                                                    SPI 0x02: reply (status) bytes
                               end of 0x02 packet: CDSTEN- low   <-
CDHRD- x n (CDCMD- low)     <- reply bytes; last byte: CDSTEN- high
```

The order of the data and reply phases is the firmware's choice (firmware `docs/commands.md`); the FPGA treats the
three buffers independently. [sim]

## RP2040 side: SPI packets

SPI mode 0, MSB first, SS (pin 16) low for the whole packet. The FPGA samples SI on rising SCK and changes SO on
falling SCK. The first byte of a packet is the opcode; only its bits 2-0 select a port, and an opcode with bits 7-2
all set (0xFC-0xFF) selects none. [sim]

| Opcode bits 2-0 | Firmware sends | Port | Bytes after the opcode |
|---|---|---|---|
| 001 | 0x01 | command read | SO returns: stale byte, the 7 command bytes, 00 (see below) |
| 010 | 0x02 | reply write | up to 64 reply bytes into the reply buffer |
| 100 | 0x04 | control write | each byte is stored in the control register (low 4 bits); the last one counts |
| 101 | 0x05 | sector write | up to 2048 bytes into the sector buffer |
| 110 | (0x0E once after configuration) | none in effect | SO returns 00 |
| other | 0x03, 0x00 | none | SO returns the status byte for every byte |

So 0x09 would act like 0x01, for example; the firmware only uses the values in the second column. [sim]

**SO.** The byte shifted out during byte 1 of every packet is the status byte (fpga.md), because the transmit
register is loaded at SS falling, before the opcode is known. After each byte the next transmit byte is loaded
from the port: for 0x01 the command bytes, for no port the status byte again. [sim]

**0x01 layout.** 10 bytes back: `[status] [stale] [cmd0] ... [cmd6] [00]`. The stale byte is the last byte read
in the previous 0x01 packet (00 after power-up), because the command bytes come out one read step late. The end
of the packet (SS high) empties the command buffer and drops GPIO21 if it has not already fallen. [sim; matches
the firmware's use of bytes 2-8 [sim+doc]]

**Byte gap.** The transmit load and the bit-counter restart happen 2-3 main-clock cycles (28-43 ns) after the 8th
falling SCK edge, so the next byte's first rising SCK edge must come later than that. In simulation any idle gap
of 12 ns or more between bytes gives stable reads at 2.5-31 MHz SCK. In SPI mode 0 the RP2040's SPI block pauses SCK
between back-to-back bytes (RP2040 datasheet 4.4.3.10; the firmware drives SS as a plain GPIO), and its real rate is 20.83 MHz (125 MHz / 6) rather than the 30 MHz the firmware asks for. [sim; rate
calculated from the SDK's default 125 MHz clock, which the board's 12 MHz RP2040 crystal (marked "120") gives;
gap: datasheet; its length (about one SCK period) not measured]

**0x00 end marker.** Selects no port and changes nothing. [sim]

### GPIO lines

| Line | Pin | Behaviour |
|---|---|---|
| GPIO21 | 42 | level. High from the 7th accepted command byte (or a one-cycle pulse for opcode 0x08) until the 0x01 packet has read the buffer empty. While high, command write strobes are ignored [sim] |
| GPIO20 | 38 | the same signal as CDDTEN-. High = sector buffer empty, or a 0x05 packet in progress, or (control bit 1) outside the 75 Hz window even with unread data [sim]. The firmware reads high as "can take a sector"; that holds only with control bit 1 clear [sim] |
| GPIO22 | 43 | input. A high level resets the data path asynchronously (fpga.md "Reset and power-up"). The firmware pulses it for 10 µs [sim+doc] |

## 3DO side: the CD bus

The console drives CDEN-, CDCMD-, CDHWR- and CDHRD-; all are active low. The FPGA synchronises CDHWR- and CDHRD-
with two flip-flops on the main clock and acts on their falling edge. CDEN- and CDCMD- are sampled directly at that
moment, without synchronisation. [sim]

### Command writes (CDHWR-)

- A write is accepted when the synchronised CDHWR- falls while CDEN- and CDCMD- are low and GPIO21 is low. The
  edge is detected 2-3 main-clock cycles (28-43 ns) after the pin falls; CDD0-7 is stored at that moment, so the
  data must be valid by then and stay valid for at least one more cycle. The technical guide's strobes are
  0.2-0.3 µs wide, a large margin. [sim; strobe width doc]
- CDHWR- must be high for at least two main-clock cycles between strobes for the next falling edge to be seen.
  [sim]
- CDEN- going high between bytes does not end a command (bytes are counted, not framed). [sim]

### Status and data reads (CDHRD-)

- CDCMD- selects the buffer: low = reply (status) bytes, high = sector data. CDEN- must be low for the read
  pointer to step. [sim]
- The FPGA drives CDD0-7 from about 2 main-clock cycles (~30 ns) after CDHRD- falls until about 2 cycles after it
  rises, **whatever CDEN- is**. The output register updates on the falling main-clock edge from the buffer that
  CDCMD- selects at that moment. Whether the board's level shifter adds a CDEN- gate is unknown (SataTo3DO gates
  its bus driver with CDEN-). [sim; difference to SataTo3DO sim+doc]
- Reading an empty buffer returns the byte at the read position (old data, or 00 if never written) and does not
  step. [sim]

### Handshake outputs

| Output | Low when | Goes high |
|---|---|---|
| CDSTEN- (pin 4) | the reply buffer holds bytes and no 0x02 packet is in progress | when the 3DO reads the last reply byte, or while a new 0x02 packet arrives [sim+doc] |
| CDDTEN- (pin 44) | the sector buffer holds bytes, no 0x05 packet is in progress, and (control bit 1) the 75 Hz window is open | when the 3DO reads the last byte, during every 0x05 packet, outside the window in audio mode [sim+doc] |
| CDMDCHG (pin 2) | control bit 0 is set | when control bit 0 is cleared (firmware: after 100 ms) [sim+doc] |
| CDWAIT- (pin 45) | never | constant 1 [inference] |

The empty flags follow a buffer change by about 3 main-clock cycles (pointer synchronisation), so CDSTEN- and
CDDTEN- go high about 40 ns after the 3DO's last read is detected. Neither depends on CDEN-. [sim]

**75 Hz window.** With control bit 1, CDDTEN- may only go low during the first 2048 oscillator cycles (170.7 µs)
of every 160,001-cycle period (13.33 ms = 1/75 s): at most one "data waiting" opening per CD frame
time, i.e. 1x real-time pacing. The 3DO can still read bytes outside the window. [sim; 1x meaning
inference]

## Power-up sequence (firmware and FPGA)

```
RP2040: CRESET_B low 1 ms, bitstream over SPI1 at 2.4 MHz, extra clocks      (firmware fpga_init)
FPGA:   configuration done (CDONE high); outputs tri-state, then enabled on the first slow-clock edge
RP2040: SPI1 to "30 MHz" (20.83 MHz), bytes 0e 03, GPIO22 10 µs pulse
FPGA:   GPIO22 starts the command byte counter; buffers empty: status c0, CDSTEN-/CDDTEN- high
```

Without the GPIO22 pulse the FPGA stores 7 command bytes but never raises GPIO21. [sim]
