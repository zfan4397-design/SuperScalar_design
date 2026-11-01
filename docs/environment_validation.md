# 环境验收记录

日期：2026-10-12。

- Vivado 2023.2：`D:/Vivado/2023.2/bin/vivado.bat -version` 检查通过。
- VS Code 1.136.2：`D:/Microsoft VS Code/bin/code.cmd --version` 检查通过。
- 已安装 `mshr-h.veriloghdl` 1.29.0，提供 Verilog/SystemVerilog 语法支持。
- 多根工作区配置 JSON 校验通过：自己的工程和 3.2 参考源码分别显示。
- 3.2 的 `vsrc` 和 `vpackage` 替换完成，下载副本逐文件 SHA-256 核对通过。
- 原 2.4d 完整保存在 `D:/zz/superscalercore_backup_2.4d_20261012_ea2903dc`。
- 公共定义核对通过：170 个常量/枚举值、51 个 packed 字段。四种 packed 向量宽度为 164、158、28、193。
- Vivado xvlog 对 `cpu_defs.vh` 及其包含的头文件进行 Verilog 分析，返回成功。
- Vivado 工程包含 9 个 Verilog 头文件，RTL 和测试平台暂时为空。

早先用于验证工具链的临时示例 RTL/测试平台已删除，旧仿真生成文件已移到系统临时目录；最终工程不包含示例 CPU。未选择开发板，未实现 CPU，未执行 CPU 正确性测试、CoreMark 或 FPGA 实现。

上游参考核心使用 XSim 编译时报告端口宽度前向引用问题，详细说明在 README。未改动参考源码；该问题不影响你从零编写的 Verilog 工程。
