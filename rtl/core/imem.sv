`timescale 1ns/1ps
// =====================================================================
// imem.sv - Instruction SRAM (read-only during execution)
//
// Depth: 1024 words x 32-bit = 4 KB (matches memory_map.md: 0x0000_0000
// - 0x0000_0FFF)
// Preloaded by the testbench using $readmemh on a .hex file.
// Combinational read (single-cycle core fetches instruction same cycle
// as PC update).
// =====================================================================

module imem #(
    parameter int DEPTH_WORDS = 1024,
    parameter string INIT_FILE = ""   // optional, can also be loaded from TB
) (
    input  logic [31:0] addr,     // byte address (word-aligned, addr[1:0]=00)
    output logic [31:0] rdata
);

    localparam int ADDR_BITS = $clog2(DEPTH_WORDS);

    logic [31:0] mem [0:DEPTH_WORDS-1];

`ifndef SYNTHESIS
    // Simulation only: the program can be overridden at run time with
    //   vsim ... +IMEM=instr_test.hex
    string plusarg_file;
`endif

    // Program image: INIT_FILE is loaded in simulation AND synthesis (ROM contents);
    // only the +IMEM run-time override is simulation-only.
    initial begin
`ifndef SYNTHESIS
        if ($value$plusargs("IMEM=%s", plusarg_file))
            $readmemh(plusarg_file, mem);
        else
`endif
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Word index from byte address
    wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];

    assign rdata = mem[word_idx];

endmodule
