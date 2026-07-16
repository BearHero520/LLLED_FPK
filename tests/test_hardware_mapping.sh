#!/bin/bash
set -eo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/App.Native.UGreenLED/app/server/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_has_line() { grep -Fxq "$2" <<< "$1" || fail "missing line [$2] in [$1]"; }

SERVER_DIR="$ROOT/App.Native.UGreenLED/app/server"
SETTINGS_FILE="$TMP/settings.conf"
TARGET="$ROOT/App.Native.UGreenLED/app"
source "$LIB/settings.sh"
settings_init "$SETTINGS_FILE"
source "$LIB/hardware_profile.sh"

FAN_SOURCE="$ROOT/App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware/fan/it8613_fan.c"
FAN_480T_SOURCE="$ROOT/App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware/fan/it8613_dxp480t.c"
LOADER_SOURCE="$ROOT/App.Native.UGreenLED/app/server/vendor/UGREEN-NAS-Hardware/core/loader.c"
grep -Fq 'control | 0x80' "$FAN_SOURCE" || fail "DXP4800 automatic fan mode must restore control bit 7"
grep -Fq 'control | 0x80' "$FAN_480T_SOURCE" || fail "DXP480T automatic fan mode must restore control bit 7"
grep -Fq 'ugreenctl_plugin_v3' "$LOADER_SOURCE" || fail "ugreenctl loader must prefer ABI v3 plugins"
auto_cpu_line=$(grep -nF 'set_automatic_mode(0x16);' "$FAN_480T_SOURCE" | head -n 1 | cut -d: -f1)
auto_sys2_line=$(grep -nF 'set_automatic_mode(0x1e);' "$FAN_480T_SOURCE" | head -n 1 | cut -d: -f1)
auto_sys1_line=$(grep -nF 'set_automatic_mode(0x17);' "$FAN_480T_SOURCE" | head -n 1 | cut -d: -f1)
(( auto_cpu_line < auto_sys2_line && auto_sys2_line < auto_sys1_line )) || fail "DXP480T automatic mode order must be CPU, system 2, system 1"

UGREEN_PRODUCT_NAME="UGREEN DXP6800 Pro"
assert_eq "$(hardware_profile_key)" "dxp6800"
assert_eq "$(hardware_hctl_profile)" "dxp6800"
assert_eq "$(hardware_disk_count)" "6"

settings_set "$SETTINGS_FILE" hardware profile dxp8800
assert_eq "$(hardware_disk_count)" "8"
assert_eq "$(hardware_support_level)" "stable"
settings_set "$SETTINGS_FILE" hardware profile dxp4800_gt
assert_eq "$(hardware_write_protocol)" "smbus-block"
assert_eq "$(hardware_support_level)" "experimental"
settings_set "$SETTINGS_FILE" hardware write_protocol legacy
assert_eq "$(hardware_write_protocol)" "legacy"
settings_set "$SETTINGS_FILE" hardware write_protocol auto
settings_set "$SETTINGS_FILE" hardware profile dxp480t_plus
assert_eq "$(hardware_disk_count)" "0"
assert_eq "$(hardware_netdev_count)" "0"
assert_eq "$(hardware_support_level)" "limited"
hardware_driver_supported && fail "DXP480T must not use the 0x3a DKMS driver"

settings_set "$SETTINGS_FILE" hardware profile idx6011_pro
assert_eq "$(hardware_profile_key)" "idx6011_pro"
assert_eq "$(hardware_write_protocol)" "smbus-block"
assert_eq "$(hardware_netdev_count)" "2"
assert_eq "$(hardware_cli_led_name netdev2)" "disk1"
assert_eq "$(hardware_cli_led_name disk1)" "disk2"
assert_eq "$(hardware_cli_led_name disk6)" "disk7"

MOCK_CLI="$TMP/ugreen_leds_cli"
cat > "$MOCK_CLI" <<'EOF'
#!/bin/bash
if [[ "$2" == "-status" ]]; then
    echo "$1: status = on, brightness = 64, color = RGB(1, 2, 3)"
else
    exit 0
fi
EOF
chmod +x "$MOCK_CLI"
UGREEN_CLI="$MOCK_CLI"
LED_SYSFS_ROOT="$TMP/sysfs"
LED_API_CACHE_DIR="$TMP/cache"
mkdir -p "$LED_API_CACHE_DIR"
source "$LIB/led_api.sh"
source "$LIB/led_apply.sh"

