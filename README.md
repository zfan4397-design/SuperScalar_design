# SuperScalar_design

超标量 CPU 的 Verilog 复现工程，参考项目为 `superscalercore`。本仓库保留原有提交中的代码，并补充本地 `mysuperscaler` 工程快照。

## 目录

- `rtl/`：仓库原有模块，以及本地 `rtl/utils/` 下的重命名、保留站等模块。
- `build/vivado/mysuperscaler.srcs/sources_1/new/`：在 Vivado 中编辑的 Verilog 源码，包括取指、译码、访存、退休、CLINT 和 store buffer 等模块。
- `build/vivado/mysuperscaler.xpr`：本地 Vivado 工程描述。
- `vpackage/`：Verilog 公共宏、结构定义和辅助函数。
- `scripts/`：创建工程、添加模块和模块检查脚本。
- `tests/`：现有模块测试平台。
- `docs/`：学习和工程说明；`original_project_readme.md` 保留本地原始说明，其中早期“RTL 为空”等描述已不代表当前状态。
- `superscalar/`：原有提交中的 Vivado 工程，保留原样。

## 使用说明

使用 Vivado 2023.2，可打开 `build/vivado/mysuperscaler.xpr` 查看本地复现工程。工程器件为 `xc7k70tfbv676-1`，尚未选择开发板或配置引脚约束。迁移到其他路径后，部分脚本中的本地工具路径、参考项目路径需要按实际环境调整。

源码正在逐模块复现和验证，部分模块仍有 TODO；本次上传未进行整核编译、仿真或综合验证。

两个源码目录中存在同名模块及不同版本，例如 `rs_lsu_queue.v`。上传保留各版本，未合并或替换实现。请按对应工程和模块脚本选择文件，不要递归编译仓库内全部 Verilog 文件。`scripts/add_rs_lsu.tcl` 在 GUI 源文件存在时优先选择 GUI 版本。

本地工程原始目录结构保留，以便现有脚本定位源码；`build/` 中仅加入上述工程描述和手写源码，缓存、仿真产物及日志不上传。VS Code 工作区中的 `../superscalercore` 是本地参考目录，需要另行准备。
