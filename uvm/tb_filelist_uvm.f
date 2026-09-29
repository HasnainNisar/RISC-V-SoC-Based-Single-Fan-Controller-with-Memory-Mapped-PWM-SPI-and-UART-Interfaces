// tb_filelist_uvm.f - Compile order for the UVM environment
// Run from the PROJECT ROOT. Requires a UVM-capable simulator (Questa, VCS,
// Xcelium). Verilator and Icarus cannot run this UVM environment.
//
//   vlog -sv -timescale 1ns/1ps +incdir+uvm -f uvm/tb_filelist_uvm.f
//   vsim -c work.tb_top_uvm +UVM_TESTNAME=normal_test -do "run -all; quit -f"
//   (core_instr_test additionally needs  +IMEM=instr_test.hex -- see run_uvm.do)
//
// +incdir+uvm lets the `include lines inside uvm_pkg_includes.sv find the
// agent/sequence/test files (they sit flat in uvm/).
//
// Do NOT add the individual class files (spi_driver.sv, scoreboard.sv, ...)
// to a Questa project or filelist -- they are pulled into soc_uvm_pkg by
// `include and cannot compile on their own.

// ---- DUT (synthesizable RTL) ----
-f filelist.f

// ---- Testbench-side models and checkers ----
sim/models/fan_model.sv
sim/soc_assertions.sv

// ---- UVM environment (order matters: interface, then package, then top) ----
uvm/soc_if.sv
uvm/uvm_pkg_includes.sv
uvm/tb_top_uvm.sv
