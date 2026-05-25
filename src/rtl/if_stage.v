`timescale 1ns / 1ps
// ============================================================================
// IF Stage - Instruction Fetch
// Manages PC, handles stalls, and generates instruction address
// Branch prediction: Always Taken
// ============================================================================

module if_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pc_write,          // Stall control
    input  wire [31:0] branch_target,     // From ID stage
    input  wire        is_taken,          // From ID stage
    input  wire        exception_occurred, // From CP0
    input  wire [31:0] exception_target,   // From CP0 (0xBFC0_0380)
    output reg  [31:0] pc,
    output reg  [31:0] pc_plus4,
    output reg  [31:0] instr_addr
);

    // Reset vector
    localparam RESET_VECTOR = 32'hBFC0_0000;

    reg [31:0] next_pc;

    // Next PC calculation (combinational)
    // Priority: exception > branch/jump > sequential
    always @(*) begin
        if (exception_occurred)
            next_pc = exception_target;
        else if (is_taken)
            next_pc = branch_target;
        else
            next_pc = pc_plus4;
    end

    // PC register and output
    // Exception bypasses stall: always update PC on exception
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc         <= RESET_VECTOR;
            pc_plus4   <= RESET_VECTOR + 32'd4;
            instr_addr <= RESET_VECTOR;
        end else if (pc_write || exception_occurred) begin
            pc         <= next_pc;
            pc_plus4   <= next_pc + 32'd4;
            instr_addr <= next_pc;
        end
    end

endmodule
