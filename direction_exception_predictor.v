// 术语：lane=本组第几路指令；bank=独立存储分块；slot=长预测资源槽。
// 命名：_now=当前组合查询；_q=寄存查询上下文；_tmp=本拍合并更新临时量；dbg=观察信号。
// reg/wire是声明类别，是否为时钟状态由赋值位置决定；[W-1:0]是W位，名称后的数组维度表示多项。
// Requires SystemVerilog: wire/reg style with unpacked array ports and state.

// ============================================================================
// 长历史补充方向预测器
// 数据流：PC命中已升级mode/slot -> shadow长历史作PHT地址 -> 同步读取两位计数器 -> recent旁路 -> lp_o。
// 升级流：统计CBR反馈的样本/错误/候选历史 -> 到窗口阈值时尝试分配空闲slot -> 产生seed训练事件。
// 每个slot独立维护PHT、历史、4项训练FIFO和4项旁路；同拍同slot只让最老lane得到查询读口。
// 注意rt_*是后端反馈接口名称，不保证来自真正退休；br_pc在当前实现保留接口但未用于内部地址计算。
// 本文件没有清空/恢复脉冲输入，修复由rt_exception触发epoch切换；slot运行时无淘汰释放路径。
// 容量公式：每slot PHT有2^BHR_BITS项×2位；实际历史长度/槽数/阈值取决于上层参数覆盖。
// ============================================================================
module direction_exception_predictor #(
    // BRTYPE_WIDTH为类型位数；EXCPT_WIDTH为异常编码位数。
    parameter PC_WIDTH=32, DATA_WIDTH=32, BRTYPE_WIDTH=2, EXCPT_WIDTH=4,
    // 前端并行查询的指令槽位数
    parameter integer IN_WIDTH          = 4,
    // 后端反馈端口数
    parameter integer PORT_WIDTH        = 2,
    // 长预测器模式表项数；按折叠PC定位，保存tag、样本数、错误数、候选历史和升级状态。
    parameter integer MODE_ENTRIES      = 16,
    // 可分配的长预测槽数量；每个slot有独立PC标签、历史、PHT RAM、更新FIFO和bypass。
    parameter integer LONG_SLOTS        = 2,
    // 每项分支历史的位数；直接作为PHT地址。
    parameter integer BHR_BITS          = 12,
    // 升级统计的样本窗口上限；样本首次到达该值时检查错误阈值
    parameter integer SAMPLE_THRESHOLD  = 96,
    // 达到样本窗口时，错误数至少为该值且有空闲slot，才尝试升级长预测
    parameter integer MISS_THRESHOLD    = 64,
    // PHT两位计数器初值
    parameter [1:0]  PHT_INIT_STATE    = 2'b10
) (
    input wire                                                 clk,
    input wire                                                 rst,

    // 当前前端查询请求是否有效；
    input wire                                                 have_inst_i,
    // 本次取指组起始PC；第i路指令地址按pc_i+4*i生成
    input wire [PC_WIDTH-1:0]                                  pc_i,
    // 逐lane长预测采用标志：have_q、长路径命中、读口分配均有效才为1；为0时上层应回退短预测。
    output reg [IN_WIDTH-1:0]                                  use_long_o,
    // 每lane的长预测最终2位计数器；只有有效、命中长路径且获读口时输出，否则为00，需结合use_long_o使用。
    output reg [1:0] lp_o [IN_WIDTH-1:0],
    
    // 调试输出：每lane基础历史；短路径来自当前shadow_bht，长路径为查询时寄存的基础历史。
    output reg [BHR_BITS-1:0] dbg_base_hist_o [IN_WIDTH-1:0],
    // 调试输出：长PHT本次实际使用的历史地址，BHR_BITS位；当前与寄存的base历史相同。
    output reg [BHR_BITS-1:0] dbg_lookup_hist_o [IN_WIDTH-1:0],
    // 调试输出：每lane的long slot编号，不是fetch bank；需结合use_long_o判断该编号是否有效。
    output reg [((LONG_SLOTS<=2)?1:$clog2(LONG_SLOTS))-1:0] dbg_slot_o [IN_WIDTH-1:0],
    // 调试输出：逐lane查询是否命中最近更新旁路；需要同时满足本模块的查询有效条件。
    output reg [IN_WIDTH-1:0]                                  dbg_bypass_hit_o,
    // 调试输出：命中的长bypass条目地址，即PHT历史索引，不是指令PC/跳转目标；未命中为0。
    output reg [BHR_BITS-1:0] dbg_bypass_addr_o [IN_WIDTH-1:0],
    // 调试输出：命中的长bypass两位计数器；未命中为00，需同时看hit标志。
    output reg [1:0] dbg_bypass_ctr_o [IN_WIDTH-1:0],
    // 调试输出：最终采用的2位计数器，已包含RAM值/bypass覆盖和有效性选择。
    output reg [1:0] dbg_final_ctr_o [IN_WIDTH-1:0],
    // 调试输出：最终计数器来源编码，0=RAM、1=recent bypass；无效查询也置0，不能据此单独判断有效。
    output reg [1:0] dbg_ctr_src_o [IN_WIDTH-1:0],

    // 前端逐lane接受/有效标志，来自组内截断后的有效指令
    input wire [IN_WIDTH-1:0]                                  br_grant,
    // 前端已接受指令的PC数组；短路径用来定位投机BHT项，长路径接口保留此输入但实际用已寄存lane_slot_q定位。
    input wire [PC_WIDTH-1:0] br_pc [IN_WIDTH-1:0],
    // 前端每lane预解码得到的分支类型；这里只对CBR_DIRECT条件分支移入投机方向历史。
    input wire [BRTYPE_WIDTH-1:0] br_brtype [IN_WIDTH-1:0],
    // 前端每lane的预测方向，1跳/0不跳；用于投机历史，不能当成后端真实结果。
    input wire [IN_WIDTH-1:0]                                  br_taken,

    // 后端逐端口反馈有效；结合CBR_DIRECT过滤条件分支；反馈来自执行/写回还是退休取决于上层接线。
    input wire [PORT_WIDTH-1:0]                                rt_grant,
    // 后端反馈的分支自身PC；计算训练表位置、模式表索引与标签，不是分支目标PC。
    input wire [PC_WIDTH-1:0] rt_pc [PORT_WIDTH-1:0],
    // 后端逐端口分支类型；本预测器只用CBR_DIRECT反馈训练方向历史/计数器。
    input wire [BRTYPE_WIDTH-1:0] rt_brtype [PORT_WIDTH-1:0],
    // 后端真实下一条PC；不跳时应为rt_pc+4；本文件以它是否不同于PC+4推导真实taken。
    input wire [PC_WIDTH-1:0] rt_brdest [PORT_WIDTH-1:0],
    // 后端异常/预测错误编码；等于EXCPT_BRWRONG时视为预测错误，不是简单的单比特方向。
    input wire [EXCPT_WIDTH-1:0] rt_exception [PORT_WIDTH-1:0], // 异常信息：每个反馈端口一项
    // 反馈端口当前是否命中已升级且slot标签有效的长预测记录；不是保存的“当初取指实际使用long”标志。
    output reg [PORT_WIDTH-1:0]                                rt_use_long_o
);
    // 类型编码0：非分支；常量保留以对齐上层接口，本模块通常只判断CBR_DIRECT。
    localparam [1:0] NBR = 2'd0;
    // 类型编码1：无条件直接跳转jal；本方向预测器不训练该类型。
    localparam [1:0] MBR_DIRECT = 2'd1;
    // 类型编码2：条件直接分支B型；这是本模块方向预测/历史训练处理的类型。
    localparam [1:0] CBR_DIRECT = 2'd2;
    // 类型编码3：无条件间接跳转jalr；本方向预测器不训练该类型。
    localparam [1:0] MBR_INDIRECT = 2'd3;
    // 错误编码1：后端发现真实next PC与预测next PC不一致；用于统计错误及epoch修复。
    localparam [3:0] EXCPT_BRWRONG = 4'd1;


    // mode表索引位数log2(MODE_ENTRIES)，PC[PC_WIDTH-1:2]按此宽度异或折叠。
    localparam integer MODE_IDX_BITS = $clog2(MODE_ENTRIES);
    // long slot编号宽度，槽数<=2时至少用1位，避免零宽向量。
    localparam integer SLOT_IDX_W    = (LONG_SLOTS <= 2) ? 1 : $clog2(LONG_SLOTS);
    // 模式/slot标签位宽=PC_WIDTH-2，保存指令PC除去最低两位，防止折叠索引冲突误命中。
    localparam integer MODE_TAG_W    = PC_WIDTH - 2;
    // 样本计数器位宽，能表示0到SAMPLE_THRESHOLD（含上限）。
    localparam integer SAMPLE_W      = (SAMPLE_THRESHOLD <= 1) ? 1 : $clog2(SAMPLE_THRESHOLD + 1);
    // 错误计数器位宽，按SAMPLE_THRESHOLD+1计算，因错误数最多等于样本数。
    localparam integer MISS_W        = (SAMPLE_THRESHOLD <= 1) ? 1 : $clog2(SAMPLE_THRESHOLD + 1);

    // 长预测器每slot更新FIFO的指针位数，固定2位。
    localparam integer UPD_FIFO_BITS  = 2;
    // 每slot更新FIFO深度=2^UPD_FIFO_BITS=4。
    localparam integer UPD_FIFO_DEPTH = (1 << UPD_FIFO_BITS);
    // 最近更新旁路表的循环写入指针宽度，固定2位。
    localparam integer BYPASS_BITS    = 2;
    // 每组旁路表项数2^BYPASS_BITS=4；保存最近生成的计数器值，不是等待执行的训练队列。
    localparam integer BYPASS_DEPTH   = (1 << BYPASS_BITS);

    // 长训练状态0：检查队首；seed直接写初始值，普通请求发起旧计数读取。
    localparam [1:0] UPD_IDLE  = 2'd0;
    // 长训练状态1：取得RAM旧计数、应用bypass，计算并保存新值，同时更新recent旁路。
    localparam [1:0] UPD_WAIT  = 2'd1;
    // 长训练状态2：将pending新计数写入RAM，并弹出队首请求。
    localparam [1:0] UPD_WRITE = 2'd2;

    // 逐mode项有效位，说明该项记录了一个分支PC。
    reg [MODE_ENTRIES-1:0]                      mode_valid;
    // 逐mode项升级标志，表示已给该分支分配long slot；仍需slot有效和tag匹配。
    reg [MODE_ENTRIES-1:0]                      mode_upgraded;
    // 每个mode项记录的完整指令PC标签PC[PC_WIDTH-1:2]，用于消除索引冲突。
    reg [MODE_TAG_W-1:0] mode_tag [MODE_ENTRIES-1:0];
    // 每mode项观察到的条件分支反馈样本数，达到窗口上限后停止增加。
    reg [SAMPLE_W-1:0] mode_sample_ctr [MODE_ENTRIES-1:0];
    // 每mode项在样本窗口内出现EXCPT_BRWRONG的次数，用于升级门槛。
    reg [MISS_W-1:0] mode_miss_ctr [MODE_ENTRIES-1:0];
    // 尚未升级的分支也积累BHR_BITS位真实历史，升级时作为long slot初始历史。
    reg [BHR_BITS-1:0] mode_candidate_hist [MODE_ENTRIES-1:0];
    // 每mode项升级后所分配的long slot编号，mode_upgraded和slot tag检查有效后才使用。
    reg [SLOT_IDX_W-1:0] mode_long_slot_id [MODE_ENTRIES-1:0];

    // 逐long slot分配有效位；分配后置1，此文件没有运行时淘汰/释放slot的路径。
    reg [LONG_SLOTS-1:0]                       long_slot_valid;
    // 每long slot所属分支的完整PC标签，与mode标签一起确认归属。
    reg [MODE_TAG_W-1:0] long_slot_tag [LONG_SLOTS-1:0];
    // 每long slot的前端投机历史，移入被接受查询的预测方向。
    reg [BHR_BITS-1:0] active_bhr [LONG_SLOTS-1:0];
    // 每long slot由后端真实条件分支结果维护的基准历史。
    reg [BHR_BITS-1:0] commit_bhr [LONG_SLOTS-1:0];
    // 每long slot寄存后的查询可见历史，epoch一致取active，否则取commit。
    reg [BHR_BITS-1:0] shadow_bhr [LONG_SLOTS-1:0];
    // 每个历史项/long slot对应的投机代际标签；等于active_epoch时才把active历史视为当前路径。
    reg [7:0] epoch_tag [LONG_SLOTS-1:0];
    // 当前投机历史代际；条件分支反馈错误时加1，使旧代际active历史失效。
    reg [7:0]                                  active_epoch;

    // 寄存后的查询有效位，用于对齐同步PHT读数据和查询上下文；不直接代表后端反馈有效。
    reg                                        have_q;
    // 当前逐lane是否命中已升级mode及有效slot；命中不代表一定获得该slot的读口。
    reg [IN_WIDTH-1:0]                         lane_use_long_now;
    // 寄存的长路径命中标志，与同步RAM读出对齐。
    reg [IN_WIDTH-1:0]                         lane_use_long_q;
    // 当前逐lane是否实际获得对应long slot的读口；同slot仅最老lane获准。
    reg [IN_WIDTH-1:0]                         lane_lookup_valid_now;
    // 寄存的读口分配有效标志，与lane_use_long_q共同产生use_long_o。
    reg [IN_WIDTH-1:0]                         lane_lookup_valid_q;
    // 当前逐lane匹配到的long slot编号。
    reg [SLOT_IDX_W-1:0] lane_slot_now [IN_WIDTH-1:0];
    // 寄存的long slot编号，输出选PHT结果及投机更新使用。
    reg [SLOT_IDX_W-1:0] lane_slot_q [IN_WIDTH-1:0];
    // 当前逐lane从匹配slot的shadow_bhr读取的基础历史。
    reg [BHR_BITS-1:0] lane_base_hist_now [IN_WIDTH-1:0];
    // 寄存的查询基础历史，供调试观察，和本次RAM结果对齐。
    reg [BHR_BITS-1:0] lane_base_hist_q [IN_WIDTH-1:0];
    // 寄存的实际长PHT查询地址；当前与lane_base_hist_q来自同一个历史值，用于旁路匹配。
    reg [BHR_BITS-1:0] lane_lookup_hist_q [IN_WIDTH-1:0];
    // 当前查询的逐lane PC=pc_i+4*i，组合产生；lane只是指令槽位，不是bank编号。
    reg [PC_WIDTH-1:0] lane_pc_now [IN_WIDTH-1:0];

    // 每端口是否为有效条件分支反馈=rt_grant且类型为CBR_DIRECT。
    reg [PORT_WIDTH-1:0]                       rt_is_dir;
    // 按真实next PC是否不等于PC+4推导出的真实方向，供历史移位和计数器训练。
    reg [PORT_WIDTH-1:0]                       rt_taken;
    // 后端反馈是否标记EXCPT_BRWRONG；与有效条件分支相与后才触发全局epoch切换。
    reg [PORT_WIDTH-1:0]                       rt_misp;
    // 后端反馈分支PC折叠得到的mode表索引。
    reg [MODE_IDX_BITS-1:0] rt_mode_idx [PORT_WIDTH-1:0];
    // 后端反馈分支的PC标签，区分mode索引碰撞的不同指令。
    reg [MODE_TAG_W-1:0] rt_mode_tag [PORT_WIDTH-1:0];
    // 后端PC是否匹配当前有效mode项，只表明统计记录命中，不保证已经升级。
    reg [PORT_WIDTH-1:0]                       rt_mode_hit;
    // 当前mode项无效或未升级时允许替换；已升级项即使tag冲突也不被本逻辑替换。
    reg [PORT_WIDTH-1:0]                       rt_mode_replace_ok;
    // 后端PC命中已升级mode、对应slot有效且slot tag也匹配，才能按long路径训练。
    reg [PORT_WIDTH-1:0]                       rt_mode_upgraded_hit;
    // 从mode项取出的long slot编号，只有命中标志成立才代表有效归属。
    reg [SLOT_IDX_W-1:0] rt_slot_id [PORT_WIDTH-1:0];
    // 本拍任一有效条件分支反馈出错则为1；切换epoch并抑制本拍新的前端投机历史移入。
    reg                                        mispred_any;
    // 发生错误时应使用的下一代际编号；组合计算，无错误时保持当前代际。
    reg [7:0]                                  epoch_next;

    // 每long slot的PHT A口查询地址，等于该slot的shadow历史；每slot每拍只发一条查询。
    reg [BHR_BITS-1:0] pht_addra_slot [LONG_SLOTS-1:0];
    // 每long slot的PHT A口同步读出的两位计数器。
    reg [1:0] pht_douta_slot [LONG_SLOTS-1:0];
    // 每long slot PHT B口写使能，seed直写或普通训练WRITE阶段置1。
    reg [LONG_SLOTS-1:0]                       pht_web_slot;
    // 每long slot PHT B口训练地址；IDLE取队首，WRITE取pend_addr。
    reg [BHR_BITS-1:0] pht_addrb_slot [LONG_SLOTS-1:0];
    // 每long slot PHT B口写数据，两位seed计数器或pend_new_ctr。
    reg [1:0] pht_dinb_slot [LONG_SLOTS-1:0];
    // 每long slot PHT B口读取的旧两位计数器，WAIT阶段消费。
    reg [1:0] pht_doutb_slot [LONG_SLOTS-1:0];

    // 每slot每项长训练请求的PHT地址，即移入本次结果之前的基准历史。
    reg [BHR_BITS-1:0] upd_fifo_addr [LONG_SLOTS-1:0][UPD_FIFO_DEPTH-1:0];
    // 每slot每项训练请求的真实方向。
    reg [UPD_FIFO_DEPTH-1:0] upd_fifo_taken [LONG_SLOTS-1:0];
    // 每slot每项是否为升级时的种子初始化请求；seed直接写预先算好的计数器。
    reg [UPD_FIFO_DEPTH-1:0] upd_fifo_seed [LONG_SLOTS-1:0];
    // 每slot每项seed请求待写的两位初始训练值；普通请求不使用该字段。
    reg [1:0] upd_fifo_seed_ctr [LONG_SLOTS-1:0][UPD_FIFO_DEPTH-1:0];
    // 每slot长训练FIFO下一次入队位置。
    reg [UPD_FIFO_BITS-1:0] upd_fifo_head [LONG_SLOTS-1:0];
    // 每slot长训练FIFO当前队首位置。
    reg [UPD_FIFO_BITS-1:0] upd_fifo_tail [LONG_SLOTS-1:0];
    // 每slot长训练FIFO占用项数，多一位以表示满深度4。
    reg [UPD_FIFO_BITS:0] upd_fifo_count [LONG_SLOTS-1:0];
    // 每slot长训练当前FSM状态，IDLE/WAIT/WRITE分别独立运行。
    reg [1:0] upd_state [LONG_SLOTS-1:0];
    // 每slot普通长训练请求已捕获的PHT地址，从发起读到写回保持。
    reg [BHR_BITS-1:0] pend_addr [LONG_SLOTS-1:0];
    // pending训练请求的真实方向；从FIFO取出后保存，直到完成更新。
    reg [LONG_SLOTS-1:0]                                   pend_taken;
    // 每slot WAIT阶段计算出的两位新计数器，WRITE阶段写RAM。
    reg [1:0] pend_new_ctr [LONG_SLOTS-1:0];

    // recent bypass各项有效位；短路径按fetch bank/subbank分组，长路径按long slot分组。
    reg [BYPASS_DEPTH-1:0] bypass_valid [LONG_SLOTS-1:0];
    // 每slot的recent bypass地址标签，即历史索引，不是PC或跳转目标。
    reg [BHR_BITS-1:0] bypass_addr [LONG_SLOTS-1:0][BYPASS_DEPTH-1:0];
    // recent bypass保存的最新两位计数器，可覆盖查询RAM值，也供后续训练读旧值时使用。
    reg [1:0] bypass_ctr [LONG_SLOTS-1:0][BYPASS_DEPTH-1:0];
    // 每组bypass下一个可替换位置；有同地址项时原位更新，否则在指针位置写入并循环前移。
    reg [BYPASS_BITS-1:0] bypass_ptr [LONG_SLOTS-1:0];


    // 将PC除低两位外的地址位异或折叠为mode表索引，另用完整tag排除索引冲突。
    function automatic reg [MODE_IDX_BITS-1:0] pc_mode_idx(
        // PC折叠/取tag函数的输入地址，是指令自身地址。
        input reg [PC_WIDTH-1:0] pc
    );
        // 函数或组合块中的局部表索引；短路径为PC折叠结果，长路径为mode表索引，具体位宽见声明。
        reg [MODE_IDX_BITS-1:0] idx;
        // PC异或折叠函数中被遍历的原PC位编号。
        integer bit_i;
        // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
        integer slot;
        begin
            idx = '0;
            for (bit_i = 2; bit_i < PC_WIDTH; bit_i = bit_i + 1) begin
                slot = (bit_i - 2) % MODE_IDX_BITS;
                idx[slot] = idx[slot] ^ pc[bit_i];
            end
            return idx;
        end
    endfunction

    // 返回PC[PC_WIDTH-1:2]作为完整指令标签；低两位按4字节指令对齐省略。
    function automatic reg [MODE_TAG_W-1:0] pc_mode_tag(
        // PC折叠/取tag函数的输入地址，是指令自身地址。
        input reg [PC_WIDTH-1:0] pc
    );
        return pc[PC_WIDTH-1 : 2];
    endfunction

    // 两位饱和更新：taken=1向11递增，taken=0向00递减；最高位是预测方向，端点不会溢出。
    function automatic reg [1:0] sat2_update(
        // sat2_update函数输入：更新前的两位饱和计数器。
        input reg [1:0] cur,
        // 函数输入的方向位，1跳/0不跳；具体是预测值还是真实值由调用处决定。
        input reg       taken
    );
        // sat2_update的局部下一计数器值，按taken做饱和增减，返回给调用者。
        reg [1:0] nxt;
        begin
            nxt = cur;
            unique case (cur)
                2'b00: nxt = taken ? 2'b01 : 2'b00;
                2'b01: nxt = taken ? 2'b10 : 2'b00;
                2'b10: nxt = taken ? 2'b11 : 2'b01;
                2'b11: nxt = taken ? 2'b11 : 2'b10;
                default: nxt = 2'b10;
            endcase
            // 返回计算值；函数不直接写PHT RAM，由调用者安排写回。
            return nxt;
        end
    endfunction

    // 历史移位：丢掉最老的高位，最低位追加本次taken；只有1位历史时直接保存taken。
    function automatic reg [BHR_BITS-1:0] bhr_shift_in(
        // bhr_shift_in函数输入：移入当前结果之前的历史。
        input reg [BHR_BITS-1:0] bhr_old,
        // 函数输入的方向位，1跳/0不跳；具体是预测值还是真实值由调用处决定。
        input reg                taken
    );
        // 移入一个结果后的历史，丢弃最高旧位、低位追加taken；也用于投机历史更新临时值。
        reg [BHR_BITS-1:0] bhr_new;
        begin
            if (BHR_BITS == 1) begin
                bhr_new = BHR_BITS'(taken);
            end else begin
                bhr_new = {bhr_old[BHR_BITS-2:0], taken};
            end
            return bhr_new;
        end
    endfunction

    always @(*) begin
        // 前端查询第i路PC=起始PC+4*i；本模块接收br_pc但当前投机更新使用已捕获的slot编号。
        for (integer i = 0; i < IN_WIDTH; i++) begin
            // 逐lane形成指令自身PC；左移2等于乘4。bank编号随后按地址提取，不一定等于lane编号。
            lane_pc_now[i] = pc_i + PC_WIDTH'($unsigned(i) << 2);
        end
    end

  
    always @(*) begin
        // 本次组合查询中各long slot读口是否已被更老lane占用，防止同拍多个地址争用同一端口。
        reg [LONG_SLOTS-1:0] slot_claimed;

        // 默认所有lane不命中、无读口；按lane从老到新分配每slot唯一查询端口。
        lane_use_long_now     = '0;
        lane_lookup_valid_now = '0;
        lane_slot_now         = '{default: '0};
        lane_base_hist_now    = '{default: '0};
        pht_addra_slot        = '{default: '0};
        slot_claimed          = '0;

        for (integer i = 0; i < IN_WIDTH; i++) begin
            // 函数或组合块中的局部表索引；短路径为PC折叠结果，长路径为mode表索引，具体位宽见声明。
            reg [MODE_IDX_BITS-1:0] idx;
            // 局部完整PC标签，通常是PC[PC_WIDTH-1:2]，用于mode/slot归属比较。
            reg [MODE_TAG_W-1:0]    tag;
            // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
            reg [SLOT_IDX_W-1:0]    slot;
            // 当前lane是否命中已升级mode及同tag有效slot的组合结果。
            reg                     mode_hit;

            idx      = pc_mode_idx(lane_pc_now[i]);
            tag      = pc_mode_tag(lane_pc_now[i]);
            slot     = mode_long_slot_id[idx];
            // 必须同时命中有效mode、已升级标志、有效slot及两处完整PC tag，才认作长路径分支。
            mode_hit = mode_valid[idx] && mode_upgraded[idx] &&
                       (mode_tag[idx] == tag) &&
                       long_slot_valid[slot] &&
                       (long_slot_tag[slot] == tag);

            if (mode_hit) begin
                lane_use_long_now[i]  = 1'b1;
                lane_slot_now[i]      = slot;
                lane_base_hist_now[i] = shadow_bhr[slot];

                // 该slot尚未被更老lane占用才发送RAM查询；后续争用lane不能使用long输出，上层回退short。
                if (!slot_claimed[slot]) begin
                    lane_lookup_valid_now[i] = 1'b1;
                    pht_addra_slot[slot]     = shadow_bhr[slot];
                    slot_claimed[slot]       = 1'b1;
                end
            end
        end
    end

    always @(*) begin
        // 输出采用标志同时检查请求有效、长记录命中和读口分配；无有效long结果不能误用lp_o=00。
        use_long_o       = have_q ? (lane_use_long_q & lane_lookup_valid_q) : '0;
        lp_o             = '{default: '0};
        dbg_base_hist_o  = '{default: '0};
        dbg_lookup_hist_o= '{default: '0};
        dbg_slot_o       = '{default: '0};
        dbg_bypass_hit_o = '0;
        dbg_bypass_addr_o= '{default: '0};
        dbg_bypass_ctr_o = '{default: '0};
        dbg_final_ctr_o  = '{default: '0};
        dbg_ctr_src_o    = '{default: '0};

        for (integer i = 0; i < IN_WIDTH; i++) begin
            // 当前lane最终候选计数器：先取RAM值，再允许匹配bypass覆盖。
            reg [1:0] ctr_sel;
            // 局部旁路命中标志，循环匹配recent表时产生，最终再做查询有效门控。
            reg       bypass_hit;
            // 当前lane匹配的bypass历史地址，未命中时为0，供调试输出。
            reg [BHR_BITS-1:0] matched_bypass_addr;
            // 当前lane匹配的bypass两位计数器，未命中时为00，供调试输出。
            reg [1:0]          matched_bypass_ctr;

            ctr_sel            = pht_douta_slot[lane_slot_q[i]];
            bypass_hit         = 1'b0;
            matched_bypass_addr= '0;
            matched_bypass_ctr = '0;

            // 有效long查询才允许bypass覆盖及输出计数器；旁路地址比较使用当次寄存历史。
            if (have_q && lane_use_long_q[i] && lane_lookup_valid_q[i]) begin
                for (integer b = 0; b < BYPASS_DEPTH; b++) begin
                    if (bypass_valid[lane_slot_q[i]][b] &&
                        (bypass_addr[lane_slot_q[i]][b] == lane_lookup_hist_q[i])) begin
                        ctr_sel             = bypass_ctr[lane_slot_q[i]][b];
                        bypass_hit          = 1'b1;
                        matched_bypass_addr = bypass_addr[lane_slot_q[i]][b];
                        matched_bypass_ctr  = bypass_ctr[lane_slot_q[i]][b];
                    end
                end
                lp_o[i] = ctr_sel;
            end

            dbg_base_hist_o[i]   = lane_base_hist_q[i];
            dbg_lookup_hist_o[i] = lane_lookup_hist_q[i];
            dbg_slot_o[i]        = lane_slot_q[i];
            dbg_bypass_hit_o[i]  = have_q && lane_lookup_valid_q[i] && bypass_hit;
            dbg_bypass_addr_o[i] = matched_bypass_addr;
            dbg_bypass_ctr_o[i]  = matched_bypass_ctr;
            dbg_final_ctr_o[i]   = lp_o[i];
            dbg_ctr_src_o[i]     = have_q && lane_lookup_valid_q[i] ? (bypass_hit ? 2'd1 : 2'd0) : 2'd0;
        end
    end

    always @(*) begin
        // 后端反馈译码：查询mode/slot归属，决定统计候选、训练已升级slot还是允许替换未升级mode。
        rt_is_dir            = '0;
        rt_taken             = '0;
        rt_misp              = '0;
        rt_mode_idx          = '{default: '0};
        rt_mode_tag          = '{default: '0};
        rt_mode_hit          = '0;
        rt_mode_replace_ok   = '0;
        rt_mode_upgraded_hit = '0;
        rt_slot_id           = '{default: '0};
        rt_use_long_o        = '0;
        mispred_any          = 1'b0;

        for (integer p = 0; p < PORT_WIDTH; p++) begin
            // 函数或组合块中的局部表索引；短路径为PC折叠结果，长路径为mode表索引，具体位宽见声明。
            reg [MODE_IDX_BITS-1:0] idx;
            // 局部完整PC标签，通常是PC[PC_WIDTH-1:2]，用于mode/slot归属比较。
            reg [MODE_TAG_W-1:0]    tag;
            // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
            reg [SLOT_IDX_W-1:0]    slot;

            idx  = pc_mode_idx(rt_pc[p]);
            tag  = pc_mode_tag(rt_pc[p]);
            slot = mode_long_slot_id[idx];

            rt_is_dir[p]            = rt_grant[p] && (rt_brtype[p] == CBR_DIRECT);
            // 此实现从真实next PC与PC+4的比较推导方向；目标恰好等于PC+4时按不跳处理。
            rt_taken[p]             = (rt_brdest[p] != (rt_pc[p] + PC_WIDTH'(32'd4)));
            rt_misp[p]              = (rt_exception[p] == EXCPT_BRWRONG);
            rt_mode_idx[p]          = idx;
            rt_mode_tag[p]          = tag;
            rt_mode_hit[p]          = mode_valid[idx] && (mode_tag[idx] == tag);
            // 无效或未升级mode可替换；已升级mode被保护，PC索引冲突不能直接覆盖它。
            rt_mode_replace_ok[p]   = !mode_valid[idx] || !mode_upgraded[idx];
            rt_mode_upgraded_hit[p] = rt_mode_hit[p] && mode_upgraded[idx] &&
                                      long_slot_valid[slot] &&
                                      (long_slot_tag[slot] == tag);
            rt_slot_id[p]           = slot;
            // 这是反馈时当前表状态的归属判断，不是取指时实际选用long的历史记录。
            rt_use_long_o[p]        = rt_is_dir[p] && rt_mode_upgraded_hit[p];

            mispred_any = mispred_any | (rt_is_dir[p] && rt_misp[p]);
        end
    end

    always @(*) begin
        // 任一有效条件分支反馈出错，本拍代际只加一次；旧标签历史随后回退到commit基准。
        epoch_next = active_epoch + 8'(mispred_any ? 1'b1 : 1'b0);
    end

    generate
        // 为每个long slot生成独立PHT：2^BHR_BITS个两位计数器；A读预测，B读写训练。
        for (genvar si = 0; si < LONG_SLOTS; si++) begin : gen_long_pht_bram
            sync_dp_bram_exc #(
                .ADDR_W(BHR_BITS),
                .DATA_W(2),
                .INIT_VALUE(PHT_INIT_STATE)
            ) u_long_pht (
                .clka (clk),
                .wea  (1'b0),
                .addra(pht_addra_slot[si]),
                .dina ('0),
                .douta(pht_douta_slot[si]),
                .clkb (clk),
                .web  (pht_web_slot[si]),
                .addrb(pht_addrb_slot[si]),
                .dinb (pht_dinb_slot[si]),
                .doutb(pht_doutb_slot[si])
            );
        end
    endgenerate

    always @(*) begin
        // B口组合控制：IDLE给队首地址；seed直接写，普通请求只读；WRITE写pending新值。
        pht_web_slot   = '0;
        pht_addrb_slot = '{default: '0};
        pht_dinb_slot  = '{default: '0};

        for (integer si = 0; si < LONG_SLOTS; si++) begin
            // 每slot独立训练状态机；普通请求IDLE读、WAIT算新值、WRITE写回，seed请求在IDLE直写。
            unique case (upd_state[si])
                UPD_IDLE: begin
                    if (upd_fifo_count[si] != 0) begin
                        pht_addrb_slot[si] = upd_fifo_addr[si][upd_fifo_tail[si]];
                        // seed请求已有待写计数器：组合B口直写，当前边沿消费并同步记入bypass，无需读改写。
                        if (upd_fifo_seed[si][upd_fifo_tail[si]]) begin
                            pht_web_slot[si]  = 1'b1;
                            pht_dinb_slot[si] = upd_fifo_seed_ctr[si][upd_fifo_tail[si]];
                        end
                    end
                end
                UPD_WRITE: begin
                    pht_web_slot[si]   = 1'b1;
                    pht_addrb_slot[si] = pend_addr[si];
                    pht_dinb_slot[si]  = pend_new_ctr[si];
                end
                default: begin
                    pht_addrb_slot[si] = '0;
                end
            endcase
        end
    end

    
    
    
    
    
    always @(posedge clk) begin
        if (rst) begin
            have_q              <= 1'b0;
            lane_use_long_q     <= '0;
            lane_lookup_valid_q <= '0;
            lane_slot_q         <= '{default: '0};
            lane_base_hist_q    <= '{default: '0};
            // 把本次真正发出的历史地址寄存，与RAM读结果/bypass比较对齐；目前和base历史相同。
            lane_lookup_hist_q  <= '{default: '0};
            active_epoch        <= '0;

            for (integer mi = 0; mi < MODE_ENTRIES; mi++) begin
                mode_valid[mi]          <= 1'b0;
                mode_upgraded[mi]       <= 1'b0;
                mode_tag[mi]            <= '0;
                mode_sample_ctr[mi]     <= '0;
                mode_miss_ctr[mi]       <= '0;
                mode_candidate_hist[mi] <= '0;
                mode_long_slot_id[mi]   <= '0;
            end

            for (integer si = 0; si < LONG_SLOTS; si++) begin
                long_slot_valid[si] <= 1'b0;
                long_slot_tag[si]   <= '0;
                active_bhr[si]      <= '0;
                commit_bhr[si]      <= '0;
                shadow_bhr[si]      <= '0;
                epoch_tag[si]       <= '0;

                upd_fifo_head[si]   <= '0;
                upd_fifo_tail[si]   <= '0;
                upd_fifo_count[si]  <= '0;
                upd_state[si]       <= UPD_IDLE;
                pend_addr[si]       <= '0;
                pend_taken[si]      <= 1'b0;
                pend_new_ctr[si]    <= PHT_INIT_STATE;
                bypass_ptr[si]      <= '0;

                for (integer qi = 0; qi < UPD_FIFO_DEPTH; qi++) begin
                    upd_fifo_addr[si][qi]     <= '0;
                    upd_fifo_taken[si][qi]    <= 1'b0;
                    upd_fifo_seed[si][qi]     <= 1'b0;
                    upd_fifo_seed_ctr[si][qi] <= PHT_INIT_STATE;
                end

                for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                    bypass_valid[si][bi] <= 1'b0;
                    bypass_addr[si][bi]  <= '0;
                    bypass_ctr[si][bi]   <= PHT_INIT_STATE;
                end
            end
        end else begin
            // 本时钟事件内合并修复/投机更新后的long active历史临时副本。
            reg [BHR_BITS-1:0] active_bhr_tmp [LONG_SLOTS-1:0];
            // 本时钟事件内按反馈端口顺序更新的long基准历史临时副本。
            reg [BHR_BITS-1:0] commit_bhr_tmp [LONG_SLOTS-1:0];
            // 本拍历史修复/投机更新后的代际标签临时副本，最终保存回epoch_tag。
            reg [7:0] epoch_tag_tmp [LONG_SLOTS-1:0];
            // 本拍选定的新当前代际；无错保持active_epoch，有错使用epoch_next。
            reg [7:0]                          active_epoch_tmp;
            // 本拍long slot占用临时图；分配后立即置1，防止后续反馈端口再分配同一个slot。
            reg [LONG_SLOTS-1:0]               slot_busy_tmp;
            // 每slot本拍是否产生待入队长训练事件；每slot只有一个事件槽，同slot多次赋值时后者覆盖前者。
            reg [LONG_SLOTS-1:0]               evt_valid;
            // 每slot待入队事件的长PHT历史地址。
            reg [BHR_BITS-1:0] evt_addr [LONG_SLOTS-1:0];
            // 每slot待入队事件的真实方向。
            reg [LONG_SLOTS-1:0]               evt_taken;
            // 每slot待入队事件是否为升级种子初始化。
            reg [LONG_SLOTS-1:0]               evt_seed;
            // 每slot种子事件预先计算的两位计数器，sat2_update(PHT_INIT_STATE,真实方向)。
            reg [1:0] evt_seed_ctr [LONG_SLOTS-1:0];

            active_epoch_tmp = mispred_any ? epoch_next : active_epoch;
            // 本拍分配立即修改占用临时图，防止两个反馈端口同时选中同一个空闲slot。
            slot_busy_tmp    = long_slot_valid;
            // 每slot只保留一个本拍训练事件；若本拍多个反馈写同一slot事件字段，后面的阻塞赋值覆盖前面的。
            evt_valid        = '0;
            evt_addr         = '{default: '0};
            evt_taken        = '0;
            evt_seed         = '0;
            evt_seed_ctr     = '{default: '0};

            for (integer si = 0; si < LONG_SLOTS; si++) begin
                active_bhr_tmp[si] = active_bhr[si];
                commit_bhr_tmp[si] = commit_bhr[si];
                epoch_tag_tmp[si]  = epoch_tag[si];
            end

            have_q              <= have_inst_i;
            lane_use_long_q     <= lane_use_long_now;
            lane_lookup_valid_q <= lane_lookup_valid_now;
            lane_slot_q         <= lane_slot_now;
            lane_base_hist_q    <= lane_base_hist_now;
            // 把本次真正发出的历史地址寄存，与RAM读结果/bypass比较对齐；目前和base历史相同。
            lane_lookup_hist_q  <= lane_base_hist_now;
            active_epoch        <= active_epoch_tmp;


            for (integer p = 0; p < PORT_WIDTH; p++) begin
                if (rt_is_dir[p]) begin
                    // 函数或组合块中的局部表索引；短路径为PC折叠结果，长路径为mode表索引，具体位宽见声明。
                    reg [MODE_IDX_BITS-1:0] idx;
                    // 局部完整PC标签，通常是PC[PC_WIDTH-1:2]，用于mode/slot归属比较。
                    reg [MODE_TAG_W-1:0]    tag;

                    idx = rt_mode_idx[p];
                    tag = rt_mode_tag[p];

                    // 已升级分支：用更新前commit历史生成PHT训练事件，再将真实方向移入基准历史。
                    if (rt_mode_upgraded_hit[p]) begin
                        // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
                        reg [SLOT_IDX_W-1:0] slot;
                        // 顺序处理当前反馈之前的commit历史临时值；用来生成新历史/长PHT训练地址。
                        reg [BHR_BITS-1:0]   old_bhr_c;
                        // 把当前真实rt_taken移入old_bhr_c后得到的新基准历史。
                        reg [BHR_BITS-1:0]   new_bhr_c;

                        slot      = rt_slot_id[p];
                        old_bhr_c = commit_bhr_tmp[slot];
                        new_bhr_c = bhr_shift_in(old_bhr_c, rt_taken[p]);

                        commit_bhr_tmp[slot] = new_bhr_c;
                        evt_valid[slot]      = 1'b1;
                        // 训练地址必须是移入本次真实结果之前的历史，这样才在学习“该历史之后发生了什么”。
                        evt_addr[slot]       = old_bhr_c;
                        evt_taken[slot]      = rt_taken[p];
                        evt_seed[slot]       = 1'b0;

                        if (rt_misp[p]) begin
                            active_bhr_tmp[slot] = new_bhr_c;
                            epoch_tag_tmp[slot]  = epoch_next;
                        end
                    // 命中尚未升级的统计记录：累积样本数、错误数以及候选真实历史。
                    end else if (rt_mode_hit[p]) begin
                        // 当前被统计mode项的原样本计数，读取寄存值，供判断是否首次达到窗口上限。
                        reg [SAMPLE_W-1:0] sample_cur;
                        // 将本次反馈计入后，准备写回mode项的样本计数。
                        reg [SAMPLE_W-1:0] sample_n;
                        // 当前被统计mode项在采样窗口内的原错误计数。
                        reg [MISS_W-1:0]   miss_cur;
                        // 计入本次预测错误后，准备写回mode项的错误计数。
                        reg [MISS_W-1:0]   miss_n;
                        // 待升级mode项原候选真实历史；用作升级种子训练事件的PHT地址。
                        reg [BHR_BITS-1:0] hist_cur;
                        // 移入本次真实方向后的候选历史；写回mode项，并在升级时初始化slot的active/commit历史。
                        reg [BHR_BITS-1:0] hist_n;

                        // 这些统计临时量读取的是寄存mode表；与下面使用tmp累积多路历史的实现方式不同。
                        sample_cur = mode_sample_ctr[idx];
                        miss_cur   = mode_miss_ctr[idx];
                        hist_cur   = mode_candidate_hist[idx];
                        hist_n     = bhr_shift_in(hist_cur, rt_taken[p]);
                        sample_n   = sample_cur;
                        miss_n     = miss_cur;

                        if (sample_cur < SAMPLE_THRESHOLD) begin
                            sample_n = sample_cur + SAMPLE_W'(1);
                            if (rt_misp[p] && (miss_cur < SAMPLE_THRESHOLD)) begin
                                miss_n = miss_cur + MISS_W'(1);
                            end
                        end

                        mode_sample_ctr[idx]     <= sample_n;
                        mode_miss_ctr[idx]       <= miss_n;
                        mode_candidate_hist[idx] <= hist_n;

                        // 只有样本首次达到窗口上限才检查升级；不是滑动窗口，也不是到阈值后每拍重试分配。
                        if ((sample_cur < SAMPLE_THRESHOLD) &&
                            (sample_n == SAMPLE_THRESHOLD) &&
                            (miss_n >= MISS_THRESHOLD) &&
                            !mode_upgraded[idx]) begin
                            // 本拍分配搜索是否已找到首个空闲long slot；置1后停止选择其他槽。
                            reg found_free_slot;
                            // 本次新分配的long slot编号，只有found_free_slot为1时有效。
                            reg [SLOT_IDX_W-1:0] alloc_slot;

                            found_free_slot = 1'b0;
                            alloc_slot      = '0;
                            // 从低编号起搜索首个空闲slot；本实现没有运行时淘汰已分配slot的逻辑。
                            for (integer s = 0; s < LONG_SLOTS; s++) begin
                                if (!found_free_slot && !slot_busy_tmp[s]) begin
                                    found_free_slot = 1'b1;
                                    alloc_slot      = SLOT_IDX_W'(s);
                                end
                            end

                            // 分配成功：绑定PC标签、设置升级标志、初始化slot历史，并生成seed计数器写入事件。
                            if (found_free_slot) begin
                                slot_busy_tmp[alloc_slot]      = 1'b1;
                                mode_upgraded[idx]             <= 1'b1;
                                mode_long_slot_id[idx]         <= alloc_slot;
                                long_slot_valid[alloc_slot]    <= 1'b1;
                                long_slot_tag[alloc_slot]      <= tag;
                                active_bhr_tmp[alloc_slot]     = hist_n;
                                commit_bhr_tmp[alloc_slot]     = hist_n;
                                epoch_tag_tmp[alloc_slot]      = active_epoch_tmp;

                                evt_valid[alloc_slot]          = 1'b1;
                                evt_addr[alloc_slot]           = hist_cur;
                                evt_taken[alloc_slot]          = rt_taken[p];
                                evt_seed[alloc_slot]           = 1'b1;
                                // 只为本次历史地址播种一个计数器，不是在升级时清空整张long PHT。
                                evt_seed_ctr[alloc_slot]       = sat2_update(PHT_INIT_STATE, rt_taken[p]);
                            end
                        end
                    // 新PC占用无效/未升级mode项，从本次反馈开始统计；已升级碰撞项不会进入此分支。
                    end else if (rt_mode_replace_ok[p]) begin
                        mode_valid[idx]          <= 1'b1;
                        mode_upgraded[idx]       <= 1'b0;
                        mode_tag[idx]            <= tag;
                        mode_sample_ctr[idx]     <= SAMPLE_W'(1);
                        mode_miss_ctr[idx]       <= MISS_W'(rt_misp[p] ? 1'b1 : 1'b0);
                        mode_candidate_hist[idx] <= bhr_shift_in('0, rt_taken[p]);
                        mode_long_slot_id[idx]   <= '0;
                    end
                end
            end

            // 发生错误时抑制本拍前端新投机历史移入，优先保留后端真实结果和修复。
            if (!mispred_any) begin
                for (integer i = 0; i < IN_WIDTH; i++) begin
                    // 只有前端接受、条件分支且当次确实获long查询的lane，才投机更新对应slot历史。
                    if (br_grant[i] &&
                        lane_use_long_q[i] &&
                        lane_lookup_valid_q[i] &&
                        (br_brtype[i] == CBR_DIRECT)) begin
                        // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
                        reg [SLOT_IDX_W-1:0] slot;
                        // 投机更新的历史来源：epoch匹配取active，否则取commit，避免继续使用错误路径历史。
                        reg [BHR_BITS-1:0]   bhr_src;
                        // 移入一个结果后的历史，丢弃最高旧位、低位追加taken；也用于投机历史更新临时值。
                        reg [BHR_BITS-1:0]   bhr_new;

                        slot = lane_slot_q[i];
                        if (epoch_tag_tmp[slot] == active_epoch_tmp) begin
                            bhr_src = active_bhr_tmp[slot];
                        end else begin
                            // 该项active不属于当前epoch，不能继承错误路径历史，从后端基准历史重新开始。
                            bhr_src = commit_bhr_tmp[slot];
                        end

                        bhr_new = bhr_shift_in(bhr_src, br_taken[i]);
                        active_bhr_tmp[slot] = bhr_new;
                        epoch_tag_tmp[slot]  = active_epoch_tmp;
                    end
                end
            end

            for (integer si = 0; si < LONG_SLOTS; si++) begin
                // 本时钟事件内的FIFO入队指针临时值，用来顺序合并本拍操作，最后写回head。
                reg [UPD_FIFO_BITS-1:0] head_tmp;
                // 本时钟事件内的FIFO出队指针临时值，消费请求后前移。
                reg [UPD_FIFO_BITS-1:0] tail_tmp;
                // 先处理出队、再检查入队后得到的占用数临时值，使同拍释放空间可用于新请求。
                reg [UPD_FIFO_BITS:0]   count_tmp;

                head_tmp  = upd_fifo_head[si];
                tail_tmp  = upd_fifo_tail[si];
                count_tmp = upd_fifo_count[si];

                // 每slot独立训练状态机；普通请求IDLE读、WAIT算新值、WRITE写回，seed请求在IDLE直写。
                unique case (upd_state[si])
                    UPD_IDLE: begin
                        if (upd_fifo_count[si] != 0) begin
                            // seed请求已有待写计数器：组合B口直写，当前边沿消费并同步记入bypass，无需读改写。
                            if (upd_fifo_seed[si][upd_fifo_tail[si]]) begin
                                // 局部标志：本次地址是否已在bypass中；命中原位改ctr，否则用bypass_ptr插入。
                                reg found_bypass;

                                found_bypass = 1'b0;
                                for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                                    if (bypass_valid[si][bi] &&
                                        (bypass_addr[si][bi] == upd_fifo_addr[si][upd_fifo_tail[si]])) begin
                                        bypass_ctr[si][bi] <= upd_fifo_seed_ctr[si][upd_fifo_tail[si]];
                                        found_bypass       = 1'b1;
                                    end
                                end
                                // 没有同地址旁路项才插入循环替换位置；指针按声明位宽自动回绕。
                                if (!found_bypass) begin
                                    bypass_valid[si][bypass_ptr[si]] <= 1'b1;
                                    bypass_addr[si][bypass_ptr[si]]  <= upd_fifo_addr[si][upd_fifo_tail[si]];
                                    bypass_ctr[si][bypass_ptr[si]]   <= upd_fifo_seed_ctr[si][upd_fifo_tail[si]];
                                    bypass_ptr[si]                   <= bypass_ptr[si] + BYPASS_BITS'(1);
                                end

                                tail_tmp  = upd_fifo_tail[si] + UPD_FIFO_BITS'(1);
                                count_tmp = upd_fifo_count[si] - 1'b1;
                            end else begin
                                pend_addr[si]  <= upd_fifo_addr[si][upd_fifo_tail[si]];
                                pend_taken[si] <= upd_fifo_taken[si][upd_fifo_tail[si]];
                            end
                        end
                    end

                    UPD_WAIT: begin
                        // 本次训练使用的更新前两位计数器，RAM初值可由同地址bypass覆盖。
                        reg [1:0] old_ctr;
                        // sat2_update算出的新两位计数器，既写RAM也记入recent bypass。
                        reg [1:0] new_ctr;
                        // 局部标志：本次地址是否已在bypass中；命中原位改ctr，否则用bypass_ptr插入。
                        reg found_bypass;

                        // WAIT阶段使用上一阶段同步读出的计数器；同地址recent命中时优先用旁路值。
                        old_ctr      = pht_doutb_slot[si];
                        found_bypass = 1'b0;

                        for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                            if (bypass_valid[si][bi] &&
                                (bypass_addr[si][bi] == pend_addr[si])) begin
                                old_ctr      = bypass_ctr[si][bi];
                                found_bypass = 1'b1;
                            end
                        end

                        new_ctr          = sat2_update(old_ctr, pend_taken[si]);
                        // 保存新计数器供WRITE阶段写RAM；本WAIT边沿同时把它放入bypass，因此旁路可早于RAM写回可见。
                        pend_new_ctr[si] <= new_ctr;
                        found_bypass     = 1'b0;

                        for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                            if (bypass_valid[si][bi] &&
                                (bypass_addr[si][bi] == pend_addr[si])) begin
                                bypass_ctr[si][bi] <= new_ctr;
                                found_bypass       = 1'b1;
                            end
                        end
                        // 没有同地址旁路项才插入循环替换位置；指针按声明位宽自动回绕。
                        if (!found_bypass) begin
                            bypass_valid[si][bypass_ptr[si]] <= 1'b1;
                            bypass_addr[si][bypass_ptr[si]]  <= pend_addr[si];
                            bypass_ctr[si][bypass_ptr[si]]   <= new_ctr;
                            bypass_ptr[si]                   <= bypass_ptr[si] + BYPASS_BITS'(1);
                        end
                    end

                    UPD_WRITE: begin
                        tail_tmp  = upd_fifo_tail[si] + UPD_FIFO_BITS'(1);
                        count_tmp = upd_fifo_count[si] - 1'b1;
                    end

                    default: begin
                    end
                endcase

                // 先处理队首消费释放空间，再把本拍事件入队；队列满则跳过该训练，无外部反压端口。
                if (evt_valid[si]) begin
                    if (count_tmp < UPD_FIFO_DEPTH) begin
                        upd_fifo_addr[si][head_tmp]     <= evt_addr[si];
                        upd_fifo_taken[si][head_tmp]    <= evt_taken[si];
                        upd_fifo_seed[si][head_tmp]     <= evt_seed[si];
                        upd_fifo_seed_ctr[si][head_tmp] <= evt_seed_ctr[si];

                        head_tmp  = head_tmp + UPD_FIFO_BITS'(1);
                        count_tmp = count_tmp + 1'b1;
                    end
                end

                upd_fifo_head[si]  <= head_tmp;
                upd_fifo_tail[si]  <= tail_tmp;
                upd_fifo_count[si] <= count_tmp;

                // 每slot独立训练状态机；普通请求IDLE读、WAIT算新值、WRITE写回，seed请求在IDLE直写。
                unique case (upd_state[si])
                    UPD_IDLE: begin
                        if (upd_fifo_count[si] != 0) begin
                            // seed请求已有待写计数器：组合B口直写，当前边沿消费并同步记入bypass，无需读改写。
                            if (upd_fifo_seed[si][upd_fifo_tail[si]]) begin
                                upd_state[si] <= UPD_IDLE;
                            end else begin
                                upd_state[si] <= UPD_WAIT;
                            end
                        end else begin
                            upd_state[si] <= UPD_IDLE;
                        end
                    end
                    UPD_WAIT: begin
                        upd_state[si] <= UPD_WRITE;
                    end
                    UPD_WRITE: begin
                        upd_state[si] <= UPD_IDLE;
                    end
                    default: begin
                        upd_state[si] <= UPD_IDLE;
                    end
                endcase
            end

            for (integer si = 0; si < LONG_SLOTS; si++) begin
                active_bhr[si] <= active_bhr_tmp[si];
                commit_bhr[si] <= commit_bhr_tmp[si];
                epoch_tag[si]  <= epoch_tag_tmp[si];
                // 生成slot的下一拍shadow历史：新代际有效active优先，旧代际投机历史回退commit。
                if (epoch_tag_tmp[si] == active_epoch_tmp) begin
                    shadow_bhr[si] <= active_bhr_tmp[si];
                end else begin
                    shadow_bhr[si] <= commit_bhr_tmp[si];
                end
            end
        end
    end


endmodule








// ============================================================================
// 长PHT使用的同步双端口RAM封装：每行DATA_W位，长预测器实例设为2位计数器。
// 实际两口都由clka驱动；clkb保留未使用；同步读取，边沿后输出旧存储值(read-first)，无rst端口。
// 初始化通过initial，错误修复不会整表清零；旁路及更新排队由外层预测器负责。
// ============================================================================
module sync_dp_bram_exc #(
    // 通用同步双端口RAM行地址位宽；逻辑行数为2^ADDR_W，不是字节地址宽度。
    parameter integer ADDR_W = 6,
    // 通用RAM每行数据位数；短PHT为一行多个计数器，长PHT每行一个两位计数器。
    parameter integer DATA_W = 8,
    // RAM各行及输出寄存器的初始值，由initial赋值，不是由rst每次清表。
    parameter [DATA_W-1:0] INIT_VALUE = '0
) (
    // RAM实际工作时钟；本实现A口与B口都由posedge clka驱动。
    input wire                    clka,
    // A口写使能，1时在clka上升沿写mem[addra]；预测器查询实例中通常固定接0。
    input wire                    wea,
    // A口行地址；短PHT为PC折叠行号，长PHT为历史，具体容量由实例参数决定。
    input wire [ADDR_W-1:0]       addra,
    // A口待写数据，位宽DATA_W；查询口不写时接0。
    input wire [DATA_W-1:0]       dina,
    // A口寄存后的读出数据，地址在时钟边沿采样，不能当作异步组合查表结果。
    output wire [DATA_W-1:0]       douta,

    // 保留的B口时钟接口；本文件内部不使用它，A/B实际共用clka，不能据端口名当作异步双时钟RAM。
    input wire                    clkb,
    // B口写使能，1时在clka上升沿写mem[addrb]；更新状态机驱动。
    input wire                    web,
    // B口行地址，用于先读取训练旧值、再写入更新后的数据。
    input wire [ADDR_W-1:0]       addrb,
    // B口待写数据，短PHT为修改后的整行，长PHT为两位新计数器。
    input wire [DATA_W-1:0]       dinb,
    // B口寄存后的读出数据，供训练状态机使用。
    output wire [DATA_W-1:0]       doutb
);
    // RAM逻辑行数；通用RAM为2^ADDR_W，ip_predict_mem中的旧BHT/BTB固定64行。
    localparam integer DEPTH    = (1 << ADDR_W);
    // 逻辑总位数DEPTH*DATA_W，保留的容量常量，不代表综合后的物理BRAM块数。
    localparam integer MEM_BITS = DEPTH * DATA_W;

    // 本模块实例独立的RAM数组；多实例不是共享同一份数据，实际映射由综合工具决定。
    // 这是RAM推断提示而非保证；每个module实例的mem独立，不能据reg关键字认定一定由触发器实现。
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];
    // A口读数据寄存器；对外douta由连续赋值连接它。
    reg [DATA_W-1:0] douta_r;
    // B口读数据寄存器；对外doutb由连续赋值连接它。
    reg [DATA_W-1:0] doutb_r;

    // 仿真/支持初始化的FPGA综合在启动时设置存储初值；不是运行中每次rst都会执行。
    initial begin
        for (integer i = 0; i < DEPTH; i++) begin
            mem[i] = INIT_VALUE;
        end
        douta_r = INIT_VALUE;
        doutb_r = INIT_VALUE;
    end

    always @(posedge clka) begin
        // A口写使能有效时更新当前行；同口读输出仍由下面的旧mem值计算（非阻塞赋值）。
        if (wea) begin
            mem[addra] <= dina;
        end
        // 同步读旧值：在边沿采样地址，边沿后更新输出；同口写同址本模型返回写前值。
        douta_r <= mem[addra];
    end

    always @(posedge clka) begin
        // B口训练写入；A/B实际共用clka，本封装不做跨口冲突仲裁。
        if (web) begin
            mem[addrb] <= dinb;
        end
        // B口旧值在边沿后可见，外层需等待再计算新计数器；不能将其当作零延迟组合读。
        doutb_r <= mem[addrb];
    end

    // 输出连线，不再增加流水拍；延迟来自前面的douta_r寄存器。
    assign douta = douta_r;
    // 把B口输出寄存器连接到模块端口，不增加额外一拍。
    assign doutb = doutb_r;

endmodule
