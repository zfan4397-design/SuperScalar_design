// Internal named fields / SoA storage; original overall ports retained.
// Converted from vsrc/core/fu_mul.sv.
// Array ports retain the requested unpacked form; compile in SystemVerilog mode.
module fu_mul #(
    parameter integer EXCPT_WIDTH = 4,
    parameter integer ZIMM_WIDTH = 5,
    parameter integer ALU_SRCSEL_WIDTH = 2,
    parameter integer ALU_INFO_WIDTH = 5,
    parameter integer PC_WIDTH = 32,
    parameter integer PAYLOAD_WIDTH = EXCPT_WIDTH+ZIMM_WIDTH+2*ALU_SRCSEL_WIDTH+ALU_INFO_WIDTH+2*PC_WIDTH+81,
    parameter integer DATA_WIDTH = 32,
    parameter integer PRD_WIDTH = 6,
    parameter integer XLEN = DATA_WIDTH
) (
    input  wire clk,
    input  wire rst,
    input  wire have_inst,
    input  wire [PAYLOAD_WIDTH-1:0] payload_ram,
    input  wire [DATA_WIDTH-1:0] src1,
    input  wire [DATA_WIDTH-1:0] src2,
    input  wire [PRD_WIDTH-1:0] prd,
    input  wire prd_v,
    input  wire [PRD_WIDTH:0] rob_fifonum,
    input  wire ctrl_restore,
    input  wire ctrl_clear,
    output wire ctrl_stall_req,
    input  wire [PRD_WIDTH:0] flnum,
    output reg [PRD_WIDTH-1:0] wb0_prd,
    output reg wb0_valid,
    output reg wb0_regw,
    output reg [DATA_WIDTH-1:0] wb0_data,
    output reg [EXCPT_WIDTH-1:0] wb0_exception,
    output reg [DATA_WIDTH-1:0] wb0_brdest,
    output reg [PRD_WIDTH:0] wb0_fifonum);

// 固定位序与操作编码属于内部常量，不再作为外部可覆盖参数。
localparam integer PAYLOAD_ZIMM_LSB = EXCPT_WIDTH;
localparam integer PAYLOAD_ZIMM_W = ZIMM_WIDTH;
localparam integer PAYLOAD_EXTEND_LSB = EXCPT_WIDTH+ZIMM_WIDTH+15;
localparam integer PAYLOAD_EXTEND_W = 32;
localparam integer PAYLOAD_ALU_SRC2_LSB = EXCPT_WIDTH+ZIMM_WIDTH+47;
localparam integer PAYLOAD_ALU_SRC2_W = ALU_SRCSEL_WIDTH;
localparam integer PAYLOAD_ALU_SRC1_LSB = EXCPT_WIDTH+ZIMM_WIDTH+ALU_SRCSEL_WIDTH+47;
localparam integer PAYLOAD_ALU_SRC1_W = ALU_SRCSEL_WIDTH;
localparam integer PAYLOAD_ALU_OP_LSB = EXCPT_WIDTH+ZIMM_WIDTH+2*ALU_SRCSEL_WIDTH+47;
localparam integer PAYLOAD_ALU_OP_W = ALU_INFO_WIDTH;
localparam integer PAYLOAD_NEXT_PC_LSB = EXCPT_WIDTH+ZIMM_WIDTH+2*ALU_SRCSEL_WIDTH+ALU_INFO_WIDTH+76;
localparam integer PAYLOAD_NEXT_PC_W = PC_WIDTH;
localparam integer PAYLOAD_PC_LSB = EXCPT_WIDTH+ZIMM_WIDTH+2*ALU_SRCSEL_WIDTH+ALU_INFO_WIDTH+PC_WIDTH+76;
localparam integer PAYLOAD_PC_W = PC_WIDTH;
localparam integer SRC1SEL_REGDATA = 0;
localparam integer SRC1SEL_PC = 1;
localparam integer SRC1SEL_ZIMM = 2;
localparam integer SRC2SEL_REGDATA = 0;
localparam integer SRC2SEL_EXTEND = 1;
localparam integer ALU_MUL = 10;
localparam integer ALU_MULH = 11;
localparam integer ALU_MULHSU = 12;
localparam integer ALU_MULHU = 13;
localparam integer EXCPT_NOEX = 0;


