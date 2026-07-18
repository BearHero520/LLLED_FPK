#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export VAR_DIR="$TMP/var"
export LOG_DIR="$VAR_DIR/log"
export RUNTIME_DIR="$TMP/run"
export UGREEN_LOG_FILE="$LOG_DIR/app.log"
export UGREEN_LOG_COMPONENT="logging-test"
export UGREEN_LOG_LEVEL="INFO"
export UGREEN_LOG_MAX_BYTES=5242880
export UGREEN_LOG_KEEP_FILES=2

source "$ROOT/App.Native.UGreenLED/app/server/lib/logging.sh"
UGREEN_LOG_USE_FLOCK=false

stdout=$(ugreen_log_info "test.info" "第一行" "answer=42" "password=do-not-log")
[[ -z "$stdout" ]] || fail "logger wrote to stdout"
ugreen_log_debug "test.hidden" "INFO 级别不应写 DEBUG"

[[ -s "$UGREEN_LOG_FILE" ]] || fail "app.log was not created"
grep -Fq '[INFO]' "$UGREEN_LOG_FILE" || fail "INFO level missing"
grep -Fq '[logging-test]' "$UGREEN_LOG_FILE" || fail "component missing"
grep -Fq '[event=test.info]' "$UGREEN_LOG_FILE" || fail "event missing"
grep -Fq 'answer="42"' "$UGREEN_LOG_FILE" || fail "context missing"
grep -Fq 'password="<redacted>"' "$UGREEN_LOG_FILE" || fail "password was not redacted"
! grep -Fq 'do-not-log' "$UGREEN_LOG_FILE" || fail "secret leaked into log"
! grep -Fq 'test.hidden' "$UGREEN_LOG_FILE" || fail "DEBUG was written at INFO level"

before=$(wc -l < "$UGREEN_LOG_FILE" | tr -d ' ')
ugreen_log_warn "test.multiline" $'包含\n换行\t制表符\033[31m红色\007响铃'
after=$(wc -l < "$UGREEN_LOG_FILE" | tr -d ' ')
[[ "$after" -eq $((before + 1)) ]] || fail "multiline text forged additional log lines"
grep -Fq '[event=test.multiline]' "$UGREEN_LOG_FILE" || fail "multiline event missing"
! grep -q $'\033' "$UGREEN_LOG_FILE" || fail "ESC control character leaked into log"
! grep -q $'\007' "$UGREEN_LOG_FILE" || fail "BEL control character leaked into log"

ugreen_log_warn "test.inline_redaction" \
    'token=message-secret Authorization: Bearer bearer-secret password="two words secret"' \
    'payload={"api_key":"json two words secret"}'
grep -Fq '[event=test.inline_redaction]' "$UGREEN_LOG_FILE" || fail "inline redaction event missing"
grep -Fq '<redacted>' "$UGREEN_LOG_FILE" || fail "inline sensitive values were not redacted"
for secret in message-secret bearer-secret 'two words secret' 'json two words secret'; do
    ! grep -Fq "$secret" "$UGREEN_LOG_FILE" || fail "inline secret leaked into app log: $secret"
done

UGREEN_LOG_LEVEL=WARN
ugreen_log_rate_limited "same-error" 60 WARN "test.rate_limited" "重复错误"
ugreen_log_rate_limited "same-error" 60 WARN "test.rate_limited" "重复错误"
[[ "$(grep -Fc '[event=test.rate_limited]' "$UGREEN_LOG_FILE")" -eq 1 ]] || fail "rate limiting did not suppress duplicate"

concurrent_pids=()
for index in $(seq 1 12); do
    (ugreen_log_rate_limited "concurrent-error" 60 WARN "test.concurrent_rate" "concurrent-$index") &
    concurrent_pids+=("$!")
done
for pid in "${concurrent_pids[@]}"; do
    wait "$pid"
done
[[ "$(grep -Fc '[event=test.concurrent_rate]' "$UGREEN_LOG_FILE")" -eq 1 ]] || \
    fail "concurrent rate limiting emitted more than one record"

rate_state="$RUNTIME_DIR/log-rate/write-failure"
working_log_file="$UGREEN_LOG_FILE"
failed_log_target="$TMP/log-target-is-a-directory"
mkdir -p "$failed_log_target"
UGREEN_LOG_FILE="$failed_log_target"
ugreen_log_rate_limited "write-failure" 60 WARN "test.rate_write_failed" "must not consume rate window"
[[ ! -e "$rate_state" ]] || fail "failed log write incorrectly created rate-limit state"
UGREEN_LOG_FILE="$working_log_file"
ugreen_log_rate_limited "write-failure" 60 WARN "test.rate_write_recovered" "write recovered"
grep -Fq '[event=test.rate_write_recovered]' "$UGREEN_LOG_FILE" || \
    fail "rate-limited event was suppressed after log storage recovered"

old_stale_seconds="$UGREEN_LOG_LOCK_STALE_SECONDS"
UGREEN_LOG_LOCK_STALE_SECONDS=0

dead_lock="$TMP/dead-owner.lockdir"
mkdir -p "$dead_lock"
printf '99999999||0\n' > "$dead_lock/owner"
_ugreen_log_acquire_fallback_lock "$dead_lock" 4 || fail "dead fallback-lock owner was not reclaimed"
_ugreen_log_release_fallback_lock "$dead_lock" || fail "reclaimed fallback lock could not be released"

ownerless_lock="$TMP/ownerless.lockdir"
mkdir -p "$ownerless_lock"
_ugreen_log_acquire_fallback_lock "$ownerless_lock" 4 || fail "stale ownerless fallback lock was not reclaimed"
_ugreen_log_release_fallback_lock "$ownerless_lock" || fail "ownerless fallback lock could not be released"

live_lock="$TMP/live-owner.lockdir"
mkdir -p "$live_lock"
live_pid="${BASHPID:-$$}"
live_start=$(_ugreen_log_process_start_token "$live_pid" 2>/dev/null || true)
printf '%s|%s|0\n' "$live_pid" "$live_start" > "$live_lock/owner"
touch -t 200001010000 "$live_lock" 2>/dev/null || true
if _ugreen_log_acquire_fallback_lock "$live_lock" 2; then
    fail "live fallback-lock owner was reclaimed solely because the lock was old"
fi
[[ -f "$live_lock/owner" ]] || fail "live fallback-lock owner metadata was removed"
rm -f "$live_lock/owner"
rmdir "$live_lock"
UGREEN_LOG_LOCK_STALE_SECONDS="$old_stale_seconds"

redacted=$(ugreen_log_redact_query 'mode=smart&token=abc123&confirm=clear-logs&led=disk1')
[[ "$redacted" == *'mode=smart'* && "$redacted" == *'token=<redacted>'* && "$redacted" == *'confirm=<redacted>'* ]] || \
    fail "query redaction failed: $redacted"
[[ "$redacted" != *'abc123'* && "$redacted" != *'clear-logs'* ]] || fail "query secret leaked"

UGREEN_LOG_LEVEL=DEBUG
ugreen_log_debug "test.debug" "详细日志已开启"
grep -Fq '[event=test.debug]' "$UGREEN_LOG_FILE" || fail "DEBUG level was not written"

raw_rc_log="$TMP/raw-return.log"
if ugreen_log_run_raw "$raw_rc_log" 1024 2 "return-code" \
    bash -c 'printf "raw command output token=raw-secret Authorization: Bearer raw-bearer password=\"raw two words\"\n"; exit 37'; then
    fail "raw wrapper unexpectedly discarded the wrapped command failure"
else
    raw_rc=$?
fi
[[ "$raw_rc" -eq 37 ]] || fail "raw wrapper changed command exit code: $raw_rc"
grep -Fq '===== BEGIN ' "$raw_rc_log" || fail "raw wrapper BEGIN marker missing"
grep -Fq 'raw command output' "$raw_rc_log" || fail "raw wrapper command output missing"
grep -Fq 'rc=37' "$raw_rc_log" || fail "raw wrapper END marker or return code missing"
grep -Fq '<redacted>' "$raw_rc_log" || fail "raw output sensitive values were not redacted"
for secret in raw-secret raw-bearer 'raw two words'; do
    ! grep -Fq "$secret" "$raw_rc_log" || fail "inline secret leaked into raw log: $secret"
done

# 日志锁自身损坏/不可打开时也必须执行原命令，并原样保留退出码。
flock_fail_log="$TMP/raw-flock-open-failure.log"
flock_fail_marker="$TMP/raw-flock-command-ran"
mkdir "${flock_fail_log}.lock"
if UGREEN_LOG_USE_FLOCK=true ugreen_log_run_raw "$flock_fail_log" 1024 2 "flock-open-failure" \
    bash -c 'touch "$1"; exit 29' _ "$flock_fail_marker"; then
    fail "raw wrapper unexpectedly discarded the command failure after flock-file open failure"
