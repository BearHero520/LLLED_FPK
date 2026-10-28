# DXP6800 风扇与来电恢复（2026-10-28）

## 输入和证据

只读取证输入 `E:/工作台/固件/6800plus.img`（UGOS Pro 1.20.0.0142）。
SHA-256：`73862c9c619f3e8b2279252326654f4915234dc8f437a71eb9a0067a724062c5`。
提取目录：`firmware-inbox/work/dxp6800plus/`，复用已保留的原厂提取物。
现场诊断 `ugreen-led-diagnostics-20261028-093336.txt` 给出的精确 DMI 为
`DXP6800`，版本 `DXP6800 V1.0 20250519`；现有插件拒绝该型号。

重新核对 `fw/usr/sbin/ug-load-drive.sh:85`：DXP6800 分支加载
`ug_it86x-cpufan`，第 88 行还显式区分裸型号 DXP6800 的 LED 驱动。
本次不接入或修改 LED；这个分支也证明不能把整机冒充 Plus/Pro。
模块 `kernel/usr/lib/modules/6.18.15/kernel/drivers/ugreen/dxp480t/ug_it86x-cpufan.ko`
SHA-256 实际重算为 `dbecee7bcd4920fdc685a3162e7b7402ac12ee0994e7a87f43d1ce08da87ed4b`。
反汇编证据：同目录 `ug_it86x-cpufan.ko.analysis.txt`。

| 项目 | 模块证据 | 映射 |
| --- | --- | --- |
| 控制器 | it87x_init 0xf0 比较 0x8613 | IT8613，配置端口 0x2e/0x2f，LDN 4，HWM 0xa35/0xa36 |
| CPU | set_cpu_fan 0x97e..0x994 对 DXP6800 作七字节比较 | 控制 0x16 / PWM 0x6b；转速 0x0e/0x19 |
| 系统风扇 | set_fan 0xc46..0xc5c 的 DXP6800 分支跳到 0xd11 | 成对控制 0x17/0x73、0x1e/0x7b；转速 0x0f/0x1a、0x80/0x81 |
| 来电恢复 | set_bios、startup_read | LDN 4：0xf2 bit 5，0xf4 bits 5/6；on=0/01、off=0/11、restore=1/11 |

上述七字节分支覆盖精确 DXP6800；运行时仍只允许精确 DMI，不放行任意前缀。
这些是固件静态证据，不是现场寄存器或断电试验记录；该 BIOS 修订的物理验证仍 unknown。

## 实现

独立 `models/dxp6800.c`、`fan/it8613_dxp6800.c` 映射；复用已有来电恢复、
hwmon、直控、锁和写后回读实现。hwmon 优先，只有 ENODEV 才允许直控回退，
EIO/EACCES/EBUSY 不绕过。直控检查 IT8613/HWM 身份、原厂和 it87 所有者。
CPU 和成对系统风扇 PWM 40..255，写入需 --force --apply；不提供单系统风扇写入。
温控守护支持 custom；2026-10-28 经用户授权新增独立 stock-6800 兼容预设，采用 Pro 参数。DXP6800 原厂曲线仍未确认。
未新增 WOL、RTC 或 LED 能力。

LLLED_FPK 接入独立机型、三路遥测、写入确认、来电恢复及自定义曲线。
本地硬件扩展基于原固定产物，只增加 dxp6800.so 并更新 ugreenctl-fand；
其余二进制保留原固定产物字节，包含 LED CLI。扩展记录独立来源和哈希，不伪装已发布版本。

## 验证

使用 Windows Zig 交叉构建 Linux x86_64，并通过隔离 QEMU 运行 CTest；无宿主硬件透传。
独立映射/回退测试、精确 DMI/能力/写入保护测试，共用 IT8613 power/direct/hwmon 测试覆盖本次路径。
实际转速、PWM 响应和断电来电恢复仍需目标机器验证。

## 2026-10-28 兼容曲线
用户要求缺少原厂曲线时使用 Plus/Pro 参数。DXP6800 新增 stock-6800，采用 Pro 温度/PWM 点和 CPU 保底（65°C/PWM125、90°C/PWM220），详见 FAN_CURVE.md。保持精确 DMI 和独立硬件映射，界面标注采用 Pro 参数；不代表原厂曲线或实机散热验证。
