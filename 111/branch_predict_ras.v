module branch_predict_ras (
    input clk,
    input rst,

    //retire来的指令信息
    input wire [PORT_WIDTH-1:0] rt_grant, //每个retire端口是否有效
    input wire [4:0] rt_rd[PORT_WIDTH-1:0], //retire指令的目的寄存器
    input wire [PC_WIDTH-1:0] rt_pc [PORT_WIDTH-1:0],
    input wire [BRTYPE_WIDTH-1:0] rt_brtype [PORT_WIDTH-1:0], //分支类型
    input wire [PC_WIDTH-1:0] rt_brdest [PORT_WIDTH-1:0],//实际目标地址
    input wire [PORT_WIDTH-1:0] rt_is_ret, //是否为return
    input wire [EXCPT_WIDTH-1:0] rt_exception [PORT_WIDTH-1:0], //异常信息

    //icache接口
    input wire icache_rvalid,//read_valid
    input wire icache_busy,
    input wire have_inst_i, //输入指令是否有效
    input wire pc_i, // 输入 PC
    input wire [DATA_WIDTH-1:0] inst_i[IN_WIDTH-1:0], // 输入指令 bundle

    output wire [IN_WIDTH-1:0] have_inst_o,
    output wire [PC_WIDTH-1:0] pc[IN_WIDTH-1:0],// 每个 lane 的 PC
    output wire [PC_WIDTH-1:0] pc_next[IN_WIDTH-1:0],// 每个 lane 的下一 PC（若预测 taken 则为目标，否则 PC+4）
    output wire [DATA_WIDTH-1:0] inst[IN_WIDTH-1:0],// 每个 lane 的指令
    output wire [31:0] dbg_bundle_cut_inst,// 调试：bundle 被截断的指令数

   
    // 控制/恢复接口
    input  wire ctrl_restore_pulse,// 从 retire 侧恢复预测状态（例如分支误预测恢复）
    input wire ctrl_clear,// 清空预测状态（例如中断/异常）
    input  wire [PC_WIDTH-1:0] nxtpc_flush,// 冲刷后的下一 PC
    input  wire [PC_WIDTH-1:0] nxtpc_interrupt,// 中断后的下一 PC

    output wire redirect,// 是否发生重定向
    output wire [PC_WIDTH-1:0] redirect_pc// 重定向目标 PC
)

