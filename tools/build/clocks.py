# nextpnr pre-pack script: clock constraints for the timing report (estimates only).
# osc 12 MHz (marked on the board; agrees with the 75 Hz timer), PLL x47/8 = 70.5 MHz, SCK 30 MHz (firmware SPI1 rate after config).
ctx.addClock("pin_37", 12)
ctx.addClock("pin_15", 30)
