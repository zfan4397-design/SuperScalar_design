# CLINT 练习框架

目标工程文件：D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/clint.v

参考：D:/zz/superscalercore/vsrc/utils/clint.sv。保留全部 20 个端口的方向、顺序、符号位宽；全部常量、辅助函数/task 顺序、状态编码、4 个过程块、条件分支、状态转移、默认赋值、复位与保存/读取过程均按参考排列。

仅进行普通 Verilog 所需转换：package import 改为现有 config_pkg.vh；常量引用加宏反引号；input/output logic 改为 wire/reg；内部 logic 改为 reg；枚举改为同名同值 localparam 和 5 位状态寄存器；always_comb/always_ff 改为 always @*/always @(...)；移除 unique；函数 return 改为函数名赋值；函数/task 端口改为旧式声明；无尺寸 '0 改为上下文截取的 0；局部 pending_async_nxt 声明前移至命名过程块开头。三个单行中断选择条件增加 begin/end 以容纳空的 TODO 分支。

## 留给你填写的核心

参数、地址、原因码映射、返回类别/权限辅助判断、原有外围条件、状态转移、CSR 地址/数据连线、复位和请求/CSR 保存代码已提供。原位置保留 30 处核心 TODO，每处标有参考行号。

| TODO | 参考行号 | 要填写的逻辑 |
|---|---|---|
| CL01 | 122 | assign the int_enabled function result from the global and source enables |
| CL02 | 133 | assign the mtvec_target function result for vectored interrupts |
| CL03 | 135 | assign the mtvec_target function result for direct entry |
| CL04 | 162-165 | restore MRET privilege and MSTATUS fields, in reference order |
| CL05 | 169-172 | restore SRET privilege and MSTATUS fields, in reference order |
| CL06 | 176-178 | restore URET privilege and MSTATUS fields, in reference order |
| CL07 | 256 | combine saved pending sources with current external interrupt sources |
| CL08 | 257 | detect whether the combined interrupt-source vector is nonzero |
| CL09 | 261 | select the external-interrupt source in this branch |
| CL10 | 262 | select the software-interrupt source in this branch |
| CL11 | 263 | select the timer-interrupt source in this branch |
| CL12 | 272-273 | generate completion and retirement permission for FAST_FLUSH |
| CL13 | 276-277 | generate completion and retirement permission for DONE_TRAP |
| CL14 | 280-281 | generate completion and retirement permission for RET_DONE |
| CL15 | 311 | choose the candidate EPC for the latched synchronous/asynchronous request |
| CL16 | 312 | choose and convert the synchronous/asynchronous MCAUSE |
| CL17 | 314-316 | save prior privilege and interrupt enable, then disable MIE for trap entry |
| CL18 | 349 | redirect after the CSR side-effect flush |
| CL19 | 378 | enable the early MEPC write only for the reference request class |
| CL20 | 405 | enable the late MEPC write only for the reference request class |
| CL21 | 408 | compute the trap handler target from the saved MTVEC and MCAUSE |
| CL22 | 446 | redirect to the EPC read by the return path |
| CL23 | 476 | accumulate new interrupt sources into the pending working value |
| CL24 | 479 | clear the source accepted by the interrupt-enable check |
| CL25 | 492 | set retirement permission for a CSR side-effect event |
| CL26 | 498 | set retirement permission for an illegal return instruction |
| CL27 | 501 | set retirement permission for a legal return instruction |
| CL28 | 506 | set retirement permission for an ordinary synchronous exception |
| CL29 | 516 | set retirement permission for an asynchronous interrupt |
| CL30 | 528 | set retirement permission after SRET fails the TSR check |

函数内的 TODO 用函数名赋值返回结果，不再写 SystemVerilog 的 return。组合块和 task 内使用阻塞赋值；allow_retire_q 等时序寄存器使用非阻塞赋值。请在 TODO 原位置填入，避免额外建立 always 块。

该文件有意不完整：未填写的函数结果/组合变量可能未赋值或保留默认值；不要用伪实现、额外默认值或改变条件来消除未完成现象。语法编译只证明普通 Verilog 语法可被解析，不代表核心功能完成。

严格转换保留参考行为：组合 IDLE 启动异步处理时检查实时 ext_int_flag_i 与 async_en，而请求锁存检查 async_req_any；普通同步异常不放行退休；异步 MEPC 写入位于 ST_DONE_TRAP，使用当时的 retire_ctrl_nxtpc。此次不顺带改动这些行为。

## Vivado

在现有工程 Tcl Console 执行：

    source D:/zz/mysuperscaler/scripts/add_clint.tcl

注册为 Verilog，沿用现有 vpackage include 路径并保持顶层。当前框架不自动实例化进顶层，Vivado 可能将其显示为独立模块。