//PARAMETERS
    parameter BUF_BITS=3， //分支预测内部buffer的地址位宽
    parameter PORT_WIDTH=2， //每周期可提交/写回的分支数量
    parameter IN_WIDTH=4， //取指宽度，每周期取多少条指令
    parameter RAS_DEPTH=16

    localparam BUF_DEPTH=1<<BUF_BITS;
    localparam STATE_GET_TAG    =   1'b0;
    localparam STATE_WR_DATA    =   1'b1;

    localparam signed [31:0] PC_SPLICE_BITS = 10;     // PC 拼接位宽
    localparam signed [31:0] BHR_BITS = 4;            // 短 BHR 位宽
    localparam signed [31:0] PHT_BITS = BHR_BITS + PC_SPLICE_BITS; // PHT 索引位宽
    localparam signed [31:0] PHT_DEPTH = 1 << PHT_BITS;            // PHT 深度
    localparam signed [31:0] PHT_BANK_BITS = 2;                    // PHT bank 选择位宽
    localparam signed [31:0] PHT_BANK_ADDR_BITS = PHT_BITS - PHT_BANK_BITS; // PHT bank 内地址位宽
    localparam signed [31:0] LEGACY_PHT_BUF_BITS = 2;              // legacy PHT 更新 FIFO 位宽
    localparam signed [31:0] LEGACY_PHT_BUF_DEPTH = 4;             // legacy PHT 更新 FIFO 深度
    localparam [0:0] LEGACY_PHT_RD_OLD = 1'b0;                     // legacy PHT：读旧计数器
    localparam [0:0] LEGACY_PHT_WR_NEW = 1'b1;                     // legacy PHT：写新计数器
    localparam signed [31:0] FETCH_BANK_W = (IN_WIDTH <= 2 ? 1 : $clog2(IN_WIDTH)); // 取指 bank 位宽
    localparam signed [31:0] SHORT_BHR_BITS = 8;                   // 短预测器 BHR 位宽
    localparam signed [31:0] SHORT_LOCAL_BHT_BITS = 2;             // 短预测器局部 BHT 位宽
    localparam signed [31:0] SHORT_LOCAL_ROW_BITS = 3;             // 短预测器局部行位宽
    localparam signed [31:0] SHORT_BHT_IDX_BITS = $clog2(IN_WIDTH) + SHORT_LOCAL_BHT_BITS; // 短 BHT 索引位宽
    localparam signed [31:0] SHORT_PC_SPLICE_BITS = $clog2(IN_WIDTH) + SHORT_LOCAL_ROW_BITS; // 短 PC 拼接位宽
    localparam signed [31:0] LONG_BHR_BITS = 16;                   // 长预测器 BHR 位宽
    localparam signed [31:0] LONG_SLOT_COUNT = 4;                  // 长预测器槽位数
    localparam signed [31:0] UPGRADE_SAMPLE_WINDOW = 96;           // 升级采样窗口
    localparam signed [31:0] UPGRADE_MISS_THRESHOLD = 20;          // 升级缺失阈值
    localparam [31:0] RAS_PTR_W = (RAS_DEPTH <= 2 ? 1 : $clog2(RAS_DEPTH)); // RAS 指针位宽

	reg [31:0] active_ras_stack [0:RAS_DEPTH - 1];
	reg [31:0] commit_ras_stack [0:RAS_DEPTH - 1];
	reg [31:0] active_ras_stack_n [0:RAS_DEPTH - 1];//组合 next 版本
	reg [31:0] commit_ras_stack_n [0:RAS_DEPTH - 1];
	reg [RAS_PTR_W - 1:0] active_ras_sp;//下一次压栈位置
	reg [RAS_PTR_W - 1:0] commit_ras_sp;
	reg [RAS_PTR_W - 1:0] active_ras_sp_n;//指针的下一状态
	reg [RAS_PTR_W - 1:0] commit_ras_sp_n;
	reg [RAS_PTR_W:0] active_ras_cnt;//栈里有多少项，有多少个有效返回地址
	reg [RAS_PTR_W:0] commit_ras_cnt;
	reg [RAS_PTR_W:0] active_ras_cnt_n;//有效数量的下一状态
	reg [RAS_PTR_W:0] commit_ras_cnt_n;
	reg active_ras_empty;
	reg [31:0] active_ras_top;       // active RAS 栈顶值
	reg [RAS_PTR_W - 1:0] active_ras_sp_top; // active RAS 栈顶指针
    
    
	reg [IN_WIDTH - 1:0] slot_is_call;       // 各取指槽是否为 call
	reg [IN_WIDTH - 1:0] slot_is_ret;        // 各取指槽是否为 return
	reg [PORT_WIDTH - 1:0] rt_is_call;       // 各提交端口是否为 call
    
	wire [(IN_WIDTH * 2) - 1:0] lp;          // 短预测器局部预测结果
	reg [IN_WIDTH - 1:0] pre_taken;          // 预预测：是否跳转
	reg [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] pre_brdest; // 预预测目标
	reg [IN_WIDTH - 1:0] have_inst;          // 内部有效槽位
	wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] pc_table;  // 当前取指包 PC 表

	localparam [31:0] RAS_SP_LAST_32 = RAS_DEPTH - 1;//最后一个栈位置的编号
	localparam [31:0] RAS_CNT_MAX_32 = RAS_DEPTH;//栈最多能保存的数量
	localparam [RAS_PTR_W - 1:0] RAS_SP_LAST = RAS_SP_LAST_32[RAS_PTR_W - 1:0];//取低RAS_PTR_W位
	localparam [RAS_PTR_W:0] RAS_CNT_MAX = RAS_CNT_MAX_32[RAS_PTR_W:0];
    
    reg [PHT_BANK_ADDR_BITS-1:0] pht_addra_bank [IN_WIDTH-1:0];//读地址
    reg [1:0] pht_douta_bank [IN_WIDTH-1:0];//读数据
    reg [IN_WIDTH-1:0]                        pht_web_bank;//写使能
    reg [PHT_BANK_ADDR_BITS-1:0] pht_addrb_bank [IN_WIDTH-1:0];//写地址
    reg [1:0] pht_dinb_bank [IN_WIDTH-1:0];//写数据
    reg [1:0] pht_doutb_bank [IN_WIDTH-1:0];//写出口读出旧数据

    reg [62:0] buf_wdata [PORT_WIDTH-1:0];// retire 侧写入 BTB buffer 的打包数据
    reg [5:0] raddr [IN_WIDTH-1:0];// BTB/BHT 读地址
    reg [31:0] r_brdest [IN_WIDTH-1:0];// BTB 读出的分支目标
    reg [21:0] r_tag [IN_WIDTH-1:0];// BTB 读出的 tag
    reg [1:0] r_brtype [IN_WIDTH-1:0];// BTB 读出的分支类型
    reg [BHR_BITS-1:0] r_bhr [IN_WIDTH-1:0];// BHT 读出的 BHR
    
    // bank 化后的读地址与读数据
    reg [5:0] bank_raddr [IN_WIDTH-1:0];
    reg [31:0] bank_r_brdest [IN_WIDTH-1:0];
    reg [21:0] bank_r_tag [IN_WIDTH-1:0];
    reg [1:0] bank_r_brtype [IN_WIDTH-1:0];
    reg [BHR_BITS-1:0] bank_r_bhr [IN_WIDTH-1:0];

    reg [PORT_WIDTH-1:0] buf_we [IN_WIDTH-1:0];// BTB buffer 写使能
    reg [IN_WIDTH-1:0]                 we;// BHT 写使能
    reg [BHR_BITS-1:0] w_bhr [IN_WIDTH-1:0];// BHT 写入 BHR
    reg [IN_WIDTH-1:0]                 w_taken;// BHT 写入 taken
    reg [BHR_BITS-1:0] w_bhr_old [IN_WIDTH-1:0];// BHT 写入旧 BHR
    
    // legacy PHT 写地址与读地址（旧pht）
    reg [PHT_BANK_ADDR_BITS-1:0] w_pht_bank_addr [IN_WIDTH-1:0];
    reg [PHT_BANK_ADDR_BITS-1:0] r_pht_bank_addr [IN_WIDTH-1:0];
    reg [IN_WIDTH-1:0]                 w_pht;
    
    
    // 方向预测器接口：把取指 lane 信息送给方向预测器
    reg [IN_WIDTH-1:0]                                br_grant;
    reg [PC_WIDTH-1:0] br_pc [IN_WIDTH-1:0];
    reg [BRTYPE_WIDTH-1:0] br_brtype [IN_WIDTH-1:0];
    reg [IN_WIDTH-1:0]                                br_taken;
    
    // 短预测器 / 长预测器调试与选择信号
    reg [1:0] lp_n4 [IN_WIDTH-1:0];//短历史预测器输出的最终两位计数器值
    reg [1:0] lp_long [IN_WIDTH-1:0];//长历史预测器输出的最终两位计数器值
    reg [IN_WIDTH-1:0]                use_long_pred;//每条指令是否采用长预测器结果
    
    //调试变量
    reg [SHORT_BHR_BITS-1:0] short_base_hist_dbg [IN_WIDTH-1:0];
    reg [SHORT_BHR_BITS-1:0] short_prefix_hist_dbg [IN_WIDTH-1:0];
    reg [SHORT_BHR_BITS-1:0] short_effective_hist_dbg [IN_WIDTH-1:0];
    reg [SHORT_PC_SPLICE_BITS-$clog2(IN_WIDTH)-1:0] short_pht_row_dbg [IN_WIDTH-1:0];
    reg [SHORT_BHR_BITS-3:0] short_ctr_idx_dbg [IN_WIDTH-1:0];
    reg [IN_WIDTH-1:0]                     short_bypass_hit_dbg;
    reg [1:0] short_ctr_src_dbg [IN_WIDTH-1:0];
    reg [LONG_BHR_BITS-1:0] long_base_hist_dbg [IN_WIDTH-1:0];
    reg [LONG_BHR_BITS-1:0] long_lookup_hist_dbg [IN_WIDTH-1:0];
    reg [$clog2(LONG_SLOT_COUNT)-1:0] long_slot_dbg [IN_WIDTH-1:0];
    reg [IN_WIDTH-1:0]                     long_bypass_hit_dbg;
    reg [LONG_BHR_BITS-1:0] long_bypass_addr_dbg [IN_WIDTH-1:0];
    reg [1:0] long_bypass_ctr_dbg [IN_WIDTH-1:0];
    reg [1:0] long_ctr_src_dbg [IN_WIDTH-1:0];
    
    
    wire [IN_WIDTH-1:0]                br_short_dir_enable;//每条前端指令是否允许更新短预测器的投机历史
    wire [PORT_WIDTH-1:0]              rt_short_dir_enable;//每路后端条件分支反馈是否允许训练短预测器
    reg [PORT_WIDTH-1:0]              rt_use_long;//根据后端反馈 PC 判断，该分支当前是否匹配已升级的长预测器记录
