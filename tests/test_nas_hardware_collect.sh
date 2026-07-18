#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COLLECTOR="$ROOT/App.Native.UGreenLED/app/server/nas_hardware_collect.sh"
WRAPPER="$ROOT/App.Native.UGreenLED/cmd/hardware_diagnostic"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SYS="$TMP/sys"
PROC="$TMP/proc"
DEV="$TMP/dev"
ETC="$TMP/etc"
USR_SRC="$TMP/usr-src"
BIN="$TMP/bin"
MODULE="$TMP/it87.ko"
UGREENCTL="$TMP/ugreenctl"
DANGER_LOG="$TMP/danger.log"

mkdir -p \
    "$SYS/class/dmi/id" \
    "$SYS/module/it87/parameters" \
    "$SYS/module/it87/holders" \
    "$SYS/bus/platform/drivers/it87/it87.2608" \
    "$SYS/class/hwmon/hwmon8/device/driver" \
    "$SYS/class/i2c-adapter/i2c-2" \
    "$SYS/bus/i2c/devices/2-0031" \
    "$SYS/class/leds/power" \
    "$PROC/it86" "$DEV" "$ETC" "$USR_SRC/it87-test" "$BIN" "$TMP/out"

printf '%s\n' 'DXP480T Plus' > "$SYS/class/dmi/id/product_name"
printf '%s\n' 'UGREEN' > "$SYS/class/dmi/id/sys_vendor"
printf '%s\n' 'board' > "$SYS/class/dmi/id/board_name"
printf '%s\n' 'it8613' > "$SYS/class/hwmon/hwmon8/name"
printf '%s\n' '1234' > "$SYS/class/hwmon/hwmon8/fan3_input"
printf '%s\n' '96' > "$SYS/class/hwmon/hwmon8/pwm2"
printf '%s\n' '1' > "$SYS/class/hwmon/hwmon8/pwm2_enable"
printf '%s\n' '' > "$SYS/module/it87/parameters/force_id"
printf '%s\n' 'SMBus I801 adapter' > "$SYS/class/i2c-adapter/i2c-2/name"
printf '%s\n' 'mcu_led' > "$SYS/bus/i2c/devices/2-0031/name"
printf '%s\n' 'i2c:mcu_led' > "$SYS/bus/i2c/devices/2-0031/modalias"
printf '%s\n' '0000000000000a30-0000000000000a3f : pnp 00:00' > "$PROC/ioports"
printf '%s\n' '  0000000000000a35-0000000000000a36 : it87' >> "$PROC/ioports"
printf '%s\n' 'it87 12345 0 - Live 0x0' > "$PROC/modules"
printf '%s\n' 'NAME="Fixture Linux"' > "$ETC/os-release"
printf '%s\n' 'PACKAGE_NAME="it87"' 'PACKAGE_VERSION="test"' > "$USR_SRC/it87-test/dkms.conf"
printf '%s\n' '/* fixture */' > "$USR_SRC/it87-test/it87.c"
printf '%s\n' 'fixture-module' > "$MODULE"
touch "$DEV/i2c-2"

cat > "$BIN/lsmod" <<'EOF'
#!/bin/bash
printf '%s\n' 'Module Size Used by' 'it87 12345 0' 'i2c_dev 123 0'
EOF
cat > "$BIN/modinfo" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "-n" ]]; then
    printf '%s\n' '$MODULE'
else
    printf '%s\n' 'filename: $MODULE' 'description: fixture module' 'name: it87'
fi
EOF
cat > "$BIN/i2cdetect" <<'EOF'
#!/bin/bash
printf '%s\n' 'i2c-2 smbus SMBus I801 adapter'
EOF
cat > "$BIN/i2cget" <<'EOF'
#!/bin/bash
address=${3:-}
reg=${4:-}
if [[ "$address" == "0x31" && "$reg" == "0x5a" ]]; then
    echo 0xa5
elif [[ "$address" == "0x31" && "$reg" == "0x5b" ]]; then
    echo 0xb5
elif [[ "$address" == "0x31" && "$reg" == "0x5d" ]]; then
    echo 0x07
else
    echo 'Error: Device or resource busy' >&2
    exit 1
fi
EOF
cat > "$BIN/lspci" <<'EOF'
#!/bin/bash
printf '%s\n' '00:1f.4 SMBus [0c05]: Intel Corporation SMBus Controller' 'Kernel driver in use: i2c_i801'
EOF
cat > "$BIN/dmesg" <<'EOF'
#!/bin/bash
printf '%s\n' '[0.0] i2c i2c-2: SMBus I801 adapter registered' '[0.1] it87: Found IT8613'
EOF
cat > "$BIN/dkms" <<'EOF'
#!/bin/bash
printf '%s\n' 'it87/test, kernel, installed'
EOF
for dangerous in modprobe rmmod i2cset; do
    cat > "$BIN/$dangerous" <<EOF
#!/bin/bash
echo '$dangerous' >> '$DANGER_LOG'
exit 99
EOF
done
cat > "$UGREENCTL" <<'EOF'
#!/bin/bash
echo 'error: controller owner is active: /sys/module/it87'
exit 1
EOF
chmod +x "$BIN"/* "$UGREENCTL"

COMMON_ENV=(
    "PATH=$BIN:$PATH"
    "UGREEN_DIAG_SYS_ROOT=$SYS"
    "UGREEN_DIAG_PROC_ROOT=$PROC"
    "UGREEN_DIAG_DEV_ROOT=$DEV"
    "UGREEN_DIAG_ETC_ROOT=$ETC"
    "UGREEN_DIAG_USR_SRC_ROOT=$USR_SRC"
    "UGREEN_DIAG_UGREENCTL=$UGREENCTL"
)

REPORT=$(env "${COMMON_ENV[@]}" bash "$COLLECTOR" --stdout --i2c-probe)
grep -Fq 'read_only=true' <<< "$REPORT"
grep -Fq 'product_name=DXP480T Plus' <<< "$REPORT"
grep -Fq 'it87_loaded=true' <<< "$REPORT"
grep -Fq 'it87_bound=true' <<< "$REPORT"
grep -Fq 'i2c_adapter_count=1' <<< "$REPORT"
grep -Fq 'name=it8613' <<< "$REPORT"
grep -Fq 'node=pwm2 mode=' <<< "$REPORT"
grep -Fq 'value=96' <<< "$REPORT"
grep -Fq 'address=0x31 register=0x5a exit_code=0 output=0xa5' <<< "$REPORT"
grep -Fq 'address=0x26 register=0x5a exit_code=1 output=Error: Device or resource busy' <<< "$REPORT"
grep -Fq 'no_pwm_or_policy_writes=true' <<< "$REPORT"
grep -Fq 'no_i2c_data_writes=true' <<< "$REPORT"
[[ ! -e "$DANGER_LOG" ]] || { echo 'collector invoked a state-changing command' >&2; exit 1; }

MESSAGE=$(env "${COMMON_ENV[@]}" TMPDIR="$TMP/out" TRIM_APPDEST="$ROOT/App.Native.UGreenLED/app" \
    bash "$WRAPPER" --no-i2c-probe)
OUTPUT=${MESSAGE##*：}
[[ -f "$OUTPUT" ]]
grep -Fq 'targeted_i2c_probe=false' "$OUTPUT"
case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *) [[ "$(stat -c '%a' "$OUTPUT")" == "600" ]] ;;
esac

echo 'nas hardware collector tests passed'
