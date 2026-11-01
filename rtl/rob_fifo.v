module rob_fifo #(
    parameter   PORT_WIDTH  =   2,
    parameter   RT_WIDTH    =   2,
    parameter   WK_WIDTH    =   2,
    parameter   PORT_WIDTH    =   2,   // 指令提交端口数
    parameter   RD_WIDTH      =   6,   // 读端口数（供发射/唤醒等读取 ROB 结果）
    parameter   FU0WB_WIDTH   =   2,   // 功能单元 0 写回端口数
    parameter   FU1WB_WIDTH   =   1,   // 功能单元 1 写回端口数
    parameter   FU2WB_WIDTH   =   2,   // 功能单元 2 写回端口数
    parameter   RT_WIDTH      =   2,   // 退休端口数
    parameter   WK_WIDTH      =   2,    // 唤醒端口数
    parameter   PRD_WIDTH = 6,//物理寄存器编号的位宽
    parameter   LOG2_ROB_DEPTH = PRD_WIDTH//ROB 表项地址的位宽
    parameter   ROB_DEPTH = 1<<LOG2_ROB_DEPTH,//ROB 表项数量
    parameter   PC_WIDTH = 32,
    parameter   DATA_WIDTH = 32,//操作数和执行结果的位宽
    parameter   STBF_WIDTH = 3,//Store Buffer 条目编号的位宽
    parameter   BR_INFO_WIDTH = 4,//分支判断条件编码的位宽
    parameter   BRTYPE_WIDTH = 2,//分支类型编码的位宽
    parameter   REG_INFO_WIDTH = 3,//寄存器写回数据来源的选择编码
    parameter   ALU_INFO_WIDTH = 5,
    parameter   TYPE_WIDTH = 3,//指令提交类型编码的位宽
    parameter   FU_TYPE_WIDTH = 3,
    parameter   ALU_SRCSEL_WIDTH = 2,
    parameter   EXCPT_WIDTH = 4,
    parameter   WSTRB_WIDTH = 4,//写入掩码的位宽
    parameter   CSROP_WIDTH = 3,
    parameter   CSRADDR_WIDTH = 12,
    parameter   ZIMM_WIDTH = 5,
    parameter   ERROR_CODE_WIDTH = 4
)(
    input wire clk,
    input wire rst,
    
    input wire [PORT_WIDTH-1:0] we,
    input wire [LOG2_ROB_DEPTH-1:0] prd [PORT_WIDTH-1:0],
    output reg [LOG2_ROB_DEPTH:0] rob_fifonum [PORT_WIDTH-1:0],
    
    input wire hdsignal_walk,// 回滚使能（高有效）
    output wire wk_end,// 回滚完成：所有需要撤销的条目都已 walk 完毕
    input wire [PRD_WIDTH:0] wk_flnum,
    output reg [WK_WIDTH-1:0] wk_valid,
    output reg [PRD_WIDTH-1:0] wk_prd [WK_WIDTH-1:0],
    
    input wire [RT_WIDTH-1:0] rt_grant,
    output reg [RT_WIDTH-1:0] rt_valid,
    output reg [PRD_WIDTH-1:0] rt_prd [RT_WIDTH-1:0],//每个退休端口读出的物理寄存器号
    
    input wire ctrl_clear,
    output wire full,
    output reg error 

);
    reg [LOG2_ROB_DEPTH:0] wk_endaddr;
    reg [LOG2_ROB_DEPTH:0] head_ptr;
    reg [LOG2_ROB_DEPTH:0] tail_ptr;
    wire [LOG2_ROB_DEPTH:0] diff;// 已分配但未退休的条目数
    wire [LOG2_ROB_DEPTH:0] available;// 剩余可分配空间
    wire [$clog2(PORT_WIDTH):0] we_cnt;// 当前周期有效分配端口数

    reg [LOG2_ROB_DEPTH:0] head_addr[PORT_WIDTH-1:0];
    reg [LOG2_ROB_DEPTH:0] tail_addr[RT_WIDTH-1:0];

    reg [LOG2_ROB_DEPTH:0] walk_addr[WK_WIDTH-1:0];
    reg [WK_WIDTH-1:0] walk_addrequal;// walk_addr[i] 是否恰等于 wk_endaddr
    wire walk_equal;// 任一 walk_addr 命中边界
    wire [$clog2(WK_WIDTH):0] wk_cnt;
    
    wire [$clog2(RT_WIDTH):0] rt_cnt;

    reg [LOG2_ROB_DEPTH-1:0] prd_mem[ROB_DEPTH-1:0];// 每个 ROB 条目对应的物理寄存器号
    reg [ROB_DEPTH-1:0] valid;
    reg [ROB_DEPTH-1:0] valid_nxt;
    
    
    assign we_cnt   =   count_ones(we);
    assign rt_cnt   =   count_ones(rt_grant);
    assign wk_cnt   =   count_ones(wk_valid);
    assign walk_equal =   |walk_addrequal;
    assign wk_end   =   walk_equal || (head_ptr==wk_endaddr);
    assign diff     =   head_ptr - tail_ptr;
    assign available=   rob_pointer(ROB_DEPTH) - diff;
    assign full     =   available < PORT_WIDTH;
    
    // 生成各 walk 端口的有效标志
    always@(*)begin
    if(hdsignal_walk)begin
        wk_valid= {WK_WIDTH{1'b0}};
        
        if(walk_equal==0 &&(head_ptr!=wk_endaddr))begin
            wk_valid={WK_WIDTH{1'b1};
            end else begin
            wk_valid[WK_WIDTH-1] = walk_addrequal[WK_WIDTH-1];
            for(i= WK_WIDTH-2; i>=0; i=i-1) begin
                wk_valid[i] = walk_addrequal[i] ? 1'b1 : wk_valid[i+1];
                 end
        end
        
    end else begin
        wk_valid = {WK_WIDTH{1'b0}};
    end
end

// 指针一致性检查
//最高位相同（同一圈）: 应满足 head 低位 >= tail 低位
//最高位不同（跨圈）  : 应满足 head 低位 <= tail 低位
always @* begin
    if(head_ptr[LOG2_ROB_DEPTH] == tail_ptr[LOG2_ROB_DEPTH]) 
        error = (head_ptr[LOG2_ROB_DEPTH-1:0] < tail_ptr[LOG2_ROB_DEPTH-1:0]);
    else
        error = (head_ptr[LOG2_ROB_DEPTH-1:0] > tail_ptr[LOG2_ROB_DEPTH-1:0]);
end

// 生成每个分配端口的 ROB 编号
genvar hidx;//指示哪个写入端口
generate
    for(hidx=0; hidx<PORT_WIDTH; hidx=hidx+1) begin : gen_hidx
        always @* begin
            head_addr[hidx] = head_ptr + hidx;
            rob_fifonum[hidx] = head_addr[hidx];
        end
    end
endgenerate

// 生成每个退休端口的地址与读出数据
genvar tidx;//指示哪个退休端口
generate
    for(tidx=0; tidx<RT_WIDTH; tidx=tidx+1) begin : gen_tidx
        always @* begin
            tail_addr[tidx] = tail_ptr + tidx;
            rt_prd[tidx]    = prd_mem[tail_addr[tidx][LOG2_ROB_DEPTH-1:0]];
            rt_valid[tidx]  = valid[tail_addr[tidx][LOG2_ROB_DEPTH-1:0]];
        end
    end
endgenerate

// 回滚结束地址
assign wk_endaddr=wk_flnum+1'b1;

// 生成每个 walk 端口的地址、边界匹配信号与读出数据
genvar wkidx;//指示哪个回退端口
generate
    for(wkidx=0; wkidx<WK_WIDTH; wkidx=wkidx+1) begin : gen_wkidx
        always @* begin
            walk_addr[wkidx] = head_ptr - wkidx - 1;
            walk_addrequal[wkidx] = (walk_addr[wkidx] == wk_endaddr);
            wk_prd[wkidx]    = prd_mem[walk_addr[wkidx][LOG2_ROB_DEPTH-1:0]];
        end
    end
endgenerate

// head_ptr 更新
always@(posedge clk or posedge rst)begin
    if(rst)
    head_ptr<=0;
    else if(ctrl_clear)
    head_ptr<=0;
    else if(hdsignal_walk)
    head_ptr<=head_ptr-wk_cnt;
    else if(|we) 
        head_ptr <= head_ptr + we_cnt;
end

//tail_ptr 更新
always@(posedge clk or posedge rst)begin
    if(rst)
    tail_ptr<=0;
    else if(ctrl_clear)
    tail_ptr<=0;
    else if(hdsignal_walk)
    tail_ptr<=tail_ptr;
    else 
    tail_ptr<=tail_ptr+rt_cnt;
end
    
// prd_mem 写入
always@(posedge clk or posedge rst)begin
    integer i;
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(we[i]) begin
            prd_mem[head_addr[i][LOG2_ROB_DEPTH-1:0]] <= prd[i];
        end
    end
end

//valid位
always @ ( posedge clk or posedge rst ) begin
    if(rst) begin
        valid <= 0;
    end else begin
        valid <= valid_nxt;
    end
end

//valid 位下一状态
always @(*) begin : 
    integer i;
    valid_nxt = valid;
    //分配
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(we[i]) begin
            valid_nxt[head_addr[i][LOG2_ROB_DEPTH-1:0]] = 1'b1;
        end
    end
    //walk撤销
    for(i=0; i<WK_WIDTH; i=i+1) begin
        if(wk_valid[i]) begin
            valid_nxt[walk_addr[i][LOG2_ROB_DEPTH-1:0]] = 1'b0;
        end
    end
    //退休
    for(i=0; i<RT_WIDTH; i=i+1) begin
        if(rt_grant[i]) begin
            valid_nxt[tail_addr[i][LOG2_ROB_DEPTH-1:0]] = 1'b0;
        end
    end
    //清空
    if(ctrl_clear) begin
        valid_nxt = 0;
    end
end
localparam COUNT_WIDTH = (PORT_WIDTH > RT_WIDTH) ?
    ((PORT_WIDTH > WK_WIDTH) ? PORT_WIDTH : WK_WIDTH) :
    ((RT_WIDTH > WK_WIDTH) ? RT_WIDTH : WK_WIDTH);
function integer count_ones;
    input [COUNT_WIDTH-1:0] bits;
    integer bit_index;
    begin
        count_ones = 0;
        for (bit_index = 0; bit_index < COUNT_WIDTH; bit_index = bit_index + 1)
            if (bits[bit_index] === 1'b1) count_ones = count_ones + 1;
    end
endfunction
function [LOG2_ROB_DEPTH+1-1:0] rob_pointer;
    input [31:0] value;
    begin
        rob_pointer = value[LOG2_ROB_DEPTH+1-1:0];
    end
endfunction

endmodule
