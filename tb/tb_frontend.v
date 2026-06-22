`timescale 1ns / 1ps

module tb_frontend;
    // Parameters
    localparam ARCH_ADDR_W = 5;
    localparam PHYS_ADDR_W = 6;
    localparam OP_WIDTH    = 4;
    localparam ROB_ADDR_W  = 3;
    localparam NUM_RS      = 4;
    // Clock & reset
    reg clk   = 0;
    reg reset = 1;
    always #5 clk = ~clk;
    // ROB stub
    reg  [ROB_ADDR_W-1:0] rob_tail = 0;
    wire                  rob_full = 1'b0;   // never full this week

    // ----------------------------------------------------------
    // PRF ready-bit stub: all regs ready (no execution yet)
    // ----------------------------------------------------------
    wire [NUM_RS*PHYS_ADDR_W-1:0] snoop_pj_addr;
    wire [NUM_RS*PHYS_ADDR_W-1:0] snoop_pk_addr;
    wire [NUM_RS-1:0] snoop_pj_ready = {NUM_RS{1'b1}};
    wire [NUM_RS-1:0] snoop_pk_ready = {NUM_RS{1'b1}};

    // ----------------------------------------------------------
    // Wires: fetch -> decode
    // ----------------------------------------------------------
    wire [31:0] instr_A, instr_B;
    wire        valid_A, valid_B;
    wire [31:0] pc_A,    pc_B;
    wire        fe_stall;

    // ----------------------------------------------------------
    // Wires: decode -> dispatch/rename
    // ----------------------------------------------------------
    wire [OP_WIDTH-1:0]    dec_A_op,    dec_B_op;
    wire [ARCH_ADDR_W-1:0] dec_A_rs1,   dec_B_rs1;
    wire [ARCH_ADDR_W-1:0] dec_A_rs2,   dec_B_rs2;
    wire [ARCH_ADDR_W-1:0] dec_A_rd,    dec_B_rd;
    wire                   dec_A_wrd,   dec_B_wrd;
    wire [31:0]            dec_A_imm,   dec_B_imm;
    wire                   dec_A_br,    dec_B_br;
    wire                   dec_A_mem,   dec_B_mem;
    wire [1:0]             dec_A_fu,    dec_B_fu;
    wire                   dec_A_valid, dec_B_valid;

    // ----------------------------------------------------------
    // Wires: rename -> dispatch
    // ----------------------------------------------------------
    wire [PHYS_ADDR_W-1:0] ren_A_rs1, ren_B_rs1;
    wire [PHYS_ADDR_W-1:0] ren_A_rs2, ren_B_rs2;
    wire [PHYS_ADDR_W-1:0] ren_A_rd,  ren_B_rd;
    wire [PHYS_ADDR_W-1:0] ren_A_old, ren_B_old;
    wire                   stall_A,   stall_B;

    // ----------------------------------------------------------
    // Wires: dispatch -> RS
    // ----------------------------------------------------------
    wire                   rs_disp_A_valid, rs_disp_B_valid;
    wire [OP_WIDTH-1:0]    rs_disp_A_op,    rs_disp_B_op;
    wire [PHYS_ADDR_W-1:0] rs_disp_A_pj,    rs_disp_B_pj;
    wire [PHYS_ADDR_W-1:0] rs_disp_A_pk,    rs_disp_B_pk;
    wire [PHYS_ADDR_W-1:0] rs_disp_A_pd,    rs_disp_B_pd;
    wire [ROB_ADDR_W-1:0]  rs_disp_A_rob,   rs_disp_B_rob;

    // ----------------------------------------------------------
    // Wires: dispatch -> ROB stub
    // ----------------------------------------------------------
    wire                   rob_alloc_A, rob_alloc_B;
    wire [ARCH_ADDR_W-1:0] rob_A_arch,  rob_B_arch;
    wire [PHYS_ADDR_W-1:0] rob_A_phys,  rob_B_phys;
    wire [PHYS_ADDR_W-1:0] rob_A_old,   rob_B_old;
    wire                   rob_A_wrd,   rob_B_wrd;

    // RS issue port (not checked this week - no execution)
    wire                   issue_valid;
    wire [OP_WIDTH-1:0]    issue_op;
    wire [PHYS_ADDR_W-1:0] issue_pj, issue_pk, issue_pd;
    wire [ROB_ADDR_W-1:0]  issue_rob;
    wire                   disp_stall;

    // ----------------------------------------------------------
    // Module instantiations
    // ----------------------------------------------------------

    fetch #(.PC_WIDTH(32), .IMEM_DEPTH(256)) u_fetch (
        .clk_i      (clk),
        .reset_i    (reset),
        .fe_stall_i (fe_stall),
        .pc_A_o     (pc_A),   .instr_A_o (instr_A), .valid_A_o (valid_A),
        .pc_B_o     (pc_B),   .instr_B_o (instr_B), .valid_B_o (valid_B)
    );

    decode #(.ARCH_ADDR_W(ARCH_ADDR_W), .OP_WIDTH(OP_WIDTH)) u_dec_A (
        .instr_i    (instr_A),   .valid_i    (valid_A),
        .op_o       (dec_A_op),  .rs1_arch_o (dec_A_rs1), .rs2_arch_o (dec_A_rs2),
        .rd_arch_o  (dec_A_rd),  .writes_rd_o(dec_A_wrd), .imm_o      (dec_A_imm),
        .is_branch_o(dec_A_br),  .is_memory_o(dec_A_mem), .fu_type_o  (dec_A_fu),
        .valid_o    (dec_A_valid)
    );

    decode #(.ARCH_ADDR_W(ARCH_ADDR_W), .OP_WIDTH(OP_WIDTH)) u_dec_B (
        .instr_i    (instr_B),   .valid_i    (valid_B),
        .op_o       (dec_B_op),  .rs1_arch_o (dec_B_rs1), .rs2_arch_o (dec_B_rs2),
        .rd_arch_o  (dec_B_rd),  .writes_rd_o(dec_B_wrd), .imm_o      (dec_B_imm),
        .is_branch_o(dec_B_br),  .is_memory_o(dec_B_mem), .fu_type_o  (dec_B_fu),
        .valid_o    (dec_B_valid)
    );

    rename_unit #(
        .NUM_ARCH_REGS(32), .NUM_PHYS_REGS(48),
        .ARCH_ADDR_W(ARCH_ADDR_W), .PHYS_ADDR_W(PHYS_ADDR_W)
    ) u_rename (
        .clk_i              (clk),    .reset_i           (reset),
        .disp_A_valid_i     (dec_A_valid), .disp_A_rs1_arch_i (dec_A_rs1),
        .disp_A_rs2_arch_i  (dec_A_rs2),  .disp_A_rd_arch_i  (dec_A_rd),
        .disp_A_writes_rd_i (dec_A_wrd),  .disp_A_rs1_phys_o (ren_A_rs1),
        .disp_A_rs2_phys_o  (ren_A_rs2),  .disp_A_rd_phys_o  (ren_A_rd),
        .disp_A_rd_old_phys_o(ren_A_old),
        .disp_B_valid_i     (dec_B_valid), .disp_B_rs1_arch_i (dec_B_rs1),
        .disp_B_rs2_arch_i  (dec_B_rs2),  .disp_B_rd_arch_i  (dec_B_rd),
        .disp_B_writes_rd_i (dec_B_wrd),  .disp_B_rs1_phys_o (ren_B_rs1),
        .disp_B_rs2_phys_o  (ren_B_rs2),  .disp_B_rd_phys_o  (ren_B_rd),
        .disp_B_rd_old_phys_o(ren_B_old),
        .stall_A_o          (stall_A),    .stall_B_o         (stall_B),
        .commit_valid_i     (1'b0),       .commit_old_phys_i ({PHYS_ADDR_W{1'b0}})
    );

    dispatch #(
        .ARCH_ADDR_W(ARCH_ADDR_W), .PHYS_ADDR_W(PHYS_ADDR_W),
        .OP_WIDTH(OP_WIDTH),        .ROB_ADDR_W(ROB_ADDR_W)
    ) u_dispatch (
        .clk_i                 (clk),    .reset_i              (reset),
        .decode_A_valid_i      (dec_A_valid), .decode_A_op_i   (dec_A_op),
        .decode_A_rs1_arch_i   (dec_A_rs1),  .decode_A_rs2_arch_i(dec_A_rs2),
        .decode_A_rd_arch_i    (dec_A_rd),   .decode_A_writes_rd_i(dec_A_wrd),
        .decode_A_fu_type_i    (dec_A_fu),
        .decode_B_valid_i      (dec_B_valid),.decode_B_op_i   (dec_B_op),
        .decode_B_rs1_arch_i   (dec_B_rs1),  .decode_B_rs2_arch_i(dec_B_rs2),
        .decode_B_rd_arch_i    (dec_B_rd),   .decode_B_writes_rd_i(dec_B_wrd),
        .decode_B_fu_type_i    (dec_B_fu),
        .rename_A_rs1_phys_i   (ren_A_rs1),  .rename_A_rs2_phys_i(ren_A_rs2),
        .rename_A_rd_phys_i    (ren_A_rd),   .rename_A_rd_old_phys_i(ren_A_old),
        .rename_stall_A_i      (stall_A),
        .rename_B_rs1_phys_i   (ren_B_rs1),  .rename_B_rs2_phys_i(ren_B_rs2),
        .rename_B_rd_phys_i    (ren_B_rd),   .rename_B_rd_old_phys_i(ren_B_old),
        .rename_stall_B_i      (stall_B),
        .rob_tail_i            (rob_tail),   .rob_full_i        (rob_full),
        .rob_alloc_A_o         (rob_alloc_A),.rob_A_arch_dest_o (rob_A_arch),
        .rob_A_phys_dest_o     (rob_A_phys), .rob_A_old_phys_dest_o(rob_A_old),
        .rob_A_writes_rd_o     (rob_A_wrd),
        .rob_alloc_B_o         (rob_alloc_B),.rob_B_arch_dest_o (rob_B_arch),
        .rob_B_phys_dest_o     (rob_B_phys), .rob_B_old_phys_dest_o(rob_B_old),
        .rob_B_writes_rd_o     (rob_B_wrd),
        .rs_disp_A_valid_o     (rs_disp_A_valid),.rs_disp_A_op_o(rs_disp_A_op),
        .rs_disp_A_pj_o        (rs_disp_A_pj),   .rs_disp_A_pk_o(rs_disp_A_pk),
        .rs_disp_A_pd_o        (rs_disp_A_pd),   .rs_disp_A_rob_idx_o(rs_disp_A_rob),
        .rs_disp_B_valid_o     (rs_disp_B_valid),.rs_disp_B_op_o(rs_disp_B_op),
        .rs_disp_B_pj_o        (rs_disp_B_pj),   .rs_disp_B_pk_o(rs_disp_B_pk),
        .rs_disp_B_pd_o        (rs_disp_B_pd),   .rs_disp_B_rob_idx_o(rs_disp_B_rob),
        .fe_stall_o            (fe_stall)
    );

    reservation_station #(
        .NUM_RS(NUM_RS), .PHYS_ADDR_W(PHYS_ADDR_W),
        .ROB_ADDR_W(ROB_ADDR_W), .OP_WIDTH(OP_WIDTH)
    ) u_rs (
        .clk_i             (clk),    .reset_i          (reset),
        .disp_A_valid_i    (rs_disp_A_valid), .disp_A_op_i (rs_disp_A_op),
        .disp_A_pj_i       (rs_disp_A_pj),   .disp_A_pk_i (rs_disp_A_pk),
        .disp_A_pd_i       (rs_disp_A_pd),   .disp_A_rob_idx_i(rs_disp_A_rob),
        .disp_B_valid_i    (rs_disp_B_valid), .disp_B_op_i (rs_disp_B_op),
        .disp_B_pj_i       (rs_disp_B_pj),   .disp_B_pk_i (rs_disp_B_pk),
        .disp_B_pd_i       (rs_disp_B_pd),   .disp_B_rob_idx_i(rs_disp_B_rob),
        .disp_stall_o      (disp_stall),
        .snoop_pj_addr_o   (snoop_pj_addr),  .snoop_pk_addr_o(snoop_pk_addr),
        .snoop_pj_ready_i  (snoop_pj_ready), .snoop_pk_ready_i(snoop_pk_ready),
        .issue_valid_o     (issue_valid),     .issue_op_o   (issue_op),
        .issue_pj_o        (issue_pj),        .issue_pk_o   (issue_pk),
        .issue_pd_o        (issue_pd),        .issue_rob_idx_o(issue_rob)
    );

    // ----------------------------------------------------------
    // ROB tail counter (stub)
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (reset)
            rob_tail <= 0;
        else
            rob_tail <= rob_tail + rob_alloc_A + rob_alloc_B;
    end

    // ----------------------------------------------------------
    // Load instruction memory
    // ----------------------------------------------------------
    initial begin
        $readmemh("test1.hex", u_fetch.imem);
    end

    // ----------------------------------------------------------
    // VCD dump
    // ----------------------------------------------------------
    initial begin
        $dumpfile("frontend_dispatch.vcd");
        $dumpvars(0, tb_frontend);
    end

    // ----------------------------------------------------------
    // Self-checking stimulus
    // ----------------------------------------------------------
    integer errors = 0;
    integer tests  = 0;
    integer cycle  = 0;

    // Track expected physical register allocations
    // Free list starts at P32, increments each allocation
    integer next_phys;

    task check_eq;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] label;
        begin
            tests = tests + 1;
            if (actual === expected)
                $display("  PASS  %s  (got P%0d)", label, actual);
            else begin
                $display("  FAIL  %s  (expected P%0d, got P%0d)",
                         label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    always @(posedge clk) cycle <= cycle + 1;

    // Print dispatch activity every cycle
    always @(posedge clk) begin
        if (!reset) begin
            if (rob_alloc_A || rob_alloc_B) begin
                $display("Cycle %0d: A_disp=%0b (rd=x%0d,P%0d, rs1=P%0d, rs2=P%0d) | B_disp=%0b (rd=x%0d,P%0d, rs1=P%0d, rs2=P%0d)",
                    cycle,
                    rob_alloc_A, rob_A_arch, rob_A_phys, rs_disp_A_pj, rs_disp_A_pk,
                    rob_alloc_B, rob_B_arch, rob_B_phys, rs_disp_B_pj, rs_disp_B_pk);
            end
        end
    end

    initial begin
        next_phys = 32;  // free list starts at P32

        // Release reset after 2 cycles
        #20; reset = 0;

        // Wait enough cycles for all 5 bundles to dispatch
        // fetch latches on cycle 1, decode is combinational same cycle,
        // dispatch fires the following cycle -> bundles appear at cycles 2..6
        repeat(10) @(posedge clk);
        #1;

        $display("\n======================================================");
        $display("PRAVAH Week 5 - Front-End Integration Check");
        $display("======================================================");

        // --------------------------------------------------
        // Check Bundle 2 (intra-bundle RAW):
        //   slot A: add x3, x1, x2  -> gets P34 (3rd alloc: P32=x1,P33=x2,P34=x3)
        //   slot B: add x4, x3, x1  -> B's rs1 must be P34 (bypass), not P3
        // We read it from the RS directly after all dispatches settle.
        // Check the rename map via the rename unit's internal state.
        // --------------------------------------------------

        // Verify rename map final state using $display readback
        // After all 10 instructions:
        //   x1 -> P32 (addi x1)
        //   x2 -> P33 (addi x2)
        //   x3 -> P34 (add x3)
        //   x4 -> P35 (add x4)
        //   x5 -> P37 (second add x5 wins WAW; P36 was first)
        //   x6 -> P41 (second add x6 wins; P38 was first)
        //   x7 -> P39 (add x7)
        //   x8 -> P40 (add x8)

        $display("\n--- Rename map final state (arch->phys) ---");
        $display("  x1 -> P%0d  (expect P32)", u_rename.rename_map[1]);
        $display("  x2 -> P%0d  (expect P33)", u_rename.rename_map[2]);
        $display("  x3 -> P%0d  (expect P34)", u_rename.rename_map[3]);
        $display("  x4 -> P%0d  (expect P35)", u_rename.rename_map[4]);
        $display("  x5 -> P%0d  (expect P37, WAW: B wins)", u_rename.rename_map[5]);
        $display("  x6 -> P%0d  (expect P41, Bundle5-B wins)", u_rename.rename_map[6]);
        $display("  x7 -> P%0d  (expect P39)", u_rename.rename_map[7]);
        $display("  x8 -> P%0d  (expect P40)", u_rename.rename_map[8]);

        check_eq(u_rename.rename_map[1], 32, "x1->P32");
        check_eq(u_rename.rename_map[2], 33, "x2->P33");
        check_eq(u_rename.rename_map[3], 34, "x3->P34");
        check_eq(u_rename.rename_map[4], 35, "x4->P35");
        check_eq(u_rename.rename_map[5], 37, "x5->P37 (WAW: slot B wins)");
        check_eq(u_rename.rename_map[6], 41, "x6->P41 (Bundle5-B wins)");
        check_eq(u_rename.rename_map[7], 39, "x7->P39");
        check_eq(u_rename.rename_map[8], 40, "x8->P40");

        $display("\n--- Free list count (expect 6 used = 10 allocs - 0 frees) ---");
        $display("  fl_count = %0d  (expect 6)", u_rename.fl_count);
        check_eq(u_rename.fl_count, 6, "fl_count=6 after 10 allocs");

        $display("\n======================================================");
        if (errors == 0)
            $display("ALL CHECKS PASSED (%0d / %0d)", tests, tests);
        else
            $display("FAILED %0d / %0d CHECKS", errors, tests);
        $display("======================================================\n");
        $finish;
    end

    // Timeout guard
    initial begin
        #5000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
