`timescale 1ns/1ps
// =====================================================================
// fan_model.sv - Virtual Fan Model (behavioral, testbench-side)
//
// Not a real peripheral register block -- this module simulates how a
// physical fan would respond to a PWM signal:
//   1. Measures the duty cycle of pwm_out over one 256-cycle PWM period.
//   2. Computes a target RPM proportional to that duty cycle.
//   3. Ramps the reported RPM towards the target (models spin-up /
//      spin-down inertia instead of an instant jump).
//
// A `stall_inject` input lets the testbench force RPM to 0 even while
// PWM is driving the fan, to exercise the PWM controller's stall/fault
// detection logic (error-case verification).
// =====================================================================

module fan_model #(
    parameter int MAX_RPM    = 3000,  // RPM at 100% duty cycle
    parameter int RAMP_STEP  = 50     // RPM change per PWM period (inertia)
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic          pwm_in,        // pwm_out from pwm_controller
    input  logic          stall_inject,  // TB forces a stalled/jammed fan

    output logic [15:0]  rpm_out
);

    // -----------------------------------------------------------------
    // Duty cycle measurement over a 256-cycle window (matches the
    // pwm_controller's 8-bit free-running counter period)
    // -----------------------------------------------------------------
    logic [7:0]  window_counter;
    logic [8:0]  high_count, high_count_latched;
    logic [8:0]  duty_measured; // 0-255 range, same as PWM_DUTY register

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_counter <= 8'd0;
            high_count     <= 9'd0;
            high_count_latched <= 9'd0;
        end else begin
            if (window_counter == 8'd255) begin
                window_counter     <= 8'd0;
                high_count_latched <= high_count + (pwm_in ? 9'd1 : 9'd0);
                high_count         <= 9'd0;
            end else begin
                window_counter <= window_counter + 8'd1;
                high_count     <= high_count + (pwm_in ? 9'd1 : 9'd0);
            end
        end
    end

    assign duty_measured = high_count_latched;

    // -----------------------------------------------------------------
    // Target RPM proportional to measured duty
    // -----------------------------------------------------------------
    logic [31:0] target_rpm;
    assign target_rpm = (duty_measured * MAX_RPM) / 255;

    // -----------------------------------------------------------------
    // RPM ramp (inertia) - updates once per PWM window
    // -----------------------------------------------------------------
    logic [15:0] rpm_reg;
    logic        window_tick;
    assign window_tick = (window_counter == 8'd255);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rpm_reg <= 16'd0;
        end else if (stall_inject) begin
            rpm_reg <= 16'd0; // jammed / disconnected fan
        end else if (window_tick) begin
            if (rpm_reg < target_rpm) begin
                if ((target_rpm - rpm_reg) > RAMP_STEP)
                    rpm_reg <= rpm_reg + RAMP_STEP[15:0];
                else
                    rpm_reg <= target_rpm[15:0];
            end else if (rpm_reg > target_rpm) begin
                if ((rpm_reg - target_rpm) > RAMP_STEP)
                    rpm_reg <= rpm_reg - RAMP_STEP[15:0];
                else
                    rpm_reg <= target_rpm[15:0];
            end
        end
    end

    assign rpm_out = rpm_reg;

endmodule
