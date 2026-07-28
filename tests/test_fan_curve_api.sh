#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_PROJECT="$ROOT/App.Native.UGreenLED"
[[ -d "$APP_PROJECT" ]] || APP_PROJECT="$ROOT"
API="$APP_PROJECT/app/ui/api.cgi"
TMP=$(mktemp -d)
trap '[[ -n "${FAND_PID:-}" ]] && kill "$FAND_PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "missing [$2] in [$1]"; }

BIN="$TMP/ugreenctl"; FAND="$TMP/ugreenctl-fand"; PLUGINS="$TMP/models"; CALLS="$TMP/calls"; IT87_MODULE="$TMP/it87"
mkdir -p "$PLUGINS" "$TMP/run" "$TMP/var"
cat > "$TMP/var/settings.conf" <<'EOF'
[logging]
level=off

[fan_curve]
enabled=false
EOF
for model in dx4600 dxp4800 dxp4800plus dxp4800s dxp480tplus dxp6800pro; do : > "$PLUGINS/$model.so"; done
cat > "$BIN" <<'EOF'
#!/bin/sh
printf 'CALL' >> "$UGREENCTL_CALLS"
for arg in "$@"; do printf ' <%s>' "$arg" >> "$UGREENCTL_CALLS"; done
printf '\n' >> "$UGREENCTL_CALLS"
case " $* " in
  *" fan status "*) echo 'fan sys: pwm=64 mode=manual tach=750 rpm=900' ;;
  *" power startup get "*) echo restore ;;
esac
EOF
cat > "$FAND" <<'EOF'
#!/bin/sh
state=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state) state="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat > "$state" <<STATE
timestamp=123
model=dxp4800s
profile=custom
status=running
cpu_celsius=52
hdd_celsius=40
ssd_celsius=45
desired_pwm=64
applied_pwm=64
detail=
STATE
sleep 30
EOF
chmod +x "$BIN" "$FAND"
: > "$IT87_MODULE"

export TRIM_APPDEST="$APP_PROJECT/app" TRIM_PKGVAR="$TMP/var" UGREEN_RUNTIME_DIR="$TMP/run"
export UGREEN_PRODUCT_NAME="DXP4800S" BIOS_UGREENCTL="$BIN" BIOS_UGREENCTL_FAND="$FAND" BIOS_UGREENCTL_PLUGIN_DIR="$PLUGINS" BIOS_TEST_IT87_MODULE_PATH="$IT87_MODULE" UGREENCTL_CALLS="$CALLS"
request() {
  local path="$1" query="${2:-}" method="${3:-GET}"
  PATH_INFO="$path" QUERY_STRING="$query" REQUEST_METHOD="$method" CONTENT_LENGTH=0 bash "$API" | tail -n 1
}

export UGREEN_PRODUCT_NAME="DX4600"
json=$(request /bios/fan-curve 'action=start&mode=stock-4600&confirm=firmware-reversed' POST)
FAND_PID=$(cat "$TMP/run/fan-curve.pid")
assert_contains "$json" '"ok":true'
assert_contains "$json" '"running":true'
CONFIG="$TMP/var/fan-curve.conf"
[[ "$(sed -n 's/^profile=//p' "$CONFIG")" == "stock-4600" ]] || fail "DX4600 stock profile was not persisted"
json=$(request /bios/fan-curve 'action=stop' POST)
assert_contains "$json" '"ok":true'

export UGREEN_PRODUCT_NAME="DXP4800S"
json=$(request /bios/fan-curve 'action=start&mode=stock-4800s&confirm=firmware-reversed' POST)
FAND_PID=$(cat "$TMP/run/fan-curve.pid")
assert_contains "$json" '"ok":true'
assert_contains "$json" '"running":true'
[[ "$(sed -n 's/^profile=//p' "$CONFIG")" == "stock-4800s" ]] || fail "stock profile was not persisted"
[[ "$(sed -n 's/^allow_unvalidated_writes=//p' "$CONFIG")" == "true" ]] || fail "guarded curve did not retain confirmation"
json=$(request /bios/fan-curve)
assert_contains "$json" '"cpu_celsius":52'
assert_contains "$json" '"applied_pwm":64'

json=$(request /bios/fan 'channel=sys&pwm=130&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":true'
assert_contains "$json" '"fan_curve":{"enabled":false,"running":false'
assert_contains "$json" '固定转速 PWM 130；自动温控已停止'
[[ "$(sed -n 's/^enabled=//p' "$TMP/var/settings.conf" | tail -n 1)" == "false" ]] || fail "stop did not disable curve restart"

export UGREEN_PRODUCT_NAME="DXP480T Plus"
json=$(request /bios/fan-curve 'action=start&mode=stock-480tplus&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":true'
[[ "$(sed -n 's/^profile=//p' "$CONFIG")" == "stock-480tplus" ]] || fail "DXP480T Plus stock profile was not persisted"
json=$(request /bios/fan-curve 'action=stop' POST)
assert_contains "$json" '"ok":true'
json=$(request /bios/fan-curve 'action=start&mode=stock-6800pro&confirm=firmware-reversed' POST)
assert_contains "$json" '"ok":false'
assert_contains "$json" '必须与检测到的精确机型匹配'

json=$(request /bios/fan-curve 'action=start&mode=custom&confirm=firmware-reversed&interval=10&downshift=60&minimum=40&cpu=42%2C50%2C70%2C78%2C90&hdd=30%2C40%2C46%2C52%2C55&ssd=50%2C55%2C60%2C65%2C70&pwm=65%2C125%2C200%2C235&require_storage=false' POST)
assert_contains "$json" '"ok":true'
[[ "$(sed -n 's/^cpu=//p' "$CONFIG")" == "42,50,70,78,90" ]] || fail "URL-encoded CPU curve was not decoded"
[[ "$(sed -n 's/^hdd=//p' "$CONFIG")" == "30,40,46,52,55" ]] || fail "URL-encoded HDD curve was not decoded"
[[ "$(sed -n 's/^ssd=//p' "$CONFIG")" == "50,55,60,65,70" ]] || fail "URL-encoded SSD curve was not decoded"
[[ "$(sed -n 's/^pwm=//p' "$CONFIG")" == "65,125,200,235" ]] || fail "URL-encoded PWM curve was not decoded"
json=$(request /bios/fan-curve 'action=stop' POST)
assert_contains "$json" '"ok":true'

: > "$CALLS"
export UGREEN_PRODUCT_NAME="DXP4800S"
json=$(request /bios/fan-curve 'action=start&mode=custom' POST)
assert_contains "$json" '"ok":false'
assert_contains "$json" '需要先确认风险'
[[ ! -s "$CALLS" ]] || fail "unconfirmed curve start reached ugreenctl"

echo "fan curve API tests passed"
