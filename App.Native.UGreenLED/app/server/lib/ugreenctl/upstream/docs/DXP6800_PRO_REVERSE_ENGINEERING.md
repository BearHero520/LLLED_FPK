# DXP6800 Pro fan and BIOS/AC-recovery evidence

The newer user-supplied `6800plus.img` (UGOS Pro 1.20.0.0142) reconfirms
the fan and AC-recovery register map. See
[the 1.20 firmware check](DXP6800_1.20_FIRMWARE_CHECK.zh-CN.md).
Its filename does not establish a supported `DXP6800 Plus` DMI alias.

## Input and extraction

- User-supplied input: `E:\工作台\固件\6800 pro.img`
- SHA-256: `7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`
- Outer format: GNU tar. Relevant layers are `kernel.squashfs` and
  `rootfs-base.squashfs`.
- UGOS Pro version/build: `1.17.0.0095`, `20260630.111337`; kernel `6.12.30+`.
- Extracted control module:
  `kernel.squashfs:usr/lib/modules/6.12.30+/kernel/drivers/ugreen/dxp480t/ug_it86x-cpufan.ko`
- Module SHA-256: `677b740208097187caab302a16c9bf575478b46e455096f24c5ac284f2e8ccd7`
- Stock daemon: `rootfs-base.squashfs:usr/sbin/hwmonitor`
- Daemon SHA-256: `e3a2891a20fcdbab1c90374eff0ba9b5d6840634021bb3d43e681831e89b03be`

The original image remains untouched. Temporary extracts are in
`firmware-inbox/work/dxp6800pro-1.17.0.0095/` and are ignored by Git.

## Model routing and controller

`ug-load-drive.sh` loads `ug_it86x-cpufan` when the DMI product name matches
the `DXP6800` prefix (also used for DXP8800 and FORT 6). The runtime plugin
accepts only the precise DMI string `DXP6800 Pro` for any access.

The module's `it87x_init` identifies ITE IT8613 and selects the hardware-monitor
logical device at `0xa35/0xa36`; Super I/O configuration uses `0x2e/0x2f`.
The stock `hwmonitor` service supplies the temperature curve in user space.
It is not evidence of an IT8613 hardware automatic mode.

## Firmware-recovered fan map

`fan_read` selects the DXP6800 branch and reports three tachometers:

| ugreenctl id | IT8613 tachometer (low/high) | Linux it87 status node |
| --- | --- | --- |
| `cpu` | `0x0e` / `0x19` | `pwm2`, `fan2_input` |
| `sys1` | `0x0f` / `0x1a` | `pwm3`, `fan3_input` |
| `sys2` | `0x80` / `0x81` | `pwm4`, `fan4_input` |

The module's `set_cpu_fan.isra.0` compares the first seven bytes of the product
name with `DXP6800`, clears control bit 7 in `0x16`, then writes the requested
PWM to `0x6b`.

Its `set_fan.isra.0` DXP6800/FORT 6/DXP8800 branch clears control bit 7 and
writes the same requested PWM to both system channels, in stock order:

| Target | Control register | PWM register |
| --- | --- | --- |
| `sys1` | `0x17` | `0x73` |
| `sys2` | `0x1e` | `0x7b` |

The exported `sys` target reproduces that pair operation. Independent `sys1`
or `sys2` writes are intentionally not exposed because the stock interface only
provides the paired `set <pwm>` command.

## Firmware-recovered BIOS/AC-recovery map

`startup_read` reads Super I/O registers `0xf2` and `0xf4`; `set_bios` writes
the same pair for `on`, `off`, and `last status` recovery. The implementation
uses the existing guarded IT8613 power layer and exposes this as
`power startup get|set on|off|restore`.

## Support status and safeguards

This is a static clean-room recovery, not a physical validation record. The
model is therefore `reverse-engineered`:

- every write requires exact `DXP6800 Pro` DMI plus `--force --apply`;
- PWM is constrained to `40..255` and every mode/PWM write is read back;
- the preferred path is an existing `name=it8613` hwmon node;
- the direct fallback rejects the vendor `/proc/it86` interface,
  `ug_it86x_cpufan`, and `it87`, takes `/run/ugreenctl-it8613.lock`, verifies
  the IT8613 chip ID, and then verifies each write;
- no LED operation is exposed. LED control remains outside this repository's
  hardware control plane.

Physical testing must compare all three RPM readings, both system fans after a
`sys` write, CPU PWM, and AC recovery behavior before promotion to
`supported`.
