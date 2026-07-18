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
