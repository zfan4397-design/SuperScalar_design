module rs_issue_queue #(
    parameter integer IS2_ISSUE_WIDTH = 3, 
    parameter integer IS2_IQ_DEPTH = 1<<IS2_ISSUE_WIDTH, //8
    parameter integer IS2_PRD_WIDTH = 6, 
    parameter integer IS2_PRF_IDX_W = IS2_PRD_WIDTH, 
    parameter integer IS2_AGE_W = IS2_PRD_WIDTH+1, 
    parameter integer IS2_EXCPT_WIDTH = 4, 
    parameter integer IS2_ZIMM_WIDTH = 5, 
    parameter integer IS2_CSRADDR_WIDTH = 12, 
    parameter integer IS2_CSROP_WIDTH = 3, 
    parameter integer IS2_ALU_SRCSEL_WIDTH = 2, 
    parameter integer IS2_ALU_INFO_WIDTH = 5, 
    parameter integer IS2_WSTRB_WIDTH = 4, 
    parameter integer IS2_REG_INFO_WIDTH = 3, 
    parameter integer IS2_TYPE_WIDTH = 3, 
    parameter integer IS2_BRTYPE_WIDTH = 2, 
    parameter integer IS2_BR_INFO_WIDTH = 4, 
    parameter integer IS2_FU_TYPE_WIDTH = 3, 
    parameter integer IS2_PC_WIDTH = 32, 
    parameter integer IS2_RS_ENTRY_W = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+IS2_AGE_W+47), //192
    parameter integer IS2_CLEAR = 3'b011, 
    parameter integer IS2_NORMAL = 3'b000, 
    parameter integer IS2_RESTORE = 3'b001, 
    parameter integer IS2_STALL = 3'b010, 
    parameter integer IS2_ERROR = 3'b100, 
    parameter integer IS2_RS_CONTROL_PRS1_V_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+2*IS2_PRF_IDX_W+46), //178
    parameter integer IS2_RS_CONTROL_PRS1_V_W = 1, 
    parameter integer IS2_RS_CONTROL_PRS2_V_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+IS2_PRF_IDX_W+45), //171
    parameter integer IS2_RS_CONTROL_PRS2_V_W = 1, 
    parameter integer IS2_RS_CONTROL_ROB_IDX_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+47), //185
    parameter integer IS2_RS_CONTROL_ROB_IDX_W = IS2_AGE_W, 
    parameter integer IS2_RS_V_LSB = 0, 
    parameter integer IS2_RS_V_W = 1, 
    parameter integer IS2_RS_CONTROL_PRS1_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+2*IS2_PRF_IDX_W+47),//179
    parameter integer IS2_RS_CONTROL_PRS1_W = IS2_PRF_IDX_W, 
    parameter integer IS2_RS_CONTROL_PRS2_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+IS2_PRF_IDX_W+46), //172
    parameter integer IS2_RS_CONTROL_PRS2_W = IS2_PRF_IDX_W, 

    parameter integer ENTRY_NUM    = IS2_IQ_DEPTH,
    parameter integer WAKE_DELAY     = 3,
    parameter integer WB_PORT_NUM  = 4,
    parameter integer FU_NUM       = 3,
    parameter integer PRF_IDX_W    = IS2_PRF_IDX_W,
    parameter integer AGE_W        = IS2_AGE_W,
    parameter integer ISSUE_W      = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM)
) (
    
    input  wire clk,
    input  wire rst_n,
    input  wire flush_i,
    input  wire walk_i,//恢复过程有效信号。为 1 时，停止正常入队和发射，检查并删除恢复边界之后的年轻指令。
    input  wire [AGE_W-1:0] restore_age_bound_i,//7 位恢复边界编号

    input  wire rob_stall_i,//上层停顿控制。为 1 时，本队列不接收新指令，但可以发射
    
    //输入指令信息
    input  wire disp_valid_i,
    input  wire [IS2_RS_ENTRY_W-1:0] disp_entry_i,
    input  wire disp_prs1_rdy_i,
    input  wire disp_prs2_rdy_i,

    output reg rs_full_o,//表示本队列是否没有空槽
    
    //实际写回广播接口
    input  wire [PRF_IDX_W-1:0] wb_prd_i [WB_PORT_NUM-1:0],//8 路，每路 6 位。表示各路写回结果对应的目的物理寄存器编号。
    input  wire [WB_PORT_NUM-1:0] wb_valid_i,//对应写回广播是否有效
    
    //提前唤醒广播接口
    input  wire [PRF_IDX_W-1:0] is_prd_i [FU_NUM-1:0],
    input  wire [FU_NUM-1:0] is_valid_i,
    
    //向后级发射指令的接口
    input  wire fu_ready_i,
    output reg issue_valid_o,
    output reg [IS2_RS_ENTRY_W-1:0] issue_entry_o,
    output reg [ISSUE_W-1:0] is_iqid_o,//发射条目的队列槽位编号
    
    //后级读操作数阶段的反馈接口
    input  wire [ISSUE_W-1:0] resp_isid_i,//本拍反馈对应的队列槽位编号。
    input  wire resp_valid_i,
    input  wire resp_issued_i
    );

