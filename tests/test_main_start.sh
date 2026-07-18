#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

APP_ROOT="$TMP/app"
SERVER_DIR="$APP_ROOT/server"
LOG_FILE="$TMP/daemon.log"
BG_PID_FILE="$TMP/background.pid"
mkdir -p "$SERVER_DIR/lib" "$SERVER_DIR/bin" "$TMP/var" "$TMP/run"
cp "$ROOT/App.Native.UGreenLED/app/server/lib/logging.sh" "$SERVER_DIR/lib/logging.sh"

cat > "$SERVER_DIR/lib/app_paths.sh" <<'EOF'
ugreen_resolve_runtime() {
    RUNTIME_DIR="${UGREEN_RUNTIME_DIR}"
    mkdir -p "$RUNTIME_DIR"
}
EOF
cat > "$SERVER_DIR/lib/settings.sh" <<'EOF'
settings_init() { :; }
settings_set() { :; }
EOF
cat > "$SERVER_DIR/lib/hardware_profile.sh" <<'EOF'
:
EOF
cat > "$SERVER_DIR/lib/driver_manager.sh" <<'EOF'
driver_managed_by_app() { return 1; }
driver_sysfs_ready() { return 1; }
driver_dkms_installed() { return 1; }
EOF
cat > "$SERVER_DIR/lib/led_api.sh" <<'EOF'
led_backend_configured() { echo auto; }
ensure_led_backend() { return 1; }
led_backend_reset() { :; }
EOF
cat > "$SERVER_DIR/led_daemon.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" > "$TEST_DAEMON_LOG"
printf 'stub daemon output action=%s\n' "$1"
sleep 20 &
printf '%s\n' "$!" > "$TEST_BG_PID_FILE"
EOF

export TRIM_APPDEST="$APP_ROOT"
export TRIM_PKGVAR="$TMP/var"
export UGREEN_RUNTIME_DIR="$TMP/run"
export TEST_DAEMON_LOG="$LOG_FILE"
export TEST_BG_PID_FILE="$BG_PID_FILE"

if timeout 15 bash "$ROOT/App.Native.UGreenLED/cmd/main" start >"$TMP/main.stdout" 2>"$TMP/main.stderr"; then
    main_rc=0
else
    main_rc=$?
fi
[[ "$main_rc" -eq 0 ]] || { echo "FAIL: main start returned $main_rc" >&2; exit 1; }
[[ -f "$LOG_FILE" ]] || { echo "FAIL: daemon was not started" >&2; exit 1; }
[[ "$(cat "$LOG_FILE")" == "start" ]] || { echo "FAIL: unexpected daemon action" >&2; exit 1; }
[[ -f "$BG_PID_FILE" ]] || { echo "FAIL: daemon background child was not created" >&2; exit 1; }

APP_LOG="$TMP/var/log/app.log"
DAEMON_LAUNCH_LOG="$TMP/var/log/daemon-launch.log"
[[ -s "$APP_LOG" ]] || { echo "FAIL: real logger did not create app.log" >&2; exit 1; }
grep -Fq '[event=service.start_requested]' "$APP_LOG" || { echo "FAIL: start request log missing" >&2; exit 1; }
grep -Fq '[event=backend.unavailable]' "$APP_LOG" || { echo "FAIL: backend failure log missing" >&2; exit 1; }
grep -Fq 'exit_code="1"' "$APP_LOG" || { echo "FAIL: backend failure exit code missing" >&2; exit 1; }
grep -Fq '[event=daemon.started]' "$APP_LOG" || { echo "FAIL: daemon completion log missing" >&2; exit 1; }
grep -Fq 'raw_log="daemon-launch.log"' "$APP_LOG" || { echo "FAIL: daemon raw-log context missing" >&2; exit 1; }
[[ -s "$DAEMON_LAUNCH_LOG" ]] || { echo "FAIL: daemon launch raw log missing" >&2; exit 1; }
grep -Fq 'stub daemon output action=start' "$DAEMON_LAUNCH_LOG" || { echo "FAIL: daemon stdout was not captured" >&2; exit 1; }
grep -Fq '===== END operation=daemon-start' "$DAEMON_LAUNCH_LOG" || { echo "FAIL: daemon raw END marker missing" >&2; exit 1; }

kill "$(cat "$BG_PID_FILE")" 2>/dev/null || true

echo "main start logging test passed"