// 内部字段：仅在输入边界拆包，后面的运算直接使用独立信号。
wire [ALU_SRCSEL_WIDTH-1:0] payload_alu_src1;
wire [PC_WIDTH-1:0] payload_pc;
wire [ZIMM_WIDTH-1:0] payload_zimm;
wire [ALU_SRCSEL_WIDTH-1:0] payload_alu_src2;
wire [32-1:0] payload_extend;
wire [ALU_INFO_WIDTH-1:0] payload_alu_op;
wire [PC_WIDTH-1:0] payload_next_pc;
assign payload_alu_src1 = payload_ram[PAYLOAD_ALU_SRC1_LSB +: PAYLOAD_ALU_SRC1_W];
assign payload_pc = payload_ram[PAYLOAD_PC_LSB +: PAYLOAD_PC_W];
assign payload_zimm = payload_ram[PAYLOAD_ZIMM_LSB +: PAYLOAD_ZIMM_W];
assign payload_alu_src2 = payload_ram[PAYLOAD_ALU_SRC2_LSB +: PAYLOAD_ALU_SRC2_W];
assign payload_extend = payload_ram[PAYLOAD_EXTEND_LSB +: PAYLOAD_EXTEND_W];
assign payload_alu_op = payload_ram[PAYLOAD_ALU_OP_LSB +: PAYLOAD_ALU_OP_W];
assign payload_next_pc = payload_ram[PAYLOAD_NEXT_PC_LSB +: PAYLOAD_NEXT_PC_W];

function fifoid_gt(
    input [PRD_WIDTH:0]     a,
    input [PRD_WIDTH:0]     b
);
    fifoid_gt = ( (a[PRD_WIDTH] == b[PRD_WIDTH]) ?
                      (a[PRD_WIDTH-1:0] > b[PRD_WIDTH-1:0]) :
                      (a[PRD_WIDTH-1:0] < b[PRD_WIDTH-1:0]) );
    
