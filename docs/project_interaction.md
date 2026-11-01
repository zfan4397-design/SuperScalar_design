# 参考项目模块交互图

按 `D:/zz/superscalercore` 当前源码中的实例和端口连接绘制。描述参考项目的完整结构，不表示练习项目已经实现了全部模块。图中把重复通道、流水寄存器和同类信号合并；标为“连线”的节点不是额外 RTL 模块。

## 整机：top → student_top → 两个 core_cpu

```mermaid
flowchart TB
    CLOCK["差分系统时钟"] --> PLL["pll：CPU时钟 / 50MHz时钟 / 复位来源"]
    UART["uart：串口收发"] <--> TWIN["twin_controller：虚拟开关、按键、显示交互"]
    PLL --> UART
    PLL --> TWIN
    subgraph SYSTEM["student_top"]
        MAIN["maincore：core_cpu"]
        CHECK["checkcore：core_cpu"]
        IM["主核指令BRAM：blk_mem_gen_2 × IN_WIDTH"]
        IC["检查核指令BRAM：blk_mem_gen_2 × IN_WIDTH"]
        DM["主核 perip_bridge + 数据BRAM"]
        DC["检查核 perip_bridge + 数据BRAM"]
        FI["lockstep_fault_injector + XOR连线：可选故障注入"]
        CMP["lockstep_commit_compare：退休流比较、节奏控制、恢复"]
        MMIO["mmio_bridge：开关 / 按键 / LED / 数码管 / counter / clint_timer"]
        MAIN <-->|"icache接口：地址 / 指令"| IM
        CHECK <-->|"icache接口：地址 / 指令"| IC
        MAIN <-->|"dcache接口：普通读写"| DM
        CHECK <-->|"dcache接口：普通读写"| DC
        MAIN -->|"退休记录和MMIO请求"| FI
        CHECK -->|"退休记录和MMIO请求"| FI
        FI -->|"原记录或注入后的记录"| CMP
        CMP -.->|"退休许可 / 比较确认 / 回滚信息"| MAIN
        CMP -.->|"退休许可 / 比较确认 / 回滚信息"| CHECK
        CMP <-->|"共享MMIO请求与响应"| MMIO
        MMIO -->|"timer_irq"| CMP
    end
    PLL --> MAIN
    PLL --> CHECK
    TWIN -->|"virtual_sw / virtual_key"| MMIO
    MMIO -->|"virtual_led / virtual_seg"| TWIN
```

- 两个核使用相同的 `core_cpu` 模块，独立执行，退休节奏由比较模块协调。
- 当前顶层的 `icache_busy` 和 `dcache_busy` 为常量 0；接口名叫 cache，并不代表这里实例化了完整 Cache 或 AXI 总线。
- `perip_bridge` 下接 `dram_driver` 和两个 `empty_dram_driver`，分别覆盖普通数据、异常向量及日志区域。
- `lockstep_commit_compare` 的定义位于 `vsrc/lockstep/compare_fifo.sv`，文件名和模块名不同。
- 故障注入器生成掩码，顶层 XOR 连线把掩码施加到两核输出。`top.sv` 默认把外部故障注入请求接成 0。

## 单个 core_cpu：指令、数据、写回与退休

```mermaid
flowchart TB
    IMEM["指令BRAM"] --> IF
    subgraph FRONT["前端"]
        IF["if_stage：pc_reg / branch_predict / ifq"]
        ID["id_stage：rv32i_decoder / extend"]
        D0["dff_id_rr"]
        RR["rr_stage：rat"]
        D1["dff_rr_rob：分发前流水寄存器"]
        IF --> ID --> D0 --> RR --> D1
    end
    subgraph ROBGROUP["rob_ctrl"]
        ROB["rob：指令信息、结果、完成状态"]
        FIFO["rob_fifo：分配 / 退休 / walk顺序"]
        FL["freelist：空闲物理寄存器编号"]
    end
    FL -->|"freelist_valid / freelist_prd"| RR
    RR -->|"freelist_consume"| FL
    FIFO -->|"rob_fifonum"| RR
    D1 -->|"分配ROB项"| ROB
    D1 -->|"记录分配顺序"| FIFO
    subgraph ISSUE["issue_cluster"]
        AQ["rs_issue_queue × ALU_NUM"]
        LQ["rs_lsu_queue"]
        MQ["rs_mul_queue"]
        DQ["rs_div_queue"]
        BQ["biq：分支等待、计算、预测检查"]
    end
    D1 --> AQ
    D1 --> LQ
    D1 --> MQ
    D1 --> DQ
    D1 --> BQ
    AQ -->|"整数指令"| RO
    LQ -->|"访存指令"| RO
    MQ -->|"乘法指令"| RO
    DQ -->|"除法指令"| RO
    RO["各路 dff_iq_ro + read_oprand + dff_ro_fu_*：按通路分别实例化"]
    ROB -->|"源操作数数据和ready"| RO
    RO --> ALU["fu_integer × FU0WB_WIDTH"]
    RO --> MEM["fu_mem"]
    RO --> MUL["fu_mul → rv32m_mul_unit"]
    RO --> DIV["fu_div → rv32m_div_unit"]
    ALU --> WB["写回汇合与广播连线：含对应WB流水寄存器"]
    MEM --> WB
    MUL --> WB
    DIV --> WB
    BQ -->|"wb2"| WB
    WB -->|"结果 / 完成 / 异常"| ROB
    WB -.->|"旁路数据"| RO
    WB -.->|"广播唤醒"| ISSUE
    RO -.->|"resp_valid / resp_issued / 队列项编号"| ISSUE
    EXREADY["各FU可接收状态"] -.->|"fu_ready_i"| ISSUE
    ROB -->|"队首CSR/MMIO信息"| COM["commit_unit：csr + mmio_interface"]
    COM -->|"wb3"| ROB
    COM <-->|"CSR读写 / 特权状态"| CLINT["clint：异常、中断、返回处理"]
    ROB -->|"退休候选的ready / 类型 / 数据 / 异常"| RET["retire_ctrl"]
    RET -->|"rob_grant：最终退休授权"| ROBGROUP
    RET -->|"arf_v / rd / data"| ARF["arf：架构寄存器状态"]
    RET -->|"rt_grant和退休映射信息"| RR
    MEM -->|"store分配 / load查询与转发"| SB["store_buffer：位于fu_mem内部"]
    RET -->|"stbf_grant / stbf_id"| SB
    MEM <-->|"load请求与数据；store经fu_mem排出"| DMEM["perip_bridge / 数据BRAM"]
    RET -->|"异常请求 / 异常码 / PC / nxtPC"| CLINT
    CLINT -->|"except_resp / exceptend"| RET
    RET -->|"退休记录：在core_cpu顶层组合"| COMPARE["核外 lockstep_commit_compare"]
    COMPARE -.->|"core_retire_grant"| RET
    COMPARE -.->|"compare_grant：确认比较完成"| ROBGROUP
    COMPARE -.->|"比较后的映射确认 / 回滚"| RR
    COMPARE -.->|"compare_stbf_grant / id"| SB
    COM <-->|"核外比较器协调MMIO"| COMPARE
```

