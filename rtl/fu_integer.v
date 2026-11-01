module fu_integer #(
    parameter integer DATA_WIDTH       = 32,
    parameter integer PC_WIDTH         = 32,
    parameter integer PRD_WIDTH        = 6,
    parameter integer EXCPT_WIDTH      = 4,
    parameter integer ALU_SRCSEL_WIDTH = 2,
    parameter integer ALU_INFO_WIDTH   = 5,
    parameter integer REG_INFO_WIDTH   = 3,
    parameter integer TYPE_WIDTH       = 3,
    parameter integer PAYLOAD_WIDTH = EXCPT_WIDTH + 2*PC_WIDTH + 2*ALU_SRCSEL_WIDTH + ALU_INFO_WIDTH + REG_INFO_WIDTH + TYPE_WIDTH + 80
)(
    input  wire have_inst,
    input  wire [PAYLOAD_WIDTH-1:0] payload_ram,
    input  wire [DATA_WIDTH-1:0] src1,
    input  wire [DATA_WIDTH-1:0] src2,
    input  wire [PRD_WIDTH-1:0] prd,
    input  wire prd_v,
    input  wire [PRD_WIDTH:0] rob_fifonum,

    output reg [PRD_WIDTH-1:0] wb0_prd,
    output reg wb0_valid,
    output reg wb0_regw,//是否需要写寄存器
    output reg [DATA_WIDTH-1:0] wb0_data,
    output reg [EXCPT_WIDTH-1:0] wb0_exception,
    output reg [DATA_WIDTH-1:0] wb0_brdest,
    output reg [PRD_WIDTH:0] wb0_fifonum
    );
localparam integer SRC1SEL_REGDATA = 0;
localparam integer SRC1SEL_PC = 1;
localparam integer SRC2SEL_REGDATA = 0;
localparam integer SRC2SEL_EXTEND = 1;
localparam integer ALU_ADD = 0;
localparam integer ALU_SUB = 1;
localparam integer ALU_XOR = 2;
localparam integer ALU_OR = 3;
localparam integer ALU_AND = 4;
localparam integer ALU_SLL = 5;
localparam integer ALU_SRL = 6;
localparam integer ALU_SRA = 7;
localparam integer ALU_SLT = 8;
localparam integer ALU_SLTU = 9;
localparam integer RETIRE_WR_ARF = 1;
localparam integer EXCPT_NOEX = 0;
localparam integer REGW_ALU = 0;
localparam integer REGW_PC = 2;
localparam integer REGW_CMP = 3;
localparam integer REGW_CSR = 4;
localparam integer REGW_EXTEND = 5;

// Packed payload layout, from low bits to high bits.
// Skip zimm[4:0], csraddr[11:0], csrop[2:0] after exception.
localparam integer PAYLOAD_EXTEND_LSB   = EXCPT_WIDTH + 5 + 12 + 3;
localparam integer PAYLOAD_ALU_SRC2_LSB = PAYLOAD_EXTEND_LSB + 32;
localparam integer PAYLOAD_ALU_SRC1_LSB = PAYLOAD_ALU_SRC2_LSB + ALU_SRCSEL_WIDTH;
localparam integer PAYLOAD_ALU_OP_LSB   = PAYLOAD_ALU_SRC1_LSB + ALU_SRCSEL_WIDTH;
// Skip mem_wstrb[3:0], six one-bit flags, and reg_wstrb[3:0].
localparam integer PAYLOAD_REG_INFO_LSB = PAYLOAD_ALU_OP_LSB + ALU_INFO_WIDTH + 4 + 6 + 4;
localparam integer PAYLOAD_RTTYPE_LSB   = PAYLOAD_REG_INFO_LSB + REG_INFO_WIDTH;
// Skip branch_type[1:0], branch_info[3:0], futype[2:0].
localparam integer PAYLOAD_NEXT_PC_LSB  = PAYLOAD_RTTYPE_LSB + TYPE_WIDTH + 2 + 4 + 3;
localparam integer PAYLOAD_PC_LSB       = PAYLOAD_NEXT_PC_LSB + PC_WIDTH;
localparam integer PAYLOAD_RD_LSB       = PAYLOAD_PC_LSB + PC_WIDTH;

