`timescale 1ns / 1ps
// ============================================================================
// Hazard Detection Unit
// Detects Load-Use data hazards and generates stall signal
// ============================================================================

module hazard_detection (
    input  wire [4:0]  id_ex_rs,         // ID stage rs (instruction being decoded)
    input  wire [4:0]  id_ex_rt,         // ID stage rt
    input  wire [4:0]  id_ex_write_reg,  // ID/EX stage destination register (load in EX)
    input  wire        id_ex_mem_read,   // ID/EX stage is_load (load is in EX stage)
    output reg         stall,
    output reg         if_id_write,
    output reg         pc_write,
    output reg         id_ex_flush
);

    always @(*) begin
        // Default: no stall
        stall       = 1'b0;
        if_id_write = 1'b1;
        pc_write    = 1'b1;
        id_ex_flush = 1'b0;

        // Load-Use Hazard Detection
        // If the instruction in EX stage is a load and its destination
        // matches either source register of the instruction in ID stage,
        // stall the pipeline for one cycle.
        // The load result won't be available until the load reaches MEM/WB,
        // but the dependent instruction needs it in EX (one cycle too early).
        if (id_ex_mem_read &&
            (id_ex_write_reg != 5'd0) &&
            ((id_ex_write_reg == id_ex_rs) || (id_ex_write_reg == id_ex_rt))) begin
            stall       = 1'b1;
            if_id_write = 1'b0;    // Freeze IF/ID register
            pc_write    = 1'b0;    // Freeze PC
            id_ex_flush = 1'b1;    // Insert NOP in EX stage (convert to NOP)
        end
    end

endmodule
