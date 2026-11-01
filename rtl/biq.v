module biq #(
    parameter integer IS2_EXCPT_WIDTH = 4,
    parameter integer IS2_ALU_SRCSEL_WIDTH = 2,
    parameter integer IS2_TYPE_WIDTH = 3,
    parameter integer IS2_BRTYPE_WIDTH = 2,
    parameter integer IS2_BR_INFO_WIDTH = 4,
    parameter integer IS2_PC_WIDTH = 32,
    parameter integer IS2_PRD_WIDTH = 6,
    parameter integer IS2_PRF_IDX_W = IS2_PRD_WIDTH,
    parameter integer IS2_AGE_W = IS2_PRD_WIDTH+1,
    parameter integer IS2_RS_ENTRY_W = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+IS2_AGE_W+86,
    parameter integer IS2_DATA_WIDTH = 32,
    parameter integer WB_PORT_NUM = 4,
    parameter integer PORT_WIDTH = 2,
    parameter integer BIQ_BITS = 3
) (
    input  wire clk,
    input  wire rst,
    input  wire rob_stall_i,

    input  wire [PORT_WIDTH-1:0] disp_valid_i,
    input  wire [PORT_WIDTH-1:0] disp_valid_raw_i,
    input  wire [IS2_RS_ENTRY_W-1:0] disp_entry_i [PORT_WIDTH-1:0],
    input  wire [PORT_WIDTH-1:0] disp_prs1_rdy_i,
    input  wire [PORT_WIDTH-1:0] disp_prs2_rdy_i,
    input  wire [IS2_DATA_WIDTH-1:0] disp_prs1_data_i [PORT_WIDTH-1:0],
    input  wire [IS2_DATA_WIDTH-1:0] disp_prs2_data_i [PORT_WIDTH-1:0],

    input  wire [WB_PORT_NUM-1:0] wb_valid_i, // 各写回端口的有效信号。
    input  wire [IS2_PRD_WIDTH-1:0] wb_prd_i [WB_PORT_NUM-1:0],
    input  wire [IS2_DATA_WIDTH-1:0] wb_data_i [WB_PORT_NUM-1:0],

    output wire [PORT_WIDTH-1:0] wb2_valid,// 结果输出
    output wire [PORT_WIDTH-1:0] wb2_regw,
    output wire [IS2_PRD_WIDTH-1:0] wb2_prd [PORT_WIDTH-1:0],
    output wire [IS2_PRD_WIDTH:0] wb2_rob_fifonum [PORT_WIDTH-1:0],
    output wire [IS2_EXCPT_WIDTH-1:0] wb2_exception [PORT_WIDTH-1:0],
    output wire [IS2_PC_WIDTH-1:0] wb2_brdest [PORT_WIDTH-1:0],
    output wire [IS2_DATA_WIDTH-1:0] wb2_data [PORT_WIDTH-1:0],
    output wire [IS2_PC_WIDTH-1:0] wb2_pc [PORT_WIDTH-1:0],
    output wire [IS2_BRTYPE_WIDTH-1:0] wb2_brtype [PORT_WIDTH-1:0],
    output wire [PORT_WIDTH-1:0] wb2_isret,
    output wire [4:0] wb2_rd [PORT_WIDTH-1:0],// 架构目的寄存器编号。

    output reg rs_full_o,

    input  wire ctrl_clear,
    output reg ctrl_restore_req, // 寄存后的分支预测错误恢复请求。
    output reg [IS2_PC_WIDTH-1:0] nxtpc_flush,// 恢复时应采用的实际下一条 PC。
    output reg [IS2_PRD_WIDTH:0] flush_id
    );

