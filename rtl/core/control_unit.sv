`timescale 1ns/1ps
// =====================================================================
// control_unit.sv - RV32I Control Unit (combinational decoder)
// Decodes opcode/funct3/funct7 into datapath control signals.
// =====================================================================

module control_unit
    import alu_pkg::*;
(
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,

    output alu_op_e     alu_op,
    output logic        alu_src_b,   // 0 = rs2, 1 = immediate
    output logic        mem_we,      // data memory write enable
    output logic        mem_re,      // data memory read enable
    output logic        reg_we,      // register file write enable
    output logic [1:0]  wb_sel,      // writeback mux select
    output logic        branch,      // is a branch instruction
    output logic        jump,        // is JAL/JALR
    output logic        jalr,        // specifically JALR (uses rs1+imm)
    output logic        pc_plus_imm_for_auipc, // AUIPC uses PC as operand_a
    output logic        illegal_instr
);

    // wb_sel encoding:
    //   00 -> ALU result
    //   01 -> Data memory read data
    //   10 -> PC + 4  (for JAL/JALR return address)
    //   11 -> Immediate (for LUI)

    always_comb begin
        // Defaults
        alu_op        = ALU_ADD;
        alu_src_b     = 1'b0;
        mem_we        = 1'b0;
        mem_re        = 1'b0;
        reg_we        = 1'b0;
        wb_sel        = 2'b00;
        branch        = 1'b0;
        jump          = 1'b0;
        jalr          = 1'b0;
        pc_plus_imm_for_auipc = 1'b0;
        illegal_instr = 1'b0;

        case (opcode)
            // ---------------- R-type ----------------
            7'b0110011: begin
                reg_we    = 1'b1;
                alu_src_b = 1'b0;
                wb_sel    = 2'b00;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: alu_op = ALU_ADD;
                    {7'b0100000, 3'b000}: alu_op = ALU_SUB;
                    {7'b0000000, 3'b111}: alu_op = ALU_AND;
                    {7'b0000000, 3'b110}: alu_op = ALU_OR;
                    {7'b0000000, 3'b100}: alu_op = ALU_XOR;
                    {7'b0000000, 3'b001}: alu_op = ALU_SLL;
                    {7'b0000000, 3'b101}: alu_op = ALU_SRL;
                    {7'b0100000, 3'b101}: alu_op = ALU_SRA;
                    {7'b0000000, 3'b010}: alu_op = ALU_SLT;
                    {7'b0000000, 3'b011}: alu_op = ALU_SLTU;
                    default: illegal_instr = 1'b1;
                endcase
            end

            // ---------------- I-type ALU (OP-IMM) ----------------
            7'b0010011: begin
                reg_we    = 1'b1;
                alu_src_b = 1'b1;
                wb_sel    = 2'b00;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;  // ADDI
                    3'b111: alu_op = ALU_AND;  // ANDI
                    3'b110: alu_op = ALU_OR;   // ORI
                    3'b100: alu_op = ALU_XOR;  // XORI
                    3'b010: alu_op = ALU_SLT;  // SLTI
                    3'b011: alu_op = ALU_SLTU; // SLTIU
                    3'b001: alu_op = ALU_SLL;  // SLLI
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRAI/SRLI
                    default: illegal_instr = 1'b1;
                endcase
            end

            // ---------------- Loads ----------------
            7'b0000011: begin
                reg_we    = 1'b1;
                alu_src_b = 1'b1;
                alu_op    = ALU_ADD;
                mem_re    = 1'b1;
                wb_sel    = 2'b01;
                // funct3 selects width (LB/LH/LW/LBU/LHU); handled in the core's load path
            end

            // ---------------- Stores ----------------
            7'b0100011: begin
                alu_src_b = 1'b1;
                alu_op    = ALU_ADD;
                mem_we    = 1'b1;
            end

            // ---------------- Branches ----------------
            7'b1100011: begin
                branch    = 1'b1;
                alu_src_b = 1'b0;
                case (funct3)
                    3'b000: alu_op = ALU_SUB;  // BEQ
                    3'b001: alu_op = ALU_SUB;  // BNE
                    3'b100: alu_op = ALU_SLT;  // BLT
                    3'b101: alu_op = ALU_SLT;  // BGE
                    3'b110: alu_op = ALU_SLTU; // BLTU
                    3'b111: alu_op = ALU_SLTU; // BGEU
                    default: illegal_instr = 1'b1;
                endcase
            end

            // ---------------- LUI ----------------
            7'b0110111: begin
                reg_we = 1'b1;
                wb_sel = 2'b11; // pass immediate straight to writeback
            end

            // ---------------- AUIPC ----------------
            7'b0010111: begin
                reg_we = 1'b1;
                alu_src_b = 1'b1;
                alu_op = ALU_ADD;
                wb_sel = 2'b00;
                pc_plus_imm_for_auipc = 1'b1;
            end

            // ---------------- JAL ----------------
            7'b1101111: begin
                reg_we = 1'b1;
                jump   = 1'b1;
                wb_sel = 2'b10; // PC + 4
            end

            // ---------------- JALR ----------------
            7'b1100111: begin
                reg_we    = 1'b1;
                jump      = 1'b1;
                jalr      = 1'b1;
                alu_src_b = 1'b1;
                alu_op    = ALU_ADD;
                wb_sel    = 2'b10; // PC + 4
            end

            // ---------------- FENCE / ECALL / EBREAK ----------------
            // Single-core, in-order, no caches: FENCE is a NOP. ECALL/EBREAK
            // have no privileged machinery behind them and also act as NOPs.
            7'b0001111,
            7'b1110011: begin
                // no architectural effect
            end

            default: begin
                illegal_instr = 1'b1;
            end
        endcase
    end

endmodule
