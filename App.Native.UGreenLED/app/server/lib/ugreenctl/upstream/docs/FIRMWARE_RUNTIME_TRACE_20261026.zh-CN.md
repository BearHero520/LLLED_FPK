# 官方固件运行链路复核（2026-10-26）

本轮继续 Almighty 的 25 款目标，不要求用户提供实机。用户已明确没有此前询问的
九款机器；DH2100 / DH2100+ 的排除范围没有扩大。以下是新增的静态取证，
不是新增硬件支持或实机验证。兼容状态仍以 `models/compatibility.json` 为准。

## 输入和提取位置

复用原包 `E:\工作台\固件\6800plus.img`，UGOS Pro 1.20.0.0142，
大小 1,303,473,152 字节，SHA-256：

`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`

2026-10-26 重新读取 DH2600 和 DXP480T Plus 的官方中国下载页，两页首个固件项
仍为 1.20.0.0142、MD5 `c5358c7713ccf2811aaa7c5adcc10721`，与已验证原包相同，
因此没有重复下载。仅核对这两个页面，不据此修改其余产品的最新版本记录。
页面原文、URL、时间和哈希保存在下述 `sources/manifest.json`。

既有提取目录为 `firmware-inbox/work/dxp6800plus/`；本轮可复现脚本、清单、
反汇编和新增提取物统一放在：

`firmware-inbox/work/almighty-firmware-deep-20261026/`

| 原始提取物 | SHA-256 |
| --- | --- |
| `fw.squashfs` | `62b6aa1eea58ad2ef7612696d790ad771887979f006148492d75e1feef41be49` |
| `initrd-unpack/initrd` | `d0f78b6e03702223360c8ccef689b3ffa8c23e21d56c02d96d69b3fcda0884c7` |
| `apt.squashfs` | `9f7e9bc8949ce888dc258dc5a3e32360293364e74c04d974a2cd33d0aa8f05e0` |
| `disk-mapping-1.20/sbin/storage_serv` | `62130bc458462f0400f23f3f495e43129ab241fea103f3bd0db55bb058cb387e` |
| `ctlmgr-fields/sbin/ctl_serv` | 见 `control-host-trace.json` 的输入哈希 |

新输出只保留在 work，不提交固件、原厂 ELF 或解包结果；没有执行原厂程序、
加载原厂模块或访问 NAS 硬件。

## NVMe：从表项追到实际比较和内核编号

此前已恢复的八款 `block_name` 表项没有变更。本轮继续追踪执行它们的代码，
避免把“表中没有 PCI 字段”扩大为“整包没有其他板级规则”。

`storage-runtime-disassembly.txt` 中的关键位置如下，地址均属于上述精确 SHA 的 ELF：

| 地址 | 已确认行为 |
| --- | --- |
| `0x12f15f3..0x12f1606` | `InterfaceTypeAndName` 对输入路径取 basename |
| `0x12f160e..0x12f1669` | 读取机型、硬件版本，再调用 `hardware.GetHardwareInfo` |
| `0x12f2073..0x12f2093` | 将原输入路径传给 `getNvmeSlot` |
| `0x12efa91..0x12efab5` | 区分长度 10 的 `block_name` 类型 |
| `0x12efabb..0x12efae7` | `filepath.Base(path)` 与该行 ID 字符串比较长度和内容 |
| `0x12f0085` | 比较成功后复制并返回该槽记录 |
| `0x12efb34..0x12efb83` | 单独的 `pcie_address` 路径，在输入中查找地址片段 |
| `0x12efbe0..0x12efc28` | 单独的 `pcie_bridge_id` 路径调用 PCI 信息查询 |

因此，对 `block_name` 成功匹配的记录，不会再进入该函数的 PCI bridge 查询。
`GetHardwareInfo` 本身也静态追到两次字符串 map 查询，没有在该函数中重新计算
物理连接器；完整指令与调用记录见 `storage_serv-control-disassembly.txt` 和
`control-host-trace.json`。这仍只说明这些函数的行为。

进一步从 **kernel.squashfs 与 initrd 两个独立容器**提取 NVMe 驱动，内容哈希相同：

