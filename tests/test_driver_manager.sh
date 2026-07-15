#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }

VAR_DIR="$TMP/var"
SERVER_DIR="$ROOT/App.Native.UGreenLED/app/server"
I2C_SYSFS_ROOT="$TMP/i2c"
LED_SYSFS_ROOT="$TMP/leds"
mkdir -p "$VAR_DIR" "$I2C_SYSFS_ROOT" "$LED_SYSFS_ROOT"
source "$SERVER_DIR/lib/driver_manager.sh"

driver_write_managed_marker 4 true
assert_eq "$(driver_managed_bus)" "4"
grep -q '^device_created=true$' "$(driver_managed_marker)" || fail "managed marker missing creation state"

lsmod() { echo 'leds_mcu_n76e003 16384 0'; }
driver_vendor_conflict || fail "known vendor LED module was not detected"

CALLS="$TMP/calls"
: > "$CALLS"
id() { [[ "${1:-}" == "-u" ]] && echo 0; }
driver_find_led_i2c_bus() { echo 4; }
driver_module_loaded() { return 0; }
driver_release_i2c_bus() { echo "release:$1" >> "$CALLS"; return 0; }
modprobe() { echo "modprobe:$*" >> "$CALLS"; return 0; }

driver_unload
assert_eq "$(sed -n '1p' "$CALLS")" "release:4"
assert_eq "$(sed -n '2p' "$CALLS")" "modprobe:-r led-ugreen"

: > "$CALLS"
driver_release_i2c_bus() { echo "release:$1" >> "$CALLS"; return 1; }
set +e
driver_unload
rc=$?
set -e
assert_eq "$rc" "22"
[[ "$(wc -l < "$CALLS" | tr -d ' ')" == "1" ]] || fail "module unload ran after I2C release failure"

: > "$CALLS"
driver_release_i2c_bus() { echo "release:$1" >> "$CALLS"; return 0; }
modprobe() { echo "modprobe:$*" >> "$CALLS"; return 1; }
driver_probe() { echo "probe" >> "$CALLS"; return 0; }
set +e
driver_unload
rc=$?
set -e
assert_eq "$rc" "20"
grep -q '^probe$' "$CALLS" || fail "failed unload did not attempt to restore the driver"

driver_find_led_i2c_bus() { return 1; }
driver_module_loaded() { return 1; }
driver_unload

echo "driver manager tests passed"
