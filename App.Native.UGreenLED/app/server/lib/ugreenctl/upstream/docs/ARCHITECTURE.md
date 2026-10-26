# Architecture

    ugreenctl CLI
        |
        +-- core/       option parsing, DMI selection, dynamic plugin loader
        |
        +-- models/     one shared object per NAS model
                |
                +-- fan/       verified fan operations
                +-- power/     verified AC recovery operations
                +-- led/       MCU codecs, bound sysfs and persistent GPIO transport
                +-- ec/        EC transport detection; no generic writes
                +-- superio/   ITE Super I/O transport

The core owns model matching, dry-run write protection, and plugin ABI
validation. A model plugin owns its hardware map. Shared transport code must
not make a controller usable until a model explicitly enables it.

Almighty also provides a built-in LED capability registry in
`models/led_profiles.c`, keeping the older model-plugin ABI intact. The early
`core/hardware_cli.c` dispatcher handles LED and disk commands before loading
fan/power plugins; `ugreen_leds_cli` calls that same implementation. Profiles
select protocols through exact identity and revision evidence, never by MCU ID
alone. `core/identity.c` preserves raw DMI/DT identity and canonicalizes only
exact firmware-proven ARM model/compatible pairs. ARM64 builds use a fail-closed
x86 port-transport stub. `disk/` enumerates Linux physical SATA/NVMe topology and resolves only confirmed
or explicitly calibrated bay mappings. Hardware writes and timed identification
retain the same owner/identity/lock protections regardless of CLI entry point.

`ugreenctl-ledd` is an explicit foreground controller holder. For GPIO it retains
the fixed controller lock and GPIO v2 line-request FDs; a short-lived CLI cannot
promise persistent GPIO output after closing those FDs. For DXP2800 GT an
explicit `--takeover-flow` permits disabling autonomous global effects while
the holder runs, after stable full-controller snapshots. It never activates an
inactive Host2EC LDN or initializes unrelated hardware. Clean exit restores all
four raw LED states and the original FLOW, with failures reported. Autonomous
animation phase remains unknown. Root-only, versioned Unix socket
messages contain bounded values and no paths. SO_PEERCRED authenticates each
client, and one connection remains exclusive through identification/restoration.
Every write requires both acknowledgements at the CLI, RPC and transport layers.
The authenticated client PID is excluded only while that connection is active;
other controller owners still block operations. No service is started implicitly.
GT identify uses holder-owned raw BEGIN/END snapshots; caller-provided bytes
never cross the socket. Disconnect, protocol failure or timeout also triggers
restoration before the authenticated-client exclusion is cleared. Restoration
failure stops the holder and remains an execution error.
