# 全机型 LED 接入证据及续做断点

> 2026-10-27 更新：N76 增加显式 `--n76-direct BUS:ADDR` 实验直控，用户接受真实输出未验证的限制；模式回读保留，其余字段保持 unknown。下文原厂驱动依赖及拒绝裸写描述记录此前的严格回读策略，当前例外和范围以 [N76 直控说明](N76_DIRECT_CONTROL.zh-CN.md) 为准。无驱动编译功能。

更新：2026-10-16。这里区分已连接执行路径、仅有硬件档案和仅完成取证；
没有实机验证的条目均保持实验性，写入需要 `--force --apply`。
用户已明确排除 DH2100、DH2100+，当前实施范围为其余 25 款；官方
27 款目录仍保留，排除条目不再作为本轮继续搜索或完成条件。

## 已落盘的协议与能力结构

`led/led.h` 的机型档案包含独立 LED 布局、总线名称前缀、I2C 地址、预期
芯片 ID 和读取方式。每盏灯分别声明 RGB、模式掩码、最大亮度和固定色盘。
`ugreenctl_led_validate_target_patch` 同时供前端与硬件层使用；
`ugreenctl_led_identity_confirmed` 判断实际会话是否取得对应身份确认。
状态追加 `unknown_fields` 和 `cached_fields`，给后续 sysfs 后端如实描述
不可读字段及驱动缓存，不能用缓存冒充硬件寄存器回读。

目前已经连接到生产执行层的三个 MCU 协议为：

- `legacy-i2c-block`：12 字节 payload，包含 LED ID，校验高字节在前。
- `smbus-block-be`：SMBus block write，11 字节 payload 从 `0xa0` 起，
  不包含 LED ID，校验高字节在前；命令字节携带 LED ID。
- `smbus-block-le`：相同 SMBus block framing，校验低字节在前。

所有三者读取同样的 11 字节状态帧，并核对状态帧校验、模式和时序范围。
I2C 总线按实际名称枚举；不使用 `I2C_SLAVE_FORCE`、不加载/卸载驱动。
写入复核精确机型档案、芯片身份、控制器所有者与锁，并检查 ACK、每条
命令的目标字段回读以及最终合并状态。闪烁/呼吸总周期必须不超过 65535ms。

**同一 `0xc5b2` MCU 家族可以使用不同协议，不能由芯片 ID 单独选协议。**

## 官方输入和可复现分析

通用 x86 原包：`E:\工作台\固件\6800plus.img`，1,303,473,152 字节，
UGOS Pro `1.20.0.0142`，SHA-256
`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。
其官网 MD5 关联和盘位取证详见
[原厂盘位与 LED 映射](DISK_MAPPING_FIRMWARE.zh-CN.md)。

本轮新增下载取证的位置：

| 官网包 | 输入 SHA-256 | 提取目录 |
| --- | --- | --- |
| DH2300 / rk3576 | `a3a645e4f61d3a49d69b0b2c06d61b269a776dd769aa673dedceced4a616b9d3` | `firmware-inbox/work/almighty-all-models/packages/24/` |
| DH4300 Plus / rk3588 | `837ebfe8fffa4b6221ac8aee13d4b364289eccffcc4076bed6660ee1a6cfe836` | `firmware-inbox/work/almighty-all-models/packages/27/` |
| iDX6011 Pro 新包 | `10edeeb661587c4cb495e078b1f3e004d6005c83e6aa7b1c05d764c57df5b50e` | `firmware-inbox/work/almighty-all-models/packages/29/` |

这些包均由官网入口取得并核对公布的 MD5。原包不修改。
`firmware-inbox/work/almighty-led-all/analyze_leds.py` 读取现有 ELF 和 DTB，
输出 `evidence.json`、六份目标模块的重定位注释反汇编；另保留
`ata-pcie-dt.json` 供盘位任务核对 ARM 控制器节点。

## 27 款逐项状态

“执行已接”指相应协议调用链已实现和离线测试通过，不表示该机型已经
完成本项目实机验证。具体总线、芯片或修订不符时仍拒绝写入。

| 官网机型 | 当前 LED 状态 | 布局 / 限制 |
| --- | --- | --- |
| DX4600 | 执行已接：legacy | power、netdev、4 盘灯；RGB |
| DX4600+ | 执行已接：legacy | 精确 DMI `DX4600+`；同上布局由原厂路由与表确认 |
| DX4600 Pro | 执行已接：legacy | power、netdev、4 盘灯；RGB |
| DX4700 | 执行已接：legacy | power、netdev、4 盘灯；RGB |
| DX4700+ | 执行已接：legacy | 精确 DMI `DX4700+`；4 盘灯 |
| DXP2800 | 执行已接：独立修订 | `EM_DXP2800_V1.0.24` 用 legacy；精确 `DXP2800 V1.2 251215` 用 block-le；其他版本拒绝；2 盘灯 |
| DXP2800 GT | 执行已接：独立 CSCS201X 与显式 holder | 4 RGB LED、动态 Host2EC、芯片 `2011`；须已激活 LDN；直控要求 FLOW=1，FLOW=0 可显式运行 `ugreenctl-ledd --takeover-flow --force --apply`，退出恢复全灯及原 FLOW；50 ms 量化，总周期至多 12750 ms；实机 ARGB 可读性待验证 |
| DXP4800 | 执行已接：legacy | power、netdev、4 盘灯；RGB |
| DXP4800S | 执行已接：legacy | 独立精确型号；原厂选择 28a48；4 盘灯 |
| DXP4800 Plus | 执行已接：legacy | power、netdev、4 盘灯；RGB |
| DXP4800 Pro | 执行已接：legacy | power、netdev、4 盘灯；RGB |
| DXP4800 GT | 执行已接：block-be | 官方 generic MCU 模块明确 DMI 与 6 LED 布局；AMD 总线仍按档案严格检查 |
| DXP480T Plus | sysfs 执行及 fixture 已接 | N76，仅 power 白/橙/组合；没有四个 NVMe 盘灯，不支持 RGB；需已绑定原厂驱动，裸 I2C 回退缺可靠回读证据 |
| DXP6800 | 执行已接：block-be | 官方路由 generic MCU；6 盘灯 |
| DXP6800 Plus | 执行已接：legacy | 官方路由 68a88；6 盘灯 |
| DXP6800 Pro | 执行已接：legacy | 官方路由 68a88；6 盘灯 |
| DXP6800 Ultra | 执行已接：legacy | 原厂存储表有精确 Ultra 键，驱动路由选择 68a88；6 盘灯 |
| DXP8800 | 执行已接：legacy | 原厂路由选择 68a88；8 盘灯 |
| DXP8800 Plus | 执行已接：legacy | power、netdev、8 盘灯；RGB |
| DXP8800 Pro | 执行已接：legacy | 原厂路由选择 68a88；8 盘灯 |
| DXP8800 Ultra | 执行已接：legacy | 原厂精确 Ultra 键及 68a88 路由；8 盘灯 |
| iDX6011 Pro | 执行已接：block-be | 9 LED：power=0、netdev=1、netdev2=2、disk1..6=3..8；屏幕不是这组 LED |
| DH2600 | sysfs 执行及 fixture 已接 | 专用 N76：power、disk1、disk2；白/橙/组合；专用 callback 只开关，实际亮度能力为 0/1；无驱动时尚无安全裸 I2C 回退 |
| DH2300 | GPIO sysfs、持久 holder 与服务 API 已集成 | 精确 DT `UGREEN RK3576 DH2300 Board`；power/netdev/2 盘灯；白/橙，二值亮度，无 RGB/渐变 |
| DH4300 Plus | GPIO sysfs、持久 holder 与服务 API 已集成 | 精确 DT `UGREEN RK3588C DH4300Plus Board`；power/netdev/4 盘灯；白/红，二值亮度，无 RGB/渐变 |
| DH2100 | 用户明确排除 | 保留官方目录记录；当前不在 25 款实施范围，不借用其它型号协议 |
| DH2100+ | 用户明确排除 | 同上；不再将寻找该款固件作为本轮待办 |

## 协议分叉与 GPIO / N76 证据

### 官方 generic MCU 的 block-be

通用包与 iDX 新包中的 `leds-mcu.ko` SHA-256 均为
`ab3507ada3654c14454971dab5fcd85fd2f89e7f49ce21559ceceea6d2ac2efe`。
`i2c_iDX601x_write_led@0x460` 构造 payload 后，`0x4d1` 交换 16 位校验的
字节，`0x4ed` 调用 `i2c_smbus_write_block_data`，长度 11；最终线上校验
高字节在前。`i2c_iDX601x_read_led@0x2f0` 读取 `0x81 + id` 的 11 字节，
验证 ACK 和状态校验。

`leds_ugreen_probe` 精确白名单和名称数组确认 DXP4800 GT、DXP6800、
iDX6011 Pro；`iDX6011_pro_led_name` 是 9 个 24 字节字符串记录，第二
网灯位于盘灯之前。不能让 disk1 继续误写 ID 2。

上游 [DXP2800 V1.2 实机问题 128](https://github.com/miskcoo/ugreen_leds_controller/issues/128)
明确给出新 `DXP2800 V1.2 251215` 与旧 EM 修订不同，v0.4-beta 的
`smbus-block` 实现校验低字节在前。该用户证据仅接入精确新版系统版本，
不把 block-le 扩大到所有 generic MCU。

### N76 固定双色硬件

DXP480T 原厂 N76 驱动 `mcu_detect` 分别读取 `0x5a`、`0x5b`，组合要求
`0xa5b5`；候选 I2C 地址为 `0x31`、`0x26`。它不是 `0x3a/c5b2` 控制器。
颜色属性提供 `white`、`orange`、`white + orange`，不支持 RGB。
`color_show` 和 `rbrightness_show` 读取驱动缓存；不能称为真实硬件回读。
`mode_show` 则读取 `0x50/0x51`，其它已恢复写入口包括 `0xb1/0xa0`、
`0xe0/0xe1`。当前不在这些字段缺少可靠回读证据时开放裸 I2C 直写。

已实现后端使用通过官方 probe 身份检查且实际绑定的公开 LED sysfs
接口，保留互斥锁，输出驱动缓存来源。普通发行版缺该驱动时明确返回
unsupported，不把 ACK 冒充目标字段回读。DH2600 专用模块的静态 `leds`
数组是三项，对应 power、disk1、disk2。原厂 `ColorLed=false` 表示
没有 RGB，**不能解释为没有物理盘位灯**。

DXP480T 的 LED core `brightness` 可能是开关命令或闪烁相位；后端分别读取
它来判断稳态开关，读取原厂 `rbrightness` 作为配置亮度缓存。`0/1`
在原厂写接口中是关/开命令，不是强度 0/1；原厂 class max_brightness
为 254，因此公开 sysfs 可写配置强度为 `2..254`，
熄灭使用 mode off。强度写入有界等待工作队列更新缓存，明确验证属于
驱动属性层。闪烁支持单个白或橙通道、on/off 各至少 20 ms；组合色
闪烁被原厂驱动忽略，写前拒绝。原厂 breath trigger 没有可调
delay_on/off 属性，且仅电源白通道有固定呼吸路径，初版不将它声明为
任意周期的 breath。identify 使用软件闪烁，保存恢复原 active trigger、
原始亮度缓存、色盘和活动闪烁时序；未知触发器或不可恢复的未初始化
强度缓存在写前拒绝。

原厂 DH2600 的三个 LED classdev 在同一 probe 循环中使用相同的
`blink_set` 和属性组，没有逐灯的 trigger 类型过滤；可用 trigger 是全局注册能力。
后端只读预检核对所需 trigger 的完整名称：稳态请求需要 `normal`，
闪烁请求需要 `timer`，不接受 `abnormal` 或 `timer2` 等近似名称。
CLI 在首写前检查所有选定目标和全部 legacy 动作，避免前面的闪烁已经生效后，
才发现后续点亮所需的 `normal` 未注册。identify 同样先确认所需的 `normal`；
已知缺失时零写入退出，不进入闪灯或恢复写入。
实际 apply 仍重读现态并重新预检，每次属性写入仍执行授权、身份和控制者检查。
这不锁定 trigger 的注册状态，也不承诺预检与后续多次写入具备原子性。

DH2600 必须与 DXP480T 分开：专用模块的 `mcu_work` 没有 E0/E1 PWM
写入，只使用 A0/B1 开关，任意非零 brightness 都是点亮。即使该驱动
class 同样宣称 max_brightness=254、`rbrightness` 保存用户给出的数字，
也不能将它当作 254 级物理亮度；本项目对 DH2600 声明 max=1，读取
LED core 缓存归一为二值，不使用其任意数值缓存伪造强度。

### N76 无驱动路径的精确证据缺口

额外核对了官方 `kernel-6.12` 固定提交
`c75c5abd60dd45f45966720293ce1ee505fb8615`：

| 官方文件 | SHA-256 |
| --- | --- |
| [dxp480t/leds-mcu-n76e003.c](https://github.com/ugreen-opensource/kernel-6.12/blob/c75c5abd60dd45f45966720293ce1ee505fb8615/drivers/ugreen/dxp480t/leds-mcu-n76e003.c) | `352bd2d58053e57122eaad4fe9e1c671e9447eb1c8937f87951665a804f4ed7a` |
| [dh2600/leds-mcu-n76e003-dh2600.c](https://github.com/ugreen-opensource/kernel-6.12/blob/c75c5abd60dd45f45966720293ce1ee505fb8615/drivers/ugreen/dh2600/leds-mcu-n76e003-dh2600.c) | `1ea3550c7a44d1918859eb6df10dcd5fba30ccf8c64228c42ee83978a17c5ba5` |
| dxp480t/ledtrig-breath-n76e003.c | `d3da0de5fe25914ce507ffd34ba6b9ae25392f97bc9da964bfc4a84fb850b29f` |

本地只读取证副本位于 `firmware-inbox/work/almighty-led-all/n76-official/`，
其 manifest 保存来源、SHA 和所有 SMBus read 调用行号。
`smbus_need_write8` 会读相同寄存器再比较，但在两个驱动中均未调用，
不能将这个未执行 helper 当成 A0/B1/E0/E1 已可读的证据。源码未提供
MCU 自身 I2C handler 或输出状态镜像。芯片厂商通用 N76E003 数据手册
也不能说明绿联烧入的专有 SMBus 协议。

可读的 0x50/0x51 只表示 steady/timer/breath 配置，其中 steady=0
不区分实际开/关；输出位由 A0/B1 置/清。仅凭模式读回不能把 steady
称为 on 或 off。timer 请求还包括 C0/D0 起的两字节时序，未有它们真实
读回的执行证据；不能只验证模式而声称整个 blink 请求已验证。

解除剩余限制的最小资料是：绿联该版本 MCU 的协议/程序（指出当前输出
位、两通道 PWM 和时序的可读状态寄存器），或相应实机上经授权的寄存器
读回记录，配合精确 DMI、MCU ID/版本、实际总线地址和已知灯态逐项验证。
单份全零读数、ACK、Linux 驱动缓存或另一个 MCU 型号都不足以确认。
不在没有这些依据时增加强制访问、主动扫描未知地址或自动卸载原厂模块。

### N76 的 1.17 / 1.19 / 1.20 独立版本比较

本轮另做二进制差异取证，未更改或执行驱动，也未改产品 C 源。
比较输入分别来自原包 SHA-256：1.17 为
`7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`，
1.19.1.0126 为 `f36ac819032fa98d7cbf058bed95959860ef95873ac10fe0141417a7e014758f`，
1.20.0.0142 为 `73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。

| UGOS / 内核 | DXP480T 的 N76 `.ko` SHA-256 | DH2600 专用 `.ko` SHA-256 |
| --- | --- | --- |
| 1.17 / 6.12.30+ | `c7f49d684d170727731a533af851eff649fbec28f270846ff00016f125ae9fbb` | `269bd994e182b40febc425d276f2f4961a0ec23dc39f8b5501308ac382cea3b4` |
| 1.19.1.0126 / 6.18.15 | `9ac822cb97eda5b000acea74bc57102c9fb020c62cb61e4edc4dfae3be2c47f8` | `29fbeaba0a9641dc5be6cd75e2e9870a5a0f830bf74057a620d604f64cfe7261` |
| 1.20.0.0142 / 6.18.15 | `2ed2f93f6c72a2783163169e805c4c04dfa49bf30185f00355d179486bf60694` | `c7c91f25bbf636939c68f5ae2d7cfbfed6ab55b82eee35981581bc60fd7040b5` |

六个独立 core 模块的实际 SMBus read 调用都相同，每个共六处：

| 函数 | DXP480T 函数地址 | DH2600 函数地址 | 实际读寄存器 |
| --- | --- | --- | --- |
| `mode_show` | `0x70` | `0xb0` | `0x51+led_bit`、`0x50+led_bit` |
| `version_show` | `0x120` | `0x160` | `0x5d` |
| `mcu_detect` | `0x270` | `0x2b0` | `0x5a`、`0x5b`、`0x5d` |

其余 `color_show`、`rbrightness_show` 均只读结构体内存，公开属性始终
只有 color/rbrightness/mode/version，没有新增 state。`mcu_work` 和
`mcu_led_set_blink` 没有 SMBus read；六个模块均未导入 firmware 加载或
MCU 更新文件读取函数。DXP480T 的 work 写 E0/E1，DH2600 的 work 在
三版都仅写 A0/B1。这些是实际反汇编事实，不是按文件名推测。

尤其 1.19 与 1.20 的两个 core 模块，以及 normal/breath 两个 trigger，
全部函数逐字节相同，ELF 变化仅在 `.BTF` 类型元数据。文件 SHA 不同
不能当成新增 MCU 协议的证据。1.17 的函数/内核结构布局有差异，但上述
read 调用集合和四个公开属性保持一致；三个版本的 trigger 都没有 I2C
read，也不提供 MCU 固件更新接口。

复现目录为 `firmware-inbox/work/almighty-led-n76-diff/`：从仓库根运行
`inventory.py`、`compare.py`，得到 `module-inventory.json`、
`comparison.json` 及逐模块完整反汇编。报告保存各函数 SHA、read 调用
前的寄存器参数上下文、属性 show/store 绑定、所有 ELF section SHA。
1.19 两个 trigger 从已下载 kernel.squashfs 选择提取到该目录，未改原包。

另核对了不同公开版本的官方来源，并保留 `public/manifest.json`：

- `kernel-6.1.27@1c93b3b9fe1a18bf3dbcc97d4cc292d6a3234f5f` 的 drivers
  目录没有 `ugreen` 子树；未把其它内核目录中普通 MCU 名称当成 N76。
- `linux-headers-6.12.30@62859e1e5520750be5eb368de85d254666adbe05`
  完整 7416 项目录无 N76 专用文件。
- `linux-headers-6.18.15@93bb15298f306b2beb04f7e9ad5e43a1136a0b04`
  官方 headers deb 为 9,411,024 字节，SHA-256
  `8c975501c942b1d9b4aca779038bdee9ada1a5514ed9800b6cdd160b5a7608a7`，
  与仓库 SHA256SUMS 一致；只读列出 7759 个成员，无 N76 程序/协议文件。
- `ugospro-debian12@54affd67f2ae84585bf9cd9ac146e956a1cbddef`
  完整 7273 项目录按 N76/MCU/LED 名称筛选未发现相关固件或控制源码；
  这是目录取证，不表示逐一检查了所有普通软件文件的内容。
- 查询时两个官方 kernel 仓库各只有 main、无 tag；未将已分析的
  kernel-6.12 相同文件再次作为新的独立版本。

结论限于这些具体输入：**本轮未发现新增真实输出位、PWM、timing 的
读取入口或 N76 自身 MCU 程序。不能由“未发现入口”推定芯片不可读。**

2026-10-16 又检查了官方提交历史及新的原始讨论，而非重复解包上述镜像。
两份 N76 文件各只有 [2026-04-03 初始提交](https://github.com/ugreen-opensource/kernel-6.12/commit/0e4d73a6893d2aaa9772345c85bcccb3798784c1)，
初始源码与先前核对版本相同；初始文件 SHA-256 分别为 DXP480T
`352bd2d58053e57122eaad4fe9e1c671e9447eb1c8937f87951665a804f4ed7a`、DH2600
`1ea3550c7a44d1918859eb6df10dcd5fba30ccf8c64228c42ee83978a17c5ba5`。
官方 ARM 仓库另三份 MCU 候选属于 watchdog/电源/SATA/WOL，不是这两款的 LED MCU 程序。
[上游原始讨论](https://github.com/miskcoo/ugreen_leds_controller/issues/6)全部 38 条中，
`0x80/0x81` 仍只是未验证建议，没有输出/PWM/时序字段的实际回读及灯态关联，不能据此开放写入。
来源响应和哈希位于 `firmware-inbox/work/almighty-led-n76-history-20261016/`，汇总 `result.json`
SHA-256 为 `9a2c18b2349fd9481cf9e43166da3309fe9aa3d39ed735c4da5f6b731b10f333`。
这是有边界的资料检索，仍不能证明芯片不可读。用户现已确认无法接触
DH2600 和 DXP480T Plus，可接触性问题不再待答，也不重复询问。
两款仍属于当前 25 款目标，无原厂驱动时的输出、亮度和时序可靠回读缺口尚未解决，
不能因此标为完成或从目标中排除。

另检查官方固件索引中的独立升级器新候选：`us3000_jqh_ota` 脚本明确停止
`nut-server`、`nut-monitor` 和 `ups0` 后升级 UPS；对应 ELF 使用 libusb 和
USB Feature Report，不是 NAS N76 LED 程序。1.17 与 1.20 的该 ELF 相同，
SHA-256 为 `8ed024f8844c57417a540fc4b5590c3a7a50173c0db8a9d8948205eea4ffd7d7`。
1.19/1.20 已列出的文件与应用清单，以及 `ugupdate`、`ugdevice`、`ctl_serv`
的具名 Go 函数元数据，未提供新的目标 MCU 升级入口。此结论仅限已核对的
索引、文件和符号，不能证明所有匿名嵌入映像均不存在。原包哈希、定向提取物和
可复现分析在 `firmware-inbox/work/almighty-led-n76-upgrader-1305/`；`result.json`
SHA-256 为 `73c0ed7c61a60e8e66a2a66f5d25aa095a95413098b3782369ed7f6b523edc26`。
没有执行升级器、访问硬件或扩大无驱动写入能力。

### ARM GPIO LED

DH2300 DT compatible 为 `rockchip,rk3576-evb1-v10|rockchip,rk3576`；
DH4300 Plus 为 `rockchip,rk3588s-evb4-lp4x-v10|rockchip,rk3588`。
两者 `/ug-led` compatible 均为 `ug-rockchip-led`，`led_num` 分别为
4 和 6；DH4300 Plus 模块 `ug-gpio-leds.ko` 导出 power、network_stat、
disk1..4 等名称及 color、state、mode、brightness 属性。
同包另有 **DH2300Plus** 的 DTB，它不是官网 DH2300，不能拿来替代。

### ARM 两通道的真实能力

官方源码 `rk3576_kernel` 提交 `d0bf43d155dd957944aace847dbefe821ffbefb2`
及 `rk3588_kernel` 提交 `8365d0fac1d65f6035cadab55df41202c8a87e2c` 的
`drivers/ugreen/ug-gpio-leds.c` 将 color=1 定义为白色并选择 gpio[0]，
其它非零色选择 gpio[1]，同时清零另一根；与本轮 `.ko` 反汇编一致。
源码 `COLOR_ALL` 常量与其它颜色数字重叠，但执行路径不同时点亮两根，
因此不能据常量名开放 both。两款第二物理通道颜色由官网手册确认：

- [DH2300 官方手册](https://www.ugnas.com/file/upload/2025-10/21/202510211835592504.pdf)
  第一页白/橙；SHA-256 `36896080bc29e77eea311d90e02ca34305fdb9995df5b04729e280aaa04d26e7`。
- [DH4300 Plus 官方手册](https://www.ugnas.com/file/upload/2025-05/13/202505131131143507.pdf)
  第一页白/红；SHA-256 `8111996ee7d21a16660d92e87c3e5580805efce54b835521767b57afe12a0049`。

brightness callback 把非零值归一为 1，因此用户能力最大亮度为 1。
LED class 的 max_brightness 仍可能为内核默认 255；后端接受已知驱动
的 1/255 声明范围，读取归一为实际二值能力。`.color` 只写，色盘读取
解析 `.state` 的 `color` 字段；不对 `.color` 伪造读回。sysfs 公开状态
标注为驱动缓存。初版只开放 on/off，软件 identify 提供临时闪烁，不把
GPIO 定时开关称为硬件渐变。`channel1/channel2` 是两根线的可用别名。

### 无原厂驱动的 GPIO 持久 holder

`led/led_gpio.[ch]` 独立实现 GPIO v2 character-device transport，不需要
原厂 `ug-gpio-leds`，但需要内核启用 GPIO chardev v2，并保留精确真实
DT model、SoC compatible 及完整 LED wiring。动态枚举实际 gpiochip，
不固定 gpiochip 编号，也不使用全局 GPIO 序号。

| 精确型号 | GPIO OF 节点 | 通道 offset 顺序（两项一盏，power/network/disk） |
| --- | --- | --- |
| DH2300 | `/pinctrl/gpio@2ae20000` | 30,31 / 28,29 / 15,13 / 14,12 |
| DH4300 Plus | `/pinctrl/gpio@fd8a0000` | 22,4 / 8,20 |
| DH4300 Plus | `/pinctrl/gpio@fec50000` | 13,14 / 9,10 / 11,12 / 7,8 |

核对 `/ug-led` compatible/status/led_num/leds-gpios 三元组、phandle
对应 OF 节点、实际 gpiochip OF binding/name/32-line 范围。DH2300 DT
尾部四个未注册引脚明确不请求。取得固定 LED 锁后以 flags=0 的 AS-IS
方式独占实际使用引脚，打开和诊断不改方向/值；已有内核或用户所有者
一律 EBUSY。写入需要 force/apply，只原子配置目标两根线及互斥输出，
并通过 GPIO GET_VALUES 回读，不改变其它 LED。

GPIO GET 可能来自输出寄存器或输入采样，取决于控制器，是内核 GPIO
读取层级，不是光学验证。[Linux GPIO v2 文档](https://www.kernel.org/doc/html/latest/userspace-api/gpio/gpio-v2-get-line-ioctl.html)
明确 FD 关闭后输出可能恢复默认，不能用短命 CLI 写完关 FD 并称持久
生效。`ugreenctl-ledd` 必须持续持 FD 和控制器锁；CLI 通过 root-only
Unix socket 调用，整个 identify 会话独占连接。用户显式启动 holder，
工具不会暗中后台 fork；服务存在但拒绝/忙时不能绕过。

GPIO 熄灯时没有 dormant 色盘寄存器，状态色盘如实为 unknown；熄灯
状态单独设置色盘会拒绝，同时请求 mode on 才能明确选择通道。

## 待完成的具体工作

2026-10-26 补充 BIOS 版本保护：LED 诊断追加 DMI BIOS vendor/version/date，
缺失明确为 unknown/JSON null；每次 LED 读取和写入重新核对会话的机型、主板
及 BIOS 身份，变化拒绝本次操作，sysfs 属性写入和恢复同样执行这项检查。
CS2011 在访问配置端口前也比较完整身份。这个检查只证明本次会话身份未变，
不能把首次遇到的 BIOS 判成已验证兼容，也不能补足 N76 未知回读。

2026-10-26 新增 `ctl_serv` 五个实际 LED 服务函数、13 个指定 host 资产及启动路由
分析，见 [官方固件运行链路复核](FIRMWARE_RUNTIME_TRACE_20261026.zh-CN.md)。
`GetState` 已追到读取 sysfs `.state`，不能据此补足 N76 真实输出回读。
两款仍在范围内；用户没有实机，后续继续查嵌套官方资源，不再重复询问。

1. GPIO 与 GT holder/daemon、服务 API、真实 Unix socket fixture 已集成；
   x86/ARM 各 24/24 CTest 通过（23 项隔离 Linux 程序/硬件 fixture 和 1 项主机 Python 包格式测试）。GT 显式 FLOW 接管、BEGIN/END 原始
   状态恢复、断线恢复及协议保护已加入；最新哈希及后续回归以根任务
   `verification-root.json` 为准，不把旧快照当作最终交付。
2. N76 无原厂模块时仍缺 A0/B1/E0/E1 目标字段可靠回读证据，继续查
   官方 MCU 资料，不通过 I2C_FORCE 或软件缓存绕过此边界。
3. [DXP2800 GT 取证](DXP2800_GT_LED_REVERSE.zh-CN.md)对应 CSCS201X 已接
   transport 与主 API，完成双架构注入 fixture；继续取得实机 ARGB
   可读性、时序和中断恢复记录。首次读到异常状态仍拒写。
4. 最终补当前 25 款的目标系统和逐机型实机验证记录；N76 无驱动
   路径的读回限制仍存在，不能仅凭已建档就称跨系统控制全部完成。
   DH2100 / + 已按用户要求排除，不再继续搜索两款固件。

本断点的 `test-led` 已在 Linux QEMU 实际执行通过，覆盖 legacy 与
block-be/block-le 字节序、驱动所有者/锁/身份保护、非法帧、时序溢出、
完整状态恢复、不同 LED 能力拒绝及 iDX 双网络灯布局。
新增 fixture 另覆盖两款 ARM 的实际 OF 节点、完整 GPIO routing、32-line
chip 身份、AS-IS 请求不改输出、独占 owner、非 force/apply 拒写、输出
回读失败、其它 LED 引脚保留，以及 N76/GPIO sysfs 原状恢复。
状态预检回归另覆盖后续 N76 目标正在执行效果或双色组合不能闪烁时首次写入前全量拒绝、
未知模式不能默认为 off，以及明确完整请求可替换未知状态。N76/GPIO 的每次 sysfs 属性
写入均重验控制者和绑定；恢复中途出现控制者或回读必要字段为 unknown 均报告失败。
已注册 trigger 的新增回归使用所有 N76 灯一致的全局列表，覆盖缺少 `normal`、
缺少 `timer` 以及近似名称误匹配；直接后端、identify 和真实 legacy 动作序列均确认
已知缺失时零属性写入。两架构的相关 fixture 已在隔离 Linux QEMU 中通过，
原有正常 trigger 激活和恢复用例继续通过；这不是实机验证或原子事务保证。
没有实机验证。本轮未修改 `LLLED_FPK`，未提交或推送；当前交付范围为
25 款，具体后端依赖和 N76 读回缺口按上述记录保留。
