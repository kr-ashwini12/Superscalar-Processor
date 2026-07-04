`timescale 1ns/1ps

module tb_pravah_top;

    reg clk, reset;
    always #5 clk = ~clk;   // 100 MHz

    pravah_top dut (
        .clk_i   (clk),
        .reset_i (reset)
    );

    // ---- Load program and release reset ----
    initial begin
        clk   = 0;
        reset = 1;
        // dot_product.hex must be in ModelSim's working directory
        $readmemh("dot_product.hex", dut.u_fetch.imem);
        repeat(4) @(posedge clk);
        reset = 0;
        #4000;
        $finish;
    end

    // ---- Commit monitor ----
    always @(posedge clk) begin
        if (!reset) begin
            if (dut.rob_commit_A_valid)
                $display("[%0t ns] COMMIT-A  head=%0d  arch=x%0d  phys=P%0d  val=%0d",
                    $time,
                    dut.u_rob.head,
                    dut.rob_commit_A_arch,
                    dut.rob_commit_A_phys,
                    dut.u_prf.regs[dut.rob_commit_A_phys]);

            if (dut.rob_commit_B_valid)
                $display("[%0t ns] COMMIT-B  head=%0d  arch=x%0d  phys=P%0d  val=%0d",
                    $time,
                    (dut.u_rob.head + 1) % 8,
                    dut.rob_commit_B_arch,
                    dut.rob_commit_B_phys,
                    dut.u_prf.regs[dut.rob_commit_B_phys]);
        end
    end

    // ---- Dispatch monitor ----
    always @(posedge clk) begin
        if (!reset) begin
            if (dut.disp_rs_A_valid)
                $display("[%0t ns] DISPATCH-A  op=%0d  pd=P%0d  rob=%0d",
                    $time, dut.disp_rs_A_op, dut.disp_rs_A_pd, dut.disp_rs_A_rob);
            if (dut.disp_rs_B_valid)
                $display("[%0t ns] DISPATCH-B  op=%0d  pd=P%0d  rob=%0d",
                    $time, dut.disp_rs_B_op, dut.disp_rs_B_pd, dut.disp_rs_B_rob);
        end
    end

    // ---- Issue monitor ----
    always @(posedge clk) begin
        if (!reset) begin
            if (dut.issue_0_valid)
                $display("[%0t ns] ISSUE-ALU0  op=%0d  pj=P%0d  pk=P%0d  pd=P%0d  rob=%0d",
                    $time, dut.issue_0_op, dut.issue_0_pj, dut.issue_0_pk,
                    dut.issue_0_pd, dut.issue_0_rob_idx);
            if (dut.issue_1_valid)
                $display("[%0t ns] ISSUE-ALU1  op=%0d  pj=P%0d  pk=P%0d  pd=P%0d  rob=%0d",
                    $time, dut.issue_1_op, dut.issue_1_pj, dut.issue_1_pk,
                    dut.issue_1_pd, dut.issue_1_rob_idx);
        end
    end

    // ---- Final verification ----
    // Read arch register k via rename_map → PRF
    task read_arch;
        input [4:0]  arch;
        output [31:0] val;
        begin
            val = dut.u_prf.regs[dut.u_rename.rename_map[arch]];
        end
    endtask

    integer fail_cnt;
    reg [31:0] v;

    initial begin
        fail_cnt = 0;
        #3500;   // wait for pipeline to drain

        $display("");
        $display("============================================");
        $display("  MILESTONE 3 — FINAL REGISTER CHECK");
        $display("============================================");

        read_arch(1,  v);
        $display("  x1  = %3d   (expected  2)  %0s", v, (v==32'd2)  ? "PASS" : "FAIL **");
        if (v != 32'd2)  fail_cnt = fail_cnt + 1;

        read_arch(2,  v);
        $display("  x2  = %3d   (expected  3)  %0s", v, (v==32'd3)  ? "PASS" : "FAIL **");
        if (v != 32'd3)  fail_cnt = fail_cnt + 1;

        read_arch(3,  v);
        $display("  x3  = %3d   (expected  5)  %0s", v, (v==32'd5)  ? "PASS" : "FAIL **");
        if (v != 32'd5)  fail_cnt = fail_cnt + 1;

        read_arch(4,  v);
        $display("  x4  = %3d   (expected  7)  %0s", v, (v==32'd7)  ? "PASS" : "FAIL **");
        if (v != 32'd7)  fail_cnt = fail_cnt + 1;

        read_arch(5,  v);
        $display("  x5  = %3d   (expected 34)  %0s", v, (v==32'd34) ? "PASS" : "FAIL **");
        if (v != 32'd34) fail_cnt = fail_cnt + 1;

        read_arch(6,  v);
        $display("  x6  = %3d   (expected 36)  %0s", v, (v==32'd36) ? "PASS" : "FAIL **");
        if (v != 32'd36) fail_cnt = fail_cnt + 1;

        read_arch(7,  v);
        $display("  x7  = %3d   (expected 17)  %0s", v, (v==32'd17) ? "PASS" : "FAIL **");
        if (v != 32'd17) fail_cnt = fail_cnt + 1;

        $display("============================================");
        if (fail_cnt == 0)
            $display("  *** ALL PASSED — MILESTONE 3 CLEARED ***");
        else
            $display("  *** %0d FAILED — check bug-hunt list ***", fail_cnt);
        $display("============================================");
        $finish;
    end

endmodule
