#!/bin/bash
# 统一日志：只写持久化 VAR_DIR/log，不向 stdout 输出，避免污染 CGI JSON。

if [[ "${UGREEN_LOGGING_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
UGREEN_LOGGING_SH_LOADED=1

UGREEN_LOG_DIR="${LOG_DIR:-${VAR_DIR:-/tmp}/log}"
UGREEN_LOG_FILE="${UGREEN_LOG_FILE:-${UGREEN_LOG_DIR}/app.log}"
UGREEN_LOG_COMPONENT="${UGREEN_LOG_COMPONENT:-app}"
UGREEN_LOG_LEVEL="${UGREEN_LOG_LEVEL:-INFO}"
UGREEN_LOG_MAX_BYTES="${UGREEN_LOG_MAX_BYTES:-5242880}"
UGREEN_LOG_KEEP_FILES="${UGREEN_LOG_KEEP_FILES:-5}"
UGREEN_LOG_FIELD_LIMIT="${UGREEN_LOG_FIELD_LIMIT:-4096}"
UGREEN_LOG_STDERR_FALLBACK="${UGREEN_LOG_STDERR_FALLBACK:-false}"
UGREEN_LOG_LOCK_STALE_SECONDS="${UGREEN_LOG_LOCK_STALE_SECONDS:-10}"
UGREEN_LOG_TRAP_ACTIVE=false
UGREEN_LOG_USE_FLOCK=false
if command -v flock >/dev/null 2>&1; then
    case "$(uname -s 2>/dev/null || echo unknown)" in
        MINGW*|MSYS*|CYGWIN*) UGREEN_LOG_USE_FLOCK=false ;;
        *) UGREEN_LOG_USE_FLOCK=true ;;
    esac
fi

ugreen_log_now_ms() {
    local value
    value=$(date +%s%3N 2>/dev/null || true)
    if [[ "$value" =~ ^[0-9]{13,}$ ]]; then
        printf '%s\n' "$value"
    else
        printf '%s000\n' "$(date +%s 2>/dev/null || echo 0)"
    fi
}

ugreen_log_make_request_id() {
    printf 'req-%s-%s-%s\n' "$(ugreen_log_now_ms)" "${BASHPID:-$$}" "${RANDOM:-0}"
}

ugreen_log_configure_from_settings() {
    local settings_file="${1:-}" level max_kb keep
    [[ -n "$settings_file" && -f "$settings_file" ]] || return 0
    declare -F settings_get >/dev/null || return 0

    level=$(settings_get "$settings_file" logging level "info")
    max_kb=$(settings_get "$settings_file" logging max_size_kb "5120")
    keep=$(settings_get "$settings_file" logging retained_files "5")

    case "${level,,}" in
        debug|info|warn|error|off) UGREEN_LOG_LEVEL="${level^^}" ;;
        *) UGREEN_LOG_LEVEL="INFO" ;;
    esac
    if [[ "$max_kb" =~ ^[0-9]+$ ]] && (( max_kb >= 256 && max_kb <= 65536 )); then
        UGREEN_LOG_MAX_BYTES=$((max_kb * 1024))
    fi
    if [[ "$keep" =~ ^[0-9]+$ ]] && (( keep >= 1 && keep <= 10 )); then
        UGREEN_LOG_KEEP_FILES="$keep"
    fi
}

_ugreen_log_level_value() {
    case "${1^^}" in
        DEBUG) echo 10 ;;
        INFO) echo 20 ;;
        WARN|WARNING) echo 30 ;;
        ERROR) echo 40 ;;
        OFF) echo 99 ;;
        *) echo 20 ;;
    esac
}

_ugreen_log_should_emit() {
    local requested configured
    requested=$(_ugreen_log_level_value "$1")
    configured=$(_ugreen_log_level_value "$UGREEN_LOG_LEVEL")
    (( requested >= configured && configured < 99 ))
}

