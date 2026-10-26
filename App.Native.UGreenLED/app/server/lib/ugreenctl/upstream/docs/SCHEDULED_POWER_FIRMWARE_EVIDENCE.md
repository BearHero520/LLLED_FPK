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

`ugreenctl power rtc-wake get|set|clear` is a guarded clean-room equivalent of
the firmware RTC operation. It is available only to an exact model plugin with
the separately firmware-mapped WOL capability, requires `--force --apply` for
writes, discovers a Linux `wakealarm` interface, clears before setting, and
verifies readback. It does not write Super-I/O or LED registers.

RTC scheduled wake does not read or configure a network interface and is
therefore unaffected by fnOS interface renaming. The WOL capability is used
only as a conservative model-eligibility gate; the wake transaction itself is
performed exclusively through the discovered Linux RTC `wakealarm` node.

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
