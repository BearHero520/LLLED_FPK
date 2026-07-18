#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/App.Native.UGreenLED/app/server/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_has_line() { grep -Fxq "$2" <<< "$1" || fail "missing line [$2] in [$1]"; }

SETTINGS_FILE="$TMP/settings.conf"
source "$LIB/settings.sh"
settings_init "$SETTINGS_FILE"
source "$LIB/hardware_profile.sh"

HWMON_SOURCE="$ROOT/App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware/fan/it8613_hwmon.c"
FAN_480T_SOURCE="$ROOT/App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware/fan/it8613_dxp480t.c"
LOADER_SOURCE="$ROOT/App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware/core/loader.c"
grep -Fq 'IT8613_HWMON_NAME "it8613"' "$HWMON_SOURCE" || fail "fan control must discover name=it8613 dynamically"
grep -Fq 'flock(device->lock_fd, LOCK_EX)' "$HWMON_SOURCE" || fail "fan control must hold a process lock"
grep -Fq 'write_and_verify' "$HWMON_SOURCE" || fail "fan writes must be read back"
grep -Fq 'IT8613_MIN_MANUAL_PWM 40U' "$HWMON_SOURCE" || fail "fan PWM floor must remain 40"
grep -Fq 'ugreenctl_plugin_v4' "$LOADER_SOURCE" || fail "ugreenctl loader must prefer ABI v4 plugins"
grep -Fq '"it87_loaded"' "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" || fail "hardware status must report it87"
grep -Fq '"led_plugin_conflict"' "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" || fail "hardware status must report LED plugin conflicts"
grep -Fq '检测到 it87' "$ROOT/App.Native.UGreenLED/app/www/js/app.js" || fail "page must explain it87 compatibility"
cpu_line=$(grep -nF '{"cpu", 2, 3}' "$FAN_480T_SOURCE" | tail -n 1 | cut -d: -f1)
sys2_line=$(grep -nF '{"sys2", 4, 4}' "$FAN_480T_SOURCE" | tail -n 1 | cut -d: -f1)
sys1_line=$(grep -nF '{"sys1", 3, 2}' "$FAN_480T_SOURCE" | tail -n 1 | cut -d: -f1)
(( cpu_line < sys2_line && sys2_line < sys1_line )) || fail "DXP480T writes must be CPU, system 2, system 1"

UGREEN_PRODUCT_NAME="UGREEN DXP6800 Pro"
assert_eq "$(hardware_profile_key)" "dxp6800"
assert_eq "$(hardware_disk_count)" "6"
UGREEN_PRODUCT_NAME="DXP4800S"
assert_eq "$(hardware_profile_key)" "dxp4800s"
assert_eq "$(hardware_profile_display_name)" "UGREEN DXP4800S"
assert_eq "$(hardware_support_level)" "experimental"
assert_eq "$(hardware_disk_count)" "4"
settings_set "$SETTINGS_FILE" hardware profile dxp480t_plus
assert_eq "$(hardware_support_level)" "limited"
hardware_driver_supported && fail "DXP480T must not use the legacy LED driver"
settings_set "$SETTINGS_FILE" hardware profile idx6011_pro
assert_eq "$(hardware_netdev_count)" "2"
assert_eq "$(hardware_cli_led_name netdev2)" "disk1"
assert_eq "$(hardware_cli_led_name disk1)" "disk2"

CLI_LOG="$TMP/cli.log"
MOCK_CLI="$TMP/ugreen_leds_cli"
cat > "$MOCK_CLI" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CLI_LOG"
case "$*" in
  *"-status"*) echo "status = on, brightness = 64, color = RGB(1, 2, 3)" ;;
esac
EOF
chmod +x "$MOCK_CLI"
export UGREEN_CLI="$MOCK_CLI" CLI_LOG
LED_API_CACHE_DIR="$TMP/cache"
mkdir -p "$LED_API_CACHE_DIR"
source "$LIB/led_api.sh"
source "$LIB/led_apply.sh"
settings_set "$SETTINGS_FILE" hardware backend cli
led_backend_reset
assert_eq "$(led_backend_name)" "cli"
led_set_color disk1 10 20 30 70
led_set_off disk1
grep -q -- 'disk2.*-color' "$CLI_LOG" || fail "LED color did not go through bundled CLI"
grep -q -- 'disk2.*-off' "$CLI_LOG" || fail "LED off did not go through bundled CLI"
if grep -Eq 'i2c(get|set)|/sys/class/leds|power-0x26' "$LIB/led_api.sh"; then
  fail "application LED API contains a direct hardware path"
fi

settings_set "$SETTINGS_FILE" hardware profile dxp6800
source "$LIB/disk_map.sh"
led_list_disk_slots() { printf '%s\n' disk1 disk2 disk3 disk4 disk5 disk6; }
disk_inventory_rows() {
  printf '%s\n' \
    '/dev/sda|5:0:0:0|SER6|MODEL|8T|sata' \
    '/dev/sdf|0:0:0:0|SER5|MODEL|8T|sata' \
    '/dev/sdc|3:0:0:0|SER2|MODEL|8T|sata' \
    '/dev/sdb|2:0:0:0|SER1|MODEL|8T|sata' \
    '/dev/sde|1:0:0:0|SER6B|MODEL|8T|sata' \
    '/dev/sdd|4:0:0:0|SER3|MODEL|8T|sata'
}
mapping=$(disk_build_mapping)
assert_has_line "$mapping" '/dev/sdf|0:0:0:0|disk5|SER5'
assert_has_line "$mapping" '/dev/sdb|2:0:0:0|disk1|SER1'
disk_load_mapping_from_settings "$SETTINGS_FILE"
assert_eq "${DISK_LED_MAP[/dev/sdf]}" "disk5"
snapshot=$(disk_snapshot_devices)
assert_has_line "$snapshot" '/dev/sdf|0:0:0:0|SER5|MODEL|8T|sata'

echo "hardware and mapping tests passed"
