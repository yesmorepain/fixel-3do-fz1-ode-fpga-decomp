// Waveform dump for register matching (tools/eqmap.py): golden netlist and clean core, all nets.
// Built by `DUMP=1 sh tools/sim/cosim.sh TB`; file name: +vcd=PATH (default build/sim/cosim_dump.vcd).
`timescale 1ps/1ps
module cosim_dump;
  reg [8*200-1:0] path;
  initial begin
    if (!$value$plusargs("vcd=%s", path)) path = "build/sim/cosim_dump.vcd";
    $dumpfile(path);
    $dumpvars(0, tb.dut.golden);
    $dumpvars(0, tb.dut.clean);
  end
endmodule
