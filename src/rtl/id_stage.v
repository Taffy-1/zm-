`timescale 1ns / 1ps
// ============================================================================
// ID Stage - Instruction Decode
// Decodes instruction, reads registers, generates control signals,
// computes branch target, and handles BGEZ/BLTZ branches
// ============================================================================

module id_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] instr,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] reg_write_data,
    input  wire [4:0]  reg_write_addr,
    input  wire        reg_write_en,
    input  wire        id_ex_flush,     // Stall flush signal

    // Outputs to ID/EX pipeline register
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] reg_data1_o,
    output reg  [31:0] reg_data2_o,
    output reg  [31:0] sign_ext_imm,
    output reg  [4:0]  rs_addr,
    output reg  [4:0]  rt_addr,
    output reg  [4:0]  rd_addr,
    output reg  [5:0]  opcode_o,
    output reg  [5:0]  funct_o,
    output reg  [4:0]  shamt,

    // Control signals output
    output reg         reg_dst_o,
    output reg         alu_src_o,
    output reg  [1:0]  mem_to_reg_o,
    output reg         reg_write_o,
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         branch_o,
    output reg         jump_o,
    output reg         jal_o,
    output reg         jr_o,
    output reg  [1:0]  alu_op_o,
    output reg         is_load_o,
    output reg         is_store_o,
    output reg  [2:0]  load_type_o,
    output reg  [2:0]  store_type_o,
    output reg         hi_write_o,
    output reg         lo_write_o,
    output reg         hi_read_o,
    output reg         lo_read_o,
    output reg         cp0_read_o,
    output reg         cp0_write_o,
    output reg         eret_o,
    output reg         syscall_o,
    output reg         break_exc_o,

    // Branch control
    output reg  [31:0] branch_target,
    output reg         is_taken,
    output reg         is_branch,
    output reg         is_bgez_bltz_o,
    output reg         is_branch_link_o,
    output reg         invalid_instr_o,

    // Register file interface
    output wire [4:0]  rf_read_addr1,
    output wire [4:0]  rf_read_addr2,
    input  wire [31:0] rf_read_data1,
    input  wire [31:0] rf_read_data2
);

    // Instruction field extraction
    wire [5:0]  opcode = instr[31:26];
    wire [4:0]  rs     = instr[25:21];
    wire [4:0]  rt     = instr[20:16];
    wire [4:0]  rd     = instr[15:11];
    wire [4:0]  sa     = instr[10:6];
    wire [5:0]  funct  = instr[5:0];
    wire [15:0] imm    = instr[15:0];
    wire [25:0] target = instr[25:0];

    // Connect to register file read ports
    assign rf_read_addr1 = rs;
    assign rf_read_addr2 = rt;

    // Control unit outputs
    wire        cu_reg_dst, cu_alu_src, cu_reg_write, cu_mem_read, cu_mem_write;
    wire        cu_branch, cu_jump, cu_jal, cu_jr;
    wire        cu_is_load, cu_is_store, cu_is_branch_link;
    wire        cu_hi_write, cu_lo_write, cu_hi_read, cu_lo_read;
    wire        cu_cp0_read, cu_cp0_write, cu_eret, cu_syscall, cu_break_exc;
    wire        cu_is_bgez_bltz, cu_invalid_instr;
    wire [1:0]  cu_alu_op;
    wire [2:0]  cu_load_type, cu_store_type;
    wire        cu_mem_to_reg_0, cu_mem_to_reg_1;

    control_unit u_control (
        .opcode(opcode),
        .funct(funct),
        .rt(rt),
        .reg_dst(cu_reg_dst),
        .alu_src(cu_alu_src),
        .mem_to_reg_0(cu_mem_to_reg_0),
        .mem_to_reg_1(cu_mem_to_reg_1),
        .reg_write(cu_reg_write),
        .mem_read(cu_mem_read),
        .mem_write(cu_mem_write),
        .branch(cu_branch),
        .jump(cu_jump),
        .jal(cu_jal),
        .jr(cu_jr),
        .alu_op(cu_alu_op),
        .is_load(cu_is_load),
        .is_store(cu_is_store),
        .load_type(cu_load_type),
        .store_type(cu_store_type),
        .is_branch_link(cu_is_branch_link),
        .hi_write(cu_hi_write),
        .lo_write(cu_lo_write),
        .hi_read(cu_hi_read),
        .lo_read(cu_lo_read),
        .cp0_read(cu_cp0_read),
        .cp0_write(cu_cp0_write),
        .eret(cu_eret),
        .syscall(cu_syscall),
        .break_exc(cu_break_exc),
        .is_bgez_bltz(cu_is_bgez_bltz),
        .invalid_instr(cu_invalid_instr)
    );

    // Immediate extension (sign-extend by default, zero-extend for logic ops)
    wire [31:0] sign_extended  = {{16{imm[15]}}, imm};
    wire [31:0] zero_extended  = {16'b0, imm};

    // Determine immediate type based on opcode
    wire use_zero_ext = (opcode == 6'h0C) || (opcode == 6'h0D) || (opcode == 6'h0E);
    wire [31:0] extended_imm = use_zero_ext ? zero_extended : sign_extended;

    // Branch target calculation
    wire [31:0] branch_offset = {sign_extended[29:0], 2'b00};
    wire [31:0] branch_addr   = pc_plus4_i + branch_offset;

    // Jump target
    wire [31:0] jump_target = {pc_plus4_i[31:28], target, 2'b00};

    // Branch condition evaluation
    wire is_beq  = (opcode == 6'h04);
    wire is_bne  = (opcode == 6'h05);
    wire is_blez = (opcode == 6'h06);
    wire is_bgtz = (opcode == 6'h07);

    // BGEZ/BLTZ: rt[0] distinguishes
    wire is_bgez = cu_is_bgez_bltz && (rt[0] == 1'b1);
    wire is_bltz = cu_is_bgez_bltz && (rt[0] == 1'b0);
    wire is_bgezal = cu_is_bgez_bltz && (rt == 5'b10001);
    wire is_bltzal = cu_is_bgez_bltz && (rt == 5'b10000);

    wire branch_cond;
    assign branch_cond =
        (is_beq  && (rf_read_data1 == rf_read_data2)) ||
        (is_bne  && (rf_read_data1 != rf_read_data2)) ||
        (is_blez && ($signed(rf_read_data1) <= 0))     ||
        (is_bgtz && ($signed(rf_read_data1) > 0))      ||
        (is_bgez && ($signed(rf_read_data1) >= 0))     ||
        (is_bltz && ($signed(rf_read_data1) < 0))      ||
        (is_bgezal && ($signed(rf_read_data1) >= 0))   ||
        (is_bltzal && ($signed(rf_read_data1) < 0));

    // Always Taken prediction: branch = 1 means predict taken
    // Actually, for always-taken, we predict taken when:
    // - It's a branch instruction (cu_branch active)
    // - For conditional branches, we always predict taken
    // When branch_cond == 0 for a branch: prediction was wrong -> flush

    // Target selection
    wire [31:0] target_mux;
    assign target_mux = cu_jr ? rf_read_data1 :
                        cu_jump ? jump_target : branch_addr;

    // Combinational output (pipeline register boundary is ID/EX in top-level)
    always @(*) begin
        // Data path: always pass through (valid even during flush, control signals gated)
        pc_plus4_o   = pc_plus4_i;
        reg_data1_o  = rf_read_data1;
        reg_data2_o  = rf_read_data2;
        sign_ext_imm = extended_imm;
        rs_addr      = rs;
        rt_addr      = rt;
        rd_addr      = rd;
        opcode_o     = opcode;
        funct_o      = funct;
        shamt        = sa;

        if (id_ex_flush) begin
            // Insert NOP on stall: zero all control signals
            reg_dst_o    = 1'b0;
            alu_src_o    = 1'b0;
            mem_to_reg_o = 2'b00;
            reg_write_o  = 1'b0;
            mem_read_o   = 1'b0;
            mem_write_o  = 1'b0;
            branch_o     = 1'b0;
            jump_o       = 1'b0;
            jal_o        = 1'b0;
            jr_o         = 1'b0;
            alu_op_o     = 2'b00;
            is_load_o    = 1'b0;
            is_store_o   = 1'b0;
            load_type_o  = 3'b000;
            store_type_o = 3'b000;
            hi_write_o   = 1'b0;
            lo_write_o   = 1'b0;
            hi_read_o    = 1'b0;
            lo_read_o    = 1'b0;
            cp0_read_o   = 1'b0;
            cp0_write_o  = 1'b0;
            eret_o       = 1'b0;
            syscall_o    = 1'b0;
            break_exc_o  = 1'b0;
            is_bgez_bltz_o   = 1'b0;
            is_branch_link_o = 1'b0;
            invalid_instr_o  = 1'b0;
        end else begin
            // Normal operation: control signals from control unit
            reg_dst_o    = cu_reg_dst;
            alu_src_o    = cu_alu_src;
            mem_to_reg_o = {cu_mem_to_reg_1, cu_mem_to_reg_0};
            reg_write_o  = cu_reg_write;
            mem_read_o   = cu_mem_read;
            mem_write_o  = cu_mem_write;
            branch_o     = cu_branch;
            jump_o       = cu_jump;
            jal_o        = cu_jal;
            jr_o         = cu_jr;
            alu_op_o     = cu_alu_op;
            is_load_o    = cu_is_load;
            is_store_o   = cu_is_store;
            load_type_o  = cu_load_type;
            store_type_o = cu_store_type;
            hi_write_o   = cu_hi_write;
            lo_write_o   = cu_lo_write;
            hi_read_o    = cu_hi_read;
            lo_read_o    = cu_lo_read;
            cp0_read_o   = (opcode == 6'h10 && rs == 5'h00);
            cp0_write_o  = (opcode == 6'h10 && rs == 5'h04);
            eret_o       = (opcode == 6'h10 && funct == 6'h18);
            syscall_o    = cu_syscall;
            break_exc_o  = cu_break_exc;
            is_bgez_bltz_o   = cu_is_bgez_bltz;
            is_branch_link_o = cu_is_branch_link;
            invalid_instr_o  = cu_invalid_instr;

            // MFC0 override: write CP0 data to GPR[rt]
            if (opcode == 6'h10 && rs == 5'h00) begin
                reg_write_o  = 1'b1;
                mem_to_reg_o = 2'b11;  // Select CP0 data in WB
                reg_dst_o    = 1'b0;   // Destination is rt (not rd)
            end

            // MTC0 override: no GPR write
            if (opcode == 6'h10 && rs == 5'h04) begin
                reg_write_o  = 1'b0;
            end
        end
    end

    // Branch/Jump output (combinational - needed for next PC in same cycle)
    always @(*) begin
        is_taken = 1'b0;
        branch_target = pc_plus4_i + 32'd4;  // default

        if (cu_jump) begin
            // Unconditional jump: always taken
            is_taken = 1'b1;
            branch_target = jump_target;
        end else if (cu_jr) begin
            // JR/JALR: always taken
            is_taken = 1'b1;
            branch_target = rf_read_data1;
        end else if (cu_branch) begin
            // Always Taken prediction
            is_taken = 1'b1;
            branch_target = branch_addr;
        end
    end

    always @(*) begin
        is_branch = cu_branch;
    end

endmodule
