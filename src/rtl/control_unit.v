`timescale 1ns / 1ps
// ============================================================================
// Main Control Unit
// Decodes MIPS instructions and generates control signals
// Supports all 57 instructions
// ============================================================================

module control_unit (
    input  wire [5:0]  opcode,
    input  wire [5:0]  funct,
    input  wire [4:0]  rt,       // rt field for branch type detection
    output reg         reg_dst,
    output reg         alu_src,
    output reg         mem_to_reg_0,
    output reg         mem_to_reg_1,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         branch,
    output reg         jump,
    output reg         jal,
    output reg         jr,
    output reg  [1:0]  alu_op,
    output reg         is_load,
    output reg         is_store,
    output reg  [2:0]  load_type,
    output reg  [2:0]  store_type,
    output reg         is_branch_link,
    output reg         hi_write,
    output reg         lo_write,
    output reg         hi_read,
    output reg         lo_read,
    output reg         cp0_read,
    output reg         cp0_write,
    output reg         eret,
    output reg         syscall,
    output reg         break_exc,
    output reg         is_bgez_bltz,
    output reg         invalid_instr
);

    // R-type funct codes
    localparam F_JR      = 6'h08;
    localparam F_JALR    = 6'h09;
    localparam F_SYSCALL = 6'h0C;
    localparam F_BREAK   = 6'h0D;
    localparam F_MFHI    = 6'h10;
    localparam F_MTHI    = 6'h11;
    localparam F_MFLO    = 6'h12;
    localparam F_MTLO    = 6'h13;
    localparam F_MULT    = 6'h18;
    localparam F_MULTU   = 6'h19;
    localparam F_DIV     = 6'h1A;
    localparam F_DIVU    = 6'h1B;

    // I-type opcodes
    localparam OP_BGEZ_BLTZ = 6'h01;
    localparam OP_J      = 6'h02;
    localparam OP_JAL    = 6'h03;
    localparam OP_BEQ    = 6'h04;
    localparam OP_BNE    = 6'h05;
    localparam OP_BLEZ   = 6'h06;
    localparam OP_BGTZ   = 6'h07;
    localparam OP_ADDI   = 6'h08;
    localparam OP_ADDIU  = 6'h09;
    localparam OP_SLTI   = 6'h0A;
    localparam OP_SLTIU  = 6'h0B;
    localparam OP_ANDI   = 6'h0C;
    localparam OP_ORI    = 6'h0D;
    localparam OP_XORI   = 6'h0E;
    localparam OP_LUI    = 6'h0F;
    localparam OP_CP0    = 6'h10;
    localparam OP_LB     = 6'h20;
    localparam OP_LH     = 6'h21;
    localparam OP_LW     = 6'h23;
    localparam OP_LBU    = 6'h24;
    localparam OP_LHU    = 6'h25;
    localparam OP_SB     = 6'h28;
    localparam OP_SH     = 6'h29;
    localparam OP_SW     = 6'h2B;

    always @(*) begin
        // Default values
        reg_dst       = 1'b0;
        alu_src       = 1'b0;
        mem_to_reg_0  = 1'b0;
        mem_to_reg_1  = 1'b0;
        reg_write     = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        branch        = 1'b0;
        jump          = 1'b0;
        jal           = 1'b0;
        jr            = 1'b0;
        alu_op        = 2'b00;
        is_load       = 1'b0;
        is_store      = 1'b0;
        load_type     = 3'b000;
        store_type    = 3'b000;
        is_branch_link = 1'b0;
        hi_write      = 1'b0;
        lo_write      = 1'b0;
        hi_read       = 1'b0;
        lo_read       = 1'b0;
        cp0_read      = 1'b0;
        cp0_write     = 1'b0;
        eret          = 1'b0;
        syscall       = 1'b0;
        break_exc     = 1'b0;
        is_bgez_bltz  = 1'b0;
        invalid_instr = 1'b0;

        case (opcode)
            // ==================== R-Type ====================
            6'h00: begin
                case (funct)
                    // Arithmetic
                    F_JR: begin
                        jr      = 1'b1;
                        jump    = 1'b1;
                    end
                    F_JALR: begin
                        jr        = 1'b1;
                        jump      = 1'b1;
                        jal       = 1'b1;
                        reg_write = 1'b1;
                        reg_dst   = 1'b1;
                        mem_to_reg_0 = 1'b0;
                        mem_to_reg_1 = 1'b0;
                    end
                    F_SYSCALL: begin
                        syscall = 1'b1;
                    end
                    F_BREAK: begin
                        break_exc = 1'b1;
                    end
                    F_MFHI: begin
                        reg_write = 1'b1;
                        reg_dst   = 1'b1;
                        hi_read   = 1'b1;
                        // MFHI result goes through ALU (result_final mux in EX),
                        // so mem_to_reg = 2'b00 to select ALU result in WB
                        mem_to_reg_0 = 1'b0;
                        mem_to_reg_1 = 1'b0;
                    end
                    F_MTHI: begin
                        hi_write  = 1'b1;
                    end
                    F_MFLO: begin
                        reg_write = 1'b1;
                        reg_dst   = 1'b1;
                        lo_read   = 1'b1;
                        // MFLO result goes through ALU (result_final mux in EX),
                        // so mem_to_reg = 2'b00 to select ALU result in WB
                        mem_to_reg_0 = 1'b0;
                        mem_to_reg_1 = 1'b0;
                    end
                    F_MTLO: begin
                        lo_write  = 1'b1;
                    end
                    F_MULT, F_MULTU: begin
                        hi_write = 1'b1;
                        lo_write = 1'b1;
                    end
                    F_DIV, F_DIVU: begin
                        hi_write = 1'b1;
                        lo_write = 1'b1;
                    end
                    // SLL(00), SRL(02), SRA(03), SLLV(04), SRLV(06), SRAV(07)
                    6'h00, 6'h02, 6'h03, 6'h04, 6'h06, 6'h07,
                    // ADD(20), ADDU(21), SUB(22), SUBU(23),
                    6'h20, 6'h21, 6'h22, 6'h23,
                    // AND(24), OR(25), XOR(26), NOR(27)
                    6'h24, 6'h25, 6'h26, 6'h27,
                    // SLT(2A), SLTU(2B)
                    6'h2A, 6'h2B: begin
                        reg_write = 1'b1;
                        reg_dst   = 1'b1;
                        alu_op    = 2'b10;
                        alu_src   = 1'b0;
                    end
                    default: begin
                        invalid_instr = 1'b1;
                    end
                endcase
            end

            // ==================== Branch Instructions ====================
            OP_BGEZ_BLTZ: begin
                branch        = 1'b1;
                is_bgez_bltz  = 1'b1;
                alu_op        = 2'b01;
                // BGEZAL: rt=10001, BLTZAL: rt=10000
                if (rt[4:1] == 4'b1000) begin
                    is_branch_link = 1'b1;
                    reg_write = 1'b1;
                    jal       = 1'b1;
                end
            end
            OP_BEQ: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end
            OP_BNE: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end
            OP_BLEZ: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end
            OP_BGTZ: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end

            // ==================== Jump Instructions ====================
            OP_J: begin
                jump  = 1'b1;
            end
            OP_JAL: begin
                jump      = 1'b1;
                jal       = 1'b1;
                reg_write = 1'b1;
                mem_to_reg_0 = 1'b0;
                mem_to_reg_1 = 1'b1;
            end

            // ==================== I-Type ALU ====================
            OP_ADDI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_ADDIU: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_SLTI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_SLTIU: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_ANDI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_ORI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_XORI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end
            OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b11;
            end

            // ==================== Load Instructions ====================
            OP_LB: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_to_reg_0 = 1'b1;
                mem_to_reg_1 = 1'b0;
                mem_read  = 1'b1;
                is_load   = 1'b1;
                load_type = 3'b000;  // byte signed
                alu_op    = 2'b00;
            end
            OP_LBU: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_to_reg_0 = 1'b1;
                mem_to_reg_1 = 1'b0;
                mem_read  = 1'b1;
                is_load   = 1'b1;
                load_type = 3'b001;  // byte unsigned
                alu_op    = 2'b00;
            end
            OP_LH: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_to_reg_0 = 1'b1;
                mem_to_reg_1 = 1'b0;
                mem_read  = 1'b1;
                is_load   = 1'b1;
                load_type = 3'b010;  // half signed
                alu_op    = 2'b00;
            end
            OP_LHU: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_to_reg_0 = 1'b1;
                mem_to_reg_1 = 1'b0;
                mem_read  = 1'b1;
                is_load   = 1'b1;
                load_type = 3'b011;  // half unsigned
                alu_op    = 2'b00;
            end
            OP_LW: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_to_reg_0 = 1'b1;
                mem_to_reg_1 = 1'b0;
                mem_read  = 1'b1;
                is_load   = 1'b1;
                load_type = 3'b100;  // word
                alu_op    = 2'b00;
            end

            // ==================== Store Instructions ====================
            OP_SB: begin
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                is_store   = 1'b1;
                store_type = 3'b000;  // byte
                alu_op     = 2'b00;
            end
            OP_SH: begin
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                is_store   = 1'b1;
                store_type = 3'b010;  // half
                alu_op     = 2'b00;
            end
            OP_SW: begin
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                is_store   = 1'b1;
                store_type = 3'b100;  // word
                alu_op     = 2'b00;
            end

            // ==================== CP0 Instructions ====================
            OP_CP0: begin
                case (funct)
                    6'h18: begin  // ERET
                        eret = 1'b1;
                    end
                    default: begin
                        // MFC0/MTC0 determined by rs field
                        // rs=0: MFC0, rs=4: MTC0
                        // Handled in ID stage by separate logic
                        cp0_read  = 1'b0;
                        cp0_write = 1'b0;
                    end
                endcase
            end

            default: begin
                invalid_instr = 1'b1;
            end
        endcase
    end

endmodule
