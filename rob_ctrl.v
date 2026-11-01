module rob_ctrl#(
    parameter PORT_WIDTH    =   2,   // 指令提交端口数
    parameter RD_WIDTH      =   6,   // 读端口数（供发射/唤醒等读取 ROB 结果）
    parameter FU0WB_WIDTH   =   2,   // 功能单元 0 写回端口数
    parameter FU1WB_WIDTH   =   1,   // 功能单元 1 写回端口数
    parameter FU2WB_WIDTH   =   2,   // 功能单元 2 写回端口数
    parameter RT_WIDTH      =   2,   // 退休端口数
    parameter WK_WIDTH      =   2,    // 唤醒端口数
    parameter PRD_WIDTH = 6,//物理寄存器编号的位宽
    parameter LOG2_ROB_DEPTH = PRD_WIDTH//ROB 表项地址的位宽
    parameter ROB_DEPTH = 1<<LOG2_ROB_DEPTH,//ROB 表项数量
    parameter PC_WIDTH = 32,
    parameter DATA_WIDTH = 32,//操作数和执行结果的位宽
    parameter STBF_WIDTH = 3,//Store Buffer 条目编号的位宽
    parameter BR_INFO_WIDTH = 4,//分支判断条件编码的位宽
    parameter BRTYPE_WIDTH = 2,//分支类型编码的位宽
    parameter REG_INFO_WIDTH = 3,//寄存器写回数据来源的选择编码
    parameter ALU_INFO_WIDTH = 5,
    parameter TYPE_WIDTH = 3,//指令提交类型编码的位宽
    parameter FU_TYPE_WIDTH = 3,
    parameter ALU_SRCSEL_WIDTH = 2,
    parameter EXCPT_WIDTH = 4,
    parameter WSTRB_WIDTH = 4,//写入掩码的位宽
    parameter CSROP_WIDTH = 3,
    parameter CSRADDR_WIDTH = 12,
    parameter ZIMM_WIDTH = 5,
    parameter ERROR_CODE_WIDTH = 4
    )(
    input wire clk,
    input wire rst,

    input wire [PORT_WIDTH-1:0] have_inst,
    output wire [LOG2_ROB_DEPTH:0] rob_fifonum [PORT_WIDTH-1:0],
    input wire [LOG2_ROB_DEPTH-1:0] robaddr_i [PORT_WIDTH-1:0],
    
    input wire [PC_WIDTH-1:0] pc_i [PORT_WIDTH-1:0],
    input wire [PC_WIDTH-1:0] nxtpc_i [PORT_WIDTH-1:0],
    input wire [4:0] rd_i [PORT_WIDTH-1:0],
    input wire [PRD_WIDTH-1:0] prd_i [PORT_WIDTH-1:0],
    input wire [PRD_WIDTH-1:0] pprd_i [PORT_WIDTH-1:0],
    input wire [BRTYPE_WIDTH-1:0] brtype_i [PORT_WIDTH-1:0],
    input wire [PORT_WIDTH-1:0] is_ret_i,
    input wire [TYPE_WIDTH-1:0] wrtype_i [PORT_WIDTH-1:0],
    input wire [CSROP_WIDTH-1:0] csrop_i [PORT_WIDTH-1:0],
    input wire [ZIMM_WIDTH-1:0] zimm_i [PORT_WIDTH-1:0],
    input wire [CSRADDR_WIDTH-1:0] csraddr_i [PORT_WIDTH-1:0],
    input wire [PRD_WIDTH-1:0] prs1_i [PORT_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] exception_i [PORT_WIDTH-1:0],
    
     // ROB 读取接口
    input wire [LOG2_ROB_DEPTH-1:0] r_robaddr [RD_WIDTH-1:0],
    output wire [DATA_WIDTH-1:0] r_rddata [RD_WIDTH-1:0],
    output wire [RD_WIDTH-1:0] r_ready,
    
    // 写回接口
    input wire [PRD_WIDTH-1:0] wb0_prd [FU0WB_WIDTH-1:0],
    input wire [FU0WB_WIDTH-1:0] wb0_valid,
    input wire [FU0WB_WIDTH-1:0] wb0_regw,
    input wire [DATA_WIDTH-1:0] wb0_data [FU0WB_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] wb0_exception [FU0WB_WIDTH-1:0],
    input wire [DATA_WIDTH-1:0] wb0_brdest [FU0WB_WIDTH-1:0],
    
    input wire [PRD_WIDTH-1:0] wb1_prd [FU1WB_WIDTH-1:0],
    input wire [FU1WB_WIDTH-1:0] wb1_valid,
    input wire [FU1WB_WIDTH-1:0] wb1_regw,
    input wire [STBF_WIDTH-1:0] wb1_stbfid [FU1WB_WIDTH-1:0],
    input wire [DATA_WIDTH-1:0] wb1_data [FU1WB_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] wb1_exception [FU1WB_WIDTH-1:0],
    
    input wire [PRD_WIDTH-1:0] wb2_prd [FU2WB_WIDTH-1:0],
    input wire [FU2WB_WIDTH-1:0] wb2_valid,
    input wire [FU2WB_WIDTH-1:0] wb2_regw,
    input wire [DATA_WIDTH-1:0] wb2_data [FU2WB_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] wb2_exception [FU2WB_WIDTH-1:0],
    input wire [DATA_WIDTH-1:0] wb2_brdest [FU2WB_WIDTH-1:0],
    
    input wire wb3_valid,
    input wire wb3_regw,
    input wire [PRD_WIDTH-1:0] wb3_prd,
    input wire [DATA_WIDTH-1:0] wb3_data,
    input wire [EXCPT_WIDTH-1:0] wb3_exception,

    output wire csr_have_inst,
    output wire [PRD_WIDTH-1:0] csr_prd,
    output wire [DATA_WIDTH-1:0] csr_prs1_data,
    output wire [ZIMM_WIDTH-1:0] csr_zimm,
    output wire [CSRADDR_WIDTH-1:0] csr_addr,
    output wire [TYPE_WIDTH-1:0] csr_wrtype,
    output wire [CSROP_WIDTH-1:0] csr_csrtype,
    
    //回滚信号
    input wire [PRD_WIDTH:0] wk_flnum,
    output wire [WK_WIDTH-1:0] wk_valid,
    output wire [4:0] wk_rd [WK_WIDTH-1:0],
    output wire [PRD_WIDTH-1:0] wk_prd [WK_WIDTH-1:0],
    output wire [PRD_WIDTH-1:0] wk_pprd [WK_WIDTH-1:0],
    
    //retire/提交接口
    input wire [RT_WIDTH-1:0] rt_grant,
    output reg [RT_WIDTH-1:0] rt_ready,
    output wire [TYPE_WIDTH-1:0] rt_wrtype [RT_WIDTH-1:0],
    output wire [EXCPT_WIDTH-1:0] rt_exception [RT_WIDTH-1:0],
    
    output wire [PC_WIDTH-1:0] rt_pc [RT_WIDTH-1:0],
    output wire [BRTYPE_WIDTH-1:0] rt_brtype [RT_WIDTH-1:0],
    output wire [DATA_WIDTH-1:0] rt_brdest [RT_WIDTH-1:0],
    output wire [RT_WIDTH-1:0] rt_is_ret,
    output wire [4:0] rt_rd [RT_WIDTH-1:0],
    output wire [PRD_WIDTH-1:0] rt_prd [RT_WIDTH-1:0],
    output wire [DATA_WIDTH-1:0] rt_rddata [RT_WIDTH-1:0],
    output wire [STBF_WIDTH-1:0] rt_stbfid [RT_WIDTH-1:0],
    
    // Freelist 接口
    input wire [PORT_WIDTH-1:0] freelist_consume,
    output reg [PORT_WIDTH-1:0] freelist_valid,
    output wire [PRD_WIDTH-1:0] freelist_prd [PORT_WIDTH-1:0],

    input wire restart,// 从 ERROR 状态重启
    input wire ctrl_clear,
    input wire ctrl_restore,
    output reg ctrl_restoreend_req,// 恢复结束请求
    input wire ctrl_stall,
    output reg ctrl_stall_req,  // ROB FIFO 剩余空间不足时，向外请求暂停。
    output reg ctrl_error_req,
    output reg [ERROR_CODE_WIDTH-1:0] ctrl_error_code
);

