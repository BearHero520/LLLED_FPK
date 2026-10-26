# DXP4800S reverse-engineering record

> Updated firmware evidence and current implementation: [UGOS 1.19.1.0126](DXP4800S_1.19.md).

This record documents the firmware evidence used by the `dxp4800s` plugin.
It is not a physical validation report.

The completed model-intake checklist is in
[DXP4800S_INTAKE.md](DXP4800S_INTAKE.md).

## Identity and source

- Exact DMI product name: `DXP4800S` — **firmware evidence**
- Firmware: UGOS Pro `1.17.0.0095`, build `20260630.111337`
- Kernel: `6.12.30+`
- Firmware image SHA-256:
  `7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`
- Driver: `ug_it86x-sio.ko`, SHA-256:
  `4d3864794d9cdec926b666878aed4431f80b69108acceadfa21322245f1393f4`
- Stock fan daemon: `/usr/sbin/hwmonitor`, SHA-256:
  `e3a2891a20fcdbab1c90374eff0ba9b5d6840634021bb3d43e681831e89b03be`

The stock `ug-load-drive.sh` script places `DXP4800S` in the DXP4800 branch
and loads `ug_it86x-sio`. The `hwmonitor` binary selects
`/etc/default/dxp4800.conf` for the exact `DXP4800S` string. Both are
**firmware evidence**.

## Controller and access path

The stock module verifies ITE chip ID `0x8613`. Its recovered access path is:

| Item | Value | Evidence level |
| --- | --- | --- |
| Super I/O configuration ports | `0x2e / 0x2f` | firmware evidence |
| Enter configuration mode | `87 01 55 55` to port `0x2e` | firmware evidence |
| Exit configuration mode | index/data `02 / 02` | firmware evidence |
| Hardware-monitor logical device | LDN `0x04` | firmware evidence |
| Hardware-monitor index/data ports | `0xa35 / 0xa36` | firmware evidence |
| Controller ID | ITE IT8613 (`0x8613`) | firmware evidence |

This is a Super I/O hardware-monitor interface, not an ACPI EC command
dialect. A generic `/sys/kernel/debug/ec` transport is not used.

## Fan map

DXP4800S exposes one stock fan named `sysfan1`:

| Function | Register or formula | Evidence level |
| --- | --- | --- |
| Manual-control register | HWM `0x17`, clear bit 7 | firmware evidence |
| PWM write register | HWM `0x73` | firmware evidence |
| Tachometer high/low | HWM `0x1a / 0x0f` | firmware evidence |
| RPM calculation | `675000 / tachometer` | firmware evidence |

The stock `/proc/it86/fan` node is created with mode `0222` and accepts
`on`, `off`, `set N`, and `SET N`. The `on` command writes PWM `127`; `off`
writes `0`; numeric writes accept `1..255`.

The plugin deliberately exposes only target `sys` and PWM `40..255`.
`64` is the lowest running point in the stock DXP4800 curve, but it is still
only a **static safety inference**, not a physically validated stall limit.
PWM zero is not exposed through the ordinary `fan set` command.

The plugin reads PWM and mode through hwmon, or guarded direct register
reads when hwmon is absent. The stock automatic mode is a user-space policy
rather than an IT8613 hardware-auto switch. Physical readback accuracy still
requires model-specific validation.

## Stock automatic policy

The stock `hwmonitor` daemon reads CPU, SATA, and NVMe temperatures and writes
the resulting PWM to `/proc/it86/fan`. The DXP4800 curve contains:

| Source | stop / start / mid / full / max (degrees C) |
| --- | --- |
| CPU | `50 / 55 / 75 / 80 / 90` |
| HDD | `40 / 45 / 50 / 55 / 70` |
| SSD | `45 / 50 / 60 / 65 / 70` |

PWM points are `64 / 128 / 204 / 255`. On another operating system, an
"automatic" mode therefore requires a separate watchdog/daemon with reliable
temperature sources. `ugreenctl-fand` implements this software policy via guarded `ugreenctl`
writes; see [FAN_CURVE.md](FAN_CURVE.md).

## AC recovery policy

The stock module uses Super I/O LDN `0x04` registers `0xf2` and `0xf4`:

| Policy | F2 bit 5 | F4 bit 5 | F4 bit 6 | Evidence level |
| --- | --- | --- | --- | --- |
| on | 0 | 1 | 0 | firmware evidence |
| off | 0 | 1 | 1 | firmware evidence |
| restore/last | 1 | 1 | 1 | firmware evidence |

## Safe use on another Linux system

Writes require all of the following:

1. Exact DMI product name `DXP4800S`.
2. IT8613 chip ID `0x8613` and enabled HWM logical device.
3. No vendor `/proc/it86` or `ug_it86x_sio` owner. Generic IT87 may serve
   hwmon; it must be inactive before direct fallback.
4. Root or `CAP_SYS_RAWIO`.
5. `--force --apply` because physical validation is pending.
6. Independent temperature monitoring and a recovery plan.

Example guarded write:

    sudo ugreenctl --force --apply fan set sys 120

To restore stock control, stop the replacement controller, reload
`ug_it86x_sio`, and restart the stock `hwmonitor` service. If the operating
system no longer has the stock stack, reboot into UGOS Pro.

## Unknown or unvalidated

- Safe stall-free minimum PWM on a physical DXP4800S: `unknown`.
- Current PWM readback accuracy: `unknown`.
- Behavior with each non-UGOS IT87 driver and kernel version: `unknown`.
- Physical RPM response, acoustics, and thermal margin: not validated.
- Direct LED MCU writes: not exposed by this plugin.
