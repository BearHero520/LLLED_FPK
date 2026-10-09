# Patched `ugreen_leds_cli`

This application bundles a patched build of
[`miskcoo/ugreen_leds_controller`](https://github.com/miskcoo/ugreen_leds_controller)
at commit `1e881da8b3d8598abadb50e859e8433c365c2840` (MIT).

`patches/dxp480t-power.patch` adds the DXP480T/DXP480T Plus N76E003 power LED
protocol reported as working in [issue #6, comment 2156807225](https://github.com/miskcoo/ugreen_leds_controller/issues/6#issuecomment-2156807225).
It exposes these CLI-only commands:

```
ugreen_leds_cli --dxp480t-power-probe
ugreen_leds_cli --dxp480t-power <red|white> <off|steady|fast|slow|breath>
```

The patch is intentionally applied to the CLI source, not to LLLED_FPK shell
code. The application invokes only the bundled `server/bin/ugreen_leds_cli`.

`patches/diagnostics.patch` adds detailed SMBus errno/operation reporting and a
read-only `--diagnose` command. The diagnostic command reports the selected
I801 adapter, `/dev/i2c-*` node, fixed `0x3a` address, effective write protocol,
power-status read result, and raw acknowledgement register value without
changing any LED state.

`patches/dx4600-firmware-1.19.patch` retains the user-tested DX4600 controller
selection, MCU signature checks, retry timing and CLI process lock. Color and
on/off control are confirmed working on exact DX4600. Intermittent ACK errors
remain separately tracked; DH2600 is maintained on its own branch. See
[DX4600 validation baseline](DX4600_VALIDATION.zh-CN.md).

`patches/dxp4800s-firmware-1.19.patch` adds exact-DMI DXP4800S MCU
signature validation and adapter retry using the 1.19.1.0126 stock module.
See [DXP4800S firmware evidence](DXP4800S_1.19.zh-CN.md).

`patches/dx4600-i801-priority.patch` tries I801 adapters before the unrelated
DesignWare adapters on DX4600, DX4600+ and DX4600 Pro. Every candidate still
requires the existing MCU signature validation; failed I801 candidates fall
back to the other eligible adapters. The shared CLI lock remains in place.
The application batches explicitly mapped LED names in one status invocation.