_ugreen_log_redact_pattern() {
    local remaining="${1:-}" pattern="$2" suffix_index="${3:-0}"
    local output="" match prefix suffix="" match_lead match_label
    case "$suffix_index" in
        ''|*[!0-9]*) suffix_index=0 ;;
    esac
    while [[ "$remaining" =~ $pattern ]]; do
        match="${BASH_REMATCH[0]}"
        match_lead="${BASH_REMATCH[1]:-}"
        match_label="${BASH_REMATCH[2]:-}"
        suffix=""
        if (( suffix_index > 0 )); then
            suffix="${BASH_REMATCH[$suffix_index]:-}"
        fi
        [[ -n "$match" ]] || break
        prefix="${remaining%%"$match"*}"
        output+="${prefix}${match_lead}${match_label}<redacted>${suffix}"
        remaining="${remaining#*"$match"}"
    done
    UGREEN_LOG_REDACT_RESULT="${output}${remaining}"
}

_ugreen_log_redact_inline() {
    local value="${1:-}" keys credential_double credential_single credential_unquoted
    local bearer_double bearer_single bearer_unquoted had_nocasematch=false
    keys='password|passwd|passphrase|token|secret|authorization|auth|cookie|api[_-]?key|apikey|credential|private[_-]?key|access[_-]?key|session[_-]?id|csrf|confirm'
    credential_double="(^|[^[:alnum:]_])((${keys})[\"']?[[:space:]]*[:=][[:space:]]*\")([^\"]*)(\")"
    credential_single="(^|[^[:alnum:]_])((${keys})[\"']?[[:space:]]*[:=][[:space:]]*')([^']*)(')"
    credential_unquoted="(^|[^[:alnum:]_])((${keys})[\"']?[[:space:]]*[:=][[:space:]]*)((bearer[[:space:]]+)?[^[:space:]&;,\"']+)"
    bearer_double='(^|[^[:alnum:]_])(bearer[[:space:]]+")([^"]*)(")'
    bearer_single="(^|[^[:alnum:]_])(bearer[[:space:]]+')([^']*)(')"
    bearer_unquoted="(^|[^[:alnum:]_])(bearer[[:space:]]+)([^[:space:]&;,\"']+)"
    if shopt -q nocasematch; then
        had_nocasematch=true
    else
        shopt -s nocasematch
    fi
    _ugreen_log_redact_pattern "$value" "$credential_double" 5
    value="$UGREEN_LOG_REDACT_RESULT"
    _ugreen_log_redact_pattern "$value" "$credential_single" 5
    value="$UGREEN_LOG_REDACT_RESULT"
    _ugreen_log_redact_pattern "$value" "$credential_unquoted"
    value="$UGREEN_LOG_REDACT_RESULT"
    _ugreen_log_redact_pattern "$value" "$bearer_double" 4
    value="$UGREEN_LOG_REDACT_RESULT"
    _ugreen_log_redact_pattern "$value" "$bearer_single" 4
    value="$UGREEN_LOG_REDACT_RESULT"
    _ugreen_log_redact_pattern "$value" "$bearer_unquoted"
    value="$UGREEN_LOG_REDACT_RESULT"
    if [[ "$had_nocasematch" != "true" ]]; then
        shopt -u nocasematch
    fi
    UGREEN_LOG_REDACT_RESULT="$value"
}

