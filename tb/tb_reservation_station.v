`timescale 1ns / 1ps

module tb_reservation_station;

    localparam NUM_RS      = 4;
    localparam PHYS_ADDR_W = 6;
    localparam ROB_ADDR_W  = 3;
    localparam OP_WIDTH    = 4;

    localparam ADD = 4'd1;
    localparam SUB = 4'd2;
    localparam AND = 4'd3;
    localparam OR  = 4'd4;

    // -------------------------------------------------------
    // Clock & reset
    // -------------------------------------------------------
    reg clk   = 0;
    reg reset = 1;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // Dispatch port
    // -------------------------------------------------------
    reg                    disp_valid;
    reg [OP_WIDTH-1:0]     disp_op;
    reg [PHYS_ADDR_W-1:0]  disp_pj;
    reg [PHYS_ADDR_W-1:0]  disp_pk;
    reg [PHYS_ADDR_W-1:0]  disp_pd;
    reg [ROB_ADDR_W-1:0]   disp_rob_idx;
    wire                   disp_stall;

    // -------------------------------------------------------
    // Flattened snoop buses
    // -------------------------------------------------------
    wire [NUM_RS*PHYS_ADDR_W-1:0] snoop_pj_addr;   // output from DUT
    wire [NUM_RS*PHYS_ADDR_W-1:0] snoop_pk_addr;
    reg  [NUM_RS-1:0]              snoop_pj_ready;  // input to DUT
    reg  [NUM_RS-1:0]              snoop_pk_ready;

    // Fake PRF: 48-bit ready vector
    reg [47:0] prf_ready_bits;

    // Drive snoop ready bits combinationally
    integer s;
    always @* begin
        for (s = 0; s < NUM_RS; s = s + 1) begin
            snoop_pj_ready[s] = prf_ready_bits[ snoop_pj_addr[(s+1)*PHYS_ADDR_W-1 -: PHYS_ADDR_W] ];
            snoop_pk_ready[s] = prf_ready_bits[ snoop_pk_addr[(s+1)*PHYS_ADDR_W-1 -: PHYS_ADDR_W] ];
        end
    end

    // -------------------------------------------------------
    // Issue port
    // -------------------------------------------------------
    wire                   issue_valid;
    wire [OP_WIDTH-1:0]    issue_op;
    wire [PHYS_ADDR_W-1:0] issue_pj;
    wire [PHYS_ADDR_W-1:0] issue_pk;
    wire [PHYS_ADDR_W-1:0] issue_pd;
    wire [ROB_ADDR_W-1:0]  issue_rob_idx;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    reservation_station #(
        .NUM_RS      (NUM_RS),
        .PHYS_ADDR_W (PHYS_ADDR_W),
        .ROB_ADDR_W  (ROB_ADDR_W),
        .OP_WIDTH    (OP_WIDTH)
    ) dut (
        .clk_i            (clk),
        .reset_i          (reset),
        .disp_valid_i     (disp_valid),
        .disp_op_i        (disp_op),
        .disp_pj_i        (disp_pj),
        .disp_pk_i        (disp_pk),
        .disp_pd_i        (disp_pd),
        .disp_rob_idx_i   (disp_rob_idx),
        .disp_stall_o     (disp_stall),
        .snoop_pj_addr_o  (snoop_pj_addr),
        .snoop_pk_addr_o  (snoop_pk_addr),
        .snoop_pj_ready_i (snoop_pj_ready),
        .snoop_pk_ready_i (snoop_pk_ready),
        .issue_valid_o    (issue_valid),
        .issue_op_o       (issue_op),
        .issue_pj_o       (issue_pj),
        .issue_pk_o       (issue_pk),
        .issue_pd_o       (issue_pd),
        .issue_rob_idx_o  (issue_rob_idx)
    );

    // -------------------------------------------------------
    // Self-checking helpers
    // -------------------------------------------------------
    integer errors = 0;
    integer tests  = 0;

    task check_eq;
        input [31:0]  actual;
        input [31:0]  expected;
        input [255:0] label;
        begin
            tests = tests + 1;
            if (actual === expected)
                $display("  PASS  %s  (got %0d)", label, actual);
            else begin
                $display("  FAIL  %s  (expected %0d, got %0d)",
                         label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task banner;
        input [255:0] name;
        begin $display("\n--- %s ---", name); end
    endtask

    // -------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------
    initial begin
        $dumpfile("sim/waveforms/rs_sim.vcd");
        $dumpvars(0, tb_reservation_station);
    end

    // Timeout guard
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

    // -------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------
    initial begin
        disp_valid   = 0; disp_op = 0;
        disp_pj = 0; disp_pk = 0; disp_pd = 0; disp_rob_idx = 0;
        prf_ready_bits = 48'hFFFF_FFFF_FFFF;

        // ==================================================
        // T1 — Reset clears busy bits
        // ==================================================
        banner("T1: Reset clears busy bits");
        #20; reset = 0;
        @(posedge clk); #1;
        check_eq(issue_valid, 1'b0, "T1: issue_valid=0 after reset");
        check_eq(disp_stall,  1'b0, "T1: disp_stall=0 after reset");

        // ==================================================
        // T2 — Dispatch one instruction; sources ready → issues next cycle
        // ==================================================
        banner("T2: Dispatch with ready sources");
        @(posedge clk);
        disp_valid <= 1; disp_op <= ADD;
        disp_pj <= 6'd1; disp_pk <= 6'd2; disp_pd <= 6'd32; disp_rob_idx <= 3'd0;
        @(posedge clk);
        disp_valid <= 0;
        #1;
        check_eq(issue_valid, 1'b1,  "T2: issue_valid=1");
        check_eq(issue_op,    ADD,   "T2: issue_op=ADD");
        check_eq(issue_pj,    6'd1,  "T2: issue_pj=P1");
        check_eq(issue_pk,    6'd2,  "T2: issue_pk=P2");
        check_eq(issue_pd,    6'd32, "T2: issue_pd=P32");
        @(posedge clk); #1;
        check_eq(issue_valid, 1'b0, "T2: issue_valid=0 after RS cleared");

        // ==================================================
        // T3 — Dispatch with one not-ready source; stalls until ready
        // ==================================================
        banner("T3: Source not-ready; combinational wakeup when ready");
        prf_ready_bits[5] = 1'b0;
        @(posedge clk);
        disp_valid <= 1; disp_op <= SUB;
        disp_pj <= 6'd5; disp_pk <= 6'd6; disp_pd <= 6'd33; disp_rob_idx <= 3'd1;
        @(posedge clk);
        disp_valid <= 0;
        #1;
        check_eq(issue_valid, 1'b0, "T3: issue_valid=0 (P5 not ready)");
        // Make P5 ready — wakeup is combinational, no clock needed
        prf_ready_bits[5] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b1, "T3: issue_valid=1 after P5 ready");
        check_eq(issue_pj,    6'd5, "T3: issue_pj=P5");
        @(posedge clk); #1;
        check_eq(issue_valid, 1'b0, "T3: issue_valid=0 after RS cleared");

        // ==================================================
        // T4 — Fill all 4 RS entries; sources blocked
        // ==================================================
        banner("T4: Fill all 4 RS entries in order");
        prf_ready_bits[10] = 1'b0;
        prf_ready_bits[11] = 1'b0;
        prf_ready_bits[12] = 1'b0;
        prf_ready_bits[13] = 1'b0;

        @(posedge clk);
        disp_valid<=1; disp_op<=ADD; disp_pj<=6'd10; disp_pk<=6'd2; disp_pd<=6'd34; disp_rob_idx<=3'd2;
        @(posedge clk);
        disp_op<=ADD; disp_pj<=6'd11; disp_pk<=6'd2; disp_pd<=6'd35; disp_rob_idx<=3'd3;
        @(posedge clk);
        disp_op<=ADD; disp_pj<=6'd12; disp_pk<=6'd2; disp_pd<=6'd36; disp_rob_idx<=3'd4;
        @(posedge clk);
        disp_op<=ADD; disp_pj<=6'd13; disp_pk<=6'd2; disp_pd<=6'd37; disp_rob_idx<=3'd5;
        @(posedge clk);
        disp_valid <= 0;
        #1;
        check_eq(issue_valid, 1'b0, "T4: no issue (all sources blocked)");

        // ==================================================
        // T5 — Full RS array; dispatch stalls
        // ==================================================
        banner("T5: Full RS stalls dispatch");
        @(posedge clk);
        disp_valid<=1; disp_op<=ADD; disp_pj<=6'd2; disp_pk<=6'd2; disp_pd<=6'd38; disp_rob_idx<=3'd6;
        #1;
        check_eq(disp_stall, 1'b1, "T5: disp_stall=1 when array full");
        @(posedge clk);
        disp_valid <= 0;

        // ==================================================
        // T6 — One source becomes ready; that RS issues
        // ==================================================
        banner("T6: P12 becomes ready; RS[2] issues");
        prf_ready_bits[12] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b1, "T6: issue_valid=1 after P12 ready");
        check_eq(issue_pj,    6'd12, "T6: issue_pj=P12");
        @(posedge clk); #1;

        // ==================================================
        // T7 — Multiple wakeup-ready; lowest index wins, drains 1/cycle
        // ==================================================
        banner("T7: Multiple wakeup-ready; priority drain");
        prf_ready_bits[10] = 1'b1;
        prf_ready_bits[11] = 1'b1;
        prf_ready_bits[13] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b1, "T7: issue_valid with 3 ready");
        check_eq(issue_pj,    6'd10, "T7: RS[0]/P10 wins (lowest index)");
        @(posedge clk); #1;
        check_eq(issue_pj, 6'd11, "T7: RS[1]/P11 next");
        @(posedge clk); #1;
        check_eq(issue_pj, 6'd13, "T7: RS[3]/P13 last");
        @(posedge clk); #1;
        check_eq(issue_valid, 1'b0, "T7: all drained");

        // ==================================================
        // T8 — Freed RS[0] slot re-used by next dispatch
        // ==================================================
        banner("T8: Freed RS[0] re-used by next dispatch");
        prf_ready_bits[20] = 1'b0;
        @(posedge clk);
        disp_valid<=1; disp_op<=AND; disp_pj<=6'd20; disp_pk<=6'd3; disp_pd<=6'd40; disp_rob_idx<=3'd0;
        @(posedge clk);
        disp_valid <= 0;
        #1;
        check_eq(issue_valid, 1'b0, "T8: waiting for P20");
        prf_ready_bits[20] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b1, "T8: RS[0] wakes when P20 ready");
        check_eq(issue_pj,    6'd20, "T8: issue_pj=P20");
        @(posedge clk); #1;
        check_eq(issue_valid, 1'b0, "T8: RS[0] cleared");
        // Dispatch again; should land in RS[0] (lowest free)
        @(posedge clk);
        disp_valid<=1; disp_op<=OR; disp_pj<=6'd4; disp_pk<=6'd5; disp_pd<=6'd41; disp_rob_idx<=3'd1;
        @(posedge clk);
        disp_valid <= 0;
        #1;
        check_eq(issue_valid, 1'b1, "T8: new instr in RS[0] issues (P4,P5 ready)");
        check_eq(issue_op,    OR,   "T8: issue_op=OR");
        @(posedge clk); #1;

        // ==================================================
        // T9 — Reset mid-execution clears all state
        // ==================================================
        banner("T9: Reset mid-execution");
        prf_ready_bits[30] = 1'b0;
        prf_ready_bits[31] = 1'b0;
        @(posedge clk);
        disp_valid<=1; disp_op<=SUB; disp_pj<=6'd30; disp_pk<=6'd31; disp_pd<=6'd45; disp_rob_idx<=3'd2;
        @(posedge clk);
        disp_valid <= 0;
        #1;
        check_eq(issue_valid, 1'b0, "T9: instruction blocking");
        @(posedge clk);
        reset <= 1;
        @(posedge clk);
        reset <= 0;
        #1;
        check_eq(issue_valid, 1'b0, "T9: issue_valid=0 after reset");
        check_eq(disp_stall,  1'b0, "T9: disp_stall=0 after reset (all free)");
        prf_ready_bits[30] = 1'b1;
        prf_ready_bits[31] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b0, "T9: no ghost issue after reset");

        // ==================================================
        // Report
        // ==================================================
        @(posedge clk); #1;
        $display("\n====================================================");
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d / %0d)", tests, tests);
        else
            $display("FAILED %0d / %0d TESTS", errors, tests);
        $display("====================================================");
        $finish;
    end

endmodule
