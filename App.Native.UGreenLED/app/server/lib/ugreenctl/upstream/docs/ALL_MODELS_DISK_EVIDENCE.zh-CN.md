# 全机型物理盘位映射取证与接入断点

本文记录 `Almighty` 分支的盘位实现和继续取证入口。**恢复原厂数据表、通过合成 sysfs 测试、用户实机验证是三种不同状态**；没有取得稳定硬件连接证据的项目不计为完成。用户已明确将 DH2100 / DH2100+ 排除出本轮范围；当前目标为其余 25 款。最后核对日期：2026-10-16。

## 输入与可复现分析

官网 27 款的原始页面、版本、MD5 与下载记录见
[原包接收记录](ALL_MODELS_FIRMWARE_INTAKE.zh-CN.md) 和 `models/official-products.json`。
22 个 x86 官网条目的最新 1.20.0.0142 镜像 MD5 相同，为
`c5358c7713ccf2811aaa7c5adcc10721`。已有本地镜像 `E:\工作台\固件\6800plus.img`
与之相符；不能根据本地文件名把通用包误当成只适用一款。

| 输入/提取物 | SHA-256 |
| --- | --- |
| 通用 x86 官方镜像 | `73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5` |
| 通用 1.20 `storage_serv` | `62130bc458462f0400f23f3f495e43129ab241fea103f3bd0db55bb058cb387e` |
| iDX6011 Pro 官网独立最新版 `storage_serv` | `cb95cc079b7d9fcf466fc814cfbf0a4528733be1893b88c4b6f00263a0a1aaa4` |
| DH2300 / DH4300 Plus 官方 ARM64 `storage_serv`（两包相同） | `7c88375afad6c64b80eca612d1c3db137774da22b8e27514aefd9e6a499dcca8` |

`firmware-inbox/work/almighty-disk-all/decode_storage_map.py` 对 Go 的
`hardware.map.init.0` 做受限静态字面量解释，只模拟常量拷贝、分配和 map 赋值，
**不运行固件 ELF**。它从 RTTI 验证 `HardwareInfo` 112 字节布局和
`DiskSlotInfo` 72 字节记录，恢复 32 个名称（包括排除不用的 `acloud`）、
34 个真实机型/修订布局。输出 `all-storage-map.json`；生成器
`generate_profile_data.py` 写入 `disk/firmware_profiles.c` 的纯数据。
生成器还合入两个官网 ARM 目标的五个修订，共 39 个布局。
该表另含非官网目标名称；表中出现名称不构成发布支持承诺。

对最新 iDX 二进制使用同一静态解释器重新提取，输出
`idx-storage-map.json`，全部模型、修订和三个盘组逐项与通用 1.20 完全相同。
两者均解释 2942 条字面量指令，RTTI 地址为 `0x19ea2a0`。

ARM 的可复现脚本与证据位于
`firmware-inbox/work/almighty-all-models/{extract_arm_mapping.py,analyze_arm_storage.py,arm-storage-map.json,arm-storage-disassembly.txt}`。
ARM ELF 是 PIE，必须先使用 `.rela.dyn` 中 168290 项
`R_AARCH64_RELATIVE` 的 addend，再解引用 Go 静态指针；文件原字节中的旧指针不能直接用。
`hardware.map.init.0@0x10e3590` 恢复五个 ARM 名称，各字段有 RTTI 与赋值地址。

原厂 `hwmonitor`/`hwmonitor-480t` 的独立盘灯链、偏移和哈希见
[原厂盘灯证据](DISK_MAPPING_FIRMWARE.zh-CN.md)。
所有镜像及二进制留在被忽略的 `firmware-inbox/work/`；没有修改原始输入。

## 已接入的稳定连接规则

`disk/disk.c` 每次从 Linux sysfs 重新扫描整块物理 SATA 和 PCIe NVMe，
排除分区、loop、USB、虚拟/逻辑 RAID、NVMe over Fabrics。
ARM 原生 AHCI/DWC-AHCI SATA 同样列入只读库存，报告例如
`platform-2a240000.sata-ata-1`；可枚举不代表物理槽映射已完成。
ATA 使用 canonical controller 路径与 `ata_port/port_no`，不按 sdX、SCSI host、
HCTL 或已安装盘的顺序分配物理槽。串号使用有效 sysfs serial 或内核缓存 VPD 0x80，
无 SMART/SG_IO/真实盘读取。条目读取末尾及整次扫描结束再次核对路径、串号、WWID；
扫描结束还重验多控制器全端口与 NVMe 连接规则。

