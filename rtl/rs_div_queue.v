module rs_div_queue #(
    // 本模块所用的常量、位宽及字段位置，不依赖外部宏定义。
    parameter integer IS2_ISSUE_WIDTH = 3, // 默认值：3
    parameter integer IS2_IQ_DEPTH = 1<<IS2_ISSUE_WIDTH, // 默认值：8
    parameter integer IS2_PRD_WIDTH = 6, // 默认值：6
    parameter integer IS2_PRF_IDX_W = IS2_PRD_WIDTH, // 默认值：6
    parameter integer IS2_AGE_W = IS2_PRD_WIDTH+1, // 默认值：7
    parameter integer IS2_EXCPT_WIDTH = 4, // 默认值：4
    parameter integer IS2_ZIMM_WIDTH = 5, // 默认值：5
    parameter integer IS2_CSRADDR_WIDTH = 12, // 默认值：12
    parameter integer IS2_CSROP_WIDTH = 3, // 默认值：3
    parameter integer IS2_ALU_SRCSEL_WIDTH = 2, // 默认值：2
    parameter integer IS2_ALU_INFO_WIDTH = 5, // 默认值：5
    parameter integer IS2_WSTRB_WIDTH = 4, // 默认值：4
    parameter integer IS2_REG_INFO_WIDTH = 3, // 默认值：3
    parameter integer IS2_TYPE_WIDTH = 3, // 默认值：3
    parameter integer IS2_BRTYPE_WIDTH = 2, // 默认值：2
    parameter integer IS2_BR_INFO_WIDTH = 4, // 默认值：4
    parameter integer IS2_FU_TYPE_WIDTH = 3, // 默认值：3
    parameter integer IS2_PC_WIDTH = 32, // 默认值：32
    parameter integer IS2_RS_ENTRY_W = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+IS2_AGE_W+47), // 默认值：192
    parameter integer IS2_CLEAR = 3'b011, // 默认值：3
    parameter integer IS2_NORMAL = 3'b000, // 默认值：0
    parameter integer IS2_RESTORE = 3'b001, // 默认值：1
    parameter integer IS2_STALL = 3'b010, // 默认值：2
    parameter integer IS2_ERROR = 3'b100, // 默认值：4
    parameter integer IS2_RS_PAYLOAD_RAM_FUTYPE_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+39), // 默认值：92
    parameter integer IS2_RS_PAYLOAD_RAM_FUTYPE_W = IS2_FU_TYPE_WIDTH, // 默认值：3
    parameter integer IS2_FU_DIV = 7, // 默认值：7
    parameter integer IS2_RS_CONTROL_PRS1_V_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+2*IS2_PRF_IDX_W+46), // 默认值：178
    parameter integer IS2_RS_CONTROL_PRS1_V_W = 1, // 默认值：1
    parameter integer IS2_RS_CONTROL_PRS2_V_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+IS2_PRF_IDX_W+45), // 默认值：171
    parameter integer IS2_RS_CONTROL_PRS2_V_W = 1, // 默认值：1
    parameter integer IS2_RS_CONTROL_ROB_IDX_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+47), // 默认值：185
    parameter integer IS2_RS_CONTROL_ROB_IDX_W = IS2_AGE_W, // 默认值：7
    parameter integer IS2_RS_V_LSB = 0, // 默认值：0
    parameter integer IS2_RS_V_W = 1, // 默认值：1
    parameter integer IS2_RS_CONTROL_PRS1_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+2*IS2_PRF_IDX_W+47), // 默认值：179
    parameter integer IS2_RS_CONTROL_PRS1_W = IS2_PRF_IDX_W, // 默认值：6
    parameter integer IS2_RS_CONTROL_PRS2_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+IS2_PRF_IDX_W+46), // 默认值：172
    parameter integer IS2_RS_CONTROL_PRS2_W = IS2_PRF_IDX_W, // 默认值：6

    parameter integer ENTRY_NUM      = IS2_IQ_DEPTH,
    parameter integer WAKE_DELAY     = 3,
    parameter integer WB_PORT_NUM    = 4,
    parameter integer FU_NUM         = 5,
    parameter integer PRF_IDX_W      = IS2_PRF_IDX_W,
    parameter integer AGE_W          = IS2_AGE_W,
    parameter integer PORT_WIDTH     = 2,
    parameter integer ISSUE_W        = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM),
    parameter integer LSU_FU_IDX     = 2,
    parameter integer MUL_FU_IDX     = 3,
    parameter integer DIV_FU_IDX     = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire flush_i,
    input  wire walk_i,
    input  wire [AGE_W-1:0] restore_age_bound_i,
    input  wire rob_stall_i,
    
    input  wire [PORT_WIDTH-1:0] disp_valid_i,// 各分派端口的实际有效信号。
    input  wire [PORT_WIDTH-1:0] disp_valid_raw_i,// 各分派端口的原始需求有效信号，用于需求统计。
    input  wire [IS2_RS_ENTRY_W-1:0] disp_entry_i [PORT_WIDTH-1:0],
    input  wire [PORT_WIDTH-1:0] disp_prs1_rdy_i,
    input  wire [PORT_WIDTH-1:0] disp_prs2_rdy_i,
    
    output reg rs_full_o,
    
    input  wire [PRF_IDX_W-1:0] wb_prd_i [WB_PORT_NUM-1:0],
    input  wire [WB_PORT_NUM-1:0] wb_valid_i,
    
    input  wire [PRF_IDX_W-1:0] is_prd_i [FU_NUM-1:0], // 各 FU 发射的目的寄存器号
    input  wire [FU_NUM-1:0] is_valid_i,// 各 FU 发射有效
    
    input  wire fu_ready_i, // 下游 FU 可接收
    output reg issue_valid_o,// 本模块发射有效
    output reg [IS2_RS_ENTRY_W-1:0] issue_entry_o,// 发射指令打包数据
    output reg [ISSUE_W-1:0] is_iqid_o,// 发射的 IQ 索引
    input  wire [ISSUE_W-1:0] resp_isid_i,// 响应返回的 IQ 索引
    input  wire resp_valid_i,// 响应有效
    input  wire resp_issued_i // 响应表示该条目已被发射
    );

   // 本队列内部位宽
