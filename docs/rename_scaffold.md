# RAT / freelist Verilog 练习骨架

文件：

- `rtl/utils/rat.v`，对应 `D:/zz/superscalercore/vsrc/utils/rat.sv`。
- `rtl/utils/freelist.v`，对应 `D:/zz/superscalercore/vsrc/utils/freelist.sv`。

这两个文件最初作为练习骨架建立。当前核心逻辑已经由你填写，并经过本次检查修正；代码中的 `FIX R1`、`FIX R2` 标明修正位置，详见 [rename_review.md](rename_review.md)。下面保留原骨架分工和 Verilog 转换说明，供对照阅读。

## 已准备的内容

- 原模块名、参数默认值、全部端口及其排列顺序，包括暂未使用的接口。
- 原信号名、内部数组、状态宽度、状态分支、条件优先级、generate/for 循环及代码顺序。
- 原复位方式和复位值：RAT 两张表的 `xi -> pi`；freelist 初始编号、有效位、四个指针和统计计数器。
- RAT 的 clear 拷贝与读表选择位清零、状态寄存器、原有组合默认赋值、`have_inst_o` 直连。
- 连续有效位检查函数及原版关闭错误检查的写法。
- freelist 计数辅助函数、有效位下一状态的默认继承、原调试计数器。
- 参数复用现有 `vpackage/config_pkg.vh` 等头文件，没有重定义或修改原参数。

## 原先留空、目前已填写的内容

RAT：状态转移结果、控制输出、正常/walk 写请求、组内 WAW、源/旧映射前递、写通道选择、映射及选择位的运行期更新、提交/锁步回滚更新。

freelist：回退数量和地址、运行期指针推进/恢复、回收写请求、分配/回收地址、候选输出、有效位消费和回收、clear 恢复、提交/核内退休/锁步恢复状态更新。

保留的条件与循环就是参考实现的框架，本次修正保持原控制流程。源于接口展平的逐位/逐通道错误已修正；参考本身的控制约定见检查报告。

## 必要的 Verilog 语法变化

1. `import` / package 常量改为已有 `.vh` 宏，例如 `` `PRD_WIDTH ``、`` `RAT_NORMAL ``。
2. `logic` 按驱动方式改为 `wire` 或 `reg`；枚举状态改为 `reg [2:0]`。
3. `always_comb` 改为 `always @*`，`always_ff` 改为普通时序 `always`。后者不再提供 SystemVerilog 的单驱动检查；前者没有 `always_comb` 的时间零自动执行保证。
4. 多维打包端口展平为一维向量，通道 0 仍位于最低位。模块内部的存储数组不展平。
5. `for (int i=...)` 改为在命名过程块内先声明 `integer i`，再 `for (i=...)`。generate 块增加名称。
6. 函数用函数名返回结果；`$countones` 用局部 `countones` 函数替代，只统计确定为 1 的位。`$clog2` 保留，使用 Verilog-2005（Vivado 支持）。
7. 复位中的 SV 位宽强制转换改为由目标位宽截断；原复位表达式的低位结果相同。

### 展平端口如何取某个通道

```verilog
// 参考 SV：rd[i]
rd[i*5 +: 5]

// 参考 SV：freelist_prd[i]
freelist_prd[i*`PRD_WIDTH +: `PRD_WIDTH]

// 参考 SV：prd[i]（赋值左边也一样）
prd[i*`PRD_WIDTH +: `PRD_WIDTH]
```

例如 `PRD_WIDTH=6` 时，通道 0 是 `[5:0]`，通道 1 是 `[11:6]`，拼接顺序为 `{通道1, 通道0}`。

内部数组仍按原方式索引：

```verilog
rat_mem[i]
rat_we_wprd[weidx]
freelist_mem[tail_addr[i]]
```

一位通道标志也不需要切片转换，例如 `have_inst[i]`、`rdv[i]`、`wk_valid[i]`。

对于按 `assign` 驱动的三个 freelist TODO（参考 70–72 行），填写完整的 `assign ... = ...;`。组合过程块使用阻塞赋值 `=`，时序过程块使用非阻塞赋值 `<=`，与原参考写法一致。

## 检查方式

现有创建工程脚本会扫描 `rtl`，并设置 `vpackage` 头文件目录，无需修改脚本。

只检查这两个骨架的 Verilog 编译：

```powershell
New-Item -ItemType Directory -Force build/rename-scaffold-check | Out-Null
Push-Location build/rename-scaffold-check
& 'D:\Vivado\2023.2\bin\xvlog.bat' --work scaffold `
    -i D:/zz/mysuperscaler/vpackage `
    D:/zz/mysuperscaler/rtl/utils/rat.v `
    D:/zz/mysuperscaler/rtl/utils/freelist.v
Pop-Location
```

这里没有使用 `--sv`。编译只检查语法；当前功能对照回归使用 `scripts/check_rename.ps1`。
