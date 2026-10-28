# UGreen Control

UGreen Control 是面向飞牛 fnOS 的绿联 NAS 硬件工具箱，将灯光控制、硬件状态监测，以及兼容机型的风扇和电源管理集中到一个界面。

当前版本：**3.0.5**

[下载最新版本](https://github.com/BearHero520/UGreen-Control/releases/latest) · [v3.0.5 更新说明](docs/releases/v3.0.5.md) · [问题反馈](https://github.com/BearHero520/UGreen-Control/issues)

本项目由原 **LLLED_FPK 仓库直接更名**为 UGreen-Control，提交历史、Issues、Stars、Fork、标签及 Releases 均保留，旧地址会重定向到新地址。应用标识仍为 `App.Native.UGreenLED`，现有用户可通过 fnOS 应用中心覆盖升级并保留配置。

## 主要功能

- **灯光控制**：电源灯、网络灯和硬盘灯的开关、颜色、亮度，以及网络和磁盘活动灯效。
- **硬件监控**：查看 CPU、硬盘和 NVMe 温度、风扇转速、网络流量及磁盘活动。
- **风扇管理**：兼容机型的固定 PWM、自动温控、自定义曲线及机型兼容预设。
- **电源与唤醒**：兼容机型的来电恢复、网络唤醒（WOL）和 RTC 定时开机。
- **盘位与诊断**：自动识别机型和盘位、手动校正灯位映射、兼容性检测及诊断日志下载。
- **应用更新**：在“关于”页面检查版本、获取安装包并阅读项目说明。

不同机型的可用功能和验证状态不同，请以应用内检测结果及对应硬件文档为准。

## v3.0.5 更新

- 统一使用 UGreen Control 名称，在线更新、下载、说明和反馈入口使用本仓库地址。
- 将原 `almighty` 分支的应用实现合入 `main`，保留独立 WOL / RTC 能力及实际网卡选择。
- 接入 DXP6800 独立插件、三路风扇遥测、自定义温控及 Pro 参数兼容预设。
- 改善界面控件、灯光交互和窄屏布局。

DXP6800 原厂温控曲线仍未知，兼容预设采用 DXP6800 Pro 参数；DXP480T 的兼容 LED 入口支持开关、闪烁和保持当前颜色，暂不支持选色与呼吸。v3.0.5 未新增 NAS 实机写入或关机唤醒验证。

应用通过内置 CLI 完成硬件操作。BIOS、风扇、来电恢复及唤醒能力由独立的 [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 提供；LED 操作统一调用包内 `server/bin/ugreen_leds_cli`。载荷来源、校验记录和接入边界见[硬件接入说明](docs/almighty-integration.md)。

测试与反馈 QQ 群：**1108837172**

## 系统要求

- 飞牛 fnOS 0.9.27 或更高版本
- x86 平台
- 安装和硬件控制需要 root 权限

请勿与 LLLED 命令行版或其他灯控程序同时运行，以免多个程序同时控制 LED。

## LED 适配机型

下表为 LED 适配的历史状态，不代表 v3.0.5 的风扇、BIOS 或唤醒功能均已通过实机验证。各项能力分别检测。

| 状态 | 机型 |
|------|------|
| 已验证 | DX4600、DX4600 Pro、DX4700+、DXP2800、DXP4800、DXP4800 Plus、DXP6800 Pro、DXP8800 Plus |
| 实验性 | DXP4800S、DXP4800 GT、iDX6011、iDX6011 Pro |
| 待验证 | DXP2800 GT、DXP4800 Pro |
| 受限支持 | DXP480T、DXP480T Plus，仅支持红白电源灯 |

不同机型提供的 LED、风扇和电源管理功能可能不同。实验性或待验证机型建议先使用应用内的检测功能确认硬件映射。

## 下载与安装

1. 从 [GitHub Releases](https://github.com/BearHero520/UGreen-Control/releases) 下载最新的 `App.Native.UGreenLED.fpk`。
2. 打开 fnOS 应用中心，选择手动安装。
3. 选择下载的 FPK 文件并完成安装。
4. 从 fnOS 桌面打开“UGreen Control”。

升级时下载新版本 FPK，再通过应用中心手动安装即可。应用不会静默更新。

## 使用方法

### 灯光模式

| 模式 | 效果 |
|------|------|
| 关闭全部 | 关闭电源灯、网络灯和硬盘灯 |
| 开启全部 | 所有可用灯保持常亮 |
| 智能模式 | 根据硬盘和网络状态自动控制灯光 |

在“灯光设置”中选择颜色和亮度并保存。启用速度闪动后，磁盘或网络速度达到设置的阈值时，灯光会按速度快慢闪动。

### 盘位映射

应用会自动识别硬盘与灯位。在“设备与高级”页面查看盘位映射，或重新检测以恢复自动映射。

实验室及其临时灯光接管接口已移除；既有自定义映射仍可读取。

### BIOS 与风扇控制

受支持机型会显示 BIOS 控制页面，可配置风扇、来电启动、网络唤醒和定时开关机。页面未显示的功能表示当前机型或硬件环境不支持。

实验性功能会要求风险确认。修改风扇或电源设置后，请观察温度和设备状态是否正常。

## 本地打包

仓库已包含打包所需文件。在仓库根目录运行：

```bash
python scripts/build_fpk.py
```

Windows 本地安装包和校验文件默认生成到 `E:/工作台/LLLED_FPK/dist/`；Linux / CI 默认使用检出目录的 `dist/`。

## 日志与排错

应用内“设备与高级”页面可以查看日志并下载诊断包；“关于”页面提供版本、更新、项目说明和测试 QQ 群信息。常见日志路径：

```text
/var/apps/App.Native.UGreenLED/var/log/app.log
```

遇到问题时可依次检查：

1. fnOS 版本和平台是否符合要求。
2. 是否同时运行了其他 LED 控制程序。
3. 应用硬件状态中是否识别到正确机型。
4. 日志中是否存在 `WARN` 或 `ERROR`。

如果 LED 硬件暂时不可用，应用管理页面仍可打开，后台会继续尝试连接硬件。

## 相关项目

- [LLLED 命令行版](https://github.com/BearHero520/LLLED)
- [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware)

## 许可证

本项目自有代码采用 [GNU Affero General Public License v3.0 only](LICENSE) 授权。项目包含的第三方组件继续使用各自的上游许可证。
