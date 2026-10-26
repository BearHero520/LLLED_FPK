# 原厂盘位与 LED 映射：固件证据及跨系统转换

记录日期：2026-10-16。本次补查以原厂机型分支和初始化表为依据，区分
“原厂全局 ATA 编号对应哪盏灯”与“第三方 Linux 如何稳定识别该物理连接”。
二者需要不同证据，不能直接把 `ata1`、`host0` 或 `/dev/sda` 当作一号盘。

## 输入与官网核验

- 原始文件：`E:\工作台\固件\6800plus.img`，1,303,473,152 字节，仅只读访问。
- SHA-256：`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。
- MD5：`c5358c7713ccf2811aaa7c5adcc10721`。
- GNU tar 容器，UGOS Pro `1.20.0.0142`，Debian 12，amd64，内核 `6.18.15`。
- 提取目录：`firmware-inbox/work/dxp6800plus/`。

[绿联 DXP4800 Plus 官网下载页](https://www.ugnas.com/support/download-list/product_type=nas&id=9?id=9&product_type=nas&type=2)
的 `1.20.0.0142` 条目公布了相同 MD5，因此已有输入可用于核对 Plus 的
通用固件分支。本次核验复用了本地原包，没有再次下载大包，也没有依据
`6800plus.img` 这个本地文件名推断它仅包含某一型号。

官网页面快照为 `firmware-inbox/work/almighty-upstream/download-page.html`，
SHA-256 为 `c650ece412149dd92858ec4fa4b5d31e1a10c832ad8dda63479385bea65a94b9`。
该快照第 1019 行显示版本，第 1043 行指向
[官网固件临时链接接口](https://api-zh.ugnas.com/api/system/v1/ua/temp/link?appType=firmware&id=7270&model=9)，
第 1047 行包含上述 MD5；第 1255–1261 行的展开条目重复了下载入口和校验值。
本地 SHA-256 用于固定具体分析输入，官网 MD5 用于关联其公开下载条目。

## 可复现取证

分析脚本及输出仅放在忽略目录：

```text
firmware-inbox/work/almighty-firmware-map/
  analyze.py
  report.json
  report.txt
  routing-numbered.txt
  hwmonitor-480t.disasm.txt
  hwmonitor.disasm.txt
