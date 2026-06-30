// =============================================================================
// register_file.v  —  Physical Register File  (PRAVAH Week 6)
//
// YOUR Week 3/5 file with ONE change:
//   Added alloc_en2_i / alloc_addr2_i  (second allocate port for 2-wide dispatch)
//
// Everything else identical: NUM_PHYS_REGS=48, 4 read ports, 2 write ports,
// write-before-read bypass, all regs start ready=1 at reset.
// Verilog-2001 compatible.
// =============================================================================
`timescale 1ns/1ps

module register_file #(
    parameter NUM_PHYS_REGS = 48,
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 6
) (
    input  wire                  clk_i,
    input  wire                  reset_i,

    // ---------- Four Read Ports (unchanged) ----------
    input  wire [ADDR_WIDTH-1:0] rd_addr1_i,
    input  wire [ADDR_WIDTH-1:0] rd_addr2_i,
    input  wire [ADDR_WIDTH-1:0] rd_addr3_i,
    input  wire [ADDR_WIDTH-1:0] rd_addr4_i,

    output wire [DATA_WIDTH-1:0] rd_data1_o,
    output wire [DATA_WIDTH-1:0] rd_data2_o,
    output wire [DATA_WIDTH-1:0] rd_data3_o,
    output wire [DATA_WIDTH-1:0] rd_data4_o,

    output wire                  rd_ready1_o,
    output wire                  rd_ready2_o,
    output wire                  rd_ready3_o,
    output wire                  rd_ready4_o,

    // ---------- Two Write Ports (unchanged) ----------
    input  wire                  wr_en1_i,
    input  wire [ADDR_WIDTH-1:0] wr_addr1_i,
    input  wire [DATA_WIDTH-1:0] wr_data1_i,

    input  wire                  wr_en2_i,
    input  wire [ADDR_WIDTH-1:0] wr_addr2_i,
    input  wire [DATA_WIDTH-1:0] wr_data2_i,

    // ---------- Allocate Port 1 (original, for dispatch slot A) ----------
    input  wire                  alloc_en1_i,
    input  wire [ADDR_WIDTH-1:0] alloc_addr1_i,

    // ---------- Allocate Port 2 (NEW — for dispatch slot B) ----------
    input  wire                  alloc_en2_i,
    input  wire [ADDR_WIDTH-1:0] alloc_addr2_i,

    // ---------- Full ready vector (for RS snooping) ----------
    // 48 bits, one per phys reg — RS reads this combinationally
    output wire [NUM_PHYS_REGS-1:0] ready_vec_o
);

    // ---- Storage ----
    reg [DATA_WIDTH-1:0] regs  [0:NUM_PHYS_REGS-1];
    reg                  ready [0:NUM_PHYS_REGS-1];

    integer i;

    // ---- Ready vector ----
    genvar g;
    generate
        for (g = 0; g < NUM_PHYS_REGS; g = g + 1) begin : rdy_vec
            assign ready_vec_o[g] = ready[g];
        end
    endgenerate

    // ---- Synchronous updates ----
    always @(posedge clk_i) begin
        if (reset_i) begin
            for (i = 0; i < NUM_PHYS_REGS; i = i + 1) begin
                regs [i] <= {DATA_WIDTH{1'b0}};
                ready[i] <= 1'b1;    // all regs valid at reset
            end
        end else begin
            // Write port 1
            if (wr_en1_i) begin
                regs [wr_addr1_i] <= wr_data1_i;
                ready[wr_addr1_i] <= 1'b1;
            end
            // Write port 2
            if (wr_en2_i) begin
                regs [wr_addr2_i] <= wr_data2_i;
                ready[wr_addr2_i] <= 1'b1;
            end
            // Allocate port 1: clear ready (write wins if same addr)
            if (alloc_en1_i
                && !(wr_en1_i && (wr_addr1_i == alloc_addr1_i))
                && !(wr_en2_i && (wr_addr2_i == alloc_addr1_i))) begin
                ready[alloc_addr1_i] <= 1'b0;
            end
            // Allocate port 2: clear ready (write wins if same addr)
            if (alloc_en2_i
                && !(wr_en1_i && (wr_addr1_i == alloc_addr2_i))
                && !(wr_en2_i && (wr_addr2_i == alloc_addr2_i))
                && !(alloc_en1_i && (alloc_addr1_i == alloc_addr2_i))) begin
                ready[alloc_addr2_i] <= 1'b0;
            end
        end
    end

    // ---- Combinational reads with write-before-read bypass (unchanged logic) ----
    // Read port 1
    assign rd_data1_o =
        (wr_en1_i && (wr_addr1_i == rd_addr1_i)) ? wr_data1_i :
        (wr_en2_i && (wr_addr2_i == rd_addr1_i)) ? wr_data2_i :
        regs[rd_addr1_i];
    assign rd_ready1_o =
        (wr_en1_i && (wr_addr1_i == rd_addr1_i)) ? 1'b1 :
        (wr_en2_i && (wr_addr2_i == rd_addr1_i)) ? 1'b1 :
        ready[rd_addr1_i];

    // Read port 2
    assign rd_data2_o =
        (wr_en1_i && (wr_addr1_i == rd_addr2_i)) ? wr_data1_i :
        (wr_en2_i && (wr_addr2_i == rd_addr2_i)) ? wr_data2_i :
        regs[rd_addr2_i];
    assign rd_ready2_o =
        (wr_en1_i && (wr_addr1_i == rd_addr2_i)) ? 1'b1 :
        (wr_en2_i && (wr_addr2_i == rd_addr2_i)) ? 1'b1 :
        ready[rd_addr2_i];

    // Read port 3
    assign rd_data3_o =
        (wr_en1_i && (wr_addr1_i == rd_addr3_i)) ? wr_data1_i :
        (wr_en2_i && (wr_addr2_i == rd_addr3_i)) ? wr_data2_i :
        regs[rd_addr3_i];
    assign rd_ready3_o =
        (wr_en1_i && (wr_addr1_i == rd_addr3_i)) ? 1'b1 :
        (wr_en2_i && (wr_addr2_i == rd_addr3_i)) ? 1'b1 :
        ready[rd_addr3_i];

    // Read port 4
    assign rd_data4_o =
        (wr_en1_i && (wr_addr1_i == rd_addr4_i)) ? wr_data1_i :
        (wr_en2_i && (wr_addr2_i == rd_addr4_i)) ? wr_data2_i :
        regs[rd_addr4_i];
    assign rd_ready4_o =
        (wr_en1_i && (wr_addr1_i == rd_addr4_i)) ? 1'b1 :
        (wr_en2_i && (wr_addr2_i == rd_addr4_i)) ? 1'b1 :
        ready[rd_addr4_i];

endmodule
