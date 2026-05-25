`timescale 1ns / 1ps
// ============================================================================
// Forwarding Unit
// Detects RAW hazards and generates forwarding control signals
// ============================================================================

module forwarding_unit (
    input  wire [4:0]  id_ex_rs,
    input  wire [4:0]  id_ex_rt,
    input  wire [4:0]  ex_mem_write_reg,
    input  wire        ex_mem_reg_write,
    input  wire [4:0]  mem_wb_write_reg,
    input  wire        mem_wb_reg_write,
    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b
);

    // Forwarding select codes
    localparam FW_NONE  = 2'b00;  // No forwarding (use regfile data)
    localparam FW_WB    = 2'b01;  // Forward from MEM/WB
    localparam FW_MEM   = 2'b10;  // Forward from EX/MEM

    always @(*) begin
        // Default: no forwarding
        forward_a = FW_NONE;
        forward_b = FW_NONE;

        // Forward A (rs operand)
        // Priority: EX/MEM over MEM/WB
        if (ex_mem_reg_write && (ex_mem_write_reg != 5'd0) &&
            (ex_mem_write_reg == id_ex_rs)) begin
            forward_a = FW_MEM;
        end else if (mem_wb_reg_write && (mem_wb_write_reg != 5'd0) &&
                     (mem_wb_write_reg == id_ex_rs)) begin
            forward_a = FW_WB;
        end

        // Forward B (rt operand)
        if (ex_mem_reg_write && (ex_mem_write_reg != 5'd0) &&
            (ex_mem_write_reg == id_ex_rt)) begin
            forward_b = FW_MEM;
        end else if (mem_wb_reg_write && (mem_wb_write_reg != 5'd0) &&
                     (mem_wb_write_reg == id_ex_rt)) begin
            forward_b = FW_WB;
        end
    end

endmodule
