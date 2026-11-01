# mysuperscaler

自己的超标量 CPU 复现工程。模块和 RTL 文件按参考项目命名，例如 `core_cpu.v`、`pc_reg.v`，不添加 `my_` 前缀。

## 环境

- 编辑器：VS Code，`D:/Microsoft VS Code`。
- 仿真、波形与综合：Vivado 2023.2，`D:/Vivado/2023.2`，使用自带 XSim。
- 参考代码：`D:/zz/superscalercore`，3.2 的 `vpackage` 和 `vsrc`。
- 自己的 RTL：`rtl/core`、`rtl/utils`；测试平台：`sim`。
- Verilog 公共定义：`vpackage/*.vh`，对应参考项目的 SystemVerilog 包；统一入口 `cpu_defs.vh`。
- 未选择开发板，也未加入引脚约束。Vivado 工程的 `xc7k70tfbv676-1` 只是临时工程/综合目标，沿用电脑上已有工程的器件设置，不代表已经选定开发板。

## 打开与运行

用 VS Code 打开 `superscaler.code-workspace`，同时查看自己的代码和参考代码。两者模块同名，但使用独立编译入口。

在 VS Code 中按 `Ctrl+Shift+P`，选择“任务: 运行任务”，可以运行：环境检查、核对公共宏定义、创建 Vivado 工程、运行 RTL 仿真、综合自己的 RTL、检查 3.2 参考核心编译、打开 Vivado。

也可以在本目录的 PowerShell 终端执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Action definitions-check
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Action sim
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Action synth
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Action open-vivado
```

生成的 Vivado 工程为 `build/vivado/mysuperscaler.xpr`。项目脚本会扫描 `rtl` 和 `sim`；新增源文件后重新运行“创建 Vivado 工程”或“运行 RTL 仿真”即可加入。工程生成文件放在 `build`，自己的源码不要放在其中。

## 代码由你自己编写

`rtl` 和 `sim` 目录为空，CPU RTL 与测试平台由你自己写。已经提供按参考项目转换的 Verilog 宏头文件，详见 `docs/definitions.md`；没有实现 CPU 模块。

默认设计顶层预留为 `core_cpu`，默认仿真顶层预留为 `tb_core_cpu`。你自己创建对应模块后，可以运行仿真和综合；使用其他顶层名时，修改 `scripts/create_project.tcl` 中的 `top` 设置。没有源码或测试平台时，运行脚本会提示先添加代码，不会生成示例代码。

参考代码仍保持上游实现。参考编译入口只编译 `vpackage`、`vsrc/core`、`vsrc/utils`、`vsrc/lockstep`；截图中的板级 `vsrc/structure` 依赖上游 RAM/IP 和引脚约束，不纳入此无开发板检查。仅下载 `vpackage` 和 `vsrc` 并不包含上游完整 FPGA/Verilator 工程。

对未修改的 3.2 参考源码进行 XSim 编译时，`direction_exception_predictor.sv` 的调试输出端口引用了后面才声明的 `SLOT_IDX_W`，Vivado 2023.2 的 xvlog 报 `VRFC 10-3380`。`direction_predict_v4.sv` 也有同类端口宽度写法。参考源码没有为此修改，参考编译任务目前会报告这一兼容问题；自己的 Verilog 工程不依赖它，也不将参考源码加入自己的编译集合。

仿真日志见 `build/vivado_sim.log` 和 `build/vivado/mysuperscaler.sim/sim_1/behav/xsim/simulate.log`。参考编译日志见 `build/reference-check`。

学习顺序见 `docs/learning_roadmap.md`。后续分支、异常和锁步恢复必须单独测试。

工程文件名与目录名只使用 ASCII 字符。运行脚本将子进程的 TEMP/TMP 指向 `build/tmp`，避免编译临时文件进入含中文的用户目录。说明文字可使用中文。