localparam integer ENTRY_IDX_W = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM); // 槽位编号位宽，默认3。
localparam integer COUNT_W     = $clog2(ENTRY_NUM + 1); // 数量计数位宽，默认4。

// 队列每个槽位的状态
wire [ENTRY_NUM-1:0] free_q; // 各槽位是否空闲，由valid_q取反得到。
reg [ENTRY_NUM-1:0] issued_q; // 各槽位是否已发射、等待反馈。
reg [WAKE_DELAY-1:0] prs1_ready_q [ENTRY_NUM-1:0]; // 每个槽位源1的延迟就绪向量，bit0参与当前就绪判断。
reg [WAKE_DELAY-1:0] prs2_ready_q [ENTRY_NUM-1:0]; // 每个槽位源2的延迟就绪向量。
reg [ENTRY_NUM-1:0] rdy_q; // 每条指令的两个源是否都满足就绪条件；组合信号。

// 送往年龄仲裁器的信号
reg [AGE_W-1:0] age_vec [ENTRY_NUM-1:0]; // 各槽位指令年龄。
reg [ENTRY_NUM-1:0] valid_vec; // 各槽位有效位的组合映射。
reg [ENTRY_NUM-1:0] issue_elig_vec; // 各条目是否允许参加发射选择。
wire [ENTRY_IDX_W-1:0] arb_issue_idx; // 仲裁器选中的槽位。
wire arb_issue_valid; // 是否选出了有效候选。

// 新指令分配信号：下标对应分派端口
reg [PORT_WIDTH-1:0] disp_match; // 实际分派的DIV类型及控制条件匹配。
reg [PORT_WIDTH-1:0] disp_need_match; // 基于原始分派需求的匹配。
reg [ENTRY_IDX_W-1:0] alloc_idx [PORT_WIDTH-1:0]; // 各分派端口找到的空槽编号。
reg [PORT_WIDTH-1:0] alloc_fire; // 各分派端口是否分配成功。
reg [COUNT_W-1:0] free_cnt; // 当前空闲数量。
reg [COUNT_W-1:0] disp_match_cnt; // 原始DIV需求数量；原实现未用于满判断。

// 本拍发射与后级反馈信号
wire [ENTRY_IDX_W-1:0] issue_idx; // 本拍准备发射的槽位，连接arb_issue_idx。
reg issue_fire; // 本拍确实发出指令。
wire issue_kill; // 本拍收到失败反馈，抑制新发射。
reg can_issue; // 最终发射条件。
wire [ENTRY_IDX_W-1:0] resp_idx; // 反馈槽位编号。