localparam integer ENTRY_IDX_W = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM);//槽位编号位宽:3

//队列每个槽位的状态
wire [ENTRY_NUM-1:0] free_q;
reg [ENTRY_NUM-1:0] issued_q;   
reg [WAKE_DELAY-1:0] prs1_ready_q [ENTRY_NUM-1:0];
reg [WAKE_DELAY-1:0] prs2_ready_q [ENTRY_NUM-1:0]; 
reg [ENTRY_NUM-1:0] rdy_q; //每条指令的两个源是否都满足就绪条件

//送往年龄仲裁器的信号
reg [AGE_W-1:0] age_vec [ENTRY_NUM-1:0];//各槽位的指令年龄
reg [ENTRY_NUM-1:0] issue_elig_vec;//各条目是否允许参加发射选择
wire [ENTRY_IDX_W-1:0] arb_issue_idx;//仲裁器选中的槽位
wire arb_issue_valid;//仲裁器是否选出了有效候选

reg [ENTRY_IDX_W-1:0] alloc_idx;//本拍为新指令找到的空槽编号
reg alloc_fire;//本拍准备接收新指令

reg [ENTRY_IDX_W-1:0] issue_idx;//本拍准备发射的槽位arb_issue_idx
reg issue_fire;//本拍确实发出了指令
wire issue_kill;//本拍收到失败反馈
reg can_issue;
reg [ENTRY_IDX_W-1:0] resp_idx;//反馈槽位编号


localparam integer SOA_PAYLOAD_W = 2*IS2_PC_WIDTH+IS2_FU_TYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_BRTYPE_WIDTH+IS2_TYPE_WIDTH+IS2_REG_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_CSROP_WIDTH+IS2_CSRADDR_WIDTH+IS2_ZIMM_WIDTH+IS2_EXCPT_WIDTH+43; // 默认 163 位
localparam integer SOA_CONTROL_ROB_IDX_LSB = SOA_PAYLOAD_W+3*IS2_PRF_IDX_W+4;
localparam integer SOA_CONTROL_PRS1_LSB = SOA_PAYLOAD_W+2*IS2_PRF_IDX_W+4;
localparam integer SOA_CONTROL_PRS1_V_LSB = SOA_PAYLOAD_W+2*IS2_PRF_IDX_W+3;
localparam integer SOA_CONTROL_PRS2_LSB = SOA_PAYLOAD_W+IS2_PRF_IDX_W+3;
localparam integer SOA_CONTROL_PRS2_V_LSB = SOA_PAYLOAD_W+IS2_PRF_IDX_W+2;
localparam integer SOA_CONTROL_PRD_LSB = SOA_PAYLOAD_W+2;
localparam integer SOA_CONTROL_PRD_V_LSB = SOA_PAYLOAD_W+1;
localparam integer SOA_PAYLOAD_RAM_LSB = 1;
localparam integer SOA_V_LSB = 0;
reg [IS2_AGE_W-1:0] rob_idx_q [ENTRY_NUM-1:0];
reg [IS2_PRF_IDX_W-1:0] prs1_q [ENTRY_NUM-1:0];
reg [ENTRY_NUM-1:0] prs1_v_q;
reg [IS2_PRF_IDX_W-1:0] prs2_q [ENTRY_NUM-1:0];
reg [ENTRY_NUM-1:0] prs2_v_q;
reg [IS2_PRF_IDX_W-1:0] prd_q [ENTRY_NUM-1:0];
reg [ENTRY_NUM-1:0] prd_v_q;
reg [SOA_PAYLOAD_W-1:0] payload_q [ENTRY_NUM-1:0];
reg [ENTRY_NUM-1:0] valid_q;//各条目有效位
wire [IS2_RS_ENTRY_W-1:0] issue_packed [ENTRY_NUM-1:0];