else
    flock_fail_rc=$?
fi
[[ "$flock_fail_rc" -eq 29 ]] || fail "flock-file failure changed command exit code: $flock_fail_rc"
[[ -f "$flock_fail_marker" ]] || fail "flock-file failure prevented the business command from running"

raw_limit=1024
raw_log="$TMP/raw-bounded.log"
check_posix_permissions=true
case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) check_posix_permissions=false ;;
esac
ugreen_log_run_raw "$raw_log" "$raw_limit" 2 "bounded-output" bash -c '
    payload=$(printf "%0500d" 0)
    for ((i = 1; i <= 24; i++)); do
        printf "raw-%03d-%s\n" "$i" "$payload"
    done
'
[[ -f "$raw_log" && -f "${raw_log}.1" && -f "${raw_log}.2" ]] || \
    fail "raw output did not create the expected retained files"
[[ ! -e "${raw_log}.3" ]] || fail "raw output retained more files than configured"
for file in "$raw_log" "${raw_log}.1" "${raw_log}.2"; do
    size=$(wc -c < "$file" | tr -d ' ')
    (( size <= raw_limit )) || fail "raw log exceeded hard limit: $file is $size bytes"
    first_line=$(head -n 1 "$file")
    case "$first_line" in
        raw-*|'===== '*|'[raw log line omitted:'*) ;;
        *) fail "rotated raw log starts with a partial record: $first_line" ;;
    esac
    if $check_posix_permissions; then
        mode=$(stat -c %a "$file")
        [[ "$mode" == "640" ]] || fail "raw log permissions widened after rotation: $file mode=$mode"
    fi
done

if [[ -d "/proc/${BASHPID:-$$}/fd" ]]; then
    fd_log="$TMP/raw-fd.log"
    if ! {
        _ugreen_log_run_raw_unlocked "$fd_log" 1024 2 "fd-inheritance" bash -c '
            if [[ -e "/proc/${BASHPID}/fd/9" ]]; then
                printf "fd9=open\n"
                exit 91
            fi
            printf "fd9=closed\n"
        '
    } 9>>"$TMP/outer-raw.lock"; then
        fail "raw wrapper command inherited the log lock descriptor"
    fi
    grep -Fq 'fd9=closed' "$fd_log" || fail "raw wrapper did not prove fd 9 was closed"
fi

stream_log="$TMP/raw-stream.log"
{
    payload=$(printf '%0500d' 0)
    for ((index = 1; index <= 24; index++)); do
        printf 'stream-%03d-%s\n' "$index" "$payload"
    done
} | ugreen_log_stream_raw "$stream_log" "$raw_limit" 2
[[ -f "$stream_log" && -f "${stream_log}.1" && -f "${stream_log}.2" ]] || \
    fail "streaming raw logger did not rotate"
[[ ! -e "${stream_log}.3" ]] || fail "streaming raw logger retained too many files"
for file in "$stream_log" "${stream_log}.1" "${stream_log}.2"; do
    size=$(wc -c < "$file" | tr -d ' ')
    (( size <= raw_limit )) || fail "streaming raw log exceeded hard limit: $file is $size bytes"
done

UGREEN_LOG_MAX_BYTES=420
for index in $(seq 1 18); do
    ugreen_log_info "test.rotation" "rotation-$index-abcdefghijklmnopqrstuvwxyz" "index=$index"
done
[[ -f "${UGREEN_LOG_FILE}.1" ]] || fail "rotation file was not created"
[[ ! -f "${UGREEN_LOG_FILE}.3" ]] || fail "rotation retained too many files"
grep -Fq '[event=test.rotation]' "$UGREEN_LOG_FILE" || fail "logging stopped after rotation"

source "$ROOT/App.Native.UGreenLED/app/server/lib/settings.sh"
cat > "$TMP/old-settings.conf" <<'EOF'
[mode]
global=smart
EOF
UGREEN_LOG_LEVEL=ERROR
ugreen_log_configure_from_settings "$TMP/old-settings.conf"
[[ "$UGREEN_LOG_LEVEL" == "INFO" ]] || fail "old settings did not use INFO fallback"

echo "logging tests passed"
