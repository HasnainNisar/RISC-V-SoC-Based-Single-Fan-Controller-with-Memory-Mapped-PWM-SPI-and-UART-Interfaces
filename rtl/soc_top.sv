`timescale 1ns/1ps
// =====================================================================
// soc_top.sv - Top-Level SoC Integration
//
// Connects: rv32i_core -> addr_decoder -> {dmem, config_sram,
// pwm_controller, spi_master, uart_top}
//
// This is the DUT (Device Under Test) and is fully synthesizable.
// spi_slave_model, uart_terminal_model and fan_model are NOT part of
// soc_top -- they live in the testbench and connect to soc_top's pins:
//   pwm_out    -> fan_model.pwm_in
//   fan_rpm_in <- fan_model.rpm_out   (tachometer feedback)
// =====================================================================

module soc_top #(
    parameter string IMEM_INIT_FILE = "",   // e.g. "test_program.hex"
    parameter string CFG_INIT_FILE  = "",   // e.g. "config_data.hex"
    parameter int    UART_CLKS_PER_BIT = 868
) (
    input  logic  clk,
    input  logic  rst_n,

    // ---- SPI pins (to external spi_slave_model in the TB) ----
    output logic  spi_sclk,
    output logic  spi_mosi,
    input  logic  spi_miso,
    output logic  spi_cs_n,

    // ---- UART pins (to external uart_terminal_model in the TB) ----
    output logic  uart_tx_line,
    input  logic  uart_rx_line,

    // ---- Fan interface (to/from the virtual fan model in the TB) ----
    output logic         pwm_out,
    input  logic [15:0]  fan_rpm_in,

    // ---- Status ----
    output logic  bus_error
);

    // -----------------------------------------------------------------
    // Core <-> Instruction memory
    // -----------------------------------------------------------------
    logic [31:0] imem_addr, imem_rdata;

    // -----------------------------------------------------------------
    // Core <-> Address decoder (data bus)
    // -----------------------------------------------------------------
    logic [31:0] core_daddr, core_dwdata, core_drdata;
    logic        core_dwe, core_dre;
    logic [3:0]  core_dbe;

    // -----------------------------------------------------------------
    // Decoder <-> Data SRAM
    // -----------------------------------------------------------------
    logic          dmem_sel;
    logic [31:0]  dmem_addr_w, dmem_wdata_w, dmem_rdata_w;
    logic [3:0]   dmem_be_w;
    logic          dmem_we_w, dmem_re_w;

    // -----------------------------------------------------------------
    // Decoder <-> Config SRAM
    // -----------------------------------------------------------------
    logic          cfg_sel;
    logic [31:0]  cfg_addr_w, cfg_wdata_w, cfg_rdata_w;
    logic [3:0]   cfg_be_w;
    logic          cfg_we_w, cfg_re_w;

    // -----------------------------------------------------------------
    // Decoder <-> PWM controller
    // -----------------------------------------------------------------
    logic          pwm_sel;
    logic [31:0]  pwm_addr_w, pwm_wdata_w, pwm_rdata_w;
    logic          pwm_we_w, pwm_re_w;

    // -----------------------------------------------------------------
    // Decoder <-> SPI master
    // -----------------------------------------------------------------
    logic          spi_sel;
    logic [31:0]  spi_addr_w, spi_wdata_w, spi_rdata_w;
    logic          spi_we_w, spi_re_w;

    // -----------------------------------------------------------------
    // Decoder <-> UART
    // -----------------------------------------------------------------
    logic          uart_sel;
    logic [31:0]  uart_addr_w, uart_wdata_w, uart_rdata_w;
    logic          uart_we_w, uart_re_w;

    // ===================================================================
    // RV32I Core
    // ===================================================================
    rv32i_core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .imem_addr   (imem_addr),
        .imem_rdata  (imem_rdata),
        .dmem_addr   (core_daddr),
        .dmem_wdata  (core_dwdata),
        .dmem_we     (core_dwe),
        .dmem_re     (core_dre),
        .dmem_be     (core_dbe),
        .dmem_rdata  (core_drdata)
    );

    // ===================================================================
    // Instruction SRAM
    // ===================================================================
    imem #(
        .DEPTH_WORDS (1024),
        .INIT_FILE   (IMEM_INIT_FILE)
    ) u_imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    // ===================================================================
    // Address Decoder (data bus interconnect)
    // ===================================================================
    addr_decoder u_addr_decoder (
        .clk         (clk),
        .rst_n       (rst_n),

        .core_addr   (core_daddr),
        .core_wdata  (core_dwdata),
        .core_be     (core_dbe),
        .core_we     (core_dwe),
        .core_re     (core_dre),
        .core_rdata  (core_drdata),
        .bus_error   (bus_error),

        .dmem_sel    (dmem_sel),
        .dmem_addr   (dmem_addr_w),
        .dmem_wdata  (dmem_wdata_w),
        .dmem_be     (dmem_be_w),
        .dmem_we     (dmem_we_w),
        .dmem_re     (dmem_re_w),
        .dmem_rdata  (dmem_rdata_w),

        .cfg_sel     (cfg_sel),
        .cfg_addr    (cfg_addr_w),
        .cfg_wdata   (cfg_wdata_w),
        .cfg_be      (cfg_be_w),
        .cfg_we      (cfg_we_w),
        .cfg_re      (cfg_re_w),
        .cfg_rdata   (cfg_rdata_w),

        .pwm_sel     (pwm_sel),
        .pwm_addr    (pwm_addr_w),
        .pwm_wdata   (pwm_wdata_w),
        .pwm_we      (pwm_we_w),
        .pwm_re      (pwm_re_w),
        .pwm_rdata   (pwm_rdata_w),

        .spi_sel     (spi_sel),
        .spi_addr    (spi_addr_w),
        .spi_wdata   (spi_wdata_w),
        .spi_we      (spi_we_w),
        .spi_re      (spi_re_w),
        .spi_rdata   (spi_rdata_w),

        .uart_sel    (uart_sel),
        .uart_addr   (uart_addr_w),
        .uart_wdata  (uart_wdata_w),
        .uart_we     (uart_we_w),
        .uart_re     (uart_re_w),
        .uart_rdata  (uart_rdata_w)
    );

    // ===================================================================
    // Data SRAM
    // ===================================================================
    dmem #(
        .DEPTH_WORDS (1024)
    ) u_dmem (
        .clk   (clk),
        .sel   (dmem_sel),
        .addr  (dmem_addr_w),
        .wdata (dmem_wdata_w),
        .be    (dmem_be_w),
        .we    (dmem_we_w),
        .re    (dmem_re_w),
        .rdata (dmem_rdata_w)
    );

    // ===================================================================
    // Config SRAM
    // ===================================================================
    config_sram #(
        .DEPTH_WORDS (64),
        .INIT_FILE   (CFG_INIT_FILE)
    ) u_config_sram (
        .clk   (clk),
        .sel   (cfg_sel),
        .addr  (cfg_addr_w),
        .wdata (cfg_wdata_w),
        .be    (cfg_be_w),
        .we    (cfg_we_w),
        .re    (cfg_re_w),
        .rdata (cfg_rdata_w)
    );

    // ===================================================================
    // PWM Controller (fan model lives in the testbench)
    // ===================================================================
    pwm_controller #(
        .STALL_CYCLES (1024),
        .RETRY_CYCLES (256)
    ) u_pwm_controller (
        .clk    (clk),
        .rst_n  (rst_n),
        .sel    (pwm_sel),
        .addr   (pwm_addr_w),
        .wdata  (pwm_wdata_w),
        .we     (pwm_we_w),
        .re     (pwm_re_w),
        .rdata  (pwm_rdata_w),
        .pwm_out(pwm_out),
        .rpm_in (fan_rpm_in)
    );

    // ===================================================================
    // SPI Master
    // ===================================================================
    spi_master u_spi_master (
        .clk    (clk),
        .rst_n  (rst_n),
        .sel    (spi_sel),
        .addr   (spi_addr_w),
        .wdata  (spi_wdata_w),
        .we     (spi_we_w),
        .re     (spi_re_w),
        .rdata  (spi_rdata_w),
        .sclk   (spi_sclk),
        .mosi   (spi_mosi),
        .miso   (spi_miso),
        .cs_n   (spi_cs_n)
    );

    // ===================================================================
    // UART
    // ===================================================================
    uart_top #(
        .CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_uart_top (
        .clk      (clk),
        .rst_n    (rst_n),
        .sel      (uart_sel),
        .addr     (uart_addr_w),
        .wdata    (uart_wdata_w),
        .we       (uart_we_w),
        .re       (uart_re_w),
        .rdata    (uart_rdata_w),
        .tx_line  (uart_tx_line),
        .rx_line  (uart_rx_line)
    );

endmodule
