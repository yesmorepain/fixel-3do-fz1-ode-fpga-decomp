Local reference material (not redistributed): what was used and where it came from.
Fetched 2026-10-25.

## Files

- `3dodev/` from https://3dodev.com/documentation/manuals_and_schematics (base URL
  https://3dodev.com/_media/documentation/): `schematics/panasonic_fz-1_-_schematic_1_of_2.png`, `..._2_of_2.png`,
  `schematics/panasonic_fz-1_-_cd-rom_test_points.png`, `manuals/panasonic_fz-1_-_service_manual.pdf`,
  `manuals/panasonic_fz-1_-_service_manual_supplement_-_main_logic_board_and_cd-rom_drive.pdf`,
  `manuals/panasonic_fz-1_-_technical_guide_us.pdf` (section 4-3-2 = CD-ROM connector; Appendix A = expansion bus).
- `sata23do/` from https://github.com/FCare/SataTo3DO (branch main, MIT): `src/interfaces/3DO.c`, `*.pio`,
  `include/interfaces/3DO.h`, `interface_explanation_note_from_fixel` (ODE command API: 0x93, 0xc0-0xf0; no
  hardware info), `PCB/*.zip` (EAGLE sch/brd + schematics.pdf; unzipped copies in build/pcb/).
- `lattice/` from https://www.latticesemi.com/iCE40UltraFamily (downloaded 2026-10-25):
  `FPGA_DS_02028_2_7_iCE40_Ultra_Family_Data_Sheet.pdf` (FPGA-DS-02028 v2.7, Oct 2023, 49 pp, sha256 34bd7fd7...)
  and `FPGA-SC-02027-4-0-iCE5LP-4K-Pinout.xlsx` (FPGA-SC-02027 v4.0, iCE5LP4K; sha256 55f03985...). The pinout's
  SG48 column agrees with IceStorm's `u4k-sg48` pinloc for all 37 IO pins (a/b = z 0/1, edge order).
- Pages read but not saved (text only): https://3dodev.com/documentation/hardware/opera/cdrom (pinout table below,
  no timing), .../opera/xbus (generic expansion bus STB-/CMD-/SEL-/WR-; links patent WO09416382A1; nothing
  CD-specific). Further links on the cdrom page: Portfolio 2.5 cdrom.h, Wikipedia "Panasonic CD interface",
  chiark panasoniccd notes, FreeBSD matcd driver.

## 3DO CD-ROM drive connector (30-pin FFC, Molex 52045-3045 on SataTo3DO)

Names: FZ-1 US technical guide 4-3-2 (via 3dodev cdrom page); same names/pins in the SataTo3DO EAGLE netlist.
Direction ("in" = into the drive/ODE): from SataTo3DO 3DO.c/3DO.h (gpio directions, PIO programs). The
technical guide gives no directions. Even pins 3-17, 19, 21, 24, 27, 29 = GND.

| Pin | Signal  | Dir  | Meaning (guide)          | Use in SataTo3DO |
|-----|---------|------|--------------------------|------------------|
| 1   | CDRST-  | in   | reset for drive          | low = held in reset |
| 2   | CDMDCHG | out  | media change             | pulsed around reset / disc change |
| 4   | CDCMD-  | in   | data / command-          | sampled with each written byte (low = command) |
| 6   | CDSTEN- | out  | status valid             | low while status bytes are offered; each byte read by a CDHRD- pulse |
| 8   | CDDTEN- | out  | data chunk valid         | low while sector data is offered (also CDHRD- strobed) |
| 10  | CDWAIT- | out  | wait                     | held 1 (never used) |
| 12  | CDHRD-  | in   | read strobe              | drive puts a byte on CDD while low |
| 14  | CDHWR-  | in   | write strobe             | drive samples CDD while low (only if CDEN- low) |
| 16  | CDEN-   | in   | enable CD-ROM access     | bus valid for the drive only while low; also enables the '245 |
| 18,20,22,23,25,26,28,30 | CDD7..CDD0 | bidir | data bus | |

Level shifting (SataTo3DO v1.2): 74x245 on CDD0-7 (G = CDEN-, DIR from a Pico GPIO), 4-channel level shifters on
the control lines. So the bus is 5 V on the console side (inference from the shifters).