//pre_decode
genvar s;
generate
    for (s = 0; s < IN_WIDTH; s = s + 1) begin : gen_decode
        wire [6:0]  opcode ;
        wire [4:0]  rd ;
        wire [4:0]  rs1;
        wire [31:0] imm;
        always@(*)begin
        opcode = inst_i[s][6:0];
        rd     = inst_i[s][11:7];
        rs1    = inst_i[s][19:15];
        imm    = 32'b0;
        
        slot_is_call[s]=1'b0;
        slot_is_ret[s]=1'b0;
        case(opcode)
        7'1101111:begin //jal
                    imm[0]      = 1'b0;
                    imm[19:12]  = inst_i[s][19:12];
                    imm[11]     = inst_i[s][20];
                    imm[10:1]   = inst_i[s][30:21];
                    imm[31:20]  = {12{inst_i[s][31]}};
                    pre_drdest[s]=pc[s]+imm;
                    pre_taken[s]=1'b1;
                    br_brtype[s]=MBR_DIRECT;
                    if (rd == 5'd1) begin
                        slot_is_call[s] = 1'b1;
                    end
                end
                
        7'b1100111: begin // jalr
                    imm[11:0]   = inst_i[s][31:20];
                    imm[31:12]  = {20{inst_i[s][31]}};
                    br_brtype[s]= MBR_INDIRECT;

                    // RET = jalr x0, x1, 0
                    if ((rd == 5'd0) && (rs1 == 5'd1) && (imm[11:0] == 12'b0)) begin
                        slot_is_ret[s] = 1'b1;

                        if (!active_ras_empty) begin
                            pre_brdest[s] = active_ras_top;
                            pre_taken[s]  = 1'b1;
                        end else begin
                            // RAS empty -> fallback to BTB jalr prediction
                            if (r_tag[s] != pc[s][31:10]) begin
                                pre_brdest[s] = '0;
                                pre_taken[s]  = 1'b0;
                            end else begin
                                pre_brdest[s] = r_brdest[s];
                                end
                        end
                    end else begin
                        // normal JALR
                        if (rd == 5'd1) begin
                            slot_is_call[s] = 1'b1;
                        end

                        if (r_tag[s] != pc[s][31:10]) begin
                            pre_brdest[s] = '0;
                            pre_taken[s]  = 1'b0;
                        end else begin
                            pre_brdest[s] = r_brdest[s];
                            pre_taken[s]  = 1'b1;
                        end
                    end
                end
                7'b1100011: begin // B (conditional branch)
                    imm[4:1]    = inst_i[s][11:8];
                    imm[11]     = inst_i[s][7];
                    imm[10:5]   = inst_i[s][30:25];
                    imm[12]     = inst_i[s][31];
                    imm[0]      = 1'b0;
                    imm[31:13]  = {19{inst_i[s][31]}};
                    pre_brdest[s]= pc[s] + imm;
                    pre_taken[s] = use_long_pred[s] ? lp_long[s][1] : lp_n4[s][1];
                    br_brtype[s] = CBR_DIRECT;
                end
                default: begin
                    pre_brdest[s]= '0;
                    pre_taken[s] = 1'b0;
                    br_brtype[s] = NBR;
                end
            endcase
        end
    end
endgenerate
    
    
    
//active_ras：
    always@(*)begin
    active_ras_empty=active_ras_cnt==0;
    active_ras_sp_top=1'b0;
    active_ras_top=1'b0;
    if(!active_ras_empty)begin
        if(active_ras_sp==0)
        active_ras_sp_top=RAS_SP_LAST;
        else begin
        active_ras_sp_top=active_ras_sp-1'b1;
        end
        active_ras_top=active_ras_stack[active_ras_sp_top];
    end
    end
    
    
    
//判断retire端口上的call：
    always@(*)begin
    for (int i = 0; i < PORT_WIDTH; i = i + 1) begin
        rt_is_call[i] = rt_grant[i] &&
                        ((rt_brtype[i] == MBR_DIRECT) || (rt_brtype[i] == MBR_INDIRECT)) &&
                        (rt_rd[i] == 5'd1);
    end
end
    

// 把当前输出 lane 的信息接到方向预测器输入（把前端接受了哪条指令、它的 PC、预测跳转结果，反馈给方向预测器，用于维护投机历史）
generate
    genvar nidx;
    for (nidx = 0; nidx < IN_WIDTH; nidx = nidx + 1) begin : gen_br_lane
        assign br_grant[nidx] = have_inst_o[nidx];
        assign br_pc[nidx]    = pc[nidx];
        assign br_taken[nidx] = pre_taken[nidx];
    end
endgenerate

//legacy_pht
    generate
    for (genvar pb = 0; pb < IN_WIDTH; pb = pb + 1) begin : gen_legacy_pht_mem
        sync_dp_bram_bp_pht #(
            .ADDR_W(PHT_BANK_ADDR_BITS),
            .DATA_W(2),
            .INIT_VALUE(2'b11)
        ) u_legacy_pht_mem (
            .clka (clk),
            .wea  (1'b0),
            .addra(pht_addra_bank[pb]),
            .dina ('0),
            .douta(pht_douta_bank[pb]),
            .clkb (clk),
            .web  (pht_web_bank[pb]),
            .addrb(pht_addrb_bank[pb]),
            .dinb (pht_dinb_bank[pb]),
            .doutb(pht_doutb_bank[pb])
        );
    end
endgenerate

//// 每个取指 lane / bank 维护一份 BTB/BHT 访问缓冲
genvar idx;
generate
    for (idx = 0; idx < IN_WIDTH; idx = idx + 1) begin : br_bank
        reg [PORT_WIDTH-1:0]                  buf_in;// buffer 输入有效
        reg [BUF_BITS-1:0] head_addr [PORT_WIDTH-1:0]; // buffer 头地址
        reg [62:0] buf_entry [BUF_DEPTH-1:0];// buffer 数据项：{taken, tag, brtype, brdest}
        reg [BUF_DEPTH-1:0]                   buf_v;  // buffer 有效位
        reg                                   buf_consume;// buffer 消费
        reg [BUF_BITS-1:0]                    buf_head; // buffer 头指针
        reg [BUF_BITS-1:0]                    buf_tail;// buffer 尾指针
        reg                                   curr_state;
        reg                                   next_state;
        reg [5:0]                             waddr;
        reg [31:0]                            w_brdest, origin_brdest;
        reg [21:0]                            w_tag, origin_tag;
        reg [1:0]                             w_brtype, origin_brtype;
        reg [BHR_BITS-1:0]                    origin_bhr;

        // 计算每个 retire 端口对应的 buffer 头地址与是否写入
        genvar pn;
        for (pn = 0; pn < PORT_WIDTH; pn = pn + 1) begin : gen_buf_in
            assign head_addr[pn]  = buf_head + $countones(buf_we[idx][pn:0]) - 1;
            assign buf_in[pn]     = ~buf_v[head_addr[pn]] & buf_we[idx][pn];
        end

        always @(posedge clk or posedge rst) begin
            if (rst) begin
                for (integer i = 0; i < BUF_DEPTH; i = i + 1) begin
                    buf_entry[i] <= '0;
                end
            end else begin
                for (integer i = 0; i < PORT_WIDTH; i = i + 1) begin
                    if (buf_in[i]) begin
                        buf_entry[head_addr[i]] <= buf_wdata[i];
                    end
                end
            end
        end
        
        // buffer 头尾指针更新
        always @(posedge clk or posedge rst) begin
            if (rst) begin
                buf_head <= '0;
                buf_tail <= '0;
            end else begin
                buf_head <= buf_head + $countones(buf_in);
                if (buf_consume) begin//当前队首更新记录已经用于更新预测表，可以从 buffer 中移除了。
                    buf_tail <= buf_tail + 1'b1;
                end
            end
        end
        // buffer 有效位更新
        always @(posedge clk or posedge rst) begin
            if (rst) begin
                buf_v <= '0;
            end else begin
                for (integer i = 0; i < PORT_WIDTH; i = i + 1) begin
                    if (buf_in[i]) begin
                        buf_v[head_addr[i]] <= 1'b1;
                    end
                end
                if (buf_v[buf_tail] && buf_consume) begin
                    buf_v[buf_tail] <= 1'b0;//队首记录被消费，就把它标记为空
                end
            end
        end

        
        always @(posedge clk or posedge rst) begin
            if (rst) curr_state <= STATE_GET_TAG;
            else     curr_state <= next_state;
        end

        
        always @(*) begin
            case (curr_state)
                STATE_GET_TAG: next_state = buf_v[buf_tail] ? STATE_WR_DATA : STATE_GET_TAG;//get_tag:用 A 的地址读取旧信息 ；队首有记录 → 下一拍进入写数据状态；队首没记录 → 下一拍继续等待
                STATE_WR_DATA: next_state = STATE_GET_TAG;
                default:       next_state = STATE_GET_TAG;
            endcase
        end

        
        always @(*) begin
            case (curr_state)
                STATE_GET_TAG: begin
                    waddr         = buf_entry[buf_tail][61:56];
                    w_bhr[idx]     = '0;// BHT 写入 BHR
                    w_bhr_old[idx] = '0;
                    w_taken[idx]   = 1'b0;
                    we[idx]        = 1'b0;
                    buf_consume    = 1'b0;
                end
                STATE_WR_DATA: begin
                    waddr         = buf_entry[buf_tail][61:56];
                    w_bhr[idx]     = (origin_tag == w_tag) ? {origin_bhr[BHR_BITS-2:0], buf_entry[buf_tail][62]} : {{(BHR_BITS-1){1'b0}}, buf_entry[buf_tail][62]};
                    w_bhr_old[idx] = (origin_tag == w_tag) ? origin_bhr : '0;
                    w_taken[idx]   = buf_entry[buf_tail][62];
                    we[idx]        = 1'b1;
                    buf_consume    = 1'b1;
                end
                default: begin
                    waddr         = buf_entry[buf_tail][61:56];
                    w_bhr[idx]     = '0;
                    w_bhr_old[idx] = '0;
                    w_taken[idx]   = 1'b0;
                    we[idx]        = 1'b0;
                    buf_consume    = 1'b0;
                end
            endcase
        end

        always @(*) begin
            {w_brtype, w_tag, w_brdest} = buf_entry[buf_tail][55:0];
            w_pht_bank_addr[idx] = {buf_entry[buf_tail][31+PC_SPLICE_BITS-8:32], buf_entry[buf_tail][61:56], w_bhr_old[idx]};
            w_pht[idx]     = we[idx] && (w_brtype == CBR_DIRECT);
        end

        bht_mem bht_mem (
            .clka(clk),
            .wea(1'b0),
            .addra(bank_raddr[idx]),
            .dina('0),
            .douta(bank_r_bhr[idx]),
            .clkb(clk),
            .web(we[idx]),
            .addrb(waddr),
            .dinb(w_bhr[idx]),
            .doutb(origin_bhr)
        );

        btb_mem btb_mem (
            .clka(clk),
            .wea(1'b0),
            .addra(bank_raddr[idx]),
            .dina('0),
            .douta({bank_r_brtype[idx], bank_r_tag[idx], bank_r_brdest[idx]}),
            .clkb(clk),
            .web(we[idx]),
            .addrb(waddr),
            .dinb({w_brtype, w_tag, w_brdest}),
            .doutb({origin_brtype, origin_tag, origin_brdest})
        );
    end
endgenerate

//// legacy PHT update，由真正的双口 BRAM 支持
generate
    for (genvar pb = 0; pb < IN_WIDTH; pb = pb + 1) begin : gen_legacy_pht_queue
        reg [PHT_BANK_ADDR_BITS-1:0] fifo_addr [LEGACY_PHT_BUF_DEPTH-1:0];
        reg [LEGACY_PHT_BUF_DEPTH-1:0]                          fifo_taken;
        reg [LEGACY_PHT_BUF_BITS-1:0]                           fifo_head;
        reg [LEGACY_PHT_BUF_BITS-1:0]                           fifo_tail;
        reg [LEGACY_PHT_BUF_BITS:0]                             fifo_count;
        reg                                                    curr_state;
        reg [PHT_BANK_ADDR_BITS-1:0]                           pend_addr;
        reg                                                    pend_taken;
        reg [1:0]                                              old_ctr;
        reg [1:0]                                              new_ctr;

        always @(*) begin
            old_ctr = pht_doutb_bank[pb];
            if (pend_taken) begin
                new_ctr = (old_ctr == 2'b11) ? 2'b11 : (old_ctr + 2'b01);
            end else begin
                new_ctr = (old_ctr == 2'b00) ? 2'b00 : (old_ctr - 2'b01);
            end
        end

        always @(*) begin
            pht_web_bank[pb]   = 1'b0;
            pht_addrb_bank[pb] = '0;
            pht_dinb_bank[pb]  = '0;

            if (curr_state == LEGACY_PHT_RD_OLD) begin
                if (fifo_count != 0) begin
                    pht_addrb_bank[pb] = fifo_addr[fifo_tail];
                end
            end else begin
                pht_web_bank[pb]   = 1'b1;
                pht_addrb_bank[pb] = pend_addr;
                pht_dinb_bank[pb]  = new_ctr;
            end
        end

        always @(posedge clk or posedge rst) begin
            if (rst) begin
                fifo_head  <= '0;
                fifo_tail  <= '0;
                fifo_count <= '0;
                curr_state <= LEGACY_PHT_RD_OLD;
                pend_addr  <= '0;
                pend_taken <= 1'b0;
            end else begin
                reg [LEGACY_PHT_BUF_BITS-1:0] head_tmp;
                reg [LEGACY_PHT_BUF_BITS-1:0] tail_tmp;
                reg [LEGACY_PHT_BUF_BITS:0]   count_tmp;

                head_tmp  = fifo_head;
                tail_tmp  = fifo_tail;
                count_tmp = fifo_count;

                if ((curr_state == LEGACY_PHT_WR_NEW) && (fifo_count != 0)) begin
                    tail_tmp  = fifo_tail + LEGACY_PHT_BUF_BITS'(1);
                    count_tmp = fifo_count - 1'b1;
                end

                if (w_pht[pb] && (count_tmp < (LEGACY_PHT_BUF_BITS+1)'(LEGACY_PHT_BUF_DEPTH))) begin
                    fifo_addr[head_tmp]  <= w_pht_bank_addr[pb];
                    fifo_taken[head_tmp] <= w_taken[pb];
                    head_tmp             = head_tmp + LEGACY_PHT_BUF_BITS'(1);
                    count_tmp            = count_tmp + 1'b1;
                end

                fifo_head  <= head_tmp;
                fifo_tail  <= tail_tmp;
                fifo_count <= count_tmp;

                if ((curr_state == LEGACY_PHT_RD_OLD) && (fifo_count != 0)) begin
                    pend_addr  <= fifo_addr[fifo_tail];
                    pend_taken <= fifo_taken[fifo_tail];
                end

                if (curr_state == LEGACY_PHT_RD_OLD) begin
                    if (fifo_count != 0) begin
                        curr_state <= LEGACY_PHT_WR_NEW;
                    end
                end else begin
                    curr_state <= LEGACY_PHT_RD_OLD;
                end
            end
        end
    end
endgenerate


// 取指寄存器：暂存上一拍输入，形成流水
reg [PC_WIDTH-1:0]                pc_reg;
reg                               have_inst_reg;
reg [IN_WIDTH-1:0]                have_inst_table;
reg [63:0]                        bundle_issue_seq;
reg [63:0]                        bundle_seq_reg;



always @(posedge clk or posedge rst) begin
    if (rst) begin
        pc_reg        <= '0;
        have_inst_reg <= 1'b0;
        bundle_issue_seq <= '0;
        bundle_seq_reg <= '0;
    end else if (!icache_busy) begin
        pc_reg        <= pc_i;
        have_inst_reg <= have_inst_i;
        bundle_seq_reg <= bundle_issue_seq;
        if (have_inst_i) begin
            bundle_issue_seq <= bundle_issue_seq + 64'd1;
        end
    end else begin
    end
end


// 生成每个 lane 的输出 PC、指令、下一 PC、有效位等
generate
    for (genvar s = 0; s < IN_WIDTH; s = s + 1) begin : gen_out
        assign pc[s]             = pc_reg + PC_WIDTH'($unsigned(s) << 2);//对应正在处理的这组返回指令
        assign pc_table[s]       = pc_i   + PC_WIDTH'($unsigned(s) << 2);//提前形成 BTB 等预测表的查询地址
        assign inst[s]           = inst_i[s];
        assign pc_next[s]        = pre_taken[s] ? pre_brdest[s] : (pc[s] + PC_WIDTH'(32'd4));
        assign have_inst_table[s]= have_inst_reg & ~icache_busy & icache_rvalid;

        assign raddr[s]          = pc_table[s][9:4];//提取 BTB/旧 BHT 查询的行地址。
        for (genvar rp = 0; rp < PORT_WIDTH; rp = rp + 1) begin : gen_buf_we
            assign buf_we[s][rp] = (rt_pc[rp][2 +: FETCH_BANK_W] == FETCH_BANK_W'($unsigned(s))) &&
                                   rt_grant[rp] && (rt_brtype[rp] != NBR);
        end

        assign r_pht_bank_addr[s]= {pc[s][1+PC_SPLICE_BITS:4], r_bhr[s]};
        assign pht_addra_bank[s] = r_pht_bank_addr[s];
        assign lp[s]             = pht_douta_bank[s];

        assign have_inst_o[s]    = have_inst_table[s] & have_inst[s];
    end
endgenerate

// 根据 pc_table 低位选择 bank 读地址
always @(*) begin
    for (integer i = 0; i < IN_WIDTH; i = i + 1) begin
        bank_raddr[i] = '0;
    end
    for (integer i = 0; i < IN_WIDTH; i = i + 1) begin
        bank_raddr[pc_table[i][2 +: FETCH_BANK_W]] = raddr[i];
    end
end

// 从 bank 读出的 BTB/BHT 数据按 lane 分发给 r_* 信号
generate
    for (genvar s = 0; s < IN_WIDTH; s = s + 1) begin : gen_bank_out
        assign r_brdest[s] = bank_r_brdest[pc[s][2 +: FETCH_BANK_W]];
        assign r_tag[s]    = bank_r_tag[pc[s][2 +: FETCH_BANK_W]];
        assign r_brtype[s] = bank_r_brtype[pc[s][2 +: FETCH_BANK_W]];
        assign r_bhr[s]    = bank_r_bhr[pc[s][2 +: FETCH_BANK_W]];
    end
endgenerate

//// 打包 retire 侧写入 BTB buffer 的数据
generate
    for (genvar rp = 0; rp < PORT_WIDTH; rp = rp + 1) begin : gen_buf_wdata
        assign buf_wdata[rp] = {(rt_brdest[rp] != rt_pc[rp] + PC_WIDTH'(32'd4)), rt_pc[rp][9:4], rt_brtype[rp], rt_pc[rp][31:10], rt_brdest[rp]};
    end
endgenerate

// 短方向预测器训练门控always_comb begin
    br_short_dir_enable = 1'b1;
    rt_short_dir_enable = 1'b1;

    // 恢复原版训练门控：已经由 long path 接管的 cbr 不再继续训练 short。
    // 这样 recent bypass 对 short PHT 的可见性更接近 stable 语义。
    /*
    for (int i = 0; i < IN_WIDTH; i++) begin
        if (use_long_pred[i] && (br_brtype[i] == CBR_DIRECT)) begin
            br_short_dir_enable[i] = 1'b0;
        end
    end

    for (int p = 0; p < PORT_WIDTH; p++) begin
        if (rt_use_long[p] && (rt_brtype[p] == CBR_DIRECT)) begin
            rt_short_dir_enable[p] = 1'b0;
        end
    end
    */
end


// Redirect / valid gating（逻辑保持不变）
//遇到本组最早的预测跳转，就保留它及之前的指令，截断后面的指令，并转向它的预测目标。
always @(*) begin
    dbg_bundle_cut_inst = '0;
    if (ctrl_clear) begin
        have_inst   = '0;
        redirect    = 1'b1;
        redirect_pc = nxtpc_interrupt;
    end else if (ctrl_restore_pulse) begin
        have_inst   = '0;
        redirect    = 1'b1;
        redirect_pc = nxtpc_flush;
    end else if (!have_inst_reg) begin
        have_inst   = '0;
        redirect    = 1'b0;
        redirect_pc = '0;
    end else begin
        have_inst[0] = 1'b1;
        redirect     = 1'b0;
        redirect_pc  = '0;

        for (integer i = 1; i < IN_WIDTH; i = i + 1) begin
            have_inst[i] = pre_taken[i-1] ? 1'b0 : have_inst[i-1];//  只保留最早taken及之前的指令
        end

        for (integer i = IN_WIDTH-1; i >= 0; i = i - 1) begin
            if (pre_taken[i]) begin
                redirect    = 1'b1;
                redirect_pc = pre_brdest[i];//  选择最早taken的目标地址
            end
        end

        if (!icache_busy && icache_rvalid) begin
            dbg_bundle_cut_inst = IN_WIDTH - $countones(have_inst);
        end
    end
end

// RAS update:
下面保留原逻辑，直接加上中文注释。`_n` 表示组合逻辑计算出的下一状态，后续由时钟边沿保存。

```systemverilog
always @(*) begin
    reg do_push;  // 本拍前端是否执行压栈
    reg do_pop;   // 本拍前端是否请求弹栈
    reg found;    // 已选定操作或遇到预测跳转，不再考虑后面的指令
    reg [PC_WIDTH-1:0] push_addr; // 本拍准备压入的返回地址

    // 默认不执行任何前端栈操作
    do_push   = 1'b0;
    do_pop    = 1'b0;
    found     = 1'b0;
    push_addr = '0;

    // 默认保持两套栈的原有内容
    for (integer i = 0; i < RAS_DEPTH; i = i + 1) begin
        commit_ras_stack_n[i] = commit_ras_stack[i];
        active_ras_stack_n[i] = active_ras_stack[i];
    end

    // 默认保持两套栈的指针和有效数量
    commit_ras_sp_n  = commit_ras_sp;
    commit_ras_cnt_n = commit_ras_cnt;
    active_ras_sp_n  = active_ras_sp;
    active_ras_cnt_n = active_ras_cnt;

    // 按端口顺序处理后端反馈，更新基准栈
    // 使用阻塞赋值，后一个端口接着前一个端口的更新结果处理
    for (integer p = 0; p < PORT_WIDTH; p = p + 1) begin

        if (rt_is_call[p]) begin
            // 反馈为call：将该call的PC+4压入基准栈
            // sp指向下一次压栈的位置
            commit_ras_stack_n[commit_ras_sp_n] =
                rt_pc[p] + PC_WIDTH'(32'd4);

            // 压栈后指针前移；到达数组末尾则环绕回0
            if (commit_ras_sp_n == RAS_SP_LAST)
                commit_ras_sp_n = '0;
            else
                commit_ras_sp_n = commit_ras_sp_n + 1'b1;

            // 未满时有效数量加1；满时数量保持不变
            // 注意：满栈仍会写入并移动指针，覆盖最旧记录
            if (commit_ras_cnt_n != RAS_CNT_MAX) begin
                commit_ras_cnt_n = commit_ras_cnt_n + 1'b1;
            end

        end else if (rt_is_ret[p] && (commit_ras_cnt_n != '0)) begin
            // 反馈为ret且基准栈非空：弹出一个返回地址
            // 指针后退；在0位置时环绕到最后一个位置
            if (commit_ras_sp_n == 0)
                commit_ras_sp_n = RAS_SP_LAST;
            else
                commit_ras_sp_n = commit_ras_sp_n - 1'b1;

            // 有效数量减1，不需要擦除数组中的旧数据
            commit_ras_cnt_n = commit_ras_cnt_n - 1'b1;
        end
    end

    // clear优先级最高，覆盖前面已经算出的后端更新结果
    if (ctrl_clear) begin

        // 清空基准栈和前端预测栈的全部内容
        for (integer i = 0; i < RAS_DEPTH; i = i + 1) begin
            commit_ras_stack_n[i] = '0;
            active_ras_stack_n[i] = '0;
        end

        // 两套栈的指针和有效数量全部清零
        commit_ras_sp_n  = '0;
        commit_ras_cnt_n = '0;
        active_ras_sp_n  = '0;
        active_ras_cnt_n = '0;

    end else if (ctrl_restore_pulse) begin
        // 收到恢复请求：用基准栈恢复前端预测栈
        // 复制的是commit的下一状态，包含本拍后端反馈的更新
        for (integer i = 0; i < RAS_DEPTH; i = i + 1) begin
            active_ras_stack_n[i] = commit_ras_stack_n[i];
        end

        active_ras_sp_n  = commit_ras_sp_n;
        active_ras_cnt_n = commit_ras_cnt_n;

    end else begin
        // 没有clear或restore时，处理前端预测路径上的call/ret
        // 从本组最前面的指令开始扫描
        for (integer s = 0; s < IN_WIDTH; s = s + 1) begin

            // 只处理有效指令，且此前没有选定操作或遇到跳转边界
            if (!found && have_inst_o[s]) begin

                if (slot_is_call[s]) begin
                    // 遇到call：选定压栈，返回地址为该指令PC+4
                    do_push   = 1'b1;
                    push_addr = pc[s] + PC_WIDTH'(32'd4);

                    // 本拍已选定一次操作，不再处理后续指令
                    found = 1'b1;

                end else if (slot_is_ret[s]) begin
                    // 遇到ret：选定弹栈，不再处理后续指令
                    do_pop = 1'b1;
                    found  = 1'b1;
                end

                // 即使不是call/ret，只要预测跳转，
                // 后面的顺序指令也不能再操作RAS
                if (pre_taken[s]) begin
                    found = 1'b1;
                end
            end
        end

        // 根据扫描选出的操作，修改前端预测栈
        if (do_push) begin

            // 将返回地址写到当前sp指向的位置
            active_ras_stack_n[active_ras_sp] = push_addr;

            // 压栈后指针前移，到末尾时环绕回0
            if (active_ras_sp == RAS_SP_LAST)
                active_ras_sp_n = '0;
            else
                active_ras_sp_n = active_ras_sp + 1'b1;

            // 未满时数量加1，满时数量保持不变
            // 满栈仍会写入并移动指针，覆盖最旧记录
            if (active_ras_cnt != RAS_CNT_MAX) begin
                active_ras_cnt_n = active_ras_cnt + 1'b1;
            end

        end else if (do_pop && !active_ras_empty) begin
            // 请求弹栈且前端栈非空时，才真正弹出一项
            // 空栈时保持原状态
            if (active_ras_sp == 0)
                active_ras_sp_n = RAS_SP_LAST;
            else
                active_ras_sp_n = active_ras_sp - 1'b1;

            // 有效数量减1
            active_ras_cnt_n = active_ras_cnt - 1'b1;
        end
    end
end
```

// RAS 时序更新
always @(posedge clk or posedge rst) begin
    if (rst) begin
        active_ras_sp  <= '0;
        active_ras_cnt <= '0;
        commit_ras_sp  <= '0;
        commit_ras_cnt <= '0;
        for (integer i = 0; i < RAS_DEPTH; i = i + 1) begin
            active_ras_stack[i] <= '0;
            commit_ras_stack[i] <= '0;
        end
    end else begin
        active_ras_sp  <= active_ras_sp_n;
        active_ras_cnt <= active_ras_cnt_n;
        commit_ras_sp  <= commit_ras_sp_n;
        commit_ras_cnt <= commit_ras_cnt_n;
        for (integer i = 0; i < RAS_DEPTH; i = i + 1) begin
            active_ras_stack[i] <= active_ras_stack_n[i];
            commit_ras_stack[i] <= commit_ras_stack_n[i];
        end
    end
end

endmodule



// 长历史/异常方向预测器实例
direction_exception_predictor #(
    .IN_WIDTH         (IN_WIDTH),
    .PORT_WIDTH       (PORT_WIDTH),
    .MODE_ENTRIES     (32),
    .LONG_SLOTS       (LONG_SLOT_COUNT),
    .BHR_BITS         (LONG_BHR_BITS),
    .SAMPLE_THRESHOLD (UPGRADE_SAMPLE_WINDOW),
    .MISS_THRESHOLD   (UPGRADE_MISS_THRESHOLD),
    .PHT_INIT_STATE   (2'b10)
) direction_exception_predictor (
    .clk(clk),
    .rst(rst),
    .have_inst_i(have_inst_i),
    .pc_i(pc_i),
    .use_long_o(use_long_pred),
    .lp_o(lp_long),
    .dbg_base_hist_o(long_base_hist_dbg),
    .dbg_lookup_hist_o(long_lookup_hist_dbg),
    .dbg_slot_o(long_slot_dbg),
    .dbg_bypass_hit_o(long_bypass_hit_dbg),
    .dbg_bypass_addr_o(long_bypass_addr_dbg),
    .dbg_bypass_ctr_o(long_bypass_ctr_dbg),
    .dbg_final_ctr_o(),
    .dbg_ctr_src_o(long_ctr_src_dbg),
    .br_grant(br_grant),
    .br_pc(br_pc),
    .br_brtype(br_brtype),
    .br_taken(br_taken),
    .rt_grant(rt_grant),
    .rt_pc(rt_pc),
    .rt_brtype(rt_brtype),
    .rt_brdest(rt_brdest),
    .rt_exception(rt_exception),
    .rt_use_long_o(rt_use_long)
);


// 短历史/局部方向预测器实例
direction_predict_v4 #(
    .IN_WIDTH        (IN_WIDTH),
    .PORT_WIDTH      (PORT_WIDTH),
    .BHT_IDX_BITS    (SHORT_BHT_IDX_BITS),
    .BHR_BITS        (SHORT_BHR_BITS),
    .PC_SPLICE_BITS  (SHORT_PC_SPLICE_BITS),
    .PHT_BANK_BITS   (3),
    .BUF_BITS        (3),
    .PHT_INIT_STATE  (2'b10)
) direction_predict_v4 (
    .clk(clk),
    .rst(rst),
    .have_inst_i(have_inst_i),
    .pc_i(pc_i),
    .lp(lp_n4),
    .dbg_base_hist_o(short_base_hist_dbg),
    .dbg_prefix_hist_o(short_prefix_hist_dbg),
    .dbg_effective_hist_o(short_effective_hist_dbg),
    .dbg_pht_row_o(short_pht_row_dbg),
    .dbg_ctr_idx_o(short_ctr_idx_dbg),
    .dbg_bypass_hit_o(short_bypass_hit_dbg),
    .dbg_final_ctr_o(),
    .dbg_ctr_src_o(short_ctr_src_dbg),
    .br_grant(br_grant),
    .br_pc(br_pc),
    .br_brtype(br_brtype),
    .br_taken(br_taken),
    .br_dir_enable_i(br_short_dir_enable),
    .rt_grant(rt_grant),
    .rt_pc(rt_pc),
    .rt_brtype(rt_brtype),
    .rt_brdest(rt_brdest),
    .rt_exception(rt_exception),
    .rt_dir_enable_i(rt_short_dir_enable)
);
//btb_ram_双端口_64行*56位
module bp_btb_ram #(
    parameter BTB_RAM_DEPTH = 64,
    parameter BRTYPE_WIDTH  = 2,
    parameter TAG_WIDTH     = 22,
    parameter BRDEST_WIDTH  = 32,

    parameter ADDR_WIDTH =
        (BTB_RAM_DEPTH <= 1) ? 1 : $clog2(BTB_RAM_DEPTH)
)(
    input  wire clka,
    input  wire wea,
    input  wire [ADDR_WIDTH-1:0] addra,

    input  wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] dina,
    output wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] douta,

    input  wire clkb,
    input  wire web,
    input  wire [ADDR_WIDTH-1:0] addrb,

    input  wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] dinb,
    output wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] doutb
);

    localparam DATA_WIDTH =
        BRTYPE_WIDTH + TAG_WIDTH + BRDEST_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:BTB_RAM_DEPTH-1];

    reg [DATA_WIDTH-1:0] douta_r;
    reg [DATA_WIDTH-1:0] doutb_r;

    // 与原设计一致：两个端口都使用 clka。
    always @(posedge clka) begin

        // 两个端口可以同时写入。
        // 同地址同时写入时，B 优先。
        if (wea)
            mem[addra] <= dina;

        if (web)
            mem[addrb] <= dinb;

        // A 端口读取及写数据旁路。
        if (web && (addrb == addra))
            douta_r <= dinb;
        else if (wea)
            douta_r <= dina;
        else
            douta_r <= mem[addra];

        // B 端口读取及写数据旁路。
        if (web)
            doutb_r <= dinb;
        else if (wea && (addra == addrb))
            doutb_r <= dina;
        else
            doutb_r <= mem[addrb];

    end

    assign douta = douta_r;
    assign doutb = doutb_r;

endmodule


//保存计数器_双端口_8行*64位
module sync_dp_bram_bp_pht #(
    parameter ADDR_W = 6,
    parameter DATA_W = 8,
    parameter [DATA_W-1:0] INIT_VALUE = 0
)(
    input  wire clka,
    input  wire wea,
    input  wire [ADDR_W-1:0] addra,
    input  wire [DATA_W-1:0] dina,
    output wire [DATA_W-1:0] douta,

    input  wire clkb,
    input  wire web,
    input  wire [ADDR_W-1:0] addrb,
    input  wire [DATA_W-1:0] dinb,
    output wire [DATA_W-1:0] doutb
);

    localparam DEPTH = 1 << ADDR_W;

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [DATA_W-1:0] douta_r;
    reg [DATA_W-1:0] doutb_r;

    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = INIT_VALUE;

        douta_r = INIT_VALUE;
        doutb_r = INIT_VALUE;
    end

    // A 端口：同步读取，read-first。
    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;

        douta_r <= mem[addra];
    end

  
    always @(posedge clkb) begin
        if (web)
            mem[addrb] <= dinb;

        doutb_r <= mem[addrb];
    end

    assign douta = douta_r;
    assign doutb = doutb_r;

endmodule