`timescale 1ns / 1ps
// ============================================================================
// ALU Control Unit
// Generates ALU operation code based on instruction type
// ============================================================================

module alu_control (
    input  wire [5:0]  funct,
    input  wire [5:0]  opcode,
    input  wire [1:0]  alu_op_ctrl,
    output reg  [3:0]  alu_op
);

    // ALUOp control from main control unit:
    // 2'b00: lw/sw/lb/sb/lh/sh (ADD)
    // 2'b01: beq/bne (SUB for comparison)
    // 2'b10: R-type (determined by funct)
    // 2'b11: I-type immediate (determined by opcode)

    localparam ALU_ADD    = 4'h0;
    localparam ALU_SUB    = 4'h1;
    localparam ALU_AND    = 4'h2;
    localparam ALU_OR     = 4'h3;
    localparam ALU_XOR    = 4'h4;
    localparam ALU_NOR    = 4'h5;
    localparam ALU_SLT    = 4'h6;
    localparam ALU_SLTU   = 4'h7;
    localparam ALU_SLL    = 4'h8;
    localparam ALU_SRL    = 4'h9;
    localparam ALU_SRA    = 4'hA;
    localparam ALU_LUI    = 4'hB;
    localparam ALU_PASS_B = 4'hC;
    localparam ALU_SLLV   = 4'hD;
    localparam ALU_SRLV   = 4'hE;
    localparam ALU_SRAV   = 4'hF;

    always @(*) begin
        case (alu_op_ctrl)
            2'b00: begin
                // Load/Store: ADD for address calculation
                alu_op = ALU_ADD;
            end
            2'b01: begin
                // Branch: SUB for comparison
                alu_op = ALU_SUB;
            end
            2'b10: begin
                // R-type: determined by funct field
                case (funct)
                    6'h20: alu_op = ALU_ADD;    // ADD
                    6'h21: alu_op = ALU_ADD;    // ADDU
                    6'h22: alu_op = ALU_SUB;    // SUB
                    6'h23: alu_op = ALU_SUB;    // SUBU
                    6'h24: alu_op = ALU_AND;    // AND
                    6'h25: alu_op = ALU_OR;     // OR
                    6'h26: alu_op = ALU_XOR;    // XOR
                    6'h27: alu_op = ALU_NOR;    // NOR
                    6'h2A: alu_op = ALU_SLT;    // SLT
                    6'h2B: alu_op = ALU_SLTU;   // SLTU
                    6'h00: alu_op = ALU_SLL;    // SLL
                    6'h02: alu_op = ALU_SRL;    // SRL
                    6'h03: alu_op = ALU_SRA;    // SRA
                    6'h04: alu_op = ALU_SLLV;   // SLLV
                    6'h06: alu_op = ALU_SRLV;   // SRLV
                    6'h07: alu_op = ALU_SRAV;   // SRAV
                    6'h08: alu_op = ALU_PASS_B; // JR
                    6'h09: alu_op = ALU_PASS_B; // JALR
                    default: alu_op = ALU_ADD;
                endcase
            end
            2'b11: begin
                // I-type immediate: determined by opcode
                case (opcode)
                    6'h08: alu_op = ALU_ADD;    // ADDI
                    6'h09: alu_op = ALU_ADD;    // ADDIU
                    6'h0A: alu_op = ALU_SLT;    // SLTI
                    6'h0B: alu_op = ALU_SLTU;   // SLTIU
                    6'h0C: alu_op = ALU_AND;    // ANDI
                    6'h0D: alu_op = ALU_OR;     // ORI
                    6'h0E: alu_op = ALU_XOR;    // XORI
                    6'h0F: alu_op = ALU_LUI;    // LUI
                    default: alu_op = ALU_ADD;
                endcase
            end
            default: alu_op = ALU_ADD;
        endcase
    end

endmodule
