# Scheduled power firmware evidence

Official UGOS Pro `1.17.0.0095` (input SHA-256
`7bb2746324ac852475727cf23f7016517996b91dfb293d2292d531c1e71581b0`)
contains both parts of scheduled power control in `rootfs-base.squashfs`:

- `usr/sbin/TimedShutdown` is started by cron, provides a 30-second user
  warning, skips non-interruptible storage work, and then requests a normal
  system shutdown.
- `usr/sbin/OnSched` reads per-weekday times from the power configuration,
  calculates the next future time, and executes `rtcwake -m no -s <seconds>`.
  `preshutdown` invokes `OnSched` before shutdown.
- `usr/sbin/rtcwake` and the kernel RTC stack are present in the same official
  image.

The current 25-model audit supersedes the old WOL-based eligibility gate:
see [independent RTC and WOL evidence](ALL_MODELS_WAKE_EVIDENCE.zh-CN.md).
`ugreenctl power rtc-wake get|set|clear` now matches a separate exact-model RTC
table before plugin loading. No WOL capability bit or NIC is consulted. Writes
require `--force --apply`, a trusted process lock, stable machine/BIOS identity,
a unique matching RTC, clear-before-set and readback on the same selected path.
ARM additionally requires the firmware DT model/compatible and HYM8563 OF node;
its alarm epoch must be minute-aligned. x86 requires a unique rtc_cmos wakealarm.
The generic firmware RTC stack does not prove each board's ACPI/S5 wake path.

Linux exposes an empty `wakealarm` file when no alarm is armed. `ugreenctl`
reports that state as epoch `0` (disabled), rather than treating it as a broken
RTC interface.

The application owns the weekly calendar and safe-shutdown adapter. Before its
cron-based scheduled shutdown calls `systemctl poweroff`, it asks `ugreenctl`
to re-arm the next RTC wake. If RTC re-arming fails, shutdown is cancelled.
This maintains the separation between application scheduling and the upstream
hardware operation.

RTC alarm persistence, actual power-on, and weekly recurrence have not been
physically validated on every mapped model. The UI therefore shares the
firmware-reversed write confirmation and defaults to disabled.
