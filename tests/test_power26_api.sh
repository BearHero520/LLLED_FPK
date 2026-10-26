#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
API="$ROOT/App.Native.UGreenLED/app/ui/api.cgi"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "missing [$2] in [$1]"; }

CLI_LOG="$TMP/cli.log"
MOCK_CLI="$TMP/ugreen_leds_cli"
mkdir -p "$TMP/bin"
cat > "$MOCK_CLI" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CLI_LOG"
case "$*" in *"-status"*) echo 'status = on, brightness = 64, color = RGB(1, 2, 3)' ;; esac
EOF
chmod +x "$MOCK_CLI"

export TRIM_APPDEST="$ROOT/App.Native.UGreenLED/app"
export TRIM_PKGVAR="$TMP/var"
export UGREEN_PRODUCT_NAME="UGREEN DXP480T Plus"
export UGREEN_CLI_OVERRIDE="$MOCK_CLI" CLI_LOG

request() {
  local path="$1" query="${2:-}" method="${3:-GET}"
  PATH_INFO="$path" QUERY_STRING="$query" REQUEST_METHOD="$method" CONTENT_LENGTH=0 \
    bash "$API" | tail -n 1
}

json=$(request /power26/apply 'color=preserve&effect=fast&threshold=32')
assert_contains "$json" 'method not allowed'
[[ ! -s "$CLI_LOG" ]] || fail "GET request reached LED CLI"

: > "$CLI_LOG"
json=$(request /power26/apply 'color=preserve&effect=fast&threshold=32' POST)
assert_contains "$json" '"ok":true'
grep -q -- 'power -status' "$CLI_LOG" || fail "missing readback"
grep -q -- 'power -blink 250 250 --force --apply' "$CLI_LOG" || fail "missing committed blink"

: > "$CLI_LOG"
json=$(request /power26/apply 'color=preserve&effect=off&threshold=32' POST)
assert_contains "$json" '"ok":true'
grep -q -- 'power -off --force --apply' "$CLI_LOG" || fail "missing committed off"
: > "$CLI_LOG"
json=$(request /power26/apply 'color=red&effect=steady' POST)
assert_contains "$json" '"ok":false'
json=$(request /power26/apply 'color=preserve&effect=breath' POST)
assert_contains "$json" '"ok":false'
[[ ! -s "$CLI_LOG" ]] || fail "unsupported effect reached hardware"

if grep -Eq 'i2c(get|set)|LED_I2C_DEV_ROOT|/sys/class/leds' "$ROOT/App.Native.UGreenLED/app/server/lib/led_api.sh"; then
  fail "application LED API contains direct hardware access"
fi

echo "power26 API tests passed"