```

在仓库根目录执行：

```powershell
python firmware-inbox/work/almighty-firmware-map/analyze.py --input "E:/工作台/固件/6800plus.img"
```

脚本使用 pyelftools 与 Capstone；优先读取现有
`firmware-inbox/work/tools/python-elf-analysis/` 依赖。只写自己的分析目录，
不执行原厂 ELF、不访问硬件、不修改镜像或既有提取物。不传 `--input` 时
仍核对 ELF 和官网快照，但会明确记录原包未在该次运行中重新校验。

脚本核对两个二进制 SHA-256，读取 ELF 符号，使用 DWARF 验证结构布局，
解析 `ledCtrlStr` 静态记录，输出带函数名、PLT 调用名、全局变量名及字符串
引用的目标函数反汇编，并保存两份路由脚本的原始行号。

| 文件，相对于 `firmware-inbox/work/dxp6800plus/` | SHA-256 |
| --- | --- |
| `fw/usr/sbin/hwmonitor-480t` | `079d7a703e3ebd87aa59540712cba443c67e6863c5decaff187c06e5bcaa1541` |
| `fw/usr/sbin/hwmonitor` | `866c37a88a58917aaf7eb02a1f037847e63214d1c83d196253b92ad566147d6f` |
| `fw/etc/startpre.d/hwmonitor.sh` | `eca8e735ca1dd4212be408df0af736abff5aa5be190c5acf29060299fc2ef120` |
| `fw/usr/sbin/ug-load-drive.sh` | `62a6a1c2b415d03bb6fb19c06f6993e9cc9a5b86625be8393019a386d2529de2` |

## 机型到守护进程及 LED 控制器的路由

下列行号属于上述 **1.20** 提取物；不要套用到另一版本同名脚本。

| 精确目标 | `fw/etc/startpre.d/hwmonitor.sh` | `fw/usr/sbin/ug-load-drive.sh` |
| --- | --- | --- |
| DXP4800 Plus / Pro | 第 52–59 行的默认 CPU 风扇分支选择 `hwmonitor-480t`，第 53 行注释列明两机型 | 第 100–110 行精确匹配两种 DMI，加载 `leds-mcu-28a48` 及对应触发器 |
| DXP2800，system-version 含 `EM_DXP2800` | 第 26–42 行单独检查系统版本，EM 分支选择通用 `hwmonitor` | 第 57–65 行区分 EM 的 `leds-mcu-28a48` 和其他版本的 `leds-mcu` |
| DX4600 Pro | 第 45–50 行的 DX4600 分支选择通用 `hwmonitor` | 第 45–56 行的 DX4600 分支加载 `leds-mcu-28a48` |

原厂脚本部分采用前缀匹配。本项目在写硬件时仍使用精确 DMI；上述前缀
不是任意近似型号的授权。例如 DXP2800 新硬件分支不能继承 EM 版本的
LED 写入协议。

## 原厂全局 ATA 与灯号：固件确认

两个 ELF 均带 DWARF，可直接验证 `ledCtrlStr_t` 大小为 **72 字节**，
`name` 指针位于 `+0`、`sysPath` 位于 `+8`、`index` 位于 `+24`。
`DISKINFO_T` 大小为 136 字节，其 `index` 位于 `+48`。这些偏移来自
实际类型信息，不是根据打印结果猜出的结构。

`hwmonitor-480t` 的 `ledCtrlStr` 位于虚拟地址 `0x15520`；通用 `hwmonitor`
位于 `0x134c0`。记录 1–8 均包含以下初值：

| 记录 / index | 接口名 | LED class 路径 |
| --- | --- | --- |
| 1 | `ata1` | `/sys/class/leds/disk1` |
| 2 | `ata2` | `/sys/class/leds/disk2` |
| 3 | `ata3` | `/sys/class/leds/disk3` |
| 4 | `ata4` | `/sys/class/leds/disk4` |
| 5–8 | `ata5`–`ata8` | `/sys/class/leds/disk5`–`disk8` |

静态表还必须与机型分支和运行时重排一起核对：

- **DXP4800 Plus / Pro**：`hwmonitor-480t:getDevModel@0x953f` 中，
  `0x9895`、`0x98ac` 分别引用两种精确 DMI 并比较，随后 `0x98c3`
  设置 `g_DISK_TOTAL=4`，并选择 `dxp4800plus.conf`。
  `initDisk@0x8edc` 初始化 `index=1..8`；其特殊重排只针对 DXP6800、
  iDX 和 DH2600 分支，两种 Plus/Pro DMI 保留默认顺序。
- **EM DXP2800**：通用 `hwmonitor:main@0x34f0` 的 `0x3641..0x367e`
  分支选择该机型配置，并在 `0x3661` 设置 `g_DISK_TOTAL=2`。
  `initDisk@0x8278` 保留其默认顺序。
- **DX4600 Pro**：同一通用 ELF 的 `0x3859..0x3899` 分支选择 DX4600
  配置，`0x3879` 设置 `g_DISK_TOTAL=4`；初始化仍保留默认顺序。

`checkDisk` 使用盘记录的 `index` 格式化 `ata%d`，交给
`getDevNameByInterface`：后者枚举 `/sys/block`、`readlink` 并匹配接口名。
`hwmonitor-480t` 的两函数分别位于 `0x815f`、`0x6ee2`；通用 ELF 分别位于
`0x760d`、`0x6602`。因此，本次恢复的是原厂 **全局 libata 编号**：

| 目标 | 固件确认的关系 | 本项目实机状态 |
| --- | --- | --- |
| DXP4800 Plus / Pro | `ata1..4 → disk1..4` | 本次未连接实机 |
| EM DXP2800 | `ata1..2 → disk1..2` | 本次未连接实机 |
| DX4600 Pro | `ata1..4 → disk1..4` | 本次未连接实机 |

## 存储服务的独立机型表

同一原包中还恢复了存储服务的第二条证据链：

```text
ugreen.bz2（实际为 tar）
  → @cache/03_amd64_com.ugreen.storagemgr.upk（V1 长度字段容器）
  → ugb 字段（gzip tar）
  → com.ugreen.storagemgr.ugb（xz tar）
  → sbin/storage_serv
