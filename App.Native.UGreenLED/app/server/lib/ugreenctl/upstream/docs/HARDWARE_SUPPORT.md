# Hardware support policy

ugreenctl distinguishes a model profile from supported hardware.

The Almighty LED/disk commands use separate compiled capability profiles. Their
experimental support and per-revision constraints are documented in
[LED control and physical mapping](LED_CONTROL.zh-CN.md). The model sections
below retain the fan/power plugin evidence; an older plugin's null LED callback
does not describe the newer built-in LED command path.

The all-model extension remains in progress. Per-model firmware facts,
implementation gaps and fixture coverage are recorded in
[LED evidence](ALL_MODELS_LED_EVIDENCE.zh-CN.md) and
[disk evidence](ALL_MODELS_DISK_EVIDENCE.zh-CN.md). Linux ARM64 builds retain
exact device-tree identity checks and cannot use the x86 Super I/O transport.
The GPIO holder retains line ownership; its availability does not make an
unverified model or topology supported.

| Level | Meaning |
| --- | --- |
| Supported | Controller identity, access sequence, and every exposed write register are verified on the named model. |
| Read-only | The data source is verified, but no write operation is exposed. |
| Reverse-engineered | The stock command path and registers are recovered, but physical validation is pending; writes require model-specific safeguards plus `--force --apply`. |
| Profile only | The plugin participates in model discovery but exposes no hardware functions. |

Supported and explicitly guarded reverse-engineered plugins may provide write
commands. A placeholder must never map plausible-looking registers or reuse a
controller map from another model.

## DXP4800 Plus / DXP4800 Pro

The dxp4800plus plugin supports DMI product names DXP4800 Plus and DXP4800
Pro.

- Preferred controller: Linux `it87` driver, hwmon node selected by `name=it8613`
- Fan channels: CPU and system
- AC recovery policy: on, off, restore previous state

Fan reads and writes prefer the existing hwmon node and the tool never unloads
`it87`. If that node is absent, a direct Super I/O fallback uses the exact
CPU/system mapping. It opens only after rejecting the vendor interfaces and an
active `it87` module, acquires the same process lock, confirms IT8613 identity,
and verifies every write. The fallback needs `--force --apply` because its direct
fan transaction is not yet separately physically validated. AC recovery remains
an independent Super I/O operation.

Both exact DMI names also expose firmware-reversed Magic Packet WOL on the
stock `eth0` and `eth1` NICs. WOL uses ethtool rather than Super I/O, requires
`--force --apply`, and awaits physical shutdown/persistence validation.

## DXP4800

The `dxp4800` plugin matches only the exact DMI product name `DXP4800`. Its
route, IT8613 controller map, AC-recovery path, and WOL behavior were recovered
from the supplied UGOS Pro 1.17.0.95 image.

- Preferred fan controller: Linux `it87` hwmon node with `name=it8613`
- Single stock fan target: `sys` (`sysfan1`), direct map `0x17/0x73` and
  tachometer `0x1a/0x0f`
- AC recovery: Super I/O registers `0xf2/0xf4`, on/off/restore
- Wake-on-LAN: magic-packet WOL across the firmware-mapped `eth0` and `eth1`
  NICs; this uses ethtool, not a Super-I/O or BIOS register

Fan, AC-recovery, and WOL writes require exact DMI matching plus
`--force --apply`. Fan control uses the existing `it8613` hwmon path when
present; otherwise its model-specific fallback enforces controller ownership,
IT8613 identity, locking, a safe PWM range, and readback. WOL preflights NIC
magic-packet support and verifies both NIC states after writing. The paths are
firmware-reversed and await physical validation; LED control is not exposed.
See [DXP4800_REVERSE_ENGINEERING.md](DXP4800_REVERSE_ENGINEERING.md).

## DXP4800S

The `dxp4800s` plugin matches only the exact DMI product name `DXP4800S`.
Its map was recovered from UGOS Pro 1.17.0.0095 `ug_it86x-sio.ko` and the
stock `hwmonitor` model branch.

- Preferred controller: Linux `it87` driver, dynamic hwmon node `name=it8613`
- Single fan target: `sys` (stock name `sysfan1`)
- Exposed PWM range: `40..255`
- AC recovery registers: `0xf2/0xf4`
- Current PWM is read directly; only the supported manual mode is reported as
  known (the stock temperature policy is a user-space daemon)

Writes require exact DMI matching and `--force --apply`. They use the dynamic
`name=it8613` node when present; otherwise they use the recovered direct map
only after the vendor `/proc/it86` interface and generic `it87` module are both
inactive. Neither `--force` nor model selection bypasses ownership, chip-ID, or
lock checks. The direct path is firmware-reversed and awaits physical write
validation. See [DXP4800S_REVERSE_ENGINEERING.md](DXP4800S_REVERSE_ENGINEERING.md).

Firmware-reversed Magic Packet WOL is also available for the exact stock
`eth0`/`eth1` NIC map and requires the same `--force --apply` acknowledgement.

## DXP480T Plus

The dxp480tplus plugin matches the exact DMI product name DXP480T Plus. Its
ITE IT8613 map was recovered from the stock 1.17.0.95
ug_it86x-cpufan module.

- Input image SHA-256:
  7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0
- Fan status uses hwmon channels `pwm3/fan3_input` (CPU),
  `pwm2/fan2_input` (system fan 1), and `pwm4/fan4_input` (system fan 2).
- The vendor `cpu <PWM>` command controls CPU through `0x17/0x73`.
  The legacy `all` target replays its `set <PWM>` transaction for the system
  fan pair, ordered `0x16/0x6b` (system fan 1) then `0x1e/0x7b` (system fan 2).
- AC recovery policy: Super I/O registers 0xf2 and 0xf4
- LED hardware: N76E003 MCU via an I2C/SMBus driver; no ugreenctl LED write
  operation is exposed

Fan writes through hwmon require `--apply`; each `pwm*_enable=1` and PWM write
is read back while holding a process lock. If the `it8613` hwmon node is absent,
the same model-specific map is available only with `--force --apply`, no active
vendor or `it87` owner, an IT8613 identity match, and verified readback. The
corrected map was recovered from the exact stock `cpu` and `set` branches after
the earlier fallback drove `0x17/0x73` for both targets. Only manual PWM is
exposed: `pwm*_enable=2` is not reported as the vendor software temperature
curve. The system-pair write map is firmware-reversed pending a new physical
validation record. See
[DXP480T_PLUS_FAN_REVERSE_ENGINEERING.md](DXP480T_PLUS_FAN_REVERSE_ENGINEERING.md).

The stock daemon calls `eth0` and `eth1`. A read-only FNOS report for the exact
DXP480T Plus DMI name found one wired PCI adapter, an Aquantia AQC113 renamed
to `enp115s0`, with `Supports Wake-on: pg` and `Wake-on: g`. The plugin still
prefers the stock names when both are physical. When they are absent, this model
alone accepts exactly one renamed physical PCI Ethernet adapter; two or any
other count remains rejected. The policy read is physically observed, but a
magic-packet wake after shutdown and persistence remain unvalidated, so writes
still require `--force --apply`.

## DX4600 / DX4600+ / DX4600 Pro

The `dx4600` plugin matches only the official-firmware product strings
`DX4600`, `DX4600+`, and `DX4600 Pro`. UGOS Pro 1.17.0.0095 routes this family
to a single-fan ITE IT8613 controller, an HT32F52231-family LED MCU driver, a
PC-speaker/SATA-status module, and the generic userspace `hwmonitor` daemon.

Recovered static hardware routes include:

- IT8613 config ports `0x2e/0x2f`, HWM ports `0xa35/0xa36`, LDN `0x04`
- Single fan control/PWM `0x17/0x73`, tachometer `0x1a/0x0f`
- AC recovery policy registers `0xf2/0xf4`
- LED MCU on I2C/SMBus address `0x3a`
- Four SATA-present MMIO status addresses and a legacy PC-speaker beeper path

The plugin exposes the `sys` fan, AC-recovery policy, and the firmware-mapped
`eth0`/`eth1` WOL route. It prefers a dynamic `name=it8613` hwmon node and
falls back to the model-specific direct map only when that node is absent.
Direct access requires no vendor or `it87` owner, IT8613 identity, the process
lock, a `40..255` PWM, and verified manual-mode/PWM readback. All fan,
AC-recovery, WOL, and software-curve writes require exact DMI matching and
`--force --apply`; retain these guards after validation.

On 2026-09-19 the user confirmed physical DX4600 testing passed for fan
control, AC-power recovery, and Wake-on-LAN with LLLED_FPK. The supplied
diagnostic identifies exact DMI `DX4600`, application 2.1.2, and kernel
6.18.18.c1032-trim. Preserve this working implementation as the merge baseline.
This is user-reported hardware validation, not an agent-run hardware test;
it does not extend to DX4600+/Pro or provide per-policy/per-port test details.
The application restores the saved AC-recovery choice; this does not imply
that the upstream command writes BIOS NVRAM. Family-wide compatibility values
remain conservative because this report covers only exact DX4600.

The stock automatic fan policy is the userspace `stock-4600` software curve,
not an IT8613 hardware automatic mode. LED, beeper, and SATA MMIO operations
remain unexposed. See
[DX4600_REVERSE_ENGINEERING.zh-CN.md](DX4600_REVERSE_ENGINEERING.zh-CN.md)
and [DX4600_INTAKE.md](DX4600_INTAKE.md).

## DXP6800 Pro

The `dxp6800pro` plugin matches only the exact DMI product name `DXP6800 Pro`.
The stock DXP6800 prefix route in UGOS Pro 1.17.0.0095 loads
`ug_it86x-cpufan`, which identifies ITE IT8613.

- CPU status/control: `pwm2/fan2_input`, direct map `0x16/0x6b` and
  tachometer `0x0e/0x19`
- System status: `pwm3/fan3_input` and `pwm4/fan4_input`; the stock `set`
  command writes the system pair in order `0x17/0x73`, then `0x1e/0x7b`
- AC recovery policy: Super I/O registers `0xf2` and `0xf4`

This mapping is firmware-reversed and has no physical validation record. Fan
and AC-recovery writes require exact DMI matching plus `--force --apply`.
The preferred path uses the dynamic `name=it8613` hwmon node; direct fallback
requires no vendor or `it87` owner, the same process lock, IT8613 identity, and
readback of every manual-mode/PWM write. The `sys` target preserves the stock
paired-system-fan operation; individual system-fan writes are not exposed.
The stock `hwmonitor` daemon supplies a software temperature curve, so no
hardware automatic mode is claimed. See
[DXP6800_PRO_REVERSE_ENGINEERING.md](DXP6800_PRO_REVERSE_ENGINEERING.md).

Magic Packet WOL uses the separately recovered stock `eth0`/`eth1` map and
also requires `--force --apply` until physically validated.

## Firmware-derived Wake-on-LAN

The exact WOL routes for DX4600/DX4600+/DX4600 Pro, DXP4800, DXP4800S,
DXP4800 Plus/Pro, DXP480T Plus, and DXP6800 Pro are documented in
[WOL_FIRMWARE_EVIDENCE.md](WOL_FIRMWARE_EVIDENCE.md). WOL is a NIC ethtool
operation, not a BIOS or LED control operation.

## Adding a model

1. Record the exact DMI product string and controller identity.
2. Add a profile-only model plugin first.
3. Add read-only status only after comparing it with stock firmware.
4. Add one write function at a time, with a safe default and documented map.
5. Include a hardware test record in the pull request.

## DXP6800 Plus

Exact DMI `DXP6800 Plus` has an independent firmware-reversed plugin from UGOS Pro 1.20.0.0142. It provides CPU PWM, paired system PWM, three tachometers and AC recovery, with hwmon priority, guarded direct fallback and `--force --apply`. Custom software curves and `stock-6800plus` are supported. At the user's request, this compatibility preset adopts DXP6800 Pro parameters; it is not a recovered Plus factory curve. The user reports physical validation, but its detailed scope is unavailable. WOL and RTC are exposed as firmware-reversed: the 1.20 hwmonitor-480t route confirms eth0/eth1 Magic Packet policy, with the shared physical-PCI renamed-interface resolver on fnOS and other Linux distributions. Actual wake after shutdown remains unvalidated. See [firmware evidence](DXP6800_1.20_FIRMWARE_CHECK.zh-CN.md).


## 2026-10-27 WOL / RTC 独立核对

25 款的官方调用链和条件接入见 [WOL / RTC 核对表](ALL_MODELS_WAKE_EVIDENCE.zh-CN.md)。RTC 使用独立精确机型表，不再借用 WOL 标记；15 款 WOL 自动网口映射仍未确认，必须显式指定物理网卡。全部机型实际关机唤醒、逐 BIOS 行为和持久性仍待验证。此项不改变灯光/盘位未完成清单。

## DXP6800

Exact DMI `DXP6800` has an independent firmware-reversed IT8613 plugin for CPU PWM, paired system PWM, three tachometers and AC recovery. hwmon takes priority; guarded direct fallback is allowed only on ENODEV. Writes require `--force --apply`, PWM 40..255. Custom software curves and the user-selected `stock-6800` Pro-parameter compatibility preset are available; the original factory curve and physical validation remain unknown. See [evidence](DXP6800_SUPPORT.zh-CN.md).