// 就绪更新临时变量：由原单一时序过程使用
reg [WAKE_DELAY-1:0] next_prs1; // 当前循环槽位源1的更新临时值。
reg [WAKE_DELAY-1:0] next_prs2; // 当前循环槽位源2的更新临时值。

// SoA字段位置
localparam integer SOA_PAYLOAD_W = 2*IS2_PC_WIDTH+IS2_FU_TYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_BRTYPE_WIDTH+IS2_TYPE_WIDTH+IS2_REG_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_CSROP_WIDTH+IS2_CSRADDR_WIDTH+IS2_ZIMM_WIDTH+IS2_EXCPT_WIDTH+43; // 默认163位。
localparam integer SOA_CONTROL_ROB_IDX_LSB = SOA_PAYLOAD_W+3*IS2_PRF_IDX_W+4;
localparam integer SOA_CONTROL_PRS1_LSB = SOA_PAYLOAD_W+2*IS2_PRF_IDX_W+4;
localparam integer SOA_CONTROL_PRS1_V_LSB = SOA_PAYLOAD_W+2*IS2_PRF_IDX_W+3;
localparam integer SOA_CONTROL_PRS2_LSB = SOA_PAYLOAD_W+IS2_PRF_IDX_W+3;
localparam integer SOA_CONTROL_PRS2_V_LSB = SOA_PAYLOAD_W+IS2_PRF_IDX_W+2;
localparam integer SOA_CONTROL_PRD_LSB = SOA_PAYLOAD_W+2;
localparam integer SOA_CONTROL_PRD_V_LSB = SOA_PAYLOAD_W+1;
localparam integer SOA_PAYLOAD_RAM_LSB = 1;
localparam integer SOA_V_LSB = 0;

// SoA指令存储：相同下标对应同一条指令
reg [IS2_AGE_W-1:0] rob_idx_q [ENTRY_NUM-1:0]; // 各指令ROB年龄。
reg [IS2_PRF_IDX_W-1:0] prs1_q [ENTRY_NUM-1:0]; // 源1物理寄存器编号。
reg [ENTRY_NUM-1:0] prs1_v_q; // 是否使用源1，区别于是否ready。
reg [IS2_PRF_IDX_W-1:0] prs2_q [ENTRY_NUM-1:0]; // 源2物理寄存器编号。
reg [ENTRY_NUM-1:0] prs2_v_q; // 是否使用源2。
reg [IS2_PRF_IDX_W-1:0] prd_q [ENTRY_NUM-1:0]; // 目的物理寄存器编号。
reg [ENTRY_NUM-1:0] prd_v_q; // 目的寄存器是否有效。
reg [SOA_PAYLOAD_W-1:0] payload_q [ENTRY_NUM-1:0]; // 指令执行信息。
reg [ENTRY_NUM-1:0] valid_q; // 各条目有效位。
wire [IS2_RS_ENTRY_W-1:0] issue_packed [ENTRY_NUM-1:0]; // 输出边界拼接的完整指令包，不增加存储副本。

// 队列控制状态
reg [2:0] state_d; // 下一状态。
reg [2:0] state_q; // 当前状态。


// 判断队列是否已满：先筛选DIV需求，再统计空闲并计算回压。
// 原判满条件仍为free_cnt < PORT_WIDTH。
assign free_q = ~valid_q;

always @(*) begin 
    integer i;
        for (i = 0; i < PORT_WIDTH; i=i+1) begin
            disp_match[i] = disp_valid_i[i]
                         && (disp_entry_i[i][IS2_RS_PAYLOAD_RAM_FUTYPE_LSB+IS2_RS_PAYLOAD_RAM_FUTYPE_W-1:IS2_RS_PAYLOAD_RAM_FUTYPE_LSB] == IS2_FU_DIV)
                         && !walk_i
                         && !rob_stall_i;
            disp_need_match[i] = disp_valid_raw_i[i]
                              && (disp_entry_i[i][IS2_RS_PAYLOAD_RAM_FUTYPE_LSB+IS2_RS_PAYLOAD_RAM_FUTYPE_W-1:IS2_RS_PAYLOAD_RAM_FUTYPE_LSB] == IS2_FU_DIV)
                              && !walk_i
                              && !rob_stall_i;
        end
    end

