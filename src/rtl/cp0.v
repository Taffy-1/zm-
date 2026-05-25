`timescale 1ns / 1ps
// ============================================================================
// CP0 - Coprocessor 0 (System Control)
// Manages exceptions, interrupts, and privileged operations
// ============================================================================

module cp0 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cp0_read,
    input  wire        cp0_write,
    input  wire [4:0]  cp0_addr,      // rd field
    input  wire [2:0]  cp0_sel,
    input  wire [31:0] cp0_data_in,   // from GPR[rt]
    output reg  [31:0] cp0_data_out,
    input  wire [4:0]  exception_type,
    input  wire [31:0] exception_pc,
    input  wire        is_in_delay_slot,
    output reg         exception_occurred,
    output wire [31:0] exception_target,
    input  wire        eret,
    output wire [31:0] epc_out
);

    // Exception codes
    localparam EXC_INT  = 5'h00;  // Interrupt
    localparam EXC_ADEL = 5'h04;  // Address Error (Load/IF)
    localparam EXC_ADES = 5'h05;  // Address Error (Store)
    localparam EXC_SYS  = 5'h08;  // Syscall
    localparam EXC_BP   = 5'h09;  // Breakpoint
    localparam EXC_RI   = 5'h0A;  // Reserved Instruction
    localparam EXC_OV   = 5'h0C;  // Overflow

    // CP0 Register numbers
    localparam CP0_STATUS = 5'd12;
    localparam CP0_CAUSE  = 5'd13;
    localparam CP0_EPC    = 5'd14;

    // Status register bits
    localparam STATUS_IE  = 0;   // Interrupt Enable
    localparam STATUS_EXL = 1;   // Exception Level

    // CP0 Registers
    reg [31:0] status_reg;
    reg [31:0] cause_reg;
    reg [31:0] epc_reg;

    // Exception entry point
    assign exception_target = 32'hBFC0_0380;
    assign epc_out = epc_reg;

    // CP0 Read
    always @(*) begin
        cp0_data_out = 32'd0;
        if (cp0_read) begin
            case ({cp0_addr, cp0_sel})
                {CP0_STATUS, 3'd0}: cp0_data_out = status_reg;
                {CP0_CAUSE,  3'd0}: cp0_data_out = cause_reg;
                {CP0_EPC,    3'd0}: cp0_data_out = epc_reg;
                default:            cp0_data_out = 32'd0;
            endcase
        end
    end

    // CP0 Write and Exception Handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_reg <= 32'd0;
            cause_reg  <= 32'd0;
            epc_reg    <= 32'd0;
            exception_occurred <= 1'b0;
        end else begin
            exception_occurred <= 1'b0;

            // ERET: return from exception
            if (eret) begin
                status_reg[STATUS_EXL] <= 1'b0;
            end

            // Exception handling
            else if (exception_type != 5'h1F && !status_reg[STATUS_EXL]) begin
                // Save EPC
                if (is_in_delay_slot)
                    epc_reg <= exception_pc - 32'd4;  // Branch instruction PC
                else
                    epc_reg <= exception_pc;

                // Set Cause
                cause_reg[6:2] <= exception_type;
                cause_reg[31]  <= is_in_delay_slot;

                // Enter exception level
                status_reg[STATUS_EXL] <= 1'b1;
                exception_occurred <= 1'b1;
            end

            // CP0 Write (only when not in exception)
            else if (cp0_write) begin
                case ({cp0_addr, cp0_sel})
                    {CP0_STATUS, 3'd0}: status_reg <= cp0_data_in;
                    {CP0_CAUSE,  3'd0}: cause_reg[9:8] <= cp0_data_in[9:8];  // Only IP writable
                    {CP0_EPC,    3'd0}: epc_reg <= cp0_data_in;
                    default: ;
                endcase
            end
        end
    end

endmodule
