module rob #(
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
) (
    input wire clk,
    input wire rst,
    
    // 指令提交/写入端口：将译码后的指令信息写入 ROB 表项
    input wire [LOG2_ROB_DEPTH-1:0] robaddr_i [PORT_WIDTH-1:0],
    input wire [PORT_WIDTH-1:0] wrob_i,
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
    
    // 读端口：供其他单元按 ROB 地址读取执行结果
    input wire [LOG2_ROB_DEPTH-1:0] r_robaddr [RD_WIDTH-1:0],
    output reg [DATA_WIDTH-1:0] r_rddata [RD_WIDTH-1:0],
    output reg [RD_WIDTH-1:0] r_ready,
    
    // 回滚端口：输出 ROB 表项中的目的寄存器信息，用于回滚
    input wire [LOG2_ROB_DEPTH-1:0] wk_robaddr [WK_WIDTH-1:0],
    input wire [WK_WIDTH-1:0] wk_cl,
    output reg [WK_WIDTH-1:0] wk_ready,
    output reg [4:0] wk_rd [WK_WIDTH-1:0],
    output reg [PRD_WIDTH-1:0] wk_prd [WK_WIDTH-1:0],
    output reg [PRD_WIDTH-1:0] wk_pprd [WK_WIDTH-1:0],

    // 写回端口：功能单元写回执行结果
    //整数+乘法+除法
    input wire [PRD_WIDTH-1:0] wb0_prd [FU0WB_WIDTH-1:0],
    input wire [FU0WB_WIDTH-1:0] wb0_valid,//本路写回有效
    input wire [FU0WB_WIDTH-1:0] wb0_regw,// 需要写入寄存器结果
    input wire [DATA_WIDTH-1:0] wb0_data [FU0WB_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] wb0_exception [FU0WB_WIDTH-1:0],
    input wire [DATA_WIDTH-1:0] wb0_brdest [FU0WB_WIDTH-1:0],
    
    //访存
    input wire [PRD_WIDTH-1:0] wb1_prd [FU1WB_WIDTH-1:0],
    input wire [FU1WB_WIDTH-1:0] wb1_valid,
    input wire [FU1WB_WIDTH-1:0] wb1_regw,
    input wire [DATA_WIDTH-1:0] wb1_data [FU1WB_WIDTH-1:0],
    input wire [STBF_WIDTH-1:0] wb1_stbfid [FU1WB_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] wb1_exception [FU1WB_WIDTH-1:0],
    
    //biq
    input wire [PRD_WIDTH-1:0] wb2_prd [FU2WB_WIDTH-1:0],
    input wire [FU2WB_WIDTH-1:0] wb2_valid,
    input wire [FU2WB_WIDTH-1:0] wb2_regw,
    input wire [DATA_WIDTH-1:0] wb2_data [FU2WB_WIDTH-1:0],
    input wire [EXCPT_WIDTH-1:0] wb2_exception [FU2WB_WIDTH-1:0],
    input wire [DATA_WIDTH-1:0] wb2_brdest [FU2WB_WIDTH-1:0],
    
    //csr
    input wire wb3_valid,
    input wire wb3_regw,
    input wire [PRD_WIDTH-1:0] wb3_prd,
    input wire [DATA_WIDTH-1:0] wb3_data,
    input wire [EXCPT_WIDTH-1:0] wb3_exception,
    
    // CSR 查询端口：向 CSR 单元报告是否有待处理 CSR 指令及其操作数信息
    output reg csr_have_inst,
    output reg [PRD_WIDTH-1:0] csr_prd,
    output reg [DATA_WIDTH-1:0] csr_prs1_data,
    output reg [ZIMM_WIDTH-1:0] csr_zimm,
    output reg [CSRADDR_WIDTH-1:0] csr_addr,
    output reg [TYPE_WIDTH-1:0] csr_wrtype,
    output reg [CSROP_WIDTH-1:0] csr_csrtype,
    
    // 退休端口：按 ROB 地址读出退休所需信息
    input wire [LOG2_ROB_DEPTH-1:0] rt_robaddr [RT_WIDTH-1:0],
    input wire [RT_WIDTH-1:0] rt_grant,
    output reg [RT_WIDTH-1:0] rt_ready,
    output reg [TYPE_WIDTH-1:0] rt_wrtype [RT_WIDTH-1:0],
    output reg [EXCPT_WIDTH-1:0] rt_exception [RT_WIDTH-1:0],
    
    output reg [PC_WIDTH-1:0] rt_pc [RT_WIDTH-1:0],
    output reg [BRTYPE_WIDTH-1:0] rt_brtype [RT_WIDTH-1:0],
    output reg [DATA_WIDTH-1:0] rt_brdest [RT_WIDTH-1:0],
    output reg [RT_WIDTH-1:0] rt_is_ret,
    output reg [4:0] rt_rd [RT_WIDTH-1:0],
    output reg [PRD_WIDTH-1:0] rt_prd [RT_WIDTH-1:0],
    output reg [DATA_WIDTH-1:0] rt_rddata [RT_WIDTH-1:0],
    output reg [STBF_WIDTH-1:0] rt_stbfid [RT_WIDTH-1:0],// Store buffer ID
    output reg [PRD_WIDTH-1:0] rt_pprd [RT_WIDTH-1:0],

    input wire ctrl_clear);
    
    // pc, rd, prd, pprd, brtype, is_ret, wrtype, csrop, zimm, csraddr, prs1,
    // rddata, brdest, exception, stbfid, valid, complete
    reg  rob_valid [ROB_DEPTH-1:0];
    reg  rob_complete [ROB_DEPTH-1:0];
    reg [PC_WIDTH-1:0] rob_pc [ROB_DEPTH-1:0];
    reg [4:0] rob_rd [ROB_DEPTH-1:0];
    reg [PRD_WIDTH-1:0] rob_prd [ROB_DEPTH-1:0];
    reg [PRD_WIDTH-1:0] rob_pprd [ROB_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] rob_rddata [ROB_DEPTH-1:0];
    reg [BRTYPE_WIDTH-1:0] rob_brtype [ROB_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] rob_brdest [ROB_DEPTH-1:0];
    reg  rob_is_ret [ROB_DEPTH-1:0];
    reg [STBF_WIDTH-1:0] rob_stbfid [ROB_DEPTH-1:0];// Store buffer ID
    reg [EXCPT_WIDTH-1:0] rob_exception [ROB_DEPTH-1:0];
    reg [TYPE_WIDTH-1:0] rob_wrtype [ROB_DEPTH-1:0];
    reg [CSROP_WIDTH-1:0] rob_csrop [ROB_DEPTH-1:0];
    reg [ZIMM_WIDTH-1:0] rob_zimm [ROB_DEPTH-1:0];
    reg [CSRADDR_WIDTH-1:0] rob_csraddr [ROB_DEPTH-1:0];
    reg [PRD_WIDTH-1:0] rob_prs1 [ROB_DEPTH-1:0];
    
