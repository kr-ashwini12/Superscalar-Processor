`timescale 1ns / 1ps
module rename_unit #(
    parameter NUM_ARCH_REGS = 32,
    parameter NUM_PHYS_REGS = 48,
    parameter ARCH_ADDR_W   = 5,
    parameter PHYS_ADDR_W   = 6,
    parameter FREE_LIST_SZ  = NUM_PHYS_REGS - NUM_ARCH_REGS
) (
    input  wire                    clk_i,
    input  wire                    reset_i,

    input  wire                    disp_A_valid_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_A_rs1_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_A_rs2_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_A_rd_arch_i,
    input  wire                    disp_A_writes_rd_i,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rs1_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rs2_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rd_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rd_old_phys_o,

    input  wire                    disp_B_valid_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_B_rs1_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_B_rs2_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_B_rd_arch_i,
    input  wire                    disp_B_writes_rd_i,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rs1_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rs2_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rd_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rd_old_phys_o,

    output wire                    stall_A_o,
    output wire                    stall_B_o,

    input  wire                    commit_valid_i,
    input  wire [PHYS_ADDR_W-1:0]  commit_old_phys_i,

    input  wire                    commit_B_valid_i,
    input  wire [PHYS_ADDR_W-1:0]  commit_B_old_phys_i
);

    reg [PHYS_ADDR_W-1:0] rename_map [0:NUM_ARCH_REGS-1];
    reg [PHYS_ADDR_W-1:0] free_list  [0:FREE_LIST_SZ-1];
    reg [4:0] fl_head, fl_tail, fl_count;
    integer idx;

    wire A_needs_alloc = disp_A_valid_i & disp_A_writes_rd_i;
    wire B_needs_alloc = disp_B_valid_i & disp_B_writes_rd_i;

    assign stall_A_o = A_needs_alloc & (fl_count == 5'd0);
    assign stall_B_o = A_needs_alloc & B_needs_alloc & (fl_count < 5'd2);

    wire [PHYS_ADDR_W-1:0] A_new_phys = free_list[fl_head[3:0]];
    wire [PHYS_ADDR_W-1:0] B_new_phys = A_needs_alloc
                                       ? free_list[(fl_head + 4'd1) % FREE_LIST_SZ]
                                       : free_list[fl_head[3:0]];

    wire B_src1_uses_A = A_needs_alloc & (disp_A_rd_arch_i == disp_B_rs1_arch_i);
    wire B_src2_uses_A = A_needs_alloc & (disp_A_rd_arch_i == disp_B_rs2_arch_i);
    wire AB_write_same = A_needs_alloc & B_needs_alloc
                       & (disp_A_rd_arch_i == disp_B_rd_arch_i);

    assign disp_A_rs1_phys_o    = rename_map[disp_A_rs1_arch_i];
    assign disp_A_rs2_phys_o    = rename_map[disp_A_rs2_arch_i];
    assign disp_A_rd_phys_o     = A_needs_alloc ? A_new_phys : rename_map[disp_A_rd_arch_i];
    assign disp_A_rd_old_phys_o = rename_map[disp_A_rd_arch_i];

    assign disp_B_rs1_phys_o    = B_src1_uses_A ? A_new_phys : rename_map[disp_B_rs1_arch_i];
    assign disp_B_rs2_phys_o    = B_src2_uses_A ? A_new_phys : rename_map[disp_B_rs2_arch_i];
    assign disp_B_rd_phys_o     = B_needs_alloc ? B_new_phys : rename_map[disp_B_rd_arch_i];
    assign disp_B_rd_old_phys_o = AB_write_same ? A_new_phys : rename_map[disp_B_rd_arch_i];

    wire do_alloc_A  = A_needs_alloc & ~stall_A_o;
    wire do_alloc_B  = B_needs_alloc & ~stall_B_o & ~stall_A_o;
    wire do_commit_A = commit_valid_i;
    wire do_commit_B = commit_B_valid_i;

    // Count signals as plain wires — no local regs inside always block
    wire [4:0] fl_gain = {4'b0, do_commit_A} + {4'b0, do_commit_B};
    wire [4:0] fl_loss = {4'b0, do_alloc_A}  + {4'b0, do_alloc_B};

    always @(posedge clk_i) begin
        if (reset_i) begin
            for (idx = 0; idx < NUM_ARCH_REGS; idx = idx + 1)
                rename_map[idx] <= idx[PHYS_ADDR_W-1:0];
            for (idx = 0; idx < FREE_LIST_SZ; idx = idx + 1)
                free_list[idx] <= NUM_ARCH_REGS[PHYS_ADDR_W-1:0] + idx[PHYS_ADDR_W-1:0];
            fl_head  <= 5'd0;
            fl_tail  <= 5'd0;
            fl_count <= 5'd16;
        end else begin

            // Update rename map
            if (do_alloc_A) rename_map[disp_A_rd_arch_i] <= A_new_phys;
            if (do_alloc_B) rename_map[disp_B_rd_arch_i] <= B_new_phys;

            // Pop free list head (dispatch)
            if (do_alloc_A & do_alloc_B)
                fl_head <= (fl_head + 5'd2) % FREE_LIST_SZ;
            else if (do_alloc_A | do_alloc_B)
                fl_head <= (fl_head + 5'd1) % FREE_LIST_SZ;

            // Push commit A at fl_tail
            if (do_commit_A)
                free_list[fl_tail[3:0]] <= commit_old_phys_i;

            // Push commit B at fl_tail or fl_tail+1
            if (do_commit_B) begin
                if (do_commit_A)
                    free_list[(fl_tail + 5'd1) % FREE_LIST_SZ] <= commit_B_old_phys_i;
                else
                    free_list[fl_tail[3:0]] <= commit_B_old_phys_i;
            end

            // Advance fl_tail by number of commits
            if (do_commit_A & do_commit_B)
                fl_tail <= (fl_tail + 5'd2) % FREE_LIST_SZ;
            else if (do_commit_A | do_commit_B)
                fl_tail <= (fl_tail + 5'd1) % FREE_LIST_SZ;

            // fl_count: computed as wires above, no local reg needed
            fl_count <= fl_count + fl_gain - fl_loss;
        end
    end

endmodule
