// tb_filelist.f - Compile order for the directed testbenches
// Run from the PROJECT ROOT (the folder containing rtl/, sim/, uvm/, tools/ and the
// .hex files), NOT from sim/ -- paths are root-relative.
//
//   Questa:     vlog -sv -f sim/tb_filelist.f     (see run_tb.do)
//   Verilator:  verilator --binary --timing -f sim/tb_filelist.f --top-module tb_soc_top
//
// The .hex files are read via $readmemh with relative paths, so they must be in
// the directory the simulator is launched from.

// ---- DUT (synthesizable RTL) ----
-f filelist.f

// ---- Testbench-side models (NOT synthesizable) ----
sim/models/fan_model.sv
sim/models/spi_slave_model.sv
sim/models/uart_terminal_model.sv

// ---- Checkers and testbenches ----
sim/soc_assertions.sv
sim/tb_soc_top.sv
sim/tb_core_instr.sv
