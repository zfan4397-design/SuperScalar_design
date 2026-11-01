// 术语：lane=本组第几路指令；bank=独立存储分块；slot=长预测资源槽。
// 命名：_now=当前组合查询；_q=寄存查询上下文；_tmp=本拍合并更新临时量；dbg=观察信号。
// Requires SystemVerilog: wire/reg style with unpacked array ports and state.

// ============================================================================
// 短历史条件分支方向预测器（数组端口版本）。
// 数据流：pc_i -> lane地址/PC折叠 -> 并行读PHT宽行 -> shadow历史选子bank/计数器 -> bypass覆盖 -> lp。
// 历史流：br_*预测结果更新active；rt_*真实结果更新commit，并排队训练PHT；错误时切epoch恢复历史视图。
// 重要：本文件没有ctrl_clear/ctrl_restore_pulse输入，修复由有效CBR反馈的rt_exception驱动。
// 当前查询每lane独立使用base历史，没有组内prefix组合链；名字prefix保留用于观察。
// 参数声明是默认值，上层可以覆盖，不应把默认IN_WIDTH=4、BHR_BITS=9当作整核实际配置。
// 容量公式：BHT每套2^BHT_IDX_BITS项×BHR_BITS；PHT共IN_WIDTH×2^PHT_BANK_BITS块，每块2^PHT_PC_ADDR_W行×PHT_SUBLINE_W位。
// ============================================================================
module direction_predict_v4 #(
    // 接口位宽：PC_WIDTH为PC/下一PC位数；DATA_WIDTH为保留的数据位宽参数（本文件逻辑未直接使用）；BRTYPE_WIDTH为类型位数；EXCPT_WIDTH为异常编码位数。
    parameter PC_WIDTH=32, DATA_WIDTH=32, BRTYPE_WIDTH=2, EXCPT_WIDTH=4,
    // 前端并行查询的指令槽位数，也决定短预测器外层fetch bank数量；是参数默认值，实际值由实例化覆盖。
    parameter integer IN_WIDTH        = 4,
    // 后端反馈端口数；本拍最多检查PORT_WIDTH条真实分支结果，不能据名字认定为架构退休宽度。
    parameter integer PORT_WIDTH      = 2,
    // 短BHT总索引位数；总项数2^BHT_IDX_BITS，索引由fetch bank编号和折叠PC局部索引拼接。
    parameter integer BHT_IDX_BITS    = 4,
    // 每项分支历史的位数；短路径拆成子bank选择及行内计数器编号，长路径直接作为PHT地址。
    parameter integer BHR_BITS        = 9,
    // 短PHT的PC索引总预算；减去fetch bank位数后得到实际RAM行地址宽度，并非直接截取这么多PC位。
    parameter integer PC_SPLICE_BITS  = 5,
    // 历史低位用于选择PHT子bank的位数；每个fetch bank含2^PHT_BANK_BITS个独立子bank。
    parameter integer PHT_BANK_BITS   = 3,
    // 短PHT更新FIFO指针位数；每个fetch bank/子bank各有2^BUF_BITS项队列。
    parameter integer BUF_BITS        = 2,
    // PHT两位计数器初值：00强不跳、01弱不跳、10弱跳、11强跳；预测方向取最高位。
    parameter [1:0]  PHT_INIT_STATE  = 2'b11
) (
    // 模块时钟；本文件历史、上下文、FIFO等寄存状态在上升沿更新。
    input wire                                                 clk,
    // 高有效同步复位，只在posedge clk检查；重置历史/标签/队列/上下文，PHT RAM本身没有rst口，初值由initial设置。
    input wire                                                 rst,

    // 当前前端查询请求是否有效；寄存到have_q以对齐同步RAM结果，不等于后续组内截断后的逐lane有效位。
    input wire                                                 have_inst_i,
    // 本次取指组起始PC；第i路指令地址按pc_i+4*i生成，假设每条指令占4字节。
    input wire [PC_WIDTH-1:0]                                  pc_i,
    // 每个前端lane输出一个2位最终计数器；有效时最高位给出预测方向，无效查询输出00。
    output reg [1:0] lp [IN_WIDTH-1:0],
    // 调试输出：每lane基础历史；短路径来自当前shadow_bht，长路径为查询时寄存的基础历史。
    output reg [BHR_BITS-1:0] dbg_base_hist_o [IN_WIDTH-1:0],
    // 调试输出：短路径保留的prefix历史观测口；当前没有older到younger的组合前递，值等于基础历史。
    output reg [BHR_BITS-1:0] dbg_prefix_hist_o [IN_WIDTH-1:0],
    // 调试输出：短路径实际选计数器的历史；当前与base/prefix相同，不代表额外维护一张历史表。
    output reg [BHR_BITS-1:0] dbg_effective_hist_o [IN_WIDTH-1:0],
    // 调试输出：每lane查询短PHT的RAM行号，宽度PC_SPLICE_BITS-$clog2(IN_WIDTH)。
    output reg [(PC_SPLICE_BITS-$clog2(IN_WIDTH))-1:0] dbg_pht_row_o [IN_WIDTH-1:0],
    // 调试输出：两位计数器在宽数据行中的起始位偏移，不是计数器编号；由历史高位后补0得到，只取偶数值。
    output reg [(BHR_BITS-PHT_BANK_BITS):0] dbg_ctr_idx_o [IN_WIDTH-1:0],
    // 调试输出：逐lane查询是否命中最近更新旁路；需要同时满足本模块的查询有效条件。
    output reg [IN_WIDTH-1:0]                                  dbg_bypass_hit_o,
    // 调试输出：最终采用的2位计数器，已包含RAM值/bypass覆盖和有效性选择。
    output reg [1:0] dbg_final_ctr_o [IN_WIDTH-1:0],
    // 调试输出：最终计数器来源编码，0=RAM、1=recent bypass；无效查询也置0，不能据此单独判断有效。
    output reg [1:0] dbg_ctr_src_o [IN_WIDTH-1:0],

    // 前端逐lane接受/有效标志，来自组内截断后的有效指令；内部还检查条件分支类型才更新投机历史。
    input wire [IN_WIDTH-1:0]                                  br_grant,
    // 前端已接受指令的PC数组；短路径用来定位投机BHT项，长路径接口保留此输入但实际用已寄存lane_slot_q定位。
    input wire [PC_WIDTH-1:0] br_pc [IN_WIDTH-1:0],
    // 前端每lane预解码得到的分支类型；这里只对CBR_DIRECT条件分支移入投机方向历史。
    input wire [BRTYPE_WIDTH-1:0] br_brtype [IN_WIDTH-1:0],
    // 前端每lane的预测方向，1跳/0不跳；用于投机历史，不能当成后端真实结果。
    input wire [IN_WIDTH-1:0]                                  br_taken,
    // 前端逐lane短历史更新许可；与br_grant和CBR_DIRECT共同决定是否移入预测结果。
    input wire [IN_WIDTH-1:0]                                  br_dir_enable_i,

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
    // 后端逐端口短路径训练许可；与有效条件分支共同形成rt_valid_dir，门控基准历史和PHT训练。
    input wire [PORT_WIDTH-1:0]                                rt_dir_enable_i
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


    // 历史代际编号宽度为8；递增会按该位宽回绕，用标签区分当前有效投机历史与旧路径历史。
    localparam integer EPOCH_BITS      = 8;
    // fetch bank编号位宽log2(IN_WIDTH)；从PC[2 +: FETCH_BANK_W]取值，不同于PHT历史子bank位数。
    localparam integer FETCH_BANK_W    = $clog2(IN_WIDTH);
    // 每个fetch bank内的BHT局部索引宽度=BHT_IDX_BITS-FETCH_BANK_W；由较高PC位异或折叠生成。
    localparam integer BHT_ADDR_W      = BHT_IDX_BITS   - FETCH_BANK_W;
    // 短BHT总项数2^BHT_IDX_BITS；active/commit/shadow各一套，epoch_tag也是每项一个。
    localparam integer BHT_ENTRIES     = (1 << BHT_IDX_BITS);
    // 每个短PHT RAM的行地址位数=PC_SPLICE_BITS-FETCH_BANK_W；行数2^该值。
    localparam integer PHT_PC_ADDR_W   = PC_SPLICE_BITS - FETCH_BANK_W;
    // 每个短PHT训练FIFO的项数2^BUF_BITS；队列满时本实现丢弃训练请求并计数。
    localparam integer BUF_DEPTH       = (1 << BUF_BITS);
    // 每个fetch bank内部的PHT子bank数2^PHT_BANK_BITS；历史低位选择子bank。
    localparam integer PHT_BANKS       = (1 << PHT_BANK_BITS);
    // 历史中除去子bank选择后剩余的高位数，决定一行里有多少个两位计数器。
    localparam integer PHT_SUBIDX_W    = BHR_BITS - PHT_BANK_BITS;
    // 每行位宽=2^PHT_SUBIDX_W*2；一行打包多个计数器，读改写只修改其中两位。
    localparam integer PHT_SUBLINE_W   = (1 << PHT_SUBIDX_W) * 2;
    // 最近更新旁路表的循环写入指针宽度，固定2位。
    localparam integer BYPASS_BITS     = 2;
    // 每组旁路表项数2^BYPASS_BITS=4；保存最近生成的计数器值，不是等待执行的训练队列。
    localparam integer BYPASS_DEPTH    = (1 << BYPASS_BITS);

    // 把PHT_INIT_STATE重复2^PHT_SUBIDX_W次，得到整条PHT数据行的初始值。
    localparam [PHT_SUBLINE_W-1:0] PHT_INIT_SUBLINE =
        {(1 << PHT_SUBIDX_W){PHT_INIT_STATE}};

    // 短PHT训练状态0：等待队首或提供队首行地址，读取旧数据行。
    localparam STATE_RD_OLD = 1'b0;
    // 短PHT训练状态1：提供修改后的整行写数据，并消费队首请求。
    localparam STATE_WR_NEW = 1'b1;

    // 前端投机历史表：每项BHR_BITS位；沿有效预测路径移入br_taken。
    reg [BHR_BITS-1:0]                     active_bht [0:BHT_ENTRIES-1];
    // 后端真实反馈维护的基准历史表；用于训练地址重建及错误恢复，并不自行保证架构退休语义。
    reg [BHR_BITS-1:0]                     commit_bht [0:BHT_ENTRIES-1];
    // 每个历史项/long slot对应的投机代际标签；等于active_epoch时才把active历史视为当前路径。
    reg [EPOCH_BITS-1:0]                   epoch_tag  [0:BHT_ENTRIES-1];
    // 寄存后的前端可见短历史；每拍根据epoch选择active或commit，查询逻辑只消费该稳定视图。
    reg [BHR_BITS-1:0]                     shadow_bht [0:BHT_ENTRIES-1];

    // 寄存后的查询有效位，用于对齐同步PHT读数据和查询上下文；不直接代表后端反馈有效。
    reg                                    have_q;
    // 当前投机历史代际；条件分支反馈错误时加1，使旧代际active历史失效。
    reg [EPOCH_BITS-1:0]                   active_epoch;
    // 发生错误时应使用的下一代际编号；组合计算，无错误时保持当前代际。
    reg [EPOCH_BITS-1:0]                   epoch_next;

    // 当前查询的逐lane PC=pc_i+4*i，组合产生；lane只是指令槽位，不是bank编号。
    reg [PC_WIDTH-1:0] lane_pc_now [IN_WIDTH-1:0];
    // 当前逐lane查询所属的fetch bank编号，由各自PC低位提取。
    reg [FETCH_BANK_W-1:0] lane_fetch_bank_now [IN_WIDTH-1:0];
    // 当前逐lane的完整BHT索引={fetch bank,折叠PC局部索引}。
    reg [BHT_IDX_BITS-1:0] lane_bht_idx_now [IN_WIDTH-1:0];
    // 当前逐lane短PHT行号，由PC高位折叠生成，不含历史选择信息。
    reg [PHT_PC_ADDR_W-1:0] lane_pht_pc_addr_now [IN_WIDTH-1:0];

    // 寄存的查询fetch bank，和同步RAM读出行对齐，用来把bank结果选回对应lane。
    reg [FETCH_BANK_W-1:0] lane_fetch_bank_q [IN_WIDTH-1:0];
    // 寄存的BHT索引；输出阶段用它从shadow_bht取得历史。
    reg [BHT_IDX_BITS-1:0] lane_bht_idx_q [IN_WIDTH-1:0];
    // 寄存的PHT行地址，用于结果追踪、调试及旁路地址匹配。
    reg [PHT_PC_ADDR_W-1:0] lane_pht_pc_addr_q [IN_WIDTH-1:0];
    // 输出阶段按lane_bht_idx_q读取的shadow短历史；live表示组合可见值，不是后端反馈。
    reg [BHR_BITS-1:0] lane_base_hist_live [IN_WIDTH-1:0];

    // 短路径prefix历史观测中间量；当前直接等于base，没有组内串联预测依赖。
    reg [BHR_BITS-1:0] lane_prefix_hist_comb [IN_WIDTH-1:0];
    // 实际选择PHT子bank/计数器的历史中间量；当前直接等于base。
    reg [BHR_BITS-1:0] lane_hist_eff_comb [IN_WIDTH-1:0];
    // 每lane最终计数器的行内起始位偏移，历史高位左移1，不是RAM行号。
    reg [PHT_SUBIDX_W:0] lane_ctr_idx_comb [IN_WIDTH-1:0];
    // 每lane最终两位计数器，已应用bypass覆盖及have_q有效门控。
    reg [1:0] lane_ctr_final_comb [IN_WIDTH-1:0];
    // 每lane计数器来源编码，0=RAM，1=bypass；无效时也为0。
    reg [1:0] lane_ctr_src_comb [IN_WIDTH-1:0];
    // 每lane短查询旁路命中，使用have_q门控后供调试输出。
    reg [IN_WIDTH-1:0]                     lane_bypass_hit_comb;
    // 每lane短路径预测方向中间量，取最终计数器最高位；无效查询为0。
    reg [IN_WIDTH-1:0]                     lane_pred_taken_comb;


    // 前端接受反馈的指令所属fetch bank，用br_pc计算，用于定位投机历史。
    reg [FETCH_BANK_W-1:0] br_fetch_bank [IN_WIDTH-1:0];
    // 前端接受反馈的条件分支所映射的BHT项索引。
    reg [BHT_IDX_BITS-1:0] br_bht_idx [IN_WIDTH-1:0];

    // 每端口是否为有效条件分支反馈=rt_grant且类型为CBR_DIRECT。
    reg [PORT_WIDTH-1:0]                   rt_is_dir;
    // 短路径训练有效=rt_is_dir且rt_dir_enable_i；仅其有效时更新基准历史/入队训练。
    reg [PORT_WIDTH-1:0]                   rt_valid_dir;
    // 后端反馈指令所属fetch bank编号，决定训练请求送往哪组FIFO。
    reg [FETCH_BANK_W-1:0] rt_fetch_bank [PORT_WIDTH-1:0];
    // 后端反馈PC对应的短BHT索引，用来读取/更新commit历史。
    reg [BHT_IDX_BITS-1:0] rt_bht_idx [PORT_WIDTH-1:0];
    // 后端反馈PC对应的短PHT行号，写入训练FIFO。
    reg [PHT_PC_ADDR_W-1:0] rt_pht_pc_addr [PORT_WIDTH-1:0];
    // 按真实next PC是否不等于PC+4推导出的真实方向，供历史移位和计数器训练。
    reg [PORT_WIDTH-1:0]                   rt_taken;
    // 后端反馈是否标记EXCPT_BRWRONG；与有效条件分支相与后才触发全局epoch切换。
    reg [PORT_WIDTH-1:0]                   rt_misp;
    // 本拍组合读取的更新前commit历史，用于PHT训练地址；不是移入本次结果后的新历史。
    reg [BHR_BITS-1:0] rt_old_bhr [PORT_WIDTH-1:0];
    // 更新前commit历史的低PHT_BANK_BITS位，决定训练哪个历史子bank。
    reg [PHT_BANK_BITS-1:0] rt_pht_bank_sel [PORT_WIDTH-1:0];
    // 更新前commit历史高位后补0，给出训练计数器在宽行中的起始位偏移。
    reg [PHT_SUBIDX_W:0] rt_pht_ctr_idx [PORT_WIDTH-1:0];

    // 本拍任一有效条件分支反馈出错则为1；切换epoch并抑制本拍新的前端投机历史移入。
    reg                                    mispred_any;

    // 短PHT查询A口行地址数组，按[fetch bank][历史子bank]组织；同一fetch bank各子bank并行读同一PC行。
    reg [PHT_PC_ADDR_W-1:0] pht_addra_bank [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 短PHT A口同步读出的整条计数器数据行；输出阶段再按历史选子bank和其中两位。
    reg [PHT_SUBLINE_W-1:0] pht_douta_bank [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 短PHT B口写使能，每个fetch bank/子bank独立，训练写阶段置1。
    reg [PHT_BANKS-1:0] pht_web_bank [IN_WIDTH-1:0];
    // 短PHT B口训练行地址：读阶段来自FIFO队首，写阶段来自pending上下文。
    reg [PHT_PC_ADDR_W-1:0] pht_addrb_bank [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 短PHT B口写入的整条宽数据行；保留其他计数器，只改目标两位。
    reg [PHT_SUBLINE_W-1:0] pht_dinb_bank [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 短PHT B口读出的旧数据行，用于训练的读改写。
    reg [PHT_SUBLINE_W-1:0] pht_doutb_bank [IN_WIDTH-1:0][PHT_BANKS-1:0];

    // 每个fetch bank/子bank成功进入训练FIFO的累计请求数。
    reg [31:0] fifo_push_count_dbg [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 每个fetch bank/子bank因FIFO已满而未接收的训练请求累计数。
    reg [31:0] fifo_drop_count_dbg [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 每个训练FIFO历史最大占用项数，需要BUF_BITS+1位才能表示满深度。
    reg [BUF_BITS:0] fifo_peak_depth_dbg [IN_WIDTH-1:0][PHT_BANKS-1:0];

    // recent bypass各项有效位；短路径按fetch bank/subbank分组，长路径按long slot分组。
    reg [BYPASS_DEPTH-1:0] bypass_valid [IN_WIDTH-1:0][PHT_BANKS-1:0];
    // 短bypass条目的PHT行号，需与行内ctr_idx一起匹配才指向同一个计数器。
    reg [PHT_PC_ADDR_W-1:0] bypass_row [IN_WIDTH-1:0][PHT_BANKS-1:0][BYPASS_DEPTH-1:0];
    // 短bypass条目记录的行内两位计数器起始位偏移。
    reg [PHT_SUBIDX_W:0] bypass_ctr_idx [IN_WIDTH-1:0][PHT_BANKS-1:0][BYPASS_DEPTH-1:0];
    // recent bypass保存的最新两位计数器，可覆盖查询RAM值，也供后续训练读旧值时使用。
    reg [1:0] bypass_ctr [IN_WIDTH-1:0][PHT_BANKS-1:0][BYPASS_DEPTH-1:0];
    // 每组bypass下一个可替换位置；有同地址项时原位更新，否则在指针位置写入并循环前移。
    reg [BYPASS_BITS-1:0] bypass_ptr [IN_WIDTH-1:0][PHT_BANKS-1:0];

    // 把所有短训练FIFO的累计成功入队数求和形成的内部统计信号，不是独立对外端口。
    reg [31:0] dbg_bp_fifo_push_count ;
    // 把所有短训练FIFO的累计丢训练数求和，便于发现更新带宽不足。
    reg [31:0] dbg_bp_fifo_drop_count ;
    // 所有短训练FIFO历史峰值中的最大值，不是各FIFO峰值相加。
    reg [31:0] dbg_bp_fifo_peak_depth ;
    // 累计修复短历史的有效错误反馈数量；本拍多个修复通过repair_inc累加。
    reg [31:0] dbg_bp_repair_count    ;

    // generate展开编号：每个fetch bank生成一组RAM和训练FIFO，不是运行时循环计数寄存器。
    genvar g;

    initial begin
        // 参数检查只在仿真开始执行：要求非零2次幂fetch宽度，并保证索引各字段有合法位宽。
        if ((IN_WIDTH == 0) || ((IN_WIDTH & (IN_WIDTH - 1)) != 0)) begin
            begin $display("direction_predict_v4 requires IN_WIDTH to be a non-zero power of two"); $finish; end
        end
        if (BHT_IDX_BITS <= FETCH_BANK_W) begin
            begin $display("direction_predict_v4 requires BHT_IDX_BITS > $clog2(IN_WIDTH)"); $finish; end
        end
        if (PC_SPLICE_BITS <= FETCH_BANK_W) begin
            begin $display("direction_predict_v4 requires PC_SPLICE_BITS > $clog2(IN_WIDTH)"); $finish; end
        end
        if (BHR_BITS < PHT_BANK_BITS) begin
            begin $display("direction_predict_v4 requires BHR_BITS >= PHT_BANK_BITS"); $finish; end
        end
    end

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

    // 按目标索引位宽循环异或折叠较高PC位；结果与fetch bank拼接，形成短BHT索引。
    function automatic reg [BHT_ADDR_W-1:0] pc_fold_bht_local_idx(
        // PC折叠/取tag函数的输入地址，是指令自身地址。
        input reg [PC_WIDTH-1:0] pc
    );
        // 函数或组合块中的局部表索引；短路径为PC折叠结果，长路径为mode表索引，具体位宽见声明。
        reg [BHT_ADDR_W-1:0] idx;
        // PC异或折叠函数中被遍历的原PC位编号。
        integer bit_i;
        // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
        integer slot;
        begin
            idx = '0;
            for (bit_i = FETCH_BANK_W + 2; bit_i < PC_WIDTH; bit_i = bit_i + 1) begin
                slot = (bit_i - (FETCH_BANK_W + 2)) % BHT_ADDR_W;
                idx[slot] = idx[slot] ^ pc[bit_i];
            end
            return idx;
        end
    endfunction

    // 把较高PC位异或折叠成PHT_PC_ADDR_W位行号；多个PC可能别名，不是带tag的精确映射。
    function automatic reg [PHT_PC_ADDR_W-1:0] pc_fold_pht_row_idx(
        // PC折叠/取tag函数的输入地址，是指令自身地址。
        input reg [PC_WIDTH-1:0] pc
    );
        // 函数或组合块中的局部表索引；短路径为PC折叠结果，长路径为mode表索引，具体位宽见声明。
        reg [PHT_PC_ADDR_W-1:0] idx;
        // PC异或折叠函数中被遍历的原PC位编号。
        integer bit_i;
        // PC折叠函数中的目标位号（integer声明时），或长预测器选中的long slot编号（SLOT_IDX_W位声明时）。
        integer slot;
        begin
            idx = '0;
            for (bit_i = FETCH_BANK_W + 2; bit_i < PC_WIDTH; bit_i = bit_i + 1) begin
                slot = (bit_i - (FETCH_BANK_W + 2)) % PHT_PC_ADDR_W;
                idx[slot] = idx[slot] ^ pc[bit_i];
            end
            return idx;
        end
    endfunction

    always @(*) begin
        // 查询阶段：默认各lane为0，然后由当前pc_i生成bank、BHT索引、PHT行号。
        lane_pc_now          = '{default: '0};
        lane_fetch_bank_now  = '{default: '0};
        lane_bht_idx_now     = '{default: '0};
        lane_pht_pc_addr_now = '{default: '0};

        for (integer i = 0; i < IN_WIDTH; i++) begin
            // 逐lane形成指令自身PC；左移2等于乘4。bank编号随后按地址提取，不一定等于lane编号。
            lane_pc_now[i]          = pc_i + PC_WIDTH'($unsigned(i) << 2);
            lane_fetch_bank_now[i]  = lane_pc_now[i][2 +: FETCH_BANK_W];
            lane_bht_idx_now[i]     = {lane_fetch_bank_now[i], pc_fold_bht_local_idx(lane_pc_now[i])};
            lane_pht_pc_addr_now[i] = pc_fold_pht_row_idx(lane_pc_now[i]);
        end
    end

    always @(*) begin
        // 结果阶段：使用已寄存的BHT索引读取shadow；不把当前br_taken组合反馈到当前查询地址。
        lane_base_hist_live = '{default: '0};
        for (integer i = 0; i < IN_WIDTH; i++) begin
            lane_base_hist_live[i] = shadow_bht[lane_bht_idx_q[i]];
        end
    end

    always @(*) begin
        // 每个fetch bank的所有历史子bank并行读同一PC行；得到结果后再按历史选其中一个计数器。
        pht_addra_bank = '{default: '{default: '0}};
        for (integer i = 0; i < IN_WIDTH; i++) begin
            for (integer sb = 0; sb < PHT_BANKS; sb++) begin
                pht_addra_bank[lane_fetch_bank_now[i]][sb] = lane_pht_pc_addr_now[i];
            end
        end
    end

    always @(*) begin
        // 前端预测反馈的索引重建，定位要移入br_taken的active历史项。
        br_fetch_bank = '{default: '0};
        br_bht_idx    = '{default: '0};

        for (integer i = 0; i < IN_WIDTH; i++) begin
            br_fetch_bank[i] = br_pc[i][2 +: FETCH_BANK_W];
            br_bht_idx[i]    = {br_fetch_bank[i], pc_fold_bht_local_idx(br_pc[i])};
        end
    end

    always @(*) begin
        // 后端反馈译码：区分有效CBR/短训练许可，生成真实方向、旧历史、PHT训练位置及错误汇总。
        mispred_any     = 1'b0;
        rt_is_dir       = '0;
        rt_valid_dir    = '0;
        rt_fetch_bank   = '{default: '0};
        rt_bht_idx      = '{default: '0};
        rt_pht_pc_addr  = '{default: '0};
        rt_taken        = '0;
        rt_misp         = '0;
        rt_old_bhr      = '{default: '0};
        rt_pht_bank_sel = '{default: '0};
        rt_pht_ctr_idx  = '{default: '0};

        // 遍历反馈端口；符合条件的请求按端口顺序处理，具体处理历史还是入队由所在代码段决定。
        for (integer p = 0; p < PORT_WIDTH; p++) begin
            rt_is_dir[p]       = rt_grant[p] && (rt_brtype[p] == CBR_DIRECT);
            rt_valid_dir[p]    = rt_is_dir[p] && rt_dir_enable_i[p];
            rt_fetch_bank[p]   = rt_pc[p][2 +: FETCH_BANK_W];
            rt_bht_idx[p]      = {rt_fetch_bank[p], pc_fold_bht_local_idx(rt_pc[p])};
            rt_pht_pc_addr[p]  = pc_fold_pht_row_idx(rt_pc[p]);
            // 此实现从真实next PC与PC+4的比较推导方向；目标恰好等于PC+4时按不跳处理。
            rt_taken[p]        = (rt_brdest[p] != (rt_pc[p] + PC_WIDTH'($unsigned(32'd4))));
            rt_misp[p]         = (rt_exception[p] == EXCPT_BRWRONG);
            // PHT训练组合地址直接取寄存的commit_bht；下方顺序更新历史用tmp是另一层处理，不要混为同一份地址前递。
            rt_old_bhr[p]      = commit_bht[rt_bht_idx[p]];
            rt_pht_bank_sel[p] = rt_old_bhr[p][PHT_BANK_BITS-1:0];
            rt_pht_ctr_idx[p]  = {rt_old_bhr[p][BHR_BITS-1:PHT_BANK_BITS], 1'b0};

            mispred_any = mispred_any | (rt_is_dir[p] && rt_misp[p]);
        end
    end

    always @(*) begin
        // 任一有效条件分支反馈出错，本拍代际只加一次；旧标签历史随后回退到commit基准。
        epoch_next = active_epoch + EPOCH_BITS'(mispred_any ? 1'b1 : 1'b0);
    end

    always @(*) begin
        // 查询输出默认无效；本版本各lane独立使用base历史，prefix/effective仅保留观测名称。
        lp                    = '{default: '0};
        lane_prefix_hist_comb = '{default: '0};
        lane_hist_eff_comb    = '{default: '0};
        lane_ctr_idx_comb     = '{default: '0};
        lane_ctr_final_comb   = '{default: '0};
        lane_ctr_src_comb     = '{default: '0};
        lane_bypass_hit_comb  = '0;
        lane_pred_taken_comb  = '0;

        dbg_base_hist_o      = '{default: '0};
        dbg_prefix_hist_o    = '{default: '0};
        dbg_effective_hist_o = '{default: '0};
        dbg_pht_row_o        = '{default: '0};
        dbg_ctr_idx_o        = '{default: '0};
        dbg_bypass_hit_o     = '0;
        dbg_final_ctr_o      = '{default: '0};
        dbg_ctr_src_o        = '{default: '0};

        for (integer i = 0; i < IN_WIDTH; i++) begin
            // 输出查询临时量：由短历史低位选择PHT子bank。
            reg [PHT_BANK_BITS-1:0] pht_bank_sel;
            // 输出查询临时量：短PHT整行内目标两位的起始位偏移。
            reg [PHT_SUBIDX_W:0] ctr_idx;
            // 当前lane最终候选计数器：先取RAM值，再允许匹配bypass覆盖。
            reg [1:0] ctr_sel;
            // 局部旁路命中标志，循环匹配recent表时产生，最终再做查询有效门控。
            reg bypass_hit;

            // 历史低位选子bank，高位乘2得到行内位偏移；+:2表示从该位起取连续两位。
            pht_bank_sel = lane_base_hist_live[i][PHT_BANK_BITS-1:0];
            ctr_idx      = {lane_base_hist_live[i][BHR_BITS-1:PHT_BANK_BITS], 1'b0};
            ctr_sel      = pht_douta_bank[lane_fetch_bank_q[i]][pht_bank_sel][ctr_idx +: 2];
            bypass_hit   = 1'b0;

            // 匹配fetch bank、子bank、行号和位偏移；命中则以recent计数器覆盖同步RAM读出值。
            for (integer b = 0; b < BYPASS_DEPTH; b++) begin
                if (bypass_valid[lane_fetch_bank_q[i]][pht_bank_sel][b] &&
                    (bypass_row[lane_fetch_bank_q[i]][pht_bank_sel][b] == lane_pht_pc_addr_q[i]) &&
                    (bypass_ctr_idx[lane_fetch_bank_q[i]][pht_bank_sel][b] == ctr_idx)) begin
                    ctr_sel    = bypass_ctr[lane_fetch_bank_q[i]][pht_bank_sel][b];
                    bypass_hit = 1'b1;
                end
            end

            // 当前无组内prefix串联，base/prefix/effective数值相同。
            lane_prefix_hist_comb[i] = lane_base_hist_live[i];
            lane_hist_eff_comb[i]    = lane_base_hist_live[i];
            lane_ctr_idx_comb[i]     = ctr_idx;
            lane_bypass_hit_comb[i]  = have_q && bypass_hit;
            lane_ctr_final_comb[i]   = have_q ? ctr_sel : 2'b00;
            lane_ctr_src_comb[i]     = have_q ? (bypass_hit ? 2'd1 : 2'd0) : 2'd0;
            lane_pred_taken_comb[i]  = have_q ? ctr_sel[1] : 1'b0;
            lp[i]                    = lane_ctr_final_comb[i];

            dbg_base_hist_o[i]      = lane_base_hist_live[i];
            dbg_prefix_hist_o[i]    = lane_prefix_hist_comb[i];
            dbg_effective_hist_o[i] = lane_hist_eff_comb[i];
            dbg_pht_row_o[i]        = lane_pht_pc_addr_q[i];
            dbg_ctr_idx_o[i]        = lane_ctr_idx_comb[i];
            dbg_bypass_hit_o[i]     = lane_bypass_hit_comb[i];
            dbg_final_ctr_o[i]      = lane_ctr_final_comb[i];
            dbg_ctr_src_o[i]        = lane_ctr_src_comb[i];
        end
    end
 
    always @(*) begin
        // 只做各独立队列统计的汇总/最大值选择，不参与预测方向计算。
        dbg_bp_fifo_push_count = '0;
        dbg_bp_fifo_drop_count = '0;
        dbg_bp_fifo_peak_depth = '0;

        for (integer bank = 0; bank < IN_WIDTH; bank++) begin
            for (integer sb = 0; sb < PHT_BANKS; sb++) begin
                // 只做各独立队列统计的汇总/最大值选择，不参与预测方向计算。
                dbg_bp_fifo_push_count = dbg_bp_fifo_push_count + fifo_push_count_dbg[bank][sb];
                dbg_bp_fifo_drop_count = dbg_bp_fifo_drop_count + fifo_drop_count_dbg[bank][sb];
                if (fifo_peak_depth_dbg[bank][sb] > dbg_bp_fifo_peak_depth[BUF_BITS:0]) begin
                    dbg_bp_fifo_peak_depth = fifo_peak_depth_dbg[bank][sb];
                end
            end
        end
    end

    generate
        // 硬件展开：每个fetch bank再生成PHT_BANKS个RAM，每个A口查表、B口训练。
        for (g = 0; g < IN_WIDTH; g++) begin : gen_pht_mem
            for (genvar sb = 0; sb < PHT_BANKS; sb++) begin : gen_pht_subbank
                sync_dp_bram #(
                    .ADDR_W(PHT_PC_ADDR_W),
                    .DATA_W(PHT_SUBLINE_W),
                    .INIT_VALUE(PHT_INIT_SUBLINE)
                ) u_pht_mem (
                    .clka (clk),
                    .wea  (1'b0),
                    .addra(pht_addra_bank[g][sb]),
                    .dina ('0),
                    .douta(pht_douta_bank[g][sb]),
                    .clkb (clk),
                    .web  (pht_web_bank[g][sb]),
                    .addrb(pht_addrb_bank[g][sb]),
                    .dinb (pht_dinb_bank[g][sb]),
                    .doutb(pht_doutb_bank[g][sb])
                );
            end
        end
    endgenerate

    
    
    always @(posedge clk) begin
        if (rst) begin
            have_q             <= 1'b0;
            lane_fetch_bank_q  <= '{default: '0};
            lane_bht_idx_q     <= '{default: '0};
            lane_pht_pc_addr_q <= '{default: '0};
            active_epoch       <= '0;
            dbg_bp_repair_count <= '0;

            for (integer bi = 0; bi < BHT_ENTRIES; bi++) begin
                active_bht[bi] <= '0;
                commit_bht[bi] <= '0;
                epoch_tag[bi]  <= '0;
                shadow_bht[bi] <= '0;
            end
        end else begin
            // 当前时钟事件内按顺序合并反馈/修复/预测更新的临时投机历史副本，不是另一套独立寄存器。
            reg [BHR_BITS-1:0]   active_bht_tmp [0:BHT_ENTRIES-1];
            // 当前时钟事件内顺序处理多路真实反馈的临时基准历史副本。
            reg [BHR_BITS-1:0]   commit_bht_tmp [0:BHT_ENTRIES-1];
            // 本拍历史修复/投机更新后的代际标签临时副本，最终保存回epoch_tag。
            reg [EPOCH_BITS-1:0] epoch_tag_tmp  [0:BHT_ENTRIES-1];
            // 本拍选定的新当前代际；无错保持active_epoch，有错使用epoch_next。
            reg [EPOCH_BITS-1:0] active_epoch_tmp;
            // 本拍短历史修复条数的临时累加值，最后累加进dbg_bp_repair_count。
            reg [31:0]           repair_inc;

            repair_inc       = '0;
            active_epoch_tmp = mispred_any ? epoch_next : active_epoch;

            for (integer bi = 0; bi < BHT_ENTRIES; bi++) begin
                active_bht_tmp[bi] = active_bht[bi];
                commit_bht_tmp[bi] = commit_bht[bi];
                epoch_tag_tmp[bi]  = epoch_tag[bi];
            end

            have_q             <= have_inst_i;
            lane_fetch_bank_q  <= lane_fetch_bank_now;
            lane_bht_idx_q     <= lane_bht_idx_now;
            lane_pht_pc_addr_q <= lane_pht_pc_addr_now;
            active_epoch       <= active_epoch_tmp;


            // 遍历反馈端口；符合条件的请求按端口顺序处理，具体处理历史还是入队由所在代码段决定。
            for (integer p = 0; p < PORT_WIDTH; p++) begin
                // 按反馈端口顺序先移入真实结果；tmp副本保证同拍同BHT项的历史更新能够累积。
                if (rt_valid_dir[p]) begin
                    // 正在处理的后端反馈所对应的短BHT项索引。
                    reg [BHT_IDX_BITS-1:0] idx_u;
                    // 顺序处理当前反馈之前的commit历史临时值；用来生成新历史/长PHT训练地址。
                    reg [BHR_BITS-1:0]     old_bhr_c;
                    // 把当前真实rt_taken移入old_bhr_c后得到的新基准历史。
                    reg [BHR_BITS-1:0]     new_bhr_c;

                    idx_u     = rt_bht_idx[p];
                    old_bhr_c = commit_bht_tmp[idx_u];
                    new_bhr_c = bhr_shift_in(old_bhr_c, rt_taken[p]);

                    commit_bht_tmp[idx_u] = new_bhr_c;

                    // 错误分支自身历史改为已移入真实结果的基准历史，并打上新epoch标签。
                    if (rt_misp[p]) begin
                        active_bht_tmp[idx_u] = new_bhr_c;
                        epoch_tag_tmp[idx_u]  = epoch_next;
                        repair_inc            = repair_inc + 32'd1;
                    end
                end
            end

            // 发生错误时抑制本拍前端新投机历史移入，优先保留后端真实结果和修复。
            if (!mispred_any) begin
                for (integer i = 0; i < IN_WIDTH; i++) begin
                    if (br_grant[i] && br_dir_enable_i[i] &&
                        (br_brtype[i] == CBR_DIRECT)) begin
                        // 当前前端有效条件分支对应的短BHT索引，用来投机移入预测方向。
                        reg [BHT_IDX_BITS-1:0] idx_s;
                        // 投机更新的历史来源：epoch匹配取active，否则取commit，避免继续使用错误路径历史。
                        reg [BHR_BITS-1:0]     bhr_src;
                        // 移入一个结果后的历史，丢弃最高旧位、低位追加taken；也用于投机历史更新临时值。
                        reg [BHR_BITS-1:0]     bhr_new;

                        idx_s = br_bht_idx[i];
                        if (epoch_tag_tmp[idx_s] == active_epoch_tmp) begin
                            bhr_src = active_bht_tmp[idx_s];
                        end else begin
                            // 该项active不属于当前epoch，不能继承错误路径历史，从后端基准历史重新开始。
                            bhr_src = commit_bht_tmp[idx_s];
                        end

                        bhr_new = bhr_shift_in(bhr_src, br_taken[i]);
                        active_bht_tmp[idx_s] = bhr_new;
                        epoch_tag_tmp[idx_s]  = active_epoch_tmp;
                    end
                end
            end

            for (integer bi = 0; bi < BHT_ENTRIES; bi++) begin
                active_bht[bi] <= active_bht_tmp[bi];
                commit_bht[bi] <= commit_bht_tmp[bi];
                epoch_tag[bi]  <= epoch_tag_tmp[bi];
                // 生成下一拍查询可见shadow：epoch匹配用active，旧代际用commit实现惰性恢复。
                if (epoch_tag_tmp[bi] == active_epoch_tmp) begin
                    shadow_bht[bi] <= active_bht_tmp[bi];
                end else begin
                    shadow_bht[bi] <= commit_bht_tmp[bi];
                end
            end

            dbg_bp_repair_count <= dbg_bp_repair_count + repair_inc;
        end
    end


    generate
        // 每个fetch bank/历史子bank独立一条训练FIFO和读改写FSM，缓冲后端突发结果。
        for (g = 0; g < IN_WIDTH; g++) begin : gen_pht_queue_bank
            for (genvar sb = 0; sb < PHT_BANKS; sb++) begin : gen_pht_queue
                // 短训练FIFO每项的目标PHT行号；每个fetch bank/子bank各自一条队列。
                reg [PHT_PC_ADDR_W-1:0] fifo_pht_addr [0:BUF_DEPTH-1];
                // 短训练FIFO每项的行内计数器起始位偏移，与fifo_pht_addr合起来确定要改的两位。
                reg [PHT_SUBIDX_W:0]    fifo_ctr_idx  [0:BUF_DEPTH-1];
                // 短训练FIFO每项的真实方向，驱动饱和计数器加1或减1。
                reg                     fifo_taken    [0:BUF_DEPTH-1];

                // 短FIFO下一条入队位置，随成功入队数递增并按位宽环绕。
                reg [BUF_BITS-1:0]      fifo_head;
                // 短FIFO队首/下一条消费位置，写回完成后前移一项。
                reg [BUF_BITS-1:0]      fifo_tail;
                // 短FIFO当前占用项数，BUF_BITS+1位才能表示0到BUF_DEPTH。
                reg [BUF_BITS:0]        fifo_count;

                // 短PHT训练当前状态：RD_OLD读队首旧行，WR_NEW写修改后的行。
                reg                     curr_state;
                // 短训练FSM的组合下一状态，在时钟边沿保存到curr_state。
                reg                     next_state;

                // 已发起读取、等待写回的短训练请求行地址，在读阶段边沿捕获。
                reg [PHT_PC_ADDR_W-1:0] pend_pht_addr;
                // pending训练请求要修改的两位计数器起始位偏移。
                reg [PHT_SUBIDX_W:0]    pend_ctr_idx;
                // pending训练请求的真实方向；从FIFO取出后保存，直到完成更新。
                reg                     pend_taken;

                // 训练B口返回的旧整行数据，不是单个计数器。
                reg [PHT_SUBLINE_W-1:0] old_pht_subline;
                // 写回整行数据，先复制旧行，再替换目标计数器的两位。
                reg [PHT_SUBLINE_W-1:0] new_pht_subline;
                // 本次训练使用的更新前两位计数器，RAM初值可由同地址bypass覆盖。
                reg [1:0]               old_ctr;
                // sat2_update算出的新两位计数器，既写RAM也记入recent bypass。
                reg [1:0]               new_ctr;

                always @(*) begin
                    // 训练FSM：空队列留在读阶段；有队首发起读，下一拍写回，然后回读阶段。
                    next_state = curr_state;
                    unique case (curr_state)
                        STATE_RD_OLD: begin
                            if (fifo_count != 0) begin
                                next_state = STATE_WR_NEW;
                            end
                        end
                        STATE_WR_NEW: begin
                            next_state = STATE_RD_OLD;
                        end
                        default: begin
                            next_state = STATE_RD_OLD;
                        end
                    endcase
                end

                always @(*) begin
                    // 先取训练B口旧行，再用同计数器bypass纠正旧值，最后只替换行中的目标两位。
                    old_pht_subline = pht_doutb_bank[g][sb];
                    old_ctr         = old_pht_subline[pend_ctr_idx +: 2];
                    for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                        if (bypass_valid[g][sb][bi] &&
                            (bypass_row[g][sb][bi] == pend_pht_addr) &&
                            (bypass_ctr_idx[g][sb][bi] == pend_ctr_idx)) begin
                            old_ctr = bypass_ctr[g][sb][bi];
                        end
                    end
                    new_ctr                    = sat2_update(old_ctr, pend_taken);
                    // 复制整条旧行以保留其他计数器，下面的+:2切片仅改本次训练的计数器。
                    new_pht_subline            = old_pht_subline;
                    new_pht_subline[pend_ctr_idx +: 2] = new_ctr;
                end

                always @(*) begin
                    // 生成B口控制：读阶段只提供队首行号，写阶段拉高web并提供pending行号及新整行。
                    pht_web_bank[g][sb]   = 1'b0;
                    pht_addrb_bank[g][sb] = '0;
                    pht_dinb_bank[g][sb]  = '0;

                    if (curr_state == STATE_RD_OLD) begin
                        if (fifo_count != 0) begin
                            pht_addrb_bank[g][sb] = fifo_pht_addr[fifo_tail];
                        end
                    end else begin
                        // 生成B口控制：读阶段只提供队首行号，写阶段拉高web并提供pending行号及新整行。
                        pht_web_bank[g][sb]   = 1'b1;
                        pht_addrb_bank[g][sb] = pend_pht_addr;
                        pht_dinb_bank[g][sb]  = new_pht_subline;
                    end
                end

                always @(posedge clk) begin
                    if (rst) begin
                        fifo_head                  <= '0;
                        fifo_tail                  <= '0;
                        fifo_count                 <= '0;
                        curr_state                 <= STATE_RD_OLD;
                        pend_pht_addr              <= '0;
                        pend_ctr_idx               <= '0;
                        pend_taken                 <= 1'b0;
                        fifo_push_count_dbg[g][sb] <= '0;
                        fifo_drop_count_dbg[g][sb] <= '0;
                        fifo_peak_depth_dbg[g][sb] <= '0;
                        bypass_ptr[g][sb]          <= '0;

                        for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                            bypass_valid[g][sb][bi]   <= 1'b0;
                            bypass_row[g][sb][bi]     <= '0;
                            bypass_ctr_idx[g][sb][bi] <= '0;
                            bypass_ctr[g][sb][bi]     <= PHT_INIT_STATE;
                        end
                    end else begin
                        // 本时钟事件内的FIFO入队指针临时值，用来顺序合并本拍操作，最后写回head。
                        reg [BUF_BITS-1:0] head_tmp;
                        // 本时钟事件内的FIFO出队指针临时值，消费请求后前移。
                        reg [BUF_BITS-1:0] tail_tmp;
                        // 先处理出队、再检查入队后得到的占用数临时值，使同拍释放空间可用于新请求。
                        reg [BUF_BITS:0]   count_tmp;
                        // 本拍累计成功入队后的统计临时值。
                        reg [31:0]         push_count_tmp;
                        // 本拍累计因满队列丢训练后的统计临时值。
                        reg [31:0]         drop_count_tmp;

                        head_tmp       = fifo_head;
                        tail_tmp       = fifo_tail;
                        count_tmp      = fifo_count;
                        push_count_tmp = fifo_push_count_dbg[g][sb];
                        drop_count_tmp = fifo_drop_count_dbg[g][sb];

                        // 写回阶段消费旧队首并更新recent bypass；先扣占用，再接收本拍新请求。
                        if ((curr_state == STATE_WR_NEW) && (fifo_count != 0)) begin
                            // 局部标志：本次地址是否已在bypass中；命中原位改ctr，否则用bypass_ptr插入。
                            reg found_bypass;
                            found_bypass = 1'b0;
                            for (integer bi = 0; bi < BYPASS_DEPTH; bi++) begin
                                if (bypass_valid[g][sb][bi] &&
                                    (bypass_row[g][sb][bi] == pend_pht_addr) &&
                                    (bypass_ctr_idx[g][sb][bi] == pend_ctr_idx)) begin
                                    bypass_ctr[g][sb][bi] <= new_ctr;
                                    found_bypass          = 1'b1;
                                end
                            end
                            // 没有同地址旁路项才插入循环替换位置；指针按声明位宽自动回绕。
                            if (!found_bypass) begin
                                bypass_valid[g][sb][bypass_ptr[g][sb]]   <= 1'b1;
                                bypass_row[g][sb][bypass_ptr[g][sb]]     <= pend_pht_addr;
                                bypass_ctr_idx[g][sb][bypass_ptr[g][sb]] <= pend_ctr_idx;
                                bypass_ctr[g][sb][bypass_ptr[g][sb]]     <= new_ctr;
                                bypass_ptr[g][sb]                        <= bypass_ptr[g][sb] + BYPASS_BITS'(1);
                            end

                            tail_tmp  = fifo_tail + BUF_BITS'(1);
                            count_tmp = fifo_count - 1'b1;
                        end

                        // 遍历反馈端口；符合条件的请求按端口顺序处理，具体处理历史还是入队由所在代码段决定。
                        for (integer p = 0; p < PORT_WIDTH; p++) begin
                            if (rt_valid_dir[p] &&
                                (rt_fetch_bank[p] == FETCH_BANK_W'(g)) &&
                                (rt_pht_bank_sel[p] == PHT_BANK_BITS'(sb))) begin
                                // 队列有空位才收训练请求；无空位只增加drop统计，不回压处理器反馈接口。
                                if (count_tmp < BUF_DEPTH) begin
                                    fifo_pht_addr[head_tmp] <= rt_pht_pc_addr[p];
                                    fifo_ctr_idx[head_tmp]  <= rt_pht_ctr_idx[p];
                                    fifo_taken[head_tmp]    <= rt_taken[p];

                                    head_tmp       = head_tmp + BUF_BITS'(1);
                                    count_tmp      = count_tmp + 1'b1;
                                    push_count_tmp = push_count_tmp + 1'b1;
                                end else begin
                                    drop_count_tmp = drop_count_tmp + 1'b1;
                                end
                            end
                        end

                        fifo_head                  <= head_tmp;
                        fifo_tail                  <= tail_tmp;
                        fifo_count                 <= count_tmp;
                        curr_state                 <= next_state;
                        fifo_push_count_dbg[g][sb] <= push_count_tmp;
                        fifo_drop_count_dbg[g][sb] <= drop_count_tmp;

                        if (count_tmp > fifo_peak_depth_dbg[g][sb]) begin
                            fifo_peak_depth_dbg[g][sb] <= count_tmp;
                        end

                        // 读取旧行的同时捕获当前队首的行号/位偏移/方向，跨拍保存直到写回。
                        if ((curr_state == STATE_RD_OLD) && (fifo_count != 0)) begin
                            pend_pht_addr <= fifo_pht_addr[fifo_tail];
                            pend_ctr_idx  <= fifo_ctr_idx[fifo_tail];
                            pend_taken    <= fifo_taken[fifo_tail];
                        end
                    end
                end
            end
        end
    endgenerate

endmodule








// ============================================================================
// 短PHT使用的同步双端口RAM封装：A口查询，B口训练读改写，两个端口访问同一个mem。
// 实际两端口共用clka，clkb仅保留接口；同步读，输出在边沿后更新，本口写同址时返回旧值(read-first)。
// initial初始化全部数据及输出；无rst口。跨端口同址读写/同时写同址不要假设有新值旁路或可靠仲裁。
// ram_style只是块RAM推断提示，逻辑实例数不等于FPGA物理BRAM数量。
// ============================================================================
module sync_dp_bram #(
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
