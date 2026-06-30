`timescale 1ns/1ps

module rename_unit #(
    parameter NUM_ARCH_REGS = 32,
    parameter NUM_PHYS_REGS = 48,
    parameter ARCH_ADDR_W   = 5,
    parameter PHYS_ADDR_W   = 6,
    parameter FREE_LIST_SZ  = NUM_PHYS_REGS - NUM_ARCH_REGS  // 16
) (
    input  wire                    clk_i,
    input  wire                    reset_i,

    // ---- Slot A ----
    input  wire                    disp_A_valid_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_A_rs1_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_A_rs2_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_A_rd_arch_i,
    input  wire                    disp_A_writes_rd_i,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rs1_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rs2_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rd_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_A_rd_old_phys_o,

    // ---- Slot B ----
    input  wire                    disp_B_valid_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_B_rs1_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_B_rs2_arch_i,
    input  wire [ARCH_ADDR_W-1:0]  disp_B_rd_arch_i,
    input  wire                    disp_B_writes_rd_i,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rs1_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rs2_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rd_phys_o,
    output wire [PHYS_ADDR_W-1:0]  disp_B_rd_old_phys_o,

    // ---- Stall outputs (unchanged) ----
    output wire                    stall_A_o,
    output wire                    stall_B_o,

    // ---- Commit port A (original single port, now "slot A commit") ----
    input  wire                    commit_valid_i,
    input  wire [PHYS_ADDR_W-1:0]  commit_old_phys_i,

    // ---- Commit port B (NEW for Week 6 — 2-wide commit) ----
    input  wire                    commit_B_valid_i,
    input  wire [PHYS_ADDR_W-1:0]  commit_B_old_phys_i
);

    // ---- Rename map ----
    reg [PHYS_ADDR_W-1:0] rename_map [0:NUM_ARCH_REGS-1];

    // ---- Free list ----
    reg [PHYS_ADDR_W-1:0] free_list [0:FREE_LIST_SZ-1];
    reg [4:0] fl_head;
    reg [4:0] fl_tail;
    reg [4:0] fl_count;

    integer i;

    // ---- Allocation need ----
    wire A_needs_alloc = disp_A_valid_i & disp_A_writes_rd_i;
    wire B_needs_alloc = disp_B_valid_i & disp_B_writes_rd_i;

    // ---- Stall (unchanged logic) ----
    assign stall_A_o = A_needs_alloc & (fl_count == 5'd0);
    assign stall_B_o = A_needs_alloc & B_needs_alloc & (fl_count < 5'd2);

    // ---- Free list peeks ----
    wire [PHYS_ADDR_W-1:0] A_new_phys = free_list[fl_head[3:0]];
    wire [PHYS_ADDR_W-1:0] B_new_phys = A_needs_alloc
                                        ? free_list[(fl_head + 1) % FREE_LIST_SZ]
                                        : free_list[fl_head[3:0]];

    // ---- Intra-bundle bypass (unchanged logic) ----
    wire B_src1_uses_A = A_needs_alloc & (disp_A_rd_arch_i == disp_B_rs1_arch_i);
    wire B_src2_uses_A = A_needs_alloc & (disp_A_rd_arch_i == disp_B_rs2_arch_i);
    wire AB_write_same = A_needs_alloc & B_needs_alloc
                       & (disp_A_rd_arch_i == disp_B_rd_arch_i);

    // ---- Slot A outputs ----
    assign disp_A_rs1_phys_o    = rename_map[disp_A_rs1_arch_i];
    assign disp_A_rs2_phys_o    = rename_map[disp_A_rs2_arch_i];
    assign disp_A_rd_phys_o     = A_needs_alloc ? A_new_phys : rename_map[disp_A_rd_arch_i];
    assign disp_A_rd_old_phys_o = rename_map[disp_A_rd_arch_i];

    // ---- Slot B outputs ----
    assign disp_B_rs1_phys_o    = B_src1_uses_A ? A_new_phys : rename_map[disp_B_rs1_arch_i];
    assign disp_B_rs2_phys_o    = B_src2_uses_A ? A_new_phys : rename_map[disp_B_rs2_arch_i];
    assign disp_B_rd_phys_o     = B_needs_alloc ? B_new_phys : rename_map[disp_B_rd_arch_i];
    assign disp_B_rd_old_phys_o = AB_write_same ? A_new_phys : rename_map[disp_B_rd_arch_i];

    // ---- Actual allocation signals ----
    wire do_alloc_A  = A_needs_alloc & ~stall_A_o;
    wire do_alloc_B  = B_needs_alloc & ~stall_B_o & ~stall_A_o;
    wire do_commit_A = commit_valid_i;
    wire do_commit_B = commit_B_valid_i;   // NEW

    // ---- Synchronous state update ----
    always @(posedge clk_i) begin
        if (reset_i) begin
            for (i = 0; i < NUM_ARCH_REGS; i = i + 1)
                rename_map[i] <= i[PHYS_ADDR_W-1:0];
            for (i = 0; i < FREE_LIST_SZ; i = i + 1)
                free_list[i] <= NUM_ARCH_REGS[PHYS_ADDR_W-1:0] + i[PHYS_ADDR_W-1:0];
            fl_head  <= 5'd0;
            fl_tail  <= 5'd0;
            fl_count <= 5'd16;
        end else begin

            // ---- Update rename map (A first, B wins on WAW) ----
            if (do_alloc_A) rename_map[disp_A_rd_arch_i] <= A_new_phys;
            if (do_alloc_B) rename_map[disp_B_rd_arch_i] <= B_new_phys;

            // ---- Pop free list on dispatch ----
            if (do_alloc_A & do_alloc_B)
                fl_head <= (fl_head + 2) % FREE_LIST_SZ;
            else if (do_alloc_A | do_alloc_B)
                fl_head <= (fl_head + 1) % FREE_LIST_SZ;

            // ---- Push free list on commit (now 2-wide) ----
            // Commit A
            if (do_commit_A) begin
                free_list[fl_tail % FREE_LIST_SZ] <= commit_old_phys_i;
                fl_tail <= (fl_tail + 1) % FREE_LIST_SZ;
            end
            // Commit B — pushes at tail+1 if A also committed same cycle
            if (do_commit_B) begin
                if (do_commit_A)
                    free_list[(fl_tail + 1) % FREE_LIST_SZ] <= commit_B_old_phys_i;
                else
                    free_list[fl_tail % FREE_LIST_SZ] <= commit_B_old_phys_i;
                fl_tail <= (fl_tail + (do_commit_A ? 2 : 1)) % FREE_LIST_SZ;
            end

            // ---- Free list count: net change = commits - allocs ----
            begin : count_update
                reg [4:0] delta_in, delta_out;
                delta_in  = {4'b0, do_commit_A} + {4'b0, do_commit_B};
                delta_out = {4'b0, do_alloc_A}  + {4'b0, do_alloc_B};
                fl_count  <= fl_count + delta_in - delta_out;
            end
        end
    end

endmodule
