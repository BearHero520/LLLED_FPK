#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

APP_ROOT="$TMP/app"
SERVER_DIR="$APP_ROOT/server"
LOG_FILE="$TMP/daemon.log"
mkdir -p "$SERVER_DIR/lib" "$SERVER_DIR/bin" "$TMP/var" "$TMP/run"

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
EOF

export TRIM_APPDEST="$APP_ROOT"
export TRIM_PKGVAR="$TMP/var"
export UGREEN_RUNTIME_DIR="$TMP/run"
export TEST_DAEMON_LOG="$LOG_FILE"

bash "$ROOT/App.Native.UGreenLED/cmd/main" start
[[ -f "$LOG_FILE" ]] || { echo "FAIL: daemon was not started" >&2; exit 1; }
[[ "$(cat "$LOG_FILE")" == "start" ]] || { echo "FAIL: unexpected daemon action" >&2; exit 1; }

echo "main start fallback test passed"
