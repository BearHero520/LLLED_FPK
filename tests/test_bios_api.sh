#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
API="$ROOT/App.Native.UGreenLED/app/ui/api.cgi"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "missing [$2] in [$1]"; }

BIN="$TMP/ugreenctl"; PLUGINS="$TMP/models"; CALLS="$TMP/calls"
mkdir -p "$PLUGINS"
: > "$PLUGINS/dxp4800plus.so"
: > "$PLUGINS/dxp4800s.so"
: > "$PLUGINS/dxp480tplus.so"
: > "$PLUGINS/dxp6800pro.so"
cat > "$BIN" <<'EOF'
#!/bin/sh
printf 'CALL' >> "$UGREENCTL_CALLS"
for arg in "$@"; do printf ' <%s>' "$arg" >> "$UGREENCTL_CALLS"; done
printf '\n' >> "$UGREENCTL_CALLS"
case " $* " in
  *" info "*)
    if [ "$UGREEN_PRODUCT_NAME" = 'DXP6800 Pro' ]; then
      echo 'model: dxp6800pro (DXP6800 Pro (firmware-reversed))'
    else
      echo 'model: dxp4800s (UGREEN DXP4800S)'
    fi
    ;;
  *" fan status "*)
    if [ "$UGREEN_PRODUCT_NAME" = 'DXP6800 Pro' ]; then
      printf '%s\n' \
        'fan cpu: pwm=120 mode=manual tach=675 rpm=1000' \
        'fan sys1: pwm=88 mode=manual tach=750 rpm=900' \
        'fan sys2: pwm=88 mode=manual tach=450 rpm=1500'
    else
      echo 'fan sys: pwm=40 mode=manual tach=750 rpm=900'
    fi
    ;;
  *" power startup get "*) echo 'restore' ;;
esac
EOF
chmod +x "$BIN"

export TRIM_APPDEST="$ROOT/App.Native.UGreenLED/app" TRIM_PKGVAR="$TMP/var"
export UGREEN_PRODUCT_NAME="DXP4800S" BIOS_UGREENCTL="$BIN" BIOS_UGREENCTL_PLUGIN_DIR="$PLUGINS" UGREENCTL_CALLS="$CALLS"
request() {
  local path="$1" query="${2:-}" method="${3:-GET}"
  PATH_INFO="$path" QUERY_STRING="$query" REQUEST_METHOD="$method" CONTENT_LENGTH=0 bash "$API" | tail -n 1
}

json=$(request /bios/status)
assert_contains "$json" '"available":true'
assert_contains "$json" '"min_pwm":40'
assert_contains "$json" '"sys_rpm":900'
assert_contains "$json" '"fan_mode_writable":false'

: > "$CALLS"
json=$(request /bios/fan 'channel=sys&pwm=39&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":false'
[[ ! -s "$CALLS" ]] || fail "PWM below 40 reached ugreenctl"

json=$(request /bios/fan 'channel=sys&pwm=40&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":true'
grep -Fq ' <--force> <--apply> <fan> <set> <sys> <40>' "$CALLS" || fail "fan write did not use --force --apply"

: > "$CALLS"
json=$(request /bios/fan/mode 'channel=sys&mode=auto&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":false'
assert_contains "$json" '暂时只开放手动 PWM'
[[ ! -s "$CALLS" ]] || fail "fan mode write reached ugreenctl"

export UGREEN_PRODUCT_NAME="DXP6800 Pro"
json=$(request /bios/status)
assert_contains "$json" '"model":"dxp6800pro"'
assert_contains "$json" '"cpu_rpm":1000'
assert_contains "$json" '"sys_rpm":900'
assert_contains "$json" '"sys2_rpm":1500'
assert_contains "$json" '"write_confirmation_required":true'

: > "$CALLS"
json=$(request /bios/fan 'channel=sys&pwm=120' POST)
assert_contains "$json" '"ok":false'
assert_contains "$json" '固件逆向风扇写入需要先确认风险'
[[ ! -s "$CALLS" ]] || fail "unconfirmed DXP6800 Pro PWM reached ugreenctl"

json=$(request /bios/fan 'channel=sys&pwm=120&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":true'
grep -Fq ' <--force> <--apply> <fan> <set> <sys> <120>' "$CALLS" || fail "DXP6800 Pro paired fan write did not use --force --apply"

: > "$CALLS"
json=$(request /bios/fan 'channel=sys1&pwm=120&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":false'
[[ ! -s "$CALLS" ]] || fail "DXP6800 Pro individual system fan write reached ugreenctl"

json=$(request /bios/startup 'policy=last&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":true'
grep -Fq ' <--force> <--apply> <power> <startup> <set> <restore>' "$CALLS" || fail "DXP6800 Pro startup write did not use --force --apply"

echo "BIOS API tests passed"
