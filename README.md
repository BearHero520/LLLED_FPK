# 绿联 LED 灯控（飞牛 fnOS 原生应用）

在飞牛 **fnOS** 上控制绿联 NAS 机箱 LED。应用内置基于上游 `ugreen_leds_controller` 固定提交构建的 `ugreen_leds_cli`，支持 `0x3a` legacy / SMBus block-write 协议、CLI / sysfs 后端、DXP480T N76E003 电源灯后端、机型预设以及 2/4/6/8 盘位映射。

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

应用 ID：`App.Native.UGreenLED` · 当前版本：**1.8.7**

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
| BIOS 控制 | 直接集成 [UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 的 `ugreenctl`；DXP4800、DXP4800 Plus / Pro、DXP4800S、DXP480T Plus、DXP6800 Pro 优先经 `it87` hwmon 控制；全部精确映射机型均支持 eth0/eth1 网络唤醒，以及“安全关机 + RTC 定时开机”计划 |
| 自动温控 | 使用上游 `ugreenctl-fand` 软件守护程序读取 CPU、HDD、NVMe 温度并通过 `ugreenctl` 写入 PWM；DXP4800S 提供已还原的原厂兼容阈值，其他支持机型提供稳定自定义曲线 |
| Web 配置 | 飞牛桌面 iframe 内配色预设、保存后自动进入智能模式 |
| 分级诊断日志 | 统一记录服务、CGI、LED、BIOS、驱动与安装事件，包含请求 ID、源码位置、耗时、返回码和错误上下文，并自动脱敏、截断和轮转 |

> 硬件限制：灯处于 **off** 时不能直接改色，须先 `-on` 再设色。`app/server/lib/led_api.sh` 已自动处理。

> 请勿与 **LLLED 命令行版** 或其它抢灯权的应用同时运行，只保留一个控制端。

## 打包与安装

### 环境要求

- fnOS **≥ 0.9.27**，平台 **x86**
- 安装需 **root**（访问 I2C）；FPK 已内置并校验 `ugreen_leds_cli`，安装回调会安装缺少的 `i2c-tools` / `hdparm` 并加载 `i2c-dev`
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

`ugreenctl` 与 DXP4800 / DXP4800 Plus / DXP4800S / DXP480T Plus / DXP6800 Pro 机型插件由 CI 在 Ubuntu 22.04 构建并随 FPK 分发；Windows 本地检出请通过 GitHub Actions 打包。`scripts/build_fpk_remote.py` 会在 NAS 端按需安装 CMake 和编译器再构建它。硬件源代码以 Git 子模块固定在 `App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware`，克隆时请使用 `git clone --recurse-submodules`；升级时同步更新该子模块提交。

输出目录为 `dist/`，其中包括：

- `App.Native.UGreenLED-<版本>.fpk`：带版本号的发布文件。
- `App.Native.UGreenLED.fpk`：供应用更新检查使用的固定文件名。
- `App.Native.UGreenLED-<版本>.fpk.sha256`：完整性校验文件。

构建器会生成 `app.tgz`，把它的 MD5 写入 FPK 内部 `manifest` 的 `checksum` 字段，并在完成后重新读取安装包校验结构。

### 自动创建 GitHub Release

`.github/workflows/release.yml` 会在推送 `v*.*.*` 标签时自动构建并发布 Release。标签版本必须与 `App.Native.UGreenLED/manifest` 中的 `version` 一致：

```bash
git tag v1.8.7
git push origin v1.8.7
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
| 实验性 | DXP4800S（BIOS 控制固件逆向）、DXP4800 GT、iDX6011 / iDX6011 Pro |
| 待验证 | DXP2800 GT、DXP4800 Pro |
| 受限支持 | DXP480T / DXP480T Plus（独立 N76E003 控制器，仅红/白电源灯） |

DXP4800 GT 和 iDX6011 系列使用 `smbus-block`；iDX6011 Pro 的第二网络灯与六个硬盘灯会通过逻辑 LED 别名校正。实验性机型建议先在“实验室”逐灯验证。

DXP480T 系列与其他机型不同：它没有硬盘灯和网络灯，也不使用 `0x3a` RGB MCU。应用层只会调用内置 `ugreen_leds_cli` 的 `--dxp480t-power-probe` 和 `--dxp480t-power`，绝不直接访问 I²C。CLI 依据已验证的 [DXP480T Plus 控制方法](https://github.com/miskcoo/ugreen_leds_controller/issues/6#issuecomment-2156807225)，仅在 DMI 匹配 DXP480T、检测到 Intel I801 SMBus，并在 `0x31` 或 `0x26` 读到 `0x5a/0x5b = 0xa5/0xb5` 后执行写入；每个命令都会先清除 `0xa0=1`、`0xa0=2`，再以 `0xb1=1`（红）或 `0xb1=2`（白）选择通道，并用 `0x50` / `0x51` 设置常亮、快闪、慢闪或呼吸。关闭使用原协议的 `0xb1=3`。不会为该档案安装通用 `led-ugreen` DKMS 驱动。检测到专用后端后，“灯光设置”页面会自动替换为 480T 简化控制页；“网络活动”模式会复用电源灯，在总上传与下载速度超过页面设置的阈值后慢闪，达到阈值 4 倍后快闪。其他机型继续使用原来的完整 RGB 设置页。

BIOS 控制直接集成 [BearHero520/UGREEN-NAS-Hardware](https://github.com/BearHero520/UGREEN-NAS-Hardware) 的 `ugreenctl` 与 DXP4800 / DXP4800 Plus / DXP4800S / DXP480T Plus / DXP6800 Pro 插件（MIT）。该项目负责精确 DMI 匹配、IT8613 身份及原厂驱动冲突检查、进程锁和寄存器映射；本应用负责 Web API 与页面展示。DXP4800、4800S、4800 Plus / Pro 与 6800 Pro 使用动态 `name=it8613` hwmon 节点。来自官方固件的 `hwmonitor`、`hwmonitor-480t` 与 `hwmonitor-amd` 都明确映射 eth0/eth1 的 `ethtool` 魔术包唤醒，因此这六个精确 DMI 机型均可设置并回读网络唤醒；它不写 Super I/O 寄存器。官方 `TimedShutdown` / `OnSched` 路径也已接入为“定时安全关机 + RTC 定时开机”：关机前必须成功重设下一次 RTC 唤醒，失败即取消关机。全部固件逆向写入均需页面显式风险确认，并附加 `--force --apply`、芯片 ID、进程锁和回读保护；仍应先在实机验证。DXP480T Plus 的原厂驱动将 CPU PWM 映射到 `0x17/0x73`，并由 `set` 事务按 `0x16/0x6b`、`0x1e/0x7b` 成对写入系统风扇 1/2；页面不提供 sys1/sys2 单独写入。RPM 的 `0x0fff`/`0xffff` 无效值会显示为 0。映射来自该固件静态逆向，仍需实机验证；普通 DXP480T 不会因手动机型档案选择而绕过精确 DMI 保护。

DXP4800S 仅匹配精确 DMI `DXP4800S`。可读取 `sysfan1` 转速与当前 PWM，手动 PWM 只开放 `sys` 与 `40..255`，来电启动支持 `on/off/last`；只有手动模式会被报告为已知，原厂自动调速由 `hwmonitor` 用户态守护进程实现。由于这些写入来自 UGOS Pro `1.17.0.0095` 固件逆向且尚无实机验证，网页会要求显式风险确认，后端同时附加 `--force --apply`，并继续执行芯片 ID、原厂驱动冲突和进程锁保护。

自动温控同样是软件守护进程，不会将 `pwm*_enable=2` 标示为“原厂自动”。守护程序只调用已内置的 `ugreenctl`，每次写入继续经过精确 DMI、原厂控制器互斥、IT8613 锁、最低 PWM 与回读保护。DXP4800S 的原厂兼容方案采用已还原的 CPU/HDD/NVMe 阈值和 64/128/204/255 PWM 点，但安全实现不会执行停转；DXP4800 Plus / Pro、DXP480T Plus 和 DXP6800 Pro 的具体原厂阈值尚未作为经过验证的数据发布，因此页面只提供明确标识的稳定自定义曲线。CPU 温度缺失会保护性满速，用户可选择在缺少全部 HDD/NVMe 温度时同样满速；降速延迟用于避免频繁升降速。

DXP6800 Pro 仅匹配精确 DMI `DXP6800 Pro`。UGOS Pro `1.17.0.0095` 的 `ug_it86x-cpufan` 模块证明其使用 IT8613：可读取 CPU、系统风扇 1、系统风扇 2；CPU 使用独立 PWM，`sys` 写入会按原厂寄存器顺序同步系统风扇 1/2。页面不会提供单独的 sys1/sys2 写入。来电启动支持 `on/off/last`。这些映射尚未实机验证，因此所有写入均需显式风险确认，并附加 `--force --apply`、最低 PWM 40、精确 DMI、芯片 ID、原厂驱动冲突、进程锁和回读保护。

如果 LED 硬件或 `i2c-tools` 暂时不可用，应用仍会完成安装并开放 Web 管理页，不会因为灯控后端探测失败而让 fnOS 报整包安装失败。后台服务会继续重试，并在硬件状态区域显示诊断信息。

### CLI 与实验驱动

- `backend=auto`：检测到可用的 `led-ugreen` sysfs 设备时使用驱动，否则使用内置 CLI。
- `backend=cli`：强制使用内置 CLI；如果内核驱动仍占用 MCU，会拒绝启动，避免同时访问 I2C。
- `backend=sysfs`：强制使用内核驱动；不可用时明确报错。
- DXP480T 系列在 `auto` / `cli` 设置下会自动使用 `ugreen_leds_cli` 内置的专用 `power-0x26` 子命令，不调用通用 RGB 命令。
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

所有响应都会返回 `X-Request-ID`，并按结果使用 2xx / 4xx / 5xx HTTP 状态；错误响应会把同一状态码、请求 ID、脱敏客户端地址和截断后的 User-Agent 写入 `app.log` 便于关联排查。

| 路径 | 说明 |
|------|------|
| `/status` | 守护进程与 LED 状态 |
| `/mapping` | 硬盘映射表 |
| `/settings` | GET / POST 配置 |
| `/hardware/status` | 机型档案、协议、后端、DKMS 与内核 headers 状态 |
| `/bios/status` | DXP4800、DXP4800 Plus / Pro、DXP4800S、DXP480T Plus、DXP6800 Pro 的 IT8613、风扇、来电启动、网络唤醒与定时开关机状态及写入能力标记 |
| `/bios/fan?channel=cpu\|sys\|all&pwm=40..255` | POST：设置风扇 PWM；DXP4800 / 4800S 仅允许 `sys`；480T 仅允许 `cpu` / `all`；6800 Pro 仅允许 `cpu` / 成对 `sys`（同步 sys1/sys2）；所有已映射机型的固件逆向写入均要求 `confirm=firmware-reversed` |
| `/bios/fan-curve` | GET：读取自动温控曲线状态；POST `action=start`：保存并启动与精确 DMI 匹配的 `stock-4800`、`stock-4800s`、`stock-4800plus`、`stock-480tplus`、`stock-6800pro` 或 `custom` 软件曲线；POST `action=stop`：停止并禁用开机恢复。受保护写入仍要求现有风险确认。 |
| `/bios/startup?policy=on\|off\|last` | POST：设置来电启动策略；DXP4800、4800S 与 6800 Pro 写入要求 `confirm=firmware-reversed` |
| `/bios/wol?policy=on\|off` | POST：精确 DMI `DXP4800`、`DXP4800S`、`DXP4800 Plus`、`DXP4800 Pro`、`DXP480T Plus`、`DXP6800 Pro`；设置 eth0/eth1 魔术包网络唤醒并回读校验，要求 `confirm=firmware-reversed` |
| `/bios/power-schedule` | POST：`enabled=true\|false`、`days=1..7`、`wake_time=HH:MM`、`shutdown_time=HH:MM`；通过上游 RTC `wakealarm` 设定下一次开机并由 cron 执行安全关机，要求 `confirm=firmware-reversed` |
| `/power26/apply` | POST：为 DXP480T / Plus 应用红白电源灯颜色、灯效或关闭 |
| `/driver/install` | POST：确认后安装或重建本应用管理的实验驱动 |
| `/driver/unload` | POST：卸载本应用管理的驱动并切回 CLI |
| `/update/check?force=1` | 检查 GitHub 最新 Release；`force=1` 忽略 6 小时缓存 |
| `/mode?mode=off\|on\|smart` | POST：切换模式 |
| `/daemon/start` · `/daemon/stop` | POST：启停守护进程 |
| `/remap` | POST：重新 HCTL 映射 |
| `/lab/mapping/status` | 查询实验室检测状态、盘位和硬盘清单 |
| `/lab/mapping/start` · `/lab/mapping/highlight` | POST：开始检测并逐 LED 通道闪烁识别 |
| `/lab/mapping/save` | POST：保存按硬盘序列号绑定 |
| `/lab/position/save` | POST：保存按 HCTL 位置绑定 |
| `/lab/mapping/cancel` | POST：放弃当前检测 |
| `/lab/mapping/reset` | POST：恢复自动 HCTL 映射 |
| `/led/set?led=disk1&r=255&g=0&b=0` | POST：手动设色 |
| `/led/off?led=disk1` | POST：手动关闭单个灯 |
| `/logs?level=all&lines=500` | 读取受限的应用诊断日志，固定来源、最多 1000 行 / 128 KiB 日志内容 |
| `/hardware/diagnostics` | GET：即时生成硬件采集与最近应用日志组成的一键下载诊断包 |
| `/logs/config?level=debug\|info\|warn\|error` | POST：切换日志记录级别并通知守护进程重载 |
| `/logs/clear?confirm=clear-logs` | POST：清空 `app.log` 及轮转历史 |
| `/logs/client` | POST：接收受限、脱敏并限频的 Web 运行时错误，关联页面请求 ID |

Web 管理页使用 fnOS CGI，不再自动启动旧版 5088 端口服务，减少无鉴权端口暴露和无效后台进程。

“设备与高级 → 应用更新”会在打开管理页时检查 GitHub Release。发现新版后，用户可以查看更新说明并下载固定名称的 FPK；为避免依赖未公开的 fnOS 内部安装接口，应用不会静默安装，仍需在应用中心手动确认升级。

## 日志与排错

应用日志统一保存在持久化数据目录，不会写入升级时会被替换的包目录：

```text
${TRIM_PKGVAR:-/var/apps/App.Native.UGreenLED/var}/log/
├── app.log          # 服务、守护进程、CGI、LED、BIOS、配置和驱动摘要
├── app.log.1 ...    # 自动轮转历史
├── driver.log       # DKMS / 内核驱动操作的原始命令输出
├── install.log      # 依赖安装、CLI 下载和校验的原始输出
├── daemon-launch.log # 守护进程启动阶段的原始输出
├── daemon-runtime.log # 守护进程异常退出时的运行期原始输出
└── service-control.log # Web 启停后台服务时的原始输出
```

每条 `app.log` 都带有时间、级别、组件、PID、事件名、源码位置；Web/API 操作还会带请求 ID、HTTP 状态和耗时。底层 LED CLI、I²C、sysfs、BIOS 与驱动失败会记录返回码和截断后的 stderr，方便从一次页面报错追到具体硬件命令。浏览器运行时异常，以及网络失败、无效响应等缺少服务端结构化日志的页面错误也会限频上报，并保留关联请求 ID。

默认级别为 `INFO`：记录启动停止、配置/模式/硬件状态变化、写操作和全部警告错误，不会每 5 秒记录一次稳定守护循环，也不会把每 10 秒的页面轮询写入 INFO。需要深度排错时，可在 **设备与高级 → 应用诊断日志 → 记录级别** 临时切换为 `DEBUG`；排查结束后建议恢复 `INFO`。

默认 `app.log` 达到 5 MiB 后轮转并保留 5 份历史。对应配置位于 `settings.conf`：

```ini
[logging]
level=info
max_size_kb=5120
retained_files=5
```

Web 日志面板只读取固定的 `app.log`，限制为最近 1000 行和 128 KiB 日志内容，不接受任意文件路径，也不会直接暴露驱动编译原始输出。日志字段会移除换行和控制字符，并自动隐藏 password、token、secret、Authorization、Cookie 等敏感值；但 DEBUG 仍可能包含设备路径、机型和硬件状态，分享前请先检查内容。

SSH 常用排错命令：

```bash
LOG=/var/apps/App.Native.UGreenLED/var/log

# 最近 200 行，以及最近的警告/错误
sudo tail -n 200 "$LOG/app.log"
sudo grep -E '\[(WARN|ERROR)\]' "$LOG/app.log" | tail -n 200

# 实时跟踪统一日志；驱动、安装或服务启停问题再查看原始输出
sudo tail -F "$LOG/app.log"
sudo tail -n 300 "$LOG/driver.log"
sudo tail -n 300 "$LOG/install.log"
sudo tail -n 300 "$LOG/daemon-launch.log"
sudo tail -n 300 "$LOG/daemon-runtime.log"
sudo tail -n 300 "$LOG/service-control.log"
```

需要让远程测试者采集 DXP480T Plus 的 `it87` 绑定、hwmon 节点、I/O 端口、
I²C/SMBus、DKMS 来源及最近应用日志时，只需在 **设备与高级 → 应用诊断日志**
点击 **一键下载诊断包**，浏览器会直接下载可分享的文本文件，不需要 SSH 或额外命令。
采集器不会加载或卸载模块，不会执行 PWM、来电策略或 I²C 数据写入，也不会收集
硬件序列号、UUID、IP 或 MAC；DXP480T 系列的 `0x31` / `0x26` 探测仅执行定点读取，
不使用强制访问。

页面错误会显示“请求 ID”。可直接在日志面板搜索该 ID，把同一次请求的入口、底层命令和最终错误串联起来。

## 常见问题

**安装报「应用包不符合系统要求」**  
确认 `app/ui/config` 为**单个 JSON 文件**，不是目录；`manifest` 中 `platform=x86`、`os_min_version` 与系统一致。

**打开应用闪退**  
多为路径问题：运行时代码会在 `server/` 与 `target/server/` 间自动探测，请使用本仓库最新版。

**网络灯一直断网**  
请升级至含新版 `net_state.sh` 的版本（海外通→外网，否则国内通→联网）。

**为什么“安装实验驱动”按钮不可用？**
当前内核缺少 headers、系统未安装 DKMS、检测到厂商 LED 模块，或已有非本应用管理的 `led-ugreen`。这些情况下继续使用内置 CLI 即可，应用不会为启用实验功能自动修改系统编译环境。

**日志在哪里，为什么看不到 DEBUG？**

常见路径是 `/var/apps/App.Native.UGreenLED/var/log/app.log`。默认只写 INFO 及以上级别；在“设备与高级 → 应用诊断日志”切换为 DEBUG 后会记录只读 API、后端选择和成功的底层 LED 操作。切换会立即写入配置并向守护进程发送重载信号。

**日志目录不可写或日志增长太快怎么办？**

日志失败不会改变应用启停返回码，也不会污染 CGI JSON；请检查应用数据目录权限与可用空间。增长过快时先恢复 INFO，再按需降低 `max_size_kb` / `retained_files`，随后重启应用或再次切换日志级别使守护进程重载配置。

## 许可证

本项目自有代码采用 [GNU Affero General Public License v3.0 only](LICENSE)（`AGPL-3.0-only`）授权。

如果修改后的版本通过网络向用户提供服务，需要按 AGPL-3.0 第 13 条向这些用户提供对应源代码。`ugreen_leds_cli`、直接集成的 `UGREEN-NAS-Hardware`（MIT）、`led-ugreen` 驱动源码、Bootstrap Icons 以及其他第三方组件继续适用各自的上游许可证，不因本项目采用 AGPL-3.0 而被重新授权。上游硬件项目许可证副本位于 `app/server/vendor/UGREEN-NAS-Hardware/LICENSE`，驱动许可证副本位于 `app/server/driver/led-ugreen/LICENSE`。