// 固定位序与操作编码属于内部常量，不再作为外部可覆盖参数。
localparam integer IS2_RS_CONTROL_PRS1_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+2*IS2_PRF_IDX_W+86;
localparam integer IS2_RS_CONTROL_PRS1_W = IS2_PRF_IDX_W;
localparam integer IS2_RS_CONTROL_PRS2_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+IS2_PRF_IDX_W+85;
localparam integer IS2_RS_CONTROL_PRS2_W = IS2_PRF_IDX_W;
localparam integer IS2_RS_CONTROL_PRS1_V_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+2*IS2_PRF_IDX_W+85;
localparam integer IS2_RS_CONTROL_PRS2_V_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+IS2_PRF_IDX_W+84;
localparam integer IS2_RS_PAYLOAD_RAM_BRANCH_INFO_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+75;
localparam integer IS2_RS_PAYLOAD_RAM_BRANCH_INFO_W = IS2_BR_INFO_WIDTH;
localparam integer IS2_EQ = 0;
localparam integer IS2_NE = 1;
localparam integer IS2_LTU = 2;
localparam integer IS2_GEU = 3;
localparam integer IS2_LT = 6;
localparam integer IS2_GE = 7;
localparam integer IS2_RS_PAYLOAD_RAM_BRANCH_TYPE_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+75;
localparam integer IS2_RS_PAYLOAD_RAM_BRANCH_TYPE_W = IS2_BRTYPE_WIDTH;
localparam integer IS2_NBR = 0;
localparam integer IS2_MBR_DIRECT = 1;
localparam integer IS2_MBR_INDIRECT = 3;
localparam integer IS2_CBR_DIRECT = 2;
localparam integer IS2_RS_PAYLOAD_RAM_ALU_SRC1_LSB = IS2_EXCPT_WIDTH+IS2_ALU_SRCSEL_WIDTH+53;
localparam integer IS2_RS_PAYLOAD_RAM_ALU_SRC1_W = IS2_ALU_SRCSEL_WIDTH;
localparam integer IS2_SRC1SEL_REGDATA = 0;
localparam integer IS2_SRC1SEL_PC = 1;
localparam integer IS2_RS_PAYLOAD_RAM_PC_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_PC_WIDTH+78;
localparam integer IS2_RS_PAYLOAD_RAM_PC_W = IS2_PC_WIDTH;
localparam integer IS2_RS_PAYLOAD_RAM_ALU_SRC2_LSB = IS2_EXCPT_WIDTH+53;
localparam integer IS2_RS_PAYLOAD_RAM_ALU_SRC2_W = IS2_ALU_SRCSEL_WIDTH;
localparam integer IS2_SRC2SEL_REGDATA = 0;
localparam integer IS2_SRC2SEL_EXTEND = 1;
localparam integer IS2_RS_PAYLOAD_RAM_EXTEND_LSB = IS2_EXCPT_WIDTH+21;
localparam integer IS2_RS_PAYLOAD_RAM_EXTEND_W = 32;
localparam integer IS2_RS_PAYLOAD_RAM_NEXT_PC_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+78;
localparam integer IS2_RS_PAYLOAD_RAM_NEXT_PC_W = IS2_PC_WIDTH;
localparam integer IS2_RS_PAYLOAD_RAM_RTTYPE_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+75;
localparam integer IS2_RS_PAYLOAD_RAM_RTTYPE_W = IS2_TYPE_WIDTH;
localparam integer IS2_RETIRE_WR_ARF = 1;
localparam integer IS2_RS_PAYLOAD_RAM_RD_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+78;
localparam integer IS2_RS_PAYLOAD_RAM_RD_W = 5;
localparam integer IS2_EXCPT_INVALID_CALCULATE = 3;
localparam integer IS2_EXCPT_BRWRONG = 1;
localparam integer IS2_EXCPT_NOEX = 0;
localparam integer IS2_RS_CONTROL_ROB_IDX_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+86;
localparam integer IS2_RS_CONTROL_ROB_IDX_W = IS2_AGE_W;
localparam integer IS2_RS_CONTROL_PRD_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+2*IS2_PC_WIDTH+84;
localparam integer IS2_RS_CONTROL_PRD_W = IS2_PRF_IDX_W;
localparam integer IS2_RS_PAYLOAD_RAM_IS_RET_LSB = IS2_EXCPT_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+64;
localparam integer IS2_RS_PAYLOAD_RAM_IS_RET_W = 1;


