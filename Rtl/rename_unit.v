// rename_unit.v
// Register Rename Unit: Rename Map + Free List
// Single-issue (one instruction per cycle), Week 3
// Verilog-2001

module rename_unit #(
    parameter NUM_ARCH_REGS = 32,
    parameter NUM_PHYS_REGS = 48,
    parameter ARCH_ADDR_W   = 5,                             // log2(32)
    parameter PHYS_ADDR_W   = 6,                             // log2(48)
    parameter FREE_LIST_SZ  = NUM_PHYS_REGS - NUM_ARCH_REGS  // 16
) (
    input  wire                   clk_i,
    input  wire                   reset_i,

    // ---------- Dispatch Port ----------
    // Frontend presents one instruction per cycle
    input  wire                   disp_valid_i,       // instruction present
    input  wire [ARCH_ADDR_W-1:0] disp_rs1_arch_i,   // source 1 arch reg
    input  wire [ARCH_ADDR_W-1:0] disp_rs2_arch_i,   // source 2 arch reg
    input  wire [ARCH_ADDR_W-1:0] disp_rd_arch_i,    // dest arch reg
    input  wire                   disp_writes_rd_i,   // 0 = no dest (sw/beq)

    output wire [PHYS_ADDR_W-1:0] disp_rs1_phys_o,   // source 1 physical reg
    output wire [PHYS_ADDR_W-1:0] disp_rs2_phys_o,   // source 2 physical reg
    output wire [PHYS_ADDR_W-1:0] disp_rd_phys_o,    // dest physical reg (new)
    output wire [PHYS_ADDR_W-1:0] disp_rd_old_phys_o,// dest physical reg (old, for ROB rollback)
    output wire                   stall_o,            // 1 = free list empty, front-end must stall

    // ---------- Commit Port ----------
    // ROB returns old physical dest when an instruction commits
    input  wire                   commit_valid_i,
    input  wire [PHYS_ADDR_W-1:0] commit_old_phys_i  // pushed back onto free list
);

    // -----------------------------------------------------------------
    // Internal storage
    // -----------------------------------------------------------------

    // Rename map: arch reg -> physical reg
    reg [PHYS_ADDR_W-1:0] rename_map [0:NUM_ARCH_REGS-1];

    // Free list: circular FIFO of available physical registers
    reg [PHYS_ADDR_W-1:0] free_list [0:FREE_LIST_SZ-1];

    // Free list head/tail pointers (one extra bit to tell empty from full)
    reg [$clog2(FREE_LIST_SZ):0] fl_head;
    reg [$clog2(FREE_LIST_SZ):0] fl_tail;
    reg [$clog2(FREE_LIST_SZ):0] fl_count;

    integer i;

    // -----------------------------------------------------------------
    // Helper wires
    // -----------------------------------------------------------------

    // stall when we need a phys reg but none are available
    assign stall_o = disp_valid_i & disp_writes_rd_i & (fl_count == 0);

    // actual dispatch happens only when valid, writes a dest, and not stalled
    wire do_dispatch = disp_valid_i & disp_writes_rd_i & ~stall_o;
    wire do_commit   = commit_valid_i;

    // -----------------------------------------------------------------
    // Combinational outputs (all based on current rename_map / free_list)
    // -----------------------------------------------------------------

    // Source lookups: just index into rename map
    assign disp_rs1_phys_o     = rename_map[disp_rs1_arch_i];
    assign disp_rs2_phys_o     = rename_map[disp_rs2_arch_i];

    // Old dest: current mapping BEFORE this dispatch overwrites it
    // ROB stores this for rollback
    assign disp_rd_old_phys_o  = rename_map[disp_rd_arch_i];

    // New dest: head of free list (what we will assign on clock edge)
    assign disp_rd_phys_o      = free_list[fl_head[$clog2(FREE_LIST_SZ)-1:0]];

    // -----------------------------------------------------------------
    // Synchronous state update
    // -----------------------------------------------------------------
    always @(posedge clk_i) begin
        if (reset_i) begin
            // Identity map: arch reg R lives in physical reg R
            for (i = 0; i < NUM_ARCH_REGS; i = i + 1)
                rename_map[i] <= i[PHYS_ADDR_W-1:0];

            // Free list holds physical regs 32..47 (the extras)
            for (i = 0; i < FREE_LIST_SZ; i = i + 1)
                free_list[i] <= NUM_ARCH_REGS[PHYS_ADDR_W-1:0] + i[PHYS_ADDR_W-1:0];

            fl_head  <= 0;
            fl_tail  <= 0;
            fl_count <= FREE_LIST_SZ[$clog2(FREE_LIST_SZ):0];

        end else begin

            // Dispatch: pop a physical reg from free list head,
            //           update rename map for destination
            if (do_dispatch) begin
                rename_map[disp_rd_arch_i] <=
                    free_list[fl_head[$clog2(FREE_LIST_SZ)-1:0]];
                fl_head <= (fl_head + 1) % FREE_LIST_SZ;
            end

            // Commit: push old physical reg back onto free list tail
            if (do_commit) begin
                free_list[fl_tail[$clog2(FREE_LIST_SZ)-1:0]] <= commit_old_phys_i;
                fl_tail <= (fl_tail + 1) % FREE_LIST_SZ;
            end

            // Update count: dispatch removes one, commit adds one
            // If both happen in the same cycle, count is unchanged
            fl_count <= fl_count
                        - (do_dispatch ? 1 : 0)
                        + (do_commit   ? 1 : 0);
        end
    end

endmodule
