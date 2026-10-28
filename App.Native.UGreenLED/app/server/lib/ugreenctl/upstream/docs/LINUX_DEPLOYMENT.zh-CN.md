# Linux NAS 部署

> 2026-10-27 更新：N76 增加显式 `--n76-direct BUS:ADDR` 实验直控，用户接受真实输出未验证的限制；模式回读保留，其余字段保持 unknown。下文原厂驱动依赖及拒绝裸写描述记录此前的严格回读策略，当前例外和范围以 [N76 直控说明](N76_DIRECT_CONTROL.zh-CN.md) 为准。无驱动编译功能。

本指南面向 fnOS、Debian/Ubuntu、PVE、Unraid、TrueNAS SCALE。当前 25 款整合仍未完成，
具体机型、驱动依赖和未知盘位见 [灯光与盘位说明](LED_CONTROL.zh-CN.md)。下列部署方式
不代表已在这些系统的 NAS 实机验证。不要混用不同版本的程序、插件和能力目录。

## 先核对归档与运行环境

当前 `main` 正式渠道包包含四程序及十插件，使用动态 glibc；下载和快速开始见
[主线 README](../README.zh-CN.md#下载与快速开始)。下表保留 2026-10-16
对当时四程序、九插件、两个架构共 26 个 ELF 的独立检查结果；新版以各归档
manifest 的 `runtime_abi` 为准，历史运行库烟测不自动覆盖新构建。

| 要求 | x86_64 | aarch64 |
| --- | --- | --- |
| 程序解释器 | `/lib64/ld-linux-x86-64.so.2` | `/lib/ld-linux-aarch64.so.1` |
| 完整产品的数值 GLIBC 符号需求上限 | `GLIBC_2.27` | `GLIBC_2.27` |
| 载荷 `DT_NEEDED` 并集 | `libc.so.6`、`libdl.so.2`、`libpthread.so.0` | 同左 |
| 当前 RPATH / RUNPATH | 无 | 无 |

数值 glibc 门槛只是必要条件；还要满足解释器路径、依赖库及其版本符号、CPU 架构与内核接口。
归档不附带 libc 或动态加载器。两个占位插件没有外部依赖，不能据此把整个产品称为静态程序。
LED/盘位命令使用内置档案；风扇、电源等旧命令还需动态加载相应 `.so`。

先验证归档旁的 `SHA256SUMS`，整体解包到管理员选定的独立版本目录，保持其中
`usr/local/bin`、`usr/local/lib/ugreenctl/models`、文档及 manifest 的关系。管理员应保证
程序和上级目录不被其他用户替换，运行数据集也需允许执行。以下 `/your/release` 应替换成实际路径：

```sh
uname -m
getconf GNU_LIBC_VERSION
/your/release/usr/local/bin/ugreenctl --help
/your/release/usr/local/bin/ugreenctl led list --json
/your/release/usr/local/bin/ugreenctl --plugin-dir /your/release/usr/local/lib/ugreenctl/models models
```

`--help`、`led list` 不控制硬件；当前包的插件列表应完整加载十个模块且没有加载警告。
需要进一步诊断时，在 NAS 宿主机运行 `led status --json` 和 `disk list --json`。
能启动程序或加载插件不证明灯光写入、盘位映射或全部发行版已验证。

官方版本样例的 libc 基线：Debian 12/13 为 2.36/2.41，Ubuntu 22.04/24.04 LTS 为
2.35/2.39；PVE 9 基于 Debian 13；Unraid 7.2.0 发布说明列出 glibc 2.42。
这些版本满足当前数值门槛，实际设备仍按上面命令核对。fnOS 各版本/架构的统一 libc
承诺尚未确认，保留目标机检查。
来源：[Debian 12](https://packages.debian.org/bookworm/libc6)、[Debian 13](https://packages.debian.org/trixie/libc6)、
[Ubuntu 22.04](https://packages.ubuntu.com/jammy/libc6)、[Ubuntu 24.04](https://packages.ubuntu.com/noble-updates/libs/libc6)、
[PVE 9](https://newsletter.proxmox.com/archive/280d75a8-e59a-4c3c-b32f-4a9ce6f14ac6)、
[Unraid 7.2.0](https://docs.unraid.net/unraid-os/release-notes/7.2.0/)。

## Debian 12 / Ubuntu 22.04 运行库隔离烟测

2026-10-16，复用已验证的官方运行库原包，使用本轮扫描保护与命令路由修复后冻结的 x86_64/amd64 与 aarch64/arm64 产品，在无网络、宿主挂载或
硬件直通的 QEMU RAM 根文件系统中，分别装入下列官方 `libc6` 包的动态加载器及运行库。
两个发行版的两个架构均到达四个程序的 `--help` 正文，并成功动态加载、列出全部九个模型插件。
`ugreenctl-fand --help` 保留现有的退出码 1，其余三个帮助入口及 `models` 退出 0；没有把它
记录成四个帮助入口均退出 0。

| 官方运行库包 | 架构 | 原始 `.deb` SHA-256 |
| --- | --- | --- |
| Debian 12 `libc6 2.36-9+deb12u14` | amd64 | `ba4f88f73dbc3ae9055f3c20f4523bfdbaf1ad13ff95e258924f77d20b4fbedf` |
| Debian 12 `libc6 2.36-9+deb12u14` | arm64 | `01f4330719fd4f65580e16ea5a0527f372fca750e8f588d26deaf09f2d3b1cf4` |
| Ubuntu 22.04 `libc6 2.35-0ubuntu3.15` | amd64 | `79e35256227e16a607c154cdeb8d76ff12d20e31de286ea7fd9ad3b96fe0452d` |
| Ubuntu 22.04 `libc6 2.35-0ubuntu3.15` | arm64 | `dd88cc85dcfbac19c0c9b606676b7b1b87f851d75afa5c830fc5ba1293a30833` |

官方包来源：[Debian amd64](https://deb.debian.org/debian/pool/main/g/glibc/libc6_2.36-9+deb12u14_amd64.deb)、
[Debian arm64](https://deb.debian.org/debian/pool/main/g/glibc/libc6_2.36-9+deb12u14_arm64.deb)、
[Ubuntu amd64](https://security.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.35-0ubuntu3.15_amd64.deb)、
[Ubuntu arm64](https://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6_2.35-0ubuntu3.15_arm64.deb)。
原包保存在 `firmware-inbox/input/`，未修改。

两组记录包含加载器/libc 版本输出、VM 内运行库哈希、加载器 `--list` 和 `LD_DEBUG` 加载
路径，并核对产品与冻结清单中的 SHA-256。没有叠加既有 runner 的 glibc。Ubuntu 另有负控：
在隔离 VM 内暂时移走目标 `libc.so.6` 后，程序因缺库退出 127；恢复后四个运行库的哈希不变，
确认没有其他 glibc 兜底。Debian 的两枚旧 ABI 插件会产生可选 v5/v4 符号探测诊断，按既有
回退契约成功加载 v3；原始日志和精确允许的探测项均保留。新 Ubuntu harness 同样只接受 `models` 中这两枚插件的
四条完整探测行；其他未定义符号、帮助入口出现此类探测或其他加载错误均拒绝。

本地可复现证据（`input/`、`work/` 取证物不随源码或发布归档提交）：

- 冻结清单：`firmware-inbox/work/almighty-all-models/safety-audit-1235-binary-freeze.json`。
- Debian：`firmware-inbox/work/debian12-abi-smoke-20261016-1205/packages.json`、同目录
  `run_smoke.py`，最终结果及串口日志位于 `safety-audit-1235-final/`；
  `result.json` SHA-256 为 `8f6a25d759ce43e5787eb9b037854fbc373c8f790ba7e48668a21fd62c7dc2e1`。
- Ubuntu：`firmware-inbox/work/almighty-all-models/ubuntu2204-abi-smoke-1235/official-packages.json`、
  同目录 `run_smoke.py` 和 `reproduce.json`；最终快照位于 `runs/snapshot-e8efb1737ef6/`；
  顶层及快照 `results.json` SHA-256 均为 `f04efd0a18fd84b38b704ae11e8208e0dea238258e59240f273660acf2d3e18c`。

复现时应保留上述包、工具及冻结产品，从仓库根目录执行相应脚本；Debian 脚本使用
`--binary-freeze <冻结清单路径> --snapshot <新的快照目录名>`，Ubuntu 的离线完整命令和
QEMU/内核等依赖哈希见 `reproduce.json`。重新下载的仓库索引可能已指向更新的包，不应替代
表中的输入而继续沿用本次结果。

这些结果仅证明所列用户态加载器/运行库能够执行帮助入口及加载插件，**不是完整 Debian 或
Ubuntu 安装、NAS 实机、LED 写入、盘位映射或服务生命周期验证**。fnOS、PVE、Unraid、
TrueNAS SCALE 本轮均未实测，不能由 Debian 的基础运行库结果推定它们通过。
Unraid 的官方 `https://docs.unraid.net/go/download-list` 入口返回 HTTP 403 后已停止获取；
本轮没有下载或验证 Unraid 运行库。

## Debian / Ubuntu、PVE 与 fnOS

Debian/Ubuntu 可使用 README 的源码安装步骤。`scripts/install.sh --install-deps` 会修改
系统包；已有编译器和 CMake 时省略该选项。默认不安装同名兼容程序，需要时按
[兼容入口说明](LED_CONTROL.zh-CN.md#ugreen_leds_cli-兼容入口) 显式选择。

PVE 在物理 NAS 宿主机运行。虚拟机或 LXC 中的身份、sysfs、I2C/GPIO 和锁视图不能代表
宿主机；不把容器硬件直通当作默认部署方式。

fnOS 的 Web 管理员和 SSH 权限不等于 root；官方说明首位管理员 UID 为 1000，其他管理员
的 SSH 权限还需单独授权。硬件访问和 holder 仍以适当的 `sudo`/root 权限执行。
见 [fnOS 官方角色与 SSH 权限](https://help.fnnas.com/articles/v1/contact/user-role)。
不要假定自行放入 `/usr/local` 的文件会跨 fnOS 系统更新保留。

这些宿主机若使用 systemd，可审阅仓库的两份服务示例并调整绝对路径。源码安装仅把示例
放入文档目录，不自动启用。普通 GPIO holder 与 GT FLOW holder 只选相应的一份；它们共享
socket/锁。先以前台方式验证，再由管理员配置服务。

## Unraid

Unraid 将系统核心与配置载入 RAM；持久启动卷挂在 `/boot`，`config/go` 执行后阵列和
`/mnt/user` 才陆续可用。仅安装到 RAM 系统目录不足以跨重启保留，`go` 也不能直接依赖
尚未挂载的共享。见 [Unraid 官方启动顺序](https://docs.unraid.net/unraid-os/troubleshooting/common-issues/boot-and-startup-failures/)。

建议将校验过的归档和配置保存在启动卷的独立目录，启动时把选定版本解包到 root 管理的
RAM 目录；不要把高频日志写入启动卷。若使用阵列或 pool 上的程序目录，须等其就绪后启动，
并在该存储卸载前停止。

当前没有经 Unraid 本机验证的自动托管脚本；可先在管理员保留的前台终端运行所需 holder。
长期部署需显式配置会返回的启动器和正常停止入口，不能把前台 holder 直接放入 `go`
阻塞启动。单独添加 `&` 也不提供进程身份核对、退出等待或恢复结果检查。普通直接 LED 路径
无需为了部署而额外启动 holder。

## TrueNAS SCALE / Linux TrueNAS

TrueNAS 默认保护系统根目录和启动池，禁用 apt；开发模式的系统改动也不跨更新持久。
SCALE 应使用预编译归档或在另一台 Linux 上构建，**不要使用通用的 `--install-deps` 路径**。
见 [TrueNAS 官方开发模式说明](https://www.truenas.com/docs/scale/25.10/scaletutorials/systemsettings/advanced/developermode/)。

可把完整版本目录保存在专用持久数据集，例如 `/mnt/<pool>/tools/ugreenctl/releases/<version>/`，
在该数据集已挂载、解锁且允许执行后调用绝对路径程序。不要依赖自行添加的 `/usr/local`
或 `/etc` 内容跨升级保留。

若需要开机常驻，官方 `System > Advanced Settings > Init/Shutdown Scripts` 提供
`Post Init` 和 `Shutdown` 入口；任务按顺序运行且受超时限制，启动器必须及时返回。
Shutdown 阶段部分资源可能已经停止，须在运行目录/数据集卸载前正常停止 holder。
见 [TrueNAS 官方 Init/Shutdown 行为](https://www.truenas.com/docs/scale/25.10/scaletutorials/systemsettings/advanced/manageinitshutdownscale/)。
本项目目前没有经该系统实机验证的一键托管脚本；UI 启动配置和数据集版本目录应分别保留，
系统更新后重新核对路径、运行库和只读识别结果。

## 停止与升级

GPIO 的 `ugreenctl-ledd --force --apply` 需要持续持有线路 FD；DXP2800 GT 的显式
`--takeover-flow --force --apply` 还管理全局 FLOW 与原始 LED 状态。N76 不能由 GPIO holder
替代原厂驱动；其无驱动回读缺口仍未解决。

升级前停止选定服务，或向已核对身份的前台 holder 发送 SIGTERM，等待退出并检查恢复错误，
再切换整套版本目录。不要在旧进程运行时覆盖其程序或混入新版插件。SIGKILL、SSH 意外断开、
断电后的状态不等同于正常退出恢复；GT 原自主动画相位也仍未知。系统更新或停用工具时，同样
先处理本工具的启动入口和 holder 生命周期，不改变 NAS 自身的存储或网络服务。
