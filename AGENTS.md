# Hardware Control Boundaries

The following rules are mandatory for every change in this repository:

- BIOS hardware capabilities, including fan control and AC-power recovery, must use `E:\工作台\UGREEN-NAS-Hardware` as the source of truth. Implement hardware detection, register or hwmon access, model mappings, locking, and readback there; LLLED_FPK may only provide the application adapter, API, and UI around the resulting `ugreenctl` implementation.
- All LED operations must go through the bundled executable at `E:\工作台\LLLED_FPK\App.Native.UGreenLED\app\server\bin\ugreen_leds_cli` (runtime path: `server/bin/ugreen_leds_cli`). Do not add or retain an application-side LED path that directly writes I2C, sysfs, Super I/O, `/dev/port`, MCU registers, or another hardware backend.
- Keep the two control planes separate: never use `ugreen_leds_cli` for BIOS/fan/AC-recovery work, and never add LED control to `UGREEN-NAS-Hardware`.
- When a required hardware capability is missing, update or verify the responsible upstream implementation first instead of duplicating low-level hardware logic inside LLLED_FPK.

# Packaging Output Boundary

- All final FPK packages and their checksum files must be written to `E:\工作台\LLLED_FPK\dist` (repository path: `dist/`).
- Do not leave final `.fpk` or `.fpk.sha256` artifacts in the repository root, `build-*` directories, `scripts/`, or source directories.
- Local and remote packaging entry points must use `dist/` as their default final destination. Ephemeral CI smoke-test artifacts may use the CI runner's temporary directory.

# Packaging, Push, and Release Command Semantics

Treat these as three separate operations. Authorization for one operation never implies authorization for either of the others:

- **Package / 打包** means build the FPK from the current local checkout by running the local packaging entry point. Write the completed `.fpk` and `.fpk.sha256` files to `dist/`. Do not push commits or tags, dispatch a remote build as a substitute, or create/update a GitHub Release.
- **Push / 推送** means push the local `main` branch to `origin/main` (`https://github.com/BearHero520/LLLED_FPK.git`). Do not push a version tag and do not create/update a GitHub Release unless the user separately asks to publish a version.
- **Publish a version / 发布版本** means publish the manifest version as a GitHub Release at `https://github.com/BearHero520/LLLED_FPK/releases/tag/v<version>`. Before publishing, verify that the release commit is present on `origin/main`, the tag is exactly `v<manifest-version>`, and the local package and checksum in `dist/` pass validation. A version-publish request authorizes pushing that single matching version tag and creating/updating its Release, but it does not authorize unrelated commits, branches, or tags.
- Release assets must include `dist/App.Native.UGreenLED-<version>.fpk`, `dist/App.Native.UGreenLED.fpk`, and `dist/App.Native.UGreenLED-<version>.fpk.sha256`.
