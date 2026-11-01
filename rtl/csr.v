module csr#(
    parameter integer PRD_WIDTH = 6,
    parameter integer DATA_WIDTH = 32,
    parameter integer ZIMM_WIDTH = 5,
    parameter integer CSRADDR_WIDTH = 12,
    parameter integer TYPE_WIDTH = 3,
    parameter integer CSROP_WIDTH = 3,
    parameter integer EXCPT_WIDTH = 4,
    parameter integer PRIV_WIDTH = 2
) (
    input  wire clk,
    input  wire rst,
    input  wire [31:0] instret_inc,// 本周期退休增量，独立于当前 CSR 请求。

    input  wire csr_have_inst,//当前有 CSR 操作
    input  wire [PRD_WIDTH-1:0] csr_prd,//返回结果的物理寄存器
    input  wire [DATA_WIDTH-1:0] csr_prs1_data,//源寄存器的数据
    input  wire [ZIMM_WIDTH-1:0] csr_zimm,//立即数操作数
    input  wire [CSRADDR_WIDTH-1:0] csr_addr,//访问哪个 CSR
    input  wire [TYPE_WIDTH-1:0] csr_wrtype,   //是否需要普通寄存器结果
    input  wire [CSROP_WIDTH-1:0] csr_csrtype,  //对 CSR 做什么操作
    
    // 【清除】屏蔽当前指令的有效结果和指令侧 CSR 写入。
    // 不屏蔽 CLINT 写入、特权级设置或两个计数器的运行。
    input  wire ctrl_clear, 

    output reg wb3_valid,// 组合结果有效
    output reg wb3_regw, // 使能普通寄存器结果的数据保存/广播
    output reg [PRD_WIDTH-1:0] wb3_prd,
    output reg [DATA_WIDTH-1:0] wb3_data,  // 返回目标 CSR 的旧值，不是候选新值。    
    output reg [EXCPT_WIDTH-1:0] wb3_exception, 

    output reg [PRIV_WIDTH-1:0] priv_level, // 时序保存的当前特权级，由 CLINT 请求修改
    
     // 【CLINT 访问接口】供异常/中断入口及返回状态机读写 CSR。
    input  wire clint_rd_en,// 允许 CLINT 读取
    input  wire [CSRADDR_WIDTH-1:0] clint_rd_addr,// CLINT 本周期要读取的 CSR 地址。
    output reg [DATA_WIDTH-1:0] clint_rd_data,// 组合读取结果

    input  wire clint_wr_en,// CLINT 写使能，优先于整个指令侧写通道。
    input  wire [CSRADDR_WIDTH-1:0] clint_wr_addr,// CLINT 本周期要写入的 CSR 地址
    input  wire [DATA_WIDTH-1:0] clint_wr_data, // CLINT 写入数据

    input  wire clint_priv_set_en,// 允许更新特权级，独立于 CSR 写使能
    input  wire [PRIV_WIDTH-1:0] clint_priv_set_val,// 将要保存的特权级编码，默认宽度为 2 位。

    output reg ctrl_flush_TLB,// 组合 TLB 刷新请求

    output reg [DATA_WIDTH-1:0] mie, // 实际保存的中断使能状态；这里输出原值，CSR 地址读取另有掩码
    output reg [DATA_WIDTH-1:0] mstatus// 实际保存的状态寄存器，也被 sstatus/ustatus 视图共享
    );
    
