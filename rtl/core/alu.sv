`timescale 1ns/1ps
// =====================================================================
// alu.sv - RV32I Arithmetic Logic Unit (combinational)
// =====================================================================

// ALU operation encoding used by control_unit.sv
package alu_pkg;
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLL  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_SLT  = 4'b1000,
        ALU_SLTU = 4'b1001,
        ALU_PASS_B = 4'b1010 // used for LUI (result = operand_b)
    } alu_op_e;
endpackage

module alu
    import alu_pkg::*;
(
    input  logic [31:0]  operand_a,
    input  logic [31:0]  operand_b,
    input  alu_op_e      alu_op,

    output logic [31:0]  result,
    output logic          zero_flag   // result == 0
);

    logic [4:0] shamt;
    assign shamt = operand_b[4:0];

    always_comb begin
        case (alu_op)
            ALU_ADD    : result = operand_a + operand_b;
            ALU_SUB    : result = operand_a - operand_b;
            ALU_AND    : result = operand_a & operand_b;
            ALU_OR     : result = operand_a | operand_b;
            ALU_XOR    : result = operand_a ^ operand_b;
            ALU_SLL    : result = operand_a << shamt;
            ALU_SRL    : result = operand_a >> shamt;
            ALU_SRA    : result = $signed(operand_a) >>> shamt;
            ALU_SLT    : result = ($signed(operand_a) < $signed(operand_b)) ? 32'd1 : 32'd0;
            ALU_SLTU   : result = (operand_a < operand_b) ? 32'd1 : 32'd0;
            ALU_PASS_B : result = operand_b;
            default    : result = 32'd0;
        endcase
    end

    assign zero_flag = (result == 32'd0);

endmodule
