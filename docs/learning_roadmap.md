# 复现路线

参考工程：`D:/zz/superscalercore`，锁步 3.2 的 `vpackage` 和 `vsrc`。
自己的实现：`D:/zz/mysuperscaler/rtl`。模块名和文件名沿用参考项目；设计源使用 Verilog `.v`，测试平台可以用 SystemVerilog `.sv`。

目前 `rtl` 和 `sim` 是空目录，所有 RTL 与测试平台由你自己编写。模块和文件可以沿用参考项目命名；每做完一个模块，再补充它的定向测试。

1. 前端：`pc_reg` → `ifq` → `id_stage` / `rv32i_decoder`。先支持顺序取指，再加入预测。
2. 先用简单整数流水线跑通 `ADD/ADDI/LUI` 的译码、执行和写回。
3. 重命名：`rat`、`freelist`，覆盖组内 RAW/WAW 和旧映射保存。
4. 顺序记录与退休：`rob_fifo`、`rob`、`retire_ctrl`；核对顺序号与物理标签区别。
5. 发射：`issue_cluster`、各 `rs_*_queue`、年龄仲裁、唤醒、`read_oprand` 和旁路。
6. 访存：`fu_mem`、`store_buffer`、Load/Store 冲突及前递。
7. 乘除法：`fu_mul`、`fu_div` 及内部计算模块。
8. 分支预测、BIQ、ROB walk、RAT 恢复和错误路径写回屏蔽。
9. CSR/CLINT 与精确异常。
10. 在单核指令流验证后，再实现双核比较、比较后提交、MMIO 对齐及锁步恢复。

3.2 参考版的 `core_cpu` 本身含锁步接口。写自己的单核时，应明确设计自己的提交接口；不要把外部比较许可悬空后就期待参考核心正常运行。

纯 Verilog 没有 SystemVerilog 的 `package`、`struct` 和 `logic`。复现时可以用 `parameter/localparam`、`.vh` 头文件、`wire/reg` 和明确的端口代替。信号含义与数据宽度要保持一致。
