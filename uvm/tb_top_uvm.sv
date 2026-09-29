// =====================================================================
// tb_top_uvm.sv - UVM Top-Level Testbench
//
// Instantiates soc_top (DUT), the virtual fan model, the SVA checker and
// the soc_if interface, hooks up hierarchical taps into DUT internals
// (PWM state, memories, core PC/instruction, sticky event flags) and
// starts UVM with run_test().
//
// The program the core runs defaults to test_program.hex; override it with
//   +IMEM=instr_test.hex     (used by core_instr_test)
// =====================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"   // needed for `uvm_fatal in this file (macros don't carry over from uvm_pkg_includes.sv)

module tb_top_uvm;

    import uvm_pkg::*;
    import soc_uvm_pkg::*;

    localparam real CLK_PERIOD_NS      = 20.0; // 50 MHz
    localparam int  UART_CLKS_PER_BIT  = 16;   // small, fast-sim baud

    // -----------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    // -----------------------------------------------------------------
    // Interface
    // -----------------------------------------------------------------
    soc_if vif (.clk(clk), .rst_n(rst_n));

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    soc_top #(
        .IMEM_INIT_FILE    ("test_program.hex"),
        .CFG_INIT_FILE     ("config_data.hex"),
        .UART_CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .spi_sclk     (vif.spi_sclk),
        .spi_mosi     (vif.spi_mosi),
        .spi_miso     (vif.spi_miso),
        .spi_cs_n     (vif.spi_cs_n),
        .uart_tx_line (vif.uart_tx_line),
        .uart_rx_line (vif.uart_rx_line),
        .pwm_out      (vif.pwm_out_debug),
        .fan_rpm_in   (vif.fan_rpm_debug),
        .bus_error    (vif.bus_error)
    );

    // Virtual fan (testbench-side model): PWM in -> RPM out; stall injectable
    fan_model #(.MAX_RPM(3000), .RAMP_STEP(50)) u_fan_model (
        .clk          (clk),
        .rst_n        (rst_n),
        .pwm_in       (vif.pwm_out_debug),
        .stall_inject (vif.fan_stall_inject),
        .rpm_out      (vif.fan_rpm_debug)
    );

    // -----------------------------------------------------------------
    // SVA checker (same one used by the directed testbench)
    // -----------------------------------------------------------------
    soc_assertions #(.STALL_CYCLES(1024), .RETRY_CYCLES(256)) u_sva (
        .clk(clk), .rst_n(rst_n),
        .pc            (u_dut.u_core.pc),
        .core_re       (u_dut.core_dre),
        .core_we       (u_dut.core_dwe),
        .core_rdata    (u_dut.core_drdata),
        .bus_error     (vif.bus_error),
        .dmem_sel      (u_dut.dmem_sel),
        .cfg_sel       (u_dut.cfg_sel),
        .pwm_sel       (u_dut.pwm_sel),
        .spi_sel       (u_dut.spi_sel),
        .uart_sel      (u_dut.uart_sel),
        .pwm_out       (vif.pwm_out_debug),
        .pwm_en        (u_dut.u_pwm_controller.en_reg),
        .pwm_duty      (u_dut.u_pwm_controller.duty_reg),
        .pwm_fault     (u_dut.u_pwm_controller.fault_reg),
        .pwm_failsafe  (u_dut.u_pwm_controller.failsafe_active),
        .fan_rpm       (vif.fan_rpm_debug),
        .spi_sclk      (vif.spi_sclk),
        .spi_mosi      (vif.spi_mosi),
        .spi_cs_n      (vif.spi_cs_n),
        .spi_busy      (u_dut.u_spi_master.busy_reg),
        .spi_error     (u_dut.u_spi_master.error_reg),
        .spi_start     (u_dut.u_spi_master.start_pulse),
        .uart_tx_line  (vif.uart_tx_line),
        .uart_tx_en    (u_dut.u_uart_top.tx_en),
        .uart_rx_valid (u_dut.u_uart_top.rx_valid_pulse),
        .uart_frame_err(u_dut.u_uart_top.frame_err_pulse)
    );

    // -----------------------------------------------------------------
    // Hierarchical status taps (internal DUT signals -> interface)
    // -----------------------------------------------------------------
    assign vif.pwm_en_tap       = u_dut.u_pwm_controller.en_reg;
    assign vif.pwm_fault_tap    = u_dut.u_pwm_controller.fault_reg;
    assign vif.pwm_duty_tap     = u_dut.u_pwm_controller.duty_reg;
    assign vif.pwm_failsafe_tap = u_dut.u_pwm_controller.failsafe_active;
    assign vif.spi_error_tap    = u_dut.u_spi_master.error_reg;
    assign vif.core_pc          = u_dut.u_core.pc;
    assign vif.core_instr       = u_dut.imem_rdata;
    assign vif.sva_fail_count   = u_sva.fail_count;

    genvar gi;
    generate
        for (gi = 0; gi < 128; gi++) begin : g_dmem_tap
            assign vif.dmem_tap[gi] = u_dut.u_dmem.mem[gi];
        end
        for (gi = 0; gi < 16; gi++) begin : g_cfg_tap
            assign vif.cfg_tap[gi] = u_dut.u_config_sram.mem[gi];
        end
    endgenerate

    // Sticky event flags (one-clock pulses in the DUT would otherwise be missed)
    initial begin
        vif.bus_error_seen       = 1'b0;
        vif.uart_frame_err_seen  = 1'b0;
        vif.uart_rx_valid_seen   = 1'b0;
        vif.fan_stall_inject     = 1'b0;   // default before any sequence drives it
    end
    always @(posedge clk) begin
        if (vif.bus_error === 1'b1)                       vif.bus_error_seen      <= 1'b1;
        if (u_dut.u_uart_top.frame_err_pulse === 1'b1)    vif.uart_frame_err_seen <= 1'b1;
        if (u_dut.u_uart_top.rx_valid_pulse  === 1'b1)    vif.uart_rx_valid_seen  <= 1'b1;
    end

    // -----------------------------------------------------------------
    // UVM setup + run
    // -----------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual soc_if)::set(null, "*", "vif", vif);
        run_test(); // test name supplied via +UVM_TESTNAME=... on the command line
    end

    // -----------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("tb_top_uvm.vcd");
        $dumpvars(0, tb_top_uvm);
    end

    // -----------------------------------------------------------------
    // Safety timeout
    // -----------------------------------------------------------------
    initial begin
        #5_000_000; // 5 ms
        `uvm_fatal("TB_TOP", "Global simulation timeout reached")
    end

endmodule
