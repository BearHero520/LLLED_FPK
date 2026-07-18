#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
API="$ROOT/App.Native.UGreenLED/app/ui/api.cgi"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "missing [$2]"; }

export TRIM_APPDEST="$ROOT/App.Native.UGreenLED/app"
export TRIM_PKGVAR="$TMP/var"
export UGREEN_RUNTIME_DIR="$TMP/run"
export UGREEN_DIAG_I2C_PROBE=off
export UGREEN_DIAG_UGREENCTL=/bin/false

request() {
    local path="$1" query="${2:-}" method="${3:-GET}" request_id="${4:-test-request-123}" body="${5:-}"
    local length=${#body}
    PATH_INFO="$path" QUERY_STRING="$query" REQUEST_METHOD="$method" CONTENT_LENGTH="$length" \
        HTTP_X_REQUEST_ID="$request_id" bash "$API" <<< "$body"
}

response=$(request /unknown '' GET test-request-123)
assert_contains "$response" 'Status: 404 Not Found'
assert_contains "$response" 'Content-Type: application/json; charset=utf-8'
assert_contains "$response" 'X-Request-ID: test-request-123'
assert_contains "$response" '"ok":false'
[[ "$response" != *'[event='* ]] || fail "log line polluted CGI response"

LOG_FILE="$TMP/var/log/app.log"
[[ -s "$LOG_FILE" ]] || fail "API did not create app.log"
grep -Fq '[request=test-request-123]' "$LOG_FILE" || fail "request ID missing from log"
grep -Fq 'path="/unknown"' "$LOG_FILE" || fail "API path missing from log"
grep -Fq 'http_status="404"' "$LOG_FILE" || fail "HTTP status missing from request log"

mode_before=$(sed -n '/^\[mode\]$/,/^\[/s/^global=//p' "$TMP/var/settings.conf" | head -n 1)
response=$(request /mode 'mode=off' GET method-guard-test)
assert_contains "$response" 'Status: 405 Method Not Allowed'
assert_contains "$response" 'method not allowed'
mode_after=$(sed -n '/^\[mode\]$/,/^\[/s/^global=//p' "$TMP/var/settings.conf" | head -n 1)
[[ "$mode_after" == "$mode_before" ]] || fail "GET /mode changed persisted mode"

large_body=$(head -c 70000 /dev/zero | tr '\0' x)
response=$(request /settings '' POST payload-limit-test "$large_body")
assert_contains "$response" 'Status: 413 Payload Too Large'
assert_contains "$response" 'settings payload too large'

response=$(request /settings '' POST settings-secret-test $'private.password=supersecret\nmode.global=smart')
assert_contains "$response" '"ok":true'
! grep -Fq 'supersecret' "$LOG_FILE" || fail "settings value leaked into log"

response=$(request /logs/config 'level=debug' POST log-config-test)
assert_contains "$response" '"ok":true'
grep -Fq 'level=debug' "$TMP/var/settings.conf" || fail "log level was not saved"

response=$(request /logs 'source=application&level=all&lines=200' GET log-read-test)
assert_contains "$response" '"source":"application"'
assert_contains "$response" '"write_level":"debug"'
assert_contains "$response" 'test-request-123'

response=$(request /hardware/diagnostics '' GET hardware-diagnostics-test)
assert_contains "$response" 'Status: 200 OK'
assert_contains "$response" '"filename":"ugreen-led-diagnostics-'
assert_contains "$response" '===== hardware-diagnostics ====='
assert_contains "$response" 'collector_version=1'
assert_contains "$response" '===== application-log-tail ====='
assert_contains "$response" 'hardware-diagnostics-test'

response=$(request /hardware/diagnostics '' POST hardware-diagnostics-method-test)
assert_contains "$response" 'Status: 405 Method Not Allowed'
assert_contains "$response" 'method not allowed'

response=$(request /logs 'source=../settings.conf&lines=99999' GET log-path-test)
assert_contains "$response" '"ok":false'
assert_contains "$response" 'unknown log source'

response=$(request /logs/client '' POST client-error-test '{"kind":"window.error","message":"token=client-secret"}')
assert_contains "$response" '"ok":true'
grep -Fq '[event=client.error]' "$LOG_FILE" || fail "client error event missing"
grep -Fq '<redacted-sensitive-client-payload>' "$LOG_FILE" || fail "sensitive client payload was not redacted"
! grep -Fq 'client-secret' "$LOG_FILE" || fail "sensitive client payload leaked"

response=$(request /logs/config 'level=error' POST log-error-level-test)
assert_contains "$response" '"ok":true'
grep -Fq 'level=error' "$TMP/var/settings.conf" || fail "ERROR log level was not saved"

response=$(request /logs/clear 'confirm=clear-logs' POST log-clear-test)
assert_contains "$response" '"ok":true'
grep -Fq '[event=logging.cleared]' "$LOG_FILE" || fail "clear audit event missing"
! grep -Fq '[request=test-request-123]' "$LOG_FILE" || fail "rotated/current log history was not cleared"

BOOTSTRAP_VAR="$TMP/bootstrap-var"
response=$(TRIM_APPDEST="$TMP/missing-app" TRIM_PKGVAR="$BOOTSTRAP_VAR" UGREEN_RUNTIME_DIR="$TMP/bootstrap-run" \
    PATH_INFO=/status QUERY_STRING='' REQUEST_METHOD=GET CONTENT_LENGTH=0 \
    HTTP_X_REQUEST_ID=bootstrap-request-123 bash "$API" </dev/null)
assert_contains "$response" 'Status: 500 Internal Server Error'
assert_contains "$response" 'X-Request-ID: bootstrap-request-123'
assert_contains "$response" '"code":"API_BOOTSTRAP_FAILED"'
grep -Fq '[event=api.bootstrap_failed]' "$BOOTSTRAP_VAR/log/app.log" || fail "bootstrap fallback log missing"
grep -Fq '[request=bootstrap-request-123]' "$BOOTSTRAP_VAR/log/app.log" || fail "bootstrap request ID missing from fallback log"

echo "API logging tests passed"
