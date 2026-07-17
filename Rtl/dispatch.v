`timescale 1ns / 1ps

module dispatch #(
    parameter ARCH_ADDR_W = 5,
    parameter PHYS_ADDR_W = 6,
    parameter OP_WIDTH    = 4,
    parameter ROB_ADDR_W  = 3
) (
    input  wire                    clk_i,
    input  wire                    reset_i,

    // From decode — Slot A
    input  wire                    decode_A_valid_i,
    input  wire [OP_WIDTH-1:0]     decode_A_op_i,
    input  wire [ARCH_ADDR_W-1:0]  decode_A_rs1_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  decode_A_rs2_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  decode_A_rd_arch_i,
    input  wire                    decode_A_writes_rd_i,
    input  wire [1:0]              decode_A_fu_type_i,

    // From decode — Slot B
    input  wire                    decode_B_valid_i,
    input  wire [OP_WIDTH-1:0]     decode_B_op_i,
    input  wire [ARCH_ADDR_W-1:0]  decode_B_rs1_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  decode_B_rs2_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  decode_B_rd_arch_i,
    input  wire                    decode_B_writes_rd_i,
    input  wire [1:0]              decode_B_fu_type_i,

    // From rename — Slot A
    input  wire [PHYS_ADDR_W-1:0]  rename_A_rs1_phys_i,
    input  wire [PHYS_ADDR_W-1:0]  rename_A_rs2_phys_i,
    input  wire [PHYS_ADDR_W-1:0]  rename_A_rd_phys_i,
    input  wire [PHYS_ADDR_W-1:0]  rename_A_rd_old_phys_i,
    input  wire                    rename_stall_A_i,

    // From rename — Slot B
    input  wire [PHYS_ADDR_W-1:0]  rename_B_rs1_phys_i,
    input  wire [PHYS_ADDR_W-1:0]  rename_B_rs2_phys_i,
    input  wire [PHYS_ADDR_W-1:0]  rename_B_rd_phys_i,
    input  wire [PHYS_ADDR_W-1:0]  rename_B_rd_old_phys_i,
    input  wire                    rename_stall_B_i,

    // ROB interface
    input  wire [ROB_ADDR_W-1:0]   rob_tail_i,
    input  wire                    rob_full_i,

    output wire                    rob_alloc_A_o,
    output wire [ARCH_ADDR_W-1:0]  rob_A_arch_dest_o,
    output wire [PHYS_ADDR_W-1:0]  rob_A_phys_dest_o,
    output wire [PHYS_ADDR_W-1:0]  rob_A_old_phys_dest_o,
    output wire                    rob_A_writes_rd_o,

    output wire                    rob_alloc_B_o,
    output wire [ARCH_ADDR_W-1:0]  rob_B_arch_dest_o,
    output wire [PHYS_ADDR_W-1:0]  rob_B_phys_dest_o,
    output wire [PHYS_ADDR_W-1:0]  rob_B_old_phys_dest_o,
    output wire                    rob_B_writes_rd_o,

    // To RS — Slot A
    output wire                    rs_disp_A_valid_o,
    output wire [OP_WIDTH-1:0]     rs_disp_A_op_o,
    output wire [PHYS_ADDR_W-1:0]  rs_disp_A_pj_o,
    output wire [PHYS_ADDR_W-1:0]  rs_disp_A_pk_o,
    output wire [PHYS_ADDR_W-1:0]  rs_disp_A_pd_o,
    output wire [ROB_ADDR_W-1:0]   rs_disp_A_rob_idx_o,

    // To RS — Slot B
    output wire                    rs_disp_B_valid_o,
    output wire [OP_WIDTH-1:0]     rs_disp_B_op_o,
    output wire [PHYS_ADDR_W-1:0]  rs_disp_B_pj_o,
    output wire [PHYS_ADDR_W-1:0]  rs_disp_B_pk_o,
    output wire [PHYS_ADDR_W-1:0]  rs_disp_B_pd_o,
    output wire [ROB_ADDR_W-1:0]   rs_disp_B_rob_idx_o,

    // RS full back-pressure (NEW INPUT)
    input  wire                    rs_full_i,

    // Back-pressure to fetch
    output wire                    fe_stall_o
);

    // ---- Dispatch eligibility (now includes rs_full_i) ----
    wire A_dispatches = decode_A_valid_i
                      & ~rename_stall_A_i
                      & ~rob_full_i
                      & ~rs_full_i;        // <-- NEW

    wire B_dispatches = decode_B_valid_i
                      & ~rename_stall_B_i
                      & ~rob_full_i
                      & ~rs_full_i         // <-- NEW
                      & A_dispatches;

    assign fe_stall_o = (decode_A_valid_i & ~A_dispatches) |
                        (decode_B_valid_i & ~B_dispatches);

    // ---- ROB outputs (unchanged) ----
    assign rob_alloc_A_o         = A_dispatches;
    assign rob_A_arch_dest_o     = decode_A_rd_arch_i;
    assign rob_A_phys_dest_o     = rename_A_rd_phys_i;
    assign rob_A_old_phys_dest_o = rename_A_rd_old_phys_i;
    assign rob_A_writes_rd_o     = decode_A_writes_rd_i;

    assign rob_alloc_B_o         = B_dispatches;
    assign rob_B_arch_dest_o     = decode_B_rd_arch_i;
    assign rob_B_phys_dest_o     = rename_B_rd_phys_i;
    assign rob_B_old_phys_dest_o = rename_B_rd_old_phys_i;
    assign rob_B_writes_rd_o     = decode_B_writes_rd_i;

    // ---- RS outputs (unchanged) ----
    assign rs_disp_A_valid_o   = A_dispatches & (decode_A_fu_type_i == 2'd0);
    assign rs_disp_A_op_o      = decode_A_op_i;
    assign rs_disp_A_pj_o      = rename_A_rs1_phys_i;
    assign rs_disp_A_pk_o      = rename_A_rs2_phys_i;
    assign rs_disp_A_pd_o      = rename_A_rd_phys_i;
    assign rs_disp_A_rob_idx_o = rob_tail_i;

    assign rs_disp_B_valid_o   = B_dispatches & (decode_B_fu_type_i == 2'd0);
    assign rs_disp_B_op_o      = decode_B_op_i;
    assign rs_disp_B_pj_o      = rename_B_rs1_phys_i;
    assign rs_disp_B_pk_o      = rename_B_rs2_phys_i;
    assign rs_disp_B_pd_o      = rename_B_rd_phys_i;
    assign rs_disp_B_rob_idx_o = rob_tail_i + (A_dispatches ? {{(ROB_ADDR_W-1){1'b0}}, 1'b1}
                                                             : {ROB_ADDR_W{1'b0}});

endmodule