// SoA-style internal fields: computation uses these independent signals.
wire [ALU_SRCSEL_WIDTH-1:0] payload_alu_src1;
wire [ALU_SRCSEL_WIDTH-1:0] payload_alu_src2;
wire [ALU_INFO_WIDTH-1:0] payload_alu_op;
wire [REG_INFO_WIDTH-1:0] payload_reg_info;
wire [TYPE_WIDTH-1:0] payload_rttype;
wire [5-1:0] payload_rd;
wire [PC_WIDTH-1:0] payload_pc;
wire [PC_WIDTH-1:0] payload_next_pc;
wire [32-1:0] payload_extend;

assign payload_alu_src1 = payload_ram[PAYLOAD_ALU_SRC1_LSB +: ALU_SRCSEL_WIDTH];
assign payload_alu_src2 = payload_ram[PAYLOAD_ALU_SRC2_LSB +: ALU_SRCSEL_WIDTH];
assign payload_alu_op = payload_ram[PAYLOAD_ALU_OP_LSB +: ALU_INFO_WIDTH];
assign payload_reg_info = payload_ram[PAYLOAD_REG_INFO_LSB +: REG_INFO_WIDTH];
assign payload_rttype = payload_ram[PAYLOAD_RTTYPE_LSB +: TYPE_WIDTH];
assign payload_rd = payload_ram[PAYLOAD_RD_LSB +: 5];
assign payload_pc = payload_ram[PAYLOAD_PC_LSB +: PC_WIDTH];
assign payload_next_pc = payload_ram[PAYLOAD_NEXT_PC_LSB +: PC_WIDTH];
assign payload_extend = payload_ram[PAYLOAD_EXTEND_LSB +: 32];

reg [DATA_WIDTH-1:0] alu_output;
reg [1:0] cmp;

reg [DATA_WIDTH-1:0] oprand_src1;
reg [DATA_WIDTH-1:0] oprand_src2;
reg signed [DATA_WIDTH-1:0] oprand_s_src1;
reg signed [DATA_WIDTH-1:0] oprand_s_src2;
    
always@(*) begin
    case(payload_alu_src1)
        SRC1SEL_REGDATA: oprand_src1=src1;
        SRC1SEL_PC: oprand_src1=payload_pc;
        default: oprand_src1=0;
endcase
end

always@(*) begin
    case(payload_alu_src2)
        SRC2SEL_EXTEND: oprand_src2=payload_extend;
        SRC2SEL_REGDATA: oprand_src2=src2;
        default: oprand_src2=0;
endcase
end

always@(*) begin
    oprand_s_src1=$signed(oprand_src1);
    oprand_s_src2=$signed(oprand_src2);
end

always@(*) begin
    alu_output=32'b0;
    cmp=2'b00;
    case(payload_alu_op)
        ALU_ADD : alu_output = oprand_src1    +  oprand_src2;
        ALU_SUB : alu_output = oprand_src1    -  oprand_src2;
        ALU_XOR : alu_output = oprand_src1    ^  oprand_src2;
        ALU_OR  : alu_output = oprand_src1    |  oprand_src2;
        ALU_AND : alu_output = oprand_src1    &  oprand_src2;
        ALU_SLL : alu_output = oprand_src1    << oprand_src2[4:0];
        ALU_SRL : alu_output = oprand_src1    >> oprand_src2[4:0];
        ALU_SRA : alu_output = oprand_s_src1  >>> oprand_src2[4:0];
        ALU_SLT : cmp        = (oprand_s_src1 <  oprand_s_src2) ? 2'b01 : 2'b00; 
        ALU_SLTU: cmp        = (oprand_src1   <  oprand_src2 )  ? 2'b01 : 2'b00; 
        default : alu_output = 32'b0;
    endcase
end

always@(*) begin
    wb0_prd     =   prd;
    wb0_valid   =   have_inst;
    wb0_regw    =   (payload_rttype == RETIRE_WR_ARF) && (payload_rd != 5'b0);
    wb0_brdest  =   payload_next_pc;
    wb0_fifonum =   rob_fifonum;
    wb0_exception   =   EXCPT_NOEX;
end

always @(*) begin
    case(payload_reg_info)
        REGW_ALU   : wb0_data = alu_output;
        REGW_PC    : wb0_data = payload_pc + 4;
        REGW_CMP   : wb0_data = {31'b0, cmp[0]};
        REGW_CSR   : wb0_data = 0;
        REGW_EXTEND: wb0_data = payload_extend;
        default    : wb0_data = 0;
    endcase
    if(payload_rd==0) begin
        wb0_data = 0;
    end
end

endmodule
        