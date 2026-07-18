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

json=$(request /power26/apply 'color=red&effect=fast&threshold=32')
assert_contains "$json" 'method not allowed'
[[ ! -s "$CLI_LOG" ]] || fail "GET request reached LED CLI"

: > "$CLI_LOG"
json=$(request /power26/apply 'color=red&effect=fast&threshold=32' POST)
assert_contains "$json" '"ok":true'
grep -q -- '--dxp480t-power-probe' "$CLI_LOG" || fail "DXP480T controller was not probed through bundled LED CLI"
grep -q -- '--dxp480t-power red fast' "$CLI_LOG" || fail "power light did not use the DXP480T bundled CLI command"
if grep -q -- 'power -color\|power -blink\|power -brightness' "$CLI_LOG"; then
  fail "DXP480T power light fell back to the generic RGB CLI protocol"
fi

: > "$CLI_LOG"
json=$(request /power26/apply 'color=red&effect=off&threshold=32' POST)
assert_contains "$json" '"ok":true'
grep -q -- '--dxp480t-power red off' "$CLI_LOG" || fail "power light off did not use the DXP480T bundled CLI command"

if grep -Eq 'i2c(get|set)|LED_I2C_DEV_ROOT|/sys/class/leds' "$ROOT/App.Native.UGreenLED/app/server/lib/led_api.sh"; then
  fail "application LED API contains direct hardware access"
fi

PATCH="$ROOT/App.Native.UGreenLED/app/server/vendor/ugreen_leds_controller/patches/dxp480t-power.patch"
grep -Fq 'write_byte(0xa0, 1)' "$PATCH" || fail "patched CLI does not clear the red selector"
grep -Fq 'write_byte(0xa0, 2)' "$PATCH" || fail "patched CLI does not clear the white selector"
grep -Fq 'case effect_t::fast: return write_byte(0x50, 1);' "$PATCH" || fail "patched CLI does not implement fast flash"
grep -Fq 'return write_byte(0x51, 1);' "$PATCH" || fail "patched CLI does not implement slow flash"
grep -Fq 'case effect_t::breath: return write_byte(0x50, 2);' "$PATCH" || fail "patched CLI does not implement breathing"

echo "power26 API tests passed"
