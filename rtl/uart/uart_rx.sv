`timescale 1ns/1ps
// =====================================================================
// uart_rx.sv - UART Receiver (serial engine)
//
// Frame format: 1 start bit (0) + 8 data bits (LSB first) + 1 stop
// bit (1). No parity.
//
// Self-contained baud generation: CLKS_PER_BIT = system_clk_freq /
// baud_rate (set to match the transmitter's bit period). Detects the
// falling edge of the start bit, waits half a bit period to align to
// the middle of each bit, then samples each data bit at one full bit
// period apart -- standard UART receiver technique for reliable
// sampling away from bit transition edges.
//
// frame_error is asserted (for one cycle) if the stop bit is not '1'
// when sampled -- represents a framing error case for verification.
// =====================================================================

module uart_rx #(
    parameter int CLKS_PER_BIT = 868   // e.g. 50 MHz / 57600 baud approx
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic          rx_line,

    output logic [7:0]   rx_data,
    output logic          rx_valid,     // one-cycle pulse: new byte ready
    output logic          frame_error   // one-cycle pulse: bad stop bit
);

    localparam int CNT_W = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {R_IDLE, R_START, R_DATA, R_STOP} rx_state_e;
    rx_state_e state;

    logic [CNT_W-1:0] clk_count;
    localparam logic [CNT_W-1:0] HALF_BIT = CNT_W'(CLKS_PER_BIT/2);
    localparam logic [CNT_W-1:0] LAST_CLK = CNT_W'(CLKS_PER_BIT - 1);
    logic [2:0]        bit_idx;
    logic [7:0]        shift_reg;

    // 2-flop synchronizer for the async rx_line input
    logic rx_sync0, rx_sync1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx_line;
            rx_sync1 <= rx_sync0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= R_IDLE;
            clk_count   <= '0;
            bit_idx     <= 3'd0;
            shift_reg   <= 8'd0;
            rx_data     <= 8'd0;
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;

            case (state)
                R_IDLE: begin
                    clk_count <= '0;
                    if (rx_sync1 == 1'b0) begin // falling edge = start bit
                        state <= R_START;
                    end
                end

                R_START: begin
                    // Wait half a bit period to sample mid-start-bit
                    if (clk_count == HALF_BIT) begin
                        if (rx_sync1 == 1'b0) begin
                            clk_count <= '0;
                            bit_idx   <= 3'd0;
                            state     <= R_DATA;
                        end else begin
                            state <= R_IDLE; // glitch, not a real start bit
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                R_DATA: begin
                    if (clk_count == LAST_CLK) begin
                        clk_count            <= '0;
                        shift_reg[bit_idx]   <= rx_sync1;
                        if (bit_idx == 3'd7)
                            state <= R_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                R_STOP: begin
                    if (clk_count == LAST_CLK) begin
                        clk_count <= '0;
                        rx_data   <= shift_reg;
                        if (rx_sync1 == 1'b1) begin
                            rx_valid <= 1'b1;     // good frame
                        end else begin
                            frame_error <= 1'b1;  // stop bit missing
                        end
                        state <= R_IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: state <= R_IDLE;
            endcase
        end
    end

endmodule
