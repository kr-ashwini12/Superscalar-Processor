`timescale 1ns/1ps

module tb_pravah_perf;

    reg clk, reset;
    always #5 clk = ~clk;

    pravah_top dut (.clk_i(clk), .reset_i(reset));

    // =========================================================================
    // Performance counters
    // =========================================================================
    integer cycle_count;
    integer commit_count;
    integer first_commit_cycle;
    integer last_commit_cycle;
    reg     count_done;    // freeze counter once we hit target

    always @(posedge clk) begin
        if (!reset)
            cycle_count <= cycle_count + 1;
    end

    always @(posedge clk) begin
        if (!reset && !count_done) begin
            // Single expression: counts both slots atomically
            commit_count <= commit_count
                          + (dut.rob_commit_A_valid ? 1 : 0)
                          + (dut.rob_commit_B_valid ? 1 : 0);

            if (dut.rob_commit_A_valid || dut.rob_commit_B_valid) begin
                last_commit_cycle <= cycle_count;
                if (first_commit_cycle < 0)
                    first_commit_cycle <= cycle_count;
            end
        end
    end

    // =========================================================================
    // Task: reset counters
    // =========================================================================
    task reset_counters;
        begin
            cycle_count        = 0;
            commit_count       = 0;
            first_commit_cycle = -1;
            last_commit_cycle  = 0;
            count_done         = 0;
        end
    endtask

    // =========================================================================
    // Task: run one benchmark
    // =========================================================================
    task run_benchmark;
        input [255:0] name;
        input [255:0] hex_file;
        input [31:0]  expected_x16;
        input integer num_instr;
        integer       timeout_ctr;
        integer       ss_cycles;
        real          ee_ipc, ss_ipc;
        reg [31:0]    got_x16;
        begin
            $display("\n========================================");
            $display("  BENCHMARK: %0s", name);
            $display("========================================");

            $readmemh(hex_file, dut.u_fetch.imem);

            reset_counters;
            reset = 1;
            repeat(4) @(posedge clk);
            reset = 0;

            // Wait until exactly num_instr committed
            timeout_ctr = 0;
            while (commit_count < num_instr && timeout_ctr < 400) begin
                @(posedge clk); #1;
                timeout_ctr = timeout_ctr + 1;
            end
            // Freeze the counter NOW before any extra commits tick in
            count_done = 1;
            // Clamp to num_instr in case of overshoot by 1 dual-commit
            if (commit_count > num_instr) begin
                last_commit_cycle = last_commit_cycle - 1;
                commit_count = num_instr;
            end
            @(posedge clk); #1;

            if (timeout_ctr >= 400)
                $display("  WARNING: timeout after 400 cycles");

            // Read final arch x16
            got_x16 = dut.u_prf.regs[dut.u_rename.rename_map[16]];

            // IPC calculations
            ee_ipc = (last_commit_cycle > 0)
                   ? (num_instr * 1.0 / last_commit_cycle) : 0.0;

            if (first_commit_cycle >= 0 && last_commit_cycle >= first_commit_cycle)
                ss_cycles = last_commit_cycle - first_commit_cycle + 1;
            else
                ss_cycles = 1;
            ss_ipc = num_instr * 1.0 / ss_cycles;

            $display("  Instructions committed : %0d  (expected %0d)",
                     commit_count, num_instr);
            $display("  First commit cycle     : %0d", first_commit_cycle);
            $display("  Last  commit cycle     : %0d", last_commit_cycle);
            $display("  Steady-state cycles    : %0d", ss_cycles);
            $display("  End-to-end  IPC        : %.4f", ee_ipc);
            $display("  Steady-state IPC       : %.4f", ss_ipc);
            $display("  x16 final value        : %0d  (expected %0d)  %0s",
                     got_x16, expected_x16,
                     (got_x16 === expected_x16) ? "PASS" : "FAIL **");
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        clk   = 0;
        reset = 1;
        reset_counters;

        $display("\n############################################");
        $display("  PRAVAH WEEK 7 — IPC MEASUREMENT");
        $display("############################################");

        run_benchmark("Independent (no deps)", "bench_independent.hex", 16,    16);
        run_benchmark("Chain (all deps)",      "bench_chain.hex",       32768, 16);
        run_benchmark("Mixed (partial ILP)",   "bench_mixed.hex",       290,   16);

        $display("\n========================================");
        $display("  SUMMARY");
        $display("  Expected ranges:");
        $display("    Independent : ss ~ 1.7 - 2.0");
        $display("    Chain       : ss ~ 0.9 - 1.1");
        $display("    Mixed       : ss ~ 1.2 - 1.6");
        $display("========================================");
        $finish;
    end

endmodule
