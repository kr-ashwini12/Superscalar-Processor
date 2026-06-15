`timescale 1ns / 1ps

module reservation_station #(
    parameter NUM_RS       = 4,
    parameter PHYS_ADDR_W  = 6,
    parameter ROB_ADDR_W   = 3,
    parameter OP_WIDTH     = 4
) (
    input  wire clk_i,
    input  wire reset_i,

    // Dispatch port
    input  wire                              disp_valid_i,
    input  wire [OP_WIDTH-1:0]               disp_op_i,
    input  wire [PHYS_ADDR_W-1:0]            disp_pj_i,
    input  wire [PHYS_ADDR_W-1:0]            disp_pk_i,
    input  wire [PHYS_ADDR_W-1:0]            disp_pd_i,
    input  wire [ROB_ADDR_W-1:0]             disp_rob_idx_i,
    output wire                              disp_stall_o,

    // PRF ready-bit snoop (flattened arrays)
    output wire [NUM_RS*PHYS_ADDR_W-1:0]     snoop_pj_addr_o,
    output wire [NUM_RS*PHYS_ADDR_W-1:0]     snoop_pk_addr_o,
    input  wire [NUM_RS-1:0]                 snoop_pj_ready_i,
    input  wire [NUM_RS-1:0]                 snoop_pk_ready_i,

    // Issue port
    output wire                              issue_valid_o,
    output wire [OP_WIDTH-1:0]               issue_op_o,
    output wire [PHYS_ADDR_W-1:0]            issue_pj_o,
    output wire [PHYS_ADDR_W-1:0]            issue_pk_o,
    output wire [PHYS_ADDR_W-1:0]            issue_pd_o,
    output wire [ROB_ADDR_W-1:0]             issue_rob_idx_o
);

    // ----------------------------------------------------------
    // Per-RS state registers
    // ----------------------------------------------------------
    reg                   rs_busy    [0:NUM_RS-1];
    reg [OP_WIDTH-1:0]    rs_op      [0:NUM_RS-1];
    reg [PHYS_ADDR_W-1:0] rs_pj      [0:NUM_RS-1];
    reg [PHYS_ADDR_W-1:0] rs_pk      [0:NUM_RS-1];
    reg [PHYS_ADDR_W-1:0] rs_pd      [0:NUM_RS-1];
    reg [ROB_ADDR_W-1:0]  rs_rob_idx [0:NUM_RS-1];

    // ----------------------------------------------------------
    // Combinational control vectors
    // ----------------------------------------------------------
    wire [NUM_RS-1:0] rs_wakeup_ready;
    wire [NUM_RS-1:0] rs_free;
    wire [NUM_RS-1:0] issue_select;
    wire [NUM_RS-1:0] dispatch_select;

    integer i;

    // ----------------------------------------------------------
    // Step 1: Drive flattened snoop address outputs
    // ----------------------------------------------------------
    genvar g;
    generate
        for (g = 0; g < NUM_RS; g = g + 1) begin : snoop_gen
            assign snoop_pj_addr_o[(g+1)*PHYS_ADDR_W-1 : g*PHYS_ADDR_W] = rs_pj[g];
            assign snoop_pk_addr_o[(g+1)*PHYS_ADDR_W-1 : g*PHYS_ADDR_W] = rs_pk[g];
        end
    endgenerate

    // ----------------------------------------------------------
    // Step 2: Wakeup-ready (busy gate is essential — prevents
    //         fresh-reset RSs with zero indices from spuriously
    //         waking up when P0 happens to be ready)
    // ----------------------------------------------------------
    generate
        for (g = 0; g < NUM_RS; g = g + 1) begin : wakeup_gen
            assign rs_wakeup_ready[g] = rs_busy[g] &
                                        snoop_pj_ready_i[g] &
                                        snoop_pk_ready_i[g];
        end
    endgenerate

    // ----------------------------------------------------------
    // Step 3: Free signals and dispatch stall
    // ----------------------------------------------------------
    generate
        for (g = 0; g < NUM_RS; g = g + 1) begin : free_gen
            assign rs_free[g] = ~rs_busy[g];
        end
    endgenerate

    assign disp_stall_o = disp_valid_i & (rs_free == {NUM_RS{1'b0}});

    // ----------------------------------------------------------
    // Step 4: Priority encoders (lowest-index wins)
    // ----------------------------------------------------------

    // Issue select
    assign issue_select[0] =  rs_wakeup_ready[0];
    assign issue_select[1] =  rs_wakeup_ready[1] & ~rs_wakeup_ready[0];
    assign issue_select[2] =  rs_wakeup_ready[2] & ~rs_wakeup_ready[1]
                                                  & ~rs_wakeup_ready[0];
    assign issue_select[3] =  rs_wakeup_ready[3] & ~rs_wakeup_ready[2]
                                                  & ~rs_wakeup_ready[1]
                                                  & ~rs_wakeup_ready[0];

    // Dispatch select
    assign dispatch_select[0] =  rs_free[0] & disp_valid_i;
    assign dispatch_select[1] =  rs_free[1] & ~rs_free[0] & disp_valid_i;
    assign dispatch_select[2] =  rs_free[2] & ~rs_free[1] & ~rs_free[0] & disp_valid_i;
    assign dispatch_select[3] =  rs_free[3] & ~rs_free[2] & ~rs_free[1]
                                            & ~rs_free[0] & disp_valid_i;

    // ----------------------------------------------------------
    // Step 5: Issue port — combinational mux from selected RS
    // ----------------------------------------------------------
    assign issue_valid_o = |issue_select;

    assign issue_op_o =
        issue_select[0] ? rs_op[0] :
        issue_select[1] ? rs_op[1] :
        issue_select[2] ? rs_op[2] :
        issue_select[3] ? rs_op[3] : {OP_WIDTH{1'b0}};

    assign issue_pj_o =
        issue_select[0] ? rs_pj[0] :
        issue_select[1] ? rs_pj[1] :
        issue_select[2] ? rs_pj[2] :
        issue_select[3] ? rs_pj[3] : {PHYS_ADDR_W{1'b0}};

    assign issue_pk_o =
        issue_select[0] ? rs_pk[0] :
        issue_select[1] ? rs_pk[1] :
        issue_select[2] ? rs_pk[2] :
        issue_select[3] ? rs_pk[3] : {PHYS_ADDR_W{1'b0}};

    assign issue_pd_o =
        issue_select[0] ? rs_pd[0] :
        issue_select[1] ? rs_pd[1] :
        issue_select[2] ? rs_pd[2] :
        issue_select[3] ? rs_pd[3] : {PHYS_ADDR_W{1'b0}};

    assign issue_rob_idx_o =
        issue_select[0] ? rs_rob_idx[0] :
        issue_select[1] ? rs_rob_idx[1] :
        issue_select[2] ? rs_rob_idx[2] :
        issue_select[3] ? rs_rob_idx[3] : {ROB_ADDR_W{1'b0}};

    // ----------------------------------------------------------
    // Step 6: Synchronous state update
    always @(posedge clk_i) begin
        if (reset_i) begin
            for (i = 0; i < NUM_RS; i = i + 1) begin
                rs_busy[i]    <= 1'b0;
                rs_op[i]      <= {OP_WIDTH{1'b0}};
                rs_pj[i]      <= {PHYS_ADDR_W{1'b0}};
                rs_pk[i]      <= {PHYS_ADDR_W{1'b0}};
                rs_pd[i]      <= {PHYS_ADDR_W{1'b0}};
                rs_rob_idx[i] <= {ROB_ADDR_W{1'b0}};
            end
        end else begin
            // (a) Issue: free the slot
            for (i = 0; i < NUM_RS; i = i + 1) begin
                if (issue_select[i])
                    rs_busy[i] <= 1'b0;
            end
            // (b) Dispatch: fill the slot
            for (i = 0; i < NUM_RS; i = i + 1) begin
                if (dispatch_select[i]) begin
                    rs_busy[i]    <= 1'b1;
                    rs_op[i]      <= disp_op_i;
                    rs_pj[i]      <= disp_pj_i;
                    rs_pk[i]      <= disp_pk_i;
                    rs_pd[i]      <= disp_pd_i;
                    rs_rob_idx[i] <= disp_rob_idx_i;
                end
            end
        end
    end

endmodule
