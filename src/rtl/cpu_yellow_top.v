`timescale 1ns / 1ps
// ============================================================================
// CPU_YELLOW_TOP - 5-Stage Pipelined MIPS Processor
//
// Features:
// - 57 MIPS32 instructions (arithmetic, logical, shift, branch, memory, privileged)
// - 5-stage pipeline: IF -> ID -> EX -> MEM -> WB
// - Full data forwarding (EX/MEM and MEM/WB -> EX)
// - Load-Use hazard detection with stall
// - Branch prediction: Always Taken with delay slot support
// - CP0 with Status, Cause, EPC registers
// - Exception handling (Syscall, Breakpoint, Overflow, Address Error, Reserved Instr)
// - Harvard architecture (separate I-Mem and D-Mem)
//
// Top-level ports (must match the spec exactly):
// ============================================================================

module cpu_yellow_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] instr,
    output wire [31:0] instr_addr,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,
    output wire        dmem_we,
    output wire        dmem_re
);

    // ========================================================================
    // IF Stage signals
    // ========================================================================
    wire        pc_write;
    wire [31:0] branch_target;
    wire        is_taken;
    wire [31:0] pc, pc_plus4_if;

    // ========================================================================
    // IF/ID Pipeline Register
    // ========================================================================
    reg [31:0] if_id_pc_plus4;
    reg [31:0] if_id_instr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc_plus4 <= 32'd0;
            if_id_instr    <= 32'd0;
        end else if (cp0_exception_occurred) begin
            // Flush IF/ID on exception: insert NOP
            if_id_pc_plus4 <= 32'd0;
            if_id_instr    <= 32'd0;
        end else if (pc_write) begin
            if_id_pc_plus4 <= pc_plus4_if;
            if_id_instr    <= instr;
        end
    end

    // ========================================================================
    // ID Stage signals
    // ========================================================================
    wire        id_ex_flush;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_reg_data1, id_reg_data2;
    wire [31:0] id_sign_ext_imm;
    wire [4:0]  id_rs, id_rt, id_rd;
    wire [5:0]  id_opcode, id_funct;
    wire [4:0]  id_shamt;
    wire        id_reg_dst, id_alu_src, id_reg_write, id_mem_read, id_mem_write;
    wire        id_branch, id_jump, id_jal, id_jr;
    wire        id_is_load, id_is_store;
    wire        id_hi_write, id_lo_write, id_hi_read, id_lo_read;
    wire        id_cp0_read, id_cp0_write, id_eret, id_syscall, id_break_exc;
    wire        id_is_bgez_bltz, id_is_branch_link, id_invalid_instr;
    wire [1:0]  id_alu_op;
    wire [2:0]  id_load_type, id_store_type;
    wire [1:0]  id_mem_to_reg;
    wire        id_is_taken, id_is_branch;

    // Register file read ports
    wire [31:0] rf_read_data1, rf_read_data2;

    // ========================================================================
    // ID/EX Pipeline Register
    // ========================================================================
    reg [31:0] id_ex_pc_plus4;
    reg [31:0] id_ex_reg_data1, id_ex_reg_data2;
    reg [31:0] id_ex_sign_ext_imm;
    reg [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;
    reg [5:0]  id_ex_opcode, id_ex_funct;
    reg [4:0]  id_ex_shamt;
    reg        id_ex_reg_dst, id_ex_alu_src, id_ex_reg_write;
    reg        id_ex_mem_read, id_ex_mem_write;
    reg        id_ex_branch, id_ex_jump, id_ex_jal, id_ex_jr;
    reg        id_ex_is_load, id_ex_is_store;
    reg        id_ex_hi_write, id_ex_lo_write, id_ex_hi_read, id_ex_lo_read;
    reg        id_ex_cp0_read, id_ex_cp0_write, id_ex_eret;
    reg        id_ex_syscall, id_ex_break_exc;
    reg        id_ex_is_bgez_bltz, id_ex_is_branch_link, id_ex_invalid_instr;
    reg [1:0]  id_ex_alu_op;
    reg [2:0]  id_ex_load_type, id_ex_store_type;
    reg [1:0]  id_ex_mem_to_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc_plus4    <= 32'd0;
            id_ex_reg_data1   <= 32'd0;
            id_ex_reg_data2   <= 32'd0;
            id_ex_sign_ext_imm <= 32'd0;
            id_ex_rs      <= 5'd0;
            id_ex_rt      <= 5'd0;
            id_ex_rd      <= 5'd0;
            id_ex_opcode  <= 6'd0;
            id_ex_funct   <= 6'd0;
            id_ex_shamt   <= 5'd0;
            id_ex_reg_dst <= 1'b0;
            id_ex_alu_src <= 1'b0;
            id_ex_mem_to_reg <= 2'b00;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
            id_ex_jal        <= 1'b0;
            id_ex_jr         <= 1'b0;
            id_ex_alu_op     <= 2'b00;
            id_ex_is_load    <= 1'b0;
            id_ex_is_store   <= 1'b0;
            id_ex_load_type  <= 3'b000;
            id_ex_store_type <= 3'b000;
            id_ex_hi_write   <= 1'b0;
            id_ex_lo_write   <= 1'b0;
            id_ex_hi_read    <= 1'b0;
            id_ex_lo_read    <= 1'b0;
            id_ex_cp0_read   <= 1'b0;
            id_ex_cp0_write  <= 1'b0;
            id_ex_eret       <= 1'b0;
            id_ex_syscall    <= 1'b0;
            id_ex_break_exc  <= 1'b0;
            id_ex_is_bgez_bltz    <= 1'b0;
            id_ex_is_branch_link  <= 1'b0;
            id_ex_invalid_instr   <= 1'b0;
        end else if (cp0_exception_occurred) begin
            // Flush ID/EX on exception: insert NOP (zero all control signals)
            id_ex_pc_plus4    <= 32'd0;
            id_ex_reg_data1   <= 32'd0;
            id_ex_reg_data2   <= 32'd0;
            id_ex_sign_ext_imm <= 32'd0;
            id_ex_rs      <= 5'd0;
            id_ex_rt      <= 5'd0;
            id_ex_rd      <= 5'd0;
            id_ex_opcode  <= 6'd0;
            id_ex_funct   <= 6'd0;
            id_ex_shamt   <= 5'd0;
            id_ex_reg_dst <= 1'b0;
            id_ex_alu_src <= 1'b0;
            id_ex_mem_to_reg <= 2'b00;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
            id_ex_jal        <= 1'b0;
            id_ex_jr         <= 1'b0;
            id_ex_alu_op     <= 2'b00;
            id_ex_is_load    <= 1'b0;
            id_ex_is_store   <= 1'b0;
            id_ex_load_type  <= 3'b000;
            id_ex_store_type <= 3'b000;
            id_ex_hi_write   <= 1'b0;
            id_ex_lo_write   <= 1'b0;
            id_ex_hi_read    <= 1'b0;
            id_ex_lo_read    <= 1'b0;
            id_ex_cp0_read   <= 1'b0;
            id_ex_cp0_write  <= 1'b0;
            id_ex_eret       <= 1'b0;
            id_ex_syscall    <= 1'b0;
            id_ex_break_exc  <= 1'b0;
            id_ex_is_bgez_bltz    <= 1'b0;
            id_ex_is_branch_link  <= 1'b0;
            id_ex_invalid_instr   <= 1'b0;
        end else begin
            id_ex_pc_plus4    <= id_pc_plus4;
            id_ex_reg_data1   <= id_reg_data1;
            id_ex_reg_data2   <= id_reg_data2;
            id_ex_sign_ext_imm <= id_sign_ext_imm;
            id_ex_rs      <= id_rs;
            id_ex_rt      <= id_rt;
            id_ex_rd      <= id_rd;
            id_ex_opcode  <= id_opcode;
            id_ex_funct   <= id_funct;
            id_ex_shamt   <= id_shamt;
            id_ex_reg_dst <= id_reg_dst;
            id_ex_alu_src <= id_alu_src;
            id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_reg_write  <= id_reg_write;
            id_ex_mem_read   <= id_mem_read;
            id_ex_mem_write  <= id_mem_write;
            id_ex_branch     <= id_branch;
            id_ex_jump       <= id_jump;
            id_ex_jal        <= id_jal;
            id_ex_jr         <= id_jr;
            id_ex_alu_op     <= id_alu_op;
            id_ex_is_load    <= id_is_load;
            id_ex_is_store   <= id_is_store;
            id_ex_load_type  <= id_load_type;
            id_ex_store_type <= id_store_type;
            id_ex_hi_write   <= id_hi_write;
            id_ex_lo_write   <= id_lo_write;
            id_ex_hi_read    <= id_hi_read;
            id_ex_lo_read    <= id_lo_read;
            id_ex_cp0_read   <= id_cp0_read;
            id_ex_cp0_write  <= id_cp0_write;
            id_ex_eret       <= id_eret;
            id_ex_syscall    <= id_syscall;
            id_ex_break_exc  <= id_break_exc;
            id_ex_is_bgez_bltz    <= id_is_bgez_bltz;
            id_ex_is_branch_link  <= id_is_branch_link;
            id_ex_invalid_instr   <= id_invalid_instr;
        end
    end

    // ========================================================================
    // Forwarding Unit
    // ========================================================================
    wire [1:0]  forward_a, forward_b;

    // ========================================================================
    // EX Stage signals
    // ========================================================================
    wire        ex_branch_mispredict;
    wire [31:0] ex_correct_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_alu_result;
    wire [31:0] ex_reg_data2;
    wire [4:0]  ex_write_reg;
    wire [31:0] ex_hi_result, ex_lo_result;
    wire        ex_mem_read, ex_mem_write, ex_reg_write;
    wire [1:0]  ex_mem_to_reg;
    wire        ex_jal;
    wire [2:0]  ex_load_type, ex_store_type;
    wire        ex_hi_write, ex_lo_write;
    wire        ex_cp0_read, ex_cp0_write;
    wire        ex_eret, ex_syscall, ex_break_exc, ex_invalid_instr;
    wire        ex_overflow_exc;
    wire [4:0]  ex_rd;
    wire [5:0]  ex_funct;
    wire [31:0] ex_cp0_data;
    wire [4:0]  ex_cp0_rd;
    wire [2:0]  ex_cp0_sel;
    wire        ex_dmem_re;
    wire [31:0] ex_dmem_addr;

    // ========================================================================
    // EX/MEM Pipeline Register
    // ========================================================================
    reg [31:0] ex_mem_pc_plus4;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_reg_data2;
    reg [4:0]  ex_mem_write_reg;
    reg [31:0] ex_mem_hi_result, ex_mem_lo_result;
    reg        ex_mem_mem_read, ex_mem_mem_write, ex_mem_reg_write;
    reg [1:0]  ex_mem_mem_to_reg;
    reg        ex_mem_jal;
    reg [2:0]  ex_mem_load_type, ex_mem_store_type;
    reg        ex_mem_hi_write, ex_mem_lo_write;
    reg        ex_mem_cp0_read, ex_mem_cp0_write;
    reg        ex_mem_eret;
    reg        ex_mem_syscall, ex_mem_break_exc, ex_mem_invalid_instr;
    reg        ex_mem_overflow_exc;
    reg [4:0]  ex_mem_rd;
    reg [5:0]  ex_mem_funct;
    reg [31:0] ex_mem_cp0_data;
    reg [4:0]  ex_mem_cp0_rd;
    reg [2:0]  ex_mem_cp0_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_pc_plus4   <= 32'd0;
            ex_mem_alu_result <= 32'd0;
            ex_mem_reg_data2  <= 32'd0;
            ex_mem_write_reg  <= 5'd0;
            ex_mem_hi_result  <= 32'd0;
            ex_mem_lo_result  <= 32'd0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_to_reg <= 2'b00;
            ex_mem_jal        <= 1'b0;
            ex_mem_load_type  <= 3'b000;
            ex_mem_store_type <= 3'b000;
            ex_mem_hi_write   <= 1'b0;
            ex_mem_lo_write   <= 1'b0;
            ex_mem_cp0_read   <= 1'b0;
            ex_mem_cp0_write  <= 1'b0;
            ex_mem_eret       <= 1'b0;
            ex_mem_syscall    <= 1'b0;
            ex_mem_break_exc  <= 1'b0;
            ex_mem_invalid_instr <= 1'b0;
            ex_mem_overflow_exc  <= 1'b0;
            ex_mem_rd         <= 5'd0;
            ex_mem_funct      <= 6'd0;
            ex_mem_cp0_data   <= 32'd0;
            ex_mem_cp0_rd     <= 5'd0;
            ex_mem_cp0_sel    <= 3'd0;
        end else if (cp0_exception_occurred) begin
            // Flush EX/MEM on exception: insert NOP (zero all control signals)
            ex_mem_pc_plus4   <= 32'd0;
            ex_mem_alu_result <= 32'd0;
            ex_mem_reg_data2  <= 32'd0;
            ex_mem_write_reg  <= 5'd0;
            ex_mem_hi_result  <= 32'd0;
            ex_mem_lo_result  <= 32'd0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_to_reg <= 2'b00;
            ex_mem_jal        <= 1'b0;
            ex_mem_load_type  <= 3'b000;
            ex_mem_store_type <= 3'b000;
            ex_mem_hi_write   <= 1'b0;
            ex_mem_lo_write   <= 1'b0;
            ex_mem_cp0_read   <= 1'b0;
            ex_mem_cp0_write  <= 1'b0;
            ex_mem_eret       <= 1'b0;
            ex_mem_syscall    <= 1'b0;
            ex_mem_break_exc  <= 1'b0;
            ex_mem_invalid_instr <= 1'b0;
            ex_mem_overflow_exc  <= 1'b0;
            ex_mem_rd         <= 5'd0;
            ex_mem_funct      <= 6'd0;
            ex_mem_cp0_data   <= 32'd0;
            ex_mem_cp0_rd     <= 5'd0;
            ex_mem_cp0_sel    <= 3'd0;
        end else begin
            ex_mem_pc_plus4   <= ex_pc_plus4;
            ex_mem_alu_result <= ex_alu_result;
            ex_mem_reg_data2  <= ex_reg_data2;
            ex_mem_write_reg  <= ex_write_reg;
            ex_mem_hi_result  <= ex_hi_result;
            ex_mem_lo_result  <= ex_lo_result;
            ex_mem_mem_read   <= ex_mem_read;
            ex_mem_mem_write  <= ex_mem_write;
            ex_mem_reg_write  <= ex_reg_write;
            ex_mem_mem_to_reg <= ex_mem_to_reg;
            ex_mem_jal        <= ex_jal;
            ex_mem_load_type  <= ex_load_type;
            ex_mem_store_type <= ex_store_type;
            ex_mem_hi_write   <= ex_hi_write;
            ex_mem_lo_write   <= ex_lo_write;
            ex_mem_cp0_read   <= ex_cp0_read;
            ex_mem_cp0_write  <= ex_cp0_write;
            ex_mem_eret       <= ex_eret;
            ex_mem_syscall    <= ex_syscall;
            ex_mem_break_exc  <= ex_break_exc;
            ex_mem_invalid_instr <= ex_invalid_instr;
            ex_mem_overflow_exc  <= ex_overflow_exc;
            ex_mem_rd         <= ex_rd;
            ex_mem_funct      <= ex_funct;
            ex_mem_cp0_data   <= ex_cp0_data;
            ex_mem_cp0_rd     <= ex_cp0_rd;
            ex_mem_cp0_sel    <= ex_cp0_sel;
        end
    end

    // ========================================================================
    // MEM Stage signals
    // ========================================================================
    wire [31:0] mem_dmem_addr, mem_dmem_wdata;
    wire        mem_dmem_we, mem_dmem_re;
    wire        mem_cp0_read, mem_cp0_write;
    wire [4:0]  mem_cp0_addr;
    wire [2:0]  mem_cp0_sel;
    wire [31:0] mem_cp0_data;
    wire [4:0]  mem_exception_type;
    wire [31:0] mem_exception_pc;
    wire        mem_is_in_delay_slot;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_mem_data;
    wire [31:0] mem_alu_result;
    wire [4:0]  mem_write_reg;
    wire [31:0] mem_hi_result, mem_lo_result;
    wire        mem_reg_write;
    wire [1:0]  mem_mem_to_reg;
    wire        mem_jal;
    wire        mem_hi_write, mem_lo_write;

    // ========================================================================
    // CP0 signals
    // ========================================================================
    wire [31:0] cp0_data_out;
    wire        cp0_exception_occurred;
    wire [31:0] cp0_exception_target;
    wire [31:0] cp0_epc;

    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    reg [31:0] mem_wb_pc_plus4;
    reg [31:0] mem_wb_mem_data;
    reg [31:0] mem_wb_alu_result;
    reg [4:0]  mem_wb_write_reg;
    reg [31:0] mem_wb_hi_result, mem_wb_lo_result;
    reg        mem_wb_reg_write;
    reg [1:0]  mem_wb_mem_to_reg;
    reg        mem_wb_jal;
    reg        mem_wb_hi_write, mem_wb_lo_write;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_pc_plus4  <= 32'd0;
            mem_wb_mem_data  <= 32'd0;
            mem_wb_alu_result <= 32'd0;
            mem_wb_write_reg <= 5'd0;
            mem_wb_hi_result <= 32'd0;
            mem_wb_lo_result <= 32'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_mem_to_reg <= 2'b00;
            mem_wb_jal       <= 1'b0;
            mem_wb_hi_write  <= 1'b0;
            mem_wb_lo_write  <= 1'b0;
        end else begin
            mem_wb_pc_plus4  <= mem_pc_plus4;
            mem_wb_mem_data  <= mem_mem_data;
            mem_wb_alu_result <= mem_alu_result;
            mem_wb_write_reg <= mem_write_reg;
            mem_wb_hi_result <= mem_hi_result;
            mem_wb_lo_result <= mem_lo_result;
            mem_wb_reg_write <= mem_reg_write;
            mem_wb_mem_to_reg <= mem_mem_to_reg;
            mem_wb_jal       <= mem_jal;
            mem_wb_hi_write  <= mem_hi_write;
            mem_wb_lo_write  <= mem_lo_write;
        end
    end

    // ========================================================================
    // WB Stage signals
    // ========================================================================
    wire [31:0] wb_reg_write_data;
    wire [4:0]  wb_reg_write_addr;
    wire        wb_reg_write_en;
    wire [31:0] wb_hi_write_data, wb_lo_write_data;
    wire        wb_hi_wen, wb_lo_wen;

    // ========================================================================
    // Stall and Hazard signals
    // ========================================================================
    wire stall, if_id_write, id_ex_flush_hazard;
    assign id_ex_flush = id_ex_flush_hazard || cp0_exception_occurred;
    assign pc_write = if_id_write;

    // DMEM read interface: dmem_re is driven from EX stage for loads,
    // so dmem_rdata_reg updates at EX→MEM transition (one cycle early).
    // dmem_addr is muxed: EX for loads (read address), MEM for stores (write address).
    assign dmem_re   = ex_dmem_re;
    assign dmem_addr = ex_dmem_re ? ex_dmem_addr : mem_dmem_addr;

    // ========================================================================
    // Module Instantiations
    // ========================================================================

    // IF Stage
    if_stage u_if (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_write      (pc_write),
        .branch_target (branch_target),
        .is_taken      (is_taken),
        .exception_occurred (cp0_exception_occurred),
        .exception_target   (cp0_exception_target),
        .pc            (pc),
        .pc_plus4      (pc_plus4_if),
        .instr_addr    (instr_addr)
    );

    // ID Stage
    id_stage u_id (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr            (if_id_instr),
        .pc_plus4_i       (if_id_pc_plus4),
        .reg_write_data   (wb_reg_write_data),
        .reg_write_addr   (wb_reg_write_addr),
        .reg_write_en     (wb_reg_write_en),
        .id_ex_flush      (id_ex_flush),
        .pc_plus4_o       (id_pc_plus4),
        .reg_data1_o      (id_reg_data1),
        .reg_data2_o      (id_reg_data2),
        .sign_ext_imm     (id_sign_ext_imm),
        .rs_addr          (id_rs),
        .rt_addr          (id_rt),
        .rd_addr          (id_rd),
        .opcode_o         (id_opcode),
        .funct_o          (id_funct),
        .shamt            (id_shamt),
        .reg_dst_o        (id_reg_dst),
        .alu_src_o        (id_alu_src),
        .mem_to_reg_o     (id_mem_to_reg),
        .reg_write_o      (id_reg_write),
        .mem_read_o       (id_mem_read),
        .mem_write_o      (id_mem_write),
        .branch_o         (id_branch),
        .jump_o           (id_jump),
        .jal_o            (id_jal),
        .jr_o             (id_jr),
        .alu_op_o         (id_alu_op),
        .is_load_o        (id_is_load),
        .is_store_o       (id_is_store),
        .load_type_o      (id_load_type),
        .store_type_o     (id_store_type),
        .hi_write_o       (id_hi_write),
        .lo_write_o       (id_lo_write),
        .hi_read_o        (id_hi_read),
        .lo_read_o        (id_lo_read),
        .cp0_read_o       (id_cp0_read),
        .cp0_write_o      (id_cp0_write),
        .eret_o           (id_eret),
        .syscall_o        (id_syscall),
        .break_exc_o      (id_break_exc),
        .is_bgez_bltz_o   (id_is_bgez_bltz),
        .is_branch_link_o (id_is_branch_link),
        .invalid_instr_o  (id_invalid_instr),
        .branch_target    (branch_target),
        .is_taken         (is_taken),
        .is_branch        (id_is_branch),
        .rf_read_addr1    (),
        .rf_read_addr2    (),
        .rf_read_data1    (rf_read_data1),
        .rf_read_data2    (rf_read_data2)
    );

    // Register File
    regfile u_regfile (
        .clk         (clk),
        .rst_n       (rst_n),
        .read_addr1  (if_id_instr[25:21]),  // rs
        .read_addr2  (if_id_instr[20:16]),  // rt
        .read_data1  (rf_read_data1),
        .read_data2  (rf_read_data2),
        .write_en    (wb_reg_write_en),
        .write_addr  (wb_reg_write_addr),
        .write_data  (wb_reg_write_data)
    );

    // ========================================================================
    // Hazard Detection - compute ID/EX write register for load-use detection
    // ========================================================================
    wire [4:0] id_ex_write_reg = id_ex_jal ? 5'd31 :
                                  (id_ex_reg_dst ? id_ex_rd : id_ex_rt);

    // Hazard Detection
    hazard_detection u_hazard (
        .id_ex_rs         (if_id_instr[25:21]),  // Use IF/ID directly (combinational)
        .id_ex_rt         (if_id_instr[20:16]),  // so it works during stalls
        .id_ex_write_reg  (id_ex_write_reg),
        .id_ex_mem_read   (id_ex_is_load),
        .stall            (stall),
        .if_id_write      (if_id_write),
        .pc_write         (),    // already connected via assign
        .id_ex_flush      (id_ex_flush_hazard)
    );

    // Forwarding Unit
    forwarding_unit u_forward (
        .id_ex_rs         (id_ex_rs),
        .id_ex_rt         (id_ex_rt),
        .ex_mem_write_reg (ex_mem_write_reg),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_write_reg (mem_wb_write_reg),
        .mem_wb_reg_write (mem_wb_reg_write),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // EX Stage
    ex_stage u_ex (
        .clk                 (clk),
        .rst_n               (rst_n),
        .pc_plus4_i          (id_ex_pc_plus4),
        .reg_data1           (id_ex_reg_data1),
        .reg_data2           (id_ex_reg_data2),
        .sign_ext_imm        (id_ex_sign_ext_imm),
        .rs_addr             (id_ex_rs),
        .rt_addr             (id_ex_rt),
        .rd_addr             (id_ex_rd),
        .opcode              (id_ex_opcode),
        .funct               (id_ex_funct),
        .shamt               (id_ex_shamt),
        .reg_dst_i           (id_ex_reg_dst),
        .alu_src_i           (id_ex_alu_src),
        .mem_to_reg_i        (id_ex_mem_to_reg),
        .reg_write_i         (id_ex_reg_write),
        .mem_read_i          (id_ex_mem_read),
        .mem_write_i         (id_ex_mem_write),
        .branch_i            (id_ex_branch),
        .jump_i              (id_ex_jump),
        .jal_i               (id_ex_jal),
        .jr_i                (id_ex_jr),
        .alu_op_i            (id_ex_alu_op),
        .is_load_i           (id_ex_is_load),
        .is_store_i          (id_ex_is_store),
        .load_type_i         (id_ex_load_type),
        .store_type_i        (id_ex_store_type),
        .hi_write_i          (id_ex_hi_write),
        .lo_write_i          (id_ex_lo_write),
        .hi_read_i           (id_ex_hi_read),
        .lo_read_i           (id_ex_lo_read),
        .cp0_read_i          (id_ex_cp0_read),
        .cp0_write_i         (id_ex_cp0_write),
        .eret_i              (id_ex_eret),
        .syscall_i           (id_ex_syscall),
        .break_exc_i         (id_ex_break_exc),
        .is_bgez_bltz_i      (id_ex_is_bgez_bltz),
        .is_branch_link_i    (id_ex_is_branch_link),
        .invalid_instr_i     (id_ex_invalid_instr),
        .forward_a           (forward_a),
        .forward_b           (forward_b),
        .ex_mem_alu_result   (ex_mem_alu_result),
        .mem_wb_write_data   (wb_reg_write_data),
        .ex_mem_hi           (ex_mem_hi_result),
        .ex_mem_lo           (ex_mem_lo_result),
        .mem_wb_hi           (mem_wb_hi_result),
        .mem_wb_lo           (mem_wb_lo_result),
        .branch_mispredict   (ex_branch_mispredict),
        .correct_pc          (ex_correct_pc),
        .pc_plus4_o          (ex_pc_plus4),
        .alu_result          (ex_alu_result),
        .reg_data2_o         (ex_reg_data2),
        .write_reg           (ex_write_reg),
        .hi_result           (ex_hi_result),
        .lo_result           (ex_lo_result),
        .mem_read_o          (ex_mem_read),
        .mem_write_o         (ex_mem_write),
        .reg_write_o         (ex_reg_write),
        .mem_to_reg_o        (ex_mem_to_reg),
        .jal_o               (ex_jal),
        .load_type_o         (ex_load_type),
        .store_type_o        (ex_store_type),
        .hi_write_o          (ex_hi_write),
        .lo_write_o          (ex_lo_write),
        .cp0_read_o          (ex_cp0_read),
        .cp0_write_o         (ex_cp0_write),
        .eret_o              (ex_eret),
        .syscall_o           (ex_syscall),
        .break_exc_o         (ex_break_exc),
        .invalid_instr_o     (ex_invalid_instr),
        .overflow_exc        (ex_overflow_exc),
        .rd_addr_o           (ex_rd),
        .funct_o             (ex_funct),
        .cp0_data            (ex_cp0_data),
        .cp0_rd              (ex_cp0_rd),
        .cp0_sel             (ex_cp0_sel),
        .cp0_write_reg_o     (),               // unused - tied in top level
        .dmem_re_ex          (ex_dmem_re),
        .dmem_addr_ex        (ex_dmem_addr)
    );

    // MEM Stage
    mem_stage u_mem (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .pc_plus4_i             (ex_mem_pc_plus4),
        .alu_result_i           (ex_mem_alu_result),
        .reg_data2_i            (ex_mem_reg_data2),
        .write_reg_i            (ex_mem_write_reg),
        .hi_result_i            (ex_mem_hi_result),
        .lo_result_i            (ex_mem_lo_result),
        .mem_read_i             (ex_mem_mem_read),
        .mem_write_i            (ex_mem_mem_write),
        .reg_write_i            (ex_mem_reg_write),
        .mem_to_reg_i           (ex_mem_mem_to_reg),
        .jal_i                  (ex_mem_jal),
        .load_type_i            (ex_mem_load_type),
        .store_type_i           (ex_mem_store_type),
        .hi_write_i             (ex_mem_hi_write),
        .lo_write_i             (ex_mem_lo_write),
        .cp0_read_i             (ex_mem_cp0_read),
        .cp0_write_i            (ex_mem_cp0_write),
        .eret_i                 (ex_mem_eret),
        .syscall_i              (ex_mem_syscall),
        .break_exc_i            (ex_mem_break_exc),
        .invalid_instr_i        (ex_mem_invalid_instr),
        .overflow_exc_i         (ex_mem_overflow_exc),
        .rd_addr_i              (ex_mem_rd),
        .funct_i                (ex_mem_funct),
        .cp0_data_i             (ex_mem_cp0_data),
        .cp0_rd_i               (ex_mem_cp0_rd),
        .cp0_sel_i              (ex_mem_cp0_sel),
        .dmem_rdata             (dmem_rdata),
        .dmem_addr              (mem_dmem_addr),  // Internal wire for store address
        .dmem_wdata             (dmem_wdata),
        .dmem_we                (dmem_we),
        .dmem_re                (),               // Not used; reads driven by EX stage
        .cp0_data_out           (cp0_data_out),
        .exception_occurred_cp0 (cp0_exception_occurred),
        .exception_target_cp0   (cp0_exception_target),
        .cp0_read               (mem_cp0_read),
        .cp0_write              (mem_cp0_write),
        .cp0_addr               (mem_cp0_addr),
        .cp0_sel                (mem_cp0_sel),
        .cp0_data_in            (mem_cp0_data),
        .exception_type         (mem_exception_type),
        .exception_pc           (mem_exception_pc),
        .is_in_delay_slot       (mem_is_in_delay_slot),
        .pc_plus4_o             (mem_pc_plus4),
        .mem_data               (mem_mem_data),
        .alu_result_o           (mem_alu_result),
        .write_reg_o            (mem_write_reg),
        .hi_result_o            (mem_hi_result),
        .lo_result_o            (mem_lo_result),
        .reg_write_o            (mem_reg_write),
        .mem_to_reg_o           (mem_mem_to_reg),
        .jal_o                  (mem_jal),
        .hi_write_o             (mem_hi_write),
        .lo_write_o             (mem_lo_write)
    );

    // CP0
    cp0 u_cp0 (
        .clk                 (clk),
        .rst_n               (rst_n),
        .cp0_read            (mem_cp0_read),
        .cp0_write           (mem_cp0_write),
        .cp0_addr            (mem_cp0_addr),
        .cp0_sel             (mem_cp0_sel),
        .cp0_data_in         (mem_cp0_data),
        .cp0_data_out        (cp0_data_out),
        .exception_type      (mem_exception_type),
        .exception_pc        (mem_exception_pc),
        .is_in_delay_slot    (mem_is_in_delay_slot),
        .exception_occurred  (cp0_exception_occurred),
        .exception_target    (cp0_exception_target),
        .eret                (ex_mem_eret),
        .epc_out             (cp0_epc)
    );

    // WB Stage
    wb_stage u_wb (
        .clk             (clk),
        .rst_n           (rst_n),
        .pc_plus4_i      (mem_wb_pc_plus4),
        .mem_data_i      (mem_wb_mem_data),
        .alu_result_i    (mem_wb_alu_result),
        .write_reg_i     (mem_wb_write_reg),
        .hi_result_i     (mem_wb_hi_result),
        .lo_result_i     (mem_wb_lo_result),
        .reg_write_i     (mem_wb_reg_write),
        .mem_to_reg_i    (mem_wb_mem_to_reg),
        .jal_i           (mem_wb_jal),
        .hi_write_i      (mem_wb_hi_write),
        .lo_write_i      (mem_wb_lo_write),
        .cp0_data        (cp0_data_out),
        .reg_write_data  (wb_reg_write_data),
        .reg_write_addr  (wb_reg_write_addr),
        .reg_write_en    (wb_reg_write_en),
        .hi_write_data   (wb_hi_write_data),
        .lo_write_data   (wb_lo_write_data),
        .hi_wen          (wb_hi_wen),
        .lo_wen          (wb_lo_wen)
    );

endmodule
