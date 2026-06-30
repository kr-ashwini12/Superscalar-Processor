`timescale 1ns/1ps

module alu #(
    parameter OP_WIDTH    = 4,
    parameter DATA_WIDTH  = 32,
    parameter PHYS_ADDR_W = 6,
    parameter ROB_ADDR_W  = 3
) (
    input  wire                    clk_i,    // unused — ALU is combinational
    input  wire                    reset_i,  // unused

    // Issue inputs (from RS)
    input  wire                    valid_i,
    input  wire [OP_WIDTH-1:0]     op_i,
    input  wire [DATA_WIDTH-1:0]   src1_val_i,
    input  wire [DATA_WIDTH-1:0]   src2_val_i,
    input  wire [DATA_WIDTH-1:0]   imm_i,       // stored in RS, used for ADDI
    input  wire [PHYS_ADDR_W-1:0]  phys_dest_i,
    input  wire [ROB_ADDR_W-1:0]   rob_idx_i,

    // Writeback outputs
    output wire                    result_valid_o,
    output wire [DATA_WIDTH-1:0]   result_o,
    output wire [PHYS_ADDR_W-1:0]  phys_dest_o,
    output wire [ROB_ADDR_W-1:0]   rob_idx_o
);

    reg [DATA_WIDTH-1:0] result_r;

    always @(*) begin
        case (op_i)
            4'd0:    result_r = src1_val_i + src2_val_i;               // ADD
            4'd1:    result_r = src1_val_i - src2_val_i;               // SUB
            4'd2:    result_r = src1_val_i & src2_val_i;               // AND
            4'd3:    result_r = src1_val_i | src2_val_i;               // OR
            4'd4:    result_r = src1_val_i ^ src2_val_i;               // XOR
            4'd5:    result_r = src1_val_i << src2_val_i[4:0];         // SLL
            4'd6:    result_r = src1_val_i >> src2_val_i[4:0];         // SRL
            4'd7:    result_r = ($signed(src1_val_i) < $signed(src2_val_i))
                                    ? 32'd1 : 32'd0;                   // SLT
            4'd8:    result_r = src1_val_i + imm_i;                    // ADDI
            default: result_r = 32'd0;
        endcase
    end

    assign result_valid_o = valid_i;
    assign result_o       = result_r;
    assign phys_dest_o    = phys_dest_i;
    assign rob_idx_o      = rob_idx_i;

endmodule