endfunction

    localparam [1:0] MUL_OP_MUL    = 2'b00;
    localparam [1:0] MUL_OP_MULH   = 2'b01;
    localparam [1:0] MUL_OP_MULHSU = 2'b10;
    localparam [1:0] MUL_OP_MULHU  = 2'b11;

    reg [DATA_WIDTH-1:0] oprand_src1;
    reg [DATA_WIDTH-1:0] oprand_src2;
    wire mul_req_valid;
    wire mul_req_ready;
    reg [1:0] mul_req_op;
    wire mul_resp_valid;
    wire mul_resp_ready;
    wire [DATA_WIDTH-1:0] mul_resp_result;
    reg is_mul_inst;
    wire mul_req_fire;
    wire req_killed_by_restore;
    wire wb0_kill;
    
    //_r：当前保存在寄存器里的值
    reg c0_valid_r;
    reg [PRD_WIDTH-1:0] c0_prd_r;
    reg c0_prd_v_r;
    reg [DATA_WIDTH-1:0] c0_brdest_r;
    reg [PRD_WIDTH:0] c0_fifonum_r;
    
    reg c1_valid_r;
    reg [PRD_WIDTH-1:0] c1_prd_r;
    reg c1_prd_v_r;
    reg [DATA_WIDTH-1:0] c1_brdest_r;
    reg [PRD_WIDTH:0] c1_fifonum_r;
    
    reg c2_valid_r;
    reg [PRD_WIDTH-1:0] c2_prd_r;
    reg c2_prd_v_r;
    reg [DATA_WIDTH-1:0] c2_brdest_r;
    reg [PRD_WIDTH:0] c2_fifonum_r;
    
    //_n：准备再下一时钟上升沿写入的值
    reg c0_valid_n;
    reg [PRD_WIDTH-1:0] c0_prd_n;
    reg c0_prd_v_n;
    reg [DATA_WIDTH-1:0] c0_brdest_n;
    reg [PRD_WIDTH:0] c0_fifonum_n;
    
    reg c1_valid_n;
    reg [PRD_WIDTH-1:0] c1_prd_n;
    reg c1_prd_v_n;
    reg [DATA_WIDTH-1:0] c1_brdest_n;
    reg [PRD_WIDTH:0] c1_fifonum_n;
    
    reg c2_valid_n;
    reg [PRD_WIDTH-1:0] c2_prd_n;
    reg c2_prd_v_n;
    reg [DATA_WIDTH-1:0] c2_brdest_n;
    reg [PRD_WIDTH:0] c2_fifonum_n;

    always @(*) begin
        case (payload_alu_src1)
            SRC1SEL_REGDATA: oprand_src1 = src1;
            SRC1SEL_PC:      oprand_src1 = payload_pc;
            SRC1SEL_ZIMM:    oprand_src1 = {{(DATA_WIDTH-ZIMM_WIDTH){1'b0}}, payload_zimm};
            default:         oprand_src1 = 0;
        endcase
    end

    always @(*) begin
        case (payload_alu_src2)
            SRC2SEL_REGDATA: oprand_src2 = src2;
            SRC2SEL_EXTEND:  oprand_src2 = payload_extend;
            default:         oprand_src2 = 0;
        endcase
    end

    always @(*) begin
        is_mul_inst = 1'b1;
        mul_req_op  = MUL_OP_MUL;
        case (payload_alu_op)
            ALU_MUL:    mul_req_op = MUL_OP_MUL;
            ALU_MULH:   mul_req_op = MUL_OP_MULH;
            ALU_MULHSU: mul_req_op = MUL_OP_MULHSU;
            ALU_MULHU:  mul_req_op = MUL_OP_MULHU;
            default: begin
                is_mul_inst = 1'b0;
                mul_req_op  = MUL_OP_MUL;
            end
        endcase
    end

    assign req_killed_by_restore = ctrl_restore && fifoid_gt(rob_fifonum, flnum);
    assign mul_req_valid         = have_inst && is_mul_inst && !ctrl_clear && !req_killed_by_restore;
    assign mul_req_fire          = mul_req_valid && mul_req_ready;
    assign mul_resp_ready        = 1'b1;
    assign ctrl_stall_req        = !mul_req_ready;

    always @(*) begin
        c0_valid_n   = mul_req_fire;
        c0_prd_n     = prd;
        c0_prd_v_n   = prd_v;
        c0_brdest_n  = payload_next_pc;
        c0_fifonum_n = rob_fifonum;

        c1_valid_n   = c0_valid_r;
        c1_prd_n     = c0_prd_r;
        c1_prd_v_n   = c0_prd_v_r;
        c1_brdest_n  = c0_brdest_r;
        c1_fifonum_n = c0_fifonum_r;

        c2_valid_n   = c1_valid_r;
        c2_prd_n     = c1_prd_r;
        c2_prd_v_n   = c1_prd_v_r;
        c2_brdest_n  = c1_brdest_r;
        c2_fifonum_n = c1_fifonum_r;

        if (ctrl_restore) begin
            if (c0_valid_n && fifoid_gt(c0_fifonum_n, flnum)) c0_valid_n = 1'b0;
            if (c1_valid_n && fifoid_gt(c1_fifonum_n, flnum)) c1_valid_n = 1'b0;
            if (c2_valid_n && fifoid_gt(c2_fifonum_n, flnum)) c2_valid_n = 1'b0;
        end
    end

    assign wb0_kill = ctrl_clear || (ctrl_restore && c2_valid_r && fifoid_gt(c2_fifonum_r, flnum));

    always @(*) begin
        wb0_prd       = c2_prd_r;
        wb0_valid     = mul_resp_valid && c2_valid_r && !wb0_kill;
        wb0_regw      = c2_prd_v_r;
        wb0_data      = mul_resp_result;
        wb0_exception = EXCPT_NOEX;
        wb0_brdest    = c2_brdest_r;
        wb0_fifonum   = c2_fifonum_r;
    end

    rv32m_mul_unit #(
    .XLEN(DATA_WIDTH)
) u_rv32m_mul_unit (
        .clk(clk),
        .rst(rst),
        .flush_i(ctrl_clear),
        .req_valid_i(mul_req_valid),
        .req_ready_o(mul_req_ready),
        .req_op_i(mul_req_op),
        .req_rs1_i(oprand_src1),
        .req_rs2_i(oprand_src2),
        .resp_valid_o(mul_resp_valid),
        .resp_ready_i(mul_resp_ready),
        .resp_result_o(mul_resp_result)
    );

    always @(posedge clk) begin
        if (rst) begin
            c0_valid_r   <= 1'b0;
            c0_prd_r     <= 0;
            c0_prd_v_r   <= 1'b0;
            c0_brdest_r  <= 0;
            c0_fifonum_r <= 0;
            c1_valid_r   <= 1'b0;
            c1_prd_r     <= 0;
            c1_prd_v_r   <= 1'b0;
            c1_brdest_r  <= 0;
            c1_fifonum_r <= 0;
            c2_valid_r   <= 1'b0;
            c2_prd_r     <= 0;
            c2_prd_v_r   <= 1'b0;
            c2_brdest_r  <= 0;
            c2_fifonum_r <= 0;
        end else if (ctrl_clear) begin
            c0_valid_r   <= 1'b0;
            c0_prd_r     <= 0;
            c0_prd_v_r   <= 1'b0;
            c0_brdest_r  <= 0;
            c0_fifonum_r <= 0;
            c1_valid_r   <= 1'b0;
            c1_prd_r     <= 0;
            c1_prd_v_r   <= 1'b0;
            c1_brdest_r  <= 0;
            c1_fifonum_r <= 0;
            c2_valid_r   <= 1'b0;
            c2_prd_r     <= 0;
            c2_prd_v_r   <= 1'b0;
            c2_brdest_r  <= 0;
            c2_fifonum_r <= 0;
        end else begin
            c0_valid_r   <= c0_valid_n;
            c0_prd_r     <= c0_prd_n;
            c0_prd_v_r   <= c0_prd_v_n;
            c0_brdest_r  <= c0_brdest_n;
            c0_fifonum_r <= c0_fifonum_n;
            c1_valid_r   <= c1_valid_n;
            c1_prd_r     <= c1_prd_n;
            c1_prd_v_r   <= c1_prd_v_n;
            c1_brdest_r  <= c1_brdest_n;
            c1_fifonum_r <= c1_fifonum_n;
            c2_valid_r   <= c2_valid_n;
            c2_prd_r     <= c2_prd_n;
            c2_prd_v_r   <= c2_prd_v_n;
            c2_brdest_r  <= c2_brdest_n;
            c2_fifonum_r <= c2_fifonum_n;
        end
    end

endmodule
