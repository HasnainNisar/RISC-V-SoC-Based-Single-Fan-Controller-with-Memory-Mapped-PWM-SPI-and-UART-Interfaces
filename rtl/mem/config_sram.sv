`timescale 1ns/1ps
// =====================================================================
// config_sram.sv - Configuration SRAM (fan profiles / thresholds)
//
// Depth: 64 words x 32-bit = 256 B (matches memory_map.md: 0x2000_0000
// - 0x2000_00FF)
// Preloadable by testbench via $readmemh, and also writable at runtime
// (e.g. by the core after an SPI profile-fetch, or directly by
// the testbench forcing values in for directed tests).
// Synchronous write, combinational read.
// =====================================================================

module config_sram #(
    parameter int DEPTH_WORDS = 64,
    parameter string INIT_FILE = ""
) (
    input  logic         clk,
    input  logic         sel,
    input  logic [31:0]  addr,      // byte address within region
    input  logic [31:0]  wdata,
    input  logic [3:0]   be,         // byte enables (SB/SH/SW)
    input  logic          we,
    input  logic          re,
    output logic [31:0]  rdata
);

    localparam int ADDR_BITS = $clog2(DEPTH_WORDS);

    logic [31:0] mem [0:DEPTH_WORDS-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];

    // plain 'always' (not always_ff): the array is also loaded by $readmemh in the
    // initial block above, which SystemVerilog does not allow for always_ff variables.
    always @(posedge clk) begin
        if (sel && we) begin
            if (be[0]) mem[word_idx][7:0]   <= wdata[7:0];
            if (be[1]) mem[word_idx][15:8]  <= wdata[15:8];
            if (be[2]) mem[word_idx][23:16] <= wdata[23:16];
            if (be[3]) mem[word_idx][31:24] <= wdata[31:24];
        end
    end

    assign rdata = (sel && re) ? mem[word_idx] : 32'd0;

endmodule
