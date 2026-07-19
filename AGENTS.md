# Hardware Control Boundaries

The following rules are mandatory for every change in this repository:

- BIOS hardware capabilities, including fan control and AC-power recovery, must use `E:\工作台\UGREEN-NAS-Hardware` as the source of truth. Implement hardware detection, register or hwmon access, model mappings, locking, and readback there; LLLED_FPK may only provide the application adapter, API, and UI around the resulting `ugreenctl` implementation.
- All LED operations must go through the bundled executable at `E:\工作台\LLLED_FPK\App.Native.UGreenLED\app\server\bin\ugreen_leds_cli` (runtime path: `server/bin/ugreen_leds_cli`). Do not add or retain an application-side LED path that directly writes I2C, sysfs, Super I/O, `/dev/port`, MCU registers, or another hardware backend.
- Keep the two control planes separate: never use `ugreen_leds_cli` for BIOS/fan/AC-recovery work, and never add LED control to `UGREEN-NAS-Hardware`.
- When a required hardware capability is missing, update or verify the responsible upstream implementation first instead of duplicating low-level hardware logic inside LLLED_FPK.
