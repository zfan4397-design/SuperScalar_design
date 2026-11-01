`include "config_pkg.vh"
`include "payload_defs.vh"

module decoder (
    input wire [31:0] instr_i,
    input wire [`PC_WIDTH-1:0] pc_i,
    input wire [`PC_WIDTH-1:0] next_pc_i,

    output wire [`RS_PAYLOAD_RAM_WIDTH-1:0] payload_o,

    output reg [4:0] rs1_addr_o,
    output reg [4:0] rs2_addr_o,
    output reg [11:0] csr_addr_o
);

    // REGISTERS / WIRES
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg [6:0] funct7;
    reg [4:0] rs1;
    reg [4:0] rs2;
    reg [4:0] rd;
    reg [11:0] csr_addr;

    reg [`ZIMM_WIDTH-1:0] csr_zimm;

    reg [`RS_PAYLOAD_RAM_WIDTH-1:0] payload_d;

    reg [2:0] extend_op_d;
    reg extend_sign_d;
    wire [31:0] extend_res;

    // BASIC
    always @(*) begin
        opcode   = instr_i[6:0];
        rd       = instr_i[11:7];
        funct3   = instr_i[14:12];
        rs1      = instr_i[19:15];
        rs2      = instr_i[24:20];
        funct7   = instr_i[31:25];
        csr_addr = instr_i[31:20];

        csr_zimm = instr_i[19:15];
    end

    // MAIN DECODE
    always @(*) begin
        // default
        payload_d = {`RS_PAYLOAD_RAM_WIDTH{1'b0}};

        payload_d[`RS_PAYLOAD_RAM_RD_RANGE]      = rd;
        payload_d[`RS_PAYLOAD_RAM_PC_RANGE]      = pc_i;
        payload_d[`RS_PAYLOAD_RAM_NEXT_PC_RANGE] = next_pc_i;

        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE]   = `FU_NORMAL;
        payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE]   = `RETIRE_NWR;
        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] = `REGW_ALU;

        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] = `WSTRB_NONE;
        payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE]     = 1'b0;
        payload_d[`RS_PAYLOAD_RAM_MEM_R_RANGE]     = 1'b0;
        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] = `WSTRB_NONE;

        payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE]   = 1'b0;
        payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE]   = 1'b0;
        payload_d[`RS_PAYLOAD_RAM_RDV_RANGE]    = 1'b0;
        payload_d[`RS_PAYLOAD_RAM_IS_RET_RANGE] = 1'b0;

        payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] = `NBR;
        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `EQ;

        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE]   = `ALU_ADD;
        payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] = `SRC1SEL_REGDATA;
        payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] = `SRC2SEL_REGDATA;

        payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE]    = 32'b0;
        payload_d[`RS_PAYLOAD_RAM_ZIMM_RANGE]      = 0;
        payload_d[`RS_PAYLOAD_RAM_CSRADDR_RANGE]   = 12'b0;
        payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] = `EXCPT_NOEX;

        payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] = `CSROP_NCSR;

        extend_op_d   = 3'b000;
        extend_sign_d = 1'b0;

        rs1_addr_o = rs1;
        rs2_addr_o = rs2;
        csr_addr_o = csr_addr;

        case (opcode)

            // LUI
            7'b0110111: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_NORMAL;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_EXTEND;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_ALL;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_REGDATA;

                extend_op_d   = 3'b011; // U
                extend_sign_d = 1'b0;

                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                rs1_addr_o = 5'd0;
                rs2_addr_o = 5'd0;
                csr_addr_o = 12'd0;
            end

            // AUIPC
            7'b0010111: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_NORMAL;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_ALL;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_PC;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b011; // U
                extend_sign_d = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                rs1_addr_o = 5'd0;
                rs2_addr_o = 5'd0;
                csr_addr_o = 12'd0;
            end

            // JAL
            7'b1101111: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_BR;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_PC;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_ALL;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `MBR_DIRECT;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_PC;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b100; // J
                extend_sign_d = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                rs1_addr_o = 5'd0;
                rs2_addr_o = 5'd0;
                csr_addr_o = 12'd0;
            end

            // JALR
            7'b1100111: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_BR;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_PC;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_ALL;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `MBR_INDIRECT;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;
                payload_d[`RS_PAYLOAD_RAM_IS_RET_RANGE] =
                    (rd == 5'd0) && (rs1 == 5'd1) &&
                    (instr_i[31:20] == 12'b0);

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b000; // I
                extend_sign_d = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                rs1_addr_o = rs1;
                rs2_addr_o = 5'd0;
                csr_addr_o = 12'd0;
            end

            // BRANCH
            7'b1100011: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_BR;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_NWR;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_NONE;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `CBR_DIRECT;

                case (funct3)
                    3'b000:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `EQ;
                    3'b001:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `NE;
                    3'b100:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `LT;
                    3'b101:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `GE;
                    3'b110:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `LTU;
                    3'b111:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `GEU;
                    default:
                        payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] = `EQ;
                endcase

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_PC;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b010; // B
                extend_sign_d = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                rs1_addr_o = rs1;
                rs2_addr_o = rs2;
                csr_addr_o = 12'd0;
            end

            // LOAD
            7'b0000011: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_MEM;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_MEM_SIGNED;

                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_NONE;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b000; // I-type
                extend_sign_d = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                case (funct3)
                    3'b000: begin // LB
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_SB;
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                            `WSTRB_SB;
                    end

                    3'b001: begin // LH
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_SH;
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                            `WSTRB_SH;
                    end

                    3'b010: begin // LW
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_SW;
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                            `WSTRB_SW;
                    end

                    3'b100: begin // LBU
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_SB;
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                            `WSTRB_SB;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_MEM_UNSIGNED;
                    end

                    3'b101: begin // LHU
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_SH;
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                            `WSTRB_SH;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_MEM_UNSIGNED;
                    end

                    default: begin
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_NONE;
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                            `WSTRB_NONE;
                        payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;
                        payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                            `RETIRE_NWR;
                    end
                endcase

                rs1_addr_o = rs1;
                rs2_addr_o = 5'd0;
                csr_addr_o = 12'd0;
            end

            // STORE
            7'b0100011: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_MEM;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_MEM;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_NONE;

                case (funct3)
                    3'b000:
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] = `WSTRB_SB;
                    3'b001:
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] = `WSTRB_SH;
                    3'b010:
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] = `WSTRB_SW;
                    default:
                        payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] = `WSTRB_SW;
                endcase

                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b1;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b001; // S
                extend_sign_d = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                rs1_addr_o = rs1;
                rs2_addr_o = rs2;
                csr_addr_o = 12'd0;
            end

            // OP-IMM
            7'b0010011: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_NORMAL;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_ALL;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_EXTEND;

                extend_op_d   = 3'b000; // I
                extend_sign_d = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                    extend_res;

                case (funct3)
                    3'b000:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_ADD; // ADDI

                    3'b010: begin // SLTI
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SLT;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_CMP;
                    end

                    3'b011: begin // SLTIU
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SLTU;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_CMP;
                    end

                    3'b100:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_XOR; // XORI

                    3'b110:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_OR; // ORI

                    3'b111:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_AND; // ANDI

                    3'b001: begin // SLLI
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SLL;
                        extend_op_d   = 3'b101; // I shamt
                        extend_sign_d = 1'b0;
                        payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                            extend_res;
                    end

                    3'b101: begin
                        extend_op_d   = 3'b101; // I shamt
                        extend_sign_d = 1'b0;
                        payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] =
                            extend_res;

                        if (funct7 == 7'b0000000) begin // SRLI
                            payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                                `ALU_SRL;
                        end
                        else if (funct7 == 7'b0100000) begin // SRAI
                            payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                                `ALU_SRA;
                        end
                        else begin
                            payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                                `RETIRE_NWR;
                            payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                                `WSTRB_NONE;
                            payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                                1'b0;
                        end
                    end

                    default: begin
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_ADD;
                        payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                            `RETIRE_NWR;
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_NONE;
                        payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                            1'b0;
                    end
                endcase

                rs1_addr_o = rs1;
                rs2_addr_o = 5'd0;
                csr_addr_o = 12'd0;
            end

            // OP (R-type)
            7'b0110011: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_NORMAL;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_WR_ARF;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_ALL;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b1;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                    (rd != 5'd0);

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_REGDATA;

                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] = 32'b0;
                payload_d[`RS_PAYLOAD_RAM_ZIMM_RANGE] = 0;

                case ({funct7, funct3})
                    {7'b0000000, 3'b000}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_ADD;

                    {7'b0100000, 3'b000}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SUB;

                    {7'b0000000, 3'b001}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SLL;

                    {7'b0000000, 3'b010}: begin
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SLT;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_CMP;
                    end

                    {7'b0000000, 3'b011}: begin
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SLTU;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_CMP;
                    end

                    {7'b0000000, 3'b100}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_XOR;

                    {7'b0000000, 3'b101}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SRL;

                    {7'b0100000, 3'b101}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_SRA;

                    {7'b0000000, 3'b110}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_OR;

                    {7'b0000000, 3'b111}:
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_AND;

                    {7'b0000001, 3'b000}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_MUL;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_MUL;
                    end

                    {7'b0000001, 3'b001}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_MUL;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_MULH;
                    end

                    {7'b0000001, 3'b010}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_MUL;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_MULHSU;
                    end

                    {7'b0000001, 3'b011}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_MUL;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_MULHU;
                    end

                    {7'b0000001, 3'b100}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_DIV;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_DIV;
                    end

                    {7'b0000001, 3'b101}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_DIV;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_DIVU;
                    end

                    {7'b0000001, 3'b110}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_DIV;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_REM;
                    end

                    {7'b0000001, 3'b111}: begin
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_DIV;
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_REMU;
                    end

                    default: begin
                        payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                            `ALU_ADD;
                        payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                            `RETIRE_NWR;
                        payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                            `WSTRB_NONE;
                        payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                            1'b0;
                    end
                endcase

                rs1_addr_o = rs1;
                rs2_addr_o = rs2;
                csr_addr_o = 12'd0;
            end

            // FENCE / FENCE.I
            7'b0001111: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_NORMAL;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_NWR;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;

                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_NONE;
                payload_d[`RS_PAYLOAD_RAM_MEM_W_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE] =
                    `WSTRB_NONE;

                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;

                payload_d[`RS_PAYLOAD_RAM_BRANCH_TYPE_RANGE] =
                    `NBR;
                payload_d[`RS_PAYLOAD_RAM_BRANCH_INFO_RANGE] =
                    `EQ;

                payload_d[`RS_PAYLOAD_RAM_ALU_OP_RANGE] =
                    `ALU_ADD;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE] =
                    `SRC1SEL_REGDATA;
                payload_d[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE] =
                    `SRC2SEL_REGDATA;

                payload_d[`RS_PAYLOAD_RAM_EXTEND_RANGE] = 32'b0;
                payload_d[`RS_PAYLOAD_RAM_ZIMM_RANGE] = 0;

                rs1_addr_o = rs1;
                rs2_addr_o = rs2;
                csr_addr_o = 12'd0;
            end

            // SYSTEM / CSR / 特权指令
            7'b1110011: begin
                payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                    `FU_CSR;
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_NWR;
                payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                    `REGW_ALU;
                payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                    `WSTRB_NONE;
                payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RS2R_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;
                payload_d[`RS_PAYLOAD_RAM_ZIMM_RANGE] =
                    csr_zimm;
                payload_d[`RS_PAYLOAD_RAM_CSRADDR_RANGE] =
                    csr_addr;
                payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                    `EXCPT_NOEX;

                rs1_addr_o = rs1;
                rs2_addr_o = rs2;
                csr_addr_o = csr_addr;

                // 特权指令
                if (funct3 == 3'b000) begin
                    case (instr_i[31:20])
                        12'h000: begin // ECALL
                            payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                                `EXCPT_ECALL;
                        end

                        12'h001: begin // EBREAK
                            payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                                `EXCPT_EBREAK;
                        end

                        12'h302: begin // MRET
                            payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                                `EXCPT_MRET;
                        end

                        12'h102: begin // SRET
                            payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                                `EXCPT_SRET;
                        end

                        12'h002: begin // URET
                            payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                                `EXCPT_URET;
                        end

                        default: begin
                            payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                                `EXCPT_ILLEGAL_INST;
                        end
                    endcase

                    payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                        `RETIRE_NWR;
                    payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                        `REGW_ALU;
                    payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;

                    rs1_addr_o = 5'd0;
                    rs2_addr_o = 5'd0;
                    csr_addr_o = 12'd0;
                end

                // CSR 指令
                else begin
                    payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                        `REGW_CSR;
                    payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                        `RETIRE_WR_ARF;

                    payload_d[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE] =
                        `WSTRB_ALL;
                    payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                        (rd != 5'd0);

                    payload_d[`RS_PAYLOAD_RAM_CSRADDR_RANGE] =
                        csr_addr;
                    payload_d[`RS_PAYLOAD_RAM_ZIMM_RANGE] =
                        csr_zimm;

                    case (funct3)
                        3'b001:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_CSRRW;
                        3'b010:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_CSRRS;
                        3'b011:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_CSRRC;
                        3'b101:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_CSRRWI;
                        3'b110:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_CSRRSI;
                        3'b111:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_CSRRCI;
                        default:
                            payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                                `CSROP_NCSR;
                    endcase

                    if (funct3[2] == 1'b0)
                        payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] =
                            (rs1 != 5'd0);
                    else
                        payload_d[`RS_PAYLOAD_RAM_RS1R_RANGE] =
                            1'b0;

                    // CSRRS/CSRRC rs1=x0：只读 CSR。
                    if ((funct3 == 3'b010 || funct3 == 3'b011)
                        && (rs1 == 5'd0)) begin
                        payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                            `CSROP_READ;
                    end

                    // CSRRSI/CSRRCI zimm=0：只读 CSR。
                    if ((funct3 == 3'b110 || funct3 == 3'b111)
                        && (instr_i[19:15] == 5'd0)) begin
                        payload_d[`RS_PAYLOAD_RAM_CSROP_RANGE] =
                            `CSROP_READ;
                    end

                    // 原 inside 集合判断转换为普通比较。
                    if (!((funct3 == 3'b001) ||
                          (funct3 == 3'b010) ||
                          (funct3 == 3'b011) ||
                          (funct3 == 3'b101) ||
                          (funct3 == 3'b110) ||
                          (funct3 == 3'b111))) begin

                        payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                            `EXCPT_ILLEGAL_INST;
                        payload_d[`RS_PAYLOAD_RAM_REG_INFO_RANGE] =
                            `REGW_ALU;
                        payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                            `RETIRE_NWR;
                        payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] =
                            1'b0;
                        payload_d[`RS_PAYLOAD_RAM_FUTYPE_RANGE] =
                            `FU_EXC;
                    end
                end
            end

            // DEFAULT
            default: begin
                payload_d[`RS_PAYLOAD_RAM_EXCEPTION_RANGE] =
                    `EXCPT_ILLEGAL_INST;
            end
        endcase

        if (rd == 5'd0) begin
            payload_d[`RS_PAYLOAD_RAM_RDV_RANGE] = 1'b0;

            if (payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] ==
                `RETIRE_WR_ARF)
                payload_d[`RS_PAYLOAD_RAM_RTTYPE_RANGE] =
                    `RETIRE_NWR;
        end
    end

    // INSTANTIATION：保持原项目独立的 extend 模块。
    extend u_extend (
        .imm_i       (instr_i[31:7]),
        .extend_op   (extend_op_d),
        .extend_sign (extend_sign_d),
        .extend      (extend_res)
    );

    // OUTPUT
    assign payload_o = payload_d;

endmodule