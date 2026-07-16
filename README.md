# 绿联 LED 灯控（飞牛 fnOS 原生应用）

在飞牛 **fnOS** 上控制绿联 NAS 机箱 LED。应用内置上游 **v0.4-beta `ugreen_leds_cli`**，支持 `0x3a` legacy / SMBus block-write 协议、CLI / sysfs 后端、DXP480T N76E003 电源灯后端、机型预设以及 2/4/6/8 盘位映射。

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

应用 ID：`App.Native.UGreenLED` · 当前版本：**1.7.6**

## 功能概览

| 功能 | 说明 |
|------|------|
| 三档模式 | 关闭全部 / 开启全部 / 智能模式 |
| 硬盘灯 | 活动、空闲、休眠、深度睡眠、离线（拔出自动关灯） |
| 硬件后端 | 默认使用内置 CLI；可检测或实验性安装 `led-ugreen` sysfs/DKMS 后端；DXP480T 自动使用专用电源灯后端，所有 I²C 控制路径严格互斥 |
| 机型档案 | DMI 自动识别，也可手动选择；档案包含协议、灯位数量、LED 编号别名和 HCTL 顺序 |
| 盘位映射 | 自动按当前 HCTL 实时重建；实验室支持按硬盘位置或按硬盘序列号绑定 LED |
| 网络灯 | **外网**（海外检测点通）、**联网**（仅国内通）、**断网** |
| 速度闪动 | 磁盘读写、网络上传下载超过阈值后闪动，速度越高闪动越快，两项可独立开关 |
| 电源灯 | 智能 / 全开模式下可单独配色 |
| BIOS 控制 | 直接集成 [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 的 `ugreenctl`；DXP4800 Plus / Pro 支持 CPU、系统风扇 PWM，DXP480T Plus 可读三路转速/PWM/模式，并已验证 CPU/全部风扇 PWM 与来电启动策略 |
| Web 配置 | 飞牛桌面 iframe 内配色预设、保存后自动进入智能模式 |

> 硬件限制：灯处于 **off** 时不能直接改色，须先 `-on` 再设色。`app/server/lib/led_api.sh` 已自动处理。

> 请勿与 **LLLED 命令行版** 或其它抢灯权的应用同时运行，只保留一个控制端。

## 打包与安装

### 环境要求

- fnOS **≥ 0.9.27**，平台 **x86**
- 安装需 **root**（访问 I2C）；FPK 已内置并校验 v0.4-beta `ugreen_leds_cli`，安装回调会安装缺少的 `i2c-tools` / `hdparm` 并加载 `i2c-dev`
- 实验性内核驱动不会自动安装；主动启用时需要 `dkms` 和当前内核对应的 headers

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

脚本会交互询问 NAS 地址、用户名和密码，也可通过 `FNOS_HOST`、`FNOS_USER`、`FNOS_PASSWORD` 环境变量传入；密码不会写入源码或打印到终端。

安装包输出：`App.Native.UGreenLED.fpk`（不纳入 Git，可从 [Releases](https://github.com/BearHero520/LLLED_FPK/releases) 下载）。

### 本地无 NAS 打包

仓库内置了跨平台构建器，可在 Windows、Linux 或 GitHub Actions 中直接生成与 `fnpack` 相同结构的 FPK，不需要连接 NAS：

```bash
python scripts/build_ugreenctl.py # 仅 x86 Linux；GitHub Actions 会自动执行
python scripts/build_fpk.py
```

`ugreenctl` 与 DXP4800 Plus / DXP480T Plus 机型插件由 CI 在 Ubuntu 22.04 构建并随 FPK 分发；Windows 本地检出请通过 GitHub Actions 打包。`scripts/build_fpk_remote.py` 会在 NAS 端按需安装 CMake 和编译器再构建它。硬件源代码以 Git 子模块固定在 `App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware`，克隆时请使用 `git clone --recurse-submodules`；升级时同步更新该子模块提交。

输出目录为 `dist/`，其中包括：

- `App.Native.UGreenLED-<版本>.fpk`：带版本号的发布文件。
- `App.Native.UGreenLED.fpk`：供应用更新检查使用的固定文件名。
- `App.Native.UGreenLED-<版本>.fpk.sha256`：完整性校验文件。

构建器会生成 `app.tgz`，把它的 MD5 写入 FPK 内部 `manifest` 的 `checksum` 字段，并在完成后重新读取安装包校验结构。

### 自动创建 GitHub Release

`.github/workflows/release.yml` 会在推送 `v*.*.*` 标签时自动构建并发布 Release。标签版本必须与 `App.Native.UGreenLED/manifest` 中的 `version` 一致：

```bash
git tag v1.7.6
git push origin v1.7.6
```

也可以在 GitHub Actions 页面手动运行工作流，只生成可下载的构建产物而不创建 Release。Release 会同时上传带版本文件名、固定文件名以及 SHA256 校验文件。

### 本地预览 Web 界面

无需安装到 fnOS，运行内置模拟 API 预览服务器：

```bash
python scripts/preview_web.py
```

浏览器会打开 `http://127.0.0.1:8080/cgi/ThirdParty/App.Native.UGreenLED/index.cgi/`。预览模式使用模拟网速、硬盘和守护进程数据，不会控制真实 LED。

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

智能模式的“速度闪动提示”中可分别启用磁盘和网络闪动，并设置触发阈值（KB/s）。新安装和升级后默认关闭，以保持原有灯效；启用后低、中、高三档速度会使用不同闪动频率。

自动模式不会把 `/dev/sdX` 当作固定盘位；每次启动和硬盘拓扑变化后，都会用当前的 `device + HCTL + serial` 重建映射。缺少中间硬盘时，其余盘位不会向前挤压。

内置 HCTL 预设：

| 机型 | 映射规则 |
|------|----------|
| DX4600 / DX4700 / DXP2800 / DXP4800 系列 | `0:0:0:0→disk1`，依次递增并限制到实际灯位数 |
| DXP6800 Pro | `0→disk5`、`1→disk6`、`2→disk1`、`3→disk2`、`4→disk3`、`5→disk4` |
| DXP8800 Plus | `0…7→disk1…disk8` |

### 支持状态

| 状态 | 机型 |
|------|------|
| 已验证 | DX4600 Pro、DX4700+、DXP2800、DXP4800、DXP4800 Plus、DXP6800 Pro、DXP8800 Plus |
| 实验性 | DXP4800 GT、iDX6011 / iDX6011 Pro |
| 待验证 | DXP2800 GT、DXP4800 Pro |
| 受限支持 | DXP480T / DXP480T Plus（独立 N76E003 控制器，仅红/白电源灯） |

DXP4800 GT 和 iDX6011 系列使用 `smbus-block`；iDX6011 Pro 的第二网络灯与六个硬盘灯会通过逻辑 LED 别名校正。实验性机型建议先在“实验室”逐灯验证。

DXP480T 系列与其他机型不同：它没有硬盘灯和网络灯，也不使用 `0x3a` RGB MCU。应用按原厂 `leds-mcu-n76e003` 驱动的规则，在可用 I²C 总线上探测地址 `0x31`、`0x26`，并读取 `0x5a/0x5b` 验证 `0xa5b5` 签名后才允许写入。红/白通道、常亮、快闪、慢闪、呼吸和关闭均使用固件恢复的 SMBus byte-data 寄存器序列；不会为该档案安装通用 `led-ugreen` DKMS 驱动。检测到专用后端后，“灯光设置”页面会自动替换为 480T 简化控制页；“网络活动”模式会复用电源灯，在总上传与下载速度超过页面设置的阈值后慢闪，达到阈值 4 倍后快闪。其他机型继续使用原来的完整 RGB 设置页。

BIOS 控制直接集成 [BearHero520/UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 的 `ugreenctl` 与 DXP4800 Plus / DXP480T Plus 插件（MIT）。该项目负责精确 DMI 匹配、IT8613 身份及原厂驱动冲突检查、进程锁和寄存器映射；本应用负责 Web API 与页面展示。DXP480T Plus 的风扇和来电启动路径来自原厂固件 `1.17.0.95` 静态逆向，并已在实机验证：页面可读取 CPU、系统风扇 1、系统风扇 2 的转速、PWM 和自动/手动模式；写入仍只开放 CPU 或全部风扇，PWM 强制最低 40。全部风扇按原厂顺序写入 CPU、系统风扇 2、系统风扇 1，不开放单独系统风扇写入。普通 DXP480T 不会因手动机型档案选择而绕过精确 DMI 保护。

如果 LED 硬件或 `i2c-tools` 暂时不可用，应用仍会完成安装并开放 Web 管理页，不会因为灯控后端探测失败而让 fnOS 报整包安装失败。后台服务会继续重试，并在硬件状态区域显示诊断信息。

### CLI 与实验驱动

- `backend=auto`：检测到可用的 `led-ugreen` sysfs 设备时使用驱动，否则使用内置 CLI。
- `backend=cli`：强制使用内置 CLI；如果内核驱动仍占用 MCU，会拒绝启动，避免同时访问 I2C。
- `backend=sysfs`：强制使用内核驱动；不可用时明确报错。
- DXP480T 系列在 `auto` / `cli` 设置下会自动使用专用 `power-0x26` 后端，不调用通用 CLI。
- `write_protocol=auto` 默认跟随机型档案；未知硬件可手动强制 `legacy` 或 `smbus-block`，避免完全依赖 DMI 名称。
- FPK 携带上游驱动源码，但只有用户在 Web 页面确认后才会通过 DKMS 编译；缺少 headers、存在厂商 LED 模块或已有非本应用管理的驱动时会拒绝覆盖。
- 随包驱动基于上游 v0.4-beta `kmod` 源码，仅增加状态读取的数组边界保护；上游许可证原样保留在驱动目录中。
- 用户启用过的驱动会在应用随系统启动时重新探测；内核升级后若 DKMS 模块暂不可用，会安全回退到内置 CLI。卸载驱动时会先释放应用创建的 I²C 设备，确认 MCU 不再被占用后才允许切回 CLI。

### 实验室：两种硬盘灯绑定方式

当 6 盘位或 8 盘位机型的硬盘灯顺序与系统顺序不一致时，可在侧边栏进入“实验室”。检测模式会先点亮全部硬盘灯，再提供两种互相独立的绑定方式：

- **按位置绑定（推荐）**：将 HCTL 代表的硬盘位置绑定到 LED 通道。更换硬盘后对应关系不变，适合固定机箱盘位。
- **按硬盘绑定**：将硬盘序列号绑定到 LED 通道。设备名变化或硬盘移动后，映射仍跟随这块具体硬盘。

两套规则会同时保留，最后保存的方式成为当前生效模式；“恢复自动映射”只切回自动 HCTL 模式，不会删除已保存的两套规则。

> 此功能未经完整机型验证。检测期间会临时接管硬盘灯，保存、取消或会话超时后恢复后台灯效；网络灯和电源灯不参与绑定。页面提供“恢复自动映射”用于随时回退。

运行时配置：`/var/apps/App.Native.UGreenLED/var/settings.conf`（Web 保存后写入）。高频状态、速度采样、LED 缓存和 PID 存放在 `/run/App.Native.UGreenLED`，重启后自动重建，避免持续写入应用所在存储池。

硬盘活动仍按 `check_interval`（默认 5 秒）从内核 `/proc/diskstats` 读取；`hdparm -C` 电源状态查询由 `disk_power_probe_interval` 控制（默认 60 秒，可在“设备与高级”设置 10–3600 秒），热插拔扫描由 `hotplug_check_interval` 控制（默认 30 秒，可设置 5–3600 秒）。

## HTTP API（CGI）

基址：`/cgi/ThirdParty/App.Native.UGreenLED/api.cgi`

| 路径 | 说明 |
|------|------|
| `/status` | 守护进程与 LED 状态 |
| `/mapping` | 硬盘映射表 |
| `/settings` | GET / POST 配置 |
| `/hardware/status` | 机型档案、协议、后端、DKMS 与内核 headers 状态 |
| `/bios/status` | DXP4800 Plus / Pro / DXP480T Plus 的 IT8613、风扇 PWM/转速/模式与来电启动状态 |
| `/bios/fan?channel=cpu\|sys\|all&pwm=40..255` | POST：设置风扇 PWM；480T 仅允许 `cpu` / `all` |
| `/bios/startup?policy=on\|off\|last` | POST：设置来电启动策略 |
| `/power26/apply` | POST：为 DXP480T / Plus 应用红白电源灯颜色、灯效或关闭 |
| `/driver/install` | POST：确认后安装或重建本应用管理的实验驱动 |
| `/driver/unload` | POST：卸载本应用管理的驱动并切回 CLI |
| `/update/check?force=1` | 检查 GitHub 最新 Release；`force=1` 忽略 6 小时缓存 |
| `/mode?mode=off\|on\|smart` | 切换模式 |
| `/daemon/start` · `/daemon/stop` | 启停守护进程 |
| `/remap` | 重新 HCTL 映射 |
| `/lab/mapping/status` | 查询实验室检测状态、盘位和硬盘清单 |
| `/lab/mapping/start` · `/lab/mapping/highlight` | 开始检测并逐 LED 通道闪烁识别 |
| `/lab/mapping/save` | 保存按硬盘序列号绑定 |
| `/lab/position/save` | 保存按 HCTL 位置绑定 |
| `/lab/mapping/cancel` | 放弃当前检测 |
| `/lab/mapping/reset` | 恢复自动 HCTL 映射 |
| `/led/set?led=disk1&r=255&g=0&b=0` | 手动设色 |
| `/led/off?led=disk1` | 手动关闭单个灯 |

Web 管理页使用 fnOS CGI，不再自动启动旧版 5088 端口服务，减少无鉴权端口暴露和无效后台进程。

“设备与高级 → 应用更新”会在打开管理页时检查 GitHub Release。发现新版后，用户可以查看更新说明并下载固定名称的 FPK；为避免依赖未公开的 fnOS 内部安装接口，应用不会静默安装，仍需在应用中心手动确认升级。

## 常见问题

**安装报「应用包不符合系统要求」**  
确认 `app/ui/config` 为**单个 JSON 文件**，不是目录；`manifest` 中 `platform=x86`、`os_min_version` 与系统一致。

**打开应用闪退**  
多为路径问题：运行时代码会在 `server/` 与 `target/server/` 间自动探测，请使用本仓库最新版。

**网络灯一直断网**  
请升级至含新版 `net_state.sh` 的版本（海外通→外网，否则国内通→联网）。

**为什么“安装实验驱动”按钮不可用？**
当前内核缺少 headers、系统未安装 DKMS、检测到厂商 LED 模块，或已有非本应用管理的 `led-ugreen`。这些情况下继续使用内置 CLI 即可，应用不会为启用实验功能自动修改系统编译环境。

## 许可证

本项目自有代码采用 [GNU Affero General Public License v3.0 only](LICENSE)（`AGPL-3.0-only`）授权。

如果修改后的版本通过网络向用户提供服务，需要按 AGPL-3.0 第 13 条向这些用户提供对应源代码。`ugreen_leds_cli`、直接集成的 `UGREEN-NAS-Hardware`（MIT）、`led-ugreen` 驱动源码、Bootstrap Icons 以及其他第三方组件继续适用各自的上游许可证，不因本项目采用 AGPL-3.0 而被重新授权。上游硬件项目许可证副本位于 `app/server/vendor/UGREEN-NAS-Hardware/LICENSE`，驱动许可证副本位于 `app/server/driver/led-ugreen/LICENSE`。
