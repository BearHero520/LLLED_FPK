# 25 款 WOL / RTC 官方固件核对与接入

核对日期：2026-10-27。范围为 25 款，DH2100 / DH2100+ 按用户要求排除。此记录说明官方调用链与受保护的 Linux 接口适配，**不代表逐机、逐 BIOS 已验证关机唤醒**。

## 输入与提取

复用并重新计算四个原包 SHA-256；未改动原包、未重新下载固件。

| 输入组 | 原文件 | SHA-256 |
| --- | --- | --- |
| x86 | `6800plus.img` | `73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5` |
| dh2300 | `release_20260921-firmware_image-1.20.0.142-rk3576_release_arm64_6.1.27_nasync.img` | `a3a645e4f61d3a49d69b0b2c06d61b269a776dd769aa673dedceced4a616b9d3` |
| dh4300plus | `release_20260921-firmware_image-1.20.0.142-rk3588_release_arm64_6.1.27_nasync.img` | `837ebfe8fffa4b6221ac8aee13d4b364289eccffcc4076bed6660ee1a6cfe836` |
| idx | `release_agent_cli_20260930-firmware_image-1.20.12.30-intel_release_amd64_6.18_nasync.img` | `10edeeb661587c4cb495e078b1f3e004d6005c83e6aa7b1c05d764c57df5b50e` |

临时提取与反汇编：`firmware-inbox/work/almighty-wake-audit-20261027/`；含 `extraction.json`、`inputs-verified.json`、`daemon-analysis.json`、`dt-evidence.json`。原有提取继续复用 `dxp6800plus/` 和 `almighty-all-models/packages/{24,27,29}/`。长期摘要见 [结构化证据](../validation/almighty/2026-10-27-wake-audit/firmware-evidence.json)。

## 已核对的调用链