| 模块 | SHA-256 |
| --- | --- |
| `nvme.ko` | `7073e46c15f19a7b712787554cc3f8b76e9634281d97bf46be3f4cdeb963a651` |
| `nvme-core.ko` | `a961e4fbf32ff27461c0f0423c4d4219e2f992c7b2940be310a95c7901353af1` |

`nvme.ko` 确实存在 UGREEN 分支：`.text+0x4903` 准备厂商字符串，
`+0x4916` 调用 `dmi_match`，匹配后到 `+0x4cdb` 设置 `0x20`，
随后 OR 到 quirks 参数中传给 `nvme_init_ctrl`。它不是物理槽号表。
官方公开的 [kernel-6.12 pci.c](https://github.com/ugreen-opensource/kernel-6.12/blob/c75c5abd60dd45f45966720293ce1ee505fb8615/drivers/nvme/host/pci.c#L3065)
及同提交 `nvme.h` 将这个分支解释为 `NVME_QUIRK_NO_DEEPEST_PS`。
公开源码为 6.12；这里用它解释常量，6.18.15 模块的实际分支以反汇编为证，
不声称二者源码逐字一致。

在实际 `nvme-core.ko` 的 `nvme_init_ctrl` 中：

- `.text+0x1ff1..0x2004` 调用 `ida_alloc_range`，范围从 0 到 `0xffffffff`；
- `+0x2013` 将返回值写入控制器的 instance 字段（本二进制偏移 `+0x58`）；
- `nvme_alloc_ns` 的 `+0xa1b6..0xa1c3` 从该 instance 和 namespace 编号构造盘名。

这条已追踪的命名链没有把数字与某个板级 M.2 丝印对应，不能移植成
“nvme0 恒等于物理第一槽”。没有在生产代码中增加这种 fallback。

启动层也已新增核对：原始 newc cpio 共索引 2,829 个成员；检查不含 NUL、
不超过 256 KiB 的普通文本，保存匹配片段及行号。已提取的
`60-persistent-storage.rules` 为 by-id/by-path 命名规则，未在这些规则中发现
物理 M.2 重编号。`init` 的 SHA-256 为
`18d0c775901e99136f27b785e5cf40df78bbfd3786e782e81e94ccd4bc39ea51`。
fw/kernel/OEM 列表和 160 项路由/配置/模块提取记录见
`boot-asset-index.json`、`initrd-text-hits.json`、`routing-extraction.json`。
这些有界范围不构成对所有二进制、脚本或匿名资源的缺失证明。

八款的 **M.2 物理槽号**仍为 unknown：DX4600、DX4600+、DX4600 Pro、DX4700、
DH2600、DXP2800、DXP4800、DXP4800S。它们已有的 SATA 和 LED 能力不因此撤销，
也不把缺独立 M.2 灯解释为无需确认物理连接器。

## LED：用户态服务到 N76 驱动的读取边界

新增追踪 `ctl_serv` 的五个实际服务函数，而非只搜索名称：

| 函数 / 指令地址 | 已恢复的接口 |
| --- | --- |
| `AdjustColor`，`0x1940145` | 写 `/sys/class/leds/%s/color` |
| `AdjustLight`，`0x19405cb` | 写 `/sys/class/leds/%s/brightness` |
| `AdjustTrigger`，`0x1940a85` 等 | 写 trigger、delay_on、delay_off 等属性 |
| `GetState`，`0x1941a86` | 读 `/sys/class/leds/%s/state` |
| `build`，`0x193e900` | 构建并保存 INI 配置 |

命令字符串长度也按 Go 调用前的长度常量核对；反汇编中相邻 rodata 字符串
不是该命令的一部分。上述方法调用 `utils.ShellExec`，没有在这些函数中另走
N76 I2C 读回。结合此前已确认的 N76 `.state` 缓存字段来源，这个用户态 getter
不能补足 A0/B1/E0/E1 的真实输出、色盘、亮度或时序读取定义。

DMI 到模块的原厂路由仍由 `usr/sbin/ug-load-drive.sh` 确认：
DH2600 加载 `leds-mcu-n76e003-dh2600`，DXP480T 分支加载
`leds-mcu-n76e003`。本轮新增的是服务调用证据，没有修改已经记录的
I2C 地址、芯片 ID、模式读取或写寄存器定义。

为查找可能漏掉的升级程序或内嵌载荷，额外提取/检查了 13 个指定 host：
`UGN_Remote_Firmware_Tool`、ug-core、uginstall、ugpostinst、ugdevice、ugpwproctl、
四个 hwmonitor、uginit、ugupdate、ctl_serv。结果见 `host-asset-analysis.json`。
对 ELF 做目标字符串、Go 函数元数据/本机符号和有界 gzip 验证；未得到新的
N76 MCU 程序或可信读回定义。gzip 检查每个 host 最多 256 个魔数候选，
解压上限 4 MiB，**不覆盖裸 8051 程序、其它压缩或加密/无名载荷**。

其中新候选 `UGN_Remote_Firmware_Tool` SHA-256 为
`04b115d94d121d98c27672873bdfd4c4bf412745e40ef3871af4951d95e4cbb4`，
包含 HDMI remote 的云 API、HID/DFU 及 dongle/RCU 更新路径；这些具体标识支持
将它分类为 HDMI 遥控器更新工具，不能拿它推导 NAS N76 LED 协议。
另为 1.20 apt.squashfs 新建完整文件清单和有界候选索引；这仅是索引证据。

随后继续拆解原包的全部 20 个内置应用 UPK：实际包含 18 个
`UGREEN-PKG-FORMAT` 和 2 个 `UGREEN-PKG-V2-FORMAT`，按各自 magic 和长度
字段解析，再进入嵌套 UGB tar，没有把一种包头长度套到另一种格式。
新增索引 5,209 个成员，提取并检查 380 份不超过 1 MiB 的配置/安装脚本等文本。
其中 wizard / ugos_serv 共 31 个成员、11 份文本，另检查 discovery_serv、
ugos_serv 和 `libugos_serv-shared.so` 三个 ELF。结果分别保存在
`all-app-analysis.json`、`all-app-routing-summary.json`、`nested-host-asset-analysis.json`。
有界文本命中主要是网页翻译；唯一非网页命中是 ctl_serv 的 HTTP firmware 路由，
没有在这些脚本/配置中取得新板级规则。清单没有新命名的 MCU/HEX/BIN/ROM 目标，
这不排除匿名二进制载荷或尚未追踪的共享库调用。

DH2600 / DXP480T Plus 无原厂驱动的控制仍未完成。现有绑定原厂驱动的 sysfs
路径保留其“驱动缓存”标记，不伪称直接硬件回读，也不以 ACK 代替状态读取。

## 状态、验证与后续

没有修改硬件寄存器、生产 C 或测试源码，没有开放未知映射。25 款目标中，
八款 M.2 和两款无驱动 N76（重叠 DH2600，共九款）的缺口仍保留；
所有机型的 LED/盘位实机验证均未执行。

`result-accepted.json` 汇总本轮输入、关键地址、静态断言、证据哈希及剩余工作；
根 `checkpoint.json` / `verification-root.json` 记录最终 Release 构建、
CTest 结果及当前源码/二进制哈希。测试 fixture 和隔离 QEMU 不能代替 NAS 实测。

本轮两架构 Release configure/build 成功，Ninja 均无待构建对象；完整 CTest
各 24/24 通过，独立日志为 `ctest-x86_64.log` 和 `ctest-aarch64.log`。
38 个发布候选二进制与此前冻结哈希相同；没有重复运行相同 payload 的 ABI 虚拟机。
证据文档同时加入 CMake 安装和本地打包清单；更新后的安装目录与文档哈希单独验证，
避免分发的目录留下指向缺失文档的链接。

下一步按新断点继续：追原始 vmlinuz 中与控制器注册有关的板级初始化，以及
原厂硬件信息服务所链接共享库的实际实现；从 ELF 的依赖/重定位找到入口后
才扩展反汇编，不重复这次已经完成的 20 包文件名扫描。对裸 MCU 载荷需要
容器/长度/引用等正向识别证据，
不把随机字节片段认作 8051 固件。不再反复询问用户是否持有这些机器，
也不以等待采集资料替代可做的固件工作。

未提交、未推送、未发布，未访问或修改 `E:\工作台\LLLED_FPK`。

## BIOS 变化保护补充

用户提醒部分机型 BIOS 更新可能改变回读，并指向 main 的 DX4600 记录。
只读核对的 main 提交为 `1283704`；其中 `1f4f17d` 保存了用户报告的精确
DX4600 风扇、来电启动和 WOL 工作基线（应用 2.1.2、fnOS 内核 6.18.18.c1032-trim），
并没有将该记录扩大到 LED、盘位、DX4600+/Pro 或任意新 BIOS。
`90959b0` 则修复 it87 hwmon 的缓存读取延迟：立即回读不符时等待 2 秒再读，
仍不符即失败。当前分支保留这个修复，没有把 hwmon 错误当成直控回退条件。
这些提交未给出精确的 BIOS 更新前后版本和寄存器变化对照，不能据此编造 BIOS 黑/白名单。

新增实现读取 DMI 的 BIOS vendor/version/date，缺失为 unknown；LED JSON 输出为 null，
并单列 `bios_compatibility=not-independently-validated`。LED 会话每次读取/写入均重新
核对机型、产品修订、主板及 BIOS 文本身份；不同或不可读取则拒绝操作。sysfs 的
逐属性写入、identify 恢复也经过该授权检查。CS2011 在任何配置端口访问前检查
完整身份。会话一致性不证明 BIOS 兼容，也不证明芯片固件版本一致；没有可靠接口
时 MCU 固件版本仍 unknown，不能用 BIOS/UGOS/内核版本替代。

审查还发现 DXP2800 GT 的旧默认分支会把任意非 LL_ BIOS 选成 rev2，而两版 SATA
顺序恰好相反。现已移除这个兜底：无精确 BIOS/主板与物理槽配对证据时不自动定位
GT SATA；只有两版事实表逐字段相同的非 SATA 项独立保留。未映射 SATA 存在时，
共享 U.2 灯位也拒绝定位；明确校准仍用原有完整替换与碰撞检查。新增的未知 BIOS、
混合 SATA/U.2、身份变化和缺失字段用例均通过生产入口测试。

这项收紧使当前 SATA 自动映射数从 24 调整为 23；另有 GT 的 BIOS 路由缺口和
480T 的无 SATA 情况。八款未知 M.2、两款无原厂驱动 N76 以及所有实机验证限制不变。
本阶段独立验证记录位于 `firmware-inbox/work/almighty-bios-20261026/`，
旧 `almighty-firmware-deep-20261026/result-accepted.json` 对应修改前的历史快照。

## 继续读取原包：内核、共享库与升级工具

按用户要求继续复用同一个已校验的 1.20.0.0142 原包，不以缺少实机停止固件分析。
本次独立输出目录为 `firmware-inbox/work/almighty-official-followup-20261026/`，
三个子目录 `kernel/`、`native/`、`n76/` 分别保存解析脚本、输入哈希、实际指令或
源码行号和报告。没有改动生产 C、测试源码或兼容目录的能力状态。

### 原始内核中的枚举和板级分支

从 tar 成员 `./vmlinuz` 的实际 HdrS 头定位 zstd 载荷（文件偏移 `0x52cc`），
而非把任意压缩魔数当作入口。该成员 SHA-256 为
`63fe8f45eedb6805e1bb9a3d79b0e65063ace44ca0d40f6d013d6705593cdf52`；
解出的原始 ELF 为 57,635,600 字节，SHA-256 为
`4420385c4328e15dbff6ee3c120f94e29feacacd33a1fc6d49b5ed8f0fe238bf`。
恢复 173,029 个 kallsyms，并用 `_text` 及符号表自身地址交叉核对；反汇编仍读取
原始 ELF 的字节，新增符号 ELF 仅用于辅助查看。

已闭合 `acpi_pci_root_create → pci_scan_child_bus → pci_scan_child_bus_extend →
pci_scan_slot`：`pci_scan_child_bus_extend@0xffffffff819ffc40` 的循环按 devfn
从 0 每次增加 8 至 `0x100`。另一个实际入口 `dmi_check_pciprobe` 将真实
`pciprobe_dmi_table` 传给 DMI 检查；借 BTF 确认结构大小后解出 24 条记录，
这些记录属于 Dell/HP/Stratus/NEC。其排序回调设置 `pci_bf_sort=3`；
`pcibios_init` 的可选排序按 domain/bus/devfn 比较。

另外解出 `.pci_fixup` 的 990 条记录、213 个 hook；涉及 NVMe 名称的已查 hook
为 ASUS 电源管理修订。UGREEN/DXP2800S 的实际字符串引用位于 watchdog profile
选择，GT 初始化涉及 watchdog 和 `/proc/it86`，不能当成 M.2 编号依据。
这些结论限定于已追到的入口和表，不扩大为“整包没有板级规则”。

`register_slot@0xffffffff81ab4eb0` 确实消费 ACPI `_ADR` / `_SUN`，这是继续查证
板级槽位的正向入口；本轮尚未取得八款目标实际 AML 与机壳/主板物理槽号的配对。
PCI 枚举顺序和原厂 `nvme0n1` 表项仍不能直接变成跨系统的物理槽位。

### 硬件信息服务的真实实现

从 ELF 的 `DT_NEEDED` 和重定位追到
`ugos_serv → libugos_serv-shared.so → libcore-ugos.so / libproto-ugos.so`。
新提取的两库 SHA-256 分别为
`9a68b6e8017651943a3dfafb13cbc19f68baec22ee3685f7f2662d25d616f2f9` 和
`95f0a08b4e123c292da18e70c77c1f87d82a6f4315210291cde6e379e8e270ca`。

实际创建的 `InfoServiceImpl` 在 vtable 槽 `0x1c9c30` 保留基类
`GetHardwareInfo` 导入；对应 `libproto-ugos.so:0xfdd380` 的 50 字节函数仅写入
状态码 `0x0c`、空字符串并返回，没有读取硬件。这与生成的 gRPC 未实现默认项一致，
不能把方法名或请求字段当成另一张实际槽位表。

另一条真实链路 `get_model@0x137840 → read_dmi_info@0x136cb0 →
File::ReadFile@0x138b10` 读取 DMI `product_name`。完整恢复的 native 模型枚举为
32 项，没有 GT 项。`get_hw_version@0x12d2e0` 对 DXP2800/2800S/2800A 使用
`product_version` 的 `EM_` 前缀；对 DXP4800 Pro 使用 `get_cpu` 结果中的
`i3-1315u` 匹配。该 getter 本身也有 DMI/CPU 信息读取，且没有建立其与 Go
存储路由版本相等的证据，不能拿 native 的 rev 标签补 GT 的 BIOS→SATA 缺口。
原厂 helper 的环境覆盖及缓存机制没有移植进生产身份识别。

### 升级工具中确实存在的 MCU 路径

原包 `./ugpt` SHA-256 为
`b5f8ba95b488f43a1be47f0a8fd86db5750acf818572900604666e3a519f3dc8`。
它实际是 Makeself 2.4.5 shell 加 gzip tar，按头部的 713 行/长度边界分层解析，
并核对嵌入 MD5；不是 ELF。10 个成员中实际插件只有 echo 和 upgrade，
全部读取源码，没有运行归档、插件或升级命令。

`plugin/upgrade_tool.py:1374..1382` 仅在显式 `arch_spu=rk3588` 分支调用
`updata_mcu_fireware`。该函数查找 `UGREEN_CEC_Controler_APP_*`，使用
bus 4 / address `0x15` / register `0x11` 查询版本，再按条件将包暂存到 `/boot`；
本函数本身没有 MCU 刷写事务。源码里的强制 I2C 访问仅作为原厂证据记录，
没有执行，也没有加入本项目后端。

这条具体路径与 DH2600/480T 的 N76 `0x31/0x26` 不是同一接口，不能提供它们的
输出、亮度和时序真实读回定义。它排除了一个有实际升级入口的候选，不证明其它
未追踪载荷不存在。两款 N76 仍依赖绑定原厂驱动；八款 M.2 与 GT BIOS 路由仍未知。

本阶段重新完成两架构 Release configure/build 和完整 CTest，各 24/24 通过；
原有 38 个二进制哈希保持不变。native 的 10 项字节/符号/重定位断言、升级分支
的 7 项 AST 断言和内核结构/符号自指检查分别保留在子报告中。
离线证据与 QEMU 结果不升级为实机验证；没有提交、推送或修改 `LLLED_FPK`。
