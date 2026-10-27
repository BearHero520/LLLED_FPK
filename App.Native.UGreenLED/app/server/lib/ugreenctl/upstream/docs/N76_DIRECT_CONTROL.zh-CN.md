# N76 用户态实验性直控

2026-10-27 用户明确选择按官方 N76 驱动协议直控，移除手动/自动编译驱动功能，并接受
“已发送，硬件状态未验证”的输出语义。这个例外只适用于这里列出的 N76 输出字段；
不改变其它控制器的回读保护，也不能绕过机型、芯片身份、所有者和锁。

## 使用和范围

直控集成在 `ugreenctl led`，不下载、编译、安装或加载 N76 内核模块。
仍需要 Linux 的 I²C 总线驱动和 `i2c-dev`；这不是完全绕过内核的端口访问。
必须显式指定已经确认的总线和官方候选地址 `--n76-direct BUS:0x31` 或
`--n76-direct BUS:0x26`。程序不扫描地址、不默认猜总线，也不从 sysfs 错误自动回退。
未指定此选项时保留原有绑定驱动的 sysfs 路径。

以下 `1:0x31` 仅演示格式，使用前替换为本机已经确认的总线/地址；不能照抄当作机型固定值：

```sh
# 预览：不打开 I²C、不读取寄存器、不写灯
ugreenctl led set power --mode on --color white --n76-direct 1:0x31 --json
# 只读身份、MCU 版本、模式；实际灯态字段仍为 null
sudo ugreenctl led status power --n76-direct 1:0x31 --json
# 显式执行：精确身份、锁和控制者检查通过后才发出命令
sudo ugreenctl led set power --mode on --color white --n76-direct 1:0x31 --force --apply --json
# DH2600 盘位灯
sudo ugreenctl led set disk1 --mode blink --color orange --on-ms 500 --off-ms 500 --n76-direct 1:0x31 --force --apply
# DXP480T Plus 可显式设置配置亮度（DH2600 没有该 PWM 能力）
sudo ugreenctl led set power --mode on --color white --brightness 128 --n76-direct 1:0x31 --force --apply
```

| 精确机型 | LED / 位移 | 颜色 | 亮度 |
| --- | --- | --- | --- |
| DH2600 | power=0、disk1=4、disk2=2 | 白、橙、白+橙；闪烁限单色 | 仅开/关（0/1），不写 E0/E1 |
| DXP480T Plus | power=0，没有四个 NVMe 盘灯 | 同上 | 配置强度 2..254；省略时保留不可读的当前强度 |

请求必须给出完整 mode；on/blink 还必须给出颜色，不能从未知原态猜色。
熄灭只用 `led off TARGET` 或单独 `--mode off`。不支持裸 RGB、组合色闪烁、任意周期呼吸。
`identify/disk locate` 需要恢复原始灯态，直控无法可靠保存它，因此拒绝这些操作。
兼容入口仍保留原有逐动作语义；不能把分开的 legacy 颜色与点亮动作假装成一个完整事务。
需要颜色/闪烁时使用上述 `led set`，不要把不支持的 legacy 动作记为已适配。

## 回读和失败语义

JSON 成功表示所有 SMBus 写调用成功且可读模式寄存器检查通过，不证明灯实际已亮。
返回 `write_result=sent-unverified`、`verification=mode-registers-only`、
`hardware_state_verified=false`；mode/color/brightness/timing 为 null，并列在
`unknown_fields`，`cached_fields` 不伪造缓存。`n76_mode_registers` 是两个原始模式字节，
`n76_mcu_version` 是读取的 MCU 版本；steady=0 不能区分开与关。
命令参数仍独立显示用户请求，不复制到硬件状态。

保持默认 dry-run；实写必须 `--force --apply`。精确 DMI/主板/BIOS 身份在会话内比较，
检查芯片 A5B5 和稳定的 MCU 版本，使用共享 `/run/ugreenctl-led-mcu.lock`。
拒绝原厂模块、已存在的 N76 I²C client（包括未绑定 client）和已知控制进程；
每次写前重查身份/所有者，使用普通 I2C_SLAVE，绝不 FORCE 或自动卸载驱动。
模式写入逐项回读并最终复核。错误立即停止、禁用当前会话后续写入，输出说明可能已部分
改变；不尝试凭未知原态回滚。不同请求和多灯操作不具备硬件原子性。管理者仍须避免其他
未识别的 root I²C 程序同时操作；用户态锁不能阻止任意外部进程。

## 官方证据和静态推导

固定官方源码提交 `c75c5abd60dd45f45966720293ce1ee505fb8615`，来源清单
`tools/n76/sources.json`，本地只读副本 `firmware-inbox/work/almighty-led-all/n76-official/`：

| 官方输入 | SHA-256 |
| --- | --- |
| DXP480T Plus leds-mcu-n76e003.c | 352bd2d58053e57122eaad4fe9e1c671e9447eb1c8937f87951665a804f4ed7a |
| DH2600 leds-mcu-n76e003-dh2600.c | 1ea3550c7a44d1918859eb6df10dcd5fba30ccf8c64228c42ee83978a17c5ba5 |

官网源码 `leds[]` 确定上述位移；`mcu_detect` 定义 0x31/0x26、0x5a/0x5b=A5B5、
0x5d 版本；`mcu_work` 定义 A0 置位/B1 清位与 480T 的 E0/E1 PWM；
`mcu_led_set_blink` 定义 0x50+bit/+1 模式、C0+2*bit/D0+2*bit 的低字节在先
双字节时序（橙色另加2），以及单色闪烁最短20ms。2/10ms 写后等待也来自驱动。

模式读取还以官方 UGOS 1.20 DH2600 模块 `mode_show` 的实际反汇编确认
0x50+led_bit 与 0x51+led_bit；模块 SHA-256
`c7c91f25bbf636939c68f5ae2d7cfbfed6ab55b82eee35981581bc60fd7040b5`。
该原始 1.20 包 SHA-256 为
`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。
已有三版比较与提取目录见 `ALL_MODELS_LED_EVIDENCE.zh-CN.md` 和
`firmware-inbox/work/almighty-led-n76-diff/`；不重新下载或提交原包。

`led/led_n76_protocol.c` 是按协议独立编写的事务规划器，没有复制原厂 GPL 实现。
“先停两通道效果、清当前灯输出、写所需时序/PWM、再置位/开启效果”是基于这些独立
接口组合的静态设计，尚无实机验证。真实输出/PWM/时序读口仍 unknown，未读取猜测的寄存器。

## 官方固件实际如何处理

已重新核对 UGOS 1.20 实际 `.ko`，而非仅凭开源代码猜测：

- `brightness_set` 先记录请求并调度 workqueue；`mcu_work` 向 B1/A0 发出开关和颜色位命令。
- 480T 在请求值不是0/1时额外写 E0/E1，并更新内存中的 brightness；DH2600 的 worker 没有 PWM 写入。
- `color_show` 从 `led` 结构的颜色字节返回文本；`rbrightness_show` 从结构内 brightness 整数返回文本。这两个函数都没有 SMBus 读取调用。
- `mode_show` 真正读取 0x50+bit / 0x51+bit；`version_show` 读取 0x5d。模式为0只代表无效果，不代表输出关闭。
- 480T `mcu_work` 的写失败分支调用 `_dev_err` 后跳回后续流程；A0失败后仍可能继续写 PWM，PWM 失败后仍可能更新缓存。DH2600 对 A0/B1 的失败也记录错误再继续。这条异步 worker 路径不提供完整事务成功或真实灯态保证。

因此，官方方案能够控制灯，是因为已知写协议，不是因为它每次验证了真实灯态。
本项目沿用已确认的协议，明确区分“命令已发送”和“硬件状态已验证”，并对 I/O 错误停止后续写入；不复制原厂忽略错误后继续更新缓存的行为。

DXP480T Plus 1.20 模块 SHA-256 为
`2ed2f93f6c72a2783163169e805c4c04dfa49bf30185f00355d179486bf60694`；
DH2600 模块 SHA 见上。现有反汇编定位：480T `color_show=0x180`、
`rbrightness_show=0x230`、`mcu_work=0x680`；DH2600 `mode_show=0xb0`、
`mcu_work=0x610`。这些地址仅适用于此处 SHA 对应的模块。

## 验证限制

测试通过模拟 SMBus 验证三盏灯位移、单色时序字节序、480T PWM、失败停止、错误身份、
BIOS/MCU 变化、所有者冲突、锁、默认不写及输出 unknown 语义。Release 和隔离 Linux/QEMU
结果记录在本轮验证文件；这些均不能替代 DH2600 或 DXP480T Plus 实机灯态验证。
旧 `2026-10-26-n76-build` 报告和 `2026-10-27-f2ffb71` 工具包仅是已撤回方案的历史快照，
不能用于证明当前直控代码。当前工具不再提供驱动编译功能，未修改 LLLED_FPK。