reg [2:0]state_d;
reg [2:0]state_q;

//判断队列是否已满
assign free_q=~valid_q;
always@(*)begin
rs_full_o=(free_q==0);
end

//状态机控制
always@(posedge clk or negedge rst_n)begin
if(!rst_n)begin
state_q<=IS2_CLEAR;
end else
state_q<=state_d;
end 

always@(*) begin
state_d=state_q;
case(state_q)
    IS2_NORMAL:begin
        if(flush_i) state_d=IS2_CLEAR;
        else if(walk_i) state_d=IS2_RESTORE;
        else if(rob_stall_i) state_d=IS2_STALL;
        else state_d=IS2_NORMAL;
        end
    IS2_RESTORE: begin
            if (!walk_i)        state_d = IS2_NORMAL;
        end
    IS2_STALL: begin
            if (flush_i)        state_d = IS2_CLEAR;
            else if (!rob_stall_i) state_d = IS2_NORMAL;
        end
    IS2_CLEAR: begin
            if (walk_i)         state_d = IS2_RESTORE;
            else                state_d = IS2_NORMAL;
        end
    IS2_ERROR: begin
            state_d = IS2_ERROR;
        end
        default: state_d = IS2_ERROR;
    endcase
end

//为新指令分配槽位
always@(*)begin
integer i;
alloc_idx=0;
alloc_fire=1'b0;
if(disp_valid_i && !rs_full_o && !rob_stall_i && !walk_i)begin
    for(i=0;i<ENTRY_NUM;i=i+1) begin
        if(!alloc_fire && free_q[i])begin
            alloc_idx=i[ENTRY_IDX_W-1:0];
            alloc_fire=1'b1;
        end
    end
end
end