```

UPK SHA-256 为 `6caafd6b5b26d25ac9e627ae28c8f25e659c6c03bea77d6c3910ccd8945e909f`；
`storage_serv` SHA-256 为
`62130bc458462f0400f23f3f495e43129ab241fea103f3bd0db55bb058cb387e`。
提取和分析目录为 `firmware-inbox/work/dxp6800plus/disk-mapping-1.20/`，
其中 `extract_mapping_evidence.py` 导出
`official-disk-slot-evidence.json`，`analyze_disk_map.py` 导出
`mapping-disassembly.txt`。本次已重新执行导出并独立核对二进制哈希。

Go RTTI 的 `DiskSlotInfo@0x19c8d80` 给出 72 字节记录：`SlotName@0`、
`IDType@16`、`IDString@32`、`ColorLed@48`、`InterfaceType@56`。
`hardware.map.init.0@0x12ad520` 以精确机型键建立硬件表，恢复结果如下。
表中的顺序按逻辑盘位 1、2、3……排列：

| 精确机型键 | 固件内部 revision 键 | 对应全局 ATA | 静态记录 / 外层机型赋值地址 |
| --- | --- | --- | --- |
| DX4600 Pro | `rev1` | `ata1,2,3,4` | 表 `0x1d71948`；赋值 `0x12adff3` |
| DXP2800 | `rev1`、`rev2` | 均为 `ata1,2` | 初始化内联写入；赋值 `0x12adbae` |
| DXP4800 | `rev1` | `ata1,2,3,4` | 表 `0x1d71948`；赋值 `0x12aef6e` |
| DXP4800 Plus | `rev1` | `ata1,2,3,4` | 表 `0x1d71948`；赋值 `0x12af34b` |
| DXP4800 Pro | `rev1`、`rev2` | 均为 `ata1,2,3,4` | 表 `0x1d71948`；赋值 `0x12af6ab` |
| DXP6800 Pro | `rev1` | `ata3,4,5,6,1,2` | 表 `0x1d73cd0`；赋值 `0x12b044b` |
| DXP8800 Plus | `rev1` | `ata1,2,3,4,5,6,7,8` | 表 `0x1d77c90`；赋值 `0x12b0ff5` |

这些 SATA 行的 `IDType` 均为 `ata_id`，`InterfaceType` 为 `sata`，
`ColorLed=true`。该布尔值是原厂硬件描述，不能单凭它选择 LED 写协议
或推断任意 RGB 效果已获验证。

`diskdevice.getSataSlot@0x12ef700` 在 `0x12ef811..0x12ef888` 将 `IDString`
格式化为 `/%s/`，验证 `ata_id` 后匹配实际 sysfs 路径中的该组件。
`getSlotNumber@0x12f3d40` 取 `SlotName` 末尾数字作为逻辑槽号。这进一步
确认 `IDString` 仍是 **全局 ATA 路径组件**，不是 PCI 地址或本地端口。
JSON 保留了每个 revision 的赋值指令地址及原始记录，便于逐项复核。

继续恢复 `device.GetHwVersion@0x105f1a0` 可见：DXP2800 分支在
`0x105f208..0x105f240` 调用 `dmi.GetHwVersion` 并检查 `EM_` 前缀，
命中取 `rev1`，否则取 `rev2`。继续看 `dmi.GetHwVersion@0x105c280`，
它经 `dmidecode.New` 调用 `Decoder.BIOS@0x105c2cf`，读取首项结构
`+0x18` 的字符串；该字段的准确名称尚未通过 RTTI 确认。因此不能把它
直接写成 system-product-version。存储服务的 revision 选择与
`ug-load-drive.sh` 用 system-version 选择 LED 驱动是两条独立链路。
DXP4800 Pro 在 `0x105f2a7..0x105f2fa` 将 CPU 名称
转小写并查找 `i3-1315u`，命中取 `rev2`，否则取 `rev1`。本次七个 LED
机型中的其余机型走默认 `rev1`。两种 Pro revision 的 SATA 表相同。
因此这些内部键不能直接等同于 DMI `product_version` 的完整字符串或
机身 V1.2，不据此扩大 LED 协议和自动映射范围。

## 控制器本地端口转换

镜像内上述表没有给出 PCI BDF、vendor/device ID 或本地端口拓扑。
跨发行版驱动装载、扩展控制器或枚举顺序变化后，全局 `ataX`、HCTL 和
sdX 都不能直接作为机箱盘位。转换需要补充独立的一手硬件资料：

- DXP4800 Plus 用户 pbexiga 于 2026-03-08 提供
  [Proxmox / OMV 日志](https://forum.proxmox.com/threads/regression-in-6-17-asmedia-asm1164-sata-controller-forced-to-max_performance-preventing-disk-spin-down.181474/)，
  明确设备为 ASM1164、PCI ID `1b21:1164`、驱动 `ahci`，日志报告四个
  已实现端口及 mask `0xf`。该用户的 `05:00.0` 仅是当台机器的地址。
- DXP4800 Pro 用户 TemplarB 于 2026-08-24 提供
  [TrueNAS 实机配置](https://forums.truenas.com/t/i-just-started-making-my-nas-as-it-seems-one-of-hdds-is-failing-what-to-do/67624)：
  i3-1315U 设备采用 ASMedia 1164，四盘直接接入四口控制器。
- [ugreen-led-control 项目的机型表](https://github.com/alexanderschubert/ugreen-led-control#supported-models)
  记录 Plus/Pro 的 `ata1..4` 顺序已有用户确认，可作为原厂表的独立交叉证据。

**推断范围**：在精确 DMI 为 DXP4800 Plus 或 Pro、整机仅存在一个符合
`1b21:1164` / class `010601` / `ahci` 的 SATA 控制器，而且完整 ATA 端口
清单恰好覆盖该控制器的本地端口 1–4 时，结合原厂顺序与一手硬件记录，
可以把本地端口 1–4 对应到盘位及灯号 1–4。

这里的“单一控制器”必须从 PCI 清单确认；“四个端口”必须枚举
`/sys/class/ata_port`，包含未插盘端口，并核对其规范路径和 PCI 父设备。
不能仅看到四块已插入硬盘就认为四口布局已确认，也不固定 `05:00.0`。
Linux 导出的 `port_no` 为控制器本地端口号，起点为 1；其语义可查
[libata transport 实现](https://github.com/torvalds/linux/blob/master/drivers/ata/libata-transport.c)
及 [systemd 的 ATA 路径实现](https://github.com/systemd/systemd/blob/main/src/udev/udev-builtin-path_id.c)。

EM DXP2800 另有独立的控制器证据：Tim Kutzner 于 2024-05-08 发布的
[DXP2800 拆机与 lspci 实测](https://www.igorslab.de/en/ugreen-nasync-dxp2800-nas-im-test/3/)
仅列出一个 Intel `54d3` SATA 控制器；它不是 Plus/Pro 的 ASM1164。
结合原厂两口顺序，生产实现仅对精确 DMI `DXP2800`、实际 sysfs 中
`product_version=EM_DXP2800_V1.0.24`、唯一 `8086:54d3` / class `010601` /
`ahci`、完整本地端口恰好 1–2 的设备使用本地端口 1–2 对应盘位 1–2 的
条件式转换。EM 版本与该控制器布局的结合属于静态推断及运行时身份核验，
不能把拆机文章当作所有 DXP2800 修订都已实测；V1.2、GT 和未知系统版本
不继承这个转换。

生产扫描在上述完整条件成立时使用对应转换；新增控制器、缺失端口、重复
端口、非 AHCI 驱动或读取错误均不能凭排序补齐。DX4600 Pro 本次仍只取得
全局 ATA 表，尚未获得同等完整的控制器拓扑证据，不把另外两类控制器条件
套用过去。其它已有固定 PCI 拓扑及校准方法见
[盘位映射来源与限制](../disk/NOTICE.md)。

## 验证与交付边界

已实际运行上述脚本，重新计算原包 SHA-256、MD5 和大小，结果均匹配；
两个 ELF 哈希、DWARF 结构布局、灯号表及官网快照检查通过。输出目录保留，
没有清理临时提取物。本分析没有执行原厂代码或硬件写入，没有产生新的
物理盘位实机记录；固件确认、条件式静态推断和外部用户报告在上文分别标明。

本文仅记录盘位映射取证。构建、协议 fixture 与目标系统测试结果见本次
对应实现交付；不把反汇编成功当作硬件验证。本次没有修改 `LLLED_FPK`，
没有提交或推送。
