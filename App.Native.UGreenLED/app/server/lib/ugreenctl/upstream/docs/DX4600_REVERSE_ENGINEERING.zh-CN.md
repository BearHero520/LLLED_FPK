# DX4600 系列 UGOS Pro 1.17.0.0095 固件逆向记录

## 1. 范围与输入

本记录分析用户提供并确认属于官方发布的通用 UGOS Pro 系统镜像：

- 输入文件：`E:\工作台\固件\4600.img`
- 文件大小：`1,738,734,592` 字节
- SHA-256：`7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`
- 外层格式：GNU tar
- 系统：Debian GNU/Linux 12 (bookworm)，`amd64`
- 固件：`1.17.0.0095`
- 构建时间：`20260630.111337`
- 内核：`6.12.30+`

该镜像与同目录的 `4800.img`、`4800plus.img`、`4800pro.img`、
`480t plus.img`、`6800 pro.img` 的 SHA-256 完全相同，因此它是包含多个
机型分支的通用系统镜像。文件名本身不能证明某一台实机的 DMI 或主板版本。

外层镜像中的关键层及 MD5：

| 层 | 大小（字节） | MD5 |
| --- | ---: | --- |
| `rootfs-base.squashfs` | 791,789,568 | `f11d31551a2a1248ae386c3ef0dd1b0c` |
| `kernel.squashfs` | 80,871,424 | `f19c84459a7e88f48f7bf938db18cd0f` |
| `fw.squashfs` | 155,860,992 | `2f02907214806a4160ac7a86288b4112` |

这些 MD5 与仓库已有的同版本解包层完全一致。本次复用已校验的只读层进行
静态分析，原始镜像没有被修改。

## 2. 机型路由与精确产品名

`fw/etc/startpre.d/hwmonitor.sh` 对以 `DX4600` 开头的产品名安装
`fw/usr/sbin/hwmonitor`。`fw/usr/sbin/ug-load-drive.sh` 对
`DX4700` 或 `DX4600` 前缀加载：

- `ug_gpio_btn`
- `leds-mcu-28a48`
- `ug_sata_beep-dx4700`
- `ug_it86x-sio`
- `ledtrig-breath-ht32f52231`
- `ledtrig-normal-ht32f52231`
- `ledtrig-timer2-ht32f52231`
- `ledtrig-netdev2`

`ug_sata_beep-dx4700.ko` 的静态产品表以及 `ugpwproctl` 均包含以下三个
精确字符串：

- `DX4600`
- `DX4600+`
- `DX4600 Pro`

因此，这三个名字是固件确认的候选精确 DMI 名称。尚未读取用户实机的
`/sys/class/dmi/id/product_name`，不能把前缀匹配自动扩展到其他名称，也不能
据此宣称三种外观或主板版本已经实机验证。

通用 `hwmonitor` 的 `DX4600` 分支设置四个 SATA 盘位、两个 NVMe 盘位，
并读取 `/etc/default/dx4600.conf`。

## 3. 风扇与 IT8613 Super I/O

### 3.1 控制器身份

`ug_it86x-sio.ko` 是 x86-64 内核模块，模块名为 `ug_it86x_sio`，vermagic
为 `6.12.30+ SMP preempt mod_unload modversions`。其初始化路径执行以下操作：

1. 申请 `0x2e..0x2f` 端口；
2. 向 `0x2e` 连续写入 `0x87, 0x01, 0x55, 0x55` 进入 Super I/O 配置；
3. 从配置寄存器 `0x20/0x21` 读取芯片 ID，从 `0x22` 读取修订号低四位；
4. 只接受芯片 ID `0x8613`，日志为 `Found chip IT8613`；
5. 选择 HWM 逻辑设备 `LDN 0x04`，并检查激活寄存器 `0x30` bit 0；
6. 通过配置寄存器 `0x02` 写 `0x02` 退出配置。

硬件监控寄存器通过固定索引/数据端口 `0xa35/0xa36` 访问。这是 IT8613
Super I/O 路径，不是 ACPI EC。

### 3.2 单风扇寄存器

固件模块只实现一个系统风扇目标：

