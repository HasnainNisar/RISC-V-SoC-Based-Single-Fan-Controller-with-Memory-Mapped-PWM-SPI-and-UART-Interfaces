`timescale 1ns/1ps
// =====================================================================
// uvm_pkg_includes.sv - SoC UVM Package
//
// Compile order requirement: soc_if.sv MUST be compiled BEFORE this
// package (interfaces cannot be declared inside a package, but classes
// in this package reference `virtual soc_if`, which requires the
// interface to already be visible at the compilation-unit scope).
//
// See tb_filelist_uvm.f for the full recommended compile order.
// =====================================================================

`include "uvm_macros.svh"

package soc_uvm_pkg;

    import uvm_pkg::*;

    // ---- SPI agent ----
    `include "spi_seq_item.sv"
    `include "spi_sequencer.sv"
    `include "spi_driver.sv"
    `include "spi_monitor.sv"
    `include "spi_agent.sv"

    // ---- UART agent ----
    `include "uart_seq_item.sv"
    `include "uart_sequencer.sv"
    `include "uart_driver.sv"
    `include "uart_monitor.sv"
    `include "uart_agent.sv"

    // ---- PWM agent (monitor-only) ----
    `include "pwm_monitor.sv"
    `include "pwm_agent.sv"

    // ---- Core monitor (instruction stream, for instruction coverage) ----
    `include "core_monitor.sv"

    // ---- Scoreboard / coverage ----
    `include "scoreboard.sv"

    // ---- Environment ----
    `include "env.sv"

    // ---- Sequences ----
    `include "normal_seq.sv"
    `include "error_seq.sv"
    `include "failsafe_seq.sv"

    // ---- Tests ----
    `include "test_lib.sv"

endpackage