FPGA pin roles found by simulation (docs/fpga.md): CDEN- 48, CDHWR- 47, CDHRD- 46, CDCMD- 3, CDD0-7 =
6, 9, 10, 11, 12, 13, 18, 19, CDSTEN- 4, CDDTEN- 44, CDMDCHG 2, CDWAIT- 45 (constant 1, guess). CDRST- does not
reach an FPGA input. RP2040 side: GPIO21 = 42, GPIO20 = 38, GPIO22 = 43.

## iCE5LP4K SG48 IO banks (from the Lattice pinout xlsx)

- Bank 0 (top, VCCIO_0 pin 33): 23, 25, 26, 27, 28, 31, 32, 34, 35 (G0), 36, 37 (G1), 38, 42, 43; RGB0-2 = 41, 40, 39.
- Bank 1 (bottom right, SPI_Vccio1 pin 22; config SPI): 6, 9, 10, 11, 12, 13, 14 SO, 15 SCK, 16 SS, 17 SI, 18, 19,
  20 (G3), 21; CDONE 7, CRESET_B 8.
- Bank 2 (bottom left, VCCIO_2 pin 1): 2, 3, 4, 44 (G6), 45, 46, 47, 48.
- Used pins by bank: bank 1 = SPI + the 8-bit bus (6, 9-13, 18, 19); bank 2 = 2, 3, 4, 44, 45, 46, 47, 48 (the
  candidate 3DO control lines); bank 0 = 23, 25, 34, 36, 38, 42, 43 (incl. the SCK copies and the reset input 43).
  Bank 1 shares VCCIO with the RP2040 config SPI, so the bus pins are likely 3.3 V with external level shifting
  (inference, as on SataTo3DO).

## Findings checked against the documents (2026-10-25)

