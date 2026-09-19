# DX4600 主线整理（2026-09-19）

用户确认精确型号 DX4600 的灯光颜色/开关、风扇、断电恢复和 WOL 均已实测通过。
主线保留对应控制实现，身份检查、锁、写入保护和回读继续有效。
本记录不扩展到 DX4600+、DX4600 Pro、DH2600，也不补写未提供的逐策略或逐网口测试细节。

## 保留与整理

- LED 只通过内置 `server/bin/ugreen_leds_cli`；固定上游提交及补丁由
  `scripts/build_ugreen_leds_cli.py` 重放。DX4600 的签名、总线候选、legacy 帧、
  重试间隔与互斥锁沿用实测实现，独立补丁为 `dx4600-firmware-1.19.patch`。
- BIOS/风扇/电源/WOL 实现仍在 UGREEN-NAS-Hardware；应用子模块引用其已记录
  DX4600 实测结果的提交。随包硬件二进制从相同源码重新构建。
- 保留 DX4600 来电策略保存和服务生命周期恢复，见
  [来电策略恢复](DX4600_STARTUP_PERSISTENCE.zh-CN.md)。这不是改写 BIOS NVRAM。
- 已运行的 `/daemon/start` 请求直接返回当前状态，避免保存灯光设置时反复恢复硬件。
- 只读硬件诊断显式传递随包模型目录，避免依赖 Windows 构建机的默认安装路径。
- 主线不带 DH2600 源码注册、LED 协议、页面选项、测试及插件。两个仓库均通过
  `codex/dh2600-firmware` 独立保存其开发代码，未将该机型宣称为实测通过。
- 构建成功后清理非本分支模型插件；打包前拒绝残留插件，防止切换分支后混包。
- 清理旧前端入口和不再引用的 JS 产物；保留回归测试及必要诊断。

## 验证

- 固定 LED 上游提交及三份补丁干净重放、静态 Linux 编译、Linux `--version` / `--help` 检查通过。
- 硬件上游 CMake Release 构建通过，glibc 生产构建的 12 项 CTest 在隔离 Linux VM 全部通过。
  插件加载检查通过。模拟测试不连接 NAS，不构成新增实机写入验收。
- 应用 `test_startup_persistence.sh`、`test_bios_api.sh`、`test_hardware_mapping.sh`、
  `test_main_start.sh`、`test_api_logging.sh`、`test_nas_hardware_collect.sh`、
  `test_api_daemon_start.sh` 通过。
- 前端 TypeScript 检查和 Vite 构建通过；保留原有图表 chunk 大小提示。
- 项目文件与 LED SHA-256 校验通过，并验证额外机型插件会被拒绝；未生成 FPK。

原始实测 CLI 与拆分后 CLI 的指纹分别记录于
[LED 基准](../App.Native.UGreenLED/app/server/vendor/ugreen_leds_controller/DX4600_VALIDATION.zh-CN.md)。
ACK 不匹配与历史超时仍单独追踪；本轮不通过伪造成功状态来消除报错。

## 其他工作

拆分前的未提交工作保存在两个仓库的 `codex/preserve-before-dx4600-split-20260919`
本地分支及仓库外 `E:\工作台\llled-merge-backup-20260919`。其中 NVMe 温度修复、
独立版本/UI 改动没有混入本次 DX4600 合并。没有推送分支、发布版本或打包。
