# DXP2800 GT：CSCS201X LED 协议取证

状态：官方发布源码与原厂固件路由已确认，已实现独立用户态实验性 LED transport，并通过双架构注入式测试。尚无本项目的实机读写验证，不开放风扇、看门狗或电源控制。

## 输入及来源

- UGOS Pro `1.20.0.0142` 通用升级包：原始 SHA-256 `73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。`fw/usr/sbin/ug-load-drive.sh:136` 精确分支 `DXP2800 GT` 加载 `ug_201x_sio`，与 DXP4800 GT 的 `ug_4800gt-sio`、`leds-mcu` 分支不同。
- 官方 [kernel-6.12](https://github.com/ugreen-opensource/kernel-6.12) 提交固定为 `c75c5abd60dd45f45966720293ce1ee505fb8615`。整树递归 API 会截断，已单独核对 `drivers/ugreen` 子树。

| 文件 | SHA-256 | 关键位置 |
| --- | --- | --- |
| [ug_201x.c](https://github.com/ugreen-opensource/kernel-6.12/blob/c75c5abd60dd45f45966720293ce1ee505fb8615/drivers/ugreen/ug_201x.c) | `a59042ec0a5f3b699a671821fae36ea575d1568d3388fe8429978481497c8acc` | 文件头明确用于 2800gt、芯片 CSCS201X；SIO/H2EC/ARGB 事务 |
| [leds-sio-201x.c](https://github.com/ugreen-opensource/kernel-6.12/blob/c75c5abd60dd45f45966720293ce1ee505fb8615/drivers/ugreen/leds-sio-201x.c) | `3cf4d535866990be60de212241791f3564e1297770eab4b51c2461342084e138` | LED 数量、逻辑 ID、模式、颜色、50 ms 编码 |
| [Makefile](https://github.com/ugreen-opensource/kernel-6.12/blob/c75c5abd60dd45f45966720293ce1ee505fb8615/drivers/ugreen/Makefile) | `0f3c5849bd435151836a36a6ed098adfff618a35c024e0d47966f15d96c1406c` | 发布副本含 `CONFIG_UG_OSS_REMOVE` 标记，当前未列 201x 构建目标 |

当前升级包 `kernel.squashfs` 没有该 `.ko`，不虚构模块哈希、编译或加载结果。源码保存在忽略目录 `firmware-inbox/work/almighty-all-models/official-source/`，原许可证保持不变；本项目实现应根据接口事实独立编写，不能把 GPL 驱动源码直接纳入 MIT 代码。

## SIO 身份与运行时地址

`ug_201x.c:155–274`、`:765–815` 给出以下协议：

| 项目 | 值 |
| --- | --- |
| 索引/数据端口 | `0x2e / 0x2f` |
| 进入序列（向索引端口） | `0xa5, 0x69, 0x87` |
| 退出序列（向索引端口） | `0x87, 0x69, 0xa5` |
| 芯片 ID | 索引 `0x20` 为高字节、`0x21` 为低字节，必须等于 `0x2011` |
| 芯片 revision | 索引 `0x22/0x23`，高字节在前；源码记录它，但没有限定可接受值 |
| LDN 选择 | 索引 `0x07`，Host2EC 为 LDN `0x0a` |
| LDN 激活 | 索引 `0x30`，原厂初始化写 `0x01` |
| Host2EC 基址 | LDN `0x0a` 的索引 `0x60/0x61`，高字节在前 |

没有证据支持固定 Host2EC 基址。用户态 LED 路径应从真实控制器读取它，保存/恢复原 LDN 选择，并要求 Host2EC 已激活；不应自动激活或照搬原厂 `InitEc()`。该初始化同时启用风扇、设置温度 ADC，驱动 probe 还操作电源键、看门狗和 AMD 电源策略 MMIO，均超出灯光任务。

## Host2EC 单字节事务

`Chipsea_Host2ec_Outb` 与 `Chipsea_Host2ec_Inb` 采用相同地址装载步骤，见 `ug_201x.c:215–248`：

1. 向 `base+0x01` 写 `0x00`，关闭自动递增，使用单字节事务。
2. 把 32 位 EC 地址的字节按最高到最低顺序，分别写到 `base+0x07`、`+0x06`、`+0x05`、`+0x04`。
3. 写入取低 8 位后写 `base+0x08`；读取从 `base+0x08` 取一个字节。

源码声明了 `IMA_HOST_CTS=0x00`、`IMA_SEM=0x0c`，**没有使用它们，也没有实现忙状态、完成状态或信号量握手**，因此其位定义和时序仍为 unknown。事务调用的 `ug_msleep(1)` 在未启用 `CONFIG_UG_FEAT_MSLEEP` 时为空操作；不能将它描述为硬件已证明要求的固定延迟。

通用读事务确实用于温度与风扇转速。LED 代码没有调用 ARGB 硬件读函数；用同一读事务访问 ARGB 地址具备静态依据，但 ARGB 字段的实机可读性、复位值及读回含义仍待验证。

## 四个 LED 及寄存器

逻辑 ID 为 `power=0`、`network_stat=1`、`disk1=2`、`disk2=3`，CLI 中网络别名为 `netdev`。源码 `LED_COUNT=4`，不能因名称解析函数遗留了 `disk3/disk4` 字符串而扩展实际通道。

下表都是 8 位字段，见 `ug_201x.c:113–120`、`:376–409`：

| LED | mode | brightness | period | duty | B | R | G |
| --- | --- | --- | --- | --- | --- | --- | --- |
| power | `0x20005400` | `0x20005404` | `0x20005408` | `0x2000540c` | `0x20005444` | `0x20005445` | `0x20005446` |
| netdev | `0x20005401` | `0x20005405` | `0x20005409` | `0x2000540d` | `0x20005448` | `0x20005449` | `0x2000544a` |
| disk1 | `0x20005402` | `0x20005406` | `0x2000540a` | `0x2000540e` | `0x2000544c` | `0x2000544d` | `0x2000544e` |
| disk2 | `0x20005403` | `0x20005407` | `0x2000540b` | `0x2000540f` | `0x20005450` | `0x20005451` | `0x20005452` |

- mode：`0=off`、`1=on`、`2=blink`、`3=breath`。
- brightness：原始范围 `0..255`。原厂 sysfs 将数值 `0/1` 特判为关/开，只有 `2..255` 执行亮度字段写入；不能把这种用户接口特判当作硬件亮度范围。
- RGB：每 LED 跨度四字节，实际按 **B、R、G** 三地址写入；第四字节没有读写证据。原始 setter 支持三个任意字节，sysfs `color` 只提供五种预设：白 `(255,255,255)`、橙 `(220,40,0)`、红 `(255,0,0)`、绿 `(0,255,0)`、蓝 `(0,0,255)`。

### 闪烁与呼吸时序

`leds-sio-201x.c:239–343` 将周期与亮起时段分别编码，**不是两个独立 on/off 字段**：

```text
period = floor((on_ms + off_ms) / 50)
duty   = floor(on_ms / 50)
```

因此静态解码为 `on_ms=duty*50`、`off_ms=(period-duty)*50`，仅在模式及原始字段有效时成立。原厂 sysfs 闪烁下限为 on/off 各 100 ms；呼吸下限为 on 1000 ms、off 500 ms。两个字段只有 8 位，避免截断时总时长上限为 12750 ms。原厂 setter 没有上限检查，会截低字节；本项目必须拒绝溢出，并明确 50 ms 量化。要求精确时长的接口可直接拒绝非 50 ms 整数倍，不能静默声称实现了原始请求时长。

### 全局自主灯效

`ARGB_FLOW_CONTROL=0x20005440` 是控制器级字段。源码 `ug_cs201x_probe:790` 写 `1` 并注释禁用自主流动，`ug_cs201x_remove:817` 写 `0`；remove 的注释同样写 disable，应视为不一致注释，不能扩大解释。原厂 LED setter 本身没有其它 LED 启用握手。`InitEc()` 里的 FAN/ADC 初始化不是本项目允许执行的灯光接入步骤。

普通 CLI 只接受已经为 `FLOW=1` 的控制器，符合条件时不需要 holder。`FLOW=0` 不能由普通 `led set` 隐式接管；它会提示显式运行：

```sh
sudo ugreenctl-ledd --takeover-flow --force --apply
```

这是覆盖所有四盏灯的前台实验性 holder 生命周期。只有精确真实 DMI、`2011` 芯片、已激活的 LDN `0x0a`、有效稳定基址、固定双锁及所有者检查均通过后，才允许 `0→1`。不启用 inactive LDN，不猜基址，不修改 Pinmux、风扇、ADC、看门狗或电源策略。启动前对全部四盏灯的 28 个字段字节读取两份稳定合法快照，同时核对 FLOW；写 `1` 后回读，并确认全部 28 字节没有变化，才对客户端开放会话。

holder 正常退出时先完成尚未结束的 identify，再恢复并回读全部 28 字节，最后把原 FLOW 值恢复并回读。若原值就是 `1`，仍恢复 28 字节，但不额外写 FLOW。启动中途失败也尝试完整恢复；任何身份、所有者、基址或回读异常都会拒绝继续写，失败必须报告状态可能改变。会话中 FLOW 被其它主体改为 `0` 且目标状态已经不同，不会再次接管。正式服务使用能返回恢复错误的 `restore_close()`；`close()` 只保留最佳努力的清理能力，不能代替错误报告。

停止 holder 会撤销它存续期间的灯光设置，而不是把全局接管永久留在控制器上。28 字节及 FLOW 的恢复只代表已建模寄存器恢复；自主动画相位、内部进度、复位值、全部板修订行为和光学效果仍没有实机验证，不能承诺动画相位恢复。`SIGKILL`、掉电或新所有者接管后也不能保证恢复。

## 所有者、回读与恢复边界

- 原厂路由模块名为 `ug_201x_sio`；源码 platform driver/device 名为 `ug-sio201`，会创建 `/proc/it86/{fan,startup,temp}`。直接端口路径必须拒绝已加载或绑定的同控制器所有者，并使用跨进程锁；`--force` 不能绕过。
- LED class 名为 `power`、`network_stat`、`disk1`、`disk2`。自定义属性仅写入用的 `color`；该源码没有 `state` 或硬件回读 getter。LED class 的 brightness、trigger 及内部原子变量均不能冒充当前硬件状态。
- 配置端口的原厂 `request_muxed_region` 和内核 `ug_201x_lock` 不会自动与用户态锁互通。用户态须检查所有者/端口占用；不能与原厂风扇或看门狗路径并行直控。
- 普通灯光直控只访问上表字段；显式 holder 仅增加有证据的 FLOW `0/1` 生命周期。识别后仍应逐次检查所有者和身份，拒绝无效基址、未激活 Host2EC、不合理 mode/timing、未确认的芯片；不得通过“初始化”清空这些异常。
- 完整单 LED 快照至少包含七个原始字节：mode、brightness、period、duty、R/G/B。恢复须保留 off/on 模式下 dormant timing；不得把恢复操作重新编码为未经核验的请求值。
- 若无法读取和验证原状态，不能承诺 `identify` 结束或中断后恢复完整状态；应在写入前拒绝，而非先闪灯再报告 unknown。

## 复现与当前验证

`firmware-inbox/work/almighty-all-models/extract_gt_led_evidence.py` 从固定源码检查关键常量、四个 ID 与 50 ms 转换，生成 `dxp2800-gt-led-evidence.json`，包含每个来源的 SHA-256、逐 LED 地址、owner、未证实事项。脚本已运行并通过一致性断言。它只做静态取证，不执行、安装或加载驱动。

### 独立用户态实现

接口实现在 `led/led_cs201x.[ch]`，机型接线位于 `models/led_profiles.c`。该实现根据上面的接口事实独立编写，未复制原厂驱动源码。生产入口始终重新读取真实 DMI；只有 `DXP2800 GT` 和 `cs201x-sio` profile 能进入端口路径。Linux ARM 构建保留该接口，但生产端口入口返回 `ENOTSUP`，不引用 x86 专属 `sys/io.h`。

在授予端口权限前检查所有者并依次持有固定的 `/run/ugreenctl-led-mcu.lock`、`/run/ugreenctl-it8613.lock`；再次读取芯片、LDN 激活状态和运行时基址。基址须在 `0x0100..0xfff0` 且 16 字节对齐，会话中变化即拒绝。保留/恢复原 LDN，不改变激活位。普通入口必须读到 `FLOW=1`；`open_holder(..., takeover_flow=true, ...)` 才允许上述可恢复的 FLOW 生命周期。两条路径均不执行 `InitEc()`。

每个目标在修改前连续读取并核对两份完整七字节快照；模式或活动时序异常、读取失败、快照变化均在写入前拒绝。写入要求 `--force --apply`，每个字段都重新核对 DMI、芯片和所有者，单字节回读后再核对完整目标。普通写入失败时尝试恢复全部旧字节；恢复失败明确报告状态可能改变，不能因 `--force` 绕过失败。`identify` 成功结束或信号中断后恢复七个原始字节，包含 off/on 下未使用的时序；持锁直到恢复结束。它不能保证恢复 `SIGKILL`、掉电或新控制器所有者已接管等外部变化。

时序只接受 50 ms 整数倍、周期不超过 12750 ms；闪烁至少 100/100 ms，呼吸至少 1000/500 ms。RGB 与亮度各字节限制为 `0..255`。inactive timing 的 duty 大于 period 时，状态读取把 timing 标记为 unknown；原始快照仍可供 `identify` 完整恢复。

远程 identify 使用 `begin_identify()` 保存该目标七个原始字节并开始蓝色 200/200 ms 闪烁，`end_identify()` 按原字节恢复。原始字段始终保留在 holder 内，不能从 unknown timing 的解码值重新构造；wire 只传目标及授权标志。尚有 saved identify 时拒绝另一个 BEGIN 和普通 APPLY。BEGIN 启动失败会尝试恢复并保留 saved 状态，供 END、客户端断线或最终 holder 退出再次恢复。只有内核 `SO_PEERCRED` 已认证的当前客户端 PID 可从控制器进程检查中排除，其它所有者仍会拒绝。

### 测试边界

`tests/test_led_cs201x.c` 使用可注入端口回调执行真实解析、身份保护、事务和恢复代码，不访问宿主硬件。已分别以 Linux x86_64、aarch64 编译（`-std=c11 -Wall -Wextra -Werror`）并在隔离 QEMU 实际执行通过。覆盖精确 DMI/来源、错误芯片、未激活 LDN、无效/变化基址、所有者/锁/权限失败、四个 LED 地址、RGB/亮度/时序约束、完整读取失败、快照变化、写回不符后的恢复、恢复失败、所有者在事务中出现，以及正常/中断 identify 对 dormant timing 的字节级恢复。ARM fixture 还验证生产入口返回 `ENOTSUP`。

holder 新 fixture 进一步覆盖：缺少显式接管时 FLOW0 拒绝、inactive LDN 不写、全 28 字节预读取失败不写、FLOW 非 0/1 拒绝、接管回读不符后的恢复、接管改变其它灯字段时拒绝并恢复、初始 FLOW0/1 两条退出路径、全灯 dormant timing 字节恢复、BEGIN/END 及断线前 pending identify 的最终恢复、写失败后保留 saved 状态，以及新所有者/外部 FLOW 变化/回读失败时明确报告恢复失败。它们仍是软件注入模型，不是实机证据。

这些测试证明注入模型下的软件行为。ARGB 字段在真实 CS2011 上的可读性、读回语义、板修订差异和实际灯效仍是静态推断；不能因此升级为实机验证。完整产品构建与 CTest 结果以本轮根任务最终验收记录为准。

未访问或修改 `LLLED_FPK`，未修改原始固件，未提交或推送。