Sources: SM = FZ-1 service manual (IC600 pin table p.2-22, CN820 table p.2-24); SUP = supplement p.7 schematic
(CN620, R620-R628 100 ohm, RA620/621 220 ohm x4, 4.8 V scope traces); TG = technical guide 4-6/4-7 (pinout) and
5-1-8 p.41 (CD-ROM drive check waveforms); DS = Lattice FPGA-DS-02028; XL = iCE5LP4K pinout xlsx; FW = firmware
source/src (piode2.h, cdrom.c, fpga.c); S3 = SataTo3DO 3DO.c/3DO.h/*.pio.

| Finding | Document evidence | Status |
|---|---|---|
| Connector pinout + names | SM CN820, TG 4-7, SUP CN620, S3 netlist all agree | documented |
| Directions (console out: CDRST-, CDCMD-, CDHRD-, CDHWR-, CDEN-; in: CDMDCHG, CDSTEN-, CDDTEN-, CDWAIT-; CDD bidir) | SM CN820 + IC600 table | documented |
| All strobes/enables active low | `-`/`#` suffixes (SM, SUP); TG p.41 waveforms drawn low-going | documented |
| Console side is 5 V TTL, FPGA IO max 3.6 V -> external level shifting needed | SM "TTL", SUP traces 0-4.8 V; DS abs max 3.60 V, LVCMOS 1.8/2.5/3.3 only | documented |
| Console inputs have pull-ups (FPGA may tri-state) | SM IC600 "w/Pull-up" on CDD0-7, CDWAIT-, CDDTEN-, CDSTEN-, CDMDCHG | documented |
| pin 47 = CDHWR-, 46 = CDHRD-, 48 = CDEN-, 3 = CDCMD- | names/directions documented; FPGA pin roles from sim (strobe qualifies with pin 48 low; pin 3 low = command, as TG "Data/Command-") | sim + docs consistent |
| CDD0-7 = pins 6, 9, 10, 11, 12, 13, 18, 19 | sim: SPI bit k <-> pin; FW interprets SPI bytes as 3DO opcodes on working hardware, so SPI bit k = CDDk. All 8 bits tested both ways | sim + FW |
| Strobe width 0.2-0.3 us, in groups | TG p.41; FPGA syncs strobes with 2 FFs at the PLL clock (7.5-15 ns), so ample margin | documented timing |
| pin 4 = CDSTEN- (low while reply bytes are pending) | TG: "Status Valid", low ~0.1 ms pulses; S3 holds it low while status bytes are read | sim + docs consistent |
| pin 44 = CDDTEN- (low while sector data is pending) | TG: "Data Chunk Valid", low 0.7-0.8 ms; S3 same use | sim + docs consistent |
| pin 2 = CDMDCHG, low while ctrl byte = 1 | FW holds ctrl 1 for 100 ms after disc change/reset; S3 drives CDMDCHG low for 100 ms after reset | sim + S3 match |
| pin 45 = CDWAIT- (constant 1) | S3 holds CDWAIT- high; pin 45 is the only constant output in bank 2 (XL) | inference |
| No FPGA input for CDRST- | none of the docs show the ODE board; S3 reads CDRST- on the Pico | open |
| GPIO20 = pin 38 (high = can take a sector) | FW cdrom.c waits while GPIO20 low; sim: pin 38 high when buffer empty | sim + FW |
| GPIO21 = pin 42 (rising = command waiting) | FW IRQ on rising edge; sim: rises on 7th CDHWR- | sim + FW |
| GPIO21 level = 7th command byte accepted; falls when a 0x01 read empties the FIFO; opcode 0x08 gives a 14 ns pulse after byte 1 | FW: 7-byte commands, IRQ on rising edge; S3: ABORT is 7 bytes | sim (tb_wr); 0x08 rule differs from S3 |
| CDD driven whenever CDHRD- is low, CDEN- ignored for the drive enable | S3 gates its '245 with CDEN- | difference; ODE board gating unknown |
| GPIO22 = pin 43 (high pulse = reset) | FW idles 0, pulses 1 for 10 us; netlist: posedge async reset | netlist + FW |
| Bus pins in bank 1 with SPI; control in bank 2; SG48 pin numbers | XL (matches IceStorm u4k-sg48) | documented |
| Oscillator on pin 37 (GBIN G1), PLL SIMPLE x47/8 | XL: pin 37 = IOT_45a_G1; DS Table 4.18: VCO 533-1066 MHz -> input 11.3-22.7 MHz, main clock 66.7-133 MHz. Y1 beside the FPGA is marked "12.0" (read on the board 2026-10-26) | range documented |
| n11 clock (19 OE regs) | IceStorm chipdb-u4k: extra cell SMCCLK at (25,3), CLK = slf_op_5. Not in DS (DS lists only HFOSC 48 MHz, LFOSC 10 kHz); frequency unknown | open |
| EBR address cascade | DS 3.1.5.3 says EBRs can be cascaded (no bit detail); bits from icebox_explain; sim read-back correct | inference + sim |

## Cross-check with the firmware and menu docs (2026-10-26)

Sources: FD = firmware `docs/firmware.md`, CM = `docs/commands.md`, ST = `docs/storage.md`, FS = firmware
`source/src` (fpga.c, cdrom.c, main.c); MD = menu `docs/menu.md`, MS = menu `src/ode.c`. FPGA side: docs/ and
the sims (cmd, buf, wr, s4). "Doc gap" = the FPGA shows more than the doc says, no conflict.

| Finding | Document evidence | Status |
|---|---|---|
| Commands are 7 bytes; GPIO21 rises on the 7th | FD command flow; MD `ode_cmd` 7 bytes out; FS `memcpy(cmd, &rx[2], 7)` | match |
| Opcode 0x08: GPIO21 is a 14 ns pulse after byte 1 | FS ABORT handler pulses GPIO22 first, which resyncs the counter; menu never sends 0x08 (MD list) | FPGA-only rule; firmware copes (see below) |
| 0x01 = status, stale byte, 7 cmd bytes, 00; packet end flushes the cmd FIFO | FD "bytes 2-8"; FS reads 10, uses rx[2..8] | match |
| Firmware reads 0x01 only after a GPIO21 rising edge | FS: `cd_recv_command` only from `cd_cmd_dispatch` <- `cd_cmd_poll` if `g_cmd_pending` <- IRQ | match: the early-0x01 desync (tb_wr B) is not reachable from the firmware |
| Reply FIFO 64 B, 65th+ dropped, no overflow status bit | FD 0x02 <= 64; FS caps `len` at 64; MS largest reply read 0x12; CM ABORT reply 32 B | match |
| Sector FIFO 2048 B, overflow drops; status bit 5 = exactly 2048 unread | FD "bit 5 = data FIFO busy"; FS splits > 2048 and waits for bit 5 clear + 320 us; MD/MS 2 KB transfers | match ("busy" = full) |
| 0x03: every returned byte is the status byte | FS returns rx[2] of 3 | match |
| Status bits 7/6 (sector/reply empty), 3-0 (ctrl echo) | not used by FS (POLL log only) | doc gap |
| 0x00 end marker has no lasting effect (decodes to no port) | FD "end marker, meaning inferred" | inferred meaning not supported; harmless |
| Ctrl bit 0 -> CDMDCHG low | FD "1 for 100 ms = media change / drive reset, inferred" | confirmed (CDMDCHG; S3 also 100 ms) |
| Ctrl bit 1 -> CDDTEN- only in a 2048-cycle window every 160001 osc cycles (75 Hz with the 12 MHz oscillator) | FD/ST "2 = CD audio mode, inferred"; ST: also set for data reads when the last track is audio | consistent: it is 1x real-time pacing, applied to whatever is read |
| Ctrl bits 2-3 stored only | FS writes only 0, 1, 2 | match |
| GPIO20 = the same net as CDDTEN- (n7): high = sector FIFO empty, or a 0x05 packet active, or (ctrl bit 1) outside the window | FD "GPIO20: data FIFO can take a sector"; CM "wait for GPIO20 (FIFO ready)" | **contradiction with ctrl bit 1**: sim s4 G shows GPIO20 = 1 with 16 unread bytes outside the window, so `wait_data_ready` does not wait then. Effect on audio-track games: unknown (guess: overflow drops possible if the 3DO is slower than the SD/USB read) |
| GPIO22 = full reset: all FIFOs, cmd counter, opcode reg, and the control register | FD "pulse on abort / read timeout / after config, meaning inferred: data-path reset" | confirmed, wider than FD says; also clears ctrl. FS keeps `cdda_mode` = 1, so after an ABORT or RD timeout in audio mode `set_cdda_mode` does not rewrite 2 (FPGA stays at 0 until `cd_state_reset`) |
| Post-config GPIO22 pulse is required (FFs start 0; no counter start without it) | FS `fpga_init` pulses it only if CDONE = 1 | match (FD presents it as optional; it is not) |
| `fpga_init` sends `0e 03` with CS low after the bitstream | not in FD | doc gap; 0x0e decodes to port 6 (no state), and the pin 43 pulse follows: no effect (guess: part of the wake-up clocks) |
| 100 ms RD timeout | CM/FS: `g_ticks` (10 ms steps) diff > 100, so 110-120 ms | firmware-only; no FPGA timeout or counter. With ctrl bit 1 GPIO20 is low only inside the 170 us window, so the timeout can only fire in data mode |
| 320 us after bit 5 clears before the rest of a > 2048 sector | FS | needs the 3DO to read >= 452 B (2500 - 2048) in 320 us; TG 0.7-0.8 ms per chunk gives ~2.3-3.4 B/us: margin (inference) |
| SPI1 rate "30 MHz" | FD "whatever the divider gives"; FS no `set_sys_clock`, so SDK default 125 MHz clk_peri (from the 12 MHz crystal Y2, marked "120", read on the board 2026-10-26) -> prescale 2 x postdiv 3 = 20.83 MHz (calculation) | consistent with the FPGA's >= 12 ns byte gap: RP2040 datasheet 4.4.3.10 (Motorola SPI, SPH=0: frame select pulsed high between back-to-back words, so SCK pauses; firmware drives SS as a plain GPIO). Pause length ~1 SCK (48 ns): inference |
| RP2040 catches the 14 ns GPIO21 pulse | clk_sys 125 MHz (8 ns): at least one sample of a 14 ns pulse | guess: yes; if missed, the next command raises GPIO21, 0x01 returns the ABORT and the ABORT handler's GPIO22 resyncs (new command lost) |
| Lost-IRQ path: `cd_state_reset` (button short press / boot.iso) clears `g_cmd_pending` | FS main loop: `buttons_process()` before `cd_cmd_poll()`; no GPIO22 on the button path | analysis: if GPIO21 rose before the button callback in the same pass, the command is never read; GPIO21 stays high, the n29 gate drops all later command bytes, no new edge: stuck until a GPIO22 pulse or reboot. Likelihood unknown (guess: rare) |
| RD-timeout / ABORT GPIO22 pulse during a 3DO command burst | FS pulses unconditionally | analysis: remaining bytes count as a new command (desync until the next GPIO22). Guess: rare |
| Reply bytes the 3DO does not read stay in the reply FIFO (only pin 43 flushes) | MS reads n bytes; whether the Portfolio xbus driver drains until CDSTEN- high: not documented | open |
| 75 Hz MSF stepping | CM "75 frames per second" is address arithmetic, not timing | no FPGA link |