| 功能 | 寄存器/位 |
| --- | --- |
| 风扇控制 | `0x17`；清除 bit 7 进入手动 |
| PWM | `0x73` |
| 转速计高/低字节 | `0x1a / 0x0f` |
| HWM 索引/数据端口 | `0xa35 / 0xa36` |

驱动把转速计值 `0`、`0xffff`、`0x0fff` 视为无效/零转速。其换算为
`RPM = 1,350,000 / (2 × tach) = 675,000 / tach`。

`/proc/it86/fan` 以 `0222` 创建，写入语法是：

- `on` 或 `ON`：PWM 127
- `off` 或 `OFF`：PWM 0
- `set N` 或 `SET N`：`N` 为 `1..255`

虽然模块内有 `fan_read`，proc 节点实际是只写权限，不能据此宣称原厂路径
能够可靠读取当前 PWM。

关键静态位置：

- `it87x_init`：`.init.text + 0x10`
- `set_fan.isra.0`：`.text + 0x250`
- `fan_read`：`.text + 0x520`
- `set_bios`：`.text + 0x710`
- `startup_write`：`.text + 0x860`

### 3.3 原厂自动温控是软件曲线

实际运行的更新版 `hwmonitor` SHA-256 为
`866c37a88a58917aaf7eb02a1f037847e63214d1c83d196253b92ad566147d6f`。
它读取 CPU coretemp、SATA 与 NVMe 温度，分别计算目标 PWM，取三者最大值，
仅在目标改变时向 `/proc/it86/fan` 写 `off` 或 `set N`。

`dx4600.conf` 中恢复出的基础参数：

| 热源 | stop / start / mid / full / max（°C） |
| --- | --- |
| CPU | `45 / 50 / 70 / 80 / 90` |
| HDD | `35 / 40 / 50 / 55 / 70` |
| NVMe | `40 / 45 / 55 / 65 / 70` |

基础 PWM 点为 `64 / 128 / 204 / 255`（start / mid / full / max）。

镜像内 `/etc/fan.conf` 的默认值是 `mode = 2`。`load_hw_config` 在该模式下
将三组 stop/start 各降低 5°C，并把 mid/full PWM 各增加 24。因此此镜像
默认生效的曲线是：

| 热源 | stop / start / mid / full / max（°C） |
| --- | --- |
| CPU | `40 / 45 / 70 / 80 / 90` |
| HDD | `30 / 35 / 50 / 55 / 70` |
| NVMe | `35 / 40 / 55 / 65 / 70` |

默认生效 PWM 点为 `64 / 152 / 228 / 255`。基础配置和 `mode = 2` 修正必须
分开记录，不能只抄配置文件就宣称那是运行时曲线。

每条曲线采用分段线性插值：

- 温度不高于 stop：目标 0；
- stop 到 start：从硬编码 PWM 25 插值到 start PWM；
- start 到 mid、mid 到 full、full 到 max：分别在相邻点间线性插值；
- 高于 max：使用最大 PWM。

`mode = 3` 会强制 PWM 255。相关函数位置：

- `getFanPwm`：`0x487c`
- `setFanLimit`：`0x4aa9`
- `load_hw_config`：`0x4bb2`
- `read_fan_speed`：`0xbb39`
- `write_fan_speed`：`0xbc41`

结论：DX4600 的原厂自动调速是用户态 `hwmonitor` 软件守护，不是 IT8613
硬件自动模式。

## 4. 来电启动与 Wake-on-LAN

`/proc/it86/startup` 由同一个 IT8613 模块以 `0777` 创建，支持
`on`、`off`、`last`：

| 策略 | `0xf2` bit 5 | `0xf4` bit 5 | `0xf4` bit 6 |
| --- | ---: | ---: | ---: |
| on | 0 | 1 | 0 |
| off | 0 | 1 | 1 |
| last/restore | 1 | 1 | 1 |

寄存器属于 `LDN 0x04`。`hwmonitor` 根据 `/etc/power.conf` 的
`power_boot` 向该 proc 节点写 on/off。