原厂 `ata_id=ataN` 是原厂全局注册编号。本实现先验证**全部控制器和空端口**，
再将其转换为控制器局部端口；不是拿当前系统的 ataN 直接套表。

| 转换 | 必须通过的运行时条件 |
| --- | --- |
| Plus/Pro 四盘 | 精确机型；唯一 `1b21:1164` / AHCI；恰好局部 1–4 四端口；无额外 SATA/ATA 父节点 |
| DXP2800 两个精确修订 | 精确机型和真实 `product_version=EM_DXP2800_V1.0.24` 或 `DXP2800 V1.2 251215`；唯一 `8086:54d3` / AHCI；恰好两端口 |
| 老四盘控制器角色 | 精确原厂机型表；完整 Intel 两口 + ASMedia `0612/1062` 两口，或唯一 `1164` 四口；Intel 对应原厂 ATA1–2、ASMedia 对应 ATA3–4 |
| 六盘控制器角色 | 精确原厂表；完整 Intel 两口 + ASMedia `1164` 四口，或唯一 `1166` 六口；再应用该机型原厂槽序 |
| 八盘控制器角色 | 两个完整 `1164` 四口；上游 Intel bridge ID 分别 `8086:51bc` 和 `8086:51be`；相同/缺少桥角色拒绝 |
| GT SATA | 原厂明确的 root PCI path 与完整局部端口；DXP2800 GT 两版 SATA 顺序相反，尚无精确 BIOS 与物理盘位配对证据，自动 SATA 映射保持 unknown；不再使用 `LL_`/else 兜底，现有管理员显式校准保留 |
| NVMe `pcie_bridge_id` | 遍历 canonical PCI 祖先，精确 vendor/device 且 class 为 PCI bridge；不同物理控制器落同一槽则全部冲突失效，同控制器 namespace 先归并 |
| NVMe `pcie_address` | 原厂 root port 固定；仅放宽直接 endpoint 的下游 BDF 编号，不把桥后其他任意设备当成同一连接器 |
| GT NVMe/U.2 `syspath` | 原厂精确 root path；U.2 与 SATA 共享同一物理 bay 时，双占/重复槽会拒绝定位 |
| ARM 原厂 OF 角色 | 精确 DT model、原厂 OF 节点身份/reg/compatible/status、全部空端口及独占完整控制器布局；DH4300 Plus 另要求唯一 ASM1062 两口及原厂 PCIe OF root |

以上全局 ATA 到局部角色的转换包含**静态拓扑推断**，受完整运行时结构校验约束，
不是本项目新增的实机验证。已有一手实机锚点及来源：

- [上游作者和机主的原始盘位记录](https://github.com/miskcoo/ugreen_leds_controller/issues/9)：
  DXP4800 的 Intel 两口在前、ASMedia 两口在后；6800 Pro 的 ASMedia 四口在前、Intel 两口在后；8800 Plus 的双四口分组。
- [6800 Pro 机主的完整 PCI 枚举](https://forums.truenas.com/t/ugreen-nasync-series-collecting-infos-for-development/6174)：
  Intel `8086:51d3` 与 ASMedia `1b21:1164`；ASMedia endpoint 曾为 58:00.0，
  与其他实机的 59:00.0 不同，因此运行时代码不固定 endpoint BDF。
- [Plus 机主的四口 ASM1164 启动记录](https://forum.proxmox.com/threads/regression-in-6-17-asmedia-asm1164-sata-controller-forced-to-max_performance-preventing-disk-spin-down.181474/)、
  [Pro 机主的四口记录](https://forums.truenas.com/t/i-just-started-making-my-nas-as-it-seems-one-of-hdds-is-failing-what-to-do/67624)：
  独立支持单 ASM1164 四口转换。
- [DXP2800 实机拆解和 PCI 枚举](https://www.igorslab.de/en/ugreen-nasync-dxp2800-nas-im-test/3/)：
  Intel `8086:54d3`，并非 Plus/Pro 的控制器。

未满足上述硬件形状时保持 unknown；不会按相似机型、已装盘排序或缺口补号。
`mapping_source` 区分管理员校准、单控制器证据转换、原厂 ATA 拓扑转换和原厂 PCI 规则。

## 官网 27 款：逐项状态

表中“已接入”表示生产 scanner 中已有规则并有合成 sysfs 回归；**不表示实机验证**。
M.2 数字包括原厂列入管理的系统 NVMe，未把它们都宣传为可换用户盘槽。
无盘灯与物理盘位未知分开处理：已映射的无灯盘可正常列出，locate 返回 unsupported。

| 官网机型 | SATA/U.2 | NVMe/M.2 | 尚需证据/限制 |
| --- | --- | --- | --- |
| DXP2800 GT | 已接入两 SATA + 两 U.2 root-path，SATA 双修订 | 已接入两个 root-path | 缺 BIOS 时 SATA 拒绝；不是按设备名推断 |
| DXP4800 GT | 已接入四 SATA + 两 U.2 root-path | 已接入两个 root-path | 完整端口验证；共享 bay 冲突拒绝 |
| DXP8800 Ultra | 已接入八盘控制器角色 | 已接入三个 bridge-ID | 两 ASMedia 的桥角色必须明确 |
| DXP6800 Ultra | 已接入六盘角色和原厂 3,4,5,6,1,2 槽序 | 已接入三个 bridge-ID | 受完整 controller 校验约束 |
| DXP4800 Pro | 已接入四盘单 ASM1164；两修订槽序相同 | 已接入两个 bridge-ID | 精确机型和 ASIC/空口验证 |
| DXP4800S | 已接入自身原厂表与四盘角色 | **待稳定连接证据**：原厂只写 block_name | 不套用 Plus 的 NVMe 桥 ID |
| iDX6011 Pro | 已接入自身 3,4,1,2,5,6 槽序 | 已接入两个 bridge-ID + 一个 root-path | 最新独立固件数据已完整核对 |
| DXP6800 | 已接入六盘角色 | 已接入三个 bridge-ID | 原厂独立名称/表 |
| DH4300 Plus | 已接入原包 kernel + OF 角色的条件式四盘映射 | 原厂无 NVMe 盘组 | 两原生单口 + PCI ASM1062 两口；完整排他校验，静态未实机 |
| DH2300 | 已接入原包 kernel + OF 角色的条件式两盘反序 | 原厂无 NVMe 盘组 | 三修订槽表相同，完整 OF 校验，静态未实机 |
| DX4600 | 已接入四盘角色 | **待稳定连接证据**：block_name | 精确自身表 |
| DX4600+ | 已接入四盘角色 | **待稳定连接证据**：block_name | 精确自身表 |
| DX4600 Pro | 已接入四盘角色 | **待稳定连接证据**：block_name | 不把名称相近的板型 PCI 路径混用 |
| DH2600 | 已接入双盘反序；盘灯关联已确认 | **待稳定连接证据**：block_name | 双色盘灯，ColorLed=false 不等于无盘灯 |
| DX4700+ | 已接入四盘角色 | 已接入两个 bridge-ID | 原厂不同于 DX4700 的 M.2 标识方式 |
| DX4700 | 已接入四盘角色 | **待稳定连接证据**：block_name | 不套用 DX4700+ 桥 ID |
| DXP8800 Pro | 已接入八盘角色 | 已接入三个 bridge-ID | 双控制器桥角色验证 |
| DXP8800 Plus | 已接入八盘角色 | 已接入三个 bridge-ID | 一手实机分组锚点，endpoint BDF 可变 |
| DXP8800 | 已接入八盘角色 | 已接入三个 bridge-ID | 精确自身表 |
| DXP6800 Pro | 已接入六盘角色 | 已接入三个 bridge-ID | 一手实机锚点；58/59 总线变化 fixture |
| DXP6800 Plus | 已接入六盘角色 | 已接入三个 bridge-ID | 精确自身表 |
| DXP4800 Plus | 已接入四盘单 ASM1164 | 已接入两个 bridge-ID | 精确 ASIC/全部空口验证 |
| DXP480T Plus | 无 SATA 盘组 | 已接入四个物理 NVMe 连接器 | 官方 LED 模块只有 power；NVMe locate 明确 unsupported |
| DXP2800 | 已接入精确 EM 与 V1.2 251215 两修订、两口条件式转换 | **待稳定连接证据**：block_name | 只有确认的精确修订；ASIC 不符保持 unknown，不继承 EM LED 寄存器 |
| DXP4800 | 已接入自身原厂表与四盘角色 | **待稳定连接证据**：block_name | 有一手四盘分组记录 |
| DH2100 | 用户明确排除本轮范围 | 用户明确排除本轮范围 | 保留此前未取得官方原包的事实，不标成硬件不支持 |
| DH2100+ | 用户明确排除本轮范围 | 用户明确排除本轮范围 | 同上 |

## ARM 原包 kernel / OF 角色转换

原厂 ARM 静态表：DH2300 rev1/2/3 都是 physical slot1/2 → global ATA2/1；
DH4300 Plus rev1/2 都是 slot1..4 → global ATA2/1/4/3，ColorLed 均 false。
不同修订表相同，因此无需猜修订来选择盘位值。
非 Plus 的 DH4300 使用 `target_id`（0:1:0、0:0:0、1:1:0、1:0:0），
不能混入 Plus 的规则。

官方 DTB 原始属性导出在
`firmware-inbox/work/almighty-led-all/ata-pcie-dt.json`：

| 精确 DT model | 已启用 SATA OF 节点 | DT 端口信息 |
| --- | --- | --- |
| `UGREEN RK3576 DH2300 Board` | `/sata@2a240000`、`/sata@2a250000` | 各自 `ports-implemented=1`，各一个局部端口 |
| `UGREEN RK3588C DH4300Plus Board` | `/sata@fe230000`、`/sata@fe220000` | 各一个局部端口，另有 sata0-pm-reset/sata1-pm-reset |

两 DT 的 `/aliases` 都没有 SATA alias 或槽标签；列出次序和地址大小不能独立证明槽号。
共同 compatible 为 `rockchip,rk-ahci`、`snps,dwc-ahci`。
DH2300 已确认 GPIO 盘灯 disk1/2；DH4300 Plus 已确认 disk1..4。

一手拆机/lspci 已确认
[DH4300 Plus 为原生两口 + ASMedia ASM1062 两口](https://www.igorslab.de/en/ugreen-nasync-dh4300-plus-nas-im-test/3/)，
记录 PCI endpoint 为 `0003:31:00.0`；不能把 `sata*-pm-reset` 引脚名称当成存在 SATA port multiplier 的证明。
厂方 `ug_sataio.c` 也区分原生与桥接两组启动。
但是公开 `rk3576_kernel` 中延迟注册 gate 名为 `...TIMESEQUANCED_INIT_DHX300`，
DH2300 原包配置名为 `...TIMESEQUANCED_BOOT_DHX300`；DH4300 Plus 原包没有该 INIT 项。
不能直接用这段不同配置源码认定原包注册顺序。因此进一步从两款**实际原包 Image** 恢复
kallsyms、重定位与 initcall 表，核对编译后的代码，而不是按公开源码分支假设：

| 原包 Image | SHA-256 |
| --- | --- |
| DH2300 Linux 6.1.115+ | `6da0fbc6632be9dca1d6524da8d95234184fcbc6daa6237bbddd44d9bf6c6967` |
| DH4300 Plus Linux 6.1.84 | `91a9cc80e58f5174a5fb845f8ee74ec3ddd4132ecf9331f4357da98a1d919113` |

使用 [vmlinux-to-elf 1.3.6](https://github.com/marin-m/vmlinux-to-elf) 只做静态恢复，
不执行原包内核。DH4300 Plus 解出 158787 个符号、253092 个 AArch64 RELA。
`arm_kernel_evidence.py`、`inspect_arm_kernel.py`、`inspect_arm_dt.py` 和结果
`arm-kernel-evidence.json`、`arm-ordered-controllers.json`、
`dh2300-ahci-disassembly.txt`、`dh4300plus-{ahci-disassembly,probe-chain}.txt`
均在 `firmware-inbox/work/almighty-disk-all/`。

实际原包证据链如下：

1. `of_platform_bus_create` 通过 `of_get_next_child` 按**原始 FDT 子节点链**创建设备。
   原包 FDT 顺序为 DH2300 的 `2a240000` 再 `2a250000`，DH4300 Plus 的
   `fe230000` 再 `fe220000`。后者并非地址从小到大，因此没有地址排序规则。
2. 实际 DWC 与 NANENG PHY 的 `platform_driver.driver.probe_type` 均为 0；
   `driver_allows_async_probing` 和 `__driver_attach` 反汇编证实默认走同步 probe。
   原包 U-Boot bootargs 没有 `driver_async_probe` 覆盖。
3. 两款实际 initcall 表中 PHY provider 均先于 DWC：DH2300 为
   `...a197580`（combphy）先于 `...a197710`（DWC）；DH4300 Plus 为
   `...a1b681c` 先于 `...a1b69a4`。pinctrl、regulator core 与 OF population 更早。
   两 PHY 依赖本 SoC 已注册的 CRU/syscon/reset，SATA 节点没有外接 regulator provider。
   普通板级资源链不需要靠一个 controller 等待另一个异步 provider 来决定 ATA 顺序。
4. DH2300 的实际 `ahci_dwc_driver_init@ffffffc009fe57f0` 直接同步注册 platform driver。
   DH4300 Plus 的实际 `dwc_ahci_deferred_regist@ffffffc008c436f0`
   等 `get_ug_sataio_pwr > 0` 后注册原生 driver；
   `gen_ahci_deferred_regist@ffffffc008c3e0e4` 则等 `> 1` 才注册 PCI AHCI。
   `ug_sataio` 在这两个阶段之间留有硬盘分组上电延迟，因此原生两口先、PCI 两口后。
5. `ata_host_register` 对成功注册 host 的局部端口设置 `local_port_no=i+1`，并按原厂注册
   次序分配 print_id。结合各自独立 `storage_serv` 表，得到下表的板级物理连接。

| 精确机型 | 原厂固定硬件连接 | 物理槽 |
| --- | --- | --- |
| DH2300 | OF `/sata@2a240000` 局部口1；`/sata@2a250000` 局部口1 | 2；1 |
| DH4300 Plus | OF `/sata@fe230000` 局部口1；`/sata@fe220000` 局部口1 | 2；1 |
| DH4300 Plus | OF `/pcie@fe170000` 后唯一 ASM1062 的局部口1、2 | 4、3 |

这是**由实际原包 kernel、DT、数据表连接起来的条件式静态转换**，未经本项目实机插拔验证。
生产运行时不再使用当前系统全局 ATA 编号，也不依赖 controller 注册顺序：只读稳定 OF 身份
和局部口，要求所有原生 OF 节点及端口都存在（含空槽）；DH4300 Plus 还要求唯一
`1b21:0612` / AHCI、两完整局部口，并核对 PCI 祖先的 `/pcie@fe170000`
OF 节点、compatible、reg 与 status。多出/缺失/重复 controller、错 DT model、错 OF 地址或 ASIC
都使整个自动布局失效。不同系统的 PCI domain/BDF、ATA/host 计数可变化。
成功的来源为 `firmware-of-topology`。扫描结束会重复核验全部结构。

已发现厂方开源仓库，可继续检查原厂 probe 顺序、of_alias_get_id、port/target 编号和板级 DTS：
[rk3576_kernel](https://github.com/ugreen-opensource/rk3576_kernel)、
[kernel-6.1.27](https://github.com/ugreen-opensource/kernel-6.1.27)。
下载的只读源码在 `firmware-inbox/work/almighty-disk-all/ugreen-kernel/`。
公开源码作为二级对照；决定性注册与 probe 事实来自上述实际原包 Image。
代码没有开放按当前系统 global ATA 编号定位 ARM 盘灯。

## 原厂仅 block_name 的 M.2 缺口

DH2600、DXP2800、DX4600/+/Pro、DX4700、DXP4800/S 的表只写
`nvme0n1` / `nvme1n1`，没有 bridge ID 或 root path。
这只能证明原厂枚举时的命名，不足以在 PVE、Unraid、Debian、TrueNAS 中确认 physical slot1/2。
安装盘的数量、探测并发和系统盘会改变 nvmeN；代码没有以名字回退。

继续取证应找该**精确板型**的原厂 ACPI/PCI root port 接线、官方 BIOS/板图/驱动规则，
或机主同时记录物理槽、PCI祖先和单槽插拔后的链接。只取得 lspci 设备列表仍缺“哪个 root port
是哪个物理 M.2 槽”的对应，不能照搬 Plus 或 DX4700+ 的桥 ID。
M.2 盘仍列出真实身份和稳定 PCI topology，但槽号 unknown；无已确认盘灯关联也不能 locate。

继续交叉核对了已有官方 1.17.0.95 原包的 `UGREEN-PKG-V2-FORMAT` storagemgr UPK，
`storage_serv` SHA-256 为
`87f72d0604fad4ee12179b1e0a279a3dfcf282fd57aed8666d7178e22bb71106`。
静态恢复 30 个名称，八款的所有 revision 仍只使用同样的 block_name0/1；
不是 1.20 删除了原有稳定拓扑字段。1.17 与 1.20 的既有机型硬件表完全相同，
后者仅新增 DXP4900 / iDX6021。可复现提取器 `extract_117_storage.py` 和
`117-storage-map.json` 留在 `firmware-inbox/work/almighty-disk-all/`。

需要实机证据时，可在该精确机型上运行仓库的只读采集器：

```sh
sudo sh scripts/collect-disk-evidence.sh > topology.txt
```

采集器只读缓存 sysfs，包含精确 DMI/DT、PCI 父链/ID/firmware_node/physical_slot、
SMBIOS Type9 原始槽表、ATA 局部口及盘型号；默认省略盘序列号/WWID，不调用 SMART、读盘、热重扫、
加载驱动或上传报告。在隔离 QEMU Linux 中已完成执行 smoke check。
若 BIOS Type9 明确给出 `M.2_1/M.2_2` designation 和 PCI BusAddress，这可以提供新的
固件物理槽证据；否则还需要同时记录**已确认的物理 M.2 标签与盘 serial/WWID**，
仅导出 nvmeN 或普通 lspci 列表不能代替该对应。需要盘身份对应时，用户可另行选择提供
`ugreenctl disk list --json` 中的目标盘标识；该命令输出包含 serial/WWID。

DXP2800 V1.2 的 SATA 与 M.2 分开判断：
[上游 issue 128 的机主](https://github.com/miskcoo/ugreen_leds_controller/issues/128)
给出了精确系统版本 `DXP2800 V1.2 251215` 和独立 LED 协议变更；原厂自己的 rev1/rev2
SATA 表都明确 ata1/2。因此仅在该完整 revision 字符串、真实唯一 Intel `8086:54d3` 两口
以及全部空口排他检查通过时允许局部口 1/2 转换。新修订没有独立硬件实测记录，若 ASIC
不同即 unknown。这一物理盘位条件不复制/推导 EM 的任何 LED 寄存器。
M.2 仍保留 unknown；已见不同机主的桥/设备枚举发生变化，不能用 Linux nvmeN 顺序补齐。

### SMBIOS / ACPI 槽证据核查（2026-10-16）

找到了来自原机 `dmidecode` 的
[DX4600 报告](https://github.com/linuxhw/DMI/blob/ef093a4754461de1c5a14bca0e3e65d6dc0c8ed0/Desktop/UGREEN/DX/DX4600/9919284BE86F)。
报告为精确产品 `DX4600`、系统版本 `JS0A40029`、AMI BIOS `5.19`（2022-06-16）、
SMBIOS 3.3。五条 Type9 都是通用 PCIe x1，名称为 `Slot 1` 到 `Slot 5`，
**五条 Bus Address 全为 `0000:00:00.0`，Slot ID 全为 1**。Type41 也没有 M.2 连接器标签。
这些是占位字段，不能把 `Slot 1` 或数字 `physical_slot` 直接认作物理 M.2_1。
该报告只证明这一板型/BIOS 的槽表不可用，不能外推其他修订都没有有效表。

原始报告只读保存在
`firmware-inbox/work/almighty-disk-all/m2-research/DX4600-DMI.txt`，SHA-256：
`c8d4e2469650fafd2a4c507d29f905e3a14cf22a7536de66077e19a993f81c14`。
上游加入报告的提交为 `ef093a4754461de1c5a14bca0e3e65d6dc0c8ed0`（2023-05-09）。
同一公开数据集当次 UGREEN 目录仅另有 Plus/Pro 等已知机型，没有其余七款缺口的独立槽表；
`linuxhw/ACPI` 当次公开目录也没有 UGREEN 原机表。检索结果与目录快照保存在同一研究目录，
不将“这次未找到”写成硬件不存在。

[DMTF SMBIOS 3.8.0](https://www.dmtf.org/sites/default/files/standards/documents/DSP0134_3.8.0.pdf)
7.10.8 明确 Type9 的 PCIe Bus/DevFn 指向槽中端点，不能拿它匹配上游桥。
将来若获得有效原机表，可研究以下**尚未实现**的条件式来源：精确机型/修订、明确物理
`M.2_1/M.2_2` designation、正确 M.2 storage slot type、唯一有效端点地址，并与实时
NVMe PCI class 和完整父链核对；重复/占位地址、泛称 `Slot N`、多端点歧义均拒绝。
这需要原机正例验证，当前没有新增生产 fallback。

[Linux PCI label 实现](https://github.com/torvalds/linux/blob/v6.12/drivers/pci/pci-label.c)
的 `label`、`index` / `acpi_index` 来自 Type41 或 ACPI 命名，索引不是本项目已确认的盘位号。
[ACPI PCI slot 实现](https://github.com/torvalds/linux/blob/v6.12/drivers/acpi/pci_slot.c)
也只是从 `_SUN` 注册槽名。两者可作为继续取证的材料，必须另证物理 M.2 标签的含义。

扫描器对这八款明确说明原厂只有 `nvmeN` 名称，并提示运行
`scripts/collect-disk-evidence.sh`；未收录机型的未知 NVMe 也提示该采集器。
现有校准格式只适用于 PCI ATA 连接，不能用它给未知 NVMe 猜槽号。
这些 reason 提示及八款全量拒绝定位已有 fixture，物理定位行为没有放宽。

2026-10-16 新查八款官网的下载分类及 NAS 应用页，各应用页列出 22 项，未见公开的
BIOS/UEFI/ACPI 下载项；另查官方 Debian12 完整源码目录及 x86 平台目录，未发现目标
连接器资料。国际下载入口返回 HTTP 429 后停止，没有重试或绕过。结论只限这些页面与目录，
不能声称官方不存在其他包。来源、页面哈希和检索范围见
`firmware-inbox/work/almighty-disk-all/m2-research/heartbeat-1135/research-result.json`，SHA-256
`b53db2701eaddb99578462d09249cf86a7aedb6a4b90b0e26cea376064aad4da`。
八款物理 M.2 连接器仍为 unknown，没有新增枚举编号 fallback。

后续有界检索又核对了新的原机记录：[DXP2800 V1.2 的 BIOS 笔记](https://github.com/aloli/ugreen-hal/blob/e8e41449b929cc6af17631629604856fd940c9e0/docs/hardware-notes.adoc)
列有两个 M.2 菜单项，但没有把物理连接器与 PCI 路径对应；菜单数字不能直接用作槽位规则。
[DX4600 Pro 机主的原始文章](https://post.smzdm.com/p/al87emmp/)另记录 NVMe 空槽可改变
endpoint BDF，因此单次枚举截图也不足以建立跨系统物理槽号。24 条查询及新原始资料、
固定提交与 SHA-256 保存在 `firmware-inbox/work/almighty-disk-all/m2-research/heartbeat-1305/`；
`research-result.json` SHA-256 为 `a1b6f8ee437e944d3db7f3a533df6d3104c3089134506f222b765ca6dcc7b938`。
仍未取得合格的物理标签与 PCI 拓扑配对证据，八款 unknown 状态保持不变。

## 测试、权限与校准

2026-10-26 已继续追踪原厂函数、NVMe 驱动的动态 instance 分配及启动层规则，
新增地址、容器提取哈希和边界说明见
[官方固件运行链路复核](FIRMWARE_RUNTIME_TRACE_20261026.zh-CN.md)。八款物理 M.2
仍为 unknown；用户已明确没有所询问机器，继续查官方包，不再重复询问。

同日按用户的 BIOS 版本提醒再次收紧 DXP2800 GT：原厂 rev1/rev2 表仍保留为事实，
运行时没有合格精确 BIOS 白名单，任何 BIOS 都不自动分配 SATA 盘位。仅在两版表中
逐字段一致的 NVMe/U.2 规则可独立使用；若库存里存在未映射 SATA，两个共享 U.2
灯位同时标为歧义并清空可定位字段，独立 M.2 不受这项共享灯歧义影响。
因此当前自动 SATA 为 23 款条件式、1 款未知 BIOS 路由、1 款无 SATA。

`tests/test_disk_mapping.c` 使用真实生产 `scan_at` 接口和合成 sysfs，无测试专用映射 gate。
已覆盖：稀疏 ATA 编号/非零 host、空槽、热插拔重扫、USB/分区/RAID/loop 过滤、
三方冲突、二进制 VPD 格式及截断/控制字符、Plus/Pro 单 ASIC 全空口、精确 EM revision、
四/六/八盘控制器角色、变化 endpoint BDF、额外 controller/缺空口/重复桥角色拒绝、
GT BIOS 双 revision、NVMe bridge/root-path、无物理盘灯返回 `-ENOTSUP`、校准权限/重复/槽数限制。
新增 12 款独立 NVMe bridge 表回归、480T 四连接器、GT M.2/U.2 与 iDX PCIe 第三连接器，
并检查同 ID 的额外空桥也会使 bridge-ID 映射失效。ARM 正/反例覆盖两原生 OF、四盘的
ASM1062 组、不同 domain/BDF、错误 model/reg/ASIC/桥 OF、缺空口等。
严格 Linux musl 静态构建（`-Wall -Wextra -Wpedantic -Werror`）与隔离 QEMU 实际运行通过。
完整 CMake/CTest 由主集成任务运行，不能把静态 fixture 当成 NAS 硬件实测。

同一 canonical NVMe 控制器路径、PCI 拓扑及一致身份的多个 namespace 归并为一个
物理盘，全部设备名和各自 WWID 保留为别名。代表设备名仅用于展示，不能决定物理槽号；
不同控制器仍分别校验，共享 GT SATA/U.2 灯位的碰撞保护不放宽。按序列号定位时同控制器
只计一次，不同控制器的相同序列号仍有歧义。列表 JSON 的 `namespaces` 提供归属关系。
扫描尾部重读身份后，再重新打开 `class/block`，仅比较候选设备名集合，不在这次最终采样中
读取慢属性；新增、消失、重复成员、容量溢出或目录读取错误使本次结果失败并清空输出。
最终采样包括尚未初始化或被过滤的整盘候选。这样可捕获身份慢读期间新出现、可能被旧
`readdir` 缓冲区/EOF 位置漏掉的 GT 同盘位 U.2 设备；第 3/第 5 次串号读取期间新增完整
及未初始化设备均有生产接口回归。定位须使用紧邻操作的新扫描结果；最终快照之后仍可能
发生热插拔，用户态扫描不能保证随后硬件成员永远不变。

管理员校准语法、root 所有权检查和来源许可见 [disk/NOTICE.md](../disk/NOTICE.md)。
校准绑定物理连接而非磁盘序列号/WWN，明确校准的布局是完整替换；不会与自动规则补齐混用。
unknown/歧义拒绝定位，已映射但无盘灯返回 unsupported。

本工作未提交/推送，未访问或修改 `E:\工作台\LLLED_FPK`。