_ugreen_log_sanitize() {
    local value="${1:-}" limit="${UGREEN_LOG_FIELD_LIMIT:-4096}" code octal control
    _ugreen_log_redact_inline "$value"
    value="$UGREEN_LOG_REDACT_RESULT"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ \\n }"
    value="${value//$'\t'/ \\t }"
    for code in {1..8} 11 12 {14..31} 127; do
        printf -v octal '%03o' "$code"
        printf -v control '%b' "\\${octal}"
        value="${value//$control/}"
    done
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=4096
    if (( ${#value} > limit )); then
        value="${value:0:limit}…<truncated>"
    fi
    printf '%s' "$value"
}

ugreen_log_redact_query() {
    local raw="${1:-}" pair key value lower output="" separator=""
    local -a pairs=()
    IFS='&' read -r -a pairs <<< "$raw"
    for pair in "${pairs[@]}"; do
        [[ -n "$pair" ]] || continue
        key="${pair%%=*}"
        if [[ "$pair" == *=* ]]; then value="${pair#*=}"; else value=""; fi
        lower="${key,,}"
        case "$lower" in
            *password*|*passwd*|*token*|*secret*|*authorization*|*auth*|*cookie*|*api_key*|*apikey*|*credential*|*private_key*|*access_key*|confirm)
                value="<redacted>"
                ;;
        esac
        output+="${separator}${key}=${value}"
        separator="&"
    done
    printf '%s' "$output"
}

ugreen_log_mask_address() {
    local address="${1:-}"
    if [[ "$address" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
        printf '%s.x' "${BASH_REMATCH[1]}"
    elif [[ "$address" == *:* ]]; then
        printf '%s:*' "${address%%:*:*}"
    else
        printf '%s' "$address"
    fi
}

_ugreen_log_process_start_token() {
    local pid="$1" stat_line remainder
    [[ "$pid" =~ ^[0-9]+$ && -r "/proc/${pid}/stat" ]] || return 1
    IFS= read -r stat_line < "/proc/${pid}/stat" || return 1
    remainder="${stat_line##*) }"
    set -- $remainder
    [[ $# -ge 20 && "${20:-}" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "${20}"
}

_ugreen_log_read_fallback_owner() {
    local lock_dir="$1" entry name prefix extra
    UGREEN_LOG_LOCK_OWNER_KIND=""
    UGREEN_LOG_LOCK_OWNER_PATH=""
    UGREEN_LOG_LOCK_OWNER_PID=""
    UGREEN_LOG_LOCK_OWNER_START=""
    UGREEN_LOG_LOCK_OWNER_CREATED=""

    for entry in "${lock_dir}"/owner.*; do
        [[ -d "$entry" ]] || continue
        name="${entry##*/}"
        IFS='.' read -r prefix UGREEN_LOG_LOCK_OWNER_PID UGREEN_LOG_LOCK_OWNER_START \
            UGREEN_LOG_LOCK_OWNER_CREATED extra <<< "$name"
        UGREEN_LOG_LOCK_OWNER_KIND="guard"
        UGREEN_LOG_LOCK_OWNER_PATH="$entry"
        [[ "$prefix" == "owner" ]] || UGREEN_LOG_LOCK_OWNER_PID=""
        [[ "$UGREEN_LOG_LOCK_OWNER_PID" =~ ^[0-9]+$ ]] || UGREEN_LOG_LOCK_OWNER_PID=""
        [[ "$UGREEN_LOG_LOCK_OWNER_START" == "na" ]] && UGREEN_LOG_LOCK_OWNER_START=""
        return 0
    done

    if [[ -f "${lock_dir}/owner" ]]; then
        UGREEN_LOG_LOCK_OWNER_KIND="legacy"
        UGREEN_LOG_LOCK_OWNER_PATH="${lock_dir}/owner"
        IFS='|' read -r UGREEN_LOG_LOCK_OWNER_PID UGREEN_LOG_LOCK_OWNER_START \
            UGREEN_LOG_LOCK_OWNER_CREATED 2>/dev/null < "${lock_dir}/owner" || true
        [[ "$UGREEN_LOG_LOCK_OWNER_PID" =~ ^[0-9]+$ ]] || UGREEN_LOG_LOCK_OWNER_PID=""
        return 0
    fi
    return 1
}

_ugreen_log_reclaim_fallback_lock() {
    local lock_dir="$1" owner_kind="$2" owner_path="$3" quarantine
    case "$owner_kind" in
        guard)
            [[ -n "$owner_path" ]] || return 1
            rmdir "$owner_path" 2>/dev/null || return 1
            rmdir "$lock_dir" 2>/dev/null || true
            ;;
        legacy)
            quarantine="${lock_dir}/owner.reclaim.${BASHPID:-$$}.${RANDOM:-0}"
            mv "$owner_path" "$quarantine" 2>/dev/null || return 1
            rm -f "$quarantine" 2>/dev/null || return 1
            rmdir "$lock_dir" 2>/dev/null || true
            ;;
        none)
            rmdir "$lock_dir" 2>/dev/null || return 1
            ;;
        *) return 1 ;;
    esac
    return 0
}

_ugreen_log_acquire_fallback_lock() {
    local lock_dir="$1" attempts="${2:-20}" index owner_pid="" owner_start="" owner_created=""
    local owner_kind="" owner_path="" owner_guard="" current_start="" modified=0 now=0
    local stale_seconds="${UGREEN_LOG_LOCK_STALE_SECONDS:-10}"
    [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=20
    [[ "$stale_seconds" =~ ^[0-9]+$ ]] || stale_seconds=10
    for ((index = 0; index < attempts; index++)); do
        if mkdir "$lock_dir" 2>/dev/null; then
            owner_pid="${BASHPID:-$$}"
            owner_start=$(_ugreen_log_process_start_token "$owner_pid" 2>/dev/null || true)
            now=$(date +%s 2>/dev/null || echo 0)
            owner_guard="${lock_dir}/owner.${owner_pid}.${owner_start:-na}.${now}.${RANDOM:-0}"
            if mkdir "$owner_guard" 2>/dev/null; then
                return 0
            fi
            rmdir "$lock_dir" 2>/dev/null || true
            continue
        fi
        if _ugreen_log_read_fallback_owner "$lock_dir"; then
            owner_kind="$UGREEN_LOG_LOCK_OWNER_KIND"
            owner_path="$UGREEN_LOG_LOCK_OWNER_PATH"
            owner_pid="$UGREEN_LOG_LOCK_OWNER_PID"
            owner_start="$UGREEN_LOG_LOCK_OWNER_START"
            owner_created="$UGREEN_LOG_LOCK_OWNER_CREATED"
        else
            owner_kind="none"
            owner_path=""
            owner_pid=""
            owner_start=""
            owner_created=""
        fi
        modified=$(stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
        now=$(date +%s 2>/dev/null || echo 0)
        current_start=""
        if [[ "$owner_pid" =~ ^[0-9]+$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
            current_start=$(_ugreen_log_process_start_token "$owner_pid" 2>/dev/null || true)
        fi
        if { [[ "$owner_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$owner_pid" 2>/dev/null; } || \
            { [[ -n "$owner_start" && -n "$current_start" && "$owner_start" != "$current_start" ]]; } || \
            { ! [[ "$owner_pid" =~ ^[0-9]+$ ]] && [[ "$modified" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] && \
                (( now >= modified && now - modified >= stale_seconds )); }; then
            _ugreen_log_reclaim_fallback_lock "$lock_dir" "$owner_kind" "$owner_path" || true
            continue
        fi
        sleep 0.05
    done
    return 1
}

_ugreen_log_release_fallback_lock() {
    local lock_dir="$1" entry name prefix owner_pid owner_start owner_created extra
    local current_pid current_start=""
    current_pid="${BASHPID:-$$}"
    current_start=$(_ugreen_log_process_start_token "$current_pid" 2>/dev/null || true)
    for entry in "${lock_dir}"/owner.*; do
        [[ -d "$entry" ]] || continue
        name="${entry##*/}"
        IFS='.' read -r prefix owner_pid owner_start owner_created extra <<< "$name"
        [[ "$prefix" == "owner" && "$owner_pid" == "$current_pid" ]] || continue
        [[ "$owner_start" == "na" ]] && owner_start=""
        [[ -z "$owner_start" || -z "$current_start" || "$owner_start" == "$current_start" ]] || continue
        rmdir "$entry" 2>/dev/null || return 1
        rmdir "$lock_dir" 2>/dev/null || return 1
        return 0
    done
    return 1
}

_ugreen_log_trim_rotated_unlocked() {
    local file="$1" max_bytes="$2" size
    [[ -f "$file" ]] || return 0
    size=$(wc -c 2>/dev/null < "$file" || echo 0)
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    (( size > max_bytes )) || return 0
    if tail -c "$max_bytes" "$file" 2>/dev/null > "${file}.trim.$$"; then
        sed '1d' "${file}.trim.$$" 2>/dev/null > "${file}.clean.$$" || true
        if [[ -s "${file}.clean.$$" ]]; then
            mv -f "${file}.clean.$$" "$file" 2>/dev/null || true
        else
            printf '[oversized log record omitted during rotation]\n' 2>/dev/null > "$file" || true
        fi
    fi
    chmod 0640 "$file" 2>/dev/null || true
    rm -f "${file}.trim.$$" "${file}.clean.$$" 2>/dev/null || true
}

_ugreen_log_rotate_now_unlocked() {
    local file="$1" max_bytes="${2:-$UGREEN_LOG_MAX_BYTES}" keep="${3:-$UGREEN_LOG_KEEP_FILES}"
    local index
    [[ -L "$file" ]] && return 0
    [[ -f "$file" ]] || return 0
    [[ "$max_bytes" =~ ^[0-9]+$ ]] || max_bytes=5242880
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
    (( keep >= 1 )) || keep=1
    (( max_bytes >= 1024 )) || max_bytes=1024
    rm -f "${file}.${keep}" 2>/dev/null || true
    for ((index = keep - 1; index >= 1; index--)); do
        [[ -f "${file}.${index}" ]] && mv -f "${file}.${index}" "${file}.$((index + 1))" 2>/dev/null || true
    done
    if mv -f "$file" "${file}.1" 2>/dev/null; then
        _ugreen_log_trim_rotated_unlocked "${file}.1" "$max_bytes"
    fi
}

_ugreen_log_rotate_unlocked() {
    local file="$1" max_bytes="${2:-$UGREEN_LOG_MAX_BYTES}" keep="${3:-$UGREEN_LOG_KEEP_FILES}" size
    [[ -L "$file" ]] && return 0
    [[ -f "$file" ]] || return 0
    [[ "$max_bytes" =~ ^[0-9]+$ ]] || max_bytes=5242880
    (( max_bytes >= 1024 )) || max_bytes=1024
    size=$(wc -c 2>/dev/null < "$file" || echo 0)
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    (( size < max_bytes )) && return 0
    _ugreen_log_rotate_now_unlocked "$file" "$max_bytes" "$keep"
}

ugreen_log_rotate_file() {
    local file="${1:-$UGREEN_LOG_FILE}" max_bytes="${2:-$UGREEN_LOG_MAX_BYTES}" keep="${3:-$UGREEN_LOG_KEEP_FILES}"
    local dir lock fallback_lock
    dir="${file%/*}"
    [[ "$dir" != "$file" ]] || dir="."
    mkdir -p "$dir" 2>/dev/null || return 0
    [[ -L "$file" ]] && return 0
    lock="${file}.lock"
    if [[ "$UGREEN_LOG_USE_FLOCK" == "true" ]]; then
        {
            flock -w 1 9 2>/dev/null || return 0
            _ugreen_log_rotate_unlocked "$file" "$max_bytes" "$keep"
        } 2>/dev/null 9>>"$lock"
    else
        fallback_lock="${file}.lockdir"
        if _ugreen_log_acquire_fallback_lock "$fallback_lock" 20; then
            _ugreen_log_rotate_unlocked "$file" "$max_bytes" "$keep"
            _ugreen_log_release_fallback_lock "$fallback_lock"
        fi
    fi
    return 0
}

_ugreen_log_write_line() {
    local line="$1" file="$UGREEN_LOG_FILE" dir lock fallback_lock rc=1
    dir="${file%/*}"
    [[ "$dir" != "$file" ]] || dir="."
    if ! mkdir -p "$dir" 2>/dev/null; then
        [[ "$UGREEN_LOG_STDERR_FALLBACK" == "true" ]] && printf '%s\n' "$line" >&2
        return 1
    fi
    if [[ -L "$file" ]]; then
        [[ "$UGREEN_LOG_STDERR_FALLBACK" == "true" ]] && printf '%s\n' "$line" >&2
        return 1
    fi
    chmod 0750 "$dir" 2>/dev/null || true
    lock="${file}.lock"

    if [[ "$UGREEN_LOG_USE_FLOCK" == "true" ]]; then
        {
            if flock -w 1 9 2>/dev/null; then
                _ugreen_log_rotate_unlocked "$file"
                if printf '%s\n' "$line" 2>/dev/null >> "$file"; then rc=0; fi
                chmod 0640 "$file" 2>/dev/null || true
            else
                if printf '%s\n' "$line" 2>/dev/null >> "$file"; then rc=0; fi
            fi
        } 2>/dev/null 9>>"$lock"
    else
        fallback_lock="${file}.lockdir"
        if _ugreen_log_acquire_fallback_lock "$fallback_lock" 20; then
            _ugreen_log_rotate_unlocked "$file"
            if printf '%s\n' "$line" 2>/dev/null >> "$file"; then rc=0; fi
            chmod 0640 "$file" 2>/dev/null || true
            _ugreen_log_release_fallback_lock "$fallback_lock"
        else
            if printf '%s\n' "$line" 2>/dev/null >> "$file"; then rc=0; fi
        fi
    fi
    return "$rc"
}

_ugreen_log_prepare_raw_line() {
    local value="${1:-}" max_bytes="${2:-1048576}" configured_limit safe_limit
    [[ "$max_bytes" =~ ^[0-9]+$ ]] || max_bytes=1048576
    (( max_bytes >= 1024 )) || max_bytes=1024
    configured_limit="${UGREEN_LOG_FIELD_LIMIT:-4096}"
    [[ "$configured_limit" =~ ^[0-9]+$ ]] || configured_limit=4096
    safe_limit=$(((max_bytes - 128) / 4))
    (( safe_limit >= 64 )) || safe_limit=64
    (( configured_limit < safe_limit )) && safe_limit="$configured_limit"
    local UGREEN_LOG_FIELD_LIMIT="$safe_limit"
    _ugreen_log_sanitize "$value"
}

_ugreen_log_append_raw_line_unlocked() {
    local file="$1" max_bytes="$2" keep="$3" raw_line="$4" line size bytes
    [[ "$max_bytes" =~ ^[0-9]+$ ]] || max_bytes=1048576
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=2
    (( max_bytes >= 1024 )) || max_bytes=1024
    (( keep >= 1 )) || keep=1
    [[ -L "$file" ]] && return 1
    line=$(_ugreen_log_prepare_raw_line "$raw_line" "$max_bytes")
    bytes=$(printf '%s\n' "$line" | wc -c 2>/dev/null | tr -d ' ')
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes > max_bytes )); then
        line='[raw log line omitted: exceeds file limit]'
        bytes=$(printf '%s\n' "$line" | wc -c 2>/dev/null | tr -d ' ')
    fi
    size=$(wc -c 2>/dev/null < "$file" || echo 0)
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if (( size > 0 && size + bytes > max_bytes )); then
        _ugreen_log_rotate_now_unlocked "$file" "$max_bytes" "$keep"
    fi
    printf '%s\n' "$line" 2>/dev/null >> "$file" || return 1
    chmod 0640 "$file" 2>/dev/null || true
    return 0
}

_ugreen_log_stream_raw_unlocked() {
    local file="$1" max_bytes="$2" keep="$3" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" "$line" || true
    done
    return 0
}

_ugreen_log_stream_raw_until_sentinel_unlocked() {
    local file="$1" max_bytes="$2" keep="$3" sentinel="$4" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"$sentinel" ]]; then
            line="${line%"$sentinel"}"
            [[ -n "$line" ]] && \
                _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" "$line" || true
            return 0
        fi
        _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" "$line" || true
    done
    return 0
}

_ugreen_log_write_raw_line() {
    local file="$1" max_bytes="$2" keep="$3" line="$4" dir lock fallback_lock rc=1
    dir="${file%/*}"
    [[ "$dir" != "$file" ]] || dir="."
    mkdir -p "$dir" 2>/dev/null || return 1
    [[ -L "$file" ]] && return 1
    lock="${file}.lock"
    if [[ "$UGREEN_LOG_USE_FLOCK" == "true" ]]; then
        {
            flock -w 1 9 2>/dev/null || return 1
            _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" "$line"
            return $?
        } 2>/dev/null 9>>"$lock"
    fi
    fallback_lock="${file}.lockdir"
    _ugreen_log_acquire_fallback_lock "$fallback_lock" 20 || return 1
    if _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" "$line"; then rc=0; fi
    _ugreen_log_release_fallback_lock "$fallback_lock" || true
    return "$rc"
}

ugreen_log_stream_raw() {
    local file="$1" max_bytes="${2:-1048576}" keep="${3:-2}" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        _ugreen_log_write_raw_line "$file" "$max_bytes" "$keep" "$line" || true
    done
    return 0
}

_ugreen_log_run_raw_unlocked() {
    local file="$1" max_bytes="$2" keep="$3" operation="$4"
    shift 4
    local rc timestamp request sentinel
    local -a pipeline_status=()
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date 2>/dev/null || echo unknown-time)
    request="${UGREEN_REQUEST_ID:-none}"
    sentinel="__UGREEN_RAW_DONE_${BASHPID:-$$}_${RANDOM:-0}_$(ugreen_log_now_ms)__"
    _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" \
        "===== BEGIN ${timestamp} operation=${operation} request=${request} =====" || true
    if (
        if "$@" 9>&- 2>&1; then
            command_rc=0
        else
            command_rc=$?
        fi
        printf '%s\n' "$sentinel"
        exit "$command_rc"
    ) | _ugreen_log_stream_raw_until_sentinel_unlocked "$file" "$max_bytes" "$keep" "$sentinel" 9>&-; then
        pipeline_status=("${PIPESTATUS[@]}")
    else
        pipeline_status=("${PIPESTATUS[@]}")
    fi
    rc="${pipeline_status[0]:-1}"
    _ugreen_log_append_raw_line_unlocked "$file" "$max_bytes" "$keep" \
        "===== END operation=${operation} request=${request} rc=${rc} =====" || true
    return "$rc"
}

_ugreen_log_run_without_raw() {
    if "$@" >/dev/null 2>&1; then return 0; else return $?; fi
}

ugreen_log_run_raw() {
    local file="$1" max_bytes="$2" keep="$3" operation="$4"
    shift 4
    local dir lock fallback_lock rc flock_entered=false flock_acquired=false
    dir="${file%/*}"
    [[ "$dir" != "$file" ]] || dir="."
    mkdir -p "$dir" 2>/dev/null || {
        _ugreen_log_run_without_raw "$@"
        return $?
    }
    if [[ -L "$file" ]]; then
        _ugreen_log_run_without_raw "$@"
        return $?
    fi
    lock="${file}.lock"
    if [[ "$UGREEN_LOG_USE_FLOCK" == "true" ]]; then
        {
            flock_entered=true
            if flock -w 300 9 2>/dev/null; then
                flock_acquired=true
                if _ugreen_log_run_raw_unlocked "$file" "$max_bytes" "$keep" "$operation" "$@"; then
                    rc=0
                else
                    rc=$?
                fi
            fi
        } 2>/dev/null 9>>"$lock" || true
        if [[ "$flock_entered" != "true" || "$flock_acquired" != "true" ]]; then
            _ugreen_log_run_without_raw "$@"
            return $?
        fi
        return "$rc"
    fi
    fallback_lock="${file}.lockdir"
    if ! _ugreen_log_acquire_fallback_lock "$fallback_lock" 6000; then
        _ugreen_log_run_without_raw "$@"
        return $?
    fi
    if _ugreen_log_run_raw_unlocked "$file" "$max_bytes" "$keep" "$operation" "$@"; then rc=0; else rc=$?; fi
    _ugreen_log_release_fallback_lock "$fallback_lock"
    return "$rc"
}

ugreen_log_emit() {
    local level="${1^^}" event="${2:-event}" message="${3:-}"
    shift 3 || true
    _ugreen_log_should_emit "$level" || return 0

    local timestamp component pid request source caller_source function_name source_line line item key value lower context=""
    local caller_index=2 candidate stack_size
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date 2>/dev/null || echo unknown-time)
    component=$(_ugreen_log_sanitize "$UGREEN_LOG_COMPONENT")
    pid="${BASHPID:-$$}"
    request="${UGREEN_REQUEST_ID:-}"
    stack_size=${#FUNCNAME[@]}
    while (( caller_index + 1 < stack_size )); do
        candidate="${FUNCNAME[$caller_index]:-}"
        case "$candidate" in
            ugreen_log_*|_settings_log_*|_driver_log_*|_bios_log_*|_led_log*|log|log_limited)
                caller_index=$((caller_index + 1))
                ;;
            *) break ;;
        esac
    done
    caller_source="${BASH_SOURCE[$caller_index]:-${BASH_SOURCE[1]:-unknown}}"
    source="${caller_source##*/}"
    function_name="${FUNCNAME[$caller_index]:-main}"
    source_line="${BASH_LINENO[$((caller_index - 1))]:-${BASH_LINENO[0]:-0}}"
    event="${event//[^a-zA-Z0-9_.:-]/_}"

    line="[$timestamp] [$level] [$component] [pid=$pid]"
    [[ -n "$request" ]] && line+=" [request=$(_ugreen_log_sanitize "$request")]"
    line+=" [event=$event] [source=$(_ugreen_log_sanitize "${source}:${function_name}:${source_line}")]"
    line+=" msg=\"$(_ugreen_log_sanitize "$message")\""

    for item in "$@"; do
        if [[ "$item" == *=* ]]; then
            key="${item%%=*}"
            value="${item#*=}"
        else
            key="context"
            value="$item"
        fi
        key="${key//[^a-zA-Z0-9_.-]/_}"
        lower="${key,,}"
        case "$lower" in
            *password*|*passwd*|*token*|*secret*|*authorization*|*auth*|*cookie*|*api_key*|*apikey*|*credential*|*private_key*|*access_key*) value="<redacted>" ;;
        esac
        context+=" ${key}=\"$(_ugreen_log_sanitize "$value")\""
    done
    [[ -n "$context" ]] && line+=" |${context}"
    _ugreen_log_write_line "$line"
}

