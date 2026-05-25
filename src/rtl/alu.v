`timescale 1ns / 1ps
// ============================================================================
// ALU - Arithmetic Logic Unit for CPU_YELLOW
// Supports all 57 MIPS instructions' ALU operations
// ============================================================================

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_op,
    input  wire [4:0]  shamt,
    output reg  [31:0] result,
    output wire        overflow,
    output wire        zero
);

    // ALU operation codes
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
        case (alu_op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_XOR:    result = a ^ b;
            ALU_NOR:    result = ~(a | b);
            ALU_SLT:    result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU:   result = (a < b) ? 32'd1 : 32'd0;
            ALU_SLL:    result = b << shamt;
            ALU_SRL:    result = b >> shamt;
            ALU_SRA:    result = $signed(b) >>> shamt;
            ALU_SLLV:   result = b << a[4:0];
            ALU_SRLV:   result = b >> a[4:0];
            ALU_SRAV:   result = $signed(b) >>> a[4:0];
            ALU_LUI:    result = {b[15:0], 16'b0};
            ALU_PASS_B: result = b;
            default:    result = 32'd0;
        endcase
    end

    // Overflow detection for signed ADD and SUB
    assign overflow = (alu_op == ALU_ADD) ?
        ((a[31] == b[31]) && (result[31] != a[31])) :
        ((alu_op == ALU_SUB) ?
        ((a[31] != b[31]) && (result[31] != a[31])) : 1'b0);

    // Zero flag
    assign zero = (result == 32'd0);

endmodule
