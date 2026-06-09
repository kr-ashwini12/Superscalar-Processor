`timescale 1ns / 1ps

// tb_register_file.v
// Self-checking testbench for register_file.v
// Covers all 7 required test cases from Week 3 spec

module tb_register_file;

    // ----------------------------------------------------------------
    // DUT signal declarations
    // ----------------------------------------------------------------
    reg         clk, reset;

    reg  [5:0]  rd_addr1, rd_addr2, rd_addr3, rd_addr4;
    wire [31:0] rd_data1, rd_data2, rd_data3, rd_data4;
    wire        rd_ready1, rd_ready2, rd_ready3, rd_ready4;

    reg         wr_en1;
    reg  [5:0]  wr_addr1;
    reg  [31:0] wr_data1;

    reg         wr_en2;
    reg  [5:0]  wr_addr2;
    reg  [31:0] wr_data2;

    reg         alloc_en;
    reg  [5:0]  alloc_addr;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    register_file #(
        .NUM_PHYS_REGS(48),
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) dut (
        .clk_i       (clk),
        .reset_i     (reset),

        .rd_addr1_i  (rd_addr1),  .rd_data1_o (rd_data1),  .rd_ready1_o (rd_ready1),
        .rd_addr2_i  (rd_addr2),  .rd_data2_o (rd_data2),  .rd_ready2_o (rd_ready2),
        .rd_addr3_i  (rd_addr3),  .rd_data3_o (rd_data3),  .rd_ready3_o (rd_ready3),
        .rd_addr4_i  (rd_addr4),  .rd_data4_o (rd_data4),  .rd_ready4_o (rd_ready4),

        .wr_en1_i    (wr_en1),    .wr_addr1_i (wr_addr1),  .wr_data1_i  (wr_data1),
        .wr_en2_i    (wr_en2),    .wr_addr2_i (wr_addr2),  .wr_data2_i  (wr_data2),

        .alloc_en_i  (alloc_en),  .alloc_addr_i(alloc_addr)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // ----------------------------------------------------------------
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Error counter and helper tasks
    // ----------------------------------------------------------------
    integer errors;

    task check_val;
        input [31:0] actual;
        input [31:0] expected;
        input [127:0] label;
        begin
            if (actual === expected)
                $display("  PASS [%s]: got 0x%08h", label, actual);
            else begin
                $display("  FAIL [%s]: expected 0x%08h, got 0x%08h", label, expected, actual);
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

    // ----------------------------------------------------------------
    // Test stimulus
    // ----------------------------------------------------------------
    initial begin
        // Initialise
        clk       = 0;
        reset     = 1;
        errors    = 0;
        wr_en1    = 0; wr_addr1 = 0; wr_data1 = 0;
        wr_en2    = 0; wr_addr2 = 0; wr_data2 = 0;
        alloc_en  = 0; alloc_addr = 0;
        rd_addr1  = 0; rd_addr2 = 0;
        rd_addr3  = 0; rd_addr4 = 0;

        // Hold reset for 3 cycles
        repeat (3) @(posedge clk);
        @(posedge clk); reset <= 0;
        @(posedge clk);  // one idle cycle after reset de-asserts

        // ============================================================
        // TEST 1: Read after reset -> value = 0, ready = 1
        // ============================================================
        $display("\n--- Test 1: Read after reset ---");
        rd_addr1 = 6'd5;
        #1;
        check_val(rd_data1,  32'h0,  "T1 data=0 after reset");
        check_bit(rd_ready1, 1'b1,   "T1 ready=1 after reset");

        // ============================================================
        // TEST 2: Single write then read
        // ============================================================
        $display("\n--- Test 2: Single write then read ---");
        @(posedge clk);
        wr_en1 <= 1; wr_addr1 <= 6'd5; wr_data1 <= 32'hDEAD_BEEF;
        @(posedge clk);
        wr_en1 <= 0;
        #1;
        rd_addr1 = 6'd5;
        #1;
        check_val(rd_data1, 32'hDEAD_BEEF, "T2 write-then-read value");
        check_bit(rd_ready1, 1'b1,          "T2 ready=1 after write");

        // ============================================================
        // TEST 3: Write-before-read bypass (same cycle, same address)
        // ============================================================
        $display("\n--- Test 3: Write-before-read bypass ---");
        @(posedge clk);
        wr_en1   <= 1; wr_addr1 <= 6'd10; wr_data1 <= 32'hCAFE_BABE;
        rd_addr2  = 6'd10;   // combinational read address set NOW
        #1;                  // let combinational bypass settle
        check_val(rd_data2,  32'hCAFE_BABE, "T3 bypass data");
        check_bit(rd_ready2, 1'b1,           "T3 bypass ready=1");
        @(posedge clk);
        wr_en1 <= 0;

        // ============================================================
        // TEST 4: Two simultaneous writes to DIFFERENT addresses
        // ============================================================
        $display("\n--- Test 4: Simultaneous writes to different addresses ---");
        @(posedge clk);
        wr_en1 <= 1; wr_addr1 <= 6'd20; wr_data1 <= 32'h1111_1111;
        wr_en2 <= 1; wr_addr2 <= 6'd21; wr_data2 <= 32'h2222_2222;
        @(posedge clk);
        wr_en1 <= 0; wr_en2 <= 0;
        #1;
        rd_addr1 = 6'd20; rd_addr2 = 6'd21;
        #1;
        check_val(rd_data1, 32'h1111_1111, "T4 wr_port1 value");
        check_val(rd_data2, 32'h2222_2222, "T4 wr_port2 value");

        // ============================================================
        // TEST 5: Four simultaneous reads from different addresses
        // ============================================================
        $display("\n--- Test 5: Four simultaneous reads ---");
        // Addresses 5, 10, 20, 21 were written in Tests 2, 3, 4
        rd_addr1 = 6'd5;
        rd_addr2 = 6'd10;
        rd_addr3 = 6'd20;
        rd_addr4 = 6'd21;
        #1;
        check_val(rd_data1, 32'hDEAD_BEEF, "T5 rd_port1 addr5");
        check_val(rd_data2, 32'hCAFE_BABE, "T5 rd_port2 addr10");
        check_val(rd_data3, 32'h1111_1111, "T5 rd_port3 addr20");
        check_val(rd_data4, 32'h2222_2222, "T5 rd_port4 addr21");

        // ============================================================
        // TEST 6: Allocate clears the ready bit
        // ============================================================
        $display("\n--- Test 6: Allocate clears ready bit ---");
        // addr5 currently has ready=1 (from Test 2 write)
        @(posedge clk);
        alloc_en <= 1; alloc_addr <= 6'd5;
        @(posedge clk);
        alloc_en <= 0;
        #1;
        rd_addr1 = 6'd5;
        #1;
        check_bit(rd_ready1, 1'b0, "T6 alloc clears ready");
        // Value is unchanged but ready = 0
        check_val(rd_data1, 32'hDEAD_BEEF, "T6 alloc preserves data");

        // ============================================================
        // TEST 7: Write after allocate sets ready bit back
        // ============================================================
        $display("\n--- Test 7: Write after allocate sets ready bit ---");
        @(posedge clk);
        wr_en1 <= 1; wr_addr1 <= 6'd5; wr_data1 <= 32'h0000_0099;
        @(posedge clk);
        wr_en1 <= 0;
        #1;
        rd_addr1 = 6'd5;
        #1;
        check_bit(rd_ready1, 1'b1,       "T7 write restores ready");
        check_val(rd_data1,  32'h0000_0099, "T7 write updates data");

        // ============================================================
        // BONUS: alloc and write to same address in same cycle -> write wins
        // ============================================================
        $display("\n--- Bonus: alloc + write same address, write wins ---");
        @(posedge clk);
        wr_en1    <= 1; wr_addr1    <= 6'd30; wr_data1  <= 32'hAAAA_BBBB;
        alloc_en  <= 1; alloc_addr  <= 6'd30;
        @(posedge clk);
        wr_en1 <= 0; alloc_en <= 0;
        #1;
        rd_addr1 = 6'd30;
        #1;
        check_bit(rd_ready1, 1'b1,         "Bonus wr wins: ready=1");
        check_val(rd_data1,  32'hAAAA_BBBB, "Bonus wr wins: data");

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
