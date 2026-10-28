#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVER_DIR="$ROOT/App.Native.UGreenLED/app/server"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
source "$SERVER_DIR/lib/bios_control.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
hardware_detected_product_name() { printf '%s' "$PRODUCT"; }
json_str() { printf '%s' "$1"; }
settings_get() { if [[ "$3" == wol_interface_selection ]]; then cat "$TMP/selection" 2>/dev/null || true; else printf '%s' "$4"; fi; }
settings_set() { printf '%s' "$4" > "$TMP/selection"; }
settings_apply_updates() { cat > "$TMP/settings"; }
SETTINGS_FILE="$TMP/settings"
BIOS_SCHEDULE_CRON_FILE="$TMP/power.cron"
FAIL_WOL_MODELS=false
bios_wake_cli() {
    printf '%s\n' "$*" >> "$TMP/calls"
    case "$*" in
        'network wol models'|'power rtc-wake models')
            if [[ "$*" == 'network wol models' ]] && "$FAIL_WOL_MODELS"; then return 1; fi
            for product in 'DX4600' 'DX4600+' 'DX4600 Pro' 'DXP4800' 'DXP4800S' 'DXP4800 Plus' 'DXP4800 Pro' 'DXP480T Plus' 'DXP6800 Pro' 'DXP6800 Plus' 'DXP8800 Plus'; do
                printf 'mock\t%s\twol=automatic-or-explicit\n' "$product"
            done ;;
        'network wol get') echo 'explicit interface required' >&2; return 1 ;;
        'network wol get --interface enp3s0'|'network wol get --interface eno2') echo on ;;
        'power rtc-wake get') echo 0 ;;
        '--force --apply network wol set off --interface eno2') echo 'readback mismatch' >&2; return 1 ;;
    esac
}
for PRODUCT in 'DX4600' 'DX4600+' 'DX4600 Pro' 'DXP4800' 'DXP4800S' 'DXP4800 Plus' 'DXP4800 Pro' 'DXP480T Plus' 'DXP6800 Pro' 'DXP6800 Plus'; do
    bios_supported_model || fail "$PRODUCT fan unavailable"
    bios_wol_supported_model || fail "$PRODUCT WOL unavailable"
    curve=$(bios_fan_curve_stock_json)
    [[ "$curve" == *'"available":true'* ]] || fail "$PRODUCT curve unavailable"
done
PRODUCT='DXP8800 Plus'
! bios_supported_model || fail 'wake-only model acquired fan access'
bios_wol_supported_model || fail 'wake-only model unavailable'
bios_read_power_schedule "$SETTINGS_FILE"
[[ "$BIOS_POWER_SCHEDULE_AVAILABLE" == true ]] || fail 'RTC coupled to WOL read failure'
bios_power_schedule_set "$SETTINGS_FILE" false '' '' ''
grep -Fxq -- '--force --apply power rtc-wake clear' "$TMP/calls" || fail 'RTC clear not routed upstream'
for interface in enp3s0 eno2; do
    result=$(bios_wol_query_json "$interface")
    [[ "$result" == *'"available":true'* ]] || fail 'renamed NIC get failed'
done
bios_set_wol_saved on enp3s0 || fail 'explicit NIC write failed'
[[ "$(bios_selected_wol_interface)" == enp3s0 ]] || fail 'NIC not persisted'
grep -Fxq -- '--force --apply network wol set on --interface enp3s0' "$TMP/calls" || fail 'NIC not passed to backend'
! bios_set_wol_saved off eno2 || fail 'readback error hidden'
[[ "$(bios_selected_wol_interface)" == enp3s0 ]] || fail 'failed write persisted NIC'
! bios_set_wol_saved on '../eth0' || fail 'invalid NIC accepted'
PRODUCT='DXP4800'
[[ -z "$(bios_selected_wol_interface)" ]] || fail 'NIC leaked across models'
BIOS_WAKE_CACHE_KEY=''; FAIL_WOL_MODELS=true
bios_rtc_supported_model || fail 'RTC coupled to WOL profile command'
[[ "$BIOS_WOL_SUPPORTED" == false ]] || fail 'failed WOL profiles retained'
PRODUCT='DXP6800 Plus Engineering'
! bios_rtc_supported_model || fail 'unknown exact identity accepted'
echo 'Wake independence, explicit NIC, persistence, failure and curve tests passed'