// 总体派遣接口保留，在边界提取源寄存器有效位。
wire [PORT_WIDTH-1:0] disp_prs1_v;
wire [PORT_WIDTH-1:0] disp_prs2_v;
genvar soa_disp;
generate
    for(soa_disp=0;soa_disp<PORT_WIDTH;soa_disp=soa_disp+1) begin : g_soa_disp
        assign disp_prs1_v[soa_disp] = disp_entry_i[soa_disp][IS2_RS_CONTROL_PRS1_V_LSB];
        assign disp_prs2_v[soa_disp] = disp_entry_i[soa_disp][IS2_RS_CONTROL_PRS2_V_LSB];
    end
endgenerate

function integer count_ports;
    input [PORT_WIDTH-1:0] bits_i;
    integer p;
    begin
        count_ports = 0;
        for (p=0; p<PORT_WIDTH; p=p+1)
            if (bits_i[p] == 1'b1) count_ports = count_ports + 1;
    end
endfunction

localparam BIQ_DEPTH = 1<<BIQ_BITS;

function biq_fifoid_gt(
    input [BIQ_BITS:0]     a,
    input [BIQ_BITS:0]     b
);
    biq_fifoid_gt = ( (a[BIQ_BITS] == b[BIQ_BITS]) ?
                      (a[BIQ_BITS-1:0] > b[BIQ_BITS-1:0]) :
                      (a[BIQ_BITS-1:0] < b[BIQ_BITS-1:0]) );
    
endfunction

reg [BIQ_BITS:0] head_ptr;
reg [BIQ_BITS:0] tail_ptr;
wire [BIQ_BITS:0] diff;// 两个扩展指针相减得到占用数量。
wire [BIQ_BITS-1:0] head_addr [PORT_WIDTH-1:0];// 每个派遣端口对应的实际写地址。
wire [BIQ_BITS-1:0] tail_addr [PORT_WIDTH-1:0];// 每个出队端口对应的实际读地址。

// SoA 存储：每个字段独立成数组，同一个下标对应同一条指令。
reg [IS2_PRF_IDX_W-1:0] prs1_q [BIQ_DEPTH-1:0];
reg [IS2_PRF_IDX_W-1:0] prs2_q [BIQ_DEPTH-1:0];
reg [IS2_BR_INFO_WIDTH-1:0] payload_branch_info_q [BIQ_DEPTH-1:0];
reg [IS2_BRTYPE_WIDTH-1:0] payload_branch_type_q [BIQ_DEPTH-1:0];
reg [IS2_ALU_SRCSEL_WIDTH-1:0] payload_alu_src1_q [BIQ_DEPTH-1:0];
reg [IS2_PC_WIDTH-1:0] payload_pc_q [BIQ_DEPTH-1:0];
reg [IS2_ALU_SRCSEL_WIDTH-1:0] payload_alu_src2_q [BIQ_DEPTH-1:0];
reg [32-1:0] payload_extend_q [BIQ_DEPTH-1:0];
reg [IS2_PC_WIDTH-1:0] payload_next_pc_q [BIQ_DEPTH-1:0];
reg [IS2_TYPE_WIDTH-1:0] payload_rttype_q [BIQ_DEPTH-1:0];
reg [5-1:0] payload_rd_q [BIQ_DEPTH-1:0];
reg [IS2_AGE_W-1:0] rob_idx_q [BIQ_DEPTH-1:0];
reg [IS2_PRF_IDX_W-1:0] prd_q [BIQ_DEPTH-1:0];
reg [1-1:0] payload_is_ret_q [BIQ_DEPTH-1:0];

// 每个条目的生命周期状态：
//   valid   ：条目当前占用队列。
//   complete：组合状态，操作数均就绪且条目有效。
//   handled ：已经在时钟沿记录为处理过。
//   issued  ：已经向 wb2 输出过，等待从队首释放。
reg [BIQ_DEPTH-1:0] entry_valid;
reg [BIQ_DEPTH-1:0] entry_valid_next;

reg [BIQ_DEPTH-1:0] entry_complete;
reg [BIQ_DEPTH-1:0] entry_handled;
reg [BIQ_DEPTH-1:0] entry_handled_next;

reg [BIQ_DEPTH-1:0] entry_issued;
reg [BIQ_DEPTH-1:0] entry_issued_next;

reg [IS2_DATA_WIDTH-1:0] entry_prs1_data [BIQ_DEPTH-1:0];
reg [BIQ_DEPTH-1:0] entry_prs1_v;

reg [IS2_DATA_WIDTH-1:0] entry_prs2_data [BIQ_DEPTH-1:0];
reg [BIQ_DEPTH-1:0] entry_prs2_v;

//// 各条目的组合执行结果。
reg [IS2_DATA_WIDTH-1:0] entry_data [BIQ_DEPTH-1:0];
reg [BIQ_DEPTH-1:0] entry_regw;
reg [IS2_EXCPT_WIDTH-1:0] entry_exception [BIQ_DEPTH-1:0];
reg [IS2_DATA_WIDTH-1:0] entry_brdest [BIQ_DEPTH-1:0];
reg [BIQ_DEPTH-1:0] entry_brwrong;

reg flush;
reg [BIQ_BITS:0] head_ptr_fl;// flush 后的新写指针：错误分支的下一个位置。
// 当前选择的错误分支 FIFO 编号，包含环绕位。
reg [BIQ_BITS:0] flush_addr;
reg [BIQ_BITS:0] flush_addr_nxt;
reg [PORT_WIDTH-1:0] fifo_out;// 实际允许释放的连续队首条目标志。

// 按“从最老到最新”的逻辑顺序重排后的状态向量。
wire [BIQ_DEPTH-1:0] valid_vec;
wire [BIQ_DEPTH-1:0] complete_vec;
wire [BIQ_DEPTH-1:0] handled_vec;
wire [BIQ_DEPTH-1:0] issued_vec;
wire [BIQ_DEPTH-1:0] brwrong_vec;

// 逻辑位置到扩展 FIFO 编号的映射。
wire [BIQ_BITS:0] addr_vec [BIQ_DEPTH-1:0];

// 各结果输出端口的候选条目及有效信号。
wire [PORT_WIDTH-1:0] addr_choose_valid;
wire [BIQ_BITS:0] addr_choose [PORT_WIDTH-1:0];
reg [BIQ_BITS:0] disp_need;// 本周期原始派遣请求需要的条目数。

assign diff = head_ptr - tail_ptr;// 在正常占用约束下，指针差值就是当前占用条目数。

always @(*) begin 
    disp_need = count_ports(disp_valid_raw_i);
end

always @(*) begin 
        rs_full_o = diff > ({1'b1,{BIQ_BITS{1'b0}}} - disp_need);
