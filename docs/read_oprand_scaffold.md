# read_oprand 练习框架

直接编辑你已在 Vivado 新建并加入工程的文件：

`D:/zz/mysuperscaler/build/vivado/mysuperscaler.srcs/sources_1/new/read_oprand.v`

参考：`D:/zz/superscalercore/vsrc/core/read_oprand.sv`。

没有另外创建同名模块，也不用重新 Add Sources。保留你新建文件的 Vivado 文件头和 timescale；模块正文按参考转换为 Verilog。

## 已提供的部分

- 原来的两个参数、全部端口及内部信号，声明顺序保持。
- 结构体展开成现有 `RS_PAYLOAD_RAM_WIDTH` 位向量，使用现有头文件。
- 所有组合代码块、条件、循环及旁路覆盖顺序。
- 输出直连、输入控制信息传递和两路 ROB 查询地址。
- 就绪判断的默认值、不需要源操作数时的处理，以及数据默认值。
- 既有 `fifoid_functions.vh` 中的年龄比较函数。

参考模块的 8 个过程块都是组合逻辑，没有状态寄存器、没有复位分支。保留 `clk`、`rst` 端口，不增加原项目没有的时序或复位行为。

## 留给你填写的核心

文件中有 15 个 TODO，每个标明原参考文件行号和赋值目标：

| 代码块 | 原参考行号 | 待完成内容 |
|---|---|---|
| `proc_4` | 89、94、98 | 源1匹配两组写回旁路或 ROB 就绪时的就绪状态 |
| `proc_5` | 110、115、119 | 源2对应的就绪状态 |
| `proc_6` | 129、133、138 | 源1从 ROB、wb0、wb1 选择数据 |
| `proc_7` | 146、150、155 | 源2从 ROB、wb0、wb1 选择数据 |
| `proc_8` | 161、162、163 | 生成执行有效、响应有效、响应成功信号 |

TODO 替代原位置的赋值语句，其外围条件已经写好。请在 TODO 位置写入赋值，不要把后面的旁路判断改成互斥分支；原代码后面的匹配赋值可以覆盖前面的数据选择。

## 总线取通道

普通 Verilog 中，原来的多路打包数组展开成一根总线。第 0 路仍放低位，通道排列不变。

| 原 SV 访问 | Verilog 访问 |
|---|---|
| `rob_rdata[n]` | ``rob_rdata[n*`DATA_WIDTH +: `DATA_WIDTH]`` |
| `wb0_data[i]` | ``wb0_data[i*`DATA_WIDTH +: `DATA_WIDTH]`` |
| `wb1_data[i]` | ``wb1_data[i*`DATA_WIDTH +: `DATA_WIDTH]`` |
| `wb0_prd[i]` | ``wb0_prd[i*`PRD_WIDTH +: `PRD_WIDTH]`` |
| `wb1_prd[i]` | ``wb1_prd[i*`PRD_WIDTH +: `PRD_WIDTH]`` |
| `wb0_fifonum[i]` | ``wb0_fifonum[i*(`PRD_WIDTH+1) +: (`PRD_WIDTH+1)]`` |
| `wb1_fifonum[i]` | ``wb1_fifonum[i*(`PRD_WIDTH+1) +: (`PRD_WIDTH+1)]`` |

当前宏配置下，每个数据通道 32 位，物理寄存器编号通道 6 位，带回绕信息的年龄编号通道 7 位。`rob_ready`、`wb0_valid` 等本来就是每通道一位的向量，继续按 `[i]` 访问。

## 检查

运行 `scripts/check_read_oprand.ps1` 做普通 Verilog 语法编译。

这是未完成的练习框架，不能当作功能实现使用。最后一个组合块目前只有 TODO，编译器可能提示空块或没有敏感信号；填完相应赋值后再做功能验证。