localparam [TYPE_WIDTH-1:0] RETIRE_WR_ARF = 1;
localparam [2:0] NORMAL = 3'b000, RESTORE = 3'b001,
                 STALL = 3'b010, CLEAR = 3'b011, ERROR = 3'b100;


wire [LOG2_ROB_DEPTH-1:0] wk_robaddr [WK_WIDTH-1:0];
wire [WK_WIDTH-1:0] wk_ready;
wire [LOG2_ROB_DEPTH-1:0] rt_robaddr [RT_WIDTH-1:0];
wire [PRD_WIDTH-1:0] rt_pprd [RT_WIDTH-1:0];

wire rob_full;
wire rob_error;
reg [PORT_WIDTH-1:0] wrob_i;// 实际写入 ROB 的写使能
reg [WK_WIDTH-1:0] wk_cl;// 送给 u_rob 的回滚撤销使能
reg [PORT_WIDTH-1:0] fifo_we;// ROB FIFO 写使能
reg clear;
wire [PORT_WIDTH-1:0] freelist_valid_o;
reg [RT_WIDTH-1:0] rt_grant_i;// 状态控制后的实际提交授权
wire [RT_WIDTH-1:0] rt_ready_o;// u_rob 给出的表项有效且完成标志
wire [RT_WIDTH-1:0] rt_valid; // u_rob_fifo 给出的队列位置有效标志
reg hdsignal_walk;// 内部回滚模式使能
wire wk_end; // 本拍是最后一批回滚，或者指针已经到达边界

