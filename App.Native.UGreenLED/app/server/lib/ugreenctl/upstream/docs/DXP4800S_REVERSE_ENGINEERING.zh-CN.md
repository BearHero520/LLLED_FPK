# DXP4800S 逆向记录

> Updated firmware evidence and current implementation: [UGOS 1.19.1.0126](DXP4800S_1.19.md).

本文记录 `dxp4800s` 插件采用的固件证据，不代表已经完成实机验证。

完整的新机型接入清单见 [DXP4800S_INTAKE.md](DXP4800S_INTAKE.md)。

## 身份与来源

- 精确 DMI product name：`DXP4800S`（**固件证据**）
- 固件：UGOS Pro `1.17.0.0095`，Build `20260630.111337`
- 内核：`6.12.30+`
- 固件镜像 SHA-256：
  `7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`
- 原厂驱动 `ug_it86x-sio.ko` SHA-256：
  `4d3864794d9cdec926b666878aed4431f80b69108acceadfa21322245f1393f4`
- 原厂风扇守护进程 `/usr/sbin/hwmonitor` SHA-256：
  `e3a2891a20fcdbab1c90374eff0ba9b5d6840634021bb3d43e681831e89b03be`

原厂 `ug-load-drive.sh` 把 `DXP4800S` 放在 DXP4800 分支并加载
`ug_it86x-sio`；`hwmonitor` 对精确字符串 `DXP4800S` 选择
`/etc/default/dxp4800.conf`。二者均为**固件证据**。

## 控制器与访问路径

这里不是 ACPI EC 命令协议，而是 ITE IT8613 Super I/O 硬件监控器直连：

| 项目 | 数值 | 证据等级 |
| --- | --- | --- |
| Super I/O 配置端口 | `0x2e / 0x2f` | 固件证据 |
| 进入配置模式 | 向 `0x2e` 写 `87 01 55 55` | 固件证据 |
| 退出配置模式 | 索引/数据 `02 / 02` | 固件证据 |
| Hardware Monitor logical device | LDN `0x04` | 固件证据 |
| HWM 索引/数据端口 | `0xa35 / 0xa36` | 固件证据 |
| 芯片 ID | ITE IT8613（`0x8613`） | 固件证据 |

## 风扇映射

DXP4800S 只有一个原厂风扇通道 `sysfan1`：

| 功能 | 寄存器或公式 | 证据等级 |
| --- | --- | --- |
| 手动控制 | HWM `0x17`，清 bit 7 | 固件证据 |
| PWM 写入 | HWM `0x73` | 固件证据 |
| 转速计高/低位 | HWM `0x1a / 0x0f` | 固件证据 |
| RPM | `675000 / tachometer` | 固件证据 |

原厂 `/proc/it86/fan` 以 `0222` 创建，接受 `on`、`off`、`set N`、
`SET N`。其中 `on` 写 PWM `127`，`off` 写 `0`，数值范围为 `1..255`。

插件只开放目标 `sys` 和 PWM `40..255`。`64` 来自原厂 DXP4800 曲线的最低
运行点，属于**静态安全推断**，不是实机失速下限。普通 `fan set` 不开放 PWM 0。

当前实现通过 hwmon 或受保护的直控寄存器回读 PWM 和模式；实机准确性仍待验证。
原厂“自动”由用户态 `hwmonitor` 守护进程实现，不是 IT8613 硬件自动模式。

## 原厂自动曲线

`hwmonitor` 读取 CPU、SATA HDD 和 NVMe 温度后向 `/proc/it86/fan` 写 PWM：

| 温度源 | stop / start / mid / full / max（摄氏度） |
| --- | --- |
| CPU | `50 / 55 / 75 / 80 / 90` |
| HDD | `40 / 45 / 50 / 55 / 70` |
| SSD | `45 / 50 / 60 / 65 / 70` |

PWM 点为 `64 / 128 / 204 / 255`。在其他系统上要实现“自动”，需要另行运行具备
可靠温度源和故障保护的守护进程；当前已提供 `ugreenctl-fand`，详见 [FAN_CURVE.md](FAN_CURVE.md)。

## 来电启动策略

原厂驱动使用 LDN `0x04` 的 `0xf2`、`0xf4`：

| 策略 | F2 bit 5 | F4 bit 5 | F4 bit 6 | 证据等级 |
| --- | --- | --- | --- | --- |
| on | 0 | 1 | 0 | 固件证据 |
| off | 0 | 1 | 1 | 固件证据 |
| restore/last | 1 | 1 | 1 | 固件证据 |

## 在其他 Linux 系统上安全使用

写入必须同时满足：

1. DMI 精确等于 `DXP4800S`。
2. 芯片 ID 等于 `0x8613` 且 HWM logical device 已启用。
3. 原厂 `/proc/it86`、`ug_it86x_sio` 未运行；可通过 IT87 的 hwmon 工作，
   仅直控回退要求 IT87 未运行。
4. 具备 root 或 `CAP_SYS_RAWIO`。
5. 未实机验证期间同时提供 `--force --apply`。
6. 有独立温度监控和恢复方案。

受保护的手动写入示例：

    sudo ugreenctl --force --apply fan set sys 120

恢复原厂控制时，先停止替代控制程序，再加载 `ug_it86x_sio` 并启动原厂
`hwmonitor`；若目标系统没有原厂组件，重启回 UGOS Pro。

## 未知或未验证

- DXP4800S 实机无失速最低 PWM：`unknown`。
- 当前 PWM 回读可靠性：`unknown`。
- 各非 UGOS IT87 驱动和内核版本的冲突行为：`unknown`。
- PWM/RPM、噪声和温度的实机对应关系：未验证。
- LED MCU 直接写入：本插件未开放。
