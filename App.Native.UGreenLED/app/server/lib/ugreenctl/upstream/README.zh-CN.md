# ugreenctl

ugreenctl 是一个面向绿联 NAS 的开源、用户态、插件化硬件管理工具。

[English](README.md) · [兼容性目录](docs/COMPATIBILITY.zh-CN.md) ·
[Compatibility catalog](docs/COMPATIBILITY.md)

`Almighty` 分支新增原生 LED 控制、物理盘位映射及 `ugreen_leds_cli` 参数兼容入口。
快速开始与逐机型限制见 [灯光与盘位说明](docs/LED_CONTROL.zh-CN.md)。
各 Linux NAS 的运行库、持久目录和服务要求见 [部署指南](docs/LINUX_DEPLOYMENT.zh-CN.md)。

它按照 NAS 机型加载独立的 .so 插件。已实机验证的机型开放正常写入；仅完成固件逆向
的机型只能在保留全部保护并明确确认风险时开放受限写入。models/ 中存在某机型的插件，
不代表该机型已被支持。

## 当前支持情况（已实现的固件路径）

“固件依据”是代码已经按该原厂固件实现的路径，不是“升级到这个版本以外也一定可用”的
承诺。实机验证与固件逆向是两种不同状态：看到“需确认”时，请先只读、预览，再决定是否写入。

| 精确机型（插件） | 已实现的原厂固件依据 | 已接入的功能 | 当前状态 |
| --- | --- | --- | --- |
| DX4600 / DX4600+ / DX4600 Pro (`dx4600`) | 官方 UGOS Pro `1.17.0.0095`，Build `20260630.111337`，内核 `6.12.30+` | `sys` 风扇、来电启动、WOL、计划唤醒 | 已按固件实现，尚无实机写入验证；PWM 安全范围为 `40..255`，写入需 `--force --apply`。 |
| DXP4800 Plus / DXP4800 Pro (`dxp4800plus`) | `1.17.0.95` | CPU/系统风扇读取与 PWM、来电启动策略、WOL、计划唤醒 | 常规 hwmon 风扇与来电启动已验证；直控兜底、WOL 和计划唤醒仍需 `--force --apply`。 |
| DXP4800 (`dxp4800`) | UGOS Pro `1.17.0.0095`，Build `20260630.111337`，内核 `6.12.30+` | 系统风扇、来电启动、WOL、计划唤醒 | 已按固件实现，尚无实机写入验证；所有写入均需 `--force --apply`。 |
| DXP4800S (`dxp4800s`) | UGOS Pro `1.17.0.0095`，Build `20260630.111337`，内核 `6.12.30+` | `sys` 风扇、来电启动、WOL、计划唤醒 | 已按固件实现，尚无实机写入验证；PWM 安全范围为 `40..255`，写入需 `--force --apply`。 |
| DXP480T Plus (`dxp480tplus`) | UGOS Pro `1.17.0.95`，Build `20260630.111337`，内核 `6.12.30+` | CPU/系统风扇读数、`cpu`/`all` PWM、来电启动、WOL、计划唤醒 | CPU 写入已有实机反馈；系统风扇对 (`all`) 的更正固件映射、直控兜底、WOL 和计划唤醒仍待受控实机验证。 |
| DXP6800 Pro (`dxp6800pro`) | UGOS Pro `1.17.0.0095`，Build `20260630.111337`，内核 `6.12.30+` | CPU/成对系统风扇、来电启动、WOL、计划唤醒 | 已按固件实现，尚无实机写入验证；所有写入均需 `--force --apply`。 |
| DXP2800 / DXP8800 Plus | 上游 LED 协议记录 | 型号识别与有条件的内置 LED 档案 | 风扇/电源插件仍为占位；LED 写入为实验性。 |

风扇/电源写入要求精确 DMI；ARM 灯光使用经固件证实的精确设备树型号、
compatible 和控制器身份。新增 LED 命令使用独立的内置协议档案，
目前为实验性；不能根据“有插件”推断 LED 或其他未列功能可用。完整证据和保护条件以
[models/compatibility.json](models/compatibility.json) 与
[硬件支持说明](docs/HARDWARE_SUPPORT.md) 为准。
全机型扩展仍在集成，当前逐款证据见
[灯光取证](docs/ALL_MODELS_LED_EVIDENCE.zh-CN.md)与
[盘位取证](docs/ALL_MODELS_DISK_EVIDENCE.zh-CN.md)。ARM 在没有原厂 GPIO LED
驱动时需要显式运行 `ugreenctl-ledd` 保持 GPIO 线路所有权，不会悄悄后台启动服务。

## 构建和安装

在 x86/x86_64 或 ARM64 Linux（例如 NAS 的 SSH 终端）中执行。
ARM64 不提供 x86 Super I/O 端口访问；能够编译不代表未建模功能可用：
TrueNAS SCALE 请使用部署指南的数据集与预编译方式，不在受保护系统上安装编译依赖。

    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build
    ctest --test-dir build --output-on-failure
    sudo cmake --install build

也可以使用一键安装脚本：

    sh ./scripts/install.sh --install-deps

该选项会通过系统包管理器安装 CMake 和 C 编译器，再构建并安装到 /usr/local。
如果依赖已存在，直接运行：

    sh ./scripts/install.sh

## 直接运行（不安装）

    sh ./scripts/run.sh models
    sudo sh ./scripts/run.sh info
    sh ./scripts/run.sh fan set cpu 120
    sudo sh ./scripts/run.sh --apply fan set cpu 120

run.sh 会在 build/ 中构建程序，并自动传入正确的插件目录。

## 命令怎么用：功能、参数与输出

命令的通用格式是 `ugreenctl [选项] <命令> [参数]`。尖括号表示“需要替换成你自己的值”，
例如 `fan set cpu 120` 里的 `cpu` 和 `120` 就是两个参数。旧风扇/电源命令的全局选项写在命令前；
新增 LED/盘位命令的 `--json`、`--apply`、`--force` 可放在命令前后。

第一次使用时，按下面顺序操作即可：

```sh
# 1. 看这个安装包包含哪些机型；不读写硬件。
ugreenctl models

# 2. 确认程序在这台 NAS 上识别到的型号、风扇和电源策略；不写硬件。
sudo ugreenctl info

# 3. 单独查看风扇。确认风扇 ID 后，再考虑下一步写入。
sudo ugreenctl fan status
```

如果第 2 步提示 DMI 型号不匹配或没有插件，请停止对应的风扇/电源操作；
LED/盘位命令使用独立内置档案，可先查看 `led list`。不要通过 `--model` 强行指定相近机型。

### 选项是什么

| 选项 | 什么时候用 | 参数怎么填 |
| --- | --- | --- |
| `--apply` | 真的要修改风扇、电源、WOL 或计划唤醒时。没有它只会预览。 | 不带参数。 |
| `--force` | 支持表写着“固件实现、待实机验证”的写入路径需要它。 | 不带参数；它只是风险确认，不会关闭任何安全检查。 |
| `--plugin-dir <目录>` | 直接运行 `./build/ugreenctl` 时指定插件目录。`scripts/run.sh` 会自动传入。 | 例如 `--plugin-dir ./build/models`。安装到系统后通常不用写。 |
| `--model <插件 ID>` | 仅用于排查插件加载问题。 | 例如 `--model dxp4800plus`。本机 DMI 产品名仍必须精确匹配，不能用它跨机型控制。 |

### 每条命令做什么

| 命令 | 功能 | 参数怎么填 | 成功时会看到什么 |
| --- | --- | --- | --- |
| `models` | 列出程序内置的机型插件。 | 无。 | 每行是“插件 ID、机型名称、能力”。不访问硬件。 |
| `info` | 查看本机识别的机型、控制器、来电策略、WOL 和风扇概要。 | 无。 | `model:`、`controller:`、`startup:`、`wol:` 和若干 `fan ...` 行。 |
| `thermal status` | 查看 CPU、硬盘、SSD 温度，主要供温控守护或脚本使用。 | 无。 | 一行 `cpu_celsius=... hdd_celsius=...`；`-1` 表示该传感器不可用。 |
| `fan status` | 查看每个风扇的转速、已知 PWM 和模式。 | 无。 | 例如 `cpu: pwm=120 mode=manual tach=... rpm=...`。 |
| `fan set <风扇 ID> <PWM>` | 手动设定一个风扇或风扇组的速度。 | 风扇 ID 见下表；PWM 建议填 `40..255` 的整数，数值越大转得越快。它不是百分比，不能用 `50%`。 | 预览时显示 `dry-run`；真实写入成功显示 `<风扇 ID> fan PWM set to <PWM>`。 |
| `power startup get` | 查看断电后恢复供电时的开机策略。 | 无。 | `on`、`off`、`restore` 或 `unknown`。 |
| `power startup set <策略>` | 修改断电恢复后的开机策略。 | `<策略>` 只能是 `on`（总是开机）、`off`（保持关机）或 `restore`（恢复断电前状态）；`last` 等同于 `restore`。 | 写入成功显示 `startup policy set to <策略>`。 |
| `network wol get` | 查看网络唤醒是否开启。 | 无。 | `on`、`off` 或 `unknown`。 |
| `network wol set <on|off>` | 开启或关闭 Magic Packet 网络唤醒。 | 只能填 `on` 或 `off`。 | 写入成功显示 `Wake-on-LAN policy set to <策略>`。 |
| `power rtc-wake get` | 查看下一次定时唤醒。 | 无。 | UTC Unix 时间戳，例如 `1893452400`。 |
| `power rtc-wake set <时间戳>` | 设置下一次定时唤醒。 | 填大于 0 的 UTC Unix 时间戳，不是 `2026-...` 这样的日期文字。 | 写入成功显示 `RTC wake set to <时间戳>`。 |
| `power rtc-wake clear` | 取消已设置的定时唤醒。 | 无。 | `RTC wake cleared`。 |

