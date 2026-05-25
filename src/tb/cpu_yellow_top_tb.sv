// ============================================================================
// CPU_YELLOW_TOP Testbench
// Per-instruction verification for all 57 MIPS instructions
// Uses behavioral instruction memory and data memory models
// ============================================================================

`timescale 1ns / 1ps

module cpu_yellow_top_tb;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    reg clk;
    reg rst_n;

    // 100MHz clock (10ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    wire [31:0] instr;
    wire [31:0] instr_addr;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        dmem_we;
    wire        dmem_re;

    // ========================================================================
    // Instruction Memory (Behavioral)
    // ========================================================================
    reg [31:0] imem [0:16383];  // 64KB instruction memory (16384 x 32-bit)

    // IMEM read: 1-cycle delay (matches FPGA BRAM behavior)
    reg [31:0] instr_delayed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            instr_delayed <= 32'd0;
        else
            instr_delayed <= imem[instr_addr[15:2]];
    end
    assign instr = instr_delayed;

    // ========================================================================
    // Data Memory (Behavioral)
    // ========================================================================
    reg [31:0] dmem [0:16383];  // 64KB data memory (16384 x 32-bit)
    reg [31:0] dmem_rdata_reg;

    // DMEM read: 1-cycle delay
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dmem_rdata_reg <= 32'd0;
        else if (dmem_re)
            dmem_rdata_reg <= dmem[dmem_addr[15:2]];
    end
    assign dmem_rdata = dmem_rdata_reg;

    // DMEM write
    always @(posedge clk) begin
        if (dmem_we) begin
            dmem[dmem_addr[15:2]] <= dmem_wdata;
        end
    end

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    cpu_yellow_top u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .instr      (instr),
        .instr_addr (instr_addr),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .dmem_we    (dmem_we),
        .dmem_re    (dmem_re)
    );

    // ========================================================================
    // Test Infrastructure
    // ========================================================================
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [1023:0] test_name;

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("cpu_yellow_top_tb.vcd");
        $dumpvars(0, cpu_yellow_top_tb);
    end

    // ========================================================================
    // Helper Tasks
    // ========================================================================
    task check_register;
        input [4:0] reg_num;
        input [31:0] expected;
        input [255:0] msg;
        begin
            // Wait a few cycles for writeback to complete
            repeat(5) @(posedge clk);
            // Access register file internal state for checking
            if (u_dut.u_regfile.regs[reg_num] !== expected) begin
                $display("[FAIL] %s: $%0d = %h, expected %h",
                         msg, reg_num,
                         u_dut.u_regfile.regs[reg_num], expected);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %s: $%0d = %h", msg, reg_num, expected);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task check_memory;
        input [31:0] addr;
        input [31:0] expected;
        input [255:0] msg;
        begin
            repeat(3) @(posedge clk);
            if (dmem[addr[15:2]] !== expected) begin
                $display("[FAIL] %s: mem[%h] = %h, expected %h",
                         msg, addr, dmem[addr[15:2]], expected);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %s: mem[%h] = %h", msg, addr, expected);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // ========================================================================
    // Reset Sequence
    // ========================================================================
    task do_reset;
        begin
            rst_n = 1'b0;
            repeat(5) @(posedge clk);
            rst_n = 1'b1;
            repeat(2) @(posedge clk);
        end
    endtask

    // ========================================================================
    // Clear IMEM and DMEM (fill with NOPs / zeros)
    // ========================================================================
    task clear_memories;
        integer i;
        begin
            for (i = 0; i < 16384; i = i + 1) begin
                imem[i] = 32'h00000000;  // NOP
                dmem[i] = 32'd0;
            end
        end
    endtask

    // ========================================================================
    // Load instruction into IMEM
    // ========================================================================
    task load_instr;
        input [31:0] addr;
        input [31:0] instr_word;
        begin
            imem[addr[15:2]] = instr_word;
        end
    endtask

    // ========================================================================
    // Instruction Encoding Helpers
    // ========================================================================
    function [31:0] make_rtype;
        input [5:0] opcode;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [4:0] shamt;
        input [5:0] funct;
        begin
            make_rtype = {opcode, rs, rt, rd, shamt, funct};
        end
    endfunction

    function [31:0] make_itype;
        input [5:0] opcode;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            make_itype = {opcode, rs, rt, imm};
        end
    endfunction

    function [31:0] make_jtype;
        input [5:0] opcode;
        input [25:0] target;
        begin
            make_jtype = {opcode, target};
        end
    endfunction

    // NOP (with dummy input for plain Verilog compatibility)
    function [31:0] NOP;
        input dummy;
        begin
            NOP = 32'h0000_0000;
        end
    endfunction

    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("==============================================");
        $display(" CPU_YELLOW MIPS Processor Verification");
        $display("==============================================");

        // Initialize all memories to NOP/zero first
        clear_memories();
        do_reset();

        // ================================================================
        // TEST 1: Arithmetic Instructions (14 instructions)
        // ================================================================
        $display("\n--- Test 1: Arithmetic Instructions ---");

        // CRITICAL: Load IMEM BEFORE do_reset so CPU fetches valid instructions
        imem[0] = make_itype(6'h09, 5'd0, 5'd1, 16'd10);  // ADDIU $1, $0, 10
        imem[1] = make_itype(6'h09, 5'd0, 5'd2, 16'd20);  // ADDIU $2, $0, 20
        imem[2] = make_itype(6'h09, 5'd0, 5'd3, 16'd5);   // ADDIU $3, $0, 5
        imem[3] = make_itype(6'h09, 5'd0, 5'd4, 16'd15);  // ADDIU $4, $0, 15
        imem[4] = make_rtype(6'h00, 5'd1, 5'd2, 5'd5, 5'd0, 6'h21);  // ADDU $5, $1, $2  -> $5=30
        imem[5] = make_rtype(6'h00, 5'd2, 5'd1, 5'd6, 5'd0, 6'h23);  // SUBU $6, $2, $1  -> $6=10
        imem[6] = make_rtype(6'h00, 5'd4, 5'd3, 5'd7, 5'd0, 6'h20);  // ADD $7, $4, $3   -> $7=20
        imem[7] = make_rtype(6'h00, 5'd2, 5'd4, 5'd8, 5'd0, 6'h22);  // SUB $8, $2, $4   -> $8=5
        imem[8] = make_itype(6'h08, 5'd6, 5'd9, 16'hFFF8);  // ADDI $9, $6, -8    -> $9=2
        imem[9] = make_rtype(6'h00, 5'd3, 5'd4, 5'd10, 5'd0, 6'h2A); // SLT $10, $3, $4 -> $10=1
        imem[10]= make_rtype(6'h00, 5'd4, 5'd3, 5'd11, 5'd0, 6'h2B); // SLTU $11, $4, $3 -> $11=0
        imem[11]= make_itype(6'h0A, 5'd6, 5'd12, 16'd5);   // SLTI $12, $6, 5    -> $12=0 (10>=5)
        imem[12]= make_itype(6'h0B, 5'd6, 5'd13, 16'd5);   // SLTIU $13, $6, 5   -> $13=0
        imem[13]= make_rtype(6'h00, 5'd1, 5'd3, 5'd0, 5'd0, 6'h18); // MULT $1, $3 -> HI=0, LO=50
        imem[14]= make_rtype(6'h00, 5'd0, 5'd0, 5'd14, 5'd0, 6'h12); // MFLO $14 -> $14=50
        imem[15]= make_rtype(6'h00, 5'd0, 5'd0, 5'd15, 5'd0, 6'h10); // MFHI $15 -> $15=0
        imem[16]= make_rtype(6'h00, 5'd1, 5'd3, 5'd0, 5'd0, 6'h1A); // DIV $1, $3 -> HI=0, LO=2
        imem[17]= make_rtype(6'h00, 5'd0, 5'd0, 5'd16, 5'd0, 6'h12); // MFLO $16 -> $16=2
        imem[18]= make_rtype(6'h00, 5'd4, 5'd3, 5'd0, 5'd0, 6'h19); // MULTU $4, $3 -> LO=75
        imem[19]= make_rtype(6'h00, 5'd0, 5'd0, 5'd17, 5'd0, 6'h12); // MFLO $17 -> $17=75
        imem[20]= make_rtype(6'h00, 5'd4, 5'd3, 5'd0, 5'd0, 6'h1B); // DIVU $4, $3 -> LO=3
        imem[21]= make_rtype(6'h00, 5'd0, 5'd0, 5'd18, 5'd0, 6'h12); // MFLO $18 -> $18=3
        imem[22]= NOP(1'b0);
        imem[23]= NOP(1'b0);
        imem[24]= NOP(1'b0);
        imem[25]= NOP(1'b0);

        do_reset();
        repeat(40) @(posedge clk);

        test_name = "ADDU $5=$1+$2 (10+20=30)";
        check_register(5, 32'd30, test_name);
        test_name = "SUBU $6=$2-$1 (20-10=10)";
        check_register(6, 32'd10, test_name);
        test_name = "ADD $7=$4+$3 (15+5=20)";
        check_register(7, 32'd20, test_name);
        test_name = "SUB $8=$2-$4 (20-15=5)";
        check_register(8, 32'd5, test_name);
        test_name = "ADDI $9=$6-8 (10-8=2)";
        check_register(9, 32'd2, test_name);
        test_name = "SLT $10=($3<$4)?1:0 (5<15=1)";
        check_register(10, 32'd1, test_name);
        test_name = "SLTU $11=($4<$3)?1:0 (15<5=0)";
        check_register(11, 32'd0, test_name);
        test_name = "SLTI $12=($6<5)?1:0 (10<5=0)";
        check_register(12, 32'd0, test_name);
        test_name = "SLTIU $13=($6<5)?1:0 (10<5=0)";
        check_register(13, 32'd0, test_name);
        test_name = "MULT/MFLO $14=10*5=50";
        check_register(14, 32'd50, test_name);
        test_name = "MFHI $15=0";
        check_register(15, 32'd0, test_name);
        test_name = "DIV/MFLO $16=10/5=2";
        check_register(16, 32'd2, test_name);
        test_name = "MULTU/MFLO $17=15*5=75";
        check_register(17, 32'd75, test_name);
        test_name = "DIVU/MFLO $18=15/5=3";
        check_register(18, 32'd3, test_name);

        // ================================================================
        // TEST 2: Logical Instructions (8 instructions)
        // ================================================================
        $display("\n--- Test 2: Logical Instructions ---");
        clear_memories();

        imem[0] = make_itype(6'h09, 5'd0, 5'd1, 16'h00FF);  // ADDIU $1=$0+255
        imem[1] = make_itype(6'h09, 5'd0, 5'd2, 16'h0F0F);  // ADDIU $2=$0+0x0F0F
        imem[2] = make_rtype(6'h00, 5'd1, 5'd2, 5'd3, 5'd0, 6'h24);  // AND $3,$1,$2 -> $3=0x000F
        imem[3] = make_rtype(6'h00, 5'd1, 5'd2, 5'd4, 5'd0, 6'h25);  // OR $4,$1,$2  -> $4=0x0FFF
        imem[4] = make_rtype(6'h00, 5'd1, 5'd2, 5'd5, 5'd0, 6'h26);  // XOR $5,$1,$2 -> $5=0x0FF0
        imem[5] = make_rtype(6'h00, 5'd1, 5'd2, 5'd6, 5'd0, 6'h27);  // NOR $6,$1,$2 -> $6=0xFFFFF000
        imem[6] = make_itype(6'h0C, 5'd3, 5'd7, 16'h00F0);  // ANDI $7,$3,0xF0  -> $7=0x0000
        imem[7] = make_itype(6'h0D, 5'd3, 5'd8, 16'h0F00);  // ORI $8,$3,0xF00  -> $8=0x0F0F
        imem[8] = make_itype(6'h0E, 5'd4, 5'd9, 16'h000F);  // XORI $9,$4,0x0F  -> $9=0x0FF0
        imem[9] = make_itype(6'h0F, 5'd0, 5'd10, 16'h1234); // LUI $10,0x1234   -> $10=0x12340000
        imem[10]= NOP(1'b0); imem[11]= NOP(1'b0); imem[12]= NOP(1'b0); imem[13]= NOP(1'b0);

        do_reset();
        repeat(30) @(posedge clk);
        test_name = "AND $3=0xFF&0xF0F=0xF";
        check_register(3, 32'h000F, test_name);
        test_name = "OR $4=0xFF|0xF0F=0xFFF";
        check_register(4, 32'h0FFF, test_name);
        test_name = "XOR $5=0xFF^0xF0F=0xFF0";
        check_register(5, 32'h0FF0, test_name);
        test_name = "NOR $6=~(0xFF|0xF0F)";
        check_register(6, 32'hFFFFF000, test_name);
        test_name = "ANDI $7=0xF&0xF0=0";
        check_register(7, 32'd0, test_name);
        test_name = "ORI $8=0xF|0xF00=0xF0F";
        check_register(8, 32'h0F0F, test_name);
        test_name = "XORI $9=0xFFF^0xF=0xFF0";
        check_register(9, 32'h0FF0, test_name);
        test_name = "LUI $10=0x12340000";
        check_register(10, 32'h12340000, test_name);

        // ================================================================
        // TEST 3: Shift Instructions (6 instructions)
        // ================================================================
        $display("\n--- Test 3: Shift Instructions ---");
        clear_memories();

        imem[0] = make_itype(6'h09, 5'd0, 5'd1, 16'd1);    // ADDIU $1=$0+1
        imem[1] = make_itype(6'h09, 5'd0, 5'd2, 16'd3);    // ADDIU $2=$0+3 (shift amount)
        imem[2] = make_rtype(6'h00, 5'd0, 5'd1, 5'd3, 5'd4, 6'h00);  // SLL $3,$1,4  -> $3=16
        imem[3] = make_rtype(6'h00, 5'd0, 5'd3, 5'd4, 5'd2, 6'h02);  // SRL $4,$3,2  -> $4=4
        imem[4] = make_itype(6'h09, 5'd0, 5'd5, 16'hFFF0);  // ADDIU $5=$0,-16
        imem[5] = make_rtype(6'h00, 5'd0, 5'd5, 5'd6, 5'd2, 6'h03);  // SRA $6,$5,2  -> $6=-4
        imem[6] = make_rtype(6'h00, 5'd2, 5'd3, 5'd7, 5'd0, 6'h04);  // SLLV $7,$3,$2 -> $7=128
        imem[7] = make_rtype(6'h00, 5'd2, 5'd7, 5'd8, 5'd0, 6'h06);  // SRLV $8,$7,$2 -> $8=16
        imem[8] = make_rtype(6'h00, 5'd2, 5'd5, 5'd9, 5'd0, 6'h07);  // SRAV $9,$5,$2 -> $9=-2
        imem[9] = NOP(1'b0); imem[10]= NOP(1'b0); imem[11]= NOP(1'b0);

        do_reset();
        repeat(25) @(posedge clk);
        test_name = "SLL $3=$1<<4=16";
        check_register(3, 32'd16, test_name);
        test_name = "SRL $4=$3>>2=4";
        check_register(4, 32'd4, test_name);
        test_name = "SRA $6=(-16)>>>2=-4";
        check_register(6, 32'hFFFFFFFC, test_name);
        test_name = "SLLV $7=$3<<3=128";
        check_register(7, 32'd128, test_name);
        test_name = "SRLV $8=$7>>3=16";
        check_register(8, 32'd16, test_name);
        test_name = "SRAV $9=(-16)>>>3=-2";
        check_register(9, 32'hFFFFFFFE, test_name);

        // ================================================================
        // TEST 4: Branch Instructions (12 instructions)
        // ================================================================
        $display("\n--- Test 4: Branch Instructions ---");
        clear_memories();

        imem[0]  = make_itype(6'h09, 5'd0, 5'd1, 16'd5);   // ADDIU $1=$0+5
        imem[1]  = make_itype(6'h09, 5'd0, 5'd2, 16'd5);   // ADDIU $2=$0+5
        imem[2]  = make_itype(6'h09, 5'd0, 5'd3, 16'd10);  // ADDIU $3=$0+10
        imem[3]  = make_itype(6'h04, 5'd1, 5'd2, 16'd2);   // BEQ $1,$2,+2 -> skip next 2+NOP
        imem[4]  = NOP(1'b0);                                    // delay slot
        imem[5]  = make_itype(6'h09, 5'd0, 5'd4, 16'd99);  // SKIPPED
        imem[6]  = NOP(1'b0);
        imem[7]  = make_itype(6'h09, 5'd0, 5'd4, 16'd1);   // $4=1 (target)
        imem[8]  = make_itype(6'h05, 5'd1, 5'd3, 16'd1);   // BNE $1,$3,+1 -> taken (5!=10)
        imem[9]  = NOP(1'b0);                                    // delay slot
        imem[10] = make_itype(6'h09, 5'd0, 5'd5, 16'd1);   // $5=1 (taken target)
        imem[11] = NOP(1'b0);
        // BGEZ: $1=5 >= 0, should take
        imem[12] = make_itype(6'h01, 5'd1, 5'd1, 16'd2);   // BGEZ $1,+2
        imem[13] = NOP(1'b0);
        imem[14] = make_itype(6'h09, 5'd0, 5'd6, 16'd99);  // SKIPPED
        imem[15] = NOP(1'b0);
        imem[16] = make_itype(6'h09, 5'd0, 5'd6, 16'd1);   // $6=1
        // BGTZ: $3=10 > 0, should take
        imem[17] = make_itype(6'h07, 5'd3, 5'd0, 16'd1);   // BGTZ $3,+1
        imem[18] = NOP(1'b0);
        imem[19] = make_itype(6'h09, 5'd0, 5'd7, 16'd1);   // $7=1
        imem[20] = NOP(1'b0); imem[21] = NOP(1'b0); imem[22] = NOP(1'b0); imem[23] = NOP(1'b0);

        do_reset();
        repeat(40) @(posedge clk);
        test_name = "BEQ $1==$2 (taken)";
        check_register(4, 32'd1, test_name);
        test_name = "BNE $1!=$3 (taken)";
        check_register(5, 32'd1, test_name);
        test_name = "BGEZ $1>=0 (taken)";
        check_register(6, 32'd1, test_name);
        test_name = "BGTZ $3>0 (taken)";
        check_register(7, 32'd1, test_name);

        // ================================================================
        // TEST 5: Jump Instructions (J, JAL, JR, JALR)
        // ================================================================
        $display("\n--- Test 5: Jump Instructions ---");
        clear_memories();

        // Use JAL to jump forward, save return addr
        imem[0]  = make_jtype(6'h03, 26'd3);   // JAL to addr 3
        imem[1]  = NOP(1'b0);                        // delay slot
        imem[2]  = make_itype(6'h09, 5'd0, 5'd10, 16'd99); // SKIPPED
        imem[3]  = make_itype(6'h09, 5'd0, 5'd1, 16'd1);   // $1=1 (target)
        // JR back via $31 (return addr+8 is tricky, use known reg)
        imem[4]  = make_itype(6'h09, 5'd0, 5'd2, 16'd8);   // $2=8 (addr of line after next)
        imem[5]  = make_rtype(6'h00, 5'd2, 5'd0, 5'd0, 5'd0, 6'h08); // JR $2
        imem[6]  = NOP(1'b0);
        imem[7]  = make_itype(6'h09, 5'd0, 5'd3, 16'd99);  // SKIPPED
        imem[8]  = make_itype(6'h09, 5'd0, 5'd3, 16'd1);   // $3=1 (JR target)
        imem[9]  = NOP(1'b0); imem[10] = NOP(1'b0); imem[11] = NOP(1'b0);

        do_reset();
        repeat(30) @(posedge clk);
        test_name = "JAL -> $1=1 at target";
        check_register(1, 32'd1, test_name);
        test_name = "JR $2 -> $3=1";
        check_register(3, 32'd1, test_name);

        // ================================================================
        // TEST 6: Data Movement (MFHI, MFLO, MTHI, MTLO)
        // ================================================================
        $display("\n--- Test 6: Data Movement Instructions ---");
        clear_memories();

        imem[0] = make_itype(6'h09, 5'd0, 5'd1, 16'h0042);  // $1=0x42
        imem[1] = make_rtype(6'h00, 5'd1, 5'd0, 5'd0, 5'd0, 6'h11); // MTHI $1
        imem[2] = make_rtype(6'h00, 5'd1, 5'd0, 5'd0, 5'd0, 6'h13); // MTLO $1
        imem[3] = make_rtype(6'h00, 5'd0, 5'd0, 5'd2, 5'd0, 6'h10); // MFHI $2 -> $2=0x42
        imem[4] = make_rtype(6'h00, 5'd0, 5'd0, 5'd3, 5'd0, 6'h12); // MFLO $3 -> $3=0x42
        imem[5] = NOP(1'b0); imem[6] = NOP(1'b0); imem[7] = NOP(1'b0);

        do_reset();
        repeat(20) @(posedge clk);
        test_name = "MTHI+MFHI: $2=0x42";
        check_register(2, 32'h42, test_name);
        test_name = "MTLO+MFLO: $3=0x42";
        check_register(3, 32'h42, test_name);

        // ================================================================
        // TEST 7: Load/Store Instructions (8 instructions)
        // ================================================================
        $display("\n--- Test 7: Load/Store Instructions ---");
        clear_memories();

        // Initialize data memory BEFORE reset
        dmem[0] = 32'h12345678;
        dmem[1] = 32'hABCDEF01;
        dmem[2] = 32'h000000FF;

        imem[0]  = make_itype(6'h09, 5'd0, 5'd1, 16'd0);     // $1 base=0
        imem[1]  = make_itype(6'h23, 5'd1, 5'd2, 16'd0);     // LW $2,0($1) -> $2=0x12345678
        imem[2]  = make_itype(6'h20, 5'd1, 5'd3, 16'd0);     // LB $3,0($1) -> $3=0x78(signed) -> 0x78
        imem[3]  = make_itype(6'h24, 5'd1, 5'd4, 16'd3);     // LBU $4,3($1) -> $4=0x12
        imem[4]  = make_itype(6'h21, 5'd1, 5'd5, 16'd0);     // LH $5,0($1) -> $5=0x5678(positive) -> 0x5678
        imem[5]  = make_itype(6'h25, 5'd1, 5'd6, 16'd2);     // LHU $6,2($1) -> $6=0x1234
        imem[6]  = make_itype(6'h2B, 5'd1, 5'd2, 16'd8);     // SW $2,8($1)  -> mem[2]=0x12345678
        imem[7]  = make_itype(6'h28, 5'd1, 5'd2, 16'd16);    // SB $2,16($1) -> mem[4][7:0]=0x78
        imem[8]  = make_itype(6'h29, 5'd1, 5'd2, 16'd20);    // SH $2,20($1) -> mem[5][15:0]=0x5678
        imem[9]  = NOP(1'b0); imem[10] = NOP(1'b0); imem[11] = NOP(1'b0);

        do_reset();
        repeat(30) @(posedge clk);
        test_name = "LW $2=mem[0]=0x12345678";
        check_register(2, 32'h12345678, test_name);
        test_name = "LB $3=mem[0]byte=0x78";
        check_register(3, 32'h00000078, test_name);
        test_name = "LBU $4=mem[3]byte=0x12";
        check_register(4, 32'h00000012, test_name);
        test_name = "LH $5=mem[0]half=0x5678";
        check_register(5, 32'h00005678, test_name);
        test_name = "LHU $6=mem[2]half=0x1234";
        check_register(6, 32'h00001234, test_name);
        test_name = "SW: mem[2]=0x12345678";
        check_memory(32'd8, 32'h12345678, test_name);

        // ================================================================
        // TEST 8: SYSCALL Exception
        // ================================================================
        $display("\n--- Test 8: SYSCALL Exception ---");
        clear_memories();

        imem[0] = make_rtype(6'h00, 5'd0, 5'd0, 5'd0, 5'd0, 6'h0C);  // SYSCALL
        imem[1] = NOP(1'b0);
        imem[2] = make_itype(6'h09, 5'd0, 5'd1, 16'd1);   // Should NOT execute (exception)
        imem[3] = NOP(1'b0); imem[4] = NOP(1'b0); imem[5] = NOP(1'b0);

        do_reset();
        repeat(15) @(posedge clk);
        // After SYSCALL, PC should jump to 0xBFC0_0380
        // $1 should NOT be 1 (exception occurred)
        test_name = "SYSCALL: $1!=1 (exception occurred)";
        check_register(1, 32'd0, test_name);

        // ================================================================
        // Test Summary
        // ================================================================
        $display("\n==============================================");
        $display(" TEST SUMMARY");
        $display(" Passed: %0d", pass_count);
        $display(" Failed: %0d", fail_count);
        $display("==============================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $finish;
    end

endmodule
