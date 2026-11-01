# fu_mem 练习框架

主文件：`D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/fu_mem.v`。

配套流水寄存器：同目录 `dff_fu.v`，完整转换原参考的复位、暂停、年龄过滤和寄存器传递。已有的 `store_buffer.v` 直接复用，不覆盖其中已填写的核心内容。合编时仅以 `FIX V1` 将 entry_valid 声明移到首次使用之前，解决普通 Verilog 的声明顺序错误；原文件备份在 `build/fu_mem_scaffold_check/store_buffer.before_declaration_fix.v`。

保持参考项目的参数、端口、内部信号、实例、过程、条件和循环顺序。只做 Verilog 所需的结构体展开、数组展开、wire/reg、always 和宏转换。

## 已提供

- 全部端口、信号和结构体字段偏移，PORT_WIDTH默认2。
- 原来的操作数选择、默认值、外围条件和循环。
- store_buffer 与 dff_fu 全部连接，连接顺序保持原样。
- 地址、数据、ID等直连；store数据拆字节；正常异常码和默认宽度分支。
- dff_fu原来的高电平异步复位、clear、暂停、kill_in/kill_out和输出过滤。
- reg_we保留参考中的独立更新规则，不因指令恢复过滤而清除。

## 留给你填写的28处核心

| TODO | 内容 |
|---|---|
| FM01–FM04 | 有效地址、对齐地址、字节偏移、MMIO转交编码 |
| FM05 | MMIO地址分类；该位置填写连续assign赋值 |
| FM06 | store数据按字节使能过滤 |
| FM07–FM09 | store数据左移、掩码左移、普通store入队请求 |
| FM10–FM12 | 转发是否覆盖load需求、暂停请求、写完成限定 |
| FM13–FM16 | 读写选择分支内的读写使能 |
| FM17–FM18 | 根据保存的lmask，逐字节选择Buffer或内存数据 |
| FM19 | 合并数据按字节偏移右移 |
| FM20–FM24 | 字、半字、字节load结果，以及符号/零扩展 |
| FM25–FM27 | MMIO访问大小编码 |
| FM28 | 写回有效位 |

每处标注原参考行号和赋值目标。在原位置补全阻塞赋值；FM05为assign位置。没有新增伪实现或默认零值掩盖未完成的核心。

fu_mem本身是组合逻辑与子模块连接，参考中没有独立状态寄存器复位块；复位通过原端口传给store_buffer、dff_fu。不要再给组合输出加时序复位。

## 结构体与多通道字段

`payload_ram` 展开为现有 `RS_PAYLOAD_RAM_WIDTH` 位向量，使用 `payload_defs.vh`：

```verilog
// 原payload_ram.mem_wstrb
payload_ram[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE]
// 原payload_ram.mem_wstrb[memidx]
payload_ram[`RS_PAYLOAD_RAM_MEM_WSTRB_LSB + memidx]
// 原payload_ram.reg_wstrb
payload_ram[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE]
```

退休/比较SID每路 `STBF_WIDTH+1` 位；退休地址和数据每路DATA_WIDTH位。第0路放低位，顺序不变。

## 原参考行为

参考中的prd_v、dcache_rvalid未参与功能判断，svalid接回后未再使用；debug_pc的SV非恒定声明初始化改为Verilog initial中的一次赋值，保留一次初始化语义，没有改成持续跟随的连线。MMIO访问大小继续使用c1_reg_wstrb。之前讨论过的参考时序、Store Buffer暂停和MMIO store宽度问题没有在创建框架时擅自修改。

## Vivado

添加到现有工程的sources_1并保留原顶层。当前GUI若没有显示，可在Tcl Console运行：

```tcl
source D:/zz/mysuperscaler/scripts/add_fu_mem.tcl
```

普通Verilog语法检查：`scripts/check_fu_mem.ps1`。框架尚未完成功能，不能把语法通过等同于访存功能正确。

## 本次验证

- 现有store_buffer、完整dff_fu及fu_mem框架合并后，普通Verilog语法编译通过。
- fu_mem的38个端口、11个组合过程块，dff_fu的32个端口、4个过程块，已核对端口宽度、分支顺序、赋值位置及子模块连接顺序；PORT_WIDTH=1/2/4的展开宽度与参考一致。
- `scripts/check_dff_fu.ps1` 将配套流水寄存器与参考代码对比运行200拍，覆盖正常传递、暂停、clear、年龄过滤、时钟沿之间的异步复位，以及reg_we不随普通指令清空的行为，结果为 `DFF_FU_REFERENCE_COMPARE_PASS`。
- 已校验现有Store Buffer的核心内容未改变，仅执行标为FIX V1的entry_valid声明位置修复。
