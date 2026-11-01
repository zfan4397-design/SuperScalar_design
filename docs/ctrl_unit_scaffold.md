# ctrl_unit 练习框架

编辑文件：`D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/ctrl_unit.v`。

参考：`D:/zz/superscalercore/vsrc/core/ctrl_unit.sv`。

按普通Verilog转换，保留两个参数、全部端口与信号、六个过程块、条件分支及赋值位置的顺序，复用已有config_pkg.vh和ctrl_pkg.vh。没有修改其他已填写模块。

## 已写好

- 全部接口、位宽、六种状态宏及内部信号声明。
- currState、prevState、普通恢复边界、锁步PC/边界的高电平异步复位与保存。
- 原来的完整状态转移和优先级、输出默认值、所有外围条件。
- lockstep_restore_flnum、恢复请求与结束通知等原有直连。

## 留给你写的19组核心

每组标有CU编号、原参考行号范围和应填写的目标信号。一组可以包含原来连续的多条赋值，按注释所列顺序填写。

| TODO | 内容 |
|---|---|
| CU01–CU02 | 恢复PC选择、进入锁步恢复的一拍脉冲 |
| CU03–CU04 | NORMAL中的边界保存使能、普通恢复输出 |
| CU05–CU06 | EXCEPT完成与等待时的输出 |
| CU07–CU11 | RESTORE中异常结束、新/旧边界选择、保存使能和持续恢复 |
| CU12 | ERROR中的退休保持 |
| CU13–CU14 | 锁步清理、锁步恢复的控制输出 |
| CU15–CU18 | ICache、RAT、ROB、IQ暂停请求的输出范围 |
| CU19 | 访存通路暂停输出 |

CU01和CU02在连续赋值位置，需要写assign；其余在组合过程块内，使用阻塞赋值。状态寄存器与恢复信息保存块已经完成，不需要另加always块或复位。

框架并未完成功能，可能存在未驱动的核心输出。语法通过不代表控制行为正确。原代码中sig_restore、ctrl_restore_sig、ctrl_restore的不同作用，以及访存暂停位于stall_kill判断之外的结构都保留。

当前参考顶层中的ctrl_unit.ctrl_except_resp悬空，退休使用的响应来自CLINT；框架不改变这些参考接口含义。

## Vivado

文件添加到现有sources_1，不改变当前顶层，也不自动实例化。若已打开的GUI未显示，在Tcl Console执行：

```tcl
source D:/zz/mysuperscaler/scripts/add_ctrl_unit.tcl
```

语法检查：`scripts/check_ctrl_unit.ps1`。

## 本次检查结果

- 普通Verilog语法编译通过：CTRL_UNIT_SCAFFOLD_COMPILE_PASS。
- 47个端口、6个过程块、19组TODO，原条件与赋值顺序核对通过；两组通路参数分别取(1,1)、(2,1)、(4,2)时端口宽度与参考一致。
- 已加入现有Vivado工程并成功刷新层次，原顶层保持不变。核心仍待填写，没有将框架当作完整功能实现验证。
