`timescale 1ns / 1ps
// ============================================================================
// Register File - 32 x 32-bit general purpose registers
// r0 is hardwired to 0
// ============================================================================

module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  read_addr1,   // rs
    input  wire [4:0]  read_addr2,   // rt
    output wire [31:0] read_data1,
    output wire [31:0] read_data2,
    input  wire        write_en,
    input  wire [4:0]  write_addr,
    input  wire [31:0] write_data
);

    reg [31:0] regs [0:31];
    integer i;

    // Asynchronous read with write-through bypass
    // If read_addr matches the register being written in the same cycle,
    // forward write_data directly (otherwise read sees old value)
    assign read_data1 = (read_addr1 == 5'd0) ? 32'd0 :
                        (write_en && read_addr1 == write_addr) ? write_data :
                        regs[read_addr1];
    assign read_data2 = (read_addr2 == 5'd0) ? 32'd0 :
                        (write_en && read_addr2 == write_addr) ? write_data :
                        regs[read_addr2];

    // Synchronous write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (write_en && write_addr != 5'd0) begin
            regs[write_addr] <= write_data;
        end
    end

endmodule