ugreen_log_debug() { ugreen_log_emit DEBUG "$@" || true; }
ugreen_log_info() { ugreen_log_emit INFO "$@" || true; }
ugreen_log_warn() { ugreen_log_emit WARN "$@" || true; }
ugreen_log_error() { ugreen_log_emit ERROR "$@" || true; }
ugreen_log_audit() {
    local configured_level="$UGREEN_LOG_LEVEL" rc=0
    UGREEN_LOG_LEVEL=DEBUG
    ugreen_log_emit INFO "$@" || rc=$?
    UGREEN_LOG_LEVEL="$configured_level"
    return "$rc"
}

ugreen_log_rate_limited() {
    local key="${1:-event}" interval="${2:-60}" level="${3:-WARN}" event="${4:-rate_limited}" message="${5:-}"
    shift 5 || true
    _ugreen_log_should_emit "$level" || return 0
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=60

    local state_root state_file state_lock safe_key now last=0 tmp emitted=false
    state_root="${RUNTIME_DIR:-${UGREEN_LOG_DIR}/.state}/log-rate"
    safe_key="${key//[^a-zA-Z0-9_.-]/_}"
    safe_key="${safe_key:0:96}"
    state_file="${state_root}/${safe_key}"
    now=$(date +%s 2>/dev/null || echo 0)
    mkdir -p "$state_root" 2>/dev/null || {
        ugreen_log_emit "$level" "$event" "$message" "$@" || true
        return 0
    }
    state_lock="${state_file}.lockdir"
    if ! _ugreen_log_acquire_fallback_lock "$state_lock" 240; then
        ugreen_log_emit "$level" "$event" "$message" "$@" || true
        return 0
    fi
    last=$(cat "$state_file" 2>/dev/null || echo 0)
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    if (( now >= last && now - last < interval )); then
        _ugreen_log_release_fallback_lock "$state_lock" || true
        return 0
    fi
    if ugreen_log_emit "$level" "$event" "$message" "$@"; then
        emitted=true
    fi
    if $emitted; then
        tmp="${state_file}.tmp.${BASHPID:-$$}.${RANDOM:-0}"
        if printf '%s\n' "$now" 2>/dev/null > "$tmp" && mv -f "$tmp" "$state_file" 2>/dev/null; then
            chmod 0750 "$state_root" 2>/dev/null || true
            chmod 0640 "$state_file" 2>/dev/null || true
        else
            rm -f "$tmp" 2>/dev/null || true
        fi
    fi
    _ugreen_log_release_fallback_lock "$state_lock" || true
    return 0
}

ugreen_log_shell_error() {
    local exit_code="${1:-1}" source_line="${2:-0}" command="${3:-unknown}"
    [[ "$UGREEN_LOG_TRAP_ACTIVE" == "true" ]] && return 0
    UGREEN_LOG_TRAP_ACTIVE=true
    ugreen_log_error "shell.command_failed" "Shell 命令执行失败" \
        "exit_code=$exit_code" "line=$source_line" "command=$command" "function=${FUNCNAME[1]:-main}"
    UGREEN_LOG_TRAP_ACTIVE=false
    return 0
}

ugreen_log_install_error_trap() {
    set -E
    trap 'ugreen_log_shell_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
}
