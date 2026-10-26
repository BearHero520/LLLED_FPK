# 基于官方固件的网络唤醒映射

本文是 `ugreenctl` 网络唤醒（WOL）机型映射的依据。结论来自官方 UGOS
Pro 固件的静态、净室逆向，不等同于实机验证。

## 输入与机型路由

提供的 `4600.img`、`4800.img`、`4800plus.img`、`4800s/release_*.img`、
`480t/release_*.img` 都是同一通用 UGOS Pro 镜像，SHA-256 为
`7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`。
镜像版本为 UGOS Pro `1.17.0.0095`（build `20260630.111337`）。原始镜像
未被修改，分析文件仅位于忽略的临时目录。

固件 `etc/startpre.d/hwmonitor.sh` 按 DMI 选择守护进程；下表各守护进程都
明确包含 `ethtool -s eth0 wol g`、`ethtool -s eth1 wol g` 与对应的 `wol d`
命令，并由 `power.wake_on` 控制：

| 精确 DMI product name | 原厂守护进程 | 固件接口映射 |
| --- | --- | --- |
| `DX4600` / `DX4600+` / `DX4600 Pro` | `hwmonitor`（`DX4600` 原厂路由） | `eth0`、`eth1` |
| `DXP4800` | `hwmonitor-amd` | `eth0`、`eth1` |
| `DXP4800S` | `hwmonitor` | `eth0`、`eth1` |
| `DXP4800 Plus` / `DXP4800 Pro` | `hwmonitor-480t` | `eth0`、`eth1` |
| `DXP480T Plus` | `hwmonitor-480t` | `eth0`、`eth1` |
| `DXP6800 Pro` | `hwmonitor-480t`（`DXP6800` 原厂路由） | `eth0`、`eth1` |

固件产品表确认了 `DX4600`、`DX4600+`、`DX4600 Pro` 三个精确字符串；
`ug-load-drive.sh` 还独立确认了 `DX4600` 前缀以及 `DXP4800S`、
`DXP4800 Plus`、`DXP4800 Pro`、
`DXP480T*`、`DXP6800*` 的原厂机型路由。运行时插件只接受上表中已有的精确
DMI 名称，不会把固件里的前缀判断改为模糊匹配。

## 实现与保护

WOL 是网卡配置，不是 BIOS/Super I/O 寄存器。实现使用 Linux ethtool ioctl，
等效于原厂命令但不启动 shell；也不会触碰 LED 控制平面。每个机型在
`network/wol_<model>.c` 中保留独立的 `eth0`/`eth1` 映射。

写入前会检查两个网卡都支持 Magic Packet；写完后会读取两个网卡状态，混合或
不匹配状态会报错。不会猜测 `enp*` 等改名接口。

[DX4600 系列官方规格](https://www.ugnas.com/products-detail/id-22.html)确认有两个
2.5GbE 有线网口，因此 `dx4600` 路由把改名后的物理网卡数量显式设为两张。
飞牛 OS 中若 `eth0`、`eth1` 都不存在，解析器只接受恰好两张物理 PCI 有线网卡
并按 PCI 地址稳定排序；一张、多于两张，或只有虚拟、bond、bridge 接口时都会
拒绝，不硬编码任何 `enp*` 名称。

所有 WOL 写操作仍需 `--force --apply`：固件路径已确认，但关机、重启和断电
后的持续性尚未完成实机验证。读取状态无需写入确认。

```sh
ugreenctl --model dxp480tplus network wol get
sudo ugreenctl --model dxp480tplus --force --apply network wol set on
```

## DXP480T Plus 的 FNOS 实机记录

2026-07-23 收到的只读实机记录确认：精确 DMI `DXP480T Plus` 在 FNOS
`6.18.18.c938-trim` 下仅暴露一张有线 PCI 网卡，Aquantia AQC113
`0000:73:00.0`，接口名为 `enp115s0`；`atlantic` 驱动报告
`Supports Wake-on: pg`、`Wake-on: g`。原厂 `eth0`/`eth1` 名称仍优先；仅当
两者都不存在时，该精确机型允许安全识别**恰好一张**物理 PCI 有线网卡，零张或多于
一张仍拒绝，绝不根据接口名猜测。该记录只确认策略读取与网卡能力，关机后的实际
Magic Packet 唤醒及重启、断电后的持久性仍待验证。

在升级为已验证能力前，需逐机确认两块网卡均支持 WOL、关机后 Magic Packet
可唤醒，以及重启和断电恢复后仍能保持设置。
