`include "issue_defs.vh"
module issue_cluster#(
  parameter integer DISPATCH_WIDTH = 2,// 每拍从上游接收的派遣通道数量。
  parameter integer ALU_NUM        = 2,
  parameter integer FU_NUM         = 3,              

  parameter integer IQ_DEPTH       = `IS2_IQ_DEPTH,//8条
  parameter integer ALU_ENTRY_NUM  = IQ_DEPTH,// 每个 ALU RS 的条目数
  parameter integer LSU_ENTRY_NUM  = IQ_DEPTH,
  parameter integer MUL_ENTRY_NUM  = IQ_DEPTH,
  parameter integer DIV_ENTRY_NUM  = IQ_DEPTH,

  parameter integer ALU_WAKE_DELAY = 3, // ALU 类指令唤醒延迟（拍）
  parameter integer LSU_WAKE_DELAY = 3, // 传给 LSU RS 的就绪跟踪参数。

  parameter integer WB_PORT_NUM    = 3,// 写回端口数（广播源数量）

  parameter integer PRF_IDX_W      = `IS2_PRF_IDX_W,// 物理寄存器编号位宽：6位
  parameter integer AGE_W          = `IS2_AGE_W // 指令年龄编号位宽：7位
)(
  input  wire clk,
  input  wire rst_n,
  input  wire flush_i,
  input  wire walk_i,
  input  wire [AGE_W-1:0] restore_age_bound_i,// 恢复边界，实际为 7 位 ROB 年龄编号。

  input  wire [PRF_IDX_W-1:0] wb_prd_i [WB_PORT_NUM-1:0],//写回结果对应的目的物理寄存器编号，8路，每路6位
  input  wire [WB_PORT_NUM-1:0] wb_valid_i,// 实际为 8 位，每位对应一路写回广播是否有效。

  input  wire [`IS2_DATA_WIDTH-1:0] wb_data_i [WB_PORT_NUM-1:0],// 8 路，每路 32 位。

  input  wire [DISPATCH_WIDTH-1:0] disp_valid_i, // 表示本拍上游实际允许派遣的指令通道。
  input  wire [DISPATCH_WIDTH-1:0] disp_valid_raw_i,
  input  wire [`IS2_RS_ENTRY_W-1:0] disp_entry_i [DISPATCH_WIDTH-1:0],//   [191:164]：control，共 28 位，保存寄存器编号和 ROB 年龄等信息。
    //   [163:1]  ：payload_ram，共 163 位，保存运算控制、PC 和立即数等。
    //   [0]      ：v，条目有效位。
  input  wire [DISPATCH_WIDTH-1:0] disp_prs1_rdy_i, // 每位表示对应派遣指令的第一个源操作数是否已经就绪。
  input  wire [DISPATCH_WIDTH-1:0] disp_prs2_rdy_i,
  
  input  wire [`IS2_DATA_WIDTH-1:0] disp_prs1_data_i [`IS2_PORT_WIDTH-1:0],
  input  wire [`IS2_DATA_WIDTH-1:0] disp_prs2_data_i [`IS2_PORT_WIDTH-1:0],
  
  output wire issue_stall_o, // 任意队列报告不能继续接收时置 1，向上游请求暂停派遣。

  input  wire rob_stall_i,    // 当前队列允许 STALL 状态下已经就绪的已有指令继续发射。
  input  wire [FU_NUM-1:0] fu_ready_i,// 每位表示对应下游执行路径是否能够接收新指令。
  output wire [FU_NUM-1:0] fu_issue_valid_o,
  output wire [`IS2_RS_ENTRY_W-1:0] fu_issue_entry_o [FU_NUM-1:0],

  output wire [$clog2(IQ_DEPTH)-1:0] fu_is_iqid_o [FU_NUM-1:0],//5路，每路3位，表示队列槽位0-7，确定队列条目。
  input  wire [$clog2(IQ_DEPTH)-1:0] fu_resp_isid_i [FU_NUM-1:0],// 后级返回的原队列槽位编号。
  input  wire [FU_NUM-1:0] fu_resp_valid_i,
  input  wire [FU_NUM-1:0] fu_resp_issued_i,
  
  // BIQ 分支完成与写回输出
  output wire [`IS2_PORT_WIDTH-1:0] wb2_valid,
  output wire [`IS2_PORT_WIDTH-1:0] wb2_regw,
  output wire [`IS2_PRD_WIDTH-1:0] wb2_prd [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_PRD_WIDTH:0] wb2_rob_fifonum [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_EXCPT_WIDTH-1:0] wb2_exception [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_PC_WIDTH-1:0] wb2_brdest [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_DATA_WIDTH-1:0] wb2_data [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_PC_WIDTH-1:0] wb2_pc [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_BRTYPE_WIDTH-1:0] wb2_brtype [`IS2_PORT_WIDTH-1:0],
  output wire [`IS2_PORT_WIDTH-1:0] wb2_isret,
  output wire [4:0] wb2_rd [`IS2_PORT_WIDTH-1:0],

  // 分支恢复请求
  output wire ctrl_restore_req, // 通过此信号向上层请求恢复流水线。
  output wire [`IS2_PC_WIDTH-1:0] nxtpc_flush,//恢复后应使用的正确下一条 PC。
  output wire [`IS2_PRD_WIDTH:0] flush_id,//触发恢复的分支对应的 ROB 年龄编号。
  
  output wire dbg_alu_rs_full_any,
  output wire dbg_lsu_rs_full,
  output wire dbg_mul_rs_full,
  output wire dbg_div_rs_full,
  output wire dbg_biq_rs_full
    
);


localparam integer LSU_FU_IDX = ALU_NUM;     //LSU 使用第 2 个普通发射通道。           
localparam integer ISSUE_W    = (IQ_DEPTH <= 1) ? 1 : $clog2(IQ_DEPTH);
localparam integer ALU_IDX_W  = (ALU_NUM <= 1) ? 1 : $clog2(ALU_NUM);//可表示两个 ALU 的编号。

wire [ALU_NUM-1:0] alu_rs_full;//// 实际为 2 位，分别记录 ALU0、ALU1 队列的接收阻塞。
wire lsu_rs_full;
wire mul_rs_full;
wire div_rs_full;
wire biq_rs_full;

wire [ALU_IDX_W-1:0] rr_alu_sel_q;
wire [ALU_IDX_W-1:0] rr_alu_sel_d;
wire [PRF_IDX_W-1:0] is_prd_i [FU_NUM-1:0];// 记录各发射通道本拍选中指令的目的物理寄存器编号。
wire [FU_NUM-1:0] is_valid_i; // 对应通道发射有效且指令有目的寄存器时，广播有效。

wire [FU_NUM-1:0] fu_issue_valid;//各子队列产生的发射有效信号。
wire [`IS2_RS_ENTRY_W-1:0] fu_issue_entry [FU_NUM-1:0];
wire [$clog2(IQ_DEPTH)-1:0] fu_is_iqid [FU_NUM-1:0];
wire [$clog2(IQ_DEPTH)-1:0] fu_resp_isid [FU_NUM-1:0];
wire [FU_NUM-1:0] fu_resp_valid;
wire [FU_NUM-1:0] fu_resp_issued;

genvar fidx;

    generate
        for (fidx = 0; fidx < FU_NUM; fidx = fidx + 1) begin

            // 将各子队列选出的指令、有效位和槽位编号送出模块。
            assign fu_issue_valid_o[fidx] = fu_issue_valid[fidx];
            assign fu_issue_entry_o[fidx] = fu_issue_entry[fidx];
            assign fu_is_iqid_o[fidx]     = fu_is_iqid[fidx];

            // 将后级反馈连接到对应队列。
            // 这些连续赋值只负责连线，不增加流水级。
            assign fu_resp_isid[fidx]   = fu_resp_isid_i[fidx];
            assign fu_resp_valid[fidx]  = fu_resp_valid_i[fidx];
            assign fu_resp_issued[fidx] = fu_resp_issued_i[fidx];

        end
    endgenerate
    // 从发射指令中提取目的寄存器广播
    // ========================================================================

    genvar iidx;

    generate
        for (iidx = 0; iidx < FU_NUM; iidx = iidx + 1) begin

            // IS2_RS_CONTROL_PRD_V 对应当前条目的第 164 位。
            // 该位为 1，表示指令会产生目的物理寄存器结果。
            // 发射有效且目的寄存器有效时，向其它队列发送广播。
            assign is_valid_i[iidx] =
                fu_issue_valid_o[iidx]
                && fu_issue_entry_o[iidx][`IS2_RS_CONTROL_PRD_V];

            // IS2_RS_CONTROL_PRD 对应当前条目的 [170:165]。
            // 提取 6 位目的物理寄存器编号。
            // 子队列将其与等待指令的源寄存器编号比较，
            // 按各自的提前唤醒规则更新源操作数就绪状态。
            assign is_prd_i[iidx] =
                fu_issue_entry_o[iidx][`IS2_RS_CONTROL_PRD];

        end
    endgenerate


    // ========================================================================
    // LSU 和 BIQ 的派遣有效位
    // ========================================================================

    // 实际各为 2 位。
    // valid 表示实际派遣，valid_raw 表示原始派遣需求。
    wire [`IS2_PORT_WIDTH-1:0] biq_disp_valid;
    wire [`IS2_PORT_WIDTH-1:0] biq_disp_valid_raw;
    wire [`IS2_PORT_WIDTH-1:0] lsu_disp_valid;
    wire [`IS2_PORT_WIDTH-1:0] lsu_disp_valid_raw;

    generate
        for (
            iidx = 0;
            iidx < `IS2_PORT_WIDTH;
            iidx = iidx + 1
        ) begin

            // 提取第 iidx 路指令的功能类型。
            // IS2_RS_PAYLOAD_RAM_FUTYPE 对应条目的 [94:92]，共 3 位。
            //
            // FU_BR 编码为 3。
            // 只有有效的分支指令，并且当前不处于恢复过程，
            // 才允许送入 BIQ。
            assign biq_disp_valid[iidx] =
                disp_valid_i[iidx]
                & (disp_entry_i[iidx][`IS2_RS_PAYLOAD_RAM_FUTYPE]
                   == `IS2_FU_BR)
                & ~walk_i;

            // 将原始派遣需求按分支类型过滤，供 BIQ 判断所需空间。
            assign biq_disp_valid_raw[iidx] =
                disp_valid_raw_i[iidx]
                & (disp_entry_i[iidx][`IS2_RS_PAYLOAD_RAM_FUTYPE]
                   == `IS2_FU_BR)
                & ~walk_i;

            // FU_MEM 编码为 2。
            // 只有有效的访存指令，并且当前不处于恢复过程，
            // 才允许送入 LSU 队列。
            assign lsu_disp_valid[iidx] =
                disp_valid_i[iidx]
                & (disp_entry_i[iidx][`IS2_RS_PAYLOAD_RAM_FUTYPE]
                   == `IS2_FU_MEM)
                & ~walk_i;

            // 将原始派遣需求按访存类型过滤后送入 LSU 队列。
            assign lsu_disp_valid_raw[iidx] =
                disp_valid_raw_i[iidx]
                & (disp_entry_i[iidx][`IS2_RS_PAYLOAD_RAM_FUTYPE]
                   == `IS2_FU_MEM)
                & ~walk_i;

        end
    endgenerate


    // ========================================================================
    // 汇总队列阻塞状态
    // ========================================================================

    // 对两个 ALU 队列和 LSU、MUL、DIV、BIQ 的阻塞信号做归约或。
    // 任意一个队列不能继续接收，就向上游请求暂停派遣。
    assign issue_stall_o =
        |{alu_rs_full, lsu_rs_full, mul_rs_full, div_rs_full, biq_rs_full};

    // 单独输出阻塞来源，供上层调试观察。
    assign dbg_alu_rs_full_any = |alu_rs_full;
    assign dbg_lsu_rs_full     = lsu_rs_full;
    assign dbg_mul_rs_full     = mul_rs_full;
    assign dbg_div_rs_full     = div_rs_full;
    assign dbg_biq_rs_full     = biq_rs_full;
    
     generate
    genvar a;
for (a = 0; a < ALU_NUM; a=a+1) begin : g_alu_rs
      rs_issue_queue #(
        .ENTRY_NUM    (ALU_ENTRY_NUM),
        .WAKE_DELAY   (ALU_WAKE_DELAY),
        .FU_NUM       (FU_NUM),
        .WB_PORT_NUM  (WB_PORT_NUM),
        .PRF_IDX_W    (PRF_IDX_W),
        .AGE_W        (AGE_W)
      ) u_rs_alu (
        .clk                 (clk),
        .rst_n               (rst_n),
        .flush_i             (flush_i),
        .walk_i              (walk_i),
        .restore_age_bound_i (restore_age_bound_i),
        
        .rob_stall_i         (rob_stall_i),

        .disp_valid_i        ((a < DISPATCH_WIDTH) && disp_valid_i[a] && (disp_entry_i[a][`IS2_RS_PAYLOAD_RAM_FUTYPE] == `IS2_FU_NORMAL)),
        .disp_entry_i        (disp_entry_i[a]),
        .disp_prs1_rdy_i     (disp_prs1_rdy_i[a]),
        .disp_prs2_rdy_i     (disp_prs2_rdy_i[a]),

        .rs_full_o           (alu_rs_full[a]),

        .wb_prd_i            (wb_prd_i),
        .wb_valid_i          (wb_valid_i),

        .fu_ready_i          (fu_ready_i[a]),
        .issue_valid_o       (fu_issue_valid[a]),
        .issue_entry_o       (fu_issue_entry[a]),

        .is_iqid_o           (fu_is_iqid[a]),
        .resp_isid_i         (fu_resp_isid[a]),
        .resp_valid_i        (fu_resp_valid[a]),
        .resp_issued_i       (fu_resp_issued[a]),
        .is_prd_i            (is_prd_i),
        .is_valid_i          (is_valid_i)
      );
    end
  endgenerate

  rs_lsu_queue #(
    .ENTRY_NUM    (LSU_ENTRY_NUM),
    .WAKE_DELAY    (LSU_WAKE_DELAY),
    .WB_PORT_NUM  (WB_PORT_NUM),
    .FU_NUM       (FU_NUM),
    .PRF_IDX_W    (PRF_IDX_W),
    .AGE_W        (AGE_W),
    .PORT_WIDTH   (`IS2_PORT_WIDTH)
  ) u_rs_lsu (
    .clk                 (clk),
    .rst_n               (rst_n),
    .flush_i             (flush_i),
    .walk_i              (walk_i),
    .restore_age_bound_i (restore_age_bound_i),
    
    .rob_stall_i         (rob_stall_i),

    .disp_valid_i        (lsu_disp_valid),
    .disp_valid_raw_i    (lsu_disp_valid_raw),
    .disp_entry_i        (disp_entry_i),
    .disp_prs1_rdy_i     (disp_prs1_rdy_i),
    .disp_prs2_rdy_i     (disp_prs2_rdy_i),

    .rs_full_o           (lsu_rs_full),

    .wb_prd_i            (wb_prd_i),
    .wb_valid_i          (wb_valid_i),

    .fu_ready_i          (fu_ready_i[LSU_FU_IDX]),
    .issue_valid_o       (fu_issue_valid[LSU_FU_IDX]),
    .issue_entry_o       (fu_issue_entry[LSU_FU_IDX]),

    .is_iqid_o           (fu_is_iqid[LSU_FU_IDX]),
    .resp_isid_i         (fu_resp_isid[LSU_FU_IDX]),
    .resp_valid_i        (fu_resp_valid[LSU_FU_IDX]),
    .resp_issued_i       (fu_resp_issued[LSU_FU_IDX]),
    .is_prd_i            (is_prd_i),
    .is_valid_i          (is_valid_i)
  );

  rs_mul_queue #(
    .ENTRY_NUM    (MUL_ENTRY_NUM),
    .WAKE_DELAY   (ALU_WAKE_DELAY),
    .WB_PORT_NUM  (WB_PORT_NUM),
    .FU_NUM       (FU_NUM),
    .PRF_IDX_W    (PRF_IDX_W),
    .AGE_W        (AGE_W),
    .PORT_WIDTH   (DISPATCH_WIDTH),
    .LSU_FU_IDX   (ALU_NUM),
    .MUL_FU_IDX   (ALU_NUM + 1),
    .DIV_FU_IDX   (ALU_NUM + 2)
  ) u_rs_mul (
    .clk                 (clk),
    .rst_n               (rst_n),
    .flush_i             (flush_i),
    .walk_i              (walk_i),
    .restore_age_bound_i (restore_age_bound_i),
    .rob_stall_i         (rob_stall_i),
    .disp_valid_i        (disp_valid_i),
    .disp_valid_raw_i    (disp_valid_raw_i),
    .disp_entry_i        (disp_entry_i),
    .disp_prs1_rdy_i     (disp_prs1_rdy_i),
    .disp_prs2_rdy_i     (disp_prs2_rdy_i),
    .rs_full_o           (mul_rs_full),
    .wb_prd_i            (wb_prd_i),
    .wb_valid_i          (wb_valid_i),
    .is_prd_i            (is_prd_i),
    .is_valid_i          (is_valid_i),
    .fu_ready_i          (fu_ready_i[ALU_NUM + 1]),
    .issue_valid_o       (fu_issue_valid[ALU_NUM + 1]),
    .issue_entry_o       (fu_issue_entry[ALU_NUM + 1]),
    .is_iqid_o           (fu_is_iqid[ALU_NUM + 1]),
    .resp_isid_i         (fu_resp_isid[ALU_NUM + 1]),
    .resp_valid_i        (fu_resp_valid[ALU_NUM + 1]),
    .resp_issued_i       (fu_resp_issued[ALU_NUM + 1])
  );

  rs_div_queue #(
    .ENTRY_NUM    (DIV_ENTRY_NUM),
    .WAKE_DELAY   (ALU_WAKE_DELAY),
    .WB_PORT_NUM  (WB_PORT_NUM),
    .FU_NUM       (FU_NUM),
    .PRF_IDX_W    (PRF_IDX_W),
    .AGE_W        (AGE_W),
    .PORT_WIDTH   (DISPATCH_WIDTH),
    .LSU_FU_IDX   (ALU_NUM),
    .MUL_FU_IDX   (ALU_NUM + 1),
    .DIV_FU_IDX   (ALU_NUM + 2)
  ) u_rs_div (
    .clk                 (clk),
    .rst_n               (rst_n),
    .flush_i             (flush_i),
    .walk_i              (walk_i),
    .restore_age_bound_i (restore_age_bound_i),
    .rob_stall_i         (rob_stall_i),
    .disp_valid_i        (disp_valid_i),
    .disp_valid_raw_i    (disp_valid_raw_i),
    .disp_entry_i        (disp_entry_i),
    .disp_prs1_rdy_i     (disp_prs1_rdy_i),
    .disp_prs2_rdy_i     (disp_prs2_rdy_i),
    .rs_full_o           (div_rs_full),
    .wb_prd_i            (wb_prd_i),
    .wb_valid_i          (wb_valid_i),
    .is_prd_i            (is_prd_i),
    .is_valid_i          (is_valid_i),
    .fu_ready_i          (fu_ready_i[ALU_NUM + 2]),
    .issue_valid_o       (fu_issue_valid[ALU_NUM + 2]),
    .issue_entry_o       (fu_issue_entry[ALU_NUM + 2]),
    .is_iqid_o           (fu_is_iqid[ALU_NUM + 2]),
    .resp_isid_i         (fu_resp_isid[ALU_NUM + 2]),
    .resp_valid_i        (fu_resp_valid[ALU_NUM + 2]),
    .resp_issued_i       (fu_resp_issued[ALU_NUM + 2])
  );

  biq #(
    .ENTRY_NUM     (16),
    .WB_PORT_NUM   (WB_PORT_NUM),
    .PORT_WIDTH    (`IS2_PORT_WIDTH),
    .BIQ_BITS      (4)
  ) biq (
    .clk(clk),
    .rst(~rst_n),
    .rob_stall_i(rob_stall_i),
    .disp_valid_i(biq_disp_valid),
    .disp_valid_raw_i(biq_disp_valid_raw),
    .disp_entry_i(disp_entry_i),
    .disp_prs1_rdy_i(disp_prs1_rdy_i),
    .disp_prs2_rdy_i(disp_prs2_rdy_i),
    .disp_prs1_data_i(disp_prs1_data_i),
    .disp_prs2_data_i(disp_prs2_data_i),

    .wb_valid_i(wb_valid_i),
    .wb_prd_i(wb_prd_i),
    .wb_data_i(wb_data_i),
    
    .wb2_valid(wb2_valid),
    .wb2_regw(wb2_regw),
    .wb2_prd(wb2_prd),
    .wb2_rob_fifonum(wb2_rob_fifonum),
    .wb2_exception(wb2_exception),
    .wb2_brdest(wb2_brdest),
    .wb2_data(wb2_data),
    .wb2_pc(wb2_pc),
    .wb2_brtype(wb2_brtype),
    .wb2_isret(wb2_isret),
    .wb2_rd(wb2_rd),
    .rs_full_o(biq_rs_full),
    .ctrl_clear(flush_i),
    .ctrl_restore_req(ctrl_restore_req),
    .nxtpc_flush(nxtpc_flush),
    .flush_id(flush_id)
  );



endmodule