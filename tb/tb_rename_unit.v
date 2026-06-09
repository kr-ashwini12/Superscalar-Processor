`timescale 1ns / 1ps

// tb_rename_unit.v
// Self-checking testbench for rename_unit.v
// Covers all 7 required test cases from Week 3 spec

module tb_rename_unit;

    // ----------------------------------------------------------------
    // DUT signal declarations
    // ----------------------------------------------------------------
    reg        clk, reset;

    reg        disp_valid;
    reg  [4:0] disp_rs1_arch;
    reg  [4:0] disp_rs2_arch;
    reg  [4:0] disp_rd_arch;
    reg        disp_writes_rd;

    wire [5:0] disp_rs1_phys;
    wire [5:0] disp_rs2_phys;
    wire [5:0] disp_rd_phys;
    wire [5:0] disp_rd_old_phys;
    wire       stall;

    reg        commit_valid;
    reg  [5:0] commit_old_phys;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    rename_unit #(
        .NUM_ARCH_REGS(32),
        .NUM_PHYS_REGS(48),
        .ARCH_ADDR_W(5),
        .PHYS_ADDR_W(6),
        .FREE_LIST_SZ(16)
    ) dut (
        .clk_i              (clk),
        .reset_i            (reset),
        .disp_valid_i       (disp_valid),
        .disp_rs1_arch_i    (disp_rs1_arch),
        .disp_rs2_arch_i    (disp_rs2_arch),
        .disp_rd_arch_i     (disp_rd_arch),
        .disp_writes_rd_i   (disp_writes_rd),
        .disp_rs1_phys_o    (disp_rs1_phys),
        .disp_rs2_phys_o    (disp_rs2_phys),
        .disp_rd_phys_o     (disp_rd_phys),
        .disp_rd_old_phys_o (disp_rd_old_phys),
        .stall_o            (stall),
        .commit_valid_i     (commit_valid),
        .commit_old_phys_i  (commit_old_phys)
    );

    always #5 clk = ~clk;

    integer errors;

    task check_val6;
        input [5:0]   actual;
        input [5:0]   expected;
        input [127:0] label;
        begin
            if (actual === expected)
                $display("  PASS [%s]: got %0d", label, actual);
            else begin
                $display("  FAIL [%s]: expected %0d, got %0d", label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_bit;
        input actual;
        input expected;
        input [127:0] label;
        begin
            if (actual === expected)
                $display("  PASS [%s]: got %b", label, actual);
            else begin
                $display("  FAIL [%s]: expected %b, got %b", label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    reg [5:0] cap_rd_phys, cap_rd_old_phys, cap_rs1_phys, cap_rs2_phys;

    initial begin
        clk           = 0;
        reset         = 1;
        errors        = 0;
        disp_valid    = 0;
        disp_rs1_arch = 0; disp_rs2_arch = 0;
        disp_rd_arch  = 0; disp_writes_rd = 0;
        commit_valid  = 0; commit_old_phys = 0;

        repeat(3) @(posedge clk);
        @(posedge clk); reset <= 0;
        repeat(2) @(posedge clk);

        // ============================================================
        // TEST 1: Reset state — identity map, free list = 16
        // ============================================================
        $display("\n--- Test 1: Reset state (identity map, free list = 16) ---");
        disp_valid     = 1;
        disp_rs1_arch  = 5'd1;
        disp_rs2_arch  = 5'd2;
        disp_rd_arch   = 5'd3;
        disp_writes_rd = 1;
        #1;
        check_val6(disp_rs1_phys,    6'd1,  "T1 rs1 identity map");
        check_val6(disp_rs2_phys,    6'd2,  "T1 rs2 identity map");
        check_val6(disp_rd_old_phys, 6'd3,  "T1 old phys = 3 (identity)");
        check_val6(disp_rd_phys,     6'd32, "T1 new phys = 32 (first free)");
        check_bit (stall,            1'b0,  "T1 no stall");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // TEST 2: Single dispatch writing R3 -> verify map updated
        // ============================================================
        $display("\n--- Test 2: Single dispatch writing R3 -> P32 ---");
        disp_valid     = 1;
        disp_rd_arch   = 5'd3;
        disp_writes_rd = 1;
        disp_rs1_arch  = 5'd0;
        disp_rs2_arch  = 5'd0;
        #1;
        check_val6(disp_rd_old_phys, 6'd32, "T2 old phys = 32 (T1 updated map)");
        check_val6(disp_rd_phys,     6'd33, "T2 new phys = 33");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // TEST 3: WAW dissolution — back-to-back writes to R5
        // ============================================================
        $display("\n--- Test 3: WAW dissolution - two writes to R5 get different phys ---");
        disp_valid     = 1;
        disp_rd_arch   = 5'd5;
        disp_writes_rd = 1;
        disp_rs1_arch  = 5'd0; disp_rs2_arch = 5'd0;
        #1;
        cap_rd_phys     = disp_rd_phys;
        cap_rd_old_phys = disp_rd_old_phys;
        @(posedge clk);   // first dispatch clocks in

        disp_rd_arch = 5'd5;
        #1;
        if (disp_rd_phys !== cap_rd_phys)
            $display("  PASS [T3 WAW dissolved]: first=%0d second=%0d (different)", cap_rd_phys, disp_rd_phys);
        else begin
            $display("  FAIL [T3 WAW dissolved]: both got same phys reg %0d", cap_rd_phys);
            errors = errors + 1;
        end
        check_val6(disp_rd_old_phys, cap_rd_phys, "T3 second old_phys = first new_phys");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // TEST 4: Dispatch then commit -> no stall
        // ============================================================
        $display("\n--- Test 4: Dispatch + commit -> free list stays healthy ---");
        disp_valid     = 1;
        disp_rd_arch   = 5'd10;
        disp_writes_rd = 1;
        disp_rs1_arch  = 5'd0; disp_rs2_arch = 5'd0;
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        commit_valid    = 1;
        commit_old_phys = 6'd5;
        @(posedge clk);
        commit_valid <= 0;
        @(posedge clk);

        disp_valid     = 1;
        disp_rd_arch   = 5'd15;
        disp_writes_rd = 1;
        disp_rs1_arch  = 5'd0; disp_rs2_arch = 5'd0;
        #1;
        check_bit(stall, 1'b0, "T4 no stall after commit returned reg");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // TEST 5: Non-writing instruction -> map unchanged
        // ============================================================
        $display("\n--- Test 5: Non-writing instruction -> no rename map change ---");
        disp_valid     = 1;
        disp_rs1_arch  = 5'd7;
        disp_rs2_arch  = 5'd8;
        disp_rd_arch   = 5'd7;
        disp_writes_rd = 0;
        #1;
        check_bit(stall, 1'b0, "T5 no stall for non-writing instr");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        disp_valid     = 1;
        disp_rd_arch   = 5'd7;
        disp_writes_rd = 1;
        disp_rs1_arch  = 5'd0; disp_rs2_arch = 5'd0;
        #1;
        check_val6(disp_rd_old_phys, 6'd7, "T5 map[7] still identity = 7");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // TEST 6: Free list exhaustion -> stall on 17th write
        // Reset first so free list is fresh (16 entries)
        // ============================================================
        $display("\n--- Test 6: Free list exhaustion -> stall after 16 writes ---");
        @(posedge clk); reset <= 1;
        repeat(3) @(posedge clk);
        reset <= 0;
        repeat(2) @(posedge clk);

        begin : exhaust_block
            integer k;
            for (k = 0; k < 16; k = k + 1) begin
                disp_valid     = 1;
                disp_rd_arch   = k[4:0];
                disp_writes_rd = 1;
                disp_rs1_arch  = 5'd0; disp_rs2_arch = 5'd0;
                @(posedge clk);
            end
            disp_valid <= 0;
            @(posedge clk);
        end

        // 17th dispatch — should stall
        disp_valid     = 1;
        disp_rd_arch   = 5'd16;
        disp_writes_rd = 1;
        disp_rs1_arch  = 5'd0; disp_rs2_arch = 5'd0;
        #1;
        check_bit(stall, 1'b1, "T6 stall when free list empty");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // TEST 7: Simultaneous dispatch + commit
        //
        // WHAT THIS TESTS:
        //   When fl_count = 0 (stall active), if commit and dispatch
        //   arrive in the same cycle, the RTL spec allows a one-cycle
        //   bubble (stall stays 1 that cycle because fl_count is 0 at
        //   the START of the cycle — commit's +1 hasn't registered yet).
        //   BUT on the NEXT cycle fl_count = 1, so stall goes 0 and
        //   dispatch proceeds.
        //
        // We test: after simultaneous dispatch+commit, the NEXT cycle
        // allows a free dispatch (stall = 0), proving fl_count recovered.
        // ============================================================
        $display("\n--- Test 7: Simultaneous dispatch + commit -> fl_count recovers ---");

        // Cycle A: send both dispatch and commit together
        // fl_count = 0 now, so stall = 1 this cycle (expected per spec)
        // commit pushes P32 back; dispatch is blocked by stall this cycle
        @(posedge clk);
        disp_valid      <= 1;
        disp_rd_arch    <= 5'd20;
        disp_writes_rd  <= 1;
        disp_rs1_arch   <= 5'd0;
        disp_rs2_arch   <= 5'd0;
        commit_valid    <= 1;
        commit_old_phys <= 6'd32;   // return P32 to free list
        @(posedge clk);
        // Cycle B: commit has registered, fl_count = 1, stall should now = 0
        commit_valid <= 0;
        #1;
        check_bit(stall, 1'b0, "T7 stall clears after commit registers");

        // Cycle B: let this dispatch go through (stall=0 now)
        // disp_valid still asserted from above
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);
        #1;
        // fl_count back to 0 -> stall returns
        disp_valid     = 1;
        disp_rd_arch   = 5'd21;
        disp_writes_rd = 1;
        #1;
        check_bit(stall, 1'b1, "T7 stall returns after dispatch consumed last free reg");
        @(posedge clk);
        disp_valid <= 0;
        @(posedge clk);

        // ============================================================
        // Summary
        // ============================================================
        $display("\n==============================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED %0d TEST(S)", errors);
        $display("==============================\n");

        $finish;
    end

endmodule