reg signal_error;

// 向 freelist 归还物理寄存器的有效位和编号。
wire [RT_WIDTH-1:0] insert;
wire [PRD_WIDTH-1:0] insert_pprd [RT_WIDTH-1:0];

//提交时，决定向 freelist 回收哪个物理寄存器
genvar fidx;
generate
    for(fidx=0; fidx<PORT_WIDTH; fidx=fidx+1) begin : gen_fidx
        assign insert[fidx] = rt_grant_i[fidx];// 只有真正允许提交的端口，才触发对应回收。
        assign insert_pprd[fidx] = (rt_wrtype[fidx]==RETIRE_WR_ARF) ? rt_pprd[fidx] : rt_robaddr[fidx];
    end
endgenerate

//错误诊断
always @(*) begin
    signal_error = 1'b0;//关闭了错误触发。
    ctrl_error_code = {1'b0, signal_isnotvalid(have_inst), signal_isnotvalid(rt_grant), rob_error};
end

reg [2:0] currState;
reg [2:0] nextState;

function signal_isnotvalid;
    input [PORT_WIDTH-1:0] sig;
    reg is_valid;
    begin

    is_valid = ((sig & (sig + 1)) == 0);

    signal_isnotvalid = !is_valid;
    end
endfunction

//状态寄存器
always @ ( posedge clk or posedge rst ) begin
    if(rst) begin
        currState <= NORMAL;
    end else begin
        currState <= nextState;
    end
end

always @(*) begin
    nextState = NORMAL;
    case (currState)
        NORMAL: begin
            if(signal_error) begin
                nextState = ERROR;
            end else if(ctrl_clear) begin
                nextState = CLEAR;
            end else if(ctrl_restore && !wk_end) begin
                nextState = RESTORE;
            end else if(ctrl_stall) begin
                nextState = STALL;
            end else begin
                nextState = NORMAL;
            end
        end
        RESTORE: begin
            if(ctrl_clear) begin
                nextState = CLEAR;
            end else if(wk_end) begin
                if(ctrl_stall) begin
                    nextState = STALL;
                end else begin
                    nextState = NORMAL;
                end
            end else begin
                nextState = RESTORE;
            end
        end
        STALL: begin
            if(ctrl_clear) begin
                nextState = CLEAR;
            end else if(!ctrl_stall) begin
                nextState = NORMAL;
            end else begin
                nextState = STALL;
            end
        end
        CLEAR: begin
            nextState = NORMAL;
        end
        ERROR: begin
            if(restart) begin
                nextState = NORMAL;
            end else begin
                nextState = ERROR;
            end
        end
        default: nextState = NORMAL;
    endcase
end

always @(*) begin
    wrob_i  =   have_inst;//默认：有新指令就写入 ROB
    fifo_we =   have_inst;//将新指令加入顺序队列
    
    freelist_valid = freelist_valid_o;//告诉外部哪些空闲寄存器可用
    
    rt_grant_i     = rt_grant;//执行外部给出的提交授权
    rt_ready       = rt_ready_o & rt_valid;//告诉外部哪些指令准备好提交
    
    wk_cl   =   0;//不撤销 所有路的ROB 表项
    hdsignal_walk = 1'b0;//不回滚
    
    clear   =   1'b0;//不清空
    
    //默认不发暂停、错误、回滚结束通知
    ctrl_stall_req = 1'b0;
    ctrl_error_req = 1'b0;
    ctrl_restoreend_req = 1'b0;
    case (currState)
        NORMAL: begin
            if(signal_error) begin
                wrob_i          = 0;//不写rob
                fifo_we         = 0;//不写fifo
                rt_grant_i      = 0;//不提交
            end else if(ctrl_clear) begin
                wrob_i          = 0;
                fifo_we         = 0;
                clear           = 1'b1;
            end else if(ctrl_restore && !wk_end) begin
                wrob_i          = 0;
                fifo_we         = 0;
                rt_grant_i      = 0;
                hdsignal_walk   = 1'b1;
                wk_cl           = wk_valid;
            end else if(ctrl_restore && wk_end) begin
                wrob_i          = 0;
                fifo_we         = 0;
                rt_grant_i      = 0;
                hdsignal_walk   = 1'b1;
                wk_cl           = wk_valid;
                ctrl_restoreend_req = 1'b1;
            end else if(ctrl_stall) begin
                wrob_i          = 0;
                fifo_we         = 0;
            end else if(rob_full) begin
                wrob_i          = 0;
                fifo_we         = 0;
            end
        end
        RESTORE: begin
            if(ctrl_clear) begin
                wrob_i          = 0;
                fifo_we         = 0;
                clear           = 1'b1;
            end else begin
                wrob_i          = 0;
                fifo_we         = 0;
                rt_grant_i      = 0;
                hdsignal_walk   = 1'b1;
                wk_cl           = wk_valid;
                if(wk_end) begin
                    ctrl_restoreend_req = 1'b1;
                end
            end
            
        end
        STALL: begin
            if(ctrl_clear) begin
                wrob_i          = 0;
                fifo_we         = 0;
                clear           = 1'b1;
            end if(ctrl_stall) begin
                wrob_i          = 0;
                fifo_we         = 0;
            end
        end
        CLEAR: begin
            
        end
        ERROR: begin
            if(restart) begin
            end else begin
                wrob_i          = 0;
                fifo_we         = 0;
                rt_grant_i      = 0;
                ctrl_error_req  = 1'b1;
            end
        end
        default: begin
        end
    endcase
    if(rob_full) begin
        ctrl_stall_req  = 1'b1;
    end
end

rob #(
    .PORT_WIDTH(PORT_WIDTH),
    .RD_WIDTH(RD_WIDTH),
    .FU0WB_WIDTH(FU0WB_WIDTH),
    .FU1WB_WIDTH(FU1WB_WIDTH),
    .FU2WB_WIDTH(FU2WB_WIDTH),
    .RT_WIDTH(RT_WIDTH),
    .WK_WIDTH(WK_WIDTH),
    .PRD_WIDTH(PRD_WIDTH),
    .LOG2_ROB_DEPTH(LOG2_ROB_DEPTH),
    .ROB_DEPTH(ROB_DEPTH),
    .PC_WIDTH(PC_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .STBF_WIDTH(STBF_WIDTH),
    .BR_INFO_WIDTH(BR_INFO_WIDTH),
    .BRTYPE_WIDTH(BRTYPE_WIDTH),
    .REG_INFO_WIDTH(REG_INFO_WIDTH),
    .ALU_INFO_WIDTH(ALU_INFO_WIDTH),
    .TYPE_WIDTH(TYPE_WIDTH),
    .FU_TYPE_WIDTH(FU_TYPE_WIDTH),
    .ALU_SRCSEL_WIDTH(ALU_SRCSEL_WIDTH),
    .EXCPT_WIDTH(EXCPT_WIDTH),
    .WSTRB_WIDTH(WSTRB_WIDTH),
    .CSROP_WIDTH(CSROP_WIDTH),
    .CSRADDR_WIDTH(CSRADDR_WIDTH),
    .ZIMM_WIDTH(ZIMM_WIDTH),
    .ERROR_CODE_WIDTH(ERROR_CODE_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH)
) u_rob (
    .clk(clk),
    .rst(rst),
    .robaddr_i(robaddr_i),
    .wrob_i(wrob_i),
    .pc_i(pc_i),
    .nxtpc_i(nxtpc_i),
    .rd_i(rd_i),
    .prd_i(prd_i),
    .pprd_i(pprd_i),
    .brtype_i(brtype_i),
    .is_ret_i(is_ret_i),
    .wrtype_i(wrtype_i),
    .csrop_i(csrop_i),
    .zimm_i(zimm_i),
    .csraddr_i(csraddr_i),
    .prs1_i(prs1_i),
    .exception_i(exception_i),
    .r_robaddr(r_robaddr),
    .r_rddata(r_rddata),
    .r_ready(r_ready),
    .wk_robaddr(wk_robaddr),
    .wk_cl(wk_cl),
    .wk_ready(wk_ready),
    .wk_rd(wk_rd),
    .wk_prd(wk_prd),
    .wk_pprd(wk_pprd),
    .wb0_prd(wb0_prd),
    .wb0_valid(wb0_valid),
    .wb0_data(wb0_data),
    .wb0_regw(wb0_regw),
    .wb0_exception(wb0_exception),
    .wb0_brdest(wb0_brdest),
    .wb1_prd(wb1_prd),
    .wb1_valid(wb1_valid),
    .wb1_regw(wb1_regw),
    .wb1_data(wb1_data),
    .wb1_stbfid(wb1_stbfid),
    .wb1_exception(wb1_exception),
    .wb2_prd(wb2_prd),
    .wb2_valid(wb2_valid),
    .wb2_data(wb2_data),
    .wb2_regw(wb2_regw),
    .wb2_exception(wb2_exception),
    .wb2_brdest(wb2_brdest),
    .wb3_valid(wb3_valid),
    .wb3_regw(wb3_regw),
    .wb3_prd(wb3_prd),
    .wb3_data(wb3_data),
    .wb3_exception(wb3_exception),
    .csr_have_inst(csr_have_inst),
    .csr_prd(csr_prd),
    .csr_prs1_data(csr_prs1_data),
    .csr_zimm(csr_zimm),
    .csr_addr(csr_addr),
    .csr_wrtype(csr_wrtype),
    .csr_csrtype(csr_csrtype),
    .rt_robaddr(rt_robaddr),
    .rt_grant(rt_grant_i),
    .rt_ready(rt_ready_o),
    .rt_wrtype(rt_wrtype),
    .rt_exception(rt_exception),
    .rt_pc(rt_pc),
    .rt_brtype(rt_brtype),
    .rt_brdest(rt_brdest),
    .rt_is_ret(rt_is_ret),
    .rt_rd(rt_rd),
    .rt_prd(rt_prd),
    .rt_rddata(rt_rddata),
    .rt_stbfid(rt_stbfid),
    .rt_pprd(rt_pprd),
    .ctrl_clear(clear)
);

freelist #(
    .PORT_WIDTH(PORT_WIDTH),
    .RT_WIDTH(RT_WIDTH),
    .WK_WIDTH(WK_WIDTH),
    .PRD_WIDTH(PRD_WIDTH),
    .LOG2_ROB_DEPTH(LOG2_ROB_DEPTH),
    .ROB_DEPTH(ROB_DEPTH),
    .PC_WIDTH(PC_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .STBF_WIDTH(STBF_WIDTH),
    .BR_INFO_WIDTH(BR_INFO_WIDTH),
    .BRTYPE_WIDTH(BRTYPE_WIDTH),
    .REG_INFO_WIDTH(REG_INFO_WIDTH),
    .ALU_INFO_WIDTH(ALU_INFO_WIDTH),
    .TYPE_WIDTH(TYPE_WIDTH),
    .FU_TYPE_WIDTH(FU_TYPE_WIDTH),
    .ALU_SRCSEL_WIDTH(ALU_SRCSEL_WIDTH),
    .EXCPT_WIDTH(EXCPT_WIDTH),
    .WSTRB_WIDTH(WSTRB_WIDTH),
    .CSROP_WIDTH(CSROP_WIDTH),
    .CSRADDR_WIDTH(CSRADDR_WIDTH),
    .ZIMM_WIDTH(ZIMM_WIDTH),
    .ERROR_CODE_WIDTH(ERROR_CODE_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH)
) u_freelist (
    .clk(clk),
    .rst(rst),
    .rt_grant(insert),
    .rt_pprd(insert_pprd),
    .hdsignal_walk(hdsignal_walk),
    .wk_valid(wk_valid),
    .wk_prd(wk_prd),
    .freelist_consume(freelist_consume),
    .freelist_valid(freelist_valid_o),
    .freelist_prd(freelist_prd),
    .ctrl_clear(clear)
);

rob_fifo #(
    .PORT_WIDTH(PORT_WIDTH),
    .RT_WIDTH(RT_WIDTH),
    .WK_WIDTH(WK_WIDTH),
    .PRD_WIDTH(PRD_WIDTH),
    .LOG2_ROB_DEPTH(LOG2_ROB_DEPTH),
    .ROB_DEPTH(ROB_DEPTH),
    .PC_WIDTH(PC_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .STBF_WIDTH(STBF_WIDTH),
    .BR_INFO_WIDTH(BR_INFO_WIDTH),
    .BRTYPE_WIDTH(BRTYPE_WIDTH),
    .REG_INFO_WIDTH(REG_INFO_WIDTH),
    .ALU_INFO_WIDTH(ALU_INFO_WIDTH),
    .TYPE_WIDTH(TYPE_WIDTH),
    .FU_TYPE_WIDTH(FU_TYPE_WIDTH),
    .ALU_SRCSEL_WIDTH(ALU_SRCSEL_WIDTH),
    .EXCPT_WIDTH(EXCPT_WIDTH),
    .WSTRB_WIDTH(WSTRB_WIDTH),
    .CSROP_WIDTH(CSROP_WIDTH),
    .CSRADDR_WIDTH(CSRADDR_WIDTH),
    .ZIMM_WIDTH(ZIMM_WIDTH),
    .ERROR_CODE_WIDTH(ERROR_CODE_WIDTH),
    .PAYLOAD_WIDTH(PAYLOAD_WIDTH)
) u_rob_fifo (
    .clk(clk),
    .rst(rst),
    .we(fifo_we),
    .prd(prd_i),
    .rob_fifonum(rob_fifonum),
    .hdsignal_walk(hdsignal_walk),
    .wk_end(wk_end),
    .wk_flnum(wk_flnum),
    .wk_valid(wk_valid),
    .wk_prd(wk_robaddr),
    .rt_grant(rt_grant_i),
    .rt_prd(rt_robaddr),
    .rt_valid(rt_valid),
    .full(rob_full),
    .error(rob_error),
    .ctrl_clear(clear)
);


endmodule

