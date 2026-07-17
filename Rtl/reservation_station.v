`timescale 1ns/1ps

module reservation_station #(
    parameter NUM_RS      = 8,
    parameter PHYS_ADDR_W = 6,
    parameter ROB_ADDR_W  = 3,
    parameter OP_WIDTH    = 4,
    parameter DATA_WIDTH  = 32,
    parameter NUM_PHYS    = 48
) (
    input  wire clk_i,
    input  wire reset_i,

    // ---- Dispatch port A (names mirror dispatch.v outputs) ----
    input  wire                    rs_disp_A_valid_i,
    input  wire [OP_WIDTH-1:0]     rs_disp_A_op_i,
    input  wire [PHYS_ADDR_W-1:0]  rs_disp_A_pj_i,      // phys src1
    input  wire [PHYS_ADDR_W-1:0]  rs_disp_A_pk_i,      // phys src2
    input  wire [PHYS_ADDR_W-1:0]  rs_disp_A_pd_i,      // phys dest
    input  wire [ROB_ADDR_W-1:0]   rs_disp_A_rob_idx_i,
    input  wire [DATA_WIDTH-1:0]   rs_disp_A_imm_i,     // immediate from decode

    // ---- Dispatch port B ----
    input  wire                    rs_disp_B_valid_i,
    input  wire [OP_WIDTH-1:0]     rs_disp_B_op_i,
    input  wire [PHYS_ADDR_W-1:0]  rs_disp_B_pj_i,
    input  wire [PHYS_ADDR_W-1:0]  rs_disp_B_pk_i,
    input  wire [PHYS_ADDR_W-1:0]  rs_disp_B_pd_i,
    input  wire [ROB_ADDR_W-1:0]   rs_disp_B_rob_idx_i,
    input  wire [DATA_WIDTH-1:0]   rs_disp_B_imm_i,

    // ---- Back-pressure ----
    output wire                    rs_full_o,

    // ---- PRF ready vector (48 bits, one per phys reg) ----
    input  wire [NUM_PHYS-1:0]     prf_ready_vec_i,

    // ---- Alloc ports (which phys regs are being allocated THIS cycle) ----
    // Needed so RS doesn't mark a just-allocated reg as ready at dispatch time
    input  wire                    alloc_en1_i,
    input  wire [PHYS_ADDR_W-1:0]  alloc_addr1_i,
    input  wire                    alloc_en2_i,
    input  wire [PHYS_ADDR_W-1:0]  alloc_addr2_i,

    // ---- Issue bus 0 → ALU0 ----
    output wire                    issue_0_valid_o,
    output wire [OP_WIDTH-1:0]     issue_0_op_o,
    output wire [PHYS_ADDR_W-1:0]  issue_0_pj_o,
    output wire [PHYS_ADDR_W-1:0]  issue_0_pk_o,
    output wire [PHYS_ADDR_W-1:0]  issue_0_pd_o,
    output wire [ROB_ADDR_W-1:0]   issue_0_rob_idx_o,
    output wire [DATA_WIDTH-1:0]   issue_0_imm_o,

    // ---- Issue bus 1 → ALU1 ----
    output wire                    issue_1_valid_o,
    output wire [OP_WIDTH-1:0]     issue_1_op_o,
    output wire [PHYS_ADDR_W-1:0]  issue_1_pj_o,
    output wire [PHYS_ADDR_W-1:0]  issue_1_pk_o,
    output wire [PHYS_ADDR_W-1:0]  issue_1_pd_o,
    output wire [ROB_ADDR_W-1:0]   issue_1_rob_idx_o,
    output wire [DATA_WIDTH-1:0]   issue_1_imm_o
);

    // ---- RS entry storage ----
    reg                    rs_busy    [0:NUM_RS-1];
    reg [OP_WIDTH-1:0]     rs_op      [0:NUM_RS-1];
    reg [PHYS_ADDR_W-1:0]  rs_pj      [0:NUM_RS-1];
    reg [PHYS_ADDR_W-1:0]  rs_pk      [0:NUM_RS-1];
    reg                    rs_qj_rdy  [0:NUM_RS-1];   // src1 ready (latched)
    reg                    rs_qk_rdy  [0:NUM_RS-1];   // src2 ready (latched)
    reg [PHYS_ADDR_W-1:0]  rs_pd      [0:NUM_RS-1];
    reg [ROB_ADDR_W-1:0]   rs_rob_idx [0:NUM_RS-1];
    reg [DATA_WIDTH-1:0]   rs_imm     [0:NUM_RS-1];

    // ---- Occupancy ----
    reg [3:0] rs_count;
    assign rs_full_o = (rs_count >= NUM_RS - 2);  // stop 2 from full (2-wide dispatch)

    // ---- ADDI detection: pk treated as ready when op==ADDI ----
    // op encoding from YOUR decode.v: ADDI = 4'd8
    wire is_addi_A = (rs_disp_A_op_i == 4'd8);
    wire is_addi_B = (rs_disp_B_op_i == 4'd8);

    // ---- Free-slot finder: lowest-index rs_busy==0 ----
    wire [NUM_RS-1:0] rs_free_vec;
    genvar g;
    generate
        for (g = 0; g < NUM_RS; g = g + 1) begin : fv
            assign rs_free_vec[g] = ~rs_busy[g];
        end
    endgenerate

    // Priority-encode first free slot (for dispatch A)
    wire [NUM_RS-1:0] free_sel_A;
    assign free_sel_A[0] = rs_free_vec[0];
    assign free_sel_A[1] = rs_free_vec[1] & ~rs_free_vec[0];
    assign free_sel_A[2] = rs_free_vec[2] & ~rs_free_vec[1] & ~rs_free_vec[0];
    assign free_sel_A[3] = rs_free_vec[3] & ~rs_free_vec[2] & ~rs_free_vec[1] & ~rs_free_vec[0];
    assign free_sel_A[4] = rs_free_vec[4] & ~rs_free_vec[3] & ~rs_free_vec[2] & ~rs_free_vec[1] & ~rs_free_vec[0];
    assign free_sel_A[5] = rs_free_vec[5] & ~rs_free_vec[4] & ~rs_free_vec[3] & ~rs_free_vec[2] & ~rs_free_vec[1] & ~rs_free_vec[0];
    assign free_sel_A[6] = rs_free_vec[6] & ~rs_free_vec[5] & ~rs_free_vec[4] & ~rs_free_vec[3] & ~rs_free_vec[2] & ~rs_free_vec[1] & ~rs_free_vec[0];
    assign free_sel_A[7] = rs_free_vec[7] & ~rs_free_vec[6] & ~rs_free_vec[5] & ~rs_free_vec[4] & ~rs_free_vec[3] & ~rs_free_vec[2] & ~rs_free_vec[1] & ~rs_free_vec[0];

    // Mask and find second free slot (for dispatch B)
    wire [NUM_RS-1:0] free_rem  = rs_free_vec & ~free_sel_A;
    wire [NUM_RS-1:0] free_sel_B;
    assign free_sel_B[0] = free_rem[0];
    assign free_sel_B[1] = free_rem[1] & ~free_rem[0];
    assign free_sel_B[2] = free_rem[2] & ~free_rem[1] & ~free_rem[0];
    assign free_sel_B[3] = free_rem[3] & ~free_rem[2] & ~free_rem[1] & ~free_rem[0];
    assign free_sel_B[4] = free_rem[4] & ~free_rem[3] & ~free_rem[2] & ~free_rem[1] & ~free_rem[0];
    assign free_sel_B[5] = free_rem[5] & ~free_rem[4] & ~free_rem[3] & ~free_rem[2] & ~free_rem[1] & ~free_rem[0];
    assign free_sel_B[6] = free_rem[6] & ~free_rem[5] & ~free_rem[4] & ~free_rem[3] & ~free_rem[2] & ~free_rem[1] & ~free_rem[0];
    assign free_sel_B[7] = free_rem[7] & ~free_rem[6] & ~free_rem[5] & ~free_rem[4] & ~free_rem[3] & ~free_rem[2] & ~free_rem[1] & ~free_rem[0];

    // ---- Wakeup: entry ready when both sources ready ----
    // src1 ready: latched OR current PRF snoop
    // src2 ready: latched OR current PRF snoop OR is ADDI (op==8, pk unused)
    wire [NUM_RS-1:0] wakeup_rdy;
    generate
        for (g = 0; g < NUM_RS; g = g + 1) begin : wk
            wire pj_ok = rs_qj_rdy[g] | prf_ready_vec_i[rs_pj[g]];
            wire pk_ok = rs_qk_rdy[g] | prf_ready_vec_i[rs_pk[g]]
                       | (rs_op[g] == 4'd8);   // ADDI: pk unused
            assign wakeup_rdy[g] = rs_busy[g] & pj_ok & pk_ok;
        end
    endgenerate

    // ---- Issue select: 2-pick mask-and-encode ----
    // Pick 0 (lowest-index wakeup-ready)
    wire [NUM_RS-1:0] issue_sel_0;
    assign issue_sel_0[0] = wakeup_rdy[0];
    assign issue_sel_0[1] = wakeup_rdy[1] & ~wakeup_rdy[0];
    assign issue_sel_0[2] = wakeup_rdy[2] & ~wakeup_rdy[1] & ~wakeup_rdy[0];
    assign issue_sel_0[3] = wakeup_rdy[3] & ~wakeup_rdy[2] & ~wakeup_rdy[1] & ~wakeup_rdy[0];
    assign issue_sel_0[4] = wakeup_rdy[4] & ~wakeup_rdy[3] & ~wakeup_rdy[2] & ~wakeup_rdy[1] & ~wakeup_rdy[0];
    assign issue_sel_0[5] = wakeup_rdy[5] & ~wakeup_rdy[4] & ~wakeup_rdy[3] & ~wakeup_rdy[2] & ~wakeup_rdy[1] & ~wakeup_rdy[0];
    assign issue_sel_0[6] = wakeup_rdy[6] & ~wakeup_rdy[5] & ~wakeup_rdy[4] & ~wakeup_rdy[3] & ~wakeup_rdy[2] & ~wakeup_rdy[1] & ~wakeup_rdy[0];
    assign issue_sel_0[7] = wakeup_rdy[7] & ~wakeup_rdy[6] & ~wakeup_rdy[5] & ~wakeup_rdy[4] & ~wakeup_rdy[3] & ~wakeup_rdy[2] & ~wakeup_rdy[1] & ~wakeup_rdy[0];

    // Pick 1 (mask out pick 0, then lowest-index)
    wire [NUM_RS-1:0] wk_rem  = wakeup_rdy & ~issue_sel_0;
    wire [NUM_RS-1:0] issue_sel_1;
    assign issue_sel_1[0] = wk_rem[0];
    assign issue_sel_1[1] = wk_rem[1] & ~wk_rem[0];
    assign issue_sel_1[2] = wk_rem[2] & ~wk_rem[1] & ~wk_rem[0];
    assign issue_sel_1[3] = wk_rem[3] & ~wk_rem[2] & ~wk_rem[1] & ~wk_rem[0];
    assign issue_sel_1[4] = wk_rem[4] & ~wk_rem[3] & ~wk_rem[2] & ~wk_rem[1] & ~wk_rem[0];
    assign issue_sel_1[5] = wk_rem[5] & ~wk_rem[4] & ~wk_rem[3] & ~wk_rem[2] & ~wk_rem[1] & ~wk_rem[0];
    assign issue_sel_1[6] = wk_rem[6] & ~wk_rem[5] & ~wk_rem[4] & ~wk_rem[3] & ~wk_rem[2] & ~wk_rem[1] & ~wk_rem[0];
    assign issue_sel_1[7] = wk_rem[7] & ~wk_rem[6] & ~wk_rem[5] & ~wk_rem[4] & ~wk_rem[3] & ~wk_rem[2] & ~wk_rem[1] & ~wk_rem[0];

    // ---- Issue mux: pick entry fields for each issue bus ----
    wire [2:0] idx0 = issue_sel_0[0] ? 3'd0
                    : issue_sel_0[1] ? 3'd1
                    : issue_sel_0[2] ? 3'd2
                    : issue_sel_0[3] ? 3'd3
                    : issue_sel_0[4] ? 3'd4
                    : issue_sel_0[5] ? 3'd5
                    : issue_sel_0[6] ? 3'd6 : 3'd7;

    wire [2:0] idx1 = issue_sel_1[0] ? 3'd0
                    : issue_sel_1[1] ? 3'd1
                    : issue_sel_1[2] ? 3'd2
                    : issue_sel_1[3] ? 3'd3
                    : issue_sel_1[4] ? 3'd4
                    : issue_sel_1[5] ? 3'd5
                    : issue_sel_1[6] ? 3'd6 : 3'd7;

    assign issue_0_valid_o   = |issue_sel_0;
    assign issue_0_op_o      = rs_op     [idx0];
    assign issue_0_pj_o      = rs_pj     [idx0];
    assign issue_0_pk_o      = rs_pk     [idx0];
    assign issue_0_pd_o      = rs_pd     [idx0];
    assign issue_0_rob_idx_o = rs_rob_idx[idx0];
    assign issue_0_imm_o     = rs_imm    [idx0];

    assign issue_1_valid_o   = |issue_sel_1;
    assign issue_1_op_o      = rs_op     [idx1];
    assign issue_1_pj_o      = rs_pj     [idx1];
    assign issue_1_pk_o      = rs_pk     [idx1];
    assign issue_1_pd_o      = rs_pd     [idx1];
    assign issue_1_rob_idx_o = rs_rob_idx[idx1];
    assign issue_1_imm_o     = rs_imm    [idx1];

    // ---- Count wires (module-level, avoids local reg in always block) ----
    wire [3:0] rs_issue_cnt = {3'b0, |issue_sel_0} + {3'b0, |issue_sel_1};
    wire [3:0] rs_disp_cnt  = {3'b0, rs_disp_A_valid_i & |free_sel_A}
                             + {3'b0, rs_disp_B_valid_i & |free_sel_B};

    // ---- Synchronous updates ----
    integer k;
    always @(posedge clk_i) begin
        if (reset_i) begin
            rs_count <= 4'd0;
            for (k = 0; k < NUM_RS; k = k + 1) begin
                rs_busy  [k] <= 1'b0;
                rs_qj_rdy[k] <= 1'b0;
                rs_qk_rdy[k] <= 1'b0;
            end
        end else begin

            // ---- Latch source ready bits for all busy entries ----
            for (k = 0; k < NUM_RS; k = k + 1) begin
                if (rs_busy[k]) begin
                    if (!rs_qj_rdy[k] && prf_ready_vec_i[rs_pj[k]])
                        rs_qj_rdy[k] <= 1'b1;
                    if (!rs_qk_rdy[k] && prf_ready_vec_i[rs_pk[k]])
                        rs_qk_rdy[k] <= 1'b1;
                end
            end

            // ---- Clear issued RS entries ----
            for (k = 0; k < NUM_RS; k = k + 1) begin
                if (issue_sel_0[k] | issue_sel_1[k])
                    rs_busy[k] <= 1'b0;
            end

            // ---- Dispatch slot A into first free slot ----
            if (rs_disp_A_valid_i && |free_sel_A) begin
                for (k = 0; k < NUM_RS; k = k + 1) begin
                    if (free_sel_A[k]) begin
                        rs_busy   [k] <= 1'b1;
                        rs_op     [k] <= rs_disp_A_op_i;
                        rs_pj     [k] <= rs_disp_A_pj_i;
                        rs_pk     [k] <= rs_disp_A_pk_i;
                        // Source ready: PRF says ready AND not being allocated this cycle
                        rs_qj_rdy [k] <= prf_ready_vec_i[rs_disp_A_pj_i]
                                       & ~(alloc_en1_i & (alloc_addr1_i == rs_disp_A_pj_i))
                                       & ~(alloc_en2_i & (alloc_addr2_i == rs_disp_A_pj_i));
                        rs_qk_rdy [k] <= (prf_ready_vec_i[rs_disp_A_pk_i]
                                       & ~(alloc_en1_i & (alloc_addr1_i == rs_disp_A_pk_i))
                                       & ~(alloc_en2_i & (alloc_addr2_i == rs_disp_A_pk_i)))
                                       | is_addi_A;
                        rs_pd     [k] <= rs_disp_A_pd_i;
                        rs_rob_idx[k] <= rs_disp_A_rob_idx_i;
                        rs_imm    [k] <= rs_disp_A_imm_i;
                    end
                end
            end

            // ---- Dispatch slot B into second free slot ----
            if (rs_disp_B_valid_i && |free_sel_B) begin
                for (k = 0; k < NUM_RS; k = k + 1) begin
                    if (free_sel_B[k]) begin
                        rs_busy   [k] <= 1'b1;
                        rs_op     [k] <= rs_disp_B_op_i;
                        rs_pj     [k] <= rs_disp_B_pj_i;
                        rs_pk     [k] <= rs_disp_B_pk_i;
                        rs_qj_rdy [k] <= prf_ready_vec_i[rs_disp_B_pj_i]
                                       & ~(alloc_en1_i & (alloc_addr1_i == rs_disp_B_pj_i))
                                       & ~(alloc_en2_i & (alloc_addr2_i == rs_disp_B_pj_i));
                        rs_qk_rdy [k] <= (prf_ready_vec_i[rs_disp_B_pk_i]
                                       & ~(alloc_en1_i & (alloc_addr1_i == rs_disp_B_pk_i))
                                       & ~(alloc_en2_i & (alloc_addr2_i == rs_disp_B_pk_i)))
                                       | is_addi_B;
                        rs_pd     [k] <= rs_disp_B_pd_i;
                        rs_rob_idx[k] <= rs_disp_B_rob_idx_i;
                        rs_imm    [k] <= rs_disp_B_imm_i;
                    end
                end
            end

            // ---- Update count (use module-level wires, no local reg) ----
            rs_count <= rs_count + rs_disp_cnt - rs_issue_cnt;
        end
    end

endmodule