- WOL：x86 的 `etc/startpre.d/hwmonitor.sh` 按机型选择 daemon；ARM 包直接提供其 `hwmonitor`。五个不同 daemon 的 `load_hw_config` 均有启用/禁用 eth0、eth1 Magic Packet 的调用引用，位置与二进制 SHA-256 已记录。四组 `preshutdown` 又根据 `power.wake_on` 枚举接口重新启用 WOL。原厂使用两个名称并不证明设备实际有两张网卡。
- RTC：四组 `usr/sbin/OnSched` 内容一致，SHA-256 为 `97f28662a2b6067c71b30e6761fd5b53738ed9621221f1a021d4a00d42264730`。脚本无机型排除，读取周计划后设置下一次闹钟；四组关机脚本均调用它；四组 `etc/rc.local` 也在启动时直接调用它，已记录行号及 SHA-256。x86 和 iDX 的 `modules.builtin` 均包含 `kernel/drivers/rtc/rtc-cmos.ko`。这证明系统调用机制，不提供每个 BIOS 的 ACPI/S5 硬件保证。
- DH2300：原包 DTB 精确 model 为 `UGREEN RK3576 DH2300 Board`，compatible 包含 `rockchip,rk3576`；`/ethernet@2a220000` 启用并带 `enable-phy-wakeonlan`，第二 GMAC 禁用。RTC 为 `/i2c@2ac50000/hym8563@51`，带 `wakeup-source` 与中断。
- DH4300 Plus：DT model 为 `UGREEN RK3588C DH4300Plus Board`、compatible 含 `rockchip,rk3588`。两个 GMAC 均禁用，不能使用 DH2300 的 MAC；WOL 仅开放显式 PCI 网卡路径。RTC 为 `/i2c@fec80000/hym8563@51`，带 `wakeup-source` 与中断。两个 ARM 内核均启用 HYM8563 驱动及 RTC sysfs。
- HYM8563 的闹钟精度为分钟，接口要求 epoch 按 60 秒对齐，不悄悄舍入。参见 [Linux 6.1 原始驱动](https://github.com/torvalds/linux/blob/v6.1/drivers/rtc/rtc-hym8563.c)。

## 逐机状态

所有行的 WOL 都需要当前网卡驱动报告 Magic Packet 能力；RTC 都需要存在唯一符合该机型条件的 `wakealarm`。缺设备、驱动不支持或设备歧义时拒绝，不记为“不适用”。表中“自动”只沿用已有的固件网口集合/受保护改名解析；新增机型不猜网口数量。

| 机型 | 官方 WOL daemon | 当前 WOL 选择 | 独立 RTC 匹配 | 未确认 |
| --- | --- | --- | --- | --- |
| DH2300 | hwmonitor (ARM) | **必须指定网卡** | 精确 DT + HYM8563 节点 | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DH2600 | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DH4300 Plus | hwmonitor (ARM) | **必须指定网卡** | 精确 DT + HYM8563 节点 | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DX4600 | hwmonitor | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DX4600 Pro | hwmonitor | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DX4600+ | hwmonitor | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DX4700 | hwmonitor | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DX4700+ | hwmonitor | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP2800 | hwmonitor / hwmonitor-idx (system-version route) | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP2800 GT | hwmonitor-amd | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP4800 | hwmonitor-amd | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP4800 GT | hwmonitor-amd | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP4800 Plus | hwmonitor-480t | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP4800 Pro | hwmonitor-480t | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP4800S | hwmonitor | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP480T Plus | hwmonitor-480t | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP6800 | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP6800 Plus | hwmonitor-480t | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP6800 Pro | hwmonitor-480t | 已有自动选择 / 可指定网卡 | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性 |
| DXP6800 Ultra | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP8800 | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP8800 Plus | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP8800 Pro | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| DXP8800 Ultra | hwmonitor-480t | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |
| iDX6011 Pro | hwmonitor-amd | **必须指定网卡** | 精确 DMI + 唯一 rtc_cmos | 实际唤醒、BIOS/系统持久性；自动网口映射 |

## 实现与使用

`models/wake_profiles.c` 保存分开的 RTC 和 WOL 精确机型表。`core/wake_cli.c` 在插件加载前处理唤醒命令，RTC 不再读取 `UGREENCTL_CAP_WOL`，也不因机型没有风扇插件而被挡住。`--model` 只能与真实 DMI/DT 匹配，不能用于伪装机型。旧版 dx4600 / dxp4800plus 插件族选择名继续兼容；`--plugin-dir` 对这两类内建命令不参与能力判定。

```sh
ugreenctl power rtc-wake models
ugreenctl network wol models
ugreenctl power rtc-wake get
ugreenctl network wol get --interface enp3s0
ugreenctl network wol set on --interface enp3s0                 # dry-run
sudo ugreenctl --force --apply network wol set on --interface enp3s0
ugreenctl power rtc-wake set <未来的Unix秒时间戳>                # dry-run
sudo ugreenctl --force --apply power rtc-wake set <未来的Unix秒时间戳>
sudo ugreenctl --force --apply power rtc-wake clear
```

- 写入前精确机型匹配、检查 `--force --apply`、取得独立 root-owned 进程锁，并重读机型/主板/BIOS 身份；默认 dry-run 不访问网卡或 RTC。锁不能阻止其他管理软件在命令结束后覆盖设置。
- 显式 WOL 不做名字回退：检查物理 PCI Ethernet，或 DH2300 的精确 DT MAC 节点/compatible；排除虚拟接口和 Wi-Fi，检查网卡索引与设备身份未变、Magic Packet 支持及写后完整策略读回。没有照搬原厂脚本遍历所有网口直接写入的做法。WOL 依赖正常的 Linux 网卡驱动，不是裸网卡寄存器直控。
- RTC 枚举后只接受唯一匹配控制器；ARM 还匹配 OF 节点。清除、设置、读回固定在同一路径，不以第一个 rtcN 为准，也不会在失败后改用另一块 RTC。先验证时间范围/精度，再清除、确认已清除、设置和回读；失败停止，报状态未确认。RTC 使用 Linux RTC 驱动，不写系统时钟、BIOS 或裸 CMOS/I²C 寄存器。
- 这是一次闹钟的控制接口。周计划、关机前重设、关机服务及 WOL 跨重启持久化仍由应用或系统管理；本次未自动安装服务。官方 `preshutdown` 对 OnSched 失败使用继续关机策略，本项目不复制这一行为，也不自动关机。

## 尚未确认与验收边界

### 飞牛环境参考与 RTC 时间保护（2026-10-27）

用户提供的非绿联飞牛参考机只读结果：Debian 12 用户空间、glibc 2.36、
Linux 6.18.18、`rtc_cmos 00:01`、RTC 使用 UTC；物理网卡采用 `enp…`
名称，PCI uevent 的 `PCI_CLASS=20000` 没有前导零。没有安装 `ethtool`
命令。实现直接使用内核 ethtool ioctl，不依赖外部命令；新增 fixture
对全部 25 款分别检查这类 PCI 格式、改名网卡、Wi-Fi/网桥拒绝、独立 RTC
控制器选择及时间精度。参考机身份不加入绿联白名单，不在参考机上写设置。

RTC `set` 在清除旧闹钟之前读取同一控制器的 `since_epoch`，要求与系统
Unix 时间相差不超过 5 秒；读取失败、LOCAL 时钟偏移或时钟未同步时拒绝，
保留旧闹钟，不自行改 RTC 时基或系统时钟。该检查判断当前时钟一致性，
不是自动处理 LOCAL/DST；LOCAL RTC 的时间换算仍未支持。`get` 与 `clear`
不依赖时钟同步。新增测试覆盖缺失/非法时钟和正负 8 小时偏移的零写入拒绝。

参考机采集只证明该环境的接口存在，不能证明任何绿联机型的真实唤醒。
当前二进制另在隔离 QEMU 中检查 Debian 12 / Ubuntu 22.04 官方 libc 的
加载与 WOL/RTC 目录；这不是完整发行版、飞牛服务或 NAS 主板的验收。

1. **15 款的跨系统自动网口映射仍未确认**：DH2300、DH2600、DH4300 Plus、DX4700、DX4700+、DXP2800、DXP2800 GT、DXP4800 GT、DXP6800、DXP6800 Ultra、DXP8800、DXP8800 Plus、DXP8800 Pro、DXP8800 Ultra、iDX6011 Pro。当前使用显式物理网卡；不能称自动映射完成。
2. **25 款实际关机唤醒及跨 BIOS 版本行为未完成本轮验证**。x86 的逐板 ACPI/RTC 型号与 S5 路由没有从升级包单独恢复，按原厂 RTC 栈加运行时控制器检查开放条件实现，不能宣传为所有 BIOS 均可唤醒。BIOS 更新后必须重新检查 RTC 节点、网卡能力，并重新做关机唤醒测试。
3. 网卡或 RTC 驱动缺失、TrueNAS/飞牛等系统覆盖配置、断电失去闹钟或主板待机供电条件不同，都不能由接口读回证明已解决。当前没有五类目标系统逐机实测矩阵。
4. 原有灯光/M.2/GT SATA 待办不因本次 WOL/RTC 核对而消失。

## 验证

Release 构建和 CTest 结果由本轮 `validation/almighty/2026-10-27-wake-audit/result.json` 记录；测试包括精确机型/DT 拒绝、RTC 无 WOL/插件依赖、RTC 设备歧义与时间精度、清除/设置/回读失败、WOL 物理设备身份变化和 Magic Packet/readback 失败。QEMU/fixture 不是 NAS 实机验证。

本轮未修改 `E:\工作台\LLLED_FPK`，未合并 main。工作区原有 DXP6800 Plus WOL 及网络解析改动保留。
