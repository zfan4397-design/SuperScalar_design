# Verilog 公共定义

来源是 `D:/zz/superscalercore/vpackage`，固定为锁步 3.2 提交 `8af31705bf8e6e6571a6361e0a0ab53e25656cb0`。这部分只定义常量和打包位段，不实现 CPU 模块。

自己的模块使用 `include "cpu_defs.vh"`（include 前加 Verilog 反引号）。Vivado 工程已经把 `vpackage` 加入头文件搜索路径。用宏时也要在名称前加反引号，例如 `` `PC_WIDTH ``、`` `ALU_ADD ``。

| 头文件 | 对应内容 |
|---|---|
| `config_pkg.vh` | 位宽、指令操作枚举、异常、CSR、特权级和地址范围 |
| `structure_pkg.vh` | 取指/派发/退休宽度、执行单元索引与读写口数量 |
| `ctrl_pkg.vh` | 全局控制状态，包括两个锁步恢复状态 |
| `rob_pkg.vh`、`rat_pkg.vh` | ROB/RAT 的五个局部状态 |
| `retire_pkg.vh`、`issue_pkg.vh` | 退休状态和发射状态/执行单元枚举 |
| `payload_defs.vh` | `rs_payload_ram`、`rob_entry_t`、`rs_control_t`、`rs_entry_t` 的向量宽度和字段位段 |
| `cpu_defs.vh` | 汇总上述所有头文件 |

原项目的 `package` 作用域在纯 Verilog 中不存在。全局常量保持原名称和数值；多个包中重名的状态增加包名前缀，例如 `rob_pkg::NORMAL` 对应 `` `ROB_NORMAL ``，`ctrl_pkg::NORMAL` 对应 `` `CTRL_NORMAL ``，`retire_pkg::NORMAL` 对应 `` `RT_NORMAL ``。这只是区分命名空间，不改变状态编码。保留原项目的 `EXCECPT_HANDLE` 拼写。

`struct packed` 改为向量位段宏。声明顺序与参考项目一致：第一项位于最高位，最后一项位于最低位。例如 `ROB_ENTRY_PRD_RANGE` 表示整个 ROB 内容向量中的 `prd` 字段；`ROB_ENTRY_WIDTH` 表示总位宽。你可以自行选择使用完整向量，或分开声明每个字段。

当前参数下：`RS_PAYLOAD_RAM_WIDTH=164`、`ROB_ENTRY_WIDTH=158`、`RS_CONTROL_WIDTH=28`、`RS_ENTRY_WIDTH=193`。字段位置用宏表达式推导，修改公共位宽后会相应变化。

3.2 默认保留：`PORT_WIDTH=2`、`IN_WIDTH=8`、`PRD_WIDTH=6`、`ROB_DEPTH=64`、`STBF_WIDTH=5`、`EXCPT_WIDTH=5`。不要把 `IN_WIDTH` 当成发射宽度。MMIO 与锁步常量也保留了，是否在自己的 CPU 中使用由你决定。

参考包中的 `fifoid_gt/fifoid_lt` 是年龄比较函数，不是常量定义，因此没有代写；其他模块内部参数也没有搬入公共定义。

VS Code 任务“核对公共宏定义”调用 `scripts/check_definitions.ps1`，逐项对比源包中的常量值、枚举和 packed 字段位置。这个检查不产生 HDL 模块或测试平台。