localparam integer CSROP_CSRRWI = 4;
localparam integer CSROP_CSRRSI = 5;
localparam integer CSROP_CSRRCI = 6;
localparam integer CSROP_CSRRW = 1;
localparam integer CSROP_CSRRS = 2;
localparam integer CSROP_CSRRC = 3;
localparam integer EXCPT_NOEX = 0;
localparam integer EXCPT_CSR_ILLEGAL = 6;
localparam integer EXCPT_CSR_SIDE_EFFECT = 7;
localparam integer RETIRE_WR_ARF = 1;
localparam integer CSROP_READ = 7;
localparam integer PRIV_M_MODE = 3;

    localparam [11:0] CSR_USTATUS   = 12'h000; // U 状态视图，读取/写入 mstatus 的 USTATUS_MASK 部分。
    localparam [11:0] CSR_UIE       = 12'h004; // U 中断使能视图，共享 mie 存储。
    localparam [11:0] CSR_UTVEC     = 12'h005; // U 陷阱入口；写入经过 tvec_warl。
    localparam [11:0] CSR_USCRATCH  = 12'h040; // U 软件暂存寄存器。
    localparam [11:0] CSR_UEPC      = 12'h041; // U 陷阱返回地址，低两位清零。
    localparam [11:0] CSR_UCAUSE    = 12'h042; // U 陷阱原因保存值。
    localparam [11:0] CSR_UTVAL     = 12'h043; // U 陷阱附加信息保存值。
    localparam [11:0] CSR_UIP       = 12'h044; // U 中断挂起影子值，本实现独立存储。

    localparam [11:0] CSR_SSTATUS   = 12'h100;
    localparam [11:0] CSR_SIE       = 12'h104; // S 中断使能视图，共享 mie 的位 1/5/9。
    localparam [11:0] CSR_STVEC     = 12'h105; // S 陷阱入口；写入经过 tvec_warl。
    localparam [11:0] CSR_SSCRATCH  = 12'h140; // S 软件暂存寄存器。
    localparam [11:0] CSR_SEPC      = 12'h141; // S 陷阱返回地址，低两位清零。
    localparam [11:0] CSR_SCAUSE    = 12'h142; // S 陷阱原因保存值。
    localparam [11:0] CSR_STVAL     = 12'h143; // S 陷阱附加信息保存值。
    localparam [11:0] CSR_SIP       = 12'h144; // S 中断挂起存储，使用位 1/5/9，与 mip 不自动同步。
    localparam [11:0] CSR_SATP      = 12'h180; // 地址翻译配置存储；写入附带副作用标记和刷新请求。

    localparam [11:0] CSR_MSTATUS   = 12'h300; // M 状态寄存器，本实现掩码为全 1。
    localparam [11:0] CSR_MISA      = 12'h301; // 固定 ISA 声明，读出 0x40001100；写 case 没有更新分支。
    localparam [11:0] CSR_MIE       = 12'h304; // M 中断使能视图，读写使用 MIE_MASK。
    localparam [11:0] CSR_MTVEC     = 12'h305; // M 陷阱入口；跳转地址计算由外围 CLINT 负责。
    localparam [11:0] CSR_MSCRATCH  = 12'h340; // M 软件暂存寄存器。
    localparam [11:0] CSR_MEPC      = 12'h341; // M 陷阱返回地址，低两位清零。
    localparam [11:0] CSR_MCAUSE    = 12'h342; // M 陷阱原因，通常由 CLINT 写入。
    localparam [11:0] CSR_MTVAL     = 12'h343; // M 陷阱附加信息存储。
    localparam [11:0] CSR_MIP       = 12'h344; // M 中断挂起存储，本模块没有外部中断输入直接更新它。

    localparam [11:0] CSR_CYCLE     = 12'hC00; // 64 位周期计数低 32 位，只读地址类别。
    localparam [11:0] CSR_CYCLEH    = 12'hC80; // 64 位周期计数高 32 位。
    localparam [11:0] CSR_TIME      = 12'hC01; // 复用 cycle_cnt 的低 32 位，没有独立时间源。
    localparam [11:0] CSR_TIMEH     = 12'hC81; // 复用 cycle_cnt 的高 32 位。
    localparam [11:0] CSR_INSTRET   = 12'hC02; // 64 位退休指令计数低 32 位。
    localparam [11:0] CSR_INSTRETH  = 12'hC82; // 64 位退休指令计数高 32 位。
    
    reg [DATA_WIDTH-1:0] mip, mtvec, mscratch, mepc, mcause, mtval;
    reg [DATA_WIDTH-1:0] stvec, sscratch, sepc, scause, stval, satp, sip;
    reg [DATA_WIDTH-1:0] utvec, uscratch, uepc, ucause, utval, uip_shadow;
    
    // 【64 位计数器】RV32 通过高/低两个 CSR 地址分别读取。
    // cycle 统计周期，instret 按外部退休增量累计；time 在本实现中复用 cycle。
    reg [63:0] cycle_cnt;
    reg [63:0] instret_cnt;
    
    localparam [31:0] SSTATUS_MASK = 32'h0000_1E33; 
    localparam [31:0] USTATUS_MASK = 32'h0000_0011; // U 状态视图只保留位 0、4。
    localparam [31:0] SIE_MASK     = (32'h1 << 1) | (32'h1 << 5) | (32'h1 << 9); // S 中断相关位为 1、5、9，即掩码 0x222。
    localparam [31:0] UIE_MASK     = (32'h1 << 0); // 仅开放位 0；MIE_MASK 不含该位，故底层 mie 与 MIE 地址读值可能不同。

    localparam [31:0] MIE_MASK     = 32'h0000_0AAA; // 0xAAA 开放位 1、3、5、7、9、11。
    localparam [31:0] MIP_MASK     = 32'h0000_0AAA;
    localparam [31:0] MSTATUS_MASK = 32'hFFFF_FFFF; // 全 1：本实现不在此过滤保留位或非法字段组合。
    localparam [31:0] SATP_MASK    = 32'hFFFF_FFFF; // 全 1：这里保存全部 32 位，不校验翻译模式。
    localparam [31:0] TVEC_MASK    = 32'hFFFF_FFFF;
    localparam [31:0] EPC_MASK     = 32'hFFFF_FFFC; // 清除低两位，按 4 字节地址对齐保存和读取。


reg [1:0] csr_req_priv;
    reg csr_is_ro;
    always @(*) begin
        csr_req_priv = csr_addr[9:8];
        csr_is_ro    = (csr_addr[11:10] == 2'b11);//read_only
    end
    
//// 【陷阱入口 WARL 规范化】保留高 30 位基址，将模式限制为 00 或 01。
// 00=直接模式；01=向量模式；输入 10 映射到 00，11 映射到 01。
//tvec 用来配置异常、中断处理程序的入口
function automatic [31:0] tvec_warl(input reg [31:0] v);
    begin
        case (v[1:0])
            2'b00: tvec_warl = {v[31:2], 2'b00}; 
            2'b01: tvec_warl = {v[31:2], 2'b01}; 
            2'b10: tvec_warl = {v[31:2], 2'b00}; 
            2'b11: tvec_warl = {v[31:2], 2'b01}; 
        endcase
    end