end

genvar nidx;
generate
    for (nidx = 0; nidx<PORT_WIDTH ; nidx=nidx+1 ) begin
        assign  head_addr[nidx] =   head_ptr + count_ports(disp_valid_i[nidx:0]) - {{BIQ_BITS{1'b0}},1'b1};
        assign  tail_addr[nidx] =   tail_ptr + nidx[BIQ_BITS-1:0];
    end
endgenerate

wire [PORT_WIDTH-1:0] fifo_out_tmp;//该条目是否已经可以释放
generate
    for(nidx=0; nidx<PORT_WIDTH; nidx=nidx+1) begin
    // 已有效占用且已输出过结果的条目，具备释放条件。
        assign fifo_out_tmp[nidx] = entry_valid[tail_addr[nidx][BIQ_BITS-1:0]] && entry_issued[tail_addr[nidx][BIQ_BITS-1:0]];
    end
endgenerate

always @(*) begin 
    integer i;
    fifo_out[0] = fifo_out_tmp[0];//第0条，即队首
    for (i=1; i<PORT_WIDTH; i=i+1) begin
        if(~fifo_out_tmp[i]) begin//按从队首到队尾的顺序出队，遇到第一条不能出队的指令，后面的指令都不能出队。
            fifo_out[i] = 1'b0;
        end else begin
            fifo_out[i] = fifo_out[i-1];//前一条为0，则这一条也为0
        end
    end
end

always @( posedge clk or posedge rst ) begin
    if(rst) begin
        head_ptr <= 0;
    end else begin 
        if(ctrl_clear) begin
            head_ptr <= 0;
        end else if(flush) begin
            head_ptr <= head_ptr_fl;
        end else begin
            head_ptr <= head_ptr + count_ports(disp_valid_i);
        end
    end
end

always @( posedge clk or posedge rst ) begin 
    if(rst) begin
        tail_ptr <= 0;
    end else begin
        if(ctrl_clear) begin
            tail_ptr <= 0;
        end else begin
            tail_ptr <= tail_ptr + count_ports(fifo_out);
        end
    end
end

//条目状态寄存器
always @( posedge clk or posedge rst ) begin 
    if(rst) begin
        entry_valid <= 0;
        entry_handled <= 0;
        entry_issued <= 0;
    end else begin
        if(ctrl_clear) begin
            entry_valid <= 0;
            entry_handled <= 0;
            entry_issued <= 0;
        end else begin
            entry_valid <= entry_valid_next;
            entry_handled <= entry_handled_next;
            entry_issued <= entry_issued_next;
        end
    end
end

// 条目有效状态的组合下一状态。
always @(*) begin
    integer i;
    entry_valid_next = entry_valid;
    for (i=0; i<PORT_WIDTH; i=i+1) begin
        if(disp_valid_i[i]) begin
            entry_valid_next[head_addr[i][BIQ_BITS-1:0]] = 1'b1;
        end
    end
    for (i=0; i<PORT_WIDTH; i=i+1) begin
        if(fifo_out[i]) begin
            entry_valid_next[tail_addr[i][BIQ_BITS-1:0]] = 1'b0;
        end
    end
    for (i=0; i<BIQ_DEPTH; i=i+1) begin
        if(flush && biq_fifoid_gt(addr_vec[i], flush_addr)) begin
            entry_valid_next[addr_vec[i][BIQ_BITS-1:0]] = 1'b0;
        end
    end
end

always @(*) begin 
    integer i;
    entry_handled_next = entry_handled;
    for (i=0; i<PORT_WIDTH; i=i+1) begin
        if(disp_valid_i[i]) begin
            entry_handled_next[head_addr[i][BIQ_BITS-1:0]] = 1'b0;
        end
    end
    
    for (i=0; i<BIQ_DEPTH; i=i+1) begin
        if(entry_prs1_v[i] && entry_prs2_v[i] && entry_valid[i]) begin//当前寄存器状态
            entry_handled_next[i] = 1'b1;
        end
    end
    
end

always @(*) begin 
    integer i;
    entry_issued_next = entry_issued;
    for (i=0; i<PORT_WIDTH; i=i+1) begin
        if(addr_choose_valid[i]) begin
            entry_issued_next[addr_choose[i][BIQ_BITS-1:0]] = 1'b1;
        end
    end
    for (i=0; i<PORT_WIDTH; i=i+1) begin
        if(fifo_out[i]) begin
            entry_issued_next[tail_addr[i][BIQ_BITS-1:0]]   = 1'b0;
        end
    end
    for (i=0; i<BIQ_DEPTH; i=i+1) begin
        if(flush && biq_fifoid_gt(addr_vec[i], flush_addr)) begin
            entry_issued_next[addr_vec[i][BIQ_BITS-1:0]] = 1'b0;
        end
    end
end

always @( posedge clk or posedge rst ) begin : proc_11
    integer i, j;
    if(rst) begin
        for (i=0; i<BIQ_DEPTH; i=i+1) begin
            prs1_q[i] <= 0;
                prs2_q[i] <= 0;
                payload_branch_info_q[i] <= 0;
                payload_branch_type_q[i] <= 0;
                payload_alu_src1_q[i] <= 0;
                payload_pc_q[i] <= 0;
                payload_alu_src2_q[i] <= 0;
                payload_extend_q[i] <= 0;
                payload_next_pc_q[i] <= 0;
                payload_rttype_q[i] <= 0;
                payload_rd_q[i] <= 0;
                rob_idx_q[i] <= 0;
                prd_q[i] <= 0;
                payload_is_ret_q[i] <= 0;
            entry_prs1_data[i]  <= 0;
            entry_prs1_v[i]     <= 0;
            entry_prs2_data[i]  <= 0;
            entry_prs2_v[i]     <= 0;
        end
    end else begin
        for (i=0; i<BIQ_DEPTH; i=i+1) begin
            for (j=0; j<WB_PORT_NUM; j=j+1) begin
                //唤醒
                if((prs1_q[i] == wb_prd_i[j]) && wb_valid_i[j]) begin
                    entry_prs1_v[i]     <= 1'b1;
                    entry_prs1_data[i]  <= wb_data_i[j];
                end
            end
            for (j=0; j<WB_PORT_NUM; j=j+1) begin
                if((prs2_q[i] == wb_prd_i[j]) && wb_valid_i[j]) begin
                    entry_prs2_v[i]     <= 1'b1;
                    entry_prs2_data[i]  <= wb_data_i[j];
                end
            end
        end
    
        for (i=0; i<PORT_WIDTH; i=i+1) begin
            if(disp_valid_i[i]) begin
                prs1_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_CONTROL_PRS1_LSB +: IS2_RS_CONTROL_PRS1_W];
                prs2_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_CONTROL_PRS2_LSB +: IS2_RS_CONTROL_PRS2_W];
                payload_branch_info_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_BRANCH_INFO_LSB +: IS2_RS_PAYLOAD_RAM_BRANCH_INFO_W];
                payload_branch_type_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_BRANCH_TYPE_LSB +: IS2_RS_PAYLOAD_RAM_BRANCH_TYPE_W];
                payload_alu_src1_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_ALU_SRC1_LSB +: IS2_RS_PAYLOAD_RAM_ALU_SRC1_W];
                payload_pc_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_PC_LSB +: IS2_RS_PAYLOAD_RAM_PC_W];
                payload_alu_src2_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_ALU_SRC2_LSB +: IS2_RS_PAYLOAD_RAM_ALU_SRC2_W];
                payload_extend_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_EXTEND_LSB +: IS2_RS_PAYLOAD_RAM_EXTEND_W];
                payload_next_pc_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_NEXT_PC_LSB +: IS2_RS_PAYLOAD_RAM_NEXT_PC_W];
                payload_rttype_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_RTTYPE_LSB +: IS2_RS_PAYLOAD_RAM_RTTYPE_W];
                payload_rd_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_RD_LSB +: IS2_RS_PAYLOAD_RAM_RD_W];
                rob_idx_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_CONTROL_ROB_IDX_LSB +: IS2_RS_CONTROL_ROB_IDX_W];
                prd_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_CONTROL_PRD_LSB +: IS2_RS_CONTROL_PRD_W];
                payload_is_ret_q[head_addr[i][BIQ_BITS-1:0]] <= disp_entry_i[i][IS2_RS_PAYLOAD_RAM_IS_RET_LSB +: IS2_RS_PAYLOAD_RAM_IS_RET_W];
                entry_prs1_data[head_addr[i][BIQ_BITS-1:0]]  <= disp_prs1_data_i[i];
                entry_prs1_v[head_addr[i][BIQ_BITS-1:0]]     <= ~((~disp_prs1_rdy_i[i]) && disp_prs1_v[i]);
                entry_prs2_data[head_addr[i][BIQ_BITS-1:0]]  <= disp_prs2_data_i[i];
                entry_prs2_v[head_addr[i][BIQ_BITS-1:0]]     <= ~((~disp_prs2_rdy_i[i]) && disp_prs2_v[i]);
            end
        end
    end
