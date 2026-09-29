`timescale 1ns/1ps
// =====================================================================
// uart_terminal_model.sv - UART Terminal Model (testbench-side)
//
// Not a DUT peripheral -- represents an external terminal/host (e.g.
// a PC running a serial monitor) that talks to the SoC's UART:
//   - send_byte(data)  : drives term_tx_line (-> connects to DUT rx_line)
//                        with a correctly-framed UART byte.
//   - Passive receiver : continuously watches term_rx_line (<- connects
//                        to DUT tx_line) and decodes any byte the SoC
//                        transmits into rx_byte_queue for the testbench
//                        to check (e.g. "Fan running at 80%, RPM=1400"
//                        style status bytes from architecture.md).
//
// Timing is driven by BIT_PERIOD_NS directly (delay-based), matching
// the CLKS_PER_BIT setting used in uart_rx.sv / uart_top.sv for the
// same baud rate. This model is for simulation only, not synthesis.
// =====================================================================

module uart_terminal_model #(
    parameter real BIT_PERIOD_NS = 17360.0 // e.g. matches 57600 baud approx
) (
    output logic term_tx_line,   // terminal's TX -> connects to DUT rx_line
    input  logic term_rx_line    // terminal's RX <- connects to DUT tx_line
);

    // Queue of bytes received from the DUT (for TB checking)
    logic [7:0] rx_byte_queue [$];
    int         rx_frame_errors;

    initial begin
        term_tx_line     = 1'b1; // idle high
        rx_frame_errors  = 0;
    end

    // -------------------------------------------------------------
    // send_byte: drives a full UART frame onto term_tx_line
    // -------------------------------------------------------------
    task automatic send_byte(input [7:0] data);
        integer i;
        begin
            term_tx_line = 1'b0; // start bit
            #(BIT_PERIOD_NS);
            for (i = 0; i < 8; i = i + 1) begin
                term_tx_line = data[i]; // LSB first
                #(BIT_PERIOD_NS);
            end
            term_tx_line = 1'b1; // stop bit
            #(BIT_PERIOD_NS);
        end
    endtask

    // -------------------------------------------------------------
    // Passive receiver process: decodes bytes arriving on
    // term_rx_line (driven by the DUT's UART transmitter)
    // -------------------------------------------------------------
    initial begin
        logic [7:0] byte_recv;
        forever begin
            @(negedge term_rx_line); // wait for start bit
            #(BIT_PERIOD_NS / 2.0);  // move to middle of start bit
            if (term_rx_line !== 1'b0) begin
                // false start (glitch), ignore
            end else begin
                #(BIT_PERIOD_NS);
                for (int i = 0; i < 8; i++) begin
                    byte_recv[i] = term_rx_line;
                    #(BIT_PERIOD_NS);
                end
                if (term_rx_line === 1'b1) begin
                    rx_byte_queue.push_back(byte_recv);
                end else begin
                    rx_frame_errors++;
                end
            end
        end
    end

    // Convenience function for the testbench to pop the next
    // received byte (returns 1 if a byte was available)
    function automatic bit get_next_byte(output [7:0] data);
        if (rx_byte_queue.size() > 0) begin
            data = rx_byte_queue.pop_front();
            return 1'b1;
        end else begin
            data = 8'd0;
            return 1'b0;
        end
    endfunction

endmodule
