`timescale 1ns / 1ps
// ============================================================================
// WB Stage - Write Back
// Selects write-back data source and writes to register file
// ============================================================================

module wb_stage (
    input  wire        clk,
    input  wire        rst_n,

    // From MEM/WB
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] mem_data_i,
    input  wire [31:0] alu_result_i,
    input  wire [4:0]  write_reg_i,
    input  wire [31:0] hi_result_i,
    input  wire [31:0] lo_result_i,
    input  wire        reg_write_i,
    input  wire [1:0]  mem_to_reg_i,
    input  wire        jal_i,
    input  wire        hi_write_i,
    input  wire        lo_write_i,

    // CP0 data (for MFC0)
    input  wire [31:0] cp0_data,

    // Register file interface
    output reg  [31:0] reg_write_data,
    output reg  [4:0]  reg_write_addr,
    output reg         reg_write_en,

    // HI/LO write (these are handled in EX stage, but WB can also update)
    output reg  [31:0] hi_write_data,
    output reg  [31:0] lo_write_data,
    output reg         hi_wen,
    output reg         lo_wen
);

    // Write-back data selection
    always @(*) begin
        case (mem_to_reg_i)
            2'b00: reg_write_data = alu_result_i;   // ALU result
            2'b01: reg_write_data = mem_data_i;      // Memory data
            2'b10: reg_write_data = pc_plus4_i;       // PC+4 (JAL)
            2'b11: reg_write_data = cp0_data;          // CP0 data
            default: reg_write_data = alu_result_i;
        endcase
    end

    always @(*) begin
        reg_write_addr = write_reg_i;
        reg_write_en   = reg_write_i;
    end

    // HI/LO passthrough (actual write happens in EX stage HI/LO registers)
    always @(*) begin
        hi_write_data = hi_result_i;
        lo_write_data = lo_result_i;
        hi_wen = hi_write_i;
        lo_wen = lo_write_i;
    end

endmodule
