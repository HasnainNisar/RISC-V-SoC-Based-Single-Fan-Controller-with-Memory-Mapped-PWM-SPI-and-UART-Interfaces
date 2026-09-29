`timescale 1ns/1ps
// =====================================================================
// soc_if.sv - SoC Interface
//
// Bundles all signals the UVM environment needs to drive/observe:
//   - SPI pins (DUT is master; agent drives the slave side)
//   - UART pins (DUT drives tx_line; agent drives rx_line as a host)
//   - PWM/fan debug outputs (already exposed at soc_top level)
//   - A few internal DUT status bits tapped hierarchically in
//     tb_top_uvm.sv (fault/enable/error registers) so the scoreboard
//     can check fail-safe behavior without needing new soc_top ports.
// =====================================================================

interface soc_if (
    input logic clk,
    input logic rst_n
);

    // ---- SPI ----
    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;
    logic spi_cs_n;

    // ---- UART ----
    logic uart_tx_line;
    logic uart_rx_line;

    // ---- Fan fault injection / bus status ----
    logic fan_stall_inject;
    logic bus_error;

    // ---- PWM / fan debug (already top-level ports on soc_top) ----
    logic [15:0] fan_rpm_debug;
    logic        pwm_out_debug;

    // ---- Internal status taps (driven by hierarchical assigns in
    //      tb_top_uvm.sv, read-only from the UVM env's point of view) ----
    logic pwm_en_tap;      // pwm_controller.en_reg
    logic pwm_fault_tap;   // pwm_controller.fault_reg
    logic [7:0] pwm_duty_tap; // pwm_controller.duty_reg
    logic spi_error_tap;   // spi_master.error_reg
    logic pwm_failsafe_tap;// pwm_controller.failsafe_active (drive removed)

    // ---- Core / memory observation taps ----
    logic [31:0] core_pc;          // program counter
    logic [31:0] core_instr;       // instruction being executed
    logic [31:0] dmem_tap [0:127]; // first 128 words of data SRAM
    logic [31:0] cfg_tap  [0:15];  // first 16 words of configuration SRAM

    // ---- Sticky event flags (set in tb_top_uvm.sv, never cleared) ----
    logic bus_error_seen;
    logic uart_frame_err_seen;
    logic uart_rx_valid_seen;

    // ---- SVA failure count from soc_assertions ----
    int unsigned sva_fail_count;

endinterface
