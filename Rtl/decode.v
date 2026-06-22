`timescale 1ns / 1ps

module decode #(
    parameter ARCH_ADDR_W = 5,
    parameter OP_WIDTH    = 4
) (
    input  wire [31:0]           instr_i,
    input  wire                  valid_i,

    output wire [OP_WIDTH-1:0]   op_o,
    output wire [ARCH_ADDR_W-1:0] rs1_arch_o,
    output wire [ARCH_ADDR_W-1:0] rs2_arch_o,
    output wire [ARCH_ADDR_W-1:0] rd_arch_o,
    output wire                  writes_rd_o,
    output wire [31:0]           imm_o,
    output wire                  is_branch_o,
    output wire                  is_memory_o,
    output wire [1:0]            fu_type_o,   // 0=ALU, 1=MUL, 2=LSU
    output wire                  valid_o
);

    // ----------------------------------------------------------
    // RV32I instruction fields
    // ----------------------------------------------------------
    wire [6:0] opcode = instr_i[6:0];
    wire [4:0] rd     = instr_i[11:7];
    wire [2:0] funct3 = instr_i[14:12];
    wire [4:0] rs1    = instr_i[19:15];
    wire [4:0] rs2    = instr_i[24:20];
    wire [6:0] funct7 = instr_i[31:25];

    // ----------------------------------------------------------
    // Opcode decoding
    // ----------------------------------------------------------
    reg [OP_WIDTH-1:0] op_internal;
    always @* begin
        case (opcode)
            7'b0110011: begin   // R-type
                case (funct3)
                    3'b000: op_internal = funct7[5] ? 4'd1 : 4'd0; // SUB/ADD
                    3'b111: op_internal = 4'd2;  // AND
                    3'b110: op_internal = 4'd3;  // OR
                    3'b100: op_internal = 4'd4;  // XOR
                    3'b001: op_internal = 4'd5;  // SLL
                    3'b101: op_internal = 4'd6;  // SRL
                    3'b010: op_internal = 4'd7;  // SLT
                    default: op_internal = 4'd0;
                endcase
            end
            7'b0010011: op_internal = 4'd8;   // ADDI
            7'b0000011: op_internal = 4'd9;   // LW
            7'b0100011: op_internal = 4'd10;  // SW
            7'b1100011: op_internal = funct3[0] ? 4'd12 : 4'd11; // BNE/BEQ
            7'b1101111: op_internal = 4'd13;  // JAL
            default:    op_internal = 4'd0;
        endcase
    end

    // ----------------------------------------------------------
    // Output assignments
    // ----------------------------------------------------------
    assign op_o      = op_internal;
    assign rs1_arch_o = rs1;
    assign rs2_arch_o = rs2;
    assign rd_arch_o  = rd;

    assign writes_rd_o = valid_i & (
        (opcode == 7'b0110011) |   // R-type
        (opcode == 7'b0010011) |   // ADDI
        (opcode == 7'b0000011) |   // LW
        (opcode == 7'b1101111)     // JAL
    );

    assign is_branch_o = valid_i & (
        (opcode == 7'b1100011) |   // BEQ/BNE
        (opcode == 7'b1101111)     // JAL
    );

    assign is_memory_o = valid_i & (
        (opcode == 7'b0000011) |   // LW
        (opcode == 7'b0100011)     // SW
    );

    assign fu_type_o = is_memory_o ? 2'd2 : 2'd0;  // LSU or ALU

    // ----------------------------------------------------------
    // Sign-extended immediates (all formats)
    // ----------------------------------------------------------
    wire [31:0] imm_I = {{20{instr_i[31]}}, instr_i[31:20]};
    wire [31:0] imm_S = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
    wire [31:0] imm_B = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                          instr_i[30:25], instr_i[11:8], 1'b0};
    wire [31:0] imm_J = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                          instr_i[20], instr_i[30:21], 1'b0};

    assign imm_o = (opcode == 7'b0100011) ? imm_S :  // SW
                   (opcode == 7'b1100011) ? imm_B :  // BEQ/BNE
                   (opcode == 7'b1101111) ? imm_J :  // JAL
                   imm_I;                             // default I-type

    assign valid_o = valid_i;

endmodule