//记录并更新两个源操作数的就绪状态
generate
genvar j;
for(j=0;j<ENTRY_NUM;j=j+1)begin
    reg [WAKE_DELAY-1:0] next_prs1;
    reg [WAKE_DELAY-1:0] next_prs2;
    
    if(WAKE_DELAY==1) begin
        always@(posedge clk or negedge rst_n)begin
            integer p;
            if(!rst_n || flush_i) begin
                prs1_ready_q[j]<=0;
                prs2_ready_q[j]<=0;
            end
            else begin
                next_prs1=prs1_ready_q[j];//默认保持原值
                next_prs2=prs2_ready_q[j];
                
                if (!valid_q[j]) begin
                    next_prs1 = 0;
                    next_prs2 = 0;
                end
                
                // 本拍有入队且命中当前槽位：根据派遣时的就绪信息初始化。
                if (alloc_fire && (j[ENTRY_IDX_W-1:0] == alloc_idx)) begin
                    next_prs1 = disp_prs1_rdy_i ? ({WAKE_DELAY{1'b1}}) : 0;
                    next_prs2 = disp_prs2_rdy_i ? ({WAKE_DELAY{1'b1}}) : 0;
                end
                
                if (valid_q[j]) begin
                    // 写回广播：结果已产生，匹配则置就绪。
                    for (p = 0; p < WB_PORT_NUM; p=p+1) begin
                        if (wb_valid_i[p]) begin
                            if (prs1_v_q[j] && (wb_prd_i[p] == prs1_q[j]))
                                next_prs1 = ({WAKE_DELAY{1'b1}});
                            if (prs2_v_q[j] && (wb_prd_i[p] == prs2_q[j]))
                                next_prs2 = ({WAKE_DELAY{1'b1}});
                        end
                    end
                    // 发射广播：用于提前唤醒，匹配则置就绪。
                    for (p = 0; p < FU_NUM; p=p+1) begin
                        if (is_valid_i[p]) begin
                            if (prs1_v_q[j] && (is_prd_i[p] == prs1_q[j]))
                                next_prs1 = ({WAKE_DELAY{1'b1}});
                            if (prs2_v_q[j] && (is_prd_i[p] == prs2_q[j]))
                                next_prs2 = ({WAKE_DELAY{1'b1}});
                        end
                    end
                end

                // 时钟沿保存下一拍就绪位。
                prs1_ready_q[j] <= next_prs1;
                prs2_ready_q[j] <= next_prs2;
            end
        end
         end else begin : g_wakeN

        always @(posedge clk or negedge rst_n) begin : proc_9
    integer p;
            if (!rst_n || flush_i) begin
                prs1_ready_q[j] <= 0;
                prs2_ready_q[j] <= 0;
            end
            else begin
                
                next_prs1 = {prs1_ready_q[j][WAKE_DELAY-1],
                             prs1_ready_q[j][WAKE_DELAY-1:1]};
                next_prs2 = {prs2_ready_q[j][WAKE_DELAY-1],
                             prs2_ready_q[j][WAKE_DELAY-1:1]};

                if (!valid_q[j]) begin
                    next_prs1 = 0;
                    next_prs2 = 0;
                end

                if (alloc_fire && (j[ENTRY_IDX_W-1:0] == alloc_idx)) begin
                    next_prs1 = disp_prs1_rdy_i ? {WAKE_DELAY{1'b1}} : 0;
                    next_prs2 = disp_prs2_rdy_i ? {WAKE_DELAY{1'b1}} : 0;
                end

                if (valid_q[j]) begin
                    for (p = 0; p < WB_PORT_NUM; p=p+1) begin
                        if (wb_valid_i[p]) begin
                            if (prs1_v_q[j] && (wb_prd_i[p] == prs1_q[j]))
                                next_prs1 = {WAKE_DELAY{1'b1}};
                            if (prs2_v_q[j] && (wb_prd_i[p] == prs2_q[j]))
                                next_prs2 = {WAKE_DELAY{1'b1}};
                        end
                    end

                    for (p = 0; p < FU_NUM-1; p=p+1) begin
                        if (is_valid_i[p]) begin
                            if (prs1_v_q[j] && (is_prd_i[p] == prs1_q[j]))
                                next_prs1 = {WAKE_DELAY{1'b1}};
                            if (prs2_v_q[j] && (is_prd_i[p] == prs2_q[j]))
                                next_prs2 = {WAKE_DELAY{1'b1}};
                        end
                    end

                    if (is_valid_i[FU_NUM-1]) begin
                        if (prs1_v_q[j] && (is_prd_i[FU_NUM-1] == prs1_q[j]))
                            next_prs1 = {{(WAKE_DELAY-1){1'b1}}, 1'b0};
                        if (prs2_v_q[j] && (is_prd_i[FU_NUM-1] == prs2_q[j]))
                            next_prs2 = {{(WAKE_DELAY-1){1'b1}}, 1'b0};
                    end
                end

                prs1_ready_q[j] <= next_prs1;
                prs2_ready_q[j] <= next_prs2;
            end
        end

    end

end
endgenerate

//判断每条指令的源操作数是否都已就绪
always @(*) begin 
    integer i;
    for (i = 0; i < ENTRY_NUM; i=i+1) begin
        rdy_q[i] = ((!prs1_v_q[i]) || prs1_ready_q[i][0])
                        && ((!prs2_v_q[i]) || prs2_ready_q[i][0]);
    end
end

//生成允许参加年龄仲裁的候选集合
always @(*) begin 
    integer i;
    for (i = 0; i < ENTRY_NUM; i=i+1) begin
        age_vec[i]        = rob_idx_q[i];
        issue_elig_vec[i] =
                valid_q[i]
                && !issued_q[i]
                && ((state_q == IS2_NORMAL) || (state_q == IS2_STALL))
                && rdy_q[i];
    end
end


// 年龄仲裁：选择最老的候选指令
age_matrix_arbiter #(
        .IS2_PRD_WIDTH(IS2_PRD_WIDTH),

    .ENTRY_NUM         (ENTRY_NUM),
    .AGE_W             (AGE_W)
) u_age_matrix_arbiter (
    .valid_i           (issue_elig_vec),
    .age_i             (age_vec),
    .index_o           (arb_issue_idx),
    .valid_o           (arb_issue_valid)
);

//检查本拍能否发出，并输出指令
genvar soa_slot;
generate
    for (soa_slot=0; soa_slot<ENTRY_NUM; soa_slot=soa_slot+1) begin : g_pack_issue
        assign issue_packed[soa_slot] = {rob_idx_q[soa_slot], prs1_q[soa_slot], prs1_v_q[soa_slot], prs2_q[soa_slot], prs2_v_q[soa_slot], prd_q[soa_slot], prd_v_q[soa_slot], payload_q[soa_slot], valid_q[soa_slot]};
    end
endgenerate

always @(*) begin : proc_6
    issue_idx     = arb_issue_idx;
    issue_fire    = 1'b0;
    issue_valid_o = 1'b0;
    issue_entry_o = 0;
    can_issue     = 1'b0;
    is_iqid_o     = {{(ISSUE_W-ENTRY_IDX_W){1'b0}}, issue_idx};
    if (arb_issue_valid && fu_ready_i) begin
        can_issue = issue_elig_vec[arb_issue_idx] && !issue_kill
                    && !walk_i
                    && !flush_i;
        if (can_issue) begin
            issue_fire    = 1'b1;
            issue_valid_o = 1'b1;
            issue_entry_o = issue_packed[arb_issue_idx];
        end
    end
end

//处理反馈，并在时钟沿统一更新指令与调度状态
assign issue_kill = resp_valid_i && !resp_issued_i;

always @(posedge clk or negedge rst_n) begin 
integer i;
    if (!rst_n) begin
        issued_q   <= 0;
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
    end
    else if (flush_i) begin
        issued_q   <= 0;
        for (i = 0; i < ENTRY_NUM; i=i+1) begin
            valid_q[i] <= 1'b0;
        end
    end
    else if (walk_i) begin
        if (resp_valid_i) begin
            resp_idx = resp_isid_i[ENTRY_IDX_W-1:0];
            if (resp_issued_i) begin
                valid_q[resp_idx]  <= 1'b0;
            end
            else begin
                issued_q[resp_idx]   <= 1'b0;
            end
        end
        for (i = 0; i < ENTRY_NUM; i=i+1) begin
            if (valid_q[i] && fifoid_gt(rob_idx_q[i], restore_age_bound_i)) begin
                valid_q[i] <= 1'b0;
                issued_q[i]  <= 1'b0;
            end
        end
    end
    else begin
        if (resp_valid_i) begin
            resp_idx = resp_isid_i[ENTRY_IDX_W-1:0];
            if (resp_issued_i) begin
                valid_q[resp_idx]  <= 1'b0;
            end
            else begin
                issued_q[resp_idx]   <= 1'b0;
            end
        end
      
        if (alloc_fire) begin
            rob_idx_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_ROB_IDX_LSB +: IS2_AGE_W];
            prs1_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_PRS1_LSB +: IS2_PRF_IDX_W];
            prs1_v_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_PRS1_V_LSB +: 1];
            prs2_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_PRS2_LSB +: IS2_PRF_IDX_W];
            prs2_v_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_PRS2_V_LSB +: 1];
            prd_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_PRD_LSB +: IS2_PRF_IDX_W];
            prd_v_q[alloc_idx] <= disp_entry_i[SOA_CONTROL_PRD_V_LSB +: 1];
            payload_q[alloc_idx] <= disp_entry_i[SOA_PAYLOAD_RAM_LSB +: SOA_PAYLOAD_W];
            valid_q[alloc_idx]    <= 1'b1;
            issued_q[alloc_idx]     <= 1'b0;
        end
        if (issue_fire) begin
            issued_q[issue_idx]   <= 1'b1;
        end
    end
end

function fifoid_gt;
    input [IS2_PRD_WIDTH:0] a;
    input [IS2_PRD_WIDTH:0] b;

    begin
        fifoid_gt =
            (a[IS2_PRD_WIDTH] == b[IS2_PRD_WIDTH])
            ? (a[IS2_PRD_WIDTH-1:0] > b[IS2_PRD_WIDTH-1:0])
            : (a[IS2_PRD_WIDTH-1:0] < b[IS2_PRD_WIDTH-1:0]);
    end
endfunction
endmodule