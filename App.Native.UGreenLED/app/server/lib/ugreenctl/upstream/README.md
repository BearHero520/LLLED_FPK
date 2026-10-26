# ugreenctl

The `Almighty` branch adds native LED control, physical SATA/NVMe bay mapping and an
optional `ugreen_leds_cli` argument-compatible executable. See
[LED and disk commands](docs/LED_CONTROL.zh-CN.md) for commands, evidence and
model-specific limits. These built-in capability profiles are independent of
the older fan/power model-plugin ABI; LED writes remain experimental.
See the [Linux NAS deployment guide](docs/LINUX_DEPLOYMENT.zh-CN.md) for runtime
libraries, persistent paths, and holder lifecycle on the target systems.

ugreenctl is an open-source, plugin-based hardware-management utility for UGREEN
NAS systems.

[中文文档](README.zh-CN.md) · [Compatibility catalog](docs/COMPATIBILITY.md) ·
[中文兼容性目录](docs/COMPATIBILITY.zh-CN.md)

Verified models receive normal write support. A firmware-reversed model can
expose only guarded writes with explicit acknowledgement while physical
validation is pending. A profile in the models/ directory is not a claim that
its controls work.

## Support matrix and implemented firmware paths

The firmware version below is the evidence used to implement the path. It is
not a promise that an untested firmware upgrade has the same behavior.

| Exact model (plugin) | Firmware evidence implemented | Available functions | Validation status |
| --- | --- | --- | --- |
| DX4600 / DX4600+ / DX4600 Pro (`dx4600`) | Official UGOS Pro `1.17.0.0095`, build `20260630.111337`, kernel `6.12.30+` | `sys` fan, AC recovery, WOL, scheduled wake | Firmware-reversed; no physical write validation. PWM is limited to `40..255`; writes need `--force --apply`. |
| DXP4800 Plus / DXP4800 Pro (`dxp4800plus`) | `1.17.0.95` | CPU/system fan readings and PWM, AC recovery, WOL, scheduled wake | Normal hwmon fan control and AC recovery are verified. Direct fallback, WOL, and scheduled wake still need `--force --apply`. |
| DXP4800 (`dxp4800`) | UGOS Pro `1.17.0.0095`, build `20260630.111337`, kernel `6.12.30+` | System fan, AC recovery, WOL, scheduled wake | Firmware-reversed; no physical write validation. Every write needs `--force --apply`. |
| DXP4800S (`dxp4800s`) | UGOS Pro `1.17.0.0095`, build `20260630.111337`, kernel `6.12.30+` | `sys` fan, AC recovery, WOL, scheduled wake | Firmware-reversed; no physical write validation. PWM is limited to `40..255`; writes need `--force --apply`. |
| DXP480T Plus (`dxp480tplus`) | UGOS Pro `1.17.0.95`, build `20260630.111337`, kernel `6.12.30+` | Fan readings, `cpu`/`all` PWM, AC recovery, WOL, scheduled wake | CPU writes have physical feedback. The corrected system-pair map, direct fallback, WOL, and scheduled wake await controlled physical validation. |
| DXP6800 Pro (`dxp6800pro`) | UGOS Pro `1.17.0.0095`, build `20260630.111337`, kernel `6.12.30+` | CPU/paired-system fans, AC recovery, WOL, scheduled wake | Firmware-reversed; no physical write validation. Every write needs `--force --apply`. |
| DXP2800 / DXP8800 Plus | Upstream LED protocol records | Model detection and conditional built-in LED profiles | Fan/power plugins remain placeholders; LED writes are experimental. |

Fan/power writes require exact DMI matching. LED commands use their own
compiled profiles with exact DMI or firmware-proven ARM device-tree identity,
controller identity and ownership checks. ARM GPIO control without the stock
driver requires the explicit `ugreenctl-ledd` holder; GPIO line ownership is
kept until the holder stops. The all-model integration is still in progress;
see the [LED evidence](docs/ALL_MODELS_LED_EVIDENCE.zh-CN.md) and
[disk evidence](docs/ALL_MODELS_DISK_EVIDENCE.zh-CN.md). The machine-readable [compatibility catalog](models/compatibility.json)
and [hardware support document](docs/HARDWARE_SUPPORT.md) are the authoritative
records of evidence and safeguards.