风扇 ID 不能混用：DXP4800 Plus/Pro 是 `cpu`、`sys`；DXP4800 和 DXP4800S
只有 `sys`；DXP6800 Pro 是 `cpu`、`sys`；DXP480T Plus 是 `cpu`、`all`（两个系统
风扇一起设置）。`led list/status/set/on/off/identify` 和 `disk list/map/locate`
的参数、JSON、预览与实验性写入条件见 [LED 文档](docs/LED_CONTROL.zh-CN.md)。

### 先读取，再预览，最后写入

```sh
# 只读命令：结果写入标准输出。
sudo ugreenctl info
sudo ugreenctl fan status
sudo ugreenctl power startup get
sudo ugreenctl network wol get

# 预览：命令成功但不会修改硬件。
ugreenctl fan set cpu 120
# dry-run: would set the fan PWM
# rerun with --apply to write hardware state

# 已验证路径的实际写入（通常需要 root 或 CAP_SYS_RAWIO）。
sudo ugreenctl --apply fan set cpu 120
# cpu fan PWM set to 120

# 固件逆向写路径还需要显式确认。
sudo ugreenctl --force --apply network wol set on
# Wake-on-LAN policy set to on
sudo ugreenctl --force --apply power rtc-wake set 1893452400
# RTC wake set to 1893452400
```

成功退出码为 `0`。参数错误、不支持的功能、机型不匹配、权限不足或任一安全检查
失败时，程序会返回非零退出码并向标准错误输出 `error: ...`。除上述单行
`thermal status` 格式外，不应把面向人的状态文本当作稳定 API 解析。

## 按机型执行写入

默认所有写命令都只是预览；只有带上 `--apply` 才会写硬件。`--force` 只表示确认使用
尚未实机验证的固件逆向路径，不会绕过精确 DMI、原厂驱动冲突或 IT8613 芯片 ID 检查。

DXP4800S 只有一个已恢复的 `sysfan1` 通道，插件命名为 `sys`。当前 PWM 和模式保持
`unknown`，普通写入只开放原厂曲线已经使用的 `64..255`：

    sudo ugreenctl --force --apply fan set sys 120
    sudo ugreenctl --force --apply power startup set restore

DX4600、DX4600+、DX4600 Pro 使用各自固件证据对应的单风扇映射，并统一提供
受保护的 `sys` 目标。只有这三个精确 DMI 名称会选择 `dx4600` 插件，不使用前缀匹配：

    sudo ugreenctl --force --apply fan set sys 120
    sudo ugreenctl --force --apply power startup set restore
    sudo ugreenctl --force --apply network wol set on

`stock-4600` 配置通过 `ugreenctl-fand` 保留官方守护进程默认 `mode=2` 的实际阈值和
PWM 点，同时继续执行本项目禁止停转的安全下限。LED、蜂鸣器与 SATA MMIO 操作均未开放。

在飞牛 OS 下，WOL 不依赖字面上的 `eth0`/`eth1`。两个原厂名称都不存在时，
DX4600 路由会枚举物理 PCI 有线网卡，排除虚拟、bond 和 bridge 设备，要求符合
官方双网口拓扑，按 PCI 地址排序，并检查 Magic Packet 能力及写后状态；物理网卡
数量不是两张时直接拒绝。

DXP6800 Pro 已从固件恢复、但尚未完成实机写入验证。它提供原厂 CPU 路径以及原厂的
成对系统风扇路径，两者均必须使用 `--force --apply`：

    sudo ugreenctl --force --apply fan set cpu 120
    sudo ugreenctl --force --apply fan set sys 120
    sudo ugreenctl --force --apply power startup set restore

`sys` 会以同一 PWM 写入两个已经由固件证实的系统风扇输出。原厂 `hwmonitor` 的温控
曲线属于用户态服务，不等同于硬件自动模式。寄存器映射和验证限制见
[DXP6800_PRO_REVERSE_ENGINEERING.md](docs/DXP6800_PRO_REVERSE_ENGINEERING.md)。

