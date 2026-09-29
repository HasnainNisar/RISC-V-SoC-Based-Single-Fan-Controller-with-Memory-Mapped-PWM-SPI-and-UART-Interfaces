`timescale 1ns/1ps
// =====================================================================
// soc_assertions.sv - SystemVerilog Assertions (SVA) for the SoC
//
// A passive checker module: all inputs, no outputs. It is instantiated by
// BOTH tb_soc_top (directed) and tb_top_uvm (UVM) so the same properties
// are checked in every simulation. Each property has a matching
// `cover property` where it helps to prove the scenario actually happened.
// =====================================================================
module soc_assertions #(
    parameter int STALL_CYCLES = 1024,
    parameter int RETRY_CYCLES = 256
) (
    input logic        clk,
    input logic        rst_n,

    // core
    input logic [31:0] pc,

    // bus / decoder
    input logic        core_re,
    input logic        core_we,
    input logic [31:0] core_rdata,
    input logic        bus_error,
    input logic        dmem_sel,
    input logic        cfg_sel,
    input logic        pwm_sel,
    input logic        spi_sel,
    input logic        uart_sel,

    // PWM / fan
    input logic        pwm_out,
    input logic        pwm_en,
    input logic [7:0]  pwm_duty,
    input logic        pwm_fault,
    input logic        pwm_failsafe,
    input logic [15:0] fan_rpm,

    // SPI
    input logic        spi_sclk,
    input logic        spi_mosi,
    input logic        spi_cs_n,
    input logic        spi_busy,
    input logic        spi_error,
    input logic        spi_start,

    // UART
    input logic        uart_tx_line,
    input logic        uart_tx_en,
    input logic        uart_rx_valid,
    input logic        uart_frame_err
);

    // Number of assertion failures so far (read hierarchically by the testbenches)
    int unsigned fail_count = 0;
    function automatic void bump();
        fail_count++;
    endfunction

    wire any_sel = dmem_sel | cfg_sel | pwm_sel | spi_sel | uart_sel;
    wire access  = core_re | core_we;

    // ------------------------------------------------------------------
    // Reset behaviour (checked while reset is asserted, so no disable iff)
    // ------------------------------------------------------------------
    // (qualified with $past so the very first clock of the simulation, before the
    //  asynchronous reset has had a chance to act, is not checked)
    a_reset_pc: assert property (@(posedge clk)
        (!rst_n && $past(!rst_n)) |-> (pc == 32'd0))
        else begin bump(); $error("SVA a_reset_pc: PC not 0 during reset"); end

    a_reset_periph: assert property (@(posedge clk)
        (!rst_n && $past(!rst_n)) |-> (!pwm_en && pwm_duty == 8'd0 && spi_cs_n && uart_tx_line && !bus_error && !pwm_out))
        else begin bump(); $error("SVA a_reset_periph: peripheral not in reset state"); end

    // ------------------------------------------------------------------
    // Core
    // ------------------------------------------------------------------
    a_pc_aligned: assert property (@(posedge clk) disable iff (!rst_n) pc[1:0] == 2'b00)
        else begin bump(); $error("SVA a_pc_aligned: PC is not word aligned (pc=%h)", pc); end

    // ------------------------------------------------------------------
    // Bus decoder
    // ------------------------------------------------------------------
    a_sel_onehot0: assert property (@(posedge clk) disable iff (!rst_n) $onehot0({dmem_sel, cfg_sel, pwm_sel, spi_sel, uart_sel}))
        else begin bump(); $error("SVA a_sel_onehot0: more than one peripheral/memory selected"); end

    a_unmapped_rdata: assert property (@(posedge clk) disable iff (!rst_n) (core_re && !any_sel) |-> (core_rdata == 32'hDEAD_BEEF))
        else begin bump(); $error("SVA a_unmapped_rdata: unmapped read did not return 0xDEADBEEF"); end

    a_bus_error_raise: assert property (@(posedge clk) disable iff (!rst_n) (access && !any_sel) |=> bus_error)
        else begin bump(); $error("SVA a_bus_error_raise: access to unmapped address did not raise bus_error"); end

    a_bus_error_cause: assert property (@(posedge clk) disable iff (!rst_n) bus_error |-> $past(access && !any_sel))
        else begin bump(); $error("SVA a_bus_error_cause: bus_error without an unmapped access"); end

    c_bus_error: cover property (@(posedge clk) disable iff (!rst_n) bus_error);

    // ------------------------------------------------------------------
    // PWM stall detection + fail-safe
    // ------------------------------------------------------------------
    a_pwm_needs_en: assert property (@(posedge clk) disable iff (!rst_n) pwm_out |-> pwm_en)
        else begin bump(); $error("SVA a_pwm_needs_en: pwm_out high while PWM disabled"); end

    a_failsafe_no_drive: assert property (@(posedge clk) disable iff (!rst_n) pwm_failsafe |-> !pwm_out)
        else begin bump(); $error("SVA a_failsafe_no_drive: PWM drive present while in fail-safe"); end

    a_failsafe_implies_fault: assert property (@(posedge clk) disable iff (!rst_n) pwm_failsafe |-> pwm_fault)
        else begin bump(); $error("SVA a_failsafe_implies_fault: fail-safe active without FAULT"); end

    // Stall watchdog: count consecutive stalled clocks; the fault must be
    // raised within STALL_CYCLES + 2 clocks of a continuous stall.
    // IMPORTANT: this counter must keep running even after pwm_fault has
    // already latched (a real, ongoing stall stays a stall) -- it only
    // resets when the stall condition itself ends (fan spins, PWM turned
    // off, or duty set to 0). Gating the increment on "!pwm_fault" would
    // reset the counter the instant the fault we're trying to verify
    // latches, making the '>' comparison below structurally unreachable.
    int unsigned stall_run;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) stall_run <= 0;
        else if (pwm_en && pwm_duty != 8'd0 && fan_rpm == 16'd0) stall_run <= stall_run + 1;
        else stall_run <= 0;
    end
    a_stall_detected: assert property (@(posedge clk) disable iff (!rst_n) (stall_run > STALL_CYCLES + 2) |-> pwm_fault)
        else begin bump(); $error("SVA a_stall_detected: continuous stall not flagged as FAULT"); end

    // Recovery: in RETRY (fault, drive on) a spinning fan must clear the fault next clock
    a_recovery: assert property (@(posedge clk) disable iff (!rst_n) (pwm_fault && !pwm_failsafe && fan_rpm != 16'd0) |=> !pwm_fault)
        else begin bump(); $error("SVA a_recovery: fan spinning again but FAULT not cleared"); end

    a_no_fault_when_off: assert property (@(posedge clk) disable iff (!rst_n) (!pwm_en || pwm_duty == 8'd0) |=> !pwm_fault)
        else begin bump(); $error("SVA a_no_fault_when_off: FAULT while PWM disabled / duty is 0"); end

    c_fault:    cover property (@(posedge clk) disable iff (!rst_n) $rose(pwm_fault));
    c_failsafe: cover property (@(posedge clk) disable iff (!rst_n) $rose(pwm_failsafe));
    c_recovery: cover property (@(posedge clk) disable iff (!rst_n) $fell(pwm_fault));

    // ------------------------------------------------------------------
    // SPI (Mode 0)
    // ------------------------------------------------------------------
    a_spi_sclk_idle_low: assert property (@(posedge clk) disable iff (!rst_n) spi_cs_n |-> !spi_sclk)
        else begin bump(); $error("SVA a_spi_sclk_idle_low: SCLK toggling while CS_N is high"); end

    a_spi_mosi_stable: assert property (@(posedge clk) disable iff (!rst_n) (!spi_cs_n && $changed(spi_mosi)) |-> !spi_sclk)
        else begin bump(); $error("SVA a_spi_mosi_stable: MOSI changed while SCLK high (violates Mode 0)"); end

    a_spi_busy_cs: assert property (@(posedge clk) disable iff (!rst_n) spi_busy |-> !spi_cs_n)
        else begin bump(); $error("SVA a_spi_busy_cs: busy but CS_N not asserted"); end

    a_spi_start_busy_err: assert property (@(posedge clk) disable iff (!rst_n) (spi_start && spi_busy) |=> spi_error)
        else begin bump(); $error("SVA a_spi_start_busy_err: START while busy did not set ERROR"); end

    c_spi_transfer: cover property (@(posedge clk) disable iff (!rst_n) $fell(spi_cs_n));
    c_spi_error:    cover property (@(posedge clk) disable iff (!rst_n) $rose(spi_error));

    // ------------------------------------------------------------------
    // UART
    // ------------------------------------------------------------------
    a_uart_idle_high: assert property (@(posedge clk) disable iff (!rst_n) !uart_tx_en |-> uart_tx_line)
        else begin bump(); $error("SVA a_uart_idle_high: TX line low while transmitter disabled"); end

    a_uart_valid_xor_err: assert property (@(posedge clk) disable iff (!rst_n) !(uart_rx_valid && uart_frame_err))
        else begin bump(); $error("SVA a_uart_valid_xor_err: rx_valid and frame_error in the same clock"); end

    c_uart_rx:        cover property (@(posedge clk) disable iff (!rst_n) uart_rx_valid);
    c_uart_frame_err: cover property (@(posedge clk) disable iff (!rst_n) uart_frame_err);

endmodule
