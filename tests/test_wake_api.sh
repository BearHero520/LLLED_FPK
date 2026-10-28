#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
API="$ROOT/App.Native.UGreenLED/app/ui/api.cgi"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "missing [$2] in [$1]"; }
assert_json() { python -c 'import json, sys; json.load(sys.stdin)' <<< "$1" || fail "invalid JSON response"; }

BIN="$TMP/ugreenctl"; PLUGINS="$TMP/models"; CALLS="$TMP/calls"
mkdir -p "$PLUGINS"
: > "$PLUGINS/dx4600.so"
: > "$PLUGINS/dxp4800.so"
: > "$PLUGINS/dxp4800plus.so"
: > "$PLUGINS/dxp4800s.so"
: > "$PLUGINS/dxp480tplus.so"
: > "$PLUGINS/dxp6800pro.so"
: > "$PLUGINS/dxp6800plus.so"
cat > "$BIN" <<'EOF'
#!/bin/sh
printf 'CALL' >> "$UGREENCTL_CALLS"
for arg in "$@"; do printf ' <%s>' "$arg" >> "$UGREENCTL_CALLS"; done
printf '\n' >> "$UGREENCTL_CALLS"
case " $* " in
  *" network wol models "*|*" power rtc-wake models "*)
    for product in 'DX4600' 'DXP4800' 'DXP4800S' 'DXP4800 Plus' 'DXP4800 Pro' 'DXP480T Plus' 'DXP6800 Pro' 'DXP6800 Plus' 'DXP8800 Plus'; do
      printf 'mock\t%s\twol=automatic-or-explicit\n' "$product"
    done ;;
  *" info "*)
    if [ "$UGREEN_PRODUCT_NAME" = 'DX4600' ]; then
      echo 'model: dx4600 (UGREEN DX4600 / DX4600+ / DX4600 Pro (firmware-reversed))'
    elif [ "$UGREEN_PRODUCT_NAME" = 'DXP6800 Pro' ]; then
      echo 'model: dxp6800pro (DXP6800 Pro (firmware-reversed))'
    elif [ "$UGREEN_PRODUCT_NAME" = 'DXP4800' ]; then
      echo 'model: dxp4800 (UGREEN DXP4800 (firmware-reversed))'
    else
      echo 'model: dxp4800s (UGREEN DXP4800S)'
    fi
    ;;
  *" fan status "*)
    if [ "$UGREEN_PRODUCT_NAME" = 'DX4600' ]; then
      echo 'fan sys: pwm=64 mode=manual tach=750 rpm=900'
    elif [ "$UGREEN_PRODUCT_NAME" = 'DXP6800 Pro' ]; then
      printf '%s\n' \
        'fan cpu: pwm=120 mode=manual tach=675 rpm=1000' \
        'fan sys1: pwm=88 mode=manual tach=750 rpm=900' \
        'fan sys2: pwm=88 mode=manual tach=450 rpm=1500'
    elif [ "$UGREEN_PRODUCT_NAME" = 'DXP4800' ]; then
      echo 'fan sys: pwm=128 mode=manual tach=750 rpm=900'
    else
      echo 'fan sys: pwm=40 mode=manual tach=750 rpm=900'
    fi
    ;;
  *" power startup get "*)
    if [ "${TEST_STARTUP_FAIL:-0}" = 1 ]; then
      echo 'error: controller owner is active' >&2
      exit 1
    fi
    if [ -n "${TEST_STARTUP_STATE:-}" ]; then cat "$TEST_STARTUP_STATE"; else echo restore; fi
    ;;
  *" power startup set "*)
    if [ "${TEST_STARTUP_FAIL:-0}" = 1 ]; then
      echo 'error: simulated readback failure' >&2
      exit 1
    fi
    if [ -n "${TEST_STARTUP_STATE:-}" ]; then
      for policy in "$@"; do :; done
      echo "$policy" > "$TEST_STARTUP_STATE"
    fi
    ;;
  *" network wol get "*) echo 'on' ;;
  *" power rtc-wake get "*) echo '0' ;;
  *" power rtc-wake set "*) : ;;
  *" power rtc-wake clear "*) : ;;
esac
EOF
chmod +x "$BIN"

export TRIM_APPDEST="$ROOT/App.Native.UGreenLED/app" TRIM_PKGVAR="$TMP/var"
export UGREEN_PRODUCT_NAME="DXP4800S" BIOS_UGREENCTL="$BIN" BIOS_UGREENCTL_PLUGIN_DIR="$PLUGINS" UGREENCTL_CALLS="$CALLS" BIOS_SCHEDULE_CRON_FILE="$TMP/cron.d/power"
request() {
  local path="$1" query="${2:-}" method="${3:-GET}"
  PATH_INFO="$path" QUERY_STRING="$query" REQUEST_METHOD="$method" CONTENT_LENGTH=0 bash "$API" | tail -n 1
}

export UGREEN_PRODUCT_NAME='DXP8800 Plus'
json=$(request /bios/wol 'interface=enp3s0')
assert_json "$json"
assert_contains "$json" '"available":true'
assert_contains "$json" '"interface":"enp3s0"'
grep -Fq 'CALL <network> <wol> <get> <--interface> <enp3s0>' "$CALLS" || fail 'GET did not pass exact interface without plugins'
json=$(request /bios/wol 'policy=on&interface=eno2&confirm=firmware-reversed' POST)
assert_json "$json"
assert_contains "$json" '"ok":true'
assert_contains "$json" '"wol_interface":"eno2"'
assert_contains "$json" '"rtc_supported":true'
assert_contains "$json" '"available":false'
grep -Fq 'CALL <--force> <--apply> <network> <wol> <set> <on> <--interface> <eno2>' "$CALLS" || fail 'POST did not pass NIC'
grep -Fq 'wol_interface_selection=DXP8800 Plus|eno2' "$TMP/var/settings.conf" || fail 'NIC not saved'
: > "$CALLS"
json=$(request /bios/wol 'policy=on&interface=..%2Feth0&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":false'
! grep -Fq '<--apply>' "$CALLS" || fail 'invalid NIC reached hardware write'
echo 'Wake-only model API and explicit NIC roundtrip tests passed'
