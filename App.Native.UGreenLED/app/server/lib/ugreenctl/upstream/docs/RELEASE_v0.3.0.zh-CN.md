# UGREEN NAS Hardware v0.3.0

2026-10-28，按用户要求正式发布 `v0.3.0`。程序与插件使用 `v0.3.0-preview.1`
已完成验证的同批 0.3.0 产物；本次更新发布渠道、包名、来源记录和说明文档，
没有新增硬件控制路径。原预发布及其固定下载仍保留。

每个 Linux x86_64 / aarch64 包含四个程序、十个模型插件、兼容目录、证据说明、
逐文件 SHA-256 和两架构完整 CTest 日志。主线包含原 Almighty 功能、独立 WOL/RTC、
DXP6800 及采用 Pro 参数的兼容温控曲线。源码与包来源以本次标签和 manifest 为准。

## 发布状态与硬件能力

正式发布仅表示软件分发渠道。manifest 使用 `release_channel: stable`、
`preview: false`，但保留 `status: experimental-incomplete`、`scope_complete: false`
及实际机型限制。25 款目标机型的能力与实机验证状态继续以兼容目录为准，
不因正式发布而升级。DXP6800 原厂曲线、部分物理盘位和实际关机唤醒仍待验证。
精确机型、控制器身份、所有者互斥、进程锁、PWM 下限与写后回读保护全部保留。

## 下载与使用

- `ugreenctl-almighty-0.3.0-linux-x86_64.tar.gz`：Intel / AMD 64 位 Linux。
- `ugreenctl-almighty-0.3.0-linux-aarch64.tar.gz`：ARM64 Linux，不提供 x86 端口 I/O 能力。
- 两份对应 manifest 及 `SHA256SUMS` 用于校验归档与来源。

下载后按 `SHA256SUMS` 核对，整体解包并保留 `usr/local/` 结构。先执行
`ugreenctl --version`、`ugreenctl --plugin-dir <解包目录>/usr/local/lib/ugreenctl/models models`、
`network wol models` 和 `power rtc-wake models` 进行只读检查。
包内不包含原厂固件、第三方运行库，也不会自动安装或启动服务。

完整操作见 [中文 README](../README.zh-CN.md)，部署限制见
[Linux NAS 部署](LINUX_DEPLOYMENT.zh-CN.md)。
