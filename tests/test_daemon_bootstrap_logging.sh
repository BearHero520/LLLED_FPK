#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

APP_ROOT="$TMP/app"
SERVER_DIR="$APP_ROOT/server"
mkdir -p "$SERVER_DIR/lib" "$TMP/var"
cp "$ROOT/App.Native.UGreenLED/app/server/lib/logging.sh" "$SERVER_DIR/lib/logging.sh"

cat > "$SERVER_DIR/lib/app_paths.sh" <<'EOF'
return 23
EOF

export TRIM_APPDEST="$APP_ROOT"
export TRIM_PKGVAR="$TMP/var"

if bash "$ROOT/App.Native.UGreenLED/app/server/led_daemon.sh" status \
    >"$TMP/bootstrap.stdout" 2>"$TMP/bootstrap.stderr"; then
    fail "daemon unexpectedly succeeded after app_paths bootstrap failure"
fi

LOG_FILE="$TMP/var/log/app.log"
[[ -s "$LOG_FILE" ]] || fail "daemon bootstrap failure was not persisted"
grep -Fq '[event=daemon.bootstrap_failed]' "$LOG_FILE" || fail "daemon bootstrap event missing"
grep -Fq 'app_paths.sh' "$LOG_FILE" || fail "failed daemon library path missing"
[[ ! -s "$TMP/bootstrap.stdout" ]] || fail "daemon bootstrap log polluted stdout"

cat > "$SERVER_DIR/lib/app_paths.sh" <<'EOF'
ugreen_resolve_runtime() { return 1; }
EOF
rm -f "$LOG_FILE"

if bash "$ROOT/App.Native.UGreenLED/app/server/led_daemon.sh" status \
    >"$TMP/runtime.stdout" 2>"$TMP/runtime.stderr"; then
    fail "daemon unexpectedly succeeded after runtime initialization failure"
fi
[[ -s "$LOG_FILE" ]] || fail "daemon runtime failure was not persisted"
grep -Fq '[event=daemon.runtime_failed]' "$LOG_FILE" || fail "daemon runtime event missing"
[[ ! -s "$TMP/runtime.stdout" ]] || fail "daemon runtime log polluted stdout"

cat > "$SERVER_DIR/lib/app_paths.sh" <<'EOF'
ugreen_resolve_runtime() {
    RUNTIME_DIR="$UGREEN_RUNTIME_DIR"
    mkdir -p "$RUNTIME_DIR"
}
EOF
cat > "$SERVER_DIR/lib/settings.sh" <<'EOF'
return 23
EOF
export UGREEN_RUNTIME_DIR="$TMP/run"
rm -f "$LOG_FILE"

if bash "$ROOT/App.Native.UGreenLED/app/server/led_daemon.sh" status \
    >"$TMP/library.stdout" 2>"$TMP/library.stderr"; then
    fail "daemon unexpectedly succeeded after dependency source failure"
fi
[[ -s "$LOG_FILE" ]] || fail "daemon dependency failure was not persisted"
grep -Fq '[event=daemon.library_source_failed]' "$LOG_FILE" || fail "daemon dependency event missing"
grep -Fq 'library="settings"' "$LOG_FILE" || fail "failed daemon dependency name missing"

cat > "$SERVER_DIR/lib/settings.sh" <<'EOF'
settings_init() { return 1; }
settings_get() { printf '%s\n' "${4:-}"; }
EOF
for library in hardware_profile driver_manager led_api disk_map disk_state net_state led_apply; do
    printf ':\n' > "$SERVER_DIR/lib/${library}.sh"
done
rm -f "$LOG_FILE"

if bash "$ROOT/App.Native.UGreenLED/app/server/led_daemon.sh" status \
    >"$TMP/settings.stdout" 2>"$TMP/settings.stderr"; then
    fail "daemon status unexpectedly reported running"
else
    status_rc=$?
fi
[[ "$status_rc" -eq 3 ]] || fail "daemon status changed after fail-open settings error: $status_rc"
grep -Fq '[event=settings.init_failed]' "$LOG_FILE" || fail "daemon settings initialization event missing"

echo "daemon bootstrap logging test passed"