end

generate
    for (nidx = 0; nidx<BIQ_DEPTH ; nidx=nidx+1 ) begin
        
         // 无符号源操作数。
        wire [IS2_DATA_WIDTH-1:0] src1;
        wire [IS2_DATA_WIDTH-1:0] src2;
         // 有符号
        wire signed [IS2_DATA_WIDTH-1:0]s_src1;
        wire signed [IS2_DATA_WIDTH-1:0]s_src2;

        assign src1    =   entry_prs1_data[nidx];
        assign src2    =   entry_prs2_data[nidx];
        assign s_src1  =   $signed(src1);
        assign s_src2  =   $signed(src2);

        reg res_eq; // 两个操作数相等。
        reg res_lts;// 源 1 有符号小于源 2。
        reg res_ltu; // 源 1 无符号小于源 2。
        reg br_taken;// 最终是否发生跳转。
        reg btype_taken;// 条件分支的比较条件是否成立。
        always @(*) begin 
            res_eq  =   src1   == src2;
            res_lts =   s_src1 <  s_src2;
            res_ltu =   src1   <  src2;
        end
        
        always @(*) begin 
            case(payload_branch_info_q[nidx])
                IS2_EQ:  btype_taken = res_eq;
                IS2_NE:  btype_taken = ~res_eq;
                IS2_LTU: btype_taken = res_ltu;
                IS2_GEU: btype_taken = ~res_ltu;
                IS2_LT:  btype_taken = res_lts;
                IS2_GE:  btype_taken = ~res_lts;
                default: btype_taken = 1'b0;
            endcase
        end

        always @(*) begin 
            if(payload_branch_type_q[nidx]==IS2_NBR) begin
                br_taken = 1'b0; // 非分支类型不跳转。
            end else if(payload_branch_type_q[nidx]==IS2_MBR_DIRECT || payload_branch_type_q[nidx]==IS2_MBR_INDIRECT) begin
                br_taken = 1'b1; // 无条件直接/间接跳转一定采用目标地址。
            end else if(payload_branch_type_q[nidx]==IS2_CBR_DIRECT) begin
                br_taken = btype_taken;// 条件分支由比较结果决定。
            end else begin
                br_taken = 1'b0;
            end
        end
        
        // 目标地址加法器的两个输入和计算结果。
        reg [IS2_DATA_WIDTH-1:0] oprand_src1;
        reg [IS2_DATA_WIDTH-1:0] oprand_src2;
        reg [IS2_DATA_WIDTH-1:0] br_target;

        always @(*) begin 
            case(payload_alu_src1_q[nidx])
                IS2_SRC1SEL_REGDATA :   oprand_src1 = src1;
                IS2_SRC1SEL_PC      :   oprand_src1 = payload_pc_q[nidx];
                default         :   oprand_src1 = 0;
            endcase
        end

        always @(*) begin 
            case(payload_alu_src2_q[nidx])
                IS2_SRC2SEL_REGDATA :   oprand_src2 = src2;
                IS2_SRC2SEL_EXTEND  :   oprand_src2 = payload_extend_q[nidx];
                default         :   oprand_src2 = 0;
            endcase
        end

        always @(*) begin 
            br_target = oprand_src1 + oprand_src2;
            if(payload_branch_type_q[nidx] == IS2_MBR_INDIRECT) begin
                br_target[0] = 1'b0;// 间接跳转将目标地址最低位清零。
            end
            entry_brdest[nidx]  = br_taken ? br_target : (payload_pc_q[nidx]+4);// 实际下一条 PC：
            entry_brwrong[nidx] = (entry_brdest[nidx] != payload_next_pc_q[nidx]) && entry_valid[nidx];
            entry_data[nidx]    = payload_pc_q[nidx] + 4;// 对需要链接地址的跳转指令，写回数据为 PC+4----jal、jalr
            entry_regw[nidx]    = (payload_rttype_q[nidx] == IS2_RETIRE_WR_ARF) && (payload_rd_q[nidx] != 5'b0);//开启寄存器写回。
            
            // 异常编码优先级：
            // 非分支类型 > 分支预测错误 > 无异常。
            if(payload_branch_type_q[nidx]==IS2_NBR) begin
                entry_exception[nidx]   =   IS2_EXCPT_INVALID_CALCULATE;
            end else if(entry_brwrong[nidx]) begin
                entry_exception[nidx]   =   IS2_EXCPT_BRWRONG;
            end else begin
                entry_exception[nidx]   =   IS2_EXCPT_NOEX;
            end
        end

        always @(*) begin 
            entry_complete[nidx] = entry_prs1_v[nidx] && entry_prs2_v[nidx] && entry_valid[nidx];//// 条目有效且两个源均无需继续等待，即认为计算条件满足。
        end

    end
endgenerate


//将环形物理存储映射为从最老到最新的逻辑顺序
generate
    for(nidx = 0; nidx < BIQ_DEPTH; nidx=nidx+1) begin
        assign addr_vec[nidx]       =   tail_ptr + nidx;//tail_ptr指向的会是最老一条指令
        assign valid_vec[nidx]      =   entry_valid[addr_vec[nidx][BIQ_BITS-1:0]];//条目是否有效
        assign handled_vec[nidx]    =   entry_handled[addr_vec[nidx][BIQ_BITS-1:0]];//是否已经处理过
        assign issued_vec[nidx]     =   entry_issued[addr_vec[nidx][BIQ_BITS-1:0]];//是否已经输出过结果
        assign complete_vec[nidx]   =   entry_prs1_v[addr_vec[nidx][BIQ_BITS-1:0]] && entry_prs2_v[addr_vec[nidx][BIQ_BITS-1:0]]
                                         && entry_valid[addr_vec[nidx][BIQ_BITS-1:0]];//条目有效，并且两个源操作数都已就绪
        assign brwrong_vec[nidx]    =   entry_brwrong[addr_vec[nidx][BIQ_BITS-1:0]];//实际下一条 PC 是否与预测不同
    end
endgenerate

// 预测错误分支选择与内部 flush
reg [IS2_PRD_WIDTH:0] flush_id_nxt;
//在所有已经就绪、尚未处理的预测错误分支中，选出最老的一条，并取出它的 BIQ 编号和 ROB 编号
always @(*) begin 
    integer i;
    flush_addr_nxt = 0;// 被选中指令在 BIQ 中的扩展编号，包含环绕位。
    flush_id_nxt    =   0; // 同一条指令在 ROB 中的编号。
    for (i=BIQ_DEPTH-1; i>=0; i=i-1) begin//从年轻的开始，遍历完就是最老的
        if(brwrong_vec[i] && complete_vec[i] && (~handled_vec[i])) begin
            flush_addr_nxt = addr_vec[i];
            flush_id_nxt=   rob_idx_q[addr_vec[i][BIQ_BITS-1:0]];
        end
    end
end

always @(*) begin 
    integer i;
    flush = 1'b0;
    flush_addr  =   flush_addr_nxt;
    head_ptr_fl =   flush_addr_nxt + 1;
    for (i=BIQ_DEPTH-1; i>=0; i=i-1) begin
        if(brwrong_vec[i] && complete_vec[i] && (~handled_vec[i])) begin
            flush   =   1'b1;
        end
    end
end

//对外输出寄存后的恢复信息
always @(posedge clk or posedge rst) begin : proc_21
    if(rst) begin
        ctrl_restore_req <= 1'b0;
        nxtpc_flush      <= 0;
        flush_id         <= 0;
    end else if(ctrl_clear) begin
        ctrl_restore_req <= 1'b0;
        nxtpc_flush      <= 0;
        flush_id         <= 0;
    end else begin
        ctrl_restore_req <= flush;
        nxtpc_flush      <= entry_brdest[flush_addr[BIQ_BITS-1:0]];
        flush_id         <= flush_id_nxt;
    end
end

// 结果输出候选选择
reg [BIQ_DEPTH-1:0] masked_commit;//允许向 wb2 输出执行结果
always @(*) begin 
    masked_commit = entry_valid & entry_handled & (~entry_issued);//为每条槽位生成“允许输出”标志。
end

generate
    for(nidx = 0; nidx < PORT_WIDTH; nidx=nidx+1) begin
        assign addr_choose_valid[nidx] = masked_commit[addr_vec[nidx][BIQ_BITS-1:0]];
        assign addr_choose[nidx] = addr_vec[nidx];
    end
endgenerate

generate
    for(nidx = 0; nidx < PORT_WIDTH; nidx=nidx+1) begin
        assign wb2_valid[nidx]  =   addr_choose_valid[nidx];
        assign wb2_prd[nidx]    =   prd_q[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_rob_fifonum[nidx]    =   rob_idx_q[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_regw[nidx]   =   entry_regw[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_exception[nidx]  =   entry_exception[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_data[nidx]   =   entry_data[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_brdest[nidx] =   entry_brdest[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_pc[nidx]     =   payload_pc_q[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_brtype[nidx] =   payload_branch_type_q[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_isret[nidx]  =   payload_is_ret_q[addr_choose[nidx][BIQ_BITS-1:0]];
        assign wb2_rd[nidx]     =   payload_rd_q[addr_choose[nidx][BIQ_BITS-1:0]];
    end
endgenerate

endmodule
