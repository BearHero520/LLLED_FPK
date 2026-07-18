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
cat > "$SERVER_DIR/led_daemon.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$SERVER_DIR/lib/app_paths.sh" <<'EOF'
return 23
EOF

export TRIM_APPDEST="$APP_ROOT"
export TRIM_PKGVAR="$TMP/var"
export UGREEN_LOG_USE_FLOCK=false

if bash "$ROOT/App.Native.UGreenLED/cmd/main" start >"$TMP/stdout" 2>"$TMP/stderr"; then
    fail "main unexpectedly succeeded after app_paths bootstrap failure"
fi

LOG_FILE="$TMP/var/log/app.log"
[[ -s "$LOG_FILE" ]] || fail "bootstrap failure was not persisted"
grep -Fq '[event=service.bootstrap_failed]' "$LOG_FILE" || fail "bootstrap event missing"
grep -Fq 'app_paths.sh' "$LOG_FILE" || fail "failed library path missing"
[[ ! -s "$TMP/stdout" ]] || fail "bootstrap log polluted stdout"

echo "main bootstrap logging test passed"