## Build

Build on an x86/x86_64 or ARM64 Linux host. The x86 Super I/O transport is
unavailable on ARM64; compiling the utility does not enable unsupported controls:

    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build
    ctest --test-dir build --output-on-failure
    sudo cmake --install build

For a build-tree run, point the CLI at the generated plugins:

    ./build/ugreenctl --plugin-dir ./build/models models
    sudo ./build/ugreenctl --plugin-dir ./build/models info

## One-command scripts

On Debian/Ubuntu or a suitable Linux host, copy or clone the repository and run:

    sh ./scripts/install.sh --install-deps

This optionally installs the build prerequisites using the NAS package manager,
builds the project, and installs ugreenctl to /usr/local. Omit
--install-deps when CMake and a C compiler are already installed.
TrueNAS SCALE should use a prebuilt archive in a persistent dataset as described
in the deployment guide; do not install build prerequisites into its protected system.

For a build-tree run without installing files:

    sh ./scripts/run.sh models
    sudo sh ./scripts/run.sh info
    sh ./scripts/run.sh fan set cpu 120
    sudo sh ./scripts/run.sh --apply fan set cpu 120

The last command is the only one that writes the fan register. The script
does not add --apply itself.

## CLI usage, inputs, and outputs

The general command form is:

```sh
ugreenctl [options] <command> [arguments]
```

Put global options before older fan/power commands. The built-in LED/disk
commands also accept `--json`, `--apply`, and `--force` after the command.
The CLI identifies the NAS from its exact
DMI product name; `--model` selects a plugin but never spoofs the identity or
bypasses the match.

| Input | Meaning |
| --- | --- |
| `--plugin-dir <dir>` | Directory containing the model plugins. Use `./build/models` with a build-tree binary; an installed binary uses its install-time default. |
| `--model <plugin-id>` | Select a discovered plugin explicitly, for example `dxp4800plus`. The exact local DMI name must still match. |
| `--apply` | Perform a write. Without it, every write command is only a preview. |
| `--force` | Acknowledge a firmware-reversed or experimental write path when that model requires it. It does not bypass the DMI, controller-owner, chip-ID, lock, or PWM-floor checks. |

| Command and input | Output on success |
| --- | --- |
| `models` | One line per plugin: `<plugin-id>  <display name>  <capabilities>`. No NAS hardware is accessed. |
| `info` | Selected model and controller, then startup/WOL policy and each available fan-status line. A partially unavailable read is reported as a warning on standard error. |
| `thermal status` | One machine-readable line: `cpu_celsius=<n> cpu_peak_celsius=<n> hdd_celsius=<n> ssd_celsius=<n>`. A value of `-1` means that source was unavailable. |
| `fan status` | One line per fan: `<fan-id>: pwm=<0-255|unknown> mode=<manual|auto|unknown> tach=<n> rpm=<n>`. |
| `fan set <fan-id> <pwm>` | `<pwm>` is an integer from `0` to `255`; accepted fan IDs depend on the exact model. The real write output is `<fan-id> fan PWM set to <pwm>`. |
| `power startup get` | `on`, `off`, `restore`, or `unknown`. |
| `power startup set <on|off|restore>` | `startup policy set to <policy>` after an applied write. `last` is accepted as an alias for `restore`. |
| `network wol get` | `on`, `off`, or `unknown`. |
| `network wol set <on|off>` | `Wake-on-LAN policy set to <policy>` after an applied write. |
| `power rtc-wake get` | Scheduled wake as a Unix epoch (UTC). |
| `power rtc-wake set <positive-unix-epoch>` | `RTC wake set to <epoch>` after an applied, forced write. |
| `power rtc-wake clear` | `RTC wake cleared` after an applied, forced write. |

`led list/status/set/on/off/identify` and `disk list/map/locate` are available
through the built-in profiles. See [the LED command guide](docs/LED_CONTROL.zh-CN.md)
for experimental write requirements, mapping evidence and compatibility behavior.

Fan IDs are deliberately model-specific: DXP4800 Plus/Pro accepts `cpu` and
`sys`; DXP4800, DXP4800S, and DXP6800 Pro accept `sys` (DXP6800 Pro also
accepts `cpu`); and DXP480T Plus accepts `cpu` and `all`. Always start with
`fan status` on the exact NAS before choosing a target.

### Read, preview, then apply

```sh
# Read-only commands: their values are printed to standard output.
sudo ugreenctl info
sudo ugreenctl fan status
sudo ugreenctl power startup get
sudo ugreenctl network wol get

# Preview: succeeds without changing hardware.
ugreenctl fan set cpu 120
# dry-run: would set the fan PWM
# rerun with --apply to write hardware state

# Apply a normal verified write (root/CAP_SYS_RAWIO is normally required).
sudo ugreenctl --apply fan set cpu 120
# cpu fan PWM set to 120

# Firmware-reversed writes need the additional acknowledgement.
sudo ugreenctl --force --apply network wol set on
# Wake-on-LAN policy set to on
sudo ugreenctl --force --apply power rtc-wake set 1893452400
# RTC wake set to 1893452400
```

Successful commands exit with status `0`. Invalid input, an unsupported
feature, an unmatched model, a missing privilege, or a safety check failure
returns a non-zero status and writes a descriptive `error: ...` line to
standard error. Do not parse human-readable status text as a stable API; the
documented one-line `thermal status` output is the suitable compact status
format.

DXP4800S has one recovered `sysfan1` channel. The plugin calls it `sys`, and
exposes a guarded manual range of 40-255:

    sudo ugreenctl --force --apply fan set sys 120
    sudo ugreenctl --force --apply power startup set restore

DX4600, DX4600+, and DX4600 Pro use their own firmware-derived single-fan map
and the same guarded `sys` target. The three exact DMI names select the
`dx4600` plugin; prefix matching is not used:

    sudo ugreenctl --force --apply fan set sys 120
    sudo ugreenctl --force --apply power startup set restore
    sudo ugreenctl --force --apply network wol set on

The recovered `stock-4600` profile preserves the official daemon's effective
mode-2 thresholds and PWM points through `ugreenctl-fand`, while retaining the
project's non-stop safety floor. LED, beeper, and SATA MMIO operations are not
exposed.

On fnOS, WOL does not depend on a literal `eth0`/`eth1`. If both stock names
are absent, the DX4600 route enumerates physical PCI Ethernet adapters, rejects
virtual/bond/bridge devices, requires the official two-port topology, sorts by
PCI address, and verifies Magic Packet support and post-write state. Any other
physical-adapter count is rejected.

DXP6800 Pro is firmware-reversed and has not yet had a physical write
validation. It exposes the stock CPU path and the stock paired-system-fan path;
both still require `--force --apply`:

    sudo ugreenctl --force --apply fan set cpu 120
    sudo ugreenctl --force --apply fan set sys 120
    sudo ugreenctl --force --apply power startup set restore

`sys` sets both firmware-proven system PWM outputs with the same value. The
stock `hwmonitor` thermal curve is a user-space service, so it is not exposed
as a hardware automatic mode. The recovered register map and validation limits
are in [docs/DXP6800_PRO_REVERSE_ENGINEERING.md](docs/DXP6800_PRO_REVERSE_ENGINEERING.md).

The stock automatic mode is a user-space `hwmonitor` temperature daemon, not
an IT8613 hardware-auto switch. `ugreenctl-fand` is this project's guarded
software-curve replacement: it samples Linux temperatures and submits PWM
updates through `ugreenctl`. Its configuration inputs, invocation, and
machine-readable state-file output are documented in
[docs/FAN_CURVE.md](docs/FAN_CURVE.md).

