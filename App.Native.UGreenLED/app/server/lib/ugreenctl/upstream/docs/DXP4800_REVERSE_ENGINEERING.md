# DXP4800 fan, AC recovery, and Wake-on-LAN evidence

This record documents firmware evidence for the exact DMI product name
`DXP4800`. It is a clean-room static analysis, not a physical validation
record.

## Input and extraction

- User-supplied input: `E:\工作台\固件\4800.img`
- Input SHA-256:
  `7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`
- Outer container: GNU tar; relevant layers are `kernel.squashfs` and
  `fw.squashfs`.
- UGOS Pro version/build: `1.17.0.0095`, `20260630.111337`; kernel `6.12.30+`.
- Extracted files:
  - `kernel.squashfs:usr/lib/modules/6.12.30+/kernel/drivers/ugreen/ug_it86x-sio.ko`
  - `fw.squashfs:usr/sbin/ug-load-drive.sh`
  - `fw.squashfs:usr/sbin/hwmonitor-amd`
  - `fw.squashfs:etc/default/dxp4800.conf`
- Module SHA-256:
  `4d3864794d9cdec926b666878aed4431f80b69108acceadfa21322245f1393f4`
- `hwmonitor-amd` SHA-256:
  `4718169d5f2e462991e3480cc8100fba8c5bd38f6a6cbfdb6de65c7c7a3079c0`

The original image remains untouched. Selective extraction is in
`firmware-inbox/work/dxp4800-1.17.0.95/`, which is ignored by Git.

## Exact model route and controller

The stock `ug-load-drive.sh` has an exact `DXP4800` branch. It loads
`ug_it86x-sio`; the startup script separately selects `hwmonitor-amd` for the
exact model. These are firmware evidence, rather than a transfer from an
adjacent DXP4800 variant.

`ug_it86x-sio.ko` identifies ITE IT8613 and uses configuration ports
`0x2e/0x2f`. It enters configuration with `87 01 55 55`, selects hardware
monitor LDN `0x04`, and derives index/data ports `0xa35/0xa36`. The stock
interface is Super I/O, not an ACPI EC interface.

The module exposes named functions `startup_read`, `set_bios`, and
`startup_write`. Targeted x86-64 disassembly shows the configuration-port
sequence in both `startup_read` and `set_bios`; `startup_write` dispatches its
`on`, `off`, and `last status` inputs to `set_bios`.

## Firmware-recovered capabilities

| Capability | Stock route | Recovered interface | Evidence level |
| --- | --- | --- | --- |
| System fan | `ug_it86x-sio` + `hwmonitor-amd` | sysfan1: control `0x17`, PWM `0x73`, tachometer `0x1a/0x0f` | firmware evidence |
| AC recovery | `ug_it86x-sio` | LDN `0x04` registers `0xf2` and `0xf4` | firmware evidence |
| WOL | `hwmonitor-amd` | `ETHTOOL_SWOL` equivalent for `eth0` and `eth1` | firmware evidence |
| LED | `leds-mcu-28a48` | separate LED-MCU control plane | not exposed here |

The DXP4800 daemon configuration has one system fan and no CPU fan:
`has_cpu_fan=0`, `has_sys_fan=1`. Its `stock-4800` user-space profile preserves
the recovered configuration (the leading zero-PWM stop points are intentionally
not reproduced):

| Sensor | Vendor temperature points | Applied system PWM points |
| --- | --- | --- |
| CPU | 45 / 50 / 70 / 75 / 85 °C | 64 / 128 / 204 / 255 |
| SATA | 35 / 40 / 45 / 50 / 65 °C | 64 / 128 / 204 / 255 |
| NVMe | 40 / 45 / 55 / 60 / 65 °C | 64 / 128 / 204 / 255 |

The software curve maintains the global safety floor instead of writing zero;
this is not physical proof of a stall-free minimum in every chassis.

The AC-recovery bit combinations recovered from `set_bios` are:

| Policy | F2 bit 5 | F4 bit 5 | F4 bit 6 |
| --- | --- | --- | --- |
| on | 0 | 1 | 0 |
| off | 0 | 1 | 1 |
| restore/last | 1 | 1 | 1 |

`ugreenctl power startup get|set on|off|restore` uses this guarded path. It
preserves unrelated bits and verifies the resulting register values before
returning success.

## Wake-on-LAN is NIC configuration, not a BIOS register

`hwmonitor-amd` function `load_hw_config` reads `power.wake_on`. Static
cross-references show that it invokes the following sequence:

```text
enabled:  ethtool -s eth0 wol g; ethtool -s eth1 wol g
disabled: ethtool -s eth0 wol d; ethtool -s eth1 wol d
```

The new model-specific WOL operation calls the Linux ethtool ioctl rather than
spawning the command. It preflights magic-packet support on both firmware-mapped
interfaces, writes both, and reads both back. It intentionally does not guess
renamed interfaces such as `enp*`; a non-UGOS installation must retain the
firmware `eth0`/`eth1` mapping for this operation to be available.

## Safety and unknowns

The `dxp4800` plugin is `reverse-engineered`:

- every write requires exact `DXP4800` DMI plus `--force --apply`;
- fan direct fallback rejects vendor `/proc/it86`, `ug_it86x-sio`, and `it87`
  ownership, takes the process lock, verifies IT8613 identity, and verifies
  manual mode/PWM writes;
- AC-recovery writes use the guarded Super-I/O layer and now read both registers
  back;
- WOL checks NIC support and state before and after a write; it does not touch
  Super-I/O or LED hardware.

Physical fan RPM/PWM response, AC-recovery behavior, and WOL persistence
across shutdown, reboot, and AC removal are still unvalidated. DXP4800 LED
commands remain outside this repository; the application must continue to use
its bundled `ugreen_leds_cli` path for LED operations.

Example guarded commands:

```sh
sudo ugreenctl --force --apply fan set sys 120
sudo ugreenctl --force --apply power startup set restore
sudo ugreenctl --force --apply network wol set on
```
