`timescale 1ns / 1ps
// ============================================================================
// EX Stage - Execute
// ALU operation, forwarding mux, branch resolution, HI/LO operations
// ============================================================================

module ex_stage (
    input  wire        clk,
    input  wire        rst_n,

    // From ID/EX
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] reg_data1,
    input  wire [31:0] reg_data2,
    input  wire [31:0] sign_ext_imm,
    input  wire [4:0]  rs_addr,
    input  wire [4:0]  rt_addr,
    input  wire [4:0]  rd_addr,
    input  wire [5:0]  opcode,
    input  wire [5:0]  funct,
    input  wire [4:0]  shamt,
    input  wire        reg_dst_i,
    input  wire        alu_src_i,
    input  wire [1:0]  mem_to_reg_i,
    input  wire        reg_write_i,
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        branch_i,
    input  wire        jump_i,
    input  wire        jal_i,
    input  wire        jr_i,
    input  wire [1:0]  alu_op_i,
    input  wire        is_load_i,
    input  wire        is_store_i,
    input  wire [2:0]  load_type_i,
    input  wire [2:0]  store_type_i,
    input  wire        hi_write_i,
    input  wire        lo_write_i,
    input  wire        hi_read_i,
    input  wire        lo_read_i,
    input  wire        cp0_read_i,
    input  wire        cp0_write_i,
    input  wire        eret_i,
    input  wire        syscall_i,
    input  wire        break_exc_i,
    input  wire        is_bgez_bltz_i,
    input  wire        is_branch_link_i,
    input  wire        invalid_instr_i,

    // Forwarding
    input  wire [1:0]  forward_a,
    input  wire [1:0]  forward_b,
    input  wire [31:0] ex_mem_alu_result,
    input  wire [31:0] mem_wb_write_data,
    input  wire [31:0] ex_mem_hi,
    input  wire [31:0] ex_mem_lo,
    input  wire [31:0] mem_wb_hi,
    input  wire [31:0] mem_wb_lo,

    // Branch correction
    output reg         branch_mispredict,
    output reg  [31:0] correct_pc,

    // Outputs to EX/MEM
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] alu_result,
    output reg  [31:0] reg_data2_o,
    output reg  [4:0]  write_reg,
    output reg  [31:0] hi_result,
    output reg  [31:0] lo_result,
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         reg_write_o,
    output reg  [1:0]  mem_to_reg_o,
    output reg         jal_o,
    output reg  [2:0]  load_type_o,
    output reg  [2:0]  store_type_o,
    output reg         hi_write_o,
    output reg         lo_write_o,
    output reg         cp0_read_o,
    output reg         cp0_write_o,
    output reg         cp0_write_reg_o,
    output reg         eret_o,
    output reg         syscall_o,
    output reg         break_exc_o,
    output reg         invalid_instr_o,
    output reg         overflow_exc,
    output reg  [4:0]  rd_addr_o,
    output reg  [5:0]  funct_o,

    // CP0 data
    output reg  [31:0] cp0_data,
    output reg  [4:0]  cp0_rd,
    output reg  [2:0]  cp0_sel,

    // DMEM read interface (driven from EX to pre-load dmem_rdata_reg)
    output wire        dmem_re_ex,
    output wire [31:0] dmem_addr_ex
);

    // Forwarding muxes
    wire [31:0] alu_a, alu_b;

    assign alu_a = (forward_a == 2'b10) ? ex_mem_alu_result :
                   (forward_a == 2'b01) ? mem_wb_write_data : reg_data1;

    assign alu_b = (forward_b == 2'b10) ? ex_mem_alu_result :
                   (forward_b == 2'b01) ? mem_wb_write_data : reg_data2;

    // ALU input B selection
    wire [31:0] alu_b_final = alu_src_i ? sign_ext_imm : alu_b;

    // ALU instance
    wire [31:0] alu_out;
    wire        alu_overflow, alu_zero;

    // Generate ALU op from alu_control
    wire [3:0] alu_op_code;
    alu_control u_alu_ctrl (
        .funct(funct),
        .opcode(opcode),
        .alu_op_ctrl(alu_op_i),
        .alu_op(alu_op_code)
    );

    alu u_alu (
        .a(alu_a),
        .b(alu_b_final),
        .alu_op(alu_op_code),
        .shamt(shamt),
        .result(alu_out),
        .overflow(alu_overflow),
        .zero(alu_zero)
    );

    // DMEM read interface: drive from EX stage so dmem_rdata_reg updates
    // at the EX→MEM transition, making data available during MEM stage.
    // This avoids the NBA race where MEM/WB captures stale dmem_rdata.
    assign dmem_re_ex   = is_load_i;
    assign dmem_addr_ex = alu_out;

    // Destination register selection
    wire [4:0] dest_reg = reg_dst_i ? rd_addr : rt_addr;

    // JAL writes to $31
    wire [4:0] dest_reg_final = jal_i ? 5'd31 : dest_reg;

    // HI/LO operations
    reg [31:0] hi_reg, lo_reg;

    // HI/LO forwarding
    wire [31:0] hi_in, lo_in;
    assign hi_in = hi_read_i ? ((forward_a == 2'b10) ? ex_mem_hi :
                                (forward_a == 2'b01) ? mem_wb_hi : hi_reg) : 32'd0;
    assign lo_in = lo_read_i ? ((forward_a == 2'b10) ? ex_mem_lo :
                                (forward_a == 2'b01) ? mem_wb_lo : lo_reg) : 32'd0;

    // HI/LO write logic
    wire is_mult  = (opcode == 6'h00) && (funct == 6'h18);
    wire is_multu = (opcode == 6'h00) && (funct == 6'h19);
    wire is_div   = (opcode == 6'h00) && (funct == 6'h1A);
    wire is_divu  = (opcode == 6'h00) && (funct == 6'h1B);
    wire is_mthi  = (opcode == 6'h00) && (funct == 6'h11);
    wire is_mtlo  = (opcode == 6'h00) && (funct == 6'h13);

    wire [63:0] mult_result_signed   = $signed(alu_a) * $signed(alu_b);
    wire [63:0] mult_result_unsigned = alu_a * alu_b;
    wire [63:0] mult_result = is_multu ? mult_result_unsigned : mult_result_signed;

    reg [31:0] next_hi, next_lo;
    always @(*) begin
        next_hi = hi_reg;
        next_lo = lo_reg;
        if (is_mult || is_multu) begin
            next_hi = mult_result[63:32];
            next_lo = mult_result[31:0];
        end else if (is_div) begin
            if (alu_b != 32'd0) begin
                next_lo = $signed(alu_a) / $signed(alu_b);
                next_hi = $signed(alu_a) % $signed(alu_b);
            end
        end else if (is_divu) begin
            if (alu_b != 32'd0) begin
                next_lo = alu_a / alu_b;
                next_hi = alu_a % alu_b;
            end
        end else if (is_mthi) begin
            next_hi = alu_a;
        end else if (is_mtlo) begin
            next_lo = alu_a;
        end
    end

    // Result for MFHI/MFLO - these go through ALU as PASS_B or handled specially
    wire [31:0] result_final;
    wire is_mfhi = (opcode == 6'h00) && (funct == 6'h10);
    wire is_mflo = (opcode == 6'h00) && (funct == 6'h12);

    assign result_final = is_mfhi ? hi_in :
                          is_mflo ? lo_in : alu_out;

    // Branch misprediction detection
    // Always Taken: mispredict when branch instruction doesn't take
    // Branch condition: alu_zero for BEQ, !alu_zero for BNE
    // BGEZ/BLTZ already handled in ID stage with register read
    // Here we detect misprediction for BEQ/BNE
    wire branch_actually_taken_beq  = branch_i && (opcode == 6'h04) && alu_zero;
    wire branch_actually_taken_bne  = branch_i && (opcode == 6'h05) && !alu_zero;
    wire branch_actually_taken      = branch_actually_taken_beq || branch_actually_taken_bne;

    // For BEQ/BNE, prediction was "Always Taken"
    // Misprediction = branch_i is true but condition is false
    always @(*) begin
        branch_mispredict = 1'b0;
        correct_pc = 32'd0;
        if (branch_i && !branch_actually_taken && !is_bgez_bltz_i) begin
            branch_mispredict = 1'b1;
            correct_pc = pc_plus4_i;  // PC+4 (skip branch)
        end
    end

    // Combinational passthrough outputs (pipeline register is EX/MEM in top-level)
    always @(*) begin
        pc_plus4_o     = pc_plus4_i;
        alu_result     = result_final;
        reg_data2_o    = alu_b;          // Already forwarded value for stores
        write_reg      = dest_reg_final;
        hi_result      = next_hi;
        lo_result      = next_lo;
        mem_read_o     = mem_read_i;
        mem_write_o    = mem_write_i;
        reg_write_o    = reg_write_i;
        mem_to_reg_o   = mem_to_reg_i;
        jal_o          = jal_i;
        load_type_o    = load_type_i;
        store_type_o   = store_type_i;
        hi_write_o     = hi_write_i;
        lo_write_o     = lo_write_i;
        cp0_read_o     = cp0_read_i;
        cp0_write_o    = cp0_write_i;
        cp0_write_reg_o = 1'b0;         // Unused
        eret_o         = eret_i;
        syscall_o      = syscall_i;
        break_exc_o    = break_exc_i;
        invalid_instr_o = invalid_instr_i;
        overflow_exc   = alu_overflow && ((opcode == 6'h00 && funct == 6'h20) ||  // ADD
                                           (opcode == 6'h00 && funct == 6'h22) ||  // SUB
                                           (opcode == 6'h08));                      // ADDI
        rd_addr_o      = rd_addr;
        funct_o        = funct;
        cp0_data       = alu_b;      // GPR[rt] for MTC0
        cp0_rd         = rd_addr;    // rd field for CP0 register
        cp0_sel        = 3'd0;       // sel is 0 in our implementation
    end

    // HI/LO state registers (must remain sequential)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hi_reg <= 32'd0;
            lo_reg <= 32'd0;
        end else begin
            hi_reg <= next_hi;
            lo_reg <= next_lo;
        end
    end

endmodule
