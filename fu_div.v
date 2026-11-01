module fu_div #(
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
localparam integer ALU_DIV = 14;
localparam integer ALU_DIVU = 15;
localparam integer ALU_REM = 16;
localparam integer ALU_REMU = 17;
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

    localparam [1:0] DIV_OP_DIV  = 2'b00;
    localparam [1:0] DIV_OP_DIVU = 2'b01;
    localparam [1:0] DIV_OP_REM  = 2'b10;
    localparam [1:0] DIV_OP_REMU = 2'b11;

    reg [DATA_WIDTH-1:0] oprand_src1;
    reg [DATA_WIDTH-1:0] oprand_src2;
    wire div_req_valid;
    wire div_req_ready;
    reg [1:0] div_req_op;
    
    wire div_resp_valid;
    wire div_resp_ready;
    wire [DATA_WIDTH-1:0] div_resp_result;
    reg is_div_inst;
    wire div_req_fire;
    wire req_killed_by_restore;
    
    //inflight 表示“已经接收、尚未处理完”
    reg inflight_valid_r;//这份指令身份是否仍然有效
    reg [PRD_WIDTH-1:0] inflight_prd_r;
    reg inflight_prd_v_r;
    reg [DATA_WIDTH-1:0] inflight_brdest_r;
    reg [PRD_WIDTH:0] inflight_fifonum_r;

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
        is_div_inst = 1'b1;
        div_req_op  = DIV_OP_DIV;
        case (payload_alu_op)
            ALU_DIV:  div_req_op = DIV_OP_DIV;
            ALU_DIVU: div_req_op = DIV_OP_DIVU;
            ALU_REM:  div_req_op = DIV_OP_REM;
            ALU_REMU: div_req_op = DIV_OP_REMU;
            default: begin
                is_div_inst = 1'b0;
                div_req_op  = DIV_OP_DIV;
            end
        endcase
    end

    assign req_killed_by_restore = ctrl_restore && fifoid_gt(rob_fifonum, flnum);
    assign div_req_valid         = have_inst && is_div_inst && !ctrl_clear && !req_killed_by_restore;
    assign div_req_fire          = div_req_valid && div_req_ready;
    assign div_resp_ready        = 1'b1;
    assign ctrl_stall_req        = !div_req_ready;

    always @(*) begin
        wb0_prd       = inflight_prd_r;
        wb0_valid     = div_resp_valid && inflight_valid_r;
        wb0_regw      = inflight_prd_v_r;
        wb0_data      = div_resp_result;
        wb0_exception = EXCPT_NOEX;
        wb0_brdest    = inflight_brdest_r;
        wb0_fifonum   = inflight_fifonum_r;
    end

    rv32m_div_unit #(
    .XLEN(DATA_WIDTH)
) u_rv32m_div_unit (
        .clk(clk),
        .rst(rst),
        .flush_i(ctrl_clear),
        .req_valid_i(div_req_valid),
        .req_ready_o(div_req_ready),
        .req_op_i(div_req_op),
        .req_rs1_i(oprand_src1),
        .req_rs2_i(oprand_src2),
        .resp_valid_o(div_resp_valid),
        .resp_ready_i(div_resp_ready),
        .resp_result_o(div_resp_result)
    );

    always @(posedge clk) begin
        if (rst) begin
            inflight_valid_r   <= 1'b0;
            inflight_prd_r     <= 0;
            inflight_prd_v_r   <= 1'b0;
            inflight_brdest_r  <= 0;
            inflight_fifonum_r <= 0;
        end else if (ctrl_clear) begin
            inflight_valid_r   <= 1'b0;
            inflight_prd_r     <= 0;
            inflight_prd_v_r   <= 1'b0;
            inflight_brdest_r  <= 0;
            inflight_fifonum_r <= 0;
        end else begin
            if (div_req_fire) begin
                inflight_valid_r   <= 1'b1;
                inflight_prd_r     <= prd;
                inflight_prd_v_r   <= prd_v;
                inflight_brdest_r  <= payload_next_pc;
                inflight_fifonum_r <= rob_fifonum;
            end
            if (ctrl_restore && inflight_valid_r && fifoid_gt(inflight_fifonum_r, flnum)) begin
                inflight_valid_r <= 1'b0;
            end
            if (div_resp_valid && div_resp_ready) begin
                inflight_valid_r <= 1'b0;
            end
        end
    end

endmodule