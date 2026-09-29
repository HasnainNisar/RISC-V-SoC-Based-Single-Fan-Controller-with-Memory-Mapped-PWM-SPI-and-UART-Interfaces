`timescale 1ns/1ps
// =====================================================================
// uart_tx.sv - UART Transmitter (serial engine)
//
// Frame format: 1 start bit (0) + 8 data bits (LSB first) + 1 stop
// bit (1). No parity.
//
// Pure serial engine: takes a byte + a "send" pulse, drives the tx
// line, and reports tx_busy. Baud timing is generated internally from
// a baud_tick input (one pulse per bit period), produced by a shared
// baud rate generator inside uart_top.sv so tx/rx stay synchronized
// to the same baud rate.
// =====================================================================

module uart_tx (
    input  logic         clk,
    input  logic         rst_n,

    input  logic          baud_tick,    // one pulse per bit period
    input  logic [7:0]   tx_data,
    input  logic          tx_start,     // pulse: begin sending tx_data
    output logic          tx_busy,

    output logic          tx_line       // idles high
);

    typedef enum logic [1:0] {T_IDLE, T_START, T_DATA, T_STOP} tx_state_e;
    tx_state_e state;

    logic [2:0] bit_idx;
    logic [7:0] shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= T_IDLE;
            tx_line   <= 1'b1;
            tx_busy   <= 1'b0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                T_IDLE: begin
                    tx_line <= 1'b1;
                    if (tx_start) begin
                        tx_busy   <= 1'b1;
                        shift_reg <= tx_data;
                        state     <= T_START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                T_START: begin
                    if (baud_tick) begin
                        tx_line <= 1'b0;      // start bit
                        bit_idx <= 3'd0;
                        state   <= T_DATA;
                    end
                end

                T_DATA: begin
                    if (baud_tick) begin
                        tx_line   <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7)
                            state <= T_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end
                end

                T_STOP: begin
                    if (baud_tick) begin
                        tx_line <= 1'b1;      // stop bit
                        tx_busy <= 1'b0;
                        state   <= T_IDLE;
                    end
                end

                default: state <= T_IDLE;
            endcase
        end
    end

endmodule
