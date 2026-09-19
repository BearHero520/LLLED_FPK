#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
cleanup() {
    if [[ -f "$TMP/run/led_daemon.pid" ]]; then
        kill "$(cat "$TMP/run/led_daemon.pid")" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
export TRIM_APPDEST="$TMP/app" TRIM_PKGVAR="$TMP/var" UGREEN_RUNTIME_DIR="$TMP/run"
export TEST_SERVICE_CALLS="$TMP/service-calls"
mkdir -p "$TMP/app/cmd" "$TMP/run"
ln -s "$ROOT/App.Native.UGreenLED/app/server" "$TMP/app/server"
cat > "$TMP/app/cmd/main" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_SERVICE_CALLS"
sleep 60 >/dev/null 2>&1 &
echo "$!" > "$UGREEN_RUNTIME_DIR/led_daemon.pid"
SH
chmod +x "$TMP/app/cmd/main"
request() {
    PATH_INFO=/daemon/start QUERY_STRING='' REQUEST_METHOD="$1" CONTENT_LENGTH=0 \
        bash "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" </dev/null
}
response=$(request POST)
[[ "$response" == *'"ok":true'* && "$response" == *'"daemon":"running"'* ]]
[[ "$(wc -l < "$TEST_SERVICE_CALLS")" -eq 1 ]]
first_pid=$(cat "$TMP/run/led_daemon.pid")
response=$(request POST)
[[ "$response" == *'"ok":true'* && "$response" == *'"daemon":"running"'* ]]
[[ "$(cat "$TMP/run/led_daemon.pid")" == "$first_pid" ]]
[[ "$(wc -l < "$TEST_SERVICE_CALLS")" -eq 1 ]]
response=$(request GET)
[[ "$response" == *'405 Method Not Allowed'* ]]
[[ "$(wc -l < "$TEST_SERVICE_CALLS")" -eq 1 ]]
echo 'daemon start is idempotent; existing service and hardware policy are untouched'
