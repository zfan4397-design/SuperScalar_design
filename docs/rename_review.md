# RAT / freelist 检查与修正

本次以 `D:/zz/superscalercore/vsrc/utils/rat.sv`、`freelist.sv` 为行为基准，检查你填写后的 Verilog。代码中搜索 `FIX R1`、`FIX R2` 可定位修正位置。

## FIX R1：展平端口必须取完整通道

原 SV 的 `logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0]` 转为 Verilog 一维总线后，`bus[i]` 只取一个 bit，不能再表示第 i 个完整物理编号。

原写法：

```verilog
rat_we_wprd[weidx] = freelist_prd[weidx];
rat_we_waddr[weidx] = rd[weidx];
prs1[ridx] = rat_mem[rs1[ridx]];
freelist_head_wprd[fidx] = rt_pprd[fidx];
freelist_prd[ridx] = freelist_mem[tail_addr[ridx]];
```

对应修正：

```verilog
rat_we_wprd[weidx] = freelist_prd[weidx*`PRD_WIDTH +: `PRD_WIDTH];
rat_we_waddr[weidx] = rd[weidx*5 +: 5];
prs1[ridx*`PRD_WIDTH +: `PRD_WIDTH] = rat_mem[rs1[ridx*5 +: 5]];
freelist_head_wprd[fidx] = rt_pprd[fidx*`PRD_WIDTH +: `PRD_WIDTH];
freelist_prd[ridx*`PRD_WIDTH +: `PRD_WIDTH] = freelist_mem[tail_addr[ridx]];
```

影响包括：RAT 的源查询、新旧编号输出、正常与 walk 写请求、组内前递、提交和锁步回滚；freelist 的正常/walk 回收数据及候选编号输出。漏改会把编号截成 1 bit，或只给输出的一位赋值，甚至让不同通道写到同一输出位。

本次 RAT 中 19 行、freelist 中 3 行添加了此标记；一行可能包含多个需要修正的索引。

内部数组仍然使用 `rat_mem[i]`、`rat_we_wprd[i]`、`freelist_mem[i]`。一位有效标志仍然使用 `rdv[i]`、`wk_valid[i]` 等，不做整通道切片。

## FIX R2：WAW 分支写错了变量

你原来的正常 WAW 分支在取消较老通道写使能后，给 `rat_we_waddr[weidx]` 赋了 `rd[i]`。

参考代码该位置更新的是物理数据变量，现恢复为：

```verilog
rat_we_wr[weidx] = 1'b0;
rat_we_wprd[weidx] = freelist_prd[i*`PRD_WIDTH +: `PRD_WIDTH];
```

这里较老通道的写使能已经取消，所以错误的地址赋值通常不会独立造成最终表写错；修正用于恢复参考语句的对应关系。真正导致当前重命名数据错误的主要问题是 R1。

## 保留的参考行为

没有重排状态机、改变优先级、移除锁步接口，或修改参考工程源码。`signal_error=0`、原 `end if` 写法、CLEAR/RESTORE 的原控制方式均按参考保留；本次测试检验与参考行为的对应关系，不构成对整个 CPU 控制协议的证明。`ram_style="distribute"` 也保留参考拼写，实际存储推断应查看综合结果。

## 验证与复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_rename.ps1
```

测试在 `tests/rename/tb_rename_review.sv`，不自动加入你的日常 Vivado 仿真集。DUT 以普通 Verilog 编译；原参考模块和测试平台以 SystemVerilog 编译。参考模块只在 `build/rename_review/after_run` 中制作重命名副本，原目录不写入。

比较双通道和四通道，各模块各 600 个周期，共四个探针。检查组合输出、时钟沿之后的全部映射、有效位记录、freelist 编号内容和指针。前几个周期安排高位物理编号、同组 RAW/WAW、walk、clear 同拍提交、正常回收与 walk 同拍等场景，其余周期使用可复现的伪随机激励。随机流包含用于比较控制优先级的压力输入，并不保证每个输入序列都是一条真实软件指令流。

修改前快照位于 `build/rename_review/before/rat.v` 和 `freelist.v`。可运行 `scripts/check_rename.ps1 -Before` 对这些快照做同一组回归，预期报告不匹配。日志分别位于 `before_run` / `after_run`。

测试成功标志为 `RENAME_REVIEW_PASS`。若 XSim 在生成 C 文件阶段失败，需区分工具运行环境故障与 RTL 不匹配；不能把仅通过 xvlog 当成仿真通过。

本次结果：修改前快照在第 0 个测试周期的 `freelist_prd` 输出比较中失败（高位未驱动）；修正后四个探针全部通过，各 600 周期。另通过现有常量/字段位序检查（170 个常量、51 个打包字段）。
