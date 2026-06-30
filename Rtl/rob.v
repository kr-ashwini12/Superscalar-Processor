`timescale 1ns/1ps

module rob #(
    parameter ROB_SIZE    = 8,
    parameter PHYS_ADDR_W = 6,
    parameter ARCH_ADDR_W = 5,
    parameter ROB_ADDR_W  = 3   // log2(8)
) (
    input  wire                    clk_i,
    input  wire                    reset_i,

    //  Dispatch ports (from dispatch.v) 
    // Port names mirror dispatch.v output names
    input  wire                    alloc_A_i,
    input  wire                    rob_A_writes_rd_i,
    input  wire [ARCH_ADDR_W-1:0]  rob_A_arch_dest_i,
    input  wire [PHYS_ADDR_W-1:0]  rob_A_phys_dest_i,
    input  wire [PHYS_ADDR_W-1:0]  rob_A_old_phys_dest_i,

    input  wire                    alloc_B_i,
    input  wire                    rob_B_writes_rd_i,
    input  wire [ARCH_ADDR_W-1:0]  rob_B_arch_dest_i,
    input  wire [PHYS_ADDR_W-1:0]  rob_B_phys_dest_i,
    input  wire [PHYS_ADDR_W-1:0]  rob_B_old_phys_dest_i,

    //  Outputs to dispatch 
    output wire [ROB_ADDR_W-1:0]   rob_tail_o,
    output wire                    rob_full_o,

    //  Mark-ready ports (one per ALU) 
    input  wire                    mark_rdy_0_en_i,
    input  wire [ROB_ADDR_W-1:0]   mark_rdy_0_idx_i,
    input  wire                    mark_rdy_1_en_i,
    input  wire [ROB_ADDR_W-1:0]   mark_rdy_1_idx_i,

    //  Commit ports (to rename_unit) 
    output wire                    commit_A_valid_o,
    output wire [PHYS_ADDR_W-1:0]  commit_A_old_phys_o,
    output wire [ARCH_ADDR_W-1:0]  commit_A_arch_dest_o,
    output wire [PHYS_ADDR_W-1:0]  commit_A_phys_dest_o,

    output wire                    commit_B_valid_o,
    output wire [PHYS_ADDR_W-1:0]  commit_B_old_phys_o,
    output wire [ARCH_ADDR_W-1:0]  commit_B_arch_dest_o,
    output wire [PHYS_ADDR_W-1:0]  commit_B_phys_dest_o
);

    //  Entry arrays 
    reg                    rob_valid     [0:ROB_SIZE-1];
    reg                    rob_ready     [0:ROB_SIZE-1];
    reg                    rob_writes_rd [0:ROB_SIZE-1];
    reg [ARCH_ADDR_W-1:0]  rob_arch_dest [0:ROB_SIZE-1];
    reg [PHYS_ADDR_W-1:0]  rob_phys_dest [0:ROB_SIZE-1];
    reg [PHYS_ADDR_W-1:0]  rob_old_phys  [0:ROB_SIZE-1];

    //  Pointers 
    reg [ROB_ADDR_W-1:0]  head, tail;
    reg [ROB_ADDR_W:0]    count;    // one extra bit to hold value ROB_SIZE

    //  Status outputs 
    assign rob_tail_o = tail;
    assign rob_full_o = (count == ROB_SIZE[ROB_ADDR_W:0]);

    //  Commit logic (combinational) 
    wire [ROB_ADDR_W-1:0] head1 = (head + 1) % ROB_SIZE;

    wire head_committable  = rob_valid[head]  & rob_ready[head];
    // B only commits if A commits first (in-order)
    wire head1_committable = rob_valid[head1] & rob_ready[head1] & head_committable;

    assign commit_A_valid_o     = head_committable;
    assign commit_A_old_phys_o  = rob_old_phys [head];
    assign commit_A_arch_dest_o = rob_arch_dest [head];
    assign commit_A_phys_dest_o = rob_phys_dest [head];

    assign commit_B_valid_o     = head1_committable;
    assign commit_B_old_phys_o  = rob_old_phys [head1];
    assign commit_B_arch_dest_o = rob_arch_dest [head1];
    assign commit_B_phys_dest_o = rob_phys_dest [head1];

    //  Delta helpers 
    wire do_alloc_A  = alloc_A_i;
    wire do_alloc_B  = alloc_A_i & alloc_B_i;   // B only if A allocated
    wire do_commit_A = head_committable;
    wire do_commit_B = head1_committable;

    wire [1:0] num_allocs  = {1'b0, do_alloc_A}  + {1'b0, do_alloc_B};
    wire [1:0] num_commits = {1'b0, do_commit_A} + {1'b0, do_commit_B};

    //  Synchronous updates 
    integer i;
    always @(posedge clk_i) begin
        if (reset_i) begin
            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                rob_valid    [i] <= 1'b0;
                rob_ready    [i] <= 1'b0;
                rob_writes_rd[i] <= 1'b0;
                rob_arch_dest[i] <= {ARCH_ADDR_W{1'b0}};
                rob_phys_dest[i] <= {PHYS_ADDR_W{1'b0}};
                rob_old_phys [i] <= {PHYS_ADDR_W{1'b0}};
            end
            head  <= {ROB_ADDR_W{1'b0}};
            tail  <= {ROB_ADDR_W{1'b0}};
            count <= {(ROB_ADDR_W+1){1'b0}};
        end else begin

            // Allocate slot A at tail
            if (do_alloc_A) begin
                rob_valid    [tail] <= 1'b1;
                rob_ready    [tail] <= 1'b0;
                rob_writes_rd[tail] <= rob_A_writes_rd_i;
                rob_arch_dest[tail] <= rob_A_arch_dest_i;
                rob_phys_dest[tail] <= rob_A_phys_dest_i;
                rob_old_phys [tail] <= rob_A_old_phys_dest_i;
            end

            // Allocate slot B at tail+1 (only when A also allocates)
            if (do_alloc_B) begin
                rob_valid    [(tail+1) % ROB_SIZE] <= 1'b1;
                rob_ready    [(tail+1) % ROB_SIZE] <= 1'b0;
                rob_writes_rd[(tail+1) % ROB_SIZE] <= rob_B_writes_rd_i;
                rob_arch_dest[(tail+1) % ROB_SIZE] <= rob_B_arch_dest_i;
                rob_phys_dest[(tail+1) % ROB_SIZE] <= rob_B_phys_dest_i;
                rob_old_phys [(tail+1) % ROB_SIZE] <= rob_B_old_phys_dest_i;
            end

            // Mark-ready from ALU0
            if (mark_rdy_0_en_i)
                rob_ready[mark_rdy_0_idx_i] <= 1'b1;
            // Mark-ready from ALU1
            if (mark_rdy_1_en_i)
                rob_ready[mark_rdy_1_idx_i] <= 1'b1;

            // Commit: invalidate head entries
            if (do_commit_A) rob_valid[head]  <= 1'b0;
            if (do_commit_B) rob_valid[head1] <= 1'b0;

            // Advance pointers
            tail  <= (tail  + num_allocs)  % ROB_SIZE;
            head  <= (head  + num_commits) % ROB_SIZE;
            count <= count
                   + {{(ROB_ADDR_W-1){1'b0}}, num_allocs}
                   - {{(ROB_ADDR_W-1){1'b0}}, num_commits};
        end
    end

endmodule
