// filelist.f - SYNTHESIZABLE RTL ONLY (the DUT: soc_top and everything under it)
// Paths are relative to the PROJECT ROOT -- run tools from there.
//   Synthesis / lint:  read this list only
//   Verilator lint:    verilator --lint-only --timing -Wall -f filelist.f --top-module soc_top
//   Simulation:        sim/tb_filelist.f adds the testbench-side models (sim/models/) on top
//
// Packages / shared defs first
rtl/core/alu.sv                    // defines alu_pkg, must compile before users

// Core
rtl/core/regfile.sv
rtl/core/imm_gen.sv
rtl/core/control_unit.sv
rtl/core/rv32i_core.sv
rtl/core/imem.sv

// Memories
rtl/mem/dmem.sv
rtl/mem/config_sram.sv

// Bus
rtl/bus/addr_decoder.sv

// Peripherals
rtl/pwm/pwm_controller.sv
rtl/spi/spi_master.sv
rtl/uart/uart_tx.sv
rtl/uart/uart_rx.sv
rtl/uart/uart_top.sv

// Top-level
rtl/soc_top.sv
