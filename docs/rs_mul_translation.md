# 乘法保留站 Verilog 版本

编辑文件：`D:/zz/mysuperscaler/rtl/utils/rs_mul_queue.v`。

参考文件：`D:/zz/superscalercore/vsrc/utils/rs_mul_queue.sv`。

本次按用户要求，把与 LSU 相同或相近的部分全部补齐；乘法特有的类型筛选和候选判断也直接按参考填写，所以模块内没有 TODO。年龄仲裁器复用现有 `rtl/utils/age_matrix_arbiter.v`，没有复制第二个仲裁器。

## 对应关系

保留参考的 11 个参数、23 个端口、原有内部信号顺序、两个函数、三个连续赋值、11 个过程块和仲裁器实例位置。分支、循环和赋值顺序均保持；新增字段偏移定义、函数 include、局部 integer 声明和过程块名称用于适配 Verilog。

| 原 SystemVerilog | 当前 Verilog |
|---|---|
| `import config_pkg::*`、包作用域参数 | 现有 `.vh` 头文件与宏 |
| `logic` | 按驱动方式区分 `reg`、`wire` |
| `always_comb`、`always_ff` | `always @*`、原时钟/复位敏感列表 |
| `unique case` | `case`，原分支和优先级保持 |
| `for (int i=...; ...; i++)` | 命名块内声明 `integer i`，循环使用 `i=i+1` |
| `rs_entry_t` | 与现有 LSU 相同的 `RS_ENTRY_WIDTH` 位向量 |
| `disp_entry_i[i]` | `disp_entry_i[i*RS_ENTRY_WIDTH +: RS_ENTRY_WIDTH]` |
| 结构体字段 | 同一字段在位向量中的偏移选择 |
| 多路打包广播总线 | 展开为单根总线，每路按原编号取片段 |
| `COUNT_W'(1)` | `1'b1`，计数器保存位宽不变 |
| `ENTRY_IDX_W'(j)` | 赋到原位宽的 `alloc_idx[i]`，保留有效队列编号 |
| `'0`、`'1` | `0`、对应位宽的全 1 重复拼接 |

原写法中 `rs_full_o = (free_cnt < PORT_WIDTH)`、未使用的需求计数、状态机转移条件、写回与提前唤醒的覆盖顺序全部保留。没有加入 LSU 的访存顺序约束。

## 在已有 Vivado 工程中加入

在当前工程 Tcl Console 执行：

```tcl
source D:/zz/mysuperscaler/scripts/add_rs_mul.tcl
```

脚本添加 MUL 源文件和共享依赖，补齐 include 路径，保留当前顶层模块，刷新编译顺序。重复执行不会重复加入文件。成功时输出 `MUL_HIERARCHY_REFRESH_PASS`。

本次没有改动正在编辑的 LSU 或共享仲裁器，也没有把 MUL 实例连接到 CPU 顶层。加入后可在 Sources 中查找 `rs_mul_queue`；尚未实例化的模块不会出现在现有 `if_stage` 的子层次下。

## 验证

运行 `scripts/check_rs_mul.ps1`：交付 RTL 使用普通 Verilog 编译模式，原参考及测试平台使用 SystemVerilog 模式。参考副本只改模块名和依赖模块名，原参考文件未修改。

三组参数各比较 600 拍：

| 派发路数 | 队列项数 | 就绪向量位数 |
|---:|---:|---:|
| 2 | 8 | 3 |
| 4 | 8 | 3 |
| 2 | 4 | 1 |

检查模块输出、队列内容、分配位置、状态和源就绪向量，覆盖多路分配、类型筛选、未就绪入队、写回、提前唤醒、发射、失败重试、暂停、flush、walk 及年龄编号回绕。结果为 `RS_MUL_REFERENCE_COMPARE_PASS`。

另在独立内存工程中验证添加脚本，重复加载后源文件唯一、顶层保持、文件类型为 Verilog、层次刷新成功：`MUL_PROJECT_REGISTRATION_PASS`。