同一配置加载路径会对 `eth0` 和 `eth1` 执行 `ethtool -s ... wol g|d`。
这是 NIC ethtool 操作，不是 Super I/O 寄存器。插件优先使用这两个名称；
若两者都不存在，共享解析器只接受恰好两张物理 PCI 有线网卡并按 PCI 顺序
映射，其他数量全部拒绝。固件静态证据没有确认实际网卡型号、接口重命名、
关机唤醒结果或跨重启持久性。

## 5. LED MCU

`leds-mcu-28a48.ko` 的模块名是 `leds_mcu_28a48`，描述为
`ugreen_ht32f52231 driver`。驱动：

- 扫描 I2C adapter 0..14；
- 只接受名称以 `SMBus` 或 `Synopsys` 开头的 adapter；
- 使用 7-bit I2C 地址 `0x3a`；
- 最多三次从寄存器 `0x5a` 读取 SMBus word，要求返回 `0xc5b2`；
- 从寄存器 `0x5d` 读取 MCU 版本。

注册的 LED class 设备是：

- `power`
- `network_stat`
- `disk1`
- `disk2`
- `disk3`
- `disk4`

固件内的颜色编号与 RGB 静态表：

| 编号 | 颜色 | RGB |
| ---: | --- | --- |
| 1 | white | `ff ff ff` |
| 2 | orange | `dc 28 00` |
| 3 | red | `ff 00 00` |
| 4 | green | `00 ff 00` |
| 5 | blue | `00 00 ff` |

`color_set` 接受 0..5，其中 0 会映射为 1。驱动还提供 LED class brightness
及 `debug`、`version`、`mode`、`state`、`color` 属性，并使用 normal、
timer2、breath、netdev/netdev2 trigger。

底层命令使用 12 字节 SMBus block 事务及校验计算。完整直写包格式、状态机
以及实机 MCU 修订尚未完全确认，因此当前不应绕过原厂驱动直接写 I2C。

## 6. 蜂鸣器与 SATA 在线状态

`ug_sata_beep-dx4700.ko` 对 DX4600 系列使用传统 PC speaker/PIT：

- PIT 控制：`0x43`
- PIT channel 2：`0x42`
- 相关端口：`0x41`
- 扬声器门控：`0x61` bits 0/1

`/proc/nas/beeper` 以 `0222` 创建，支持：

- `on`
- `off`
- `one`
- `timer <off_ms> <on_ms>`
- `rep <count> <off_ms> <on_ms>`

`timer`/`rep` 的 off/on 时间参数范围为 `20..99999` ms。

`/proc/nas/sata_sw` 以 `0444` 创建，报告 SATA1..SATA4 的 ON/OFF。模块
对以下四个 4 字节 MMIO 地址执行 `ioremap`，并检查 bit 1：

| 盘位标签 | MMIO 地址 |
| --- | --- |
| SATA1 | `0xfd6d0640` |
| SATA2 | `0xfd6d0650` |
| SATA3 | `0xfd6d0660` |
| SATA4 | `0xfd6d0670` |

这些是固件模块硬编码值；物理盘位对应关系尚无实机拔插记录。

关键静态位置：

- `reg_init`：`.init.text + 0x10`
- `sata_state`：`.text + 0x70`
- `beeper_write`：`.text + 0x2a0`
- `OemOverRideBeep_open`：`.text + 0x660`

## 7. 证据分级

### 固件确认

- 三个精确产品字符串 `DX4600`、`DX4600+`、`DX4600 Pro` 存在于产品表；
- DX4600 前缀对应的启动脚本、模块和用户态守护路由；
- IT8613 ID 检查、Super I/O/HWM 端口、风扇与来电启动寄存器；
- 软件温控曲线、默认 `mode = 2` 修正和单风扇最大值策略；
- LED MCU 的总线筛选、地址、检测寄存器和 LED class 设备；
- 蜂鸣器 PIT 端口、proc 命令和 SATA 状态 MMIO 地址。

### 静态推断

- 三个精确产品字符串很可能共享相同的 DX4600 硬件路由；
- 模块硬编码转速计和 SATA 标签代表设计上的单风扇与四盘位布局；
- 原厂用户态守护是正常运行时的控制器所有者。

### 实机验证

