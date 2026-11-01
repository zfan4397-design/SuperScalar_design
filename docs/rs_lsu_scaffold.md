# rs_lsu_queue Verilog 练习骨架

当前 Vivado 实际编辑的 LSU 文件是 `build/vivado/mysuperscaler.srcs/sources_1/new/rs_lsu_queue.v`。年龄仲裁器单独位于 `rtl/utils/age_matrix_arbiter.v`，在这个独立文件中填写其 TODO。原先临时附在 LSU 末尾的重复仲裁器已去除，LSU 中只保留原位置的仲裁器实例。

最初的骨架仍位于 `rtl/utils/rs_lsu_queue.v`，作为对照副本；它对应原文件 `D:/zz/superscalercore/vsrc/utils/rs_lsu_queue.sv`。不要将两份同名模块同时添加到工程。

代码严格沿原参数、端口、声明、函数、连续赋值、always 块、仲裁器实例和时序更新的顺序排列。每处 `TODO [rs_lsu_queue.sv:起始行-结束行]` 对应原代码的一条核心赋值；多行原赋值合为一个空位，共 54 处。条件、循环边界和分支顺序保留，可对照逐句填写。

## 已准备

- 所有参数及其原默认值，包括原本未使用的参数。
- 全部端口、声明、原始 `rs_entry_t` 打包位序。
- 原低有效异步复位、状态寄存器、全局 flush 的有效位/空闲位清除。
- 原各组合块的默认初始化和循环框架。
- 反馈编号等直接接线、ready 临时值的默认继承及最终寄存器保存。
- `fifoid_gt`、`fifoid_lt` 的模块局部 Verilog 函数，位于 `vpackage/fifoid_functions.vh`，行为对应原 config_pkg 函数。

## 需要填写

`shift_ready` 的移位赋值、不同 FU 的唤醒 mask、状态转移、分派过滤、数量统计和满判断、空槽分配、源就绪条件、年龄依赖判断、发射条件与输出、反馈处理、walk 撤销、入队和 issued 更新、分派/写回/提前唤醒产生的 ready 更新。

原文件的 `age_matrix_arbiter` 实例原位置保留，它调用独立的 `rtl/utils/age_matrix_arbiter.v`，两者分别填写。仲裁器的核心也留为 TODO，需要同时完成它才能得到完整功能。工程应分别引用 LSU 和仲裁器两个文件。

骨架保留原组合默认值，但这不代表模块已完成：有些信号在填完之前没有驱动，部分函数当前只返回默认值。语法编译通过不能用来判断调度功能正确。

## Verilog 必要转换

- 包引用改用现有 `.vh` 宏，结构体改用打包向量；原全局字段宽度使用既有 `payload_defs.vh`，没有重新定义字段位序。
- 多通道端口、`age_vec` 展平；内部 `entry_q`、ready 数组和 `alloc_idx` 保留数组下标访问。
- `logic` 根据驱动方式改为 wire/reg；`always_comb` 改为 `always @*`，`always_ff` 改为普通时序 always。前者没有 SV 时间零强制执行保证。
- `for (int ...)` 的变量提前声明在命名过程块内；`++` 改为 `= ... + 1`。
- `unique case` 改为 `case`，保留全部分支，但不再提供 unique 的仿真检查。
- 整数索引的尺寸转换改用 Verilog 赋值截断或上下文已保证范围的整数比较；填写时沿用原阻塞/非阻塞赋值类型。
- `$clog2` 使用 Verilog-2005 的支持，Vivado 可以直接编译，无需 `--sv`。

原注释中的局部历史说明以英文位置注释替代，避免 Vivado 编码往返导致乱码。参考的未使用信号、宽度约定等没有重新设计。

## 常用字段如何访问

```verilog
// 原：disp_entry_i[k]，整个分派条目
disp_entry_i[k*`RS_ENTRY_WIDTH +: `RS_ENTRY_WIDTH]

// 原：disp_entry_i[k].payload_ram.futype
disp_entry_i[k*`RS_ENTRY_WIDTH + RS_FUTYPE_LSB +: `FU_TYPE_WIDTH]

// 原：entry_q[j].v
entry_q[j][`RS_ENTRY_V_LSB]

// 原：entry_q[j].control.rob_idx
entry_q[j][RS_AGE_LSB +: `AGE_W]

// 原：entry_q[j].control.prs1 / prs1_v
entry_q[j][RS_PRS1_LSB +: `PRF_IDX_W]
entry_q[j][RS_PRS1_V_BIT]

// 原：entry_q[j].control.prs2 / prs2_v
entry_q[j][RS_PRS2_LSB +: `PRF_IDX_W]
entry_q[j][RS_PRS2_V_BIT]

// 原：entry_q[j].payload_ram.mem_w
entry_q[j][RS_MEM_W_BIT]

// 原：wb_prd_i[p] / is_prd_i[p]
wb_prd_i[p*PRF_IDX_W +: PRF_IDX_W]
is_prd_i[p*PRF_IDX_W +: PRF_IDX_W]

// 原：age_vec[j]，展平后
age_vec[j*AGE_W +: AGE_W]
```

注意区分本模块参数 `PRF_IDX_W` / `AGE_W` 与反引号宏：原结构体的字段宽度来自 config_pkg 的全局定义，因此字段切片使用相应宏；WB 和广播端口宽度依旧来自模块参数，与原 SV 一致。`alloc_idx[i]`、`prs1_ready_q[j][0]` 等内部数组访问不需展平。

`issue_state_ok` 为连续赋值目标，填写完整 `assign ... = ...;`。其余 TODO 在对应过程块中填写，组合块用 `=`，时序保存用 `<=`。

## 对照原代码时的两点

- 原 full 判断虽然有按需求统计的注释，实际赋值使用 `free_cnt < PORT_WIDTH`。骨架留出原位置，不替换成需求计数。
- 原发射策略禁止绕过更老的未发射访存指令，`older_unissued_store_vec` 仍保留原有声明和计算位置；不把它重新设计成 load bypass。

## 加入 Vivado 与检查

在已打开的 Vivado 工程的 Tcl Console 执行：

```tcl
source D:/zz/mysuperscaler/scripts/add_rs_lsu.tcl
```

当前 LSU 文件已被工程引用；执行上面的脚本可将独立仲裁器及函数头文件加入当前打开的工程。已有 Vivado 编辑器页签若提示外部文件修改，应选择重新加载。脚本优先选择你新建的 LSU 文件，避免添加 `rtl/utils` 中同名 LSU 副本；无需重建工程。由于还没有上层实例化，可能显示在独立或未引用模块区域。

普通 Verilog 编译检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_rs_lsu.ps1
```

检查脚本优先编译当前 Vivado 使用的 LSU 文件，并一起编译独立仲裁器，以免只检查了 `rtl/utils` 下的旧 LSU 副本。
