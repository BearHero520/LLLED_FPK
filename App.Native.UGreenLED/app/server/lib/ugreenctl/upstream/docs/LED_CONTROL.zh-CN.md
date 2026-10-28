# 灯光、盘位与旧命令兼容

本功能已从原 Almighty 合入 `main`，后续源码与使用说明统一以主分支为准。
当前预览包的下载、校验和目录结构见 [README](../README.zh-CN.md#下载与快速开始)。

本功能面向 Linux x86/x86_64 及 ARM64，首批部署目标为飞牛、Debian/Ubuntu、
PVE、Unraid、TrueNAS SCALE。RGB MCU 通过通用 `i2c-dev` 和档案指定的
SMBus 控制器访问；N76 和 ARM GPIO 的后端依赖不同，不能笼统承诺无需
原厂驱动。全机型扩展仍在集成，逐款进度及协议证据见
[全机型 LED 证据](ALL_MODELS_LED_EVIDENCE.zh-CN.md)，固件输入及校验见
[固件取证清单](ALL_MODELS_FIRMWARE_INTAKE.zh-CN.md)。各目标系统的真实硬件验证仍待分别记录。
官网目录保留 27 款；用户已排除 DH2100 和 DH2100+，本轮交付范围为其余 25 款。
运行库、Unraid/SCALE 持久目录及正常停止要求见 [Linux 部署指南](LINUX_DEPLOYMENT.zh-CN.md)。
PVE 应在宿主机运行；容器或虚拟机中的诊断结果不能代表宿主机硬件可控。

## 命令

新命令的 `--json`、`--apply`、`--force` 可以放在命令前后。
LED/盘位命令使用内置能力档案，不需要加载风扇 `.so` 插件。

```sh
# 查看本机档案声明的灯位和功能；不访问 I2C。
ugreenctl led list

# 读取实际灯光状态、总线和芯片身份。
sudo ugreenctl led status
sudo ugreenctl led status disk1 power --json

# 先预览。颜色支持名称、引号包围的 #RRGGBB、R,G,B。
ugreenctl led set disk1 --color blue --brightness 50% --mode on

# 当前写入档案全部是实验性，实际写入需要两项选项。
sudo ugreenctl led set disk1 --color '#0080ff' --brightness 128 --mode breath \
  --on-ms 800 --off-ms 800 --force --apply
sudo ugreenctl led off all --force --apply
sudo ugreenctl led on power --force --apply

# 闪灯定位，默认 5 秒，允许 1..60 秒；完成后恢复之前的状态。
sudo ugreenctl led identify disk1 --seconds 5 --force --apply

# 无需访问硬盘数据或执行 SMART 检查的物理 ATA 盘点。
ugreenctl disk map --json
ugreenctl disk list

# 仅在唯一且已经确认的物理映射上定位。
sudo ugreenctl disk locate /dev/sdb --seconds 5 --force --apply
sudo ugreenctl disk locate serial:YOUR_SERIAL --force --apply
sudo ugreenctl disk locate slot2 --force --apply
```

同一个 NVMe 控制器的多个 namespace 归属于同一物理连接器；`disk list` 的
`namespaces` 列出全部设备名及各自 WWID，任一 namespace 路径或 `wwn:` 可定位同一盏灯。
合并要求实时控制器路径、PCI 拓扑和身份一致，不按 `nvmeN` 编号推断槽号。
盘点结束前再次核对设备集合，出现热插拔变化时返回失败，需重新扫描后再定位。

RGB 分量为 `0..255`。原始亮度、色盘和模式以 `led list` 中每盏灯的能力为准；
亮度也可使用 `0%..100%`，直接按该目标的最大亮度四舍五入换算，并须满足目标最小亮度。
例如最大值为 254 时，`75%` 为 191；不会先转换到 255 再次缩放。
DXP480T Plus 的 N76 用 `0/1` 表示开关，实际 PWM 仅 `2..254`；DH2600 的
专用 N76 callback 只有二值开关，不能宣称可调 PWM。熄灭用 `led off`，
不会将 `0%` 冒充该硬件的 PWM 亮度。双色硬件使用受支持的
`white/orange/white-orange` 或 `channel1/channel2`，不会把它们冒充 RGB；
未知物理色调只标通道。`--mode` 在目标支持时接受 `on/off/blink/breath`。
不支持的颜色、亮度范围或模式在任何写入前拒绝。闪烁和呼吸的亮、灭时间单位为毫秒，
各项非负、总和须为 `1..65535`，默认 `500/500`。
仅设置颜色或亮度保留当前模式；点亮时应明确加 `--mode on`。
多个目标以空格分开；`all` 不与单个目标混用。
新 `led set` 将颜色、亮度和模式合并成每盏灯的完整意图，避免先设置 GPIO
熄灭态不存在的颜色寄存器；兼容入口仍保留旧工具的逐动作顺序。硬件总线的
多字段写入仍可能由多条事务完成，不能因此宣称硬件原子性。
实际写入前会读取全部目标，并检查各目标当前状态对应的限制；后续目标已知不能执行时，
整条请求在首次写入前拒绝。N76 当前模式未知或正在执行效果时，单独改颜色/亮度不能
推断应保留的模式，需明确给出完整模式及其必要时序；双色同时点亮不能请求原厂单通道闪烁。
兼容入口的动作按原顺序预检，真正写入前后端仍重新检查当前状态。
N76 还会在首次写入前核对所有选定目标及全部兼容动作所需的已注册 trigger：
稳态开关及保留稳态的颜色/亮度变更需要 `normal`，闪烁需要 `timer`。
按完整名称匹配，`abnormal` 不能代替 `normal`，`timer2` 不能代替 `timer`。
例如兼容请求先闪烁再点亮时，即使 `timer` 已注册，缺少后续动作所需的
`normal` 也会使整条请求在零写入时拒绝。identify 缺少所需的 `normal` 时，
在首次闪灯前返回，不执行已知无法完成的闪灯或恢复写入。
预检不锁定内核 trigger 的注册状态，也不构成原子事务；实际写入仍重读状态、
核验身份和控制者，中途出现变化仍可能失败并报告已完成数量。

定位期间保持同一控制器锁；SIGINT/SIGTERM 会触发恢复。恢复仍执行身份和
所有者检查。如果设备掉线、出现新的控制者或进程被 SIGKILL，恢复无法保证，
命令不会把恢复失败报告成成功。多目标写入不具备硬件原子性；中途失败会报告
已完成操作数量，不会静默切换另一种协议重试。
sysfs 每次属性写入都重新检查身份、绑定和控制者；恢复过程中出现新的控制者时同样停止。
恢复回读的必要字段为 unknown 时返回失败，不会把结构默认的 off/0 当作已验证状态。
旧命令的文本 `-status` 按执行顺序立即输出，后续动作失败时保留先前已读到的状态；
`--json` 始终返回单个结果或错误对象，错误中的计数仅包括已成功完成的写入意图。

## 首阶段基线档案与证据

下表保留最初七个档案的基线；新增机型、独立修订、SMBus block、N76
和 ARM 的当前实现状态以全机型证据文档及 `models/led_profiles.c` 为准。
录入档案不等于已经完成跨系统、实机或全机型发布验收。

| 精确 DMI | 额外版本限制 | 灯位 | 实现与状态 |
| --- | --- | --- | --- |
| DX4600 Pro | 无已知独立修订限制 | power、netdev、disk1..4 | legacy I2C block，实验性 |
| DXP2800 | `product_version=EM_DXP2800_V1.0.24` | power、netdev、disk1..2 | legacy I2C block，实验性 |
| DXP4800 | 无已知独立修订限制 | power、netdev、disk1..4 | legacy I2C block，实验性 |
| DXP4800 Plus / DXP4800 Pro | 各自精确 DMI | power、netdev、disk1..4 | legacy I2C block，实验性 |
| DXP6800 Pro | 无已知独立修订限制 | power、netdev、disk1..6 | legacy I2C block，实验性 |
| DXP8800 Plus | 无已知独立修订限制 | power、netdev、disk1..8 | legacy I2C block，实验性 |

以上为上游代码/实机记录支持的协议档案，不是本项目新完成的实机验证。
`led list` 仅表示已编译的档案与真实 DMI 相符；总线、MCU、状态与写入条件
需要通过后续实际访问核验。无版本限制表示尚无独立修订资料，不承诺未来修订兼容。

上述 legacy 档案写入固定使用该档案的协议，要求地址 `0x3a`、身份寄存器 `0x5a` 读取到
`0xc5b2`。同一身份值不能自动选择协议。身份缺失/为零时可尝试有效状态的只读
诊断，但写入拒绝。新增 DXP2800 V1.2 仅匹配已确认的精确修订；block-be
与 block-le 校验不同，不能因 MCU 身份相同而互相回退。N76 与 GPIO 的
缓存、不可读字段和驱动依赖另见全机型证据文档。

传统协议从 `0x81 + LED_ID` 读取 11 字节状态及大端累加校验；12 字节命令
分别设置亮度、RGB、模式和计时，从 `0x80` 读取 ACK，再回读目标字段。
代码位于 `led/led_protocol.c`、`led/led.c`；机型接线为 `models/led_profiles.c`。
DX4600 固件身份依据见 [原厂逆向记录](DX4600_REVERSE_ENGINEERING.zh-CN.md)。

总线编号动态发现，不固定为 `/dev/i2c-1`；多个匹配档案的 SMBus 总线存在时拒绝猜测。
已绑定驱动、已知原厂/第三方 LED 模块或控制进程存在时拒绝直接访问。
固定进程锁为 `/run/ugreenctl-led-mcu.lock`，使用普通 `I2C_SLAVE`，不强占内核设备、
不加载或卸载模块。`--force` 只确认实验性，不绕过上述检查。
第三方程序不遵守本项目锁时仍可能竞争；检查不能替代对控制者的明确协调。

## ARM GPIO 常驻持有进程

Linux GPIO 字符设备的线路请求由文件描述符持有；关闭后不能保证输出继续
保持（见 [Linux GPIO 线路请求 ABI](https://www.kernel.org/doc/html/latest/userspace-api/gpio/gpio-v2-get-line-ioctl.html)）。
因此没有原厂 LED 驱动时，DH2300、DH4300 Plus 使用显式的常驻持有进程，
不会把一次写入后立即关闭线路的短命命令当成持久控制。

```sh
# 在独立终端前台运行，或按下面示例配置系统服务。
sudo ugreenctl-ledd --force --apply

# 另一个终端：先看本机灯位和能力，再执行控制。
ugreenctl led list --json
sudo ugreenctl led status --json
sudo ugreenctl led set disk1 --color white --brightness 100% --mode on --force --apply
```

持有进程只接受已取证的精确 ARM 设备树、GPIO 控制器和线路配置，保持固定
控制器锁与 GPIO 线路文件描述符；每次写入重新检查身份、所有者并通过 GPIO
值读取核对。GPIO 亮度是实际的 `0/1`，不承诺 PWM 渐变。可用色调以各目标
`led list` 为准；通道名别名不会增加硬件支持的颜色。

CLI 通过 root 拥有、权限 `0600` 的 `/run/ugreenctl-ledd.sock` 通信，双方检查
内核提供的进程凭据。一个连接独占整次操作，包括定位及恢复；错误、忙或身份
不符不会切换成直接访问。每条写请求仍需 `--force --apply`。
SIGINT/SIGTERM 关闭持有进程会释放线路，之后的电平保持不作保证。

`scripts/ugreenctl-ledd.service` 是可审阅的 systemd 示例，默认可执行路径为
`/usr/local/bin/ugreenctl-ledd`。源码安装只把示例放入文档目录，不自动安装、
启用或启动服务；使用其他 PREFIX 时需相应调整路径。Unraid 等没有 systemd
的系统可由其本机服务管理器以前台进程方式托管。

N76 不是 GPIO 控制器，不能使用该持有进程替代其芯片协议；原厂驱动缺失且
直接读回证据不足时，相关功能仍明确拒绝，不计为跨系统适配完成。
用户已确认目前无法接触 DH2600 和 DXP480T Plus，两款仍在本轮 25 款目标范围内；
此项可接触性已明确，不再等待或重复询问。两款无原厂驱动时的支持仍未完成。
[只读 LED 采集说明](LED_EVIDENCE_COLLECTION.zh-CN.md) 保留供今后取得实机资料时使用；
它不会自动开放未知的 MCU 寄存器，也不能单凭缓存值证明输出回读。

## DXP2800 GT 的显式灯效接管

CS2011 的全局 `FLOW` 为 0 时，普通短命 CLI 拒绝默默关闭原厂自主灯效。
精确 DMI、芯片身份、已激活的 Host2EC 与动态基址均通过验证后，可显式启动：

```sh
sudo ugreenctl-ledd --takeover-flow --force --apply
# 另一个终端，仍可使用相同的原生命令或兼容入口。
sudo ugreenctl led set disk1 --color blue --mode on --force --apply
sudo ugreenctl disk locate slot1 --seconds 5 --force --apply
```

持有进程保存四盏灯的全部 28 个原始字段与 FLOW，检查两次快照稳定、写入 FLOW=1
后回读并确认灯位字段没有改变。控制结果在持有进程运行期间保持；正常退出会先恢复
全部原始灯位字段，再恢复原 FLOW 并核对，失败会明确报错。原自主动画的内部相位无法
保存或保证恢复。若 FLOW 原本已为 1，可省略 `--takeover-flow`，仍按完整生命周期恢复。
没有持有进程时，原来 FLOW=1 的普通直控路径保持可用。

接管不会激活未启用的 LDN，也不会调用原厂 `InitEc()`、修改风扇、ADC、看门狗或电源
策略。原厂驱动或其他控制器所有者存在时仍拒绝。`scripts/ugreenctl-ledd-gt.service`
提供单独的可审阅示例，只作为文档安装，不自动启用；不要与普通 holder 同时运行。
GT 的定位快照由服务端保留原始字节，客户端中断或断线也会触发恢复，不通过解码后
重新编码来猜测未使用的时序。掉电、SIGKILL 和其他控制器接管仍无法保证恢复。
ARGB 寄存器的真实硬件可读性尚未实机验证，静态证据及限制见
[GT 逆向记录](DXP2800_GT_LED_REVERSE.zh-CN.md)。

## 盘位自动映射与首次校准

当前 25 款中，23 款已接入条件式 SATA 自动映射；DXP2800 GT 因两版 SATA
顺序相反且缺精确 BIOS 配对证据保持 unknown，可使用已有管理员显式校准；
DXP480T Plus 没有 SATA 盘组。
15 款已接入条件式 NVMe 物理槽规则，8 款仍缺物理 M.2 连接证据，两个 ARM
目标没有原厂 NVMe 盘组。DXP480T Plus 的四个 NVMe 槽有条件映射，但没有独立
盘灯，不能把盘灯不适用理解为物理槽映射不适用。逐款状态见
[全机型盘位证据](ALL_MODELS_DISK_EVIDENCE.zh-CN.md)。不能将固件中的
`nvme0n1` 等枚举名直接作为跨系统稳定的物理槽号。映射使用 PCI
控制器和其本地 ATA `port_no`，不依赖 `/dev/sdX`、全局 ATA 编号或 SCSI
host 的枚举顺序。每次重新扫描，空槽不会把后面的盘向前挤；USB、分区、
虚拟块设备和未确认的拓扑不会冒充内置盘位。序列号/WWN 仅表示当前硬盘身份。

Plus/Pro 要求唯一 ASM1164 四口 AHCI 控制器，EM DXP2800 要求唯一 Intel
`8086:54d3` 两口 AHCI 控制器；核验全部本地端口（包含空口），不固定 PCI 总线号。
这两个方案同时采用原厂 ATA/灯号表、一手硬件资料和运行时完整拓扑检查。
证据见 [官方固件映射核对](DISK_MAPPING_FIRMWARE.zh-CN.md)。
DX4600 Pro 的 SATA 条件映射已接入，仍要求完整控制器角色与本地端口校验；
其 M.2 物理槽号保持未知。未匹配拓扑或变更布局显示 `unknown`。
自动档案来源、逐端口数据与校准格式见 [盘位证据和许可](../disk/NOTICE.md)。
上游记录不能替代对主板修订、BIOS/控制器拓扑变更的实机复核。

首次校准步骤：

1. 执行 `ugreenctl disk list`，记录当前硬盘身份与 `topology`。
2. 对照实物盘标签确认硬盘位于哪个槽；使用 `led identify diskN` 确认面板灯号。
3. 将已确认槽位与输出的实际拓扑写入 `/etc/ugreenctl/disk-map.conf`。
4. 设置文件所有者为 root，权限为 `0644` 或 `0600`，重新运行 `disk map`。

格式示意（`<...>` 必须替换为步骤 1 的实际输出）：

```text
model=DXP4800 Plus
slot1 topology=<一号槽对应的实际 topology>
slot2 topology=<二号槽对应的实际 topology>
```

校准文件必须是 root 拥有、组/其他用户不可写的普通文件；拒绝符号链接、
错误机型、重复槽位或重复拓扑。不执行 shell。也可传 `--map-file PATH`。
校准文件完整替换自动档案，未填写的槽位保持未知。更换硬盘无需重新绑定序列号，
改变硬盘连接、控制器或 PCI 拓扑后需要复核。映射缺失或有歧义时 `disk locate`
返回非零错误，不尝试点亮推测的盘位。

## ugreen_leds_cli 兼容入口

构建会生成独立的 `ugreen_leds_cli`。显式安装它：

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DUGREENCTL_INSTALL_LED_COMPAT=ON
cmake --build build
ctest --test-dir build --output-on-failure
sudo cmake --install build
```

默认安装关闭此选项，以免替换系统已有的同名工具。可以先使用构建目录中的
完整路径验证。兼容程序与新命令共用 C 后端，不调用外部旧二进制。

```sh
sudo ./build/ugreen_leds_cli all -status
sudo ./build/ugreen_leds_cli power -on -color 0 0 255 -brightness 128 -status \
  --force --apply
```

兼容 `power/netdev/disk1..8/all` 与 `-on/-off/-color/-brightness/-blink/-breath/-status`。
对每个目标按输入动作顺序执行；实际写入成功默认静默，`-status` 保持传统文本字段。
无动作表示读取状态。旧脚本需要补充 `--apply --force` 才会写硬件；默认是预览。
这项安全差异必须显式迁移，不宣称旧写脚本可完全不改直接运行。

## 机器接口与错误

LED/disk 的 JSON 使用 `schema_version=1`，成功包含 `ok:true,data`，失败包含
`ok:false,error`。标准输出仅一个 JSON 对象，诊断写标准错误。
明确的 LED/disk 命令若带前置未知选项，同样返回 `invalid_argument` 和退出码 2；
请求 `--json` 时仍只输出一个错误对象，并在参数校验失败时不访问硬件。
未知盘位为 `mapped:false,slot:null,led:null`；缺失硬盘身份字段为空字符串。
物理盘位已确认也可能没有独立灯光：`mapped:true,led_supported:false,led:null`。
`interface` 和 `slot_name` 区分 SATA、NVMe/U.2 对应槽位；定位要求另有已确认
可控盘灯。LED 状态的 `unknown_fields` 输出不可读字段，`cached_fields` 明确
标注驱动缓存；未知数值输出 `null`，缓存不代表硬件寄存器的实测回读。

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功或明确标识的预览 |
| 2 | 参数错误 |
| 3 | 型号、协议或硬件身份不支持 |
| 4 | 权限、占用或缺少实验性确认 |
| 5 | 硬件/读回或其他执行错误 |
| 6 | 无唯一、已确认的盘位映射 |
| 130 | 定位被中断，已尝试恢复 |

## 输入与验证边界

本次复核了本地保存的官方通用固件 `6800plus.img`，1,303,473,152 字节，
UGOS Pro `1.20.0.0142` / amd64 / Linux `6.18.15`，SHA-256：
`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。
其 MD5 `c5358c7713ccf2811aaa7c5adcc10721` 与官网 DXP4800 Plus 当前包一致，
因此复用同一原包，只读取证；没有重复下载。原厂提取目录
`firmware-inbox/work/dxp6800plus/`，新增可复现分析目录
`firmware-inbox/work/almighty-firmware-map/`。详情见固件映射核对文档。

协议参考源码：
`miskcoo/ugreen_leds_controller`，commit
`f0fcd8192abdd92244aba9f6f0d10572f5561380`（MIT）。本地 `git archive` 快照：
`firmware-inbox/work/almighty-upstream/ugreen_leds_controller-f0fcd8192abdd92244aba9f6f0d10572f5561380.tar`，
SHA-256：`e83c4c840ede2c945db3903ca64ecee3bdabf345a1ab5eefea3422931142152c`。
提取/参考目录：`firmware-inbox/work/almighty-upstream/source/`；不纳入 Git。

来源包括 [传统协议源码](https://github.com/miskcoo/ugreen_leds_controller/blob/f0fcd8192abdd92244aba9f6f0d10572f5561380/cli/ugreen_leds.cpp)、
[DXP2800 修订差异](https://github.com/miskcoo/ugreen_leds_controller/issues/128)、
[同芯片身份不同协议](https://github.com/miskcoo/ugreen_leds_controller/pull/100)、
[物理盘位一手记录](https://github.com/miskcoo/ugreen_leds_controller/issues/9)。
上游许可保存在 `led/LICENSE.upstream-led`，见 [第三方说明](../THIRD_PARTY_NOTICES.md)。

协议、权限/所有者/锁/身份拒绝、回读失败、定位恢复、稀疏拓扑、空槽、校准、
歧义与命令兼容通过模拟和 Linux fixture 测试。构建与模拟通过不表示实机写入已验证，
也不表示全部目标发行版已验证。后续实机记录应注明机型/板本、内核、芯片身份、
实际灯位、写前/写后状态和盘位对应；不能据此升级其他机型支持级别。

2026-10-16 验证：Release Linux x86_64 和 aarch64 交叉构建成功；
**两个配置的 CTest 各 24/24 通过**，程序测试在隔离 Linux QEMU 中执行，包含既有风扇/电源/WOL 和新增
LED、GPIO holder 实际 Unix socket、CS201X、盘位、CLI 与身份测试。
最终完整测试包含 GT 全局 FLOW holder、断线恢复和超时/迟到响应立即关闭会话的修正，
避免旧回包被当作新请求的回读；另覆盖 N76 全目标现态预检、每次 sysfs 属性写入的所有者检查、
unknown 恢复拒绝，以及 NVMe namespace 别名与扫描末尾新增完整/未初始化盘的重扫保护。
构建使用 Linux `/usr/local` 前缀；两架构分别在隔离
Linux 验证了默认安装路径及显式 `--plugin-dir` 均完整加载九个旧插件。
其中 `package-runtime` 在构建主机执行 13 项 ELF 解析回归，不执行合成对象；
它与隔离 Linux 中运行的 23 项程序/硬件 fixture 测试分开计数。
独立完整测试日志、源码及二进制哈希见工作目录的 `almighty-all-models/verification-root.json`。
旧 `build/` 缓存指向原工作区，故分别使用 `firmware-inbox/work/almighty-build/`
和 `almighty-build-arm64/`，保留原缓存。另验证了双架构临时前缀安装；没有访问 NAS 实机。
当前八款 M.2 物理槽号及 N76 无原厂驱动路径仍未完成，不能把这些测试结果当作 25 款
全部适配通过。旧 `dist/almighty/` 压缩包为早期七款基线，不能作为当前全机型交付。
