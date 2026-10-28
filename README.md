# UGreen Control

UGreen Control 是面向飞牛 fnOS 的开源绿联 NAS 硬件工具箱，将灯光控制、硬件状态监测，以及兼容机型的风扇和电源管理集中到一个 Web 界面，让日常查看和设置更方便。

当前版本：**3.0.7**

[下载最新版本](https://github.com/BearHero520/UGreen-Control/releases/latest) · [v3.0.7 更新说明](docs/releases/v3.0.7.md) · [问题反馈](https://github.com/BearHero520/UGreen-Control/issues)

## 主要功能

- **灯光控制**：电源灯、网络灯和硬盘灯的开关、颜色、亮度，以及网络和磁盘活动灯效。
- **硬件监控**：查看 CPU、硬盘和 NVMe 温度、风扇转速、网络流量及磁盘活动。
- **风扇管理**：兼容机型的固定 PWM、自动温控、自定义曲线及机型兼容预设。
- **电源与唤醒**：兼容机型的来电恢复、网络唤醒（WOL）和 RTC 定时开机。
- **盘位与诊断**：自动识别机型和盘位、手动校正灯位映射、兼容性检测及诊断日志下载。
- **应用更新**：在“关于”页面检查版本、获取安装包并阅读项目说明。

不同机型的可用功能和验证状态不同，请以应用内检测结果及对应硬件文档为准。

## 系统要求

- 飞牛 fnOS 0.9.27 或更高版本
- x86 平台
- 安装和硬件控制需要 root 权限

请勿与 LLLED 命令行版或其他灯控程序同时运行，以免多个程序同时控制 LED。

## LED 适配机型

下表为 LED 适配的历史状态，不代表当前版本的风扇、BIOS 或唤醒功能均已通过实机验证。各项能力分别检测。

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

升级时下载新版本 FPK，再通过应用中心手动安装即可。应用标识沿用 `App.Native.UGreenLED`，现有用户可覆盖升级并保留配置。应用不会静默更新。

## 使用方法

### 第一次使用

1. 打开“概览”，确认识别到的 NAS 机型，查看温度、风扇和服务状态。
2. 在“设备与高级”中核对硬盘与 LED 映射，必要时使用“重新检测”。
3. 进入“灯光设置”选择模式、颜色和亮度；需要按读写速度闪灯时，在“活动提示”中配置阈值。
4. 如需管理风扇或电源，打开“BIOS 控制”，先确认可用功能和当前状态，再保存设置。

### 灯光模式

| 模式 | 效果 |
|------|------|
| 关闭全部 | 关闭电源灯、网络灯和硬盘灯 |
| 开启全部 | 所有可用灯保持常亮 |
| 智能模式 | 根据硬盘和网络状态自动控制灯光 |

在“灯光设置”中选择颜色和亮度并保存。在“活动提示”中启用速度闪动后，磁盘或网络速度达到设置的阈值时，灯光会按速度快慢闪动。可选颜色与效果以当前机型提供的能力为准。

### 盘位映射

应用会自动识别硬盘与灯位。在“设备与高级”页面查看盘位映射，或重新检测以恢复自动映射。

已有的自定义映射仍可读取。更换硬盘或调整盘位后，建议重新核对映射。

### BIOS 与风扇控制

“BIOS 控制”页面按检测结果提供风扇、来电启动、网络唤醒和定时开关机设置。页面提示不可用的功能，需要先核对当前机型和硬件环境。

| 设置 | 用法 |
| --- | --- |
| 风扇 | 选择固定 PWM、自动温控或自定义曲线，按页面提示应用设置；自动温控由软件服务持续运行。 |
| 来电启动 | 选择恢复供电后的开机、关机或恢复原状态策略，并保存。 |
| 网络唤醒 | 选择自动匹配或实际物理网口，设置 WOL 开关并保存。 |
| 定时开关机 | 选择重复日期、开机和关机时间后启用计划；时间以 NAS 系统时区为准。 |

实验性功能会要求风险确认。修改风扇或电源设置后，请观察温度和设备状态是否正常。WOL／RTC 设置回读成功与实际关机后能否唤醒需要分别验证。

DXP6800 的原厂温控曲线仍未知，兼容预设采用 DXP6800 Pro 参数；DXP480T 系列的兼容 LED 入口支持开关、闪烁和保持当前颜色，暂不支持选色与呼吸。应用发布版本不改变各机型硬件能力的实验性标注。

## 开发与本地打包

源码包含 Web 界面、应用服务及硬件接入层。克隆时获取上游硬件子模块：

```bash
git clone --recurse-submodules https://github.com/BearHero520/UGreen-Control.git
cd UGreen-Control
```

使用 Python 3.10+ 可在本地预览界面；预览使用模拟数据，不访问 NAS 硬件：

```bash
python scripts/preview_web.py
```

仓库已包含打包所需文件。在仓库根目录运行：

```bash
python scripts/build_fpk.py
```

Windows 本地安装包和校验文件默认生成到 `E:/工作台/LLLED_FPK/dist/`；Linux / CI 默认使用检出目录的 `dist/`。

硬件操作通过内置 CLI 完成。BIOS、风扇、来电恢复及唤醒能力由 [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 提供；LED 操作统一调用包内 `server/bin/ugreen_leds_cli`。载荷来源、校验记录与开发边界见[硬件接入说明](docs/almighty-integration.md)。版本变更见 [Releases](https://github.com/BearHero520/UGreen-Control/releases) 和 [v3.0.7 更新说明](docs/releases/v3.0.7.md)。

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

## 参与和反馈

欢迎通过 [Issues](https://github.com/BearHero520/UGreen-Control/issues) 反馈问题或提出建议，也欢迎提交 Pull Request 改进功能、适配和文档。反馈时请提供精确机型、fnOS 版本、应用版本、复现步骤和相关诊断日志；分享日志前请先隐藏序列号、MAC 地址等个人信息。

测试与反馈 QQ 群：**1108837172**。

## 支持作者

如果这个项目对你有帮助，欢迎点一颗 ⭐ **Star**，让更多人发现它。
愿意的话，也可以请作者喝杯咖啡，为后续适配、测试和维护添一点动力。
打赏完全自愿，量力随心；你的使用、反馈和分享，同样是很好的支持。谢谢你！

| 支付宝 | 微信支付 |
| --- | --- |
| ![支付宝自愿打赏二维码](https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/docs/assets/donate/alipay.jpg) | ![微信支付自愿打赏二维码](https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/docs/assets/donate/wechat.png) |

点击图片可查看原图。

## 相关项目

- [LLLED 命令行版](https://github.com/BearHero520/LLLED)
- [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware)

## 许可证

本项目自有代码采用 [GNU Affero General Public License v3.0 only](LICENSE) 授权。项目包含的第三方组件继续使用各自的上游许可证。