settings_set "$SETTINGS_FILE" hardware backend cli
led_backend_reset
assert_eq "$(led_backend_name)" "cli"
assert_eq "$(led_list_disk_slots | paste -sd, -)" "disk1,disk2,disk3,disk4,disk5,disk6"
assert_eq "$(led_list_network_slots | paste -sd, -)" "netdev,netdev2"
assert_eq "$(led_backend_status_raw disk1 | cut -d: -f1)" "disk2"

mkdir -p "$LED_SYSFS_ROOT/power"
: > "$LED_SYSFS_ROOT/power/color"
: > "$LED_SYSFS_ROOT/power/brightness"
chmod +w "$LED_SYSFS_ROOT/power/color" "$LED_SYSFS_ROOT/power/brightness"
settings_set "$SETTINGS_FILE" hardware backend auto
led_backend_reset
assert_eq "$(led_backend_name)" "sysfs"

mkdir -p "$LED_SYSFS_ROOT/disk1"
printf 'off 0 0 0 0 0 0\n' > "$LED_SYSFS_ROOT/disk1/status"
: > "$LED_SYSFS_ROOT/disk1/color"
: > "$LED_SYSFS_ROOT/disk1/brightness"
: > "$LED_SYSFS_ROOT/disk1/blink_type"
led_set_color disk1 10 20 30 70
assert_eq "$(tr -d '\r\n' < "$LED_SYSFS_ROOT/disk1/color")" "10 20 30"
assert_eq "$(tr -d '\r\n' < "$LED_SYSFS_ROOT/disk1/brightness")" "70"
led_set_blink disk1 10 20 30 600 200 70
assert_eq "$(tr -d '\r\n' < "$LED_SYSFS_ROOT/disk1/blink_type")" "blink 200 400"
led_set_off disk1
assert_eq "$(tr -d '\r\n' < "$LED_SYSFS_ROOT/disk1/brightness")" "0"

MOCK_BIN="$TMP/mock-bin"
POWER26_LOG="$TMP/power26.log"
LED_I2C_DEV_ROOT="$TMP/i2c-dev"
mkdir -p "$MOCK_BIN" "$LED_I2C_DEV_ROOT"
touch "$LED_I2C_DEV_ROOT/i2c-2"
cat > "$MOCK_BIN/i2cget" <<'EOF'
#!/bin/bash
[[ "$2" == "2" && "$3" == "0x31" ]] || exit 1
case "$4" in
  0x5a) echo 0xa5 ;;
  0x5b) echo 0xb5 ;;
  0x5d) echo 0x01 ;;
  *) exit 1 ;;
esac
EOF
cat > "$MOCK_BIN/i2cset" <<EOF
#!/bin/bash
echo "\$*" >> "$POWER26_LOG"
[[ "\${I2CSET_FAIL:-}" == "1" ]] && { echo "Device or resource busy" >&2; exit 1; }
exit 0
EOF
chmod +x "$MOCK_BIN/i2cget" "$MOCK_BIN/i2cset"
PATH="$MOCK_BIN:$PATH"
export PATH LED_I2C_DEV_ROOT