endfunction

    function automatic [DATA_WIDTH-1:0] csr_read(
        input reg [11:0] a,
        input reg [DATA_WIDTH-1:0] mstatus,
        input reg [DATA_WIDTH-1:0] mie,
        input reg [DATA_WIDTH-1:0] utvec,
        input reg [DATA_WIDTH-1:0] uscratch,
        input reg [DATA_WIDTH-1:0] uepc,
        input reg [DATA_WIDTH-1:0] ucause,
        input reg [DATA_WIDTH-1:0] utval,
        input reg [DATA_WIDTH-1:0] uip_shadow,
        input reg [DATA_WIDTH-1:0] stvec,
        input reg [DATA_WIDTH-1:0] sscratch,
        input reg [DATA_WIDTH-1:0] sepc,
        input reg [DATA_WIDTH-1:0] scause,
        input reg [DATA_WIDTH-1:0] stval,
        input reg [DATA_WIDTH-1:0] sip,
        input reg [DATA_WIDTH-1:0] satp,
        input reg [DATA_WIDTH-1:0] mtvec,
        input reg [DATA_WIDTH-1:0] mscratch,
        input reg [DATA_WIDTH-1:0] mepc,
        input reg [DATA_WIDTH-1:0] mcause,
        input reg [DATA_WIDTH-1:0] mtval,
        input reg [DATA_WIDTH-1:0] mip,
        input reg [63:0] cycle_cnt,
        input reg [63:0] instret_cnt
    );
        reg [DATA_WIDTH-1:0] v;
        begin
            v = 0;
            case (a)
                
                CSR_USTATUS  : v = (mstatus & USTATUS_MASK);
                CSR_UIE      : v = (mie & UIE_MASK);
                CSR_UTVEC    : v = (utvec & TVEC_MASK);
                CSR_USCRATCH : v = uscratch;
                CSR_UEPC     : v = (uepc & EPC_MASK);
                CSR_UCAUSE   : v = ucause;
                CSR_UTVAL    : v = utval;
                CSR_UIP      : v = uip_shadow;

                CSR_SSTATUS  : v = (mstatus & SSTATUS_MASK);
                CSR_SIE      : v = (mie & SIE_MASK);
                CSR_STVEC    : v = (stvec & TVEC_MASK);
                CSR_SSCRATCH : v = sscratch;
                CSR_SEPC     : v = (sepc & EPC_MASK);
                CSR_SCAUSE   : v = scause;
                CSR_STVAL    : v = stval;
                CSR_SIP      : v = (sip & SIE_MASK);
                CSR_SATP     : v = (satp & SATP_MASK);

                CSR_MSTATUS  : v = (mstatus & MSTATUS_MASK);
                CSR_MISA     : v = 32'h4000_1100; 
                CSR_MIE      : v = (mie & MIE_MASK);
                CSR_MTVEC    : v = (mtvec & TVEC_MASK);
                CSR_MSCRATCH : v = mscratch;
                CSR_MEPC     : v = (mepc & EPC_MASK);
                CSR_MCAUSE   : v = mcause;
                CSR_MTVAL    : v = mtval;
                CSR_MIP      : v = (mip & MIP_MASK);

                CSR_CYCLE    : v = cycle_cnt[31:0];
                CSR_CYCLEH   : v = cycle_cnt[63:32];
                CSR_TIME     : v = cycle_cnt[31:0];
                CSR_TIMEH    : v = cycle_cnt[63:32];
                CSR_INSTRET  : v = instret_cnt[31:0];
                CSR_INSTRETH : v = instret_cnt[63:32];

                default      : v = 0;
            endcase
            csr_read = v;
        end
    endfunction

    reg [DATA_WIDTH-1:0] rob_old_val;//读取旧 CSR
    reg [DATA_WIDTH-1:0] rob_src_val;//寄存器数据或零扩展立即数
    reg [DATA_WIDTH-1:0] rob_new_val;//候选写入值
    reg rob_do_write;//按当前操作逻辑认定有写访问
    reg rob_illegal;//访问非法，例如权限不足
    reg rob_side_effect;//需刷新
    reg rob_satp_write;//本次被识别为写 satp

    always @(*) begin
        rob_old_val = csr_read(csr_addr[11:0], mstatus, mie, utvec, uscratch, uepc, ucause, utval, uip_shadow, stvec, sscratch, sepc, scause, stval, sip, satp, mtvec, mscratch, mepc, mcause, mtval, mip, cycle_cnt, instret_cnt);// 读取地址为 csr_addr 的 CSR
        
        if (csr_csrtype == CSROP_CSRRWI || csr_csrtype == CSROP_CSRRSI || csr_csrtype == CSROP_CSRRCI) begin
            rob_src_val = {{(DATA_WIDTH-ZIMM_WIDTH){1'b0}}, csr_zimm};
        end else begin
            rob_src_val = csr_prs1_data;
        end
        rob_do_write = 1'b0;
        rob_new_val  = rob_old_val;
        case (csr_csrtype)
            CSROP_CSRRW: begin
                rob_do_write = 1'b1;
                rob_new_val  = rob_src_val;
            end
            CSROP_CSRRS: begin
                if (rob_src_val != 0) begin
                    rob_do_write = 1'b1;
                    rob_new_val  = rob_old_val | rob_src_val;
                end
            end
            CSROP_CSRRC: begin
                if (rob_src_val != 0) begin
                    rob_do_write = 1'b1;
                    rob_new_val  = rob_old_val & ~rob_src_val;
                end
            end
            CSROP_CSRRWI: begin
                rob_do_write = 1'b1;
                rob_new_val  = rob_src_val;
            end
            CSROP_CSRRSI: begin
                if (rob_src_val != 0) begin
                    rob_do_write = 1'b1;
                    rob_new_val  = rob_old_val | rob_src_val;
                end
            end
            CSROP_CSRRCI: begin
                if (rob_src_val != 0) begin
                    rob_do_write = 1'b1;
                    rob_new_val  = rob_old_val & ~rob_src_val;
                end
            end
            default: begin
                rob_do_write = 1'b0;
                rob_new_val  = rob_old_val;
            end
        endcase
    end

    //非法情况判断
    always @(*) begin
        rob_illegal = 1'b0;
        if (csr_req_priv == 2'b10) begin
            rob_illegal = 1'b1;
        end else begin

            if (priv_level < csr_req_priv) begin
                rob_illegal = 1'b1;
            end
        end
        if (rob_do_write && csr_is_ro) begin
            rob_illegal = 1'b1;
        end
    end
    
    //satp处理
    always @(*) begin
        rob_satp_write  = (rob_do_write && (csr_addr[11:0] == CSR_SATP));
        rob_side_effect = 1'b0;
        if (rob_do_write) begin
            case (csr_addr[11:0])
                CSR_SATP: rob_side_effect = 1'b1;//写 satp  → 有副作用
                default: rob_side_effect = 1'b0;
            endcase
        end
    end
    
    always @(*) begin
        wb3_valid = csr_have_inst && !ctrl_clear;
        wb3_prd   = csr_prd;
        wb3_data  = rob_old_val;

        if (!wb3_valid) begin
            wb3_exception = EXCPT_NOEX;
        end else if (rob_illegal) begin
            wb3_exception = EXCPT_CSR_ILLEGAL;
        end else if (rob_side_effect) begin
            wb3_exception = EXCPT_CSR_SIDE_EFFECT;
        end else begin
            wb3_exception = EXCPT_NOEX;
        end

        wb3_regw = 1'b0;
        if (wb3_valid) begin
            if ((csr_wrtype == RETIRE_WR_ARF) && (csr_prd != 0) && (wb3_exception == EXCPT_NOEX)) begin
                wb3_regw = 1'b1;
            end
        end
    end

    reg rob_accept;  //指令侧这次写请求具备写入资格
    always @(*) begin
        rob_accept = csr_have_inst && !ctrl_clear && !rob_illegal && rob_do_write && (csr_csrtype != CSROP_READ);
    end

    always @(*) begin
        clint_rd_data = 0;
        if (clint_rd_en) begin
            clint_rd_data = csr_read(clint_rd_addr[11:0], mstatus, mie, utvec, uscratch, uepc, ucause, utval, uip_shadow, stvec, sscratch, sepc, scause, stval, sip, satp, mtvec, mscratch, mepc, mcause, mtval, mip, cycle_cnt, instret_cnt);
            
            if (rob_accept && (clint_rd_addr[11:0] == csr_addr[11:0])) begin
                clint_rd_data = rob_new_val;//前递
            end
            if (clint_wr_en && (clint_wr_addr[11:0] == clint_rd_addr[11:0])) begin
                clint_rd_data = clint_wr_data;
            end
        end
    end

    always @(*) begin
        ctrl_flush_TLB = 1'b0;

        if (rob_accept && rob_satp_write) begin//指令侧
            ctrl_flush_TLB = 1'b1;
        end
        if (clint_wr_en && (clint_wr_addr[11:0] == CSR_SATP)) begin//clint侧
            ctrl_flush_TLB = 1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_cnt <= 64'd0;
            instret_cnt <= 64'd0;
        end else begin
            cycle_cnt <= cycle_cnt + 64'd1;
            instret_cnt <= instret_cnt + {32'd0, instret_inc};
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            priv_level <= PRIV_M_MODE;
        end else begin
            if (clint_priv_set_en) begin
                priv_level <= clint_priv_set_val;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus    <= 32'h0000_0000;
            mie        <= 32'h0000_0000;
            mip        <= 32'h0000_0000;
            mtvec      <= 32'h0000_0000;
            mscratch   <= 32'h0000_0000;
            mepc       <= 32'h0000_0000;
            mcause     <= 32'h0000_0000;
            mtval      <= 32'h0000_0000;

            stvec      <= 32'h0000_0000;
            sscratch   <= 32'h0000_0000;
            sepc       <= 32'h0000_0000;
            scause     <= 32'h0000_0000;
            stval      <= 32'h0000_0000;
            satp       <= 32'h0000_0000;
            sip        <= 32'h0000_0000;

            utvec      <= 32'h0000_0000;
            uscratch   <= 32'h0000_0000;
            uepc       <= 32'h0000_0000;
            ucause     <= 32'h0000_0000;
            utval      <= 32'h0000_0000;
            uip_shadow <= 32'h0000_0000;
        end else begin
            
            if (clint_wr_en) begin
                case (clint_wr_addr[11:0])
                    
                    CSR_USTATUS:   mstatus    <= (mstatus & ~USTATUS_MASK) | (clint_wr_data & USTATUS_MASK);
                    CSR_UIE:       mie        <= (mie & ~UIE_MASK)         | (clint_wr_data & UIE_MASK);
                    CSR_UTVEC:     utvec      <= tvec_warl(clint_wr_data);
                    CSR_USCRATCH:  uscratch   <= clint_wr_data;
                    CSR_UEPC:      uepc       <= (clint_wr_data & EPC_MASK);
                    CSR_UCAUSE:    ucause     <= clint_wr_data;
                    CSR_UTVAL:     utval      <= clint_wr_data;
                    CSR_UIP:       uip_shadow <= clint_wr_data;

                    CSR_SSTATUS:   mstatus    <= (mstatus & ~SSTATUS_MASK) | (clint_wr_data & SSTATUS_MASK);
                    CSR_SIE:       mie        <= (mie & ~SIE_MASK)         | (clint_wr_data & SIE_MASK);
                    CSR_STVEC:     stvec      <= tvec_warl(clint_wr_data);
                    CSR_SSCRATCH:  sscratch   <= clint_wr_data;
                    CSR_SEPC:      sepc       <= (clint_wr_data & EPC_MASK);
                    CSR_SCAUSE:    scause     <= clint_wr_data;
                    CSR_STVAL:     stval      <= clint_wr_data;
                    CSR_SIP:       sip        <= (sip & ~SIE_MASK)         | (clint_wr_data & SIE_MASK);
                    CSR_SATP:      satp       <= (clint_wr_data & SATP_MASK);

                    CSR_MSTATUS:   mstatus    <= (mstatus & ~MSTATUS_MASK) | (clint_wr_data & MSTATUS_MASK);
                    CSR_MIE:       mie        <= (mie & ~MIE_MASK)         | (clint_wr_data & MIE_MASK);
                    CSR_MTVEC:     mtvec      <= tvec_warl(clint_wr_data);
                    CSR_MSCRATCH:  mscratch   <= clint_wr_data;
                    CSR_MEPC:      mepc       <= (clint_wr_data & EPC_MASK);
                    CSR_MCAUSE:    mcause     <= clint_wr_data;
                    CSR_MTVAL:     mtval      <= clint_wr_data;
                    CSR_MIP:       mip        <= (mip & ~MIP_MASK)         | (clint_wr_data & MIP_MASK);

                    default: begin
                        
                    end
                endcase
            end

            else if (rob_accept) begin
                case (csr_addr[11:0])
                    
                    CSR_USTATUS:   mstatus    <= (mstatus & ~USTATUS_MASK) | (rob_new_val & USTATUS_MASK);
                    CSR_UIE:       mie        <= (mie & ~UIE_MASK)         | (rob_new_val & UIE_MASK);
                    CSR_UTVEC:     utvec      <= tvec_warl(rob_new_val);
                    CSR_USCRATCH:  uscratch   <= rob_new_val;
                    CSR_UEPC:      uepc       <= (rob_new_val & EPC_MASK);
                    CSR_UCAUSE:    ucause     <= rob_new_val;
                    CSR_UTVAL:     utval      <= rob_new_val;
                    CSR_UIP:       uip_shadow <= rob_new_val;

                    CSR_SSTATUS:   mstatus    <= (mstatus & ~SSTATUS_MASK) | (rob_new_val & SSTATUS_MASK);
                    CSR_SIE:       mie        <= (mie & ~SIE_MASK)         | (rob_new_val & SIE_MASK);
                    CSR_STVEC:     stvec      <= tvec_warl(rob_new_val);
                    CSR_SSCRATCH:  sscratch   <= rob_new_val;
                    CSR_SEPC:      sepc       <= (rob_new_val & EPC_MASK);
                    CSR_SCAUSE:    scause     <= rob_new_val;
                    CSR_STVAL:     stval      <= rob_new_val;
                    CSR_SIP:       sip        <= (sip & ~SIE_MASK)         | (rob_new_val & SIE_MASK);
                    CSR_SATP:      satp       <= (rob_new_val & SATP_MASK);

                    CSR_MSTATUS:   mstatus    <= (mstatus & ~MSTATUS_MASK) | (rob_new_val & MSTATUS_MASK);
                    CSR_MIE:       mie        <= (mie & ~MIE_MASK)         | (rob_new_val & MIE_MASK);
                    CSR_MTVEC:     mtvec      <= tvec_warl(rob_new_val);
                    CSR_MSCRATCH:  mscratch   <= rob_new_val;
                    CSR_MEPC:      mepc       <= (rob_new_val & EPC_MASK);
                    CSR_MCAUSE:    mcause     <= rob_new_val;
                    CSR_MTVAL:     mtval      <= rob_new_val;
                    CSR_MIP:       mip        <= (mip & ~MIP_MASK)         | (rob_new_val & MIP_MASK);

                    default: begin
                        
                    end
                endcase
            end
        end
    end
endmodule
