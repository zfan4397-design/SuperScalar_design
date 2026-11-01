# Store Buffer 和 ARF

编辑文件：

- `D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/store_buffer.v`
- `D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/arf.v`

两者按参考模块转换成普通 Verilog，保留参数、端口、内部信号、过程和条件顺序。不会覆盖已有 retire_ctrl 或其他练习文件。

## Store Buffer 框架

已提供参数、全部端口、数组、指针声明，stbfid_gt 与模块内年龄函数，原有判断和循环，复位，数据/地址/掩码/编号/年龄保存，位图寄存器更新，环形扫描连线，退休信息读出和写出数据直连。

14处核心 TODO：

| 编号 | 要填写的逻辑 |
|---|---|
| SB01–SB02 | 满判断、跳过尾部空洞 |
| SB03–SB05 | 三个指针在各自条件下的推进 |
| SB06–SB08 | 写出释放、年龄恢复撤销、新项置有效 |
| SB09 | 有效且完整SID匹配后，接受比较确认 |
| SB10 | clear时保留已比较确认的有效项 |
| SB11 | 本拍store接受指示 |
| SB12–SB13 | 按字节转发数据和设置命中掩码 |
| SB14 | 队首写出使能 |

每处标注原参考源码行号和赋值目标。SB01、SB02在连续赋值位置，需要填写 assign；SB03–SB05在时序块中，用非阻塞赋值；其余在组合块中，用阻塞赋值。

所有端口保持原顺序，多路字段改成扁平总线。单个SID宽度为 `STBF_WIDTH+1`：

```verilog
// 通道i的完整SID（当前6位）
cmp_stbf_id[i*(`STBF_WIDTH+1) +: (`STBF_WIDTH+1)]
// 通道i的SID低位数组下标（当前5位）
cmp_stbf_id[i*(`STBF_WIDTH+1) +: `STBF_WIDTH]
```

idx_vec的SV定宽转换在Verilog中由赋值目标的位宽截取实现，低STBF_WIDTH位继续用于访问数组。原参考没有数据数组复位，框架也不增加；有效位、确认位和三个指针保留原来的高电平异步复位。

框架故意不完整，未填项可能没有驱动或形成不完整组合赋值。只做语法检查不表示它已经具备功能。

原参考中 tail_ptr 与 retire_ptr 同条件推进、ctrl_stall 下的位图更新条件、未使用的 dcache_re/dcache_busy/dcache_wdone 等均原样保留；之前讨论的参考逻辑问题没有在语言转换时擅自改变。

## 完整 ARF

ARF保留原参考全部逻辑：32个架构寄存器，过滤x0，多退休端口同地址时低编号端口优先，高电平异步复位。

注意：原参考明确采用低编号端口优先；例如通道0和1都写x5，保留通道0。本次是严格参考转换，没有把它改成高编号优先。若退休端口从老到年轻排列，这一策略与“年轻指令的结果应成为最终架构值”的需求需要单独核对。

现有ARF接口只有退休写入，没有供执行侧读取的端口；执行侧数据路径仍由ROB和写回旁路提供。

## Vivado

脚本把两文件注册到现有 sources_1，保留现有顶层，不自动实例化：

```tcl
source D:/zz/mysuperscaler/scripts/add_storage_modules.tcl
```

语法检查：`scripts/check_storage_modules.ps1`。

## 本次验证

- 两个文件已通过普通 Verilog 语法编译。
- ARF 的 5 个端口、2 个过程块，以及 Store Buffer 的 37 个端口、12 个过程块，已核对声明顺序、条件顺序和赋值位置；端口宽度在 PORT_WIDTH=1/2/4 下均与原参考一致。
- `scripts/check_arf.ps1` 同时对照原参考和独立寄存器模型，双端口、四端口各运行 200 拍，覆盖不写、写 x0、同地址冲突、独立通道写入和时钟沿之间的异步复位。结果为 `ARF_REFERENCE_AND_MODEL_PASS`。
- 两个源文件已加入现有 Vivado 工程并刷新层次；顶层保持不变。Store Buffer 只验证框架语法和结构，核心 TODO 尚未填写，没有宣称其功能完整。
