# UGreen Control

适用于飞牛 fnOS 的绿联 NAS 灯光、硬件监控与 BIOS 管理应用。

当前版本：**3.0.5**

本项目原名 **LLLED_FPK**，现已直接更名为 **[UGreen-Control](https://github.com/BearHero520/UGreen-Control)**。原仓库的提交历史、Issues、Stars、Fork、标签与 Releases 均保留；旧仓库地址会重定向到新地址。应用标识仍为 `App.Native.UGreenLED`，现有用户可通过 fnOS 应用中心覆盖升级并保留配置。

## 仓库更名与分支

- 原 `LLLED_FPK/almighty` 已合入当前仓库的 `main`；本仓库继续维护完整应用源码及版本发布。
- `UGREEN-NAS-Hardware/Almighty` 已合入该仓库的 `main`，硬件实现继续在独立硬件仓库维护。
- v3.0.5 起，在线更新与下载使用 [UGreen-Control Releases](https://github.com/BearHero520/UGreen-Control/releases/latest)，关于页面读取本仓库 `main/README.md`。
- BIOS、风扇、来电恢复、WOL 与 RTC 的硬件检测和访问由 [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 提供；应用仅适配 API、界面和服务。LED 操作统一调用包内 `server/bin/ugreen_leds_cli`。

当前版本保留 Almighty 的独立 WOL／RTC、DXP6800 精确插件、自定义温控曲线及界面改进。硬件包固定到不可变提交和 SHA-256；源码、测试日志和硬件限制见 [接入说明](docs/almighty-integration.md)。本次迁移没有新增 NAS 实机验证。

上游已实现的 BIOS／风扇和来电恢复能力继续开放，包括实验性路径，保留写入确认与上游硬件保护。WOL／RTC 按上游各自的精确机型清单独立开放，不再受风扇插件白名单限制；本包为 x86_64，覆盖对应的 23 款 x86 唤醒档案，ARM 机型需要 ARM 应用包。

WOL 可自动匹配已建立映射的物理网口，也可手动指定 `enp3s0`、`eno1` 等实际名称并检测当前状态。保存成功后记住当前机型的网卡选择，失败不覆盖原选择；15 款上游尚无自动映射的机型必须显式指定网卡。物理网卡身份、Magic Packet 能力和写后回读由上游检查。RTC 独立匹配控制器，不依赖 WOL 查询或风扇插件是否可用。接口可读写不代表全部机型的实际关机唤醒、跨 BIOS 行为和跨重启持久化均已实测。

重新校验或导入硬件包使用 `python scripts/build_ugreenctl.py`；Windows 环境还需通过 `--source-root` 指定上游仓库及其隔离运行环境。本地打包使用已导入且通过校验的文件。
本分支硬件支持属于实验性，历史版本的验证状态不代表此次新版已通过 NAS 实机验证。
DXP480T 的新版兼容接口支持开关和闪烁、保持当前颜色，暂不支持选色与呼吸。
导入、校验及服务边界见 [接入说明](docs/almighty-integration.md)。

测试与反馈 QQ 群：**1108837172**

2.2.4 新增 DXP6800 Plus 风扇与来电启动策略支持，完善型号显示和三路风扇遥测。
Plus 兼容温控预设采用 DXP6800 Pro 参数，也可使用自定义曲线。

2.2.3 针对 DX4600 的 `LED controller busy` 问题优化总线探测，合并各灯状态读取，
并防止页面状态刷新重叠。保留 MCU 签名校验、后备总线探测与 CLI 互斥锁；实机效果待验证。

## 主要功能

- 关闭全部、开启全部、智能模式三种灯光模式
- 根据硬盘活动、休眠、离线状态自动控制硬盘灯
- 根据网络连接状态和传输速度控制网络灯
- 自定义电源灯、网络灯和硬盘灯颜色及亮度
- 自动识别机型和盘位，支持手动校正硬盘灯映射
- 在受支持机型上提供风扇、来电启动、网络唤醒和定时开关机
- 在“关于”页面检查应用更新，并直接读取 GitHub `README.md`
- 提供应用诊断日志查看与下载

## 系统要求

- 飞牛 fnOS 0.9.27 或更高版本
- x86 平台
- 安装和硬件控制需要 root 权限

请勿与 LLLED 命令行版或其他灯控程序同时运行，以免多个程序同时控制 LED。

## 支持机型

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