settings_set "$SETTINGS_FILE" hardware profile dxp480t_plus
settings_set "$SETTINGS_FILE" hardware backend auto
led_backend_reset
led_backend_select >/dev/null
assert_eq "$LED_BACKEND_ACTIVE" "power-0x26"
assert_eq "$LED_POWER26_BUS" "2"
assert_eq "$LED_POWER26_ADDRESS" "0x31"
assert_eq "$(led_list_network_slots | paste -sd, -)" ""
assert_eq "$(led_list_disk_slots | paste -sd, -)" ""
led_set_color power 255 0 0 40
grep -q -- '-y 2 0x31 0xb1 1 b' "$POWER26_LOG" || fail "DXP480T red power LED selector missing"
grep -q -- '-y 2 0x31 0xa0 2 b' "$POWER26_LOG" || fail "DXP480T red power LED mask missing"
led_set_blink power 100 100 100 1500 500 40
grep -q -- '-y 2 0x31 0xb1 2 b' "$POWER26_LOG" || fail "DXP480T white power LED selector missing"
grep -q -- '-y 2 0x31 0xa0 1 b' "$POWER26_LOG" || fail "DXP480T white power LED mask missing"
grep -q -- '-y 2 0x31 0x50 1 b' "$POWER26_LOG" || fail "DXP480T white timer mode missing"
grep -q -- '-y 2 0x31 0xc0 132 b' "$POWER26_LOG" || fail "DXP480T slow timer low byte missing"
grep -q -- '-y 2 0x31 0xc1 3 b' "$POWER26_LOG" || fail "DXP480T slow timer high byte missing"
led_set_off power
tail -n 1 "$POWER26_LOG" | grep -q -- '-y 2 0x31 0xb1 3 b' || fail "DXP480T power-off command missing"
led_clear_cache
led_set_power26_effect red fast
grep -q -- '-y 2 0x31 0xb1 1 b' "$POWER26_LOG" || fail "DXP480T dedicated red selection missing"
grep -q -- '-y 2 0x31 0x51 1 b' "$POWER26_LOG" || fail "DXP480T dedicated red timer mode missing"
grep -q -- '-y 2 0x31 0xc2 24 b' "$POWER26_LOG" || fail "DXP480T dedicated fast timer missing"
led_set_power26_effect white breath
grep -q -- '-y 2 0x31 0xb1 2 b' "$POWER26_LOG" || fail "DXP480T dedicated white selection missing"
grep -q -- '-y 2 0x31 0x50 2 b' "$POWER26_LOG" || fail "DXP480T dedicated breath effect missing"
led_set_power26_effect white off
tail -n 1 "$POWER26_LOG" | grep -q -- '-y 2 0x31 0xb1 3 b' || fail "DXP480T dedicated off effect missing"
led_clear_cache
I2CSET_FAIL=1
export I2CSET_FAIL
! led_set_power26_effect white steady || fail "DXP480T write failure must propagate"
[[ "$LED_LAST_ERROR" == *"i2c-2 0x31"* && "$LED_LAST_ERROR" == *"Device or resource busy"* ]] || fail "DXP480T write diagnostics missing"
unset I2CSET_FAIL
assert_eq "$(power26_network_effect 31 32)" "steady"
assert_eq "$(power26_network_effect 32 32)" "slow"
assert_eq "$(power26_network_effect 127 32)" "slow"
assert_eq "$(power26_network_effect 128 32)" "fast"
settings_set "$SETTINGS_FILE" power26 color red
settings_set "$SETTINGS_FILE" power26 network_threshold_kbps 32
apply_power26_network_activity "$SETTINGS_FILE" 32
grep -q -- '-y 2 0x31 0x51 1 b' "$POWER26_LOG" || fail "DXP480T network slow effect missing"
grep -q -- '-y 2 0x31 0xc2 132 b' "$POWER26_LOG" || fail "DXP480T network slow timer missing"
apply_power26_network_activity "$SETTINGS_FILE" 128
grep -q -- '-y 2 0x31 0xc2 24 b' "$POWER26_LOG" || fail "DXP480T network fast timer missing"

settings_set "$SETTINGS_FILE" hardware profile dxp6800
settings_set "$SETTINGS_FILE" hardware backend cli
led_backend_reset
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
assert_has_line "$mapping" '/dev/sde|1:0:0:0|disk6|SER6B'
assert_has_line "$mapping" '/dev/sdb|2:0:0:0|disk1|SER1'
assert_has_line "$mapping" '/dev/sdc|3:0:0:0|disk2|SER2'
assert_has_line "$mapping" '/dev/sdd|4:0:0:0|disk3|SER3'
assert_has_line "$mapping" '/dev/sda|5:0:0:0|disk4|SER6'

disk_load_mapping_from_settings "$SETTINGS_FILE"
assert_eq "${DISK_LED_MAP[/dev/sdf]}" "disk5"
assert_eq "${DISK_LED_MAP[/dev/sdb]}" "disk1"

snapshot=$(disk_snapshot_devices)
assert_has_line "$snapshot" '/dev/sdf|0:0:0:0|SER5|MODEL|8T|sata'

driver_module_loaded() { return 1; }
driver_vendor_conflict() { return 0; }
led_driver_loaded || fail "vendor driver conflict must block CLI access"

led_driver_loaded() { return 0; }
led_sysfs_available() { return 1; }
settings_set "$SETTINGS_FILE" hardware backend cli
led_backend_reset
set +e
led_backend_select >/dev/null
rc=$?
set -e
assert_eq "$rc" "2"

echo "hardware and mapping tests passed"
