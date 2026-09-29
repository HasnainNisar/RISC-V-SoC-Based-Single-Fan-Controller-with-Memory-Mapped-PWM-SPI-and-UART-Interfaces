`timescale 1ns/1ps
// =====================================================================
// dmem.sv - Data SRAM (general-purpose read/write)
//
// Depth: 1024 words x 32-bit = 4 KB (matches memory_map.md: 0x1000_0000
// - 0x1000_0FFF)
// Synchronous write, combinational (asynchronous) read so the
// single-cycle core can read data in the same cycle it is addressed.
// This module is instantiated behind the address decoder (Phase 4);
// `sel` qualifies we/re so this SRAM only responds to its own region.
// =====================================================================

module dmem #(
    parameter int DEPTH_WORDS = 1024
) (
    input  logic         clk,
    input  logic         sel,        // this memory is selected by decoder
    input  logic [31:0]  addr,       // byte address within region
    input  logic [31:0]  wdata,
    input  logic [3:0]   be,         // byte enables (SB/SH/SW)
    input  logic          we,
    input  logic          re,
    output logic [31:0]  rdata
);

    localparam int ADDR_BITS = $clog2(DEPTH_WORDS);

    logic [31:0] mem [0:DEPTH_WORDS-1];

    wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];

    always_ff @(posedge clk) begin
        if (sel && we) begin
            if (be[0]) mem[word_idx][7:0]   <= wdata[7:0];
            if (be[1]) mem[word_idx][15:8]  <= wdata[15:8];
            if (be[2]) mem[word_idx][23:16] <= wdata[23:16];
            if (be[3]) mem[word_idx][31:24] <= wdata[31:24];
        end
    end

    assign rdata = (sel && re) ? mem[word_idx] : 32'd0;

endmodule