//写入译码信息
    always @( posedge clk ) begin
    integer i;
    if(rst) begin
        for(i=0; i<ROB_DEPTH; i=i+1) begin
            rob_pc[i]    <=  0;
            rob_rd[i]    <=  0;
            rob_prd[i]   <=  0;
            rob_pprd[i]  <=  0;
            rob_brtype[i]<=  0;
            rob_is_ret[i]<=  1'b0;
            rob_wrtype[i]<=  0;
            rob_csrop[i] <=  0;
            rob_zimm[i]  <=  0;
            rob_csraddr[i] <= 0;
            rob_prs1[i]  <=  0;
        end
    end
    else begin
        for(i= 0; i<PORT_WIDTH; i=i+1) begin
            if(wrob_i[i]) begin
                rob_pc[robaddr_i[i]]    <=  pc_i[i];
                rob_rd[robaddr_i[i]]    <=  rd_i[i];
                rob_prd[robaddr_i[i]]   <=  prd_i[i];
                rob_pprd[robaddr_i[i]]  <=  pprd_i[i];
                rob_brtype[robaddr_i[i]]<=  brtype_i[i];
                rob_is_ret[robaddr_i[i]]<=  is_ret_i[i];
                rob_wrtype[robaddr_i[i]]<=  wrtype_i[i];
                rob_csrop[robaddr_i[i]] <=  csrop_i[i];
                rob_zimm[robaddr_i[i]]  <=  zimm_i[i];
                rob_csraddr[robaddr_i[i]]<= csraddr_i[i];
                rob_prs1[robaddr_i[i]]  <=  prs1_i[i];
            end
        end
    end
end

