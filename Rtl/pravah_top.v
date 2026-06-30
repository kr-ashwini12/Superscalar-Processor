`timescale 1ns/1ps

module pravah_top (
    input wire clk_i,
    input wire reset_i
);

    // =========================================================================
    // Wires — named after the module that drives them
    // =========================================================================

    // ---- Fetch → Decode ----
    wire [31:0] fet_pc_A,    fet_pc_B;
    wire [31:0] fet_instr_A, fet_instr_B;
    wire        fet_valid_A, fet_valid_B;

    // ---- Decode A outputs ----
    wire [3:0]  dec_A_op;
    wire [4:0]  dec_A_rs1, dec_A_rs2, dec_A_rd;
    wire        dec_A_writes_rd;
    wire [31:0] dec_A_imm;
    wire [1:0]  dec_A_fu_type;
    wire        dec_A_valid;

    // ---- Decode B outputs ----
    wire [3:0]  dec_B_op;
    wire [4:0]  dec_B_rs1, dec_B_rs2, dec_B_rd;
    wire        dec_B_writes_rd;
    wire [31:0] dec_B_imm;
    wire [1:0]  dec_B_fu_type;
    wire        dec_B_valid;

    // ---- Rename outputs ----
    wire [5:0]  rn_A_rs1, rn_A_rs2, rn_A_rd, rn_A_old;
    wire [5:0]  rn_B_rs1, rn_B_rs2, rn_B_rd, rn_B_old;
    wire        rn_stall_A, rn_stall_B;

    // ---- Dispatch → RS ----
    wire        disp_rs_A_valid,  disp_rs_B_valid;
    wire [3:0]  disp_rs_A_op,     disp_rs_B_op;
    wire [5:0]  disp_rs_A_pj,     disp_rs_B_pj;
    wire [5:0]  disp_rs_A_pk,     disp_rs_B_pk;
    wire [5:0]  disp_rs_A_pd,     disp_rs_B_pd;
    wire [2:0]  disp_rs_A_rob,    disp_rs_B_rob;
    // imm passed separately (dispatch.v doesn't carry imm — added below as bypass)

    // ---- Dispatch → ROB ----
    wire        disp_rob_alloc_A, disp_rob_alloc_B;
    wire [4:0]  disp_rob_arch_A,  disp_rob_arch_B;
    wire [5:0]  disp_rob_phys_A,  disp_rob_phys_B;
    wire [5:0]  disp_rob_old_A,   disp_rob_old_B;
    wire        disp_rob_wrrd_A,  disp_rob_wrrd_B;

    // ---- Dispatch → Fetch ----
    wire        fe_stall;

    // ---- ROB outputs ----
    wire [2:0]  rob_tail;
    wire        rob_full;
    wire        rob_commit_A_valid, rob_commit_B_valid;
    wire [5:0]  rob_commit_A_old,   rob_commit_B_old;
    wire [4:0]  rob_commit_A_arch,  rob_commit_B_arch;
    wire [5:0]  rob_commit_A_phys,  rob_commit_B_phys;

    // ---- RS outputs ----
    wire        rs_full;
    wire        issue_0_valid,   issue_1_valid;
    wire [3:0]  issue_0_op,      issue_1_op;
    wire [5:0]  issue_0_pj,      issue_1_pj;
    wire [5:0]  issue_0_pk,      issue_1_pk;
    wire [5:0]  issue_0_pd,      issue_1_pd;
    wire [2:0]  issue_0_rob_idx, issue_1_rob_idx;
    wire [31:0] issue_0_imm,     issue_1_imm;

    // ---- PRF outputs ----
    wire [31:0] prf_rd1, prf_rd2, prf_rd3, prf_rd4;
    wire        prf_rdy1, prf_rdy2, prf_rdy3, prf_rdy4;  // (unused directly — RS uses vec)
    wire [47:0] prf_ready_vec;  // 48-bit, one per phys reg

    // ---- ALU outputs ----
    wire        alu0_valid, alu1_valid;
    wire [31:0] alu0_result, alu1_result;
    wire [5:0]  alu0_pd, alu1_pd;
    wire [2:0]  alu0_rob, alu1_rob;

    // =========================================================================
    // Module instances
    // =========================================================================

    // ---- Fetch----
    fetch #(.IMEM_DEPTH(256)) u_fetch (
        .clk_i     (clk_i),
        .reset_i   (reset_i),
        .fe_stall_i(fe_stall),
        .pc_A_o    (fet_pc_A),
        .instr_A_o (fet_instr_A),
        .valid_A_o (fet_valid_A),
        .pc_B_o    (fet_pc_B),
        .instr_B_o (fet_instr_B),
        .valid_B_o (fet_valid_B)
    );

    // ---- Decode A ----
    decode u_dec_A (
        .instr_i     (fet_instr_A),
        .valid_i     (fet_valid_A),
        .op_o        (dec_A_op),
        .rs1_arch_o  (dec_A_rs1),
        .rs2_arch_o  (dec_A_rs2),
        .rd_arch_o   (dec_A_rd),
        .writes_rd_o (dec_A_writes_rd),
        .imm_o       (dec_A_imm),
        .is_branch_o (),          // unused Week 6
        .is_memory_o (),          // unused Week 6
        .fu_type_o   (dec_A_fu_type),
        .valid_o     (dec_A_valid)
    );

    // ---- Decode B  ----
    decode u_dec_B (
        .instr_i     (fet_instr_B),
        .valid_i     (fet_valid_B),
        .op_o        (dec_B_op),
        .rs1_arch_o  (dec_B_rs1),
        .rs2_arch_o  (dec_B_rs2),
        .rd_arch_o   (dec_B_rd),
        .writes_rd_o (dec_B_writes_rd),
        .imm_o       (dec_B_imm),
        .is_branch_o (),
        .is_memory_o (),
        .fu_type_o   (dec_B_fu_type),
        .valid_o     (dec_B_valid)
    );

    // ---- Rename unit ----
    rename_unit u_rename (
        .clk_i               (clk_i),
        .reset_i             (reset_i),
        // Slot A
        .disp_A_valid_i      (dec_A_valid),
        .disp_A_rs1_arch_i   (dec_A_rs1),
        .disp_A_rs2_arch_i   (dec_A_rs2),
        .disp_A_rd_arch_i    (dec_A_rd),
        .disp_A_writes_rd_i  (dec_A_writes_rd),
        .disp_A_rs1_phys_o   (rn_A_rs1),
        .disp_A_rs2_phys_o   (rn_A_rs2),
        .disp_A_rd_phys_o    (rn_A_rd),
        .disp_A_rd_old_phys_o(rn_A_old),
        // Slot B
        .disp_B_valid_i      (dec_B_valid),
        .disp_B_rs1_arch_i   (dec_B_rs1),
        .disp_B_rs2_arch_i   (dec_B_rs2),
        .disp_B_rd_arch_i    (dec_B_rd),
        .disp_B_writes_rd_i  (dec_B_writes_rd),
        .disp_B_rs1_phys_o   (rn_B_rs1),
        .disp_B_rs2_phys_o   (rn_B_rs2),
        .disp_B_rd_phys_o    (rn_B_rd),
        .disp_B_rd_old_phys_o(rn_B_old),
        // Stall
        .stall_A_o           (rn_stall_A),
        .stall_B_o           (rn_stall_B),
        // Commit — A uses original single-port name; B is new
        .commit_valid_i      (rob_commit_A_valid),
        .commit_old_phys_i   (rob_commit_A_old),
        .commit_B_valid_i    (rob_commit_B_valid),
        .commit_B_old_phys_i (rob_commit_B_old)
    );

    // ---- Dispatch  ----
    dispatch u_dispatch (
        .clk_i                (clk_i),
        .reset_i              (reset_i),
        // Decode A
        .decode_A_valid_i     (dec_A_valid),
        .decode_A_op_i        (dec_A_op),
        .decode_A_rs1_arch_i  (dec_A_rs1),
        .decode_A_rs2_arch_i  (dec_A_rs2),
        .decode_A_rd_arch_i   (dec_A_rd),
        .decode_A_writes_rd_i (dec_A_writes_rd),
        .decode_A_fu_type_i   (dec_A_fu_type),
        // Decode B
        .decode_B_valid_i     (dec_B_valid),
        .decode_B_op_i        (dec_B_op),
        .decode_B_rs1_arch_i  (dec_B_rs1),
        .decode_B_rs2_arch_i  (dec_B_rs2),
        .decode_B_rd_arch_i   (dec_B_rd),
        .decode_B_writes_rd_i (dec_B_writes_rd),
        .decode_B_fu_type_i   (dec_B_fu_type),
        // Rename A
        .rename_A_rs1_phys_i  (rn_A_rs1),
        .rename_A_rs2_phys_i  (rn_A_rs2),
        .rename_A_rd_phys_i   (rn_A_rd),
        .rename_A_rd_old_phys_i(rn_A_old),
        .rename_stall_A_i     (rn_stall_A),
        // Rename B
        .rename_B_rs1_phys_i  (rn_B_rs1),
        .rename_B_rs2_phys_i  (rn_B_rs2),
        .rename_B_rd_phys_i   (rn_B_rd),
        .rename_B_rd_old_phys_i(rn_B_old),
        .rename_stall_B_i     (rn_stall_B),
        // ROB back-pressure
        .rob_tail_i           (rob_tail),
        .rob_full_i           (rob_full),
        // ROB allocation outputs
        .rob_alloc_A_o        (disp_rob_alloc_A),
        .rob_A_arch_dest_o    (disp_rob_arch_A),
        .rob_A_phys_dest_o    (disp_rob_phys_A),
        .rob_A_old_phys_dest_o(disp_rob_old_A),
        .rob_A_writes_rd_o    (disp_rob_wrrd_A),
        .rob_alloc_B_o        (disp_rob_alloc_B),
        .rob_B_arch_dest_o    (disp_rob_arch_B),
        .rob_B_phys_dest_o    (disp_rob_phys_B),
        .rob_B_old_phys_dest_o(disp_rob_old_B),
        .rob_B_writes_rd_o    (disp_rob_wrrd_B),
        // RS dispatch outputs
        .rs_disp_A_valid_o    (disp_rs_A_valid),
        .rs_disp_A_op_o       (disp_rs_A_op),
        .rs_disp_A_pj_o       (disp_rs_A_pj),
        .rs_disp_A_pk_o       (disp_rs_A_pk),
        .rs_disp_A_pd_o       (disp_rs_A_pd),
        .rs_disp_A_rob_idx_o  (disp_rs_A_rob),
        .rs_disp_B_valid_o    (disp_rs_B_valid),
        .rs_disp_B_op_o       (disp_rs_B_op),
        .rs_disp_B_pj_o       (disp_rs_B_pj),
        .rs_disp_B_pk_o       (disp_rs_B_pk),
        .rs_disp_B_pd_o       (disp_rs_B_pd),
        .rs_disp_B_rob_idx_o  (disp_rs_B_rob),
        // Stall to fetch
        .fe_stall_o           (fe_stall)
    );

    // ---- Reservation Station (new 2-issue version) ----
    reservation_station #(.NUM_RS(8), .NUM_PHYS(48)) u_rs (
        .clk_i              (clk_i),
        .reset_i            (reset_i),
        // Dispatch A
        .rs_disp_A_valid_i  (disp_rs_A_valid),
        .rs_disp_A_op_i     (disp_rs_A_op),
        .rs_disp_A_pj_i     (disp_rs_A_pj),
        .rs_disp_A_pk_i     (disp_rs_A_pk),
        .rs_disp_A_pd_i     (disp_rs_A_pd),
        .rs_disp_A_rob_idx_i(disp_rs_A_rob),
        .rs_disp_A_imm_i    (dec_A_imm),    // direct from decode (bypasses dispatch)
        // Dispatch B
        .rs_disp_B_valid_i  (disp_rs_B_valid),
        .rs_disp_B_op_i     (disp_rs_B_op),
        .rs_disp_B_pj_i     (disp_rs_B_pj),
        .rs_disp_B_pk_i     (disp_rs_B_pk),
        .rs_disp_B_pd_i     (disp_rs_B_pd),
        .rs_disp_B_rob_idx_i(disp_rs_B_rob),
        .rs_disp_B_imm_i    (dec_B_imm),    // direct from decode
        // Full
        .rs_full_o          (rs_full),
        // PRF snoop
        .prf_ready_vec_i    (prf_ready_vec),
        // Issue bus 0
        .issue_0_valid_o    (issue_0_valid),
        .issue_0_op_o       (issue_0_op),
        .issue_0_pj_o       (issue_0_pj),
        .issue_0_pk_o       (issue_0_pk),
        .issue_0_pd_o       (issue_0_pd),
        .issue_0_rob_idx_o  (issue_0_rob_idx),
        .issue_0_imm_o      (issue_0_imm),
        // Issue bus 1
        .issue_1_valid_o    (issue_1_valid),
        .issue_1_op_o       (issue_1_op),
        .issue_1_pj_o       (issue_1_pj),
        .issue_1_pk_o       (issue_1_pk),
        .issue_1_pd_o       (issue_1_pd),
        .issue_1_rob_idx_o  (issue_1_rob_idx),
        .issue_1_imm_o      (issue_1_imm)
    );

    // ---- PRF  ----
    register_file #(.NUM_PHYS_REGS(48)) u_prf (
        .clk_i       (clk_i),
        .reset_i     (reset_i),
        // Read port 1 — ALU0 src1
        .rd_addr1_i  (issue_0_pj),
        .rd_data1_o  (prf_rd1),
        .rd_ready1_o (prf_rdy1),
        // Read port 2 — ALU0 src2
        .rd_addr2_i  (issue_0_pk),
        .rd_data2_o  (prf_rd2),
        .rd_ready2_o (prf_rdy2),
        // Read port 3 — ALU1 src1
        .rd_addr3_i  (issue_1_pj),
        .rd_data3_o  (prf_rd3),
        .rd_ready3_o (prf_rdy3),
        // Read port 4 — ALU1 src2
        .rd_addr4_i  (issue_1_pk),
        .rd_data4_o  (prf_rd4),
        .rd_ready4_o (prf_rdy4),
        // Write port 1 — ALU0 writeback
        .wr_en1_i    (alu0_valid),
        .wr_addr1_i  (alu0_pd),
        .wr_data1_i  (alu0_result),
        // Write port 2 — ALU1 writeback
        .wr_en2_i    (alu1_valid),
        .wr_addr2_i  (alu1_pd),
        .wr_data2_i  (alu1_result),
        // Alloc port 1 — slot A dispatch clears ready
        .alloc_en1_i  (disp_rob_alloc_A & disp_rob_wrrd_A),
        .alloc_addr1_i(disp_rob_phys_A),
        // Alloc port 2 — slot B dispatch clears ready (NEW)
        .alloc_en2_i  (disp_rob_alloc_B & disp_rob_wrrd_B),
        .alloc_addr2_i(disp_rob_phys_B),
        // Ready vector → RS snoop
        .ready_vec_o (prf_ready_vec)
    );

    // ---- ALU 0 ----
    alu u_alu0 (
        .clk_i        (clk_i),
        .reset_i      (reset_i),
        .valid_i      (issue_0_valid),
        .op_i         (issue_0_op),
        .src1_val_i   (prf_rd1),
        .src2_val_i   (prf_rd2),
        .imm_i        (issue_0_imm),
        .phys_dest_i  (issue_0_pd),
        .rob_idx_i    (issue_0_rob_idx),
        .result_valid_o(alu0_valid),
        .result_o     (alu0_result),
        .phys_dest_o  (alu0_pd),
        .rob_idx_o    (alu0_rob)
    );

    // ---- ALU 1 ----
    alu u_alu1 (
        .clk_i        (clk_i),
        .reset_i      (reset_i),
        .valid_i      (issue_1_valid),
        .op_i         (issue_1_op),
        .src1_val_i   (prf_rd3),
        .src2_val_i   (prf_rd4),
        .imm_i        (issue_1_imm),
        .phys_dest_i  (issue_1_pd),
        .rob_idx_i    (issue_1_rob_idx),
        .result_valid_o(alu1_valid),
        .result_o     (alu1_result),
        .phys_dest_o  (alu1_pd),
        .rob_idx_o    (alu1_rob)
    );

    // ---- ROB ----
    rob u_rob (
        .clk_i                (clk_i),
        .reset_i              (reset_i),
        // Dispatch
        .alloc_A_i            (disp_rob_alloc_A),
        .rob_A_writes_rd_i    (disp_rob_wrrd_A),
        .rob_A_arch_dest_i    (disp_rob_arch_A),
        .rob_A_phys_dest_i    (disp_rob_phys_A),
        .rob_A_old_phys_dest_i(disp_rob_old_A),
        .alloc_B_i            (disp_rob_alloc_B),
        .rob_B_writes_rd_i    (disp_rob_wrrd_B),
        .rob_B_arch_dest_i    (disp_rob_arch_B),
        .rob_B_phys_dest_i    (disp_rob_phys_B),
        .rob_B_old_phys_dest_i(disp_rob_old_B),
        // Status
        .rob_tail_o           (rob_tail),
        .rob_full_o           (rob_full),
        // Mark-ready from ALUs
        .mark_rdy_0_en_i      (alu0_valid),
        .mark_rdy_0_idx_i     (alu0_rob),
        .mark_rdy_1_en_i      (alu1_valid),
        .mark_rdy_1_idx_i     (alu1_rob),
        // Commit
        .commit_A_valid_o     (rob_commit_A_valid),
        .commit_A_old_phys_o  (rob_commit_A_old),
        .commit_A_arch_dest_o (rob_commit_A_arch),
        .commit_A_phys_dest_o (rob_commit_A_phys),
        .commit_B_valid_o     (rob_commit_B_valid),
        .commit_B_old_phys_o  (rob_commit_B_old),
        .commit_B_arch_dest_o (rob_commit_B_arch),
        .commit_B_phys_dest_o (rob_commit_B_phys)
    );

endmodule
