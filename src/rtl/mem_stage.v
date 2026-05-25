`timescale 1ns / 1ps
// ============================================================================
// MEM Stage - Memory Access
// Data memory interface, load/store alignment and sign extension
// ============================================================================

module mem_stage (
    input  wire        clk,
    input  wire        rst_n,

    // From EX/MEM
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] alu_result_i,
    input  wire [31:0] reg_data2_i,
    input  wire [4:0]  write_reg_i,
    input  wire [31:0] hi_result_i,
    input  wire [31:0] lo_result_i,
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        reg_write_i,
    input  wire [1:0]  mem_to_reg_i,
    input  wire        jal_i,
    input  wire [2:0]  load_type_i,
    input  wire [2:0]  store_type_i,
    input  wire        hi_write_i,
    input  wire        lo_write_i,
    input  wire        cp0_read_i,
    input  wire        cp0_write_i,
    input  wire        eret_i,
    input  wire        syscall_i,
    input  wire        break_exc_i,
    input  wire        invalid_instr_i,
    input  wire        overflow_exc_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [5:0]  funct_i,
    input  wire [31:0] cp0_data_i,
    input  wire [4:0]  cp0_rd_i,
    input  wire [2:0]  cp0_sel_i,

    // Data memory interface
    input  wire [31:0] dmem_rdata,
    output reg  [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg         dmem_we,
    output reg         dmem_re,

    // CP0 interface
    input  wire [31:0] cp0_data_out,
    input  wire        exception_occurred_cp0,
    input  wire [31:0] exception_target_cp0,
    output reg         cp0_read,
    output reg         cp0_write,
    output reg  [4:0]  cp0_addr,
    output reg  [2:0]  cp0_sel,
    output reg  [31:0] cp0_data_in,
    output reg  [4:0]  exception_type,
    output reg  [31:0] exception_pc,
    output reg         is_in_delay_slot,

    // Outputs to MEM/WB
    output wire [31:0] pc_plus4_o,
    output wire [31:0] mem_data,
    output wire [31:0] alu_result_o,
    output wire [4:0]  write_reg_o,
    output wire [31:0] hi_result_o,
    output wire [31:0] lo_result_o,
    output wire        reg_write_o,
    output wire [1:0]  mem_to_reg_o,
    output wire        jal_o,
    output wire        hi_write_o,
    output wire        lo_write_o
);

    // Load data alignment and sign extension
    wire [1:0] addr_low = alu_result_i[1:0];
    reg  [31:0] load_data;

    always @(*) begin
        case (load_type_i)
            3'b000: begin  // LB - signed byte
                case (addr_low)
                    2'b00: load_data = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                    2'b01: load_data = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'b10: load_data = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    2'b11: load_data = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end
            3'b001: begin  // LBU - unsigned byte
                case (addr_low)
                    2'b00: load_data = {24'b0, dmem_rdata[7:0]};
                    2'b01: load_data = {24'b0, dmem_rdata[15:8]};
                    2'b10: load_data = {24'b0, dmem_rdata[23:16]};
                    2'b11: load_data = {24'b0, dmem_rdata[31:24]};
                endcase
            end
            3'b010: begin  // LH - signed half
                case (addr_low)
                    2'b00: load_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                    2'b10: load_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                    default: load_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                endcase
            end
            3'b011: begin  // LHU - unsigned half
                case (addr_low)
                    2'b00: load_data = {16'b0, dmem_rdata[15:0]};
                    2'b10: load_data = {16'b0, dmem_rdata[31:16]};
                    default: load_data = {16'b0, dmem_rdata[31:16]};
                endcase
            end
            3'b100: begin  // LW
                load_data = dmem_rdata;
            end
            default: load_data = dmem_rdata;
        endcase
    end

    // Store data alignment
    reg [31:0] store_data;
    always @(*) begin
        case (store_type_i)
            3'b000: begin  // SB
                store_data = {4{reg_data2_i[7:0]}};
            end
            3'b010: begin  // SH
                store_data = {2{reg_data2_i[15:0]}};
            end
            3'b100: begin  // SW
                store_data = reg_data2_i;
            end
            default: store_data = reg_data2_i;
        endcase
    end

    // Address error detection
    wire addr_error_load  = mem_read_i  && (
        ((load_type_i == 3'b010 || load_type_i == 3'b011) && alu_result_i[0] != 1'b0) ||
        (load_type_i == 3'b100 && alu_result_i[1:0] != 2'b00)
    );
    wire addr_error_store = mem_write_i && (
        ((store_type_i == 3'b010) && alu_result_i[0] != 1'b0) ||
        (store_type_i == 3'b100 && alu_result_i[1:0] != 2'b00)
    );

    // Memory access
    always @(*) begin
        dmem_addr  = alu_result_i;
        dmem_wdata = store_data;
        dmem_we    = mem_write_i;
        dmem_re    = mem_read_i;
    end

    // CP0 interface
    always @(*) begin
        cp0_read   = cp0_read_i;
        cp0_write  = cp0_write_i;
        cp0_addr   = cp0_rd_i;
        cp0_sel    = cp0_sel_i;
        cp0_data_in = cp0_data_i;
    end

    // Exception handling
    always @(*) begin
        exception_type  = 5'h1F;  // No exception
        exception_pc     = pc_plus4_i - 32'd4;
        is_in_delay_slot = 1'b0;

        if (syscall_i)
            exception_type = 5'h08;  // Syscall
        else if (break_exc_i)
            exception_type = 5'h09;  // Breakpoint
        else if (invalid_instr_i)
            exception_type = 5'h0A;  // Reserved Instruction
        else if (overflow_exc_i)
            exception_type = 5'h0C;  // Overflow
        else if (addr_error_load)
            exception_type = 5'h04;  // Address Error Load
        else if (addr_error_store)
            exception_type = 5'h05;  // Address Error Store
    end

    // Combinational pass-through (no extra pipeline stage)
    assign pc_plus4_o   = pc_plus4_i;
    assign mem_data     = load_data;
    assign alu_result_o = alu_result_i;
    assign write_reg_o  = write_reg_i;
    assign hi_result_o  = hi_result_i;
    assign lo_result_o  = lo_result_i;
    assign reg_write_o  = reg_write_i;
    assign mem_to_reg_o = mem_to_reg_i;
    assign jal_o        = jal_i;
    assign hi_write_o   = hi_write_i;
    assign lo_write_o   = lo_write_i;

endmodule
