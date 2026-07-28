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

BIOS_CONTROL="$LIB/bios_control.sh"
grep -Fq 'server/bin/ugreenctl' "$BIOS_CONTROL" || fail "BIOS operations must use the bundled ugreenctl adapter"
grep -Fq 'DXP480T Plus' "$BIOS_CONTROL" || fail "BIOS adapter must retain the exact DXP480T Plus guard"
grep -Fq '"DXP4800"' "$BIOS_CONTROL" || fail "BIOS adapter must retain the exact DXP4800 guard"
grep -Fq '"DXP6800 PRO"' "$BIOS_CONTROL" || fail "BIOS adapter must retain the exact DXP6800 Pro guard"
grep -Fq 'dxp4800.so' "$BIOS_CONTROL" || fail "BIOS adapter must require the DXP4800 upstream plugin"
grep -Fq 'dxp6800pro.so' "$BIOS_CONTROL" || fail "BIOS adapter must require the DXP6800 Pro upstream plugin"
grep -Fq 'direct-superio' "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" || fail "direct fan fallback must require explicit confirmation"
grep -Fq '"it87_loaded"' "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" || fail "hardware status must report it87"
grep -Fq '"led_plugin_conflict"' "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" || fail "hardware status must report LED plugin conflicts"
grep -Fq '检测到 it87' "$ROOT/App.Native.UGreenLED/app/www/js/app.js" || fail "page must explain it87 compatibility"
grep -Fq '系统风扇 1/2 会同步写入' "$ROOT/App.Native.UGreenLED/app/www/js/app.js" || fail "page must explain the DXP480T Plus shared direct PWM path"

json_str() { printf '%s' "$1"; }
SERVER_DIR="$ROOT/App.Native.UGreenLED/app/server"
source "$BIOS_CONTROL"
UGREEN_PRODUCT_NAME="DXP6800 Pro"
stock_curve=$(bios_fan_curve_stock_json)
grep -Fq '"profile":"stock-6800pro"' <<< "$stock_curve" || fail "stock fan curve must come from the bundled hardware record"
grep -Fq '"system_pwm":"64,130,210,230"' <<< "$stock_curve" || fail "stock fan curve must preserve the recovered system PWM points"

source "$LIB/fan_telemetry.sh"
grep -Fq '1m) seconds=60; bucket_seconds=10 ;;' "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" || fail "one-minute telemetry must use ten-second buckets"
grep -Fq 'FAN_TELEMETRY_INTERVAL_SECONDS:-10' "$ROOT/App.Native.UGreenLED/app/server/fan_telemetry_daemon.sh" || fail "telemetry sampler must capture every ten seconds by default"
VAR_DIR="$TMP/telemetry"
mkdir -p "$VAR_DIR"
telemetry_now=$(date +%s)
telemetry_anchor=$(( (telemetry_now / 1800) * 1800 ))
telemetry_earlier=$(( telemetry_anchor - 3500 ))
telemetry_latest=$(( telemetry_anchor - 3490 ))
telemetry_next=$(( telemetry_anchor - 1700 ))
printf '%s\n' \
  "${telemetry_earlier}|dxp6800pro|40|35|42|1200|900|800" \
  "${telemetry_latest}|dxp6800pro|41|36|43|1210|910|810" \
  "${telemetry_next}|dxp6800pro|42|37|44|1220|920|820" > "$(fan_telemetry_history_path)"
bucketed_history=$(fan_telemetry_history_json 86400 dxp6800pro 1800)
bucketed_count=$(grep -o '"at":' <<< "$bucketed_history" | wc -l | tr -d ' ')
assert_eq "$bucketed_count" "2"
grep -Fq "\"at\":${telemetry_latest}" <<< "$bucketed_history" || fail "telemetry bucket must keep its latest sample"
latest_telemetry=$(fan_telemetry_latest_json dxp6800pro)
grep -Fq "\"at\":${telemetry_next}" <<< "$latest_telemetry" || fail "telemetry cache must return its latest model sample"
grep -Fq '"sys2Rpm":820' <<< "$latest_telemetry" || fail "telemetry cache must retain secondary fan RPM"

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