本次没有实机 DMI、寄存器回读、转速响应、LED、蜂鸣器、来电启动、WOL 或
盘位拔插记录，所有硬件写入均未实机验证。

### Unknown

- 用户设备的精确 DMI、主板版本以及三个产品字符串是否完全共用同一电路；
- 风扇最小不失速 PWM、物理风扇接头和转速换算的实机一致性；
- 原厂模块卸载后直控路径的完整恢复行为；
- LED 12 字节协议的完整包格式、校验与 MCU 版本差异；
- SATA1..4 与物理槽位的一一对应；
- 实际 NIC 型号、接口名、WOL 关机唤醒及持久性；
- 来电启动三种策略在实机 BIOS/断电场景中的结果；
- `high_temp_turnOff_time` 与 `high_temp_alarm_time` 的运行时单位和边界。

## 8. 安全接入约束

本轮已增加 `dx4600` 插件，只开放单系统风扇、来电启动、WOL 和
`stock-4600` 软件温控曲线。实现遵守：

1. 只匹配固件产品表确认的 `DX4600`、`DX4600+`、`DX4600 Pro`，不按
   `DX4600` 前缀放宽；
2. 确认芯片 ID `0x8613`、`LDN 0x04` 已激活；
3. 拒绝原厂 `/proc/it86`、`ug_it86x_sio`、通用 `it87` 或仍在运行的
   `hwmonitor` 控制器所有者；
4. 使用 `/run/ugreenctl-it8613.lock`，所有直写要求 `--force --apply`；
5. 不暴露原厂的 PWM 0 停转事务；直控安全范围保持 `40..255`；
6. 切换手动位和写 PWM 后都必须回读；
7. 原厂 hwmon 路径存在时优先使用，只有节点确实不存在时才允许直控回退；
8. 将软件温控曲线实现为守护进程，不得宣称为 IT8613 硬件自动模式；
9. LED 优先通过已绑定的 LED class/sysfs；协议未完成前不实现 MCU 直写；
10. 蜂鸣器和 SATA MMIO 在完成实机验证及所有权检查前保持不支持。

对应实现位于 `models/dx4600.c`、`fan/it8613_dx4600.*`、
`network/wol_dx4600.*`、`core/fan_daemon.c` 和 `fan/thermal_curve.c`。
支持等级保持 `reverse-engineered`；上述写入仍需 `--force --apply`。

## 9. 保留的证据文件

临时证据目录：

`firmware-inbox/work/dx4600-1.17.0.95/`

关键文件：

- `metadata/`：外层版本和校验清单；
- `evidence/scripts/hwmonitor.sh`
  SHA-256 `23c77f568d2c0b6854e99212765a4d328e5febe81f0b26d8e4fc71d6f7894eef`；
- `evidence/scripts/ug-load-drive.sh`
  SHA-256 `0475642cd01618524d45f7183cfb212f8495485977f2967633a7fea066dde384`；
- `evidence/config/dx4600.conf`
  SHA-256 `111aa1bc37e02e10a8bdf30ac4da58bbf44245ab3fc54da38c7eecd0e94e5b29`；
- `evidence/bin/hwmonitor-fw`
  SHA-256 `866c37a88a58917aaf7eb02a1f037847e63214d1c83d196253b92ad566147d6f`；
- `evidence/bin/ugpwproctl`
  SHA-256 `d45d72d78bfbb4d3127ba34874396f5d2adeb5eb2f9c7db0d573d573a5480a3a`；
- `evidence/modules/ug_it86x-sio.ko`
  SHA-256 `4d3864794d9cdec926b666878aed4431f80b69108acceadfa21322245f1393f4`；
- `evidence/modules/leds-mcu-28a48.ko`
  SHA-256 `28f2f0571437cf98bcc1d3bcc9cdce9f640f8ec8b263458f0935e63b242a04ff`；
- `evidence/modules/ug_sata_beep-dx4700.ko`
  SHA-256 `243eb08b9813e9ffc669cd3503ca868cd028a06d597a76355efbd13e469e39ed`。

`firmware-inbox/work/` 为临时分析区，未清理；原始输入文件未修改。
