# retire_ctrl 练习框架

编辑的唯一模块文件：

`D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/retire_ctrl.v`

参考：`D:/zz/superscalercore/vsrc/core/retire_ctrl.sv`。

沿用原来的参数、端口、内部信号、generate、过程块、条件分支及语句顺序。仅进行普通 Verilog 所需的转换：头文件宏代替 package，wire/reg 代替 logic，状态向量代替枚举，always @* / always @(...) 代替 SV 过程，循环变量移到命名块开头，多通道端口展开为向量。第 0 路仍位于最低位。

## 已提供

- 全部接口、内部信号与现有 config_pkg.vh、retire_pkg.vh 定义。
- 原来的三态状态机转移，保留参考拼写 EXCECPT_HANDLE。
- currState 的高电平异步复位和正常更新。
- 原有默认赋值、无效分支的清零，以及所有外围判断与循环。
- grant_tmp 直连，以及 Store Buffer ID、ARF 地址和数据的直连。
- 默认 PC/nxtPC 选择队首 PC 的原有行为。

## 留给你填写的 18 处核心

每处 TODO 都标有 RT 编号、原参考文件行号及赋值目标。

| TODO | 原参考行号 | 任务 |
|---|---|---|
| RT01 | 48 | 判断是否存在阻止退休的异常 |
| RT02–RT05 | 56、57、60、66 | grant 与 ready_msk 的首通道及后续连续前缀 |
| RT06 | 79–82 | 异常白名单与外部许可组成 can_retire |
| RT07–RT08 | 91、93 | Store Buffer 退休使能、ARF 写使能 |
| RT09–RT10 | 103、107 | 第一个停止位置的异常码 |
| RT11–RT16 | 163、165、167、172、177、179 | 各状态下最终 rob_grant 与异常请求 |
| RT17–RT18 | 192、193 | 按实际退休通道更新 PC 和后继 PC |

条件与循环已经保留；在 TODO 原位置补赋值，不需要自行另建 always 块。RT01 是连续赋值位置，要填写 assign；其余是组合过程中的阻塞赋值。

这不是完整功能实现。未填写时，一些核心信号没有驱动，一些块可能没有敏感信号；不要通过额外添加默认值、复位或伪实现消除这些未完成现象。完成 TODO 后再进行功能验证。

## 展开后的通道访问

| 原 SV | 普通 Verilog |
|---|---|
| rob_exception[i] | rob_exception[i*`EXCPT_WIDTH +: `EXCPT_WIDTH] |
| rob_wrtype[i] | rob_wrtype[i*`TYPE_WIDTH +: `TYPE_WIDTH] |
| rob_pc[i] | rob_pc[i*`PC_WIDTH +: `PC_WIDTH] |
| rob_brdest[i] | rob_brdest[i*`DATA_WIDTH +: `DATA_WIDTH] |
| rob_stbfid[i] | rob_stbfid[i*(`STBF_WIDTH+1) +: (`STBF_WIDTH+1)] |

rob_grant、rob_ready、core_retire_grant 等每路一位的信号继续用 [i]。当前配置 PORT_WIDTH=2 时，rob_pc 是 64 位，rob_rd 是 10 位，rob_stbfid 是 12 位。

## Vivado 与检查

模块添加到现有工程的 sources_1，原顶层保持不变。它尚未实例化到顶层，Vivado 层次视图可能把它列为独立模块。

若当前已打开的 GUI 尚未看到文件，可在 Tcl Console 执行：

```tcl
source D:/zz/mysuperscaler/scripts/add_retire_ctrl.tcl
```

运行 `scripts/check_retire_ctrl.ps1` 可做普通 Verilog 语法编译；这不表示未完成框架已具备正确的退休功能。
