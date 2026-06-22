`timescale 1ns / 1ps

module fetch #(
    parameter PC_WIDTH   = 32,
    parameter IMEM_DEPTH = 256   // 256 x 32-bit words = 1 KB
) (
    input  wire                  clk_i,
    input  wire                  reset_i,
    input  wire                  fe_stall_i,   // back-pressure from dispatch

    // Outputs to decode (registered)
    output reg  [PC_WIDTH-1:0]   pc_A_o,
    output reg  [31:0]           instr_A_o,
    output reg                   valid_A_o,

    output reg  [PC_WIDTH-1:0]   pc_B_o,
    output reg  [31:0]           instr_B_o,
    output reg                   valid_B_o
);

    // ----------------------------------------------------------
    // PC register
    // ----------------------------------------------------------
    reg [PC_WIDTH-1:0] pc;

    // ----------------------------------------------------------
    // Instruction memory — initialized by testbench via $readmemh
    // ----------------------------------------------------------
    reg [31:0] imem [0:IMEM_DEPTH-1];

    // ----------------------------------------------------------
    // Combinational reads
    // ----------------------------------------------------------
    wire [PC_WIDTH-1:0] pc_A_comb  = pc;
    wire [PC_WIDTH-1:0] pc_B_comb  = pc + 4;

    wire [31:0] instr_A_comb = imem[pc[PC_WIDTH-1:2]];
    wire [31:0] instr_B_comb = imem[(pc + 4) >> 2];

    // Valid if the word address is within instruction memory
    wire valid_A_comb = (pc_A_comb[PC_WIDTH-1:2] < IMEM_DEPTH);
    wire valid_B_comb = (pc_B_comb[PC_WIDTH-1:2] < IMEM_DEPTH);

    // ----------------------------------------------------------
    // Sequential update
    // ----------------------------------------------------------
    always @(posedge clk_i) begin
        if (reset_i) begin
            pc        <= 0;
            pc_A_o    <= 0; instr_A_o <= 0; valid_A_o <= 0;
            pc_B_o    <= 0; instr_B_o <= 0; valid_B_o <= 0;
        end else if (!fe_stall_i) begin
            // Advance PC by 8 (2 instructions), latch outputs
            pc        <= pc + 8;
            pc_A_o    <= pc_A_comb;
            instr_A_o <= instr_A_comb;
            valid_A_o <= valid_A_comb;
            pc_B_o    <= pc_B_comb;
            instr_B_o <= instr_B_comb;
            valid_B_o <= valid_B_comb;
        end
        // If stalled: PC and outputs hold (no change)
    end

endmodule