//写入/更新执行结果相关字段
    always @( posedge clk ) begin 
    integer i;
    if(rst) begin
        for(i= 0; i<ROB_DEPTH; i=i+1) begin
            rob_rddata[i] <= 0;
            rob_brdest[i] <= 0;
            rob_exception[i] <= EXCPT_NOEX;
            rob_stbfid[i] <= 0;
        end
    end
    else begin
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(wrob_i[i]) begin
                rob_exception[robaddr_i[i]] <= exception_i[i];
                rob_brdest[robaddr_i[i]]    <= nxtpc_i[i];
            end
        end
        for(i= 0; i<FU0WB_WIDTH; i=i+1) begin
            if(wb0_valid[i] && wb0_regw[i]) begin
                rob_rddata[wb0_prd[i]]  <=  wb0_data[i];
            end
            if(wb0_valid[i]) begin
                rob_exception[wb0_prd[i]]<= wb0_exception[i];
            end
        end
        for(i= 0; i<FU1WB_WIDTH; i=i+1) begin
            if(wb1_valid[i] && wb1_regw[i]) begin
                rob_rddata[wb1_prd[i]]   <=  wb1_data[i];
            end
            if(wb1_valid[i]) begin
                rob_stbfid[wb1_prd[i]]   <=  wb1_stbfid[i];
                rob_exception[wb1_prd[i]]<= wb1_exception[i];
            end
        end
        for(i= 0; i<FU2WB_WIDTH; i=i+1) begin
            if(wb2_valid[i] && wb2_regw[i]) begin
                rob_rddata[wb2_prd[i]]  <=  wb2_data[i];
            end
            if(wb2_valid[i]) begin
                rob_brdest[wb2_prd[i]]  <=  wb2_brdest[i];
                rob_exception[wb2_prd[i]]<= wb2_exception[i];
            end
        end
            if(wb3_valid && wb3_regw) begin
                rob_rddata[wb3_prd] <= wb3_data;
            end
            if(wb3_valid) begin
                rob_exception[wb3_prd] <= wb3_exception;
            end
    end
end

//valid 位管理
always @( posedge clk or posedge rst) begin 
    integer i;
    if(rst) begin
        for(i=0; i<ROB_DEPTH; i=i+1) begin
            rob_valid[i] <= 1'b0;
        end
    end else if(ctrl_clear) begin
        for(i=0; i<ROB_DEPTH; i=i+1) begin
            rob_valid[i] <= 1'b0;
        end
    end else begin
        for(i= 0; i<PORT_WIDTH; i=i+1) begin
            if(wrob_i[i]) begin
                rob_valid[robaddr_i[i]] <=  1'b1;
            end
        end
        for(i= 0; i<WK_WIDTH; i=i+1) begin
            if(wk_cl[i]) begin
                rob_valid[wk_robaddr[i]] <= 1'b0;
            end
        end
        for(i= 0; i<RT_WIDTH; i=i+1) begin
            if(rt_grant[i] && (rt_wrtype[i]==RETIRE_WR_ARF)) begin
                rob_valid[rt_pprd[i]] <= 1'b0;
            end
        end
    end
end

//complete 位管理:判断这个物理寄存器编号对应的数据是否可用
always @( posedge clk or posedge rst) begin
    integer i;
    if(rst) begin
        for(i= 0; i<32; i=i+1) begin
            rob_complete[i] <= 1'b1;//把 32 个架构寄存器映射到前 32 个物理寄存器
        end
        for(i= 32; i<ROB_DEPTH; i=i+1) begin
            rob_complete[i] <= 1'b0;
        end
    end
    else begin
        for(i= 0; i<PORT_WIDTH; i=i+1) begin
            if(wrob_i[i]) begin
                rob_complete[robaddr_i[i]] <=  1'b0;
            end
        end
        for(i= 0; i < PORT_WIDTH; i=i+1) begin
            if(wrob_i[i] && (exception_i[i] != EXCPT_NOEX) ) begin
                rob_complete[robaddr_i[i]] <=  1'b1;
            end
        end
        for(i= 0; i<FU0WB_WIDTH; i=i+1) begin
            if(wb0_valid[i]) begin
                rob_complete[wb0_prd[i]]   <=  1'b1;
            end
        end
        for(i= 0; i<FU1WB_WIDTH; i=i+1) begin
            if(wb1_valid[i]) begin
                rob_complete[wb1_prd[i]]   <=  1'b1;
            end
        end
        for(i= 0; i<FU2WB_WIDTH; i=i+1) begin
            if(wb2_valid[i]) begin
                rob_complete[wb2_prd[i]]   <=  1'b1;
            end
        end
            if(wb3_valid) begin
                rob_complete[wb3_prd]   <=  1'b1;
            end
        for(i= 0; i<RT_WIDTH; i=i+1) begin
            if(rt_grant[i] && (rt_wrtype[i]==RETIRE_WR_ARF)) begin
                rob_complete[rt_pprd[i]] <= 1'b0;
            end
        end
    end
end

// 将各表项的 complete 位汇总为向量，便于调试/后续使用
wire [ROB_DEPTH-1:0] complete_vec;
genvar dbidx;//指示rob条目
generate
    for(dbidx=0; dbidx<ROB_DEPTH; dbidx=dbidx+1) begin 
        assign complete_vec[dbidx]  =   rob_complete[dbidx];
    end
endgenerate