Scheduled wake uses the firmware-derived Linux RTC path, not a BIOS or LED
register. It is available only for WOL-mapped exact models and needs
`--force --apply`; see
[docs/SCHEDULED_POWER_FIRMWARE_EVIDENCE.md](docs/SCHEDULED_POWER_FIRMWARE_EVIDENCE.md).

For DXP480T Plus, the `cpu` write path has physical feedback. The corrected
firmware-recovered `all` system-pair transaction still awaits controlled
physical validation. Normal hwmon writes require --apply and retain exact DMI
matching, the vendor-driver conflict guard, the IT8613 identity check, and the
PWM floor:

    sudo ugreenctl --apply fan set cpu 120
    sudo ugreenctl --apply fan set all 120

With hwmon present, the `all` target follows the vendor's two-system-fan
transaction in vendor order. When `it87` was intentionally unloaded and the
`it8613` hwmon node is absent, direct `cpu` uses control `0x17`, duty `0x73`;
direct `all` writes the system pair in order `0x16`/`0x6b`, then `0x1e`/`0x7b`.
Its three tachometers remain visible, but independent system-fan writes remain
hidden. The direct path refuses to run while any vendor interface or `it87` owns
the controller, checks chip identity and the process lock, and requires
`--force --apply`; physical validation of the corrected system-pair fallback is
still pending.

## Safety

- Every IT8613 plugin refuses to touch the controller while `/proc/it86`
  is active, avoiding concurrent register access.
- Each controller access takes an advisory lock at
  /run/ugreenctl-it8613.lock.
- Direct I/O requires root or CAP_SYS_RAWIO.
- Manual PWM disables hardware automatic control for that channel. DX4600 and
  DXP4800S stock automatic control is software-based, so stop or replace the
  stock daemon before manual use and keep temperatures independently monitored.

Before use outside UGREEN NAS firmware, unload the vendor module if it is
active:

    sudo modprobe -r ug_it86x_sio       # DX4600 / DXP4800S / DXP4800 branch
    sudo modprobe -r ug_it86x_cpufan    # DXP4800 Plus / DXP480T / DXP6800 branch

## Plugin ABI

Models may export the ABI version 3 entrypoint for fan-mode control and keep
the ABI version 2 entrypoint for compatibility:

    const struct ugreenctl_plugin *ugreenctl_plugin_v3(void);

    const struct ugreenctl_plugin *ugreenctl_plugin_v2(void);

The ABI is declared in include/ugreenctl.h. The core prefers ABI version 3,
falls back to ABI version 2, and discovers plugins by DMI product name or
--model.

## Maintaining compatibility

The machine-readable [compatibility catalog](models/compatibility.json) is the
release-facing record for every model. Before adding a plugin, follow the
[new-model intake template](docs/NEW_MODEL_TEMPLATE.md). In particular, use
exact DMI names, declare a support level, and record firmware evidence. Do not
promote a profile-only plugin to read-only or supported based on a similar
model.

## License, vendor firmware, and evidence

This repository's own source code and documentation are available under the
[MIT License](LICENSE). That license applies only to this repository; it does
not grant rights to UGREEN firmware, drivers, trademarks, or other vendor
materials.

Vendor firmware is used only as clean-room analysis evidence. This project
independently implements observed behavior, interfaces, and register maps; it
does not link, include, or redistribute vendor driver source, binaries, or
firmware images. Using this project does not grant permission to copy,
distribute, or modify vendor firmware.

The firmware version and validation status for every implemented model appear
in the support matrix above. Detailed evidence is in the
[hardware support document](docs/HARDWARE_SUPPORT.md), the
[compatibility catalog](models/compatibility.json), and the model reverse-
engineering records. This project is not affiliated with or endorsed by UGREEN.