always @(*) begin 
    integer i;
        free_cnt = 0;
        for (i = 0; i < ENTRY_NUM; i=i+1) begin
            if (free_q[i]) begin
                free_cnt = free_cnt + {{(COUNT_W-1){1'b0}},1'b1};
            end
        end
    end

always @(*) begin 
    integer i;
        disp_match_cnt = 0;
        for (i = 0; i < PORT_WIDTH; i=i+1) begin
            if (disp_need_match[i]) begin
                disp_match_cnt = disp_match_cnt + {{(COUNT_W-1){1'b0}},1'b1};
            end
        end
        
        rs_full_o = (free_cnt < PORT_WIDTH);
    end

// 状态机控制：保留原状态寄存器和全部转移条件。
always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state_q <= IS2_CLEAR;
        end else begin
            state_q <= state_d;
        end
    end

always @(*) begin 
        state_d = state_q;
        case (state_q)
            IS2_NORMAL: begin
                if (flush_i) begin
                    state_d = IS2_CLEAR;
                end else if (walk_i) begin
                    state_d = IS2_RESTORE;
                end else if (rob_stall_i) begin
                    state_d = IS2_STALL;
                end
            end
            IS2_RESTORE: begin
                if (!walk_i) begin
                    state_d = IS2_NORMAL;
                end
            end
            IS2_STALL: begin
                if (flush_i) begin
                    state_d = IS2_CLEAR;
                end else if (!rob_stall_i) begin
                    state_d = IS2_NORMAL;
                end
            end
            IS2_CLEAR: begin
                if (walk_i) begin
                    state_d = IS2_RESTORE;
                end else begin
                    state_d = IS2_NORMAL;
                end
            end
            default: begin
                state_d = IS2_ERROR;
            end
        endcase
    end

// 为新指令分配槽位：各端口依次占用临时空闲表，避免重复分配。
always @(*) begin 
    integer i, j;
        reg [ENTRY_NUM-1:0] free_tmp;
        free_tmp = free_q;
        for (i = 0; i < PORT_WIDTH; i=i+1) begin
            alloc_fire[i] = 1'b0;
            alloc_idx[i]  = 0;
            if (disp_match[i] && !rs_full_o) begin
                for (j = 0; j < ENTRY_NUM; j=j+1) begin
                    if (!alloc_fire[i] && free_tmp[j]) begin
                        alloc_fire[i] = 1'b1;
                        alloc_idx[i]  = j[ENTRY_IDX_W-1:0];
                        free_tmp[j]   = 1'b0;
                    end
                end
            end
        end
    end

// 记录并更新两个源操作数的就绪状态。
// DIV保留单一时序过程遍历槽位，不改成ALU的generate结构。
// 以下先定义向量推进函数和DIV专用提前唤醒掩码。
// 默认3位掩码：普通通道111、LSU110、MUL100、DIV000。
function automatic reg [WAKE_DELAY-1:0] shift_ready
(input reg [WAKE_DELAY-1:0] ready_vec);
    integer t;
        reg [WAKE_DELAY-1:0] next_vec;
        begin
            next_vec = ready_vec;
            for (t = 0; t < WAKE_DELAY-1; t=t+1) begin
                next_vec[t] = ready_vec[t+1];
            end
            next_vec[WAKE_DELAY-1] = ready_vec[WAKE_DELAY-1];
            shift_ready = next_vec;
        end
    endfunction

function automatic reg [WAKE_DELAY-1:0] fu_wake_mask(input integer fu_idx);
        reg [WAKE_DELAY-1:0] mask;
        begin
            mask = {WAKE_DELAY{1'b1}};
            if (fu_idx == DIV_FU_IDX) begin
                mask = {WAKE_DELAY{1'b0}};
            end else if (fu_idx == MUL_FU_IDX) begin
                mask = 0;
                mask[WAKE_DELAY-1] = 1'b1;
            end else if (fu_idx == LSU_FU_IDX) begin
                mask = {WAKE_DELAY{1'b1}};
                mask[0] = 1'b0;
            end
            fu_wake_mask = mask;
        end
    endfunction

always @(posedge clk or negedge rst_n) begin 
    integer j, k, p;
        if (!rst_n || flush_i) begin
            for (j = 0; j < ENTRY_NUM; j=j+1) begin
                prs1_ready_q[j] <= 0;
                prs2_ready_q[j] <= 0;
            end
        end else begin
            for (j = 0; j < ENTRY_NUM; j=j+1) begin
                // 默认推进原就绪向量，保留最高位。
                next_prs1 = shift_ready(prs1_ready_q[j]);
                next_prs2 = shift_ready(prs2_ready_q[j]);
                // 原本空闲的槽位先清零旧就绪信息。
                if (!valid_q[j]) begin
                    next_prs1 = 0;
                    next_prs2 = 0;
                end
                // 入队命中当前槽位：按对应分派端口初始化源就绪状态。
                for (k = 0; k < PORT_WIDTH; k=k+1) begin
                    if (alloc_fire[k] && (j[ENTRY_IDX_W-1:0] == alloc_idx[k])) begin
                        next_prs1 = disp_prs1_rdy_i[k] ? {WAKE_DELAY{1'b1}} : {WAKE_DELAY{1'b0}};
                        next_prs2 = disp_prs2_rdy_i[k] ? {WAKE_DELAY{1'b1}} : {WAKE_DELAY{1'b0}};
                    end
                end
                if (valid_q[j]) begin
                    // 写回广播：标签匹配则置就绪。
                    for (p = 0; p < WB_PORT_NUM; p=p+1) begin
                        if (wb_valid_i[p]) begin
                            if (prs1_v_q[j] && (wb_prd_i[p] == prs1_q[j])) begin
                                next_prs1 = {WAKE_DELAY{1'b1}};
                            end
                            if (prs2_v_q[j] && (wb_prd_i[p] == prs2_q[j])) begin
                                next_prs2 = {WAKE_DELAY{1'b1}};
                            end
                        end
                    end
                end
                if (valid_q[j]) begin
                    // 提前唤醒广播：按DIV原有生产者通道规则设置掩码。
                    // 保留此处后置赋值对写回临时值的覆盖关系。
                    for (p = 0; p < FU_NUM; p=p+1) begin
                        if (is_valid_i[p]) begin
                            if (prs1_v_q[j] && (is_prd_i[p] == prs1_q[j])) begin
                                next_prs1 = fu_wake_mask(p);
                            end
                            if (prs2_v_q[j] && (is_prd_i[p] == prs2_q[j])) begin
                                next_prs2 = fu_wake_mask(p);
                            end
                        end
                    end
                end
                // 在时钟沿保存该槽位的两个源就绪向量。
                prs1_ready_q[j] <= next_prs1;
                prs2_ready_q[j] <= next_prs2;
            end
        end
    end

// 判断每条指令的源操作数是否都已就绪。
always @(*) begin 
    integer i;
        for (i = 0; i < ENTRY_NUM; i=i+1) begin
            rdy_q[i] = ((!prs1_v_q[i]) || prs1_ready_q[i][0])
                    && ((!prs2_v_q[i]) || prs2_ready_q[i][0]);
        end
    end

// 生成允许参加年龄仲裁的候选集合。
always @(*) begin : proc_9
    integer i;
        for (i = 0; i < ENTRY_NUM; i=i+1) begin
            age_vec[i]        = rob_idx_q[i];
            valid_vec[i]      = valid_q[i];
            issue_elig_vec[i] = valid_vec[i]
                             && !issued_q[i]
                             && ((state_q == IS2_NORMAL) || (state_q == IS2_STALL))
                             && rdy_q[i];
        end
    end

// 年龄仲裁：选择最老的候选指令。
age_matrix_arbiter #(
        .IS2_PRD_WIDTH(IS2_PRD_WIDTH),

        .ENTRY_NUM (ENTRY_NUM),
        .AGE_W     (AGE_W)
    ) u_age_matrix_arbiter (
        .valid_i   (issue_elig_vec),
        .age_i     (age_vec),
        .index_o   (arb_issue_idx),
        .valid_o   (arb_issue_valid)
    );

// 检查本拍能否发出，并输出指令。
// SoA字段仅在输出边界拼接，没有新增完整指令存储。
genvar soa_slot;
generate
    for (soa_slot=0; soa_slot<ENTRY_NUM; soa_slot=soa_slot+1) begin : g_pack_issue
        assign issue_packed[soa_slot] = {rob_idx_q[soa_slot], prs1_q[soa_slot], prs1_v_q[soa_slot], prs2_q[soa_slot], prs2_v_q[soa_slot], prd_q[soa_slot], prd_v_q[soa_slot], payload_q[soa_slot], valid_q[soa_slot]};
    end
endgenerate

assign issue_idx = arb_issue_idx;

always @(*) begin 
        issue_fire    = 1'b0;
        issue_valid_o = 1'b0;
        issue_entry_o = 0;
        can_issue     = 1'b0;
        is_iqid_o     = {{(ISSUE_W-ENTRY_IDX_W){1'b0}}, issue_idx};
        if (arb_issue_valid && fu_ready_i) begin
            can_issue = issue_elig_vec[arb_issue_idx] && !issue_kill && !walk_i && !flush_i;
            if (can_issue) begin
                issue_fire    = 1'b1;
                issue_valid_o = 1'b1;
                issue_entry_o = issue_packed[arb_issue_idx];
            end
        end
    end

// 处理反馈，并在时钟沿统一更新指令与调度状态。
assign issue_kill = resp_valid_i && !resp_issued_i;
assign resp_idx = resp_isid_i[ENTRY_IDX_W-1:0];

integer i;
always @(posedge clk or negedge rst_n) begin 
        // 更新优先级：复位 > 清空 > 恢复 > 正常更新。
        if (!rst_n) begin
            issued_q <= 0;
            for (i = 0; i < ENTRY_NUM; i=i+1) begin
                rob_idx_q[i] <= 0;
            prs1_q[i] <= 0;
            prs1_v_q[i] <= 0;
            prs2_q[i] <= 0;
            prs2_v_q[i] <= 0;
            prd_q[i] <= 0;
            prd_v_q[i] <= 0;
            payload_q[i] <= 0;
            valid_q[i] <= 0;
            end
        end else if (flush_i) begin
            // 全部清空：清有效位，让原数据失效。
            issued_q <= 0;
            for (i = 0; i < ENTRY_NUM; i=i+1) begin
                valid_q[i] <= 1'b0;
            end
        end else if (walk_i) begin
            // 恢复期间处理已有反馈，再删除恢复边界之后的年轻项。
            // 成功反馈释放条目；失败反馈清issued，保留指令重试。
            if (resp_valid_i) begin
                if (resp_issued_i) begin
                    valid_q[resp_idx] <= 1'b0;
                end else begin
                    issued_q[resp_idx]  <= 1'b0;
                end
            end
            for (i = 0; i < ENTRY_NUM; i=i+1) begin
                if (valid_q[i] && fifoid_gt(rob_idx_q[i], restore_age_bound_i)) begin
                    valid_q[i] <= 1'b0;
                    issued_q[i]  <= 1'b0;
                end
            end
        end else begin
            // 成功反馈释放条目；失败反馈清issued，保留指令重试。
            if (resp_valid_i) begin
                if (resp_issued_i) begin
                    valid_q[resp_idx] <= 1'b0;
                end else begin
                    issued_q[resp_idx]  <= 1'b0;
                end
            end
            // 保存各分派端口的新指令，保留原多路入队结构。
            for (i = 0; i < PORT_WIDTH; i=i+1) begin
                if (alloc_fire[i]) begin
                    rob_idx_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_ROB_IDX_LSB +: IS2_AGE_W];
                    prs1_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_PRS1_LSB +: IS2_PRF_IDX_W];
                    prs1_v_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_PRS1_V_LSB +: 1];
                    prs2_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_PRS2_LSB +: IS2_PRF_IDX_W];
                    prs2_v_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_PRS2_V_LSB +: 1];
                    prd_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_PRD_LSB +: IS2_PRF_IDX_W];
                    prd_v_q[alloc_idx[i]] <= disp_entry_i[i][SOA_CONTROL_PRD_V_LSB +: 1];
                    payload_q[alloc_idx[i]] <= disp_entry_i[i][SOA_PAYLOAD_RAM_LSB +: SOA_PAYLOAD_W];
                    valid_q[alloc_idx[i]] <= disp_entry_i[i][SOA_V_LSB +: 1];
                    valid_q[alloc_idx[i]] <= 1'b1;
                    issued_q[alloc_idx[i]]  <= 1'b0;
                end
            end
            // 发射后保留valid，等待后级成功反馈再释放。
            if (issue_fire) begin
                issued_q[issue_idx] <= 1'b1;
            end
        end
    end

// 环形ROB年龄比较：返回a是否比b年轻，用于恢复删除。
function fifoid_gt(
    input [IS2_PRD_WIDTH:0]     a,
    input [IS2_PRD_WIDTH:0]     b
);
    fifoid_gt = ( (a[IS2_PRD_WIDTH] == b[IS2_PRD_WIDTH]) ?
                      (a[IS2_PRD_WIDTH-1:0] > b[IS2_PRD_WIDTH-1:0]) :
                      (a[IS2_PRD_WIDTH-1:0] < b[IS2_PRD_WIDTH-1:0]) );
    
endfunction

endmodule