//读端口组合逻辑
genvar r_index;//指示读端口
generate
    for(r_index = 0; r_index<RD_WIDTH; r_index=r_index+1) begin 
        always @* begin 
    integer i;
            r_rddata[r_index]   =   rob_rddata[r_robaddr[r_index]];
            r_ready[r_index]    =   rob_complete[r_robaddr[r_index]];
            
            //旁路
            for(i=0; i<FU0WB_WIDTH; i=i+1) begin
                if(wb0_valid[i] && wb0_regw[i] && (wb0_prd[i] == r_robaddr[r_index])) begin
                    r_rddata[r_index] = wb0_data[i];
                    r_ready[r_index]  = 1'b1;
                end
            end
            for(i=0; i<FU1WB_WIDTH; i=i+1) begin
                if(wb1_valid[i] && wb1_regw[i] && (wb1_prd[i] == r_robaddr[r_index])) begin
                    r_rddata[r_index] = wb1_data[i];
                    r_ready[r_index]  = 1'b1;
                end
            end
            for(i=0; i<FU2WB_WIDTH; i=i+1) begin
                if(wb2_valid[i] && wb2_regw[i] && (wb2_prd[i] == r_robaddr[r_index])) begin
                    r_rddata[r_index] = wb2_data[i];
                    r_ready[r_index]  = 1'b1;
                end
            end
                if(wb3_valid && wb3_regw && (wb3_prd == r_robaddr[r_index])) begin
                    r_rddata[r_index] = wb3_data;
                    r_ready[r_index]  = 1'b1;
                end
        end
    end
endgenerate

// 回滚端口组合逻辑
genvar wk_index;//指示回滚端口
generate
    for(wk_index = 0; wk_index<WK_WIDTH; wk_index=wk_index+1) begin 
        always @* begin
            wk_ready[wk_index]  =   rob_valid[wk_robaddr[wk_index]];
            wk_rd[wk_index]     =   rob_rd[wk_robaddr[wk_index]];
            wk_prd[wk_index]    =   rob_prd[wk_robaddr[wk_index]];
            wk_pprd[wk_index]   =   rob_pprd[wk_robaddr[wk_index]];
        end
    end
endgenerate

// 退休端口调试信号
reg [RT_WIDTH-1:0] debug_rt_valid;
reg [RT_WIDTH-1:0] debug_rt_complete;

// 退休端口组合逻辑
genvar rt_index;
generate
    for(rt_index = 0; rt_index<RT_WIDTH; rt_index=rt_index+1) begin 
        always @* begin
            rt_ready[rt_index]      =   rob_complete[rt_robaddr[rt_index]] && rob_valid[rt_robaddr[rt_index]];
            rt_wrtype[rt_index]     =   rob_wrtype[rt_robaddr[rt_index]];
            rt_exception[rt_index]  =   rob_exception[rt_robaddr[rt_index]];
            rt_pc[rt_index]         =   rob_pc[rt_robaddr[rt_index]];
            rt_brtype[rt_index]     =   rob_brtype[rt_robaddr[rt_index]];
            rt_brdest[rt_index]     =   rob_brdest[rt_robaddr[rt_index]];
            rt_is_ret[rt_index]     =   rob_is_ret[rt_robaddr[rt_index]];
            rt_rd[rt_index]         =   rob_rd[rt_robaddr[rt_index]];
            rt_prd[rt_index]        =   rob_prd[rt_robaddr[rt_index]];
            rt_rddata[rt_index]     =   rob_rddata[rt_robaddr[rt_index]];
            rt_stbfid[rt_index]     =   rob_stbfid[rt_robaddr[rt_index]];
            rt_pprd[rt_index]       =   rob_pprd[rt_robaddr[rt_index]];

            debug_rt_valid[rt_index]    =   rob_valid[rt_robaddr[rt_index]];
            debug_rt_complete[rt_index] =   rob_complete[rt_robaddr[rt_index]];
        end
    end
endgenerate

// CSR 查询组合逻辑：检查最旧的指令是不是尚未执行完成的 CSR 指令
always @* begin
    csr_have_inst   =   rob_valid[rt_robaddr[0]] && (rob_csrop[rt_robaddr[0]] != CSROP_NCSR) && (!rob_complete[rt_robaddr[0]]);
    csr_prd         =   rob_prd[rt_robaddr[0]];
    csr_prs1_data   =   rob_rddata[rob_prs1[rt_robaddr[0]]];
    csr_zimm        =   rob_zimm[rt_robaddr[0]];
    csr_addr        =   rob_csraddr[rt_robaddr[0]];
    csr_wrtype      =   rob_wrtype[rt_robaddr[0]];
    csr_csrtype     =   rob_csrop[rt_robaddr[0]];
end


endmodule

