// ============================================================================
// DEBUG Testbench - Trace register writes and pipeline data path
// ============================================================================

`timescale 1ns / 1ps

module cpu_yellow_top_tb;

    reg clk;
    reg rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    wire [31:0] instr;
    wire [31:0] instr_addr;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        dmem_we;
    wire        dmem_re;

    reg [31:0] imem [0:16383];
    reg [31:0] instr_delayed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) instr_delayed <= 32'd0;
        else instr_delayed <= imem[instr_addr[15:2]];
    end
    assign instr = instr_delayed;

    reg [31:0] dmem [0:16383];
    reg [31:0] dmem_rdata_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dmem_rdata_reg <= 32'd0;
        else if (dmem_re) dmem_rdata_reg <= dmem[dmem_addr[15:2]];
    end
    assign dmem_rdata = dmem_rdata_reg;

    always @(posedge clk) begin
        if (dmem_we) dmem[dmem_addr[15:2]] <= dmem_wdata;
    end

    cpu_yellow_top u_dut (
        .clk(clk), .rst_n(rst_n), .instr(instr), .instr_addr(instr_addr),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re)
    );

    function [31:0] make_itype;
        input [5:0] opcode;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin make_itype = {opcode, rs, rt, imm}; end
    endfunction

    function [31:0] make_rtype;
        input [5:0] opcode;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [4:0] shamt;
        input [5:0] funct;
        begin make_rtype = {opcode, rs, rt, rd, shamt, funct}; end
    endfunction

    function [31:0] NOP;
        input dummy;
        begin NOP = 32'h0000_0000; end
    endfunction

    integer i, cyc;
    initial begin
        $dumpfile("cpu_yellow_top_tb.vcd");
        $dumpvars(0, cpu_yellow_top_tb);

        // Init all memories to NOP
        for (i = 0; i < 16384; i = i + 1) imem[i] = 32'd0;

        // Simple test: ADDIU $1, $0, 42
        imem[0] = make_itype(6'h09, 5'd0, 5'd1, 16'd42);  // ADDIU $1, $0, 42
        imem[1] = NOP(1'b0);
        imem[2] = NOP(1'b0);
        imem[3] = NOP(1'b0);
        imem[4] = NOP(1'b0);
        imem[5] = NOP(1'b0);

        // Reset
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        cyc = 0;
        repeat(15) begin
            @(posedge clk);
            cyc = cyc + 1;
            $display("[CYCLE %0d] PC=%h instr=%h IF/ID_instr=%h",
                     cyc, u_dut.u_if.pc, instr, u_dut.if_id_instr);
            $display("  ID: opcode=%h funct=%h rs=%0d rt=%0d rd=%0d",
                     u_dut.u_id.opcode_o, u_dut.u_id.funct_o,
                     u_dut.u_id.rs_addr, u_dut.u_id.rt_addr, u_dut.u_id.rd_addr);
            $display("  ID: reg_data1=%h reg_data2=%h reg_write_o=%b",
                     u_dut.u_id.reg_data1_o, u_dut.u_id.reg_data2_o,
                     u_dut.u_id.reg_write_o);
            $display("  RF: read1=%0d read2=%0d data1=%h data2=%h wen=%b waddr=%0d wdata=%h",
                     u_dut.u_regfile.read_addr1, u_dut.u_regfile.read_addr2,
                     u_dut.u_regfile.read_data1, u_dut.u_regfile.read_data2,
                     u_dut.u_regfile.write_en, u_dut.u_regfile.write_addr,
                     u_dut.u_regfile.write_data);
            $display("  WB: reg_write_en=%b reg_write_addr=%0d reg_write_data=%h",
                     u_dut.u_wb.reg_write_en, u_dut.u_wb.reg_write_addr,
                     u_dut.u_wb.reg_write_data);
            $display("  EX: forward_a=%0d forward_b=%0d alu_a=%h alu_b=%h alu_result=%h",
                     u_dut.u_forward.forward_a, u_dut.u_forward.forward_b,
                     u_dut.u_ex.alu_a, u_dut.u_ex.alu_b_final, u_dut.u_ex.alu_result);
            $display("  REGFILE[1]=%h REGFILE[2]=%h REGFILE[3]=%h",
                     u_dut.u_regfile.regs[1], u_dut.u_regfile.regs[2],
                     u_dut.u_regfile.regs[3]);
        end

        $display("\n=== FINAL REGISTER VALUES ===");
        for (i = 1; i < 10; i = i + 1)
            $display("  $%0d = %h", i, u_dut.u_regfile.regs[i]);

        $finish;
    end

endmodule