- 各路 `read_oprand` 独立实例化，共享写回旁路输入；图中的合并节点不表示不同类型指令共用一个读操作数模块。
- BIQ 自己完成分支计算，通过 wb2 写回；当前前端名字为 rt_* 的分支训练端口，顶层实际接 BIQ 的 wb2 信息。
- `arf` 在当前模块中只有退休写接口；读操作数的数据路径来自 ROB 和写回旁路。
- 普通执行写回不等于退休；退休也不等于锁步比较确认。
- 核内退休先通知 Store Buffer；比较确认的存储授权还有单独的 `compare_stbf_grant`，不能把核内退休画成直接写外部内存。
- `commit_unit` 处理 CSR/MMIO；它不是所有普通整数指令都必须经过的最终退休级。
- 队列的就绪候选由 `age_matrix_arbiter` 选年龄最老者，各类队列自己的发射条件仍然生效。

## 控制：暂停、分支恢复、异常、锁步回滚

```mermaid
flowchart LR
    B["BIQ发现预测错误"] -->|"ctrl_restore_req / flush_id / nxtpc_flush"| CTRL["ctrl_unit"]
    R["RAT / ROB / IQ / 访存的暂停或错误请求"] --> CTRL
    CTRL -->|"ctrl_stall_*"| PIPE["对应流水级与寄存器"]
    CTRL -->|"ctrl_restore_sig + nxtpc_flush"| FRONT["前端：重定向PC、清取指队列"]
    CTRL -->|"ctrl_restore + ctrl_flnum"| BACK["ROB / RAT / 发射队列 / 流水寄存器"]
    BACK -->|"ROB walk完成：ctrl_restoreend_req"| CTRL
    RET["retire_ctrl"] -->|"ctrl_except_req / code / pc / nxtpc"| C["CLINT"]
    RET -->|"ctrl_except_req / code"| CTRL
    C -->|"ctrl_except_resp / ctrl_exceptend"| RET
    C -->|"ctrl_exceptend"| CTRL
    C -->|"nxtpc_interrupt"| FRONT
    CTRL -->|"ctrl_clear"| CLEAR["各模块清空路径"]
    COMP["锁步比较模块"] -->|"recover_req / PC / 各核年龄边界"| CTRL
    COMP -->|"rollback_*"| ARCH["RAT / ROB-freelist / Store Buffer等恢复接口"]
    CTRL -->|"LOCKSTEP_CLEAR → LOCKSTEP_RESTORE"| ARCH
```

`ctrl_unit` 的 `ctrl_except_resp` 输出在顶层悬空；退休实际使用的同名信号由 CLINT 产生。

## 除法通路在整机中的位置

```mermaid
flowchart LR
    Q["rs_div_queue"] --> D0["dff_iq_ro_way_div"]
    D0 --> RO["read_oprand_way_div"]
    RO --> D1["dff_ro_fu_div"]
    D1 --> FU["fu_div：识别操作、保存prd和年龄、恢复过滤"]
    FU <-->|"req_valid/ready；resp_valid/ready/result"| UNIT["rv32m_div_unit：符号处理、逐位除法、结果输出"]
    FU --> WB["dff_fu_div_wb"]
    WB --> ROB["ROB与广播唤醒连线"]
    FU -.->|"ctrl_stall_req：忙时暂停除法通路"| D0
    FU -.-> D1
    FU -.-> RO
    FU -.->|"经顶层取反得到fu_ready"| Q
```

普通 restore 对 fu_div 保存的在途指令做年龄过滤，不直接 flush 内部除法器；ctrl_clear 才接到 rv32m_div_unit.flush_i。内部除法器普通操作执行 XLEN 轮，除零和有符号溢出走特殊结果路径。
