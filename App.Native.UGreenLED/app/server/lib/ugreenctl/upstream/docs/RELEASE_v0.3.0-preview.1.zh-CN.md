# UGREEN NAS Hardware v0.3.0-preview.1

2026-10-28，基于合并 Almighty 后的 `main` 重新构建 Linux x86_64 与 aarch64
预览包。项目版本为 0.3.0，发布标签为 `v0.3.0-preview.1`。归档名保留既有
`ugreenctl-almighty` 前缀，manifest 的来源分支更新为 `main`。

## 本次更新

- 整合 Almighty 的 LED、磁盘映射、软件温控、来电恢复状态协调及证据目录。
- 包含独立的 WOL / RTC 机型路由、网口选择与 RTC 时间校验。
- 包含精确 DMI `DXP6800` 的独立 IT8613 风扇与来电恢复插件；`stock-6800`
  是采用 Pro 参数的兼容曲线，DXP6800 原厂曲线仍未知。
- 包含显式选择的 N76 实验直控；实际灯光输出仍未验证。
- 每个架构完整重建四个程序和十个模型插件，保留精确 DMI、控制器身份、
  所有者互斥、进程锁、安全 PWM 下限和写后回读保护。

## 发布范围与限制

本版为 GitHub 预发布，归档标记 `preview` / `experimental-incomplete`。
目录覆盖 25 款目标机型，排除 DH2100、DH2100+；目录覆盖不表示全部能力已完成。
LED 输出、部分 SATA / M.2 物理槽位、实际关机唤醒与逐 BIOS 行为仍有未验证项，
以包内 `models/compatibility.json` 和证据文档为准。本次构建与隔离 QEMU 测试
不增加 NAS 实机验证记录。

ARM64 构建不提供 x86 Super I/O 端口 I/O 能力。动态 glibc、加载器与依赖要求
以各包 manifest 的 `runtime_abi` 为准；包内不附带第三方运行库。
服务文件为部署示例，解包不会安装或启动服务。

## 下载与校验

- Intel / AMD 64 位 Linux：`ugreenctl-almighty-0.3.0-linux-x86_64-preview.tar.gz`
- ARM64 Linux：`ugreenctl-almighty-0.3.0-linux-aarch64-preview.tar.gz`
- 每个架构另附 manifest，`SHA256SUMS` 校验两个归档及两份 manifest。
- 包内附当前源码与二进制 SHA-256、两架构完整 CTest 日志及验证报告。

下载四个载荷文件及 `SHA256SUMS` 到同一目录，执行 `sha256sum -c SHA256SUMS`。
按目标架构整体解包，保留 `usr/local/bin/`、`usr/local/lib/ugreenctl/models/`
和文档目录的关系。先使用 `ugreenctl --help`、`led list --json` 及
`ugreenctl --plugin-dir <解包目录>/usr/local/lib/ugreenctl/models models`
进行只读检查，插件列表应完整列出十个模块。

部署说明见 [Linux NAS 部署](LINUX_DEPLOYMENT.zh-CN.md)，
构建与验证方法见 [构建复现](BUILD_REPRODUCIBILITY.zh-CN.md)。
配套应用后续更新位于 [UGreen-Control](https://github.com/BearHero520/UGreen-Control)。