原厂自动模式由用户态 `hwmonitor` 根据温度写 PWM，不是 IT8613 硬件自动模式。项目提供的
`ugreenctl-fand` 是受保护的软件曲线守护：它读取 Linux 温度，并通过 `ugreenctl` 提交 PWM
更新。配置输入、启动命令和机器可读状态文件输出见
[FAN_CURVE.md](docs/FAN_CURVE.md)。

DXP480T Plus 的 `cpu` 写入已有实机反馈。`all` 会按照已经实现的原厂系统风扇对事务写入，
但其更正映射仍等待受控实机验证。正常 hwmon 写入使用 `--apply`，并继续保留精确 DMI
匹配、原厂驱动冲突、IT8613 芯片身份和最低 PWM 检查：

    sudo ugreenctl --apply fan set cpu 120
    sudo ugreenctl --apply fan set all 120

hwmon 存在时，`all` 对应原厂 `set` 命令，按原厂顺序写入两个系统风扇通道。若为释放通道而
卸载 it87、`name=it8613` hwmon 节点不存在，DXP480T Plus 的直控 `cpu` 使用控制寄存器
`0x17`、占空比寄存器 `0x73`；直控 `all` 依次写入系统风扇对 `0x16/0x6b`、`0x1e/0x7b`。
三路转速仍会报告，但插件不会开放单独的系统风扇写操作。直控路径始终需要
`--force --apply`、原厂接口与 it87 冲突检查、芯片身份检查和进程锁；更正后的系统风扇对
直控映射仍等待实机验证。

## 安全说明

来电策略写入和跨重启恢复是两件事。`ugreenctl power startup set` 只写入并回读当前寄存器；
需要保存选择及在服务启动/停止时恢复，请使用[来电策略持久化说明](docs/AC_RECOVERY_PERSISTENCE.zh-CN.md)。
DXP4800 Plus / Pro 等已支持机型不能仅靠替换二进制获得应用生命周期修复。
当前25款状态见[开发状态](docs/ALMIGHTY_STATUS.zh-CN.md)，完整源码构建及可选交叉验证见
[构建复现说明](docs/BUILD_REPRODUCIBILITY.zh-CN.md)。

- 所有 IT8613 插件发现原厂 `/proc/it86` 驱动仍在运行时都会拒绝访问，避免并发操作
  寄存器。
- 每次控制器访问都会使用 /run/ugreenctl-it8613.lock 进行进程锁定。
- 直接端口 I/O 需要 root 或 CAP_SYS_RAWIO。
- 手动 PWM 会关闭对应通道的硬件自动位。DX4600 与 DXP4800S 的原厂自动控制是
  软件守护进程，手动接管前必须停止或替代原厂守护，并保持独立温度监控。

如果你在原厂 NAS 固件之外运行该工具，且原厂模块已加载，先卸载它：

    sudo modprobe -r ug_it86x_sio       # DX4600 / DXP4800S / DXP4800 分支
    sudo modprobe -r ug_it86x_cpufan    # DXP4800 Plus / DXP480T / DXP6800 分支

## 后续增加机型

机型兼容性以 [models/compatibility.json](models/compatibility.json) 为发布目录，
每个机型都必须记录：

- 固定的插件 ID 和精确 DMI 产品名；
- 支持等级：仅机型档案、只读或已支持；
- 已验证能力、控制器和固件版本；
- 已知冲突、限制条件和可复现实机证据。

新增机型前请使用 [新机型接入模板](docs/NEW_MODEL_TEMPLATE.md)。禁止因为外观、
CPU 或主板“看起来相近”就复用另一个机型的写寄存器映射。

## 插件 ABI

需要风扇模式控制的机型可导出 ABI version 3，同时保留 ABI version 2 兼容入口：

    const struct ugreenctl_plugin *ugreenctl_plugin_v3(void);

    const struct ugreenctl_plugin *ugreenctl_plugin_v2(void);

ABI 定义在 include/ugreenctl.h。核心程序优先加载 ABI version 3，无法找到时回退到
ABI version 2，并通过 DMI 产品名或 --model 选择机型。

## 许可、原厂固件与证据

本仓库自己的源代码和文档采用 [MIT 许可证](LICENSE)。这项许可证只适用于本仓库的内容，
不适用于 UGREEN/绿联的固件、驱动、商标或其他原厂内容。

原厂固件仅用作净室分析的证据：项目根据可观察到的行为、接口和寄存器映射自行实现，
不链接、不包含也不分发原厂驱动源码、二进制或镜像。使用本项目不代表获得原厂固件的
复制、分发或修改授权。

每个已接入机型对应的固件版本和验证状态见上方“当前支持情况”；详细证据见
[硬件支持说明](docs/HARDWARE_SUPPORT.md)、
[兼容性目录](models/compatibility.json) 及机型逆向记录。项目与 UGREEN/绿联没有隶属或
官方背书关系。
