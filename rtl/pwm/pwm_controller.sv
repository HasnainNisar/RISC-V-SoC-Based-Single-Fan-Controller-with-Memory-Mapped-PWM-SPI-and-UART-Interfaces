`timescale 1ns/1ps
// =====================================================================
// pwm_controller.sv - Single-Channel PWM Fan Controller with fail-safe
//
// Register map (offsets relative to base 0x3000_0000, see memory_map.md):
//   0x0  PWM_CTRL    R/W  [0]=EN, [1]=SOFT_RESET (self-clearing)
//   0x4  PWM_DUTY    R/W  [7:0]  duty cycle (0-255)
//   0x8  PWM_STATUS  R    [0]=RUNNING, [1]=FAULT, [2]=FAILSAFE (drive removed)
//   0xC  PWM_RPM     R    [15:0] simulated RPM (from fan model)
//
// PWM generation: free-running 8-bit counter compared against the duty
// register. pwm_out is high while counter < duty_reg.
//
// Stall detection + fail-safe (FSM):
//   RUN   : PWM enabled with duty != 0 but rpm_in == 0 for STALL_CYCLES
//           consecutive clocks  -> FAULT=1, enter SAFE.
//   SAFE  : drive REMOVED (pwm_out forced low) for RETRY_CYCLES so a jammed
//           fan is not driven; FAULT stays asserted.
//   RETRY : drive re-applied. If the fan spins (rpm_in != 0) the fault is
//           cleared (automatic recovery) and the FSM returns to RUN;
//           if still stalled after STALL_CYCLES it drops back to SAFE.
// Disabling the PWM (EN=0) or SOFT_RESET clears the fault and returns to RUN.
// Duty == 0 is an intentional "off" and never counts as a stall.
// =====================================================================

module pwm_controller #(
    parameter int STALL_CYCLES = 1024,
    parameter int RETRY_CYCLES = 256
) (
    input  logic         clk,
    input  logic         rst_n,

    // Bus interface (from addr_decoder)
    input  logic          sel,
    input  logic [31:0]  addr,
    input  logic [31:0]  wdata,
    input  logic          we,
    input  logic          re,
    output logic [31:0]  rdata,

    // To fan model
    output logic          pwm_out,

    // From fan model
    input  logic [15:0]  rpm_in
);

    // -----------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------
    logic        en_reg;
    logic        soft_reset_reg;   // one-clock pulse, synchronous use only
    logic [7:0]  duty_reg;

    wire [3:0] reg_offset = addr[3:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_reg         <= 1'b0;
            soft_reset_reg <= 1'b0;
            duty_reg       <= 8'd0;
        end else begin
            soft_reset_reg <= 1'b0;                 // self-clearing pulse
            if (sel && we) begin
                case (reg_offset)
                    4'h0: begin
                        en_reg         <= wdata[0];
                        soft_reset_reg <= wdata[1];
                    end
                    4'h4: duty_reg <= wdata[7:0];
                    default: ;                      // STATUS/RPM are read-only
                endcase
            end
        end
    end

    // -----------------------------------------------------------------
    // PWM generation: free-running counter + comparator
    // (soft reset is applied synchronously, NOT in the async-reset term)
    // -----------------------------------------------------------------
    logic [7:0] pwm_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              pwm_counter <= 8'd0;
        else if (soft_reset_reg) pwm_counter <= 8'd0;
        else                     pwm_counter <= pwm_counter + 8'd1;
    end

    // -----------------------------------------------------------------
    // Stall detection + fail-safe FSM
    // -----------------------------------------------------------------
    localparam int CNT_MAX = (STALL_CYCLES > RETRY_CYCLES) ? STALL_CYCLES : RETRY_CYCLES;

    typedef enum logic [1:0] {P_RUN, P_SAFE, P_RETRY} pwm_state_e;
    pwm_state_e state;

    localparam int CNT_W = $clog2(CNT_MAX+1);
    localparam logic [CNT_W-1:0] STALL_LIM = CNT_W'(STALL_CYCLES);
    localparam logic [CNT_W-1:0] RETRY_LIM = CNT_W'(RETRY_CYCLES - 1);
    logic [CNT_W-1:0] cnt;
    logic fault_reg;

    wire expect_spin = en_reg && (duty_reg != 8'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= P_RUN;
            cnt       <= '0;
            fault_reg <= 1'b0;
        end else if (soft_reset_reg || !expect_spin) begin
            state     <= P_RUN;
            cnt       <= '0;
            fault_reg <= 1'b0;
        end else begin
            case (state)
                P_RUN: begin
                    if (rpm_in == 16'd0) begin
                        if (cnt == STALL_LIM) begin
                            fault_reg <= 1'b1;
                            state     <= P_SAFE;
                            cnt       <= '0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end else begin
                        cnt <= '0;
                    end
                end

                P_SAFE: begin                        // drive removed
                    if (cnt == RETRY_LIM) begin
                        state <= P_RETRY;
                        cnt   <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                P_RETRY: begin                       // drive re-applied, watch for spin
                    if (rpm_in != 16'd0) begin
                        fault_reg <= 1'b0;           // recovered
                        state     <= P_RUN;
                        cnt       <= '0;
                    end else if (cnt == STALL_LIM) begin
                        state <= P_SAFE;             // still stalled
                        cnt   <= '0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= P_RUN;
            endcase
        end
    end

    wire failsafe_active = (state == P_SAFE);
    wire running_flag    = en_reg && (rpm_in != 16'd0);

    assign pwm_out = en_reg && !failsafe_active && (pwm_counter < duty_reg);

    // -----------------------------------------------------------------
    // Read path
    // -----------------------------------------------------------------
    always_comb begin
        rdata = 32'd0;
        if (sel && re) begin
            case (reg_offset)
                4'h0: rdata = {30'd0, soft_reset_reg, en_reg};
                4'h4: rdata = {24'd0, duty_reg};
                4'h8: rdata = {29'd0, failsafe_active, fault_reg, running_flag};
                4'hC: rdata = {16'd0, rpm_in};
                default: rdata = 32'd0;
            endcase
        end
    end

endmodule
