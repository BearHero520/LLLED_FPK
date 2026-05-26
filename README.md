# 绿联 LED 灯控（飞牛 fnOS 原生应用）

在飞牛 **fnOS** 上控制绿联 **DXP4800 Plus** / **DX4600** 系列机箱 LED（I2C `0x3a`，`ugreen_leds_cli`）。支持关闭全部、开启全部、智能模式，以及按硬盘 / 网络 / 电源状态自动配色。

- **本仓库**：[LLLED_FPK](https://github.com/BearHero520/LLLED_FPK) — 飞牛应用源码与打包说明  
- **命令行版**：[LLLED](https://github.com/BearHero520/LLLED) — 不装飞牛包时的 Shell 方案  
- **协议参考**：[miskcoo · 绿联 DX4600 Pro LED](https://blog.miskcoo.com/2024/05/ugreen-dx4600-pro-led-controller)

## 仓库结构

```
LLLED_FPK/
├── App.Native.UGreenLED/   # 飞牛原生应用（fnpack 打包）
│   ├── manifest
│   ├── ICON.PNG / ICON_256.PNG
│   ├── app/                  # server、ui、www
│   ├── cmd/                  # 安装 / 启停 / 升级生命周期
│   ├── config/
│   └── scripts/              # 图标处理等维护脚本
└── README.md
```

应用 ID：`App.Native.UGreenLED` · 当前版本：**1.2.5**

## 功能概览

| 功能 | 说明 |
|------|------|
| 三档模式 | 关闭全部 / 开启全部 / 智能模式 |
| 硬盘灯 | 活动、空闲、休眠、深度睡眠、离线（拔出自动关灯） |
| 盘位映射 | 按 **HCTL** 动态映射到 disk1–disk4，支持热插拔重映射 |
| 网络灯 | **外网**（海外检测点通）、**联网**（仅国内通）、**断网** |
| 电源灯 | 智能 / 全开模式下可单独配色 |
| Web 配置 | 飞牛桌面 iframe 内配色预设、保存后自动进入智能模式 |

> 硬件限制：灯处于 **off** 时不能直接改色，须先 `-on` 再设色。`app/server/lib/led_api.sh` 已自动处理。

> 请勿与 **LLLED 命令行版** 或其它抢灯权的应用同时运行，只保留一个控制端。

## 打包与安装

### 环境要求

- fnOS **≥ 0.9.27**，平台 **x86**
- 安装需 **root**（访问 I2C）；安装回调会自动拉取 `ugreen_leds_cli`、安装 `i2c-tools` / `hdparm` 并加载 `i2c-dev`

### 使用 fnpack 打包

参考 [飞牛 · 创建应用](https://developer.fnnas.com/docs/quick-started/create-application)：

```bash
cd App.Native.UGreenLED
fnpack build
```

生成 `App.Native.UGreenLED.fpk`，在 **应用中心 → 手动安装** 即可。

也可在仓库根目录执行（需能 SSH 到已安装 fnpack 的 NAS）：

```bash
python scripts/build_fpk_remote.py
```

安装包输出：`App.Native.UGreenLED.fpk`（不纳入 Git，可从 [Releases](https://github.com/BearHero520/LLLED_FPK/releases) 下载）。

### 更换应用图标

将源图命名为 `可爱灯泡设计.png` 放在仓库根目录（与 `App.Native.UGreenLED` 同级），然后：

```bash
python App.Native.UGreenLED/scripts/process_logo.py
```

会更新 `ICON.PNG`、`ICON_256.PNG`、`app/ui/images/icon-64.png` / `icon-256.png`（与 `ui/config` 中 `icon-{0}.png` 一致）及 `app/www/images/logo.png`。

## 使用说明

| 模式 | 行为 |
|------|------|
| **关闭全部** | 电源 / 网络 / 硬盘灯全关 |
| **开启全部** | 全部常亮（可配电源灯颜色） |
| **智能模式** | 按硬盘与网络状态自动变色 |

智能模式下盘位示例：`0:0:0:0→disk1`，`2:0:0:0→disk3`（以实际 HCTL 为准）。

运行时配置：`/var/apps/App.Native.UGreenLED/var/settings.conf`（Web 保存后写入）。

## HTTP API（CGI）

基址：`/cgi/ThirdParty/App.Native.UGreenLED/api.cgi`

| 路径 | 说明 |
|------|------|
| `/status` | 守护进程与 LED 状态 |
| `/mapping` | 硬盘映射表 |
| `/settings` | GET / POST 配置 |
| `/mode?mode=off\|on\|smart` | 切换模式 |
| `/daemon/start` · `/daemon/stop` | 启停守护进程 |
| `/remap` | 重新 HCTL 映射 |
| `/led/set?led=disk1&r=255&g=0&b=0` | 手动设色 |

## 常见问题

**安装报「应用包不符合系统要求」**  
确认 `app/ui/config` 为**单个 JSON 文件**，不是目录；`manifest` 中 `platform=x86`、`os_min_version` 与系统一致。

**打开应用闪退**  
多为路径问题：运行时代码会在 `server/` 与 `target/server/` 间自动探测，请使用本仓库最新版。

**网络灯一直断网**  
请升级至含新版 `net_state.sh` 的版本（海外通→外网，否则国内通→联网）。

## 许可证

MIT
