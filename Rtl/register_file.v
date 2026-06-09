// register_file.v
// Physical Register File: 48 registers, 32-bit wide
// 4 read ports, 2 write ports, 1 allocate port
// Write-before-read bypass, per-register ready bits
// Verilog-2001

module register_file #(
    parameter NUM_PHYS_REGS = 48,
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 6   // ceil(log2(48)) = 6
) (
    input  wire                  clk_i,
    input  wire                  reset_i,

    // ---------- Four Read Ports ----------
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

    // ---------- Two Write Ports ----------
    // Each write sets value AND sets ready = 1
    input  wire                  wr_en1_i,
    input  wire [ADDR_WIDTH-1:0] wr_addr1_i,
    input  wire [DATA_WIDTH-1:0] wr_data1_i,

    input  wire                  wr_en2_i,
    input  wire [ADDR_WIDTH-1:0] wr_addr2_i,
    input  wire [DATA_WIDTH-1:0] wr_data2_i,

    // ---------- Allocate Port ----------
    // Clears ready bit when a physical register is freshly allocated
    // (value not yet produced by execution unit)
    input  wire                  alloc_en_i,
    input  wire [ADDR_WIDTH-1:0] alloc_addr_i
);

    // -----------------------------------------------------------------
    // Storage arrays
    // -----------------------------------------------------------------
    reg [DATA_WIDTH-1:0] regs  [0:NUM_PHYS_REGS-1];
    reg                  ready [0:NUM_PHYS_REGS-1];

    integer i;

    // -----------------------------------------------------------------
    // Synchronous state update
    // -----------------------------------------------------------------
    always @(posedge clk_i) begin
        if (reset_i) begin
            // All registers reset to 0, ready = 1
            // (zero is a valid "committed" value at startup)
            for (i = 0; i < NUM_PHYS_REGS; i = i + 1) begin
                regs[i]  <= {DATA_WIDTH{1'b0}};
                ready[i] <= 1'b1;
            end
        end else begin
            // Write port 1: sets value AND ready
            if (wr_en1_i) begin
                regs[wr_addr1_i]  <= wr_data1_i;
                ready[wr_addr1_i] <= 1'b1;
            end

            // Write port 2: sets value AND ready
            if (wr_en2_i) begin
                regs[wr_addr2_i]  <= wr_data2_i;
                ready[wr_addr2_i] <= 1'b1;
            end

            // Allocate port: clears ready bit
            // Write wins over allocate if both target the same address
            // (by design this shouldn't happen, but write takes priority for safety)
            if (alloc_en_i &&
                !(wr_en1_i && (wr_addr1_i == alloc_addr_i)) &&
                !(wr_en2_i && (wr_addr2_i == alloc_addr_i))) begin
                ready[alloc_addr_i] <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------
    // Combinational reads with write-before-read bypass
    //
    // If a write port targets the same address as a read port in the
    // same cycle, return the new (incoming) data immediately.
    // Write port 1 takes priority over write port 2 if both match.
    // -----------------------------------------------------------------

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