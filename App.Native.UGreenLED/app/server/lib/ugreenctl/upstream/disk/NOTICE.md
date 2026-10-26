# Physical disk mapping sources

The Linux sysfs scanner is a new implementation. It never invokes the upstream
shell scripts. The original topology/slot evidence includes first-hand reports in
[ugreen_leds_controller issue 9](https://github.com/miskcoo/ugreen_leds_controller/issues/9)
(15–16 June 2024):

| Exact DMI | Controller-local ATA ports | Chassis slots |
| --- | --- | --- |
| DXP4800 | `0000:00:17.0` 1,2; `0000:01:00.0` 1,2 | 1,2; 3,4 |
| DXP6800 Pro | `0000:59:00.0` 1–4; `0000:00:17.0` 1,2 | 1–4; 5,6 |
| DXP8800 Plus | `0000:59:00.0` 1–4; `0000:5a:00.0` 1–4 | 1–4; 5–8 |
| DXP4800 Plus / DXP4800 Pro | Conditional single ASM1164 controller; local ports 1–4 | 1–4 |
| DXP2800, exact `EM_DXP2800_V1.0.24` / `DXP2800 V1.2 251215` revisions | Conditional single Intel `8086:54d3` controller; local ports 1–2 | 1–2 |

Those BDFs record the reports; they are **not fixed runtime endpoint mappings**.
The scanner now converts the official per-model firmware tables only after
recognizing complete controller roles and all empty ports. For example, 6800 Pro
has independently appeared at endpoint 58:00.0 and 59:00.0. NVMe uses official
bridge IDs or physical root paths where available. A name sharing a prefix
never inherits another model's data: DXP4800S has its own recovered firmware
table and does not inherit Plus/Pro registers or NVMe bridge IDs.

The full per-model implementation state, additional firmware hashes, static
conversion assumptions, fixtures and remaining ARM / `block_name` gaps are
recorded in [the all-model evidence document](../docs/ALL_MODELS_DISK_EVIDENCE.zh-CN.md).
Recovered records and synthetic regression tests are not physical validation.

## DXP4800 Plus / Pro: firmware and controller topology

The official UGOS Pro 1.20 `hwmonitor-480t` explicitly selects both exact DMI
names and a four-disk layout. Its table maps global `ata1..ata4` to `disk1..disk4`;
its model-specific reordering does not change those entries for Plus/Pro. The
input hashes, binary offsets and reproducible analysis are recorded in
[the firmware evidence document](../docs/DISK_MAPPING_FIRMWARE.zh-CN.md).

Independent first-hand hardware and mapping records:

- [Proxmox, pbexiga, 8 March 2026](https://forum.proxmox.com/threads/regression-in-6-17-asmedia-asm1164-sata-controller-forced-to-max_performance-preventing-disk-spin-down.181474/):
  DXP4800 Plus, ASM1164 `1b21:1164` revision 02, `ahci`, four implemented ports
  (`port mask 0xf`). Its observed BDF is `05:00.0`; this implementation does not
  assume that BDF.
- [TrueNAS, TemplarB, 24 August 2026](https://forums.truenas.com/t/i-just-started-making-my-nas-as-it-seems-one-of-hdds-is-failing-what-to-do/67624):
  the author's DXP4800 Pro uses an ASM1164 four-port controller for its four bays.
- [UGREEN LED Control source](https://github.com/alexanderschubert/ugreen-led-control)
  and [its author's support thread, October 2026](https://forums.unraid.net/topic/200791-plugin-ugreen-led-control-led-control-for-ugreen-dxdxp-nas/):
  reports from Plus and Pro owners confirm the `ata1..ata4` bay assignment.

The conversion from the firmware's global ATA order to a controller-local port
order is a static inference checked against the complete live topology, not a
new physical validation by this project. It is enabled only for exact DMI
`DXP4800 Plus` and `DXP4800 Pro` and requires every condition below:

- The complete PCI inventory has exactly one SATA controller, identified as
  `1b21:1164`, class `010601`, with driver `ahci`.
- The complete `class/ata_port` inventory, including empty bays, contains exactly
  four unique local ports 1–4, all under that same canonical PCI parent.
- No additional SATA controller, missing or duplicate port, extra ATA parent,
  or ambiguous controller is accepted. The topology is checked again after disk
  enumeration. Installed drives are never used to infer missing port numbers.

Successful entries report `firmware-asm1164-topology`. Failed structural checks
report unknown with the failed condition, and `disk locate` refuses the mapping.
Administrator calibration remains available for a separately confirmed layout.

## DXP2800 EM revision: firmware and Intel AHCI topology

The same official 1.20 image's generic `hwmonitor` selects a two-disk DXP2800
layout and maps `ata1..ata2` to `disk1..disk2` without a DXP2800-specific reorder.
[Tim Kutzner's first-hand teardown and lspci, 8 May 2024](https://www.igorslab.de/en/ugreen-nasync-dxp2800-nas-im-test/3/)
reports its sole SATA controller as Intel `54d3`; no auxiliary SATA controller is
present in that machine's full PCI inventory. Firmware details are recorded in
the firmware evidence document linked above.

Automatic mapping is restricted to exact DMI `DXP2800` **and** real sysfs
`product_version=EM_DXP2800_V1.0.24` or `DXP2800 V1.2 251215`, consistent with
separate LED protocol revision gates. The latter exact revision is independently
reported in [upstream issue 128](https://github.com/miskcoo/ugreen_leds_controller/issues/128);
its own official rev2 storage table has the same ATA1/2 slot order. It is a
conditional physical-topology conversion, not a claim that this project has
tested the newer board or that it shares EM LED registers. It reuses the
complete-controller structural checks with expected PCI
`8086:54d3`, class `010601`, driver `ahci`, and exactly two unique local ports 1–2
including empty bays. Successful entries report
`firmware-intel-ahci-topology`. This is the same documented static conversion
from firmware's global ATA order to the sole controller's local order; it is not
a new physical validation. Missing/changed revisions and a different PCI ASIC
remain unknown under this profile. GT has a separate official root-path table and BIOS revision
selector; it never uses this Intel conversion. No revision or model is supplied
through an environment override.

Upstream [ugreen-detect-disks](https://github.com/miskcoo/ugreen_leds_controller/blob/master/scripts/ugreen-detect-disks),
[ugreen-diskiomon](https://github.com/miskcoo/ugreen_leds_controller/blob/master/scripts/ugreen-diskiomon),
[ugreen-leds.conf](https://github.com/miskcoo/ugreen_leds_controller/blob/master/scripts/ugreen-leds.conf),
and [PR 15](https://github.com/miskcoo/ugreen_leds_controller/pull/15) document
global ATA, HCTL and manual serial mappings. This implementation deliberately
uses the controller-local `ata_port/ataX/port_no` together with the PCI function.
It does not normalize by the first occupied slot, sort sdX/HCTL, or use the global
ATA number as a slot. Empty slots, a nonzero SCSI host start, and nonconsecutive
global ATA numbers therefore do not shift the remaining disks.

Serial lookup first accepts a valid printable `device/serial` attribute where
the driver provides one, then decodes Linux's cached `device/vpd_pg80` SCSI unit
serial page. The binary page header, length and printable payload are validated;
missing or malformed serial data stays empty. This performs no SMART, ATA
IDENTIFY, SG_IO, disk reads, or subprocess calls. The kernel's
[SCSI sysfs implementation](https://github.com/torvalds/linux/blob/master/drivers/scsi/scsi_sysfs.c)
exposes cached VPD data. Serial and WWID are read again before accepting a scan
entry to detect identity changes during hotplug.

The [systemd ATA path implementation](https://github.com/systemd/systemd/blob/main/src/udev/udev-builtin-path_id.c)
is a reference for the Linux sysfs attribute's semantics, with no source copied.

## Explicit calibration

After manually confirming physical bays against disk identities and chassis
LEDs, an administrator may create `/etc/ugreenctl/disk-map.conf`, owned by root,
with no group/other write permission. Only a regular file is accepted; symlinks,
shell expressions, duplicate slots/topologies, and a model mismatch are rejected.
Values below are syntax placeholders, not a proposed DXP4800 Plus mapping:

```text
model=DXP4800 Plus
slot1 topology=pci-0000:05:00.0-ata-1
slot3 topology=pci-0000:05:00.0-ata-3
```

Use the topology reported by `ugreenctl disk list` for the disk physically
confirmed in each bay. Calibration is a complete replacement for built-in data:
omitted slots remain unknown. WWN and serial values report current disk identity;
they do not permanently attach that disk to a bay. Moving/replacing a drive keeps
the calibration attached to its physical connection. Reread and reconfirm it if
BIOS settings, PCI topology, controllers or cabling change.

Known exact models also enforce their physical bay count when loading a
calibration (for example, DXP2800 has two and DXP4800 Plus/Pro have four). Unknown
models permit up to eight records, while LED control still requires its own
exact supported hardware profile.

## Upstream license

MIT License

Copyright (c) 2024 miskcoo@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
