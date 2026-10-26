# DXP480T Plus direct-fan evidence

## Input and extraction

- Official input: `release_20260624-firmware_image-1.17.0.95-intel_release_amd64_6.12.30+ (1).img`
- Input SHA-256: `7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`
- Outer format: GNU tar; relevant layers are `fw.squashfs` and `kernel.squashfs`
- Extracted module: `usr/lib/modules/6.12.30+/kernel/drivers/ugreen/dxp480t/ug_it86x-cpufan.ko`
- Module SHA-256: `677b740208097187caab302a16c9bf575478b46e455096f24c5ac284f2e8ccd7`
- Module identity: x86-64 relocatable ELF, not stripped, Build ID `132224fcf54363dbe2ee04c130a2f90f2d252859`
- Stock user-space controller: `rootfs-base.squashfs:usr/sbin/hwmonitor-480t`
- Controller SHA-256: `b847151fa0958bc035e7bb66a6664a4b4571f47977e0d1b3a487b31fd7903773`
- Controller identity: x86-64 PIE ELF with debug information, Build ID `335894cab8ba58db024ceea955851eb6ab226f8c`

The original input remains outside the repository. Temporary extraction is in
`firmware-inbox/work/dxp480t-plus-1.17.0.95-sys2/`.

## Model routing

`fw.squashfs:usr/sbin/ug-load-drive.sh` matches `DXP480T` and loads
`ug_it86x-cpufan`. The module contains the exact DMI string `DXP480T Plus` and
selects the IT8613 hardware-monitor logical device at `0xa35/0xa36`.

## Confirmed facts

- The module reads three tachometer pairs: `0x0f/0x1a`, `0x0e/0x19`, and
  `0x80/0x81`.
- `fan_read` emits `cpufan`, `sysfan1`, and `sysfan2` from tachometer pairs
  `0x1a/0x0f`, `0x19/0x0e`, and `0x81/0x80`, respectively. It reports zero
  RPM for a raw tachometer value of `0x0000`, `0x0fff`, or `0xffff`; otherwise
  its conversion is `675000 / tachometer`.
- `hwmonitor-480t` writes `/proc/it86/fan` with `cpu <PWM>` and `set <PWM>`.
  `fan_write` dispatches `cpu` to `set_cpu_fan.isra.0` and `set` to
  `set_fan.isra.0`.
- In the exact `DXP480T Plus` branch, `set_cpu_fan.isra.0` clears bit `0x80`
  in control register `0x17` and writes the CPU duty to `0x73`.
- In the exact `DXP480T Plus` branch, `set_fan.isra.0` clears bit `0x80` and
  writes the two system-fan duties in this order: `0x16/0x6b`, then
  `0x1e/0x7b`. It does not write `0x17/0x73`.
- The `DXP6800`, `FORT 6`, and `DXP8800` branches use a different system-pair
  sequence (`0x17/0x73`, then `0x1e/0x7b`); that sequence is not used for
  DXP480T Plus.

## Runtime consequence

The prior fallback conflated the `cpu` and `set` DMI branches, so it wrote the
CPU register (`0x17/0x73`) for both targets. That explains a CPU fan responding
while both system fans remain unchanged. The corrected implementation preserves
the stock separation: `cpu` controls the CPU output and the legacy `all` target
replays the stock `set` transaction for the system-fan pair. Its register map is
firmware-reversed and must retain the existing guarded ownership, lock, exact-DMI,
minimum-PWM, and readback checks until physical validation is recorded.
