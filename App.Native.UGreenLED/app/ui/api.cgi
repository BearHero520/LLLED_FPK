#!/bin/bash
APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-/var/apps/${APP_NAME}}"
VAR_DIR="${TRIM_PKGVAR:-${APP_ROOT}/var}"

SERVER_DIR=""
for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
    [[ -f "${d}/led_daemon.sh" ]] && SERVER_DIR="$d" && break
done
SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"

LIB_DIR="${SERVER_DIR}/lib"
LOG_DIR="${VAR_DIR}/log"
UGREEN_LOG_COMPONENT="api"
UGREEN_LOG_FILE="${LOG_DIR}/app.log"
export LOG_DIR UGREEN_LOG_COMPONENT UGREEN_LOG_FILE
if [[ -f "${LIB_DIR}/logging.sh" ]] && \
    source "${LIB_DIR}/logging.sh" 2>/dev/null && \
    declare -F ugreen_log_make_request_id >/dev/null && \
    declare -F ugreen_log_error >/dev/null; then
    :
else
    UGREEN_LOG_FILE="${LOG_DIR}/app.log"
    UGREEN_LOG_LEVEL="INFO"
    _ugreen_api_fallback_sanitize() {
        local value="${1:-}" code octal control
        for code in {1..8} 11 12 {14..31} 127; do
            printf -v octal '%03o' "$code"
            printf -v control '%b' "\\${octal}"
            value="${value//$control/}"
        done
        value="${value//$'\r'/ }"
        value="${value//$'\n'/ }"
        value="${value//$'\t'/ }"
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        printf '%s' "${value:0:1024}"
    }
    _ugreen_api_fallback_emit() {
        local level="${1:-ERROR}" event="${2:-fallback.error}" message="${3:-}" item key value lower context=""
        shift 3 || true
        event="${event//[^a-zA-Z0-9_.:-]/_}"
        for item in "$@"; do
            if [[ "$item" == *=* ]]; then key="${item%%=*}"; value="${item#*=}"; else key="context"; value="$item"; fi
            key="${key//[^a-zA-Z0-9_.-]/_}"
            lower="${key,,}"
            case "$lower" in
                *password*|*passwd*|*token*|*secret*|*authorization*|*cookie*) value="<redacted>" ;;
            esac
            context+=" ${key}=\"$(_ugreen_api_fallback_sanitize "$value")\""
        done
        mkdir -p "$LOG_DIR" 2>/dev/null || return 0
        chmod 0750 "$LOG_DIR" 2>/dev/null || true
        printf '[%s] [%s] [api] [pid=%s] [request=%s] [event=%s] [source=api.cgi:fallback:0] msg="%s"%s\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo unknown-time)" "$level" "${BASHPID:-$$}" \
            "$(_ugreen_api_fallback_sanitize "${UGREEN_REQUEST_ID:-unassigned}")" "$event" \
            "$(_ugreen_api_fallback_sanitize "$message")" "$context" >> "$UGREEN_LOG_FILE" 2>/dev/null || true
        chmod 0640 "$UGREEN_LOG_FILE" 2>/dev/null || true
        return 0
    }
    ugreen_log_debug() { :; }
    ugreen_log_info() { :; }
    ugreen_log_warn() { _ugreen_api_fallback_emit WARN "$@"; }
    ugreen_log_error() { _ugreen_api_fallback_emit ERROR "$@"; }
    ugreen_log_audit() { _ugreen_api_fallback_emit INFO "$@"; }
    ugreen_log_configure_from_settings() { :; }
    ugreen_log_make_request_id() { printf 'req-%s-%s\n' "$(date +%s 2>/dev/null || echo 0)" "${BASHPID:-$$}"; }
    ugreen_log_now_ms() { printf '%s000\n' "$(date +%s 2>/dev/null || echo 0)"; }
    ugreen_log_redact_query() { printf '%s' "${1:-}"; }
    ugreen_log_mask_address() { printf '%s' "${1:-}"; }
    ugreen_log_rotate_file() { :; }
    ugreen_log_run_raw() { shift 4; "$@" >/dev/null 2>&1; }
fi
if ! declare -F ugreen_log_mask_address >/dev/null; then
    ugreen_log_mask_address() { printf '%s' "${1:-}"; }
fi

if [[ "${HTTP_X_REQUEST_ID:-}" =~ ^[A-Za-z0-9._:-]{8,64}$ ]]; then
    UGREEN_REQUEST_ID="$HTTP_X_REQUEST_ID"
else
    UGREEN_REQUEST_ID=$(ugreen_log_make_request_id)
fi
export UGREEN_REQUEST_ID

API_BOOTSTRAP_FAILED=false
API_BOOTSTRAP_ERROR=""
if [[ ! -f "${LIB_DIR}/app_paths.sh" ]]; then
    API_BOOTSTRAP_FAILED=true
    API_BOOTSTRAP_ERROR="app_paths.sh is missing"
elif ! source "${LIB_DIR}/app_paths.sh" 2>/dev/null; then
    API_BOOTSTRAP_FAILED=true
    API_BOOTSTRAP_ERROR="app_paths.sh failed to load"
elif ! declare -F ugreen_resolve_runtime >/dev/null; then
    API_BOOTSTRAP_FAILED=true
    API_BOOTSTRAP_ERROR="ugreen_resolve_runtime is unavailable"
elif ! ugreen_resolve_runtime; then
    API_BOOTSTRAP_FAILED=true
    API_BOOTSTRAP_ERROR="runtime directory resolution failed"
fi
RUNTIME_DIR="${RUNTIME_DIR:-${VAR_DIR}/run}"
export RUNTIME_DIR
if $API_BOOTSTRAP_FAILED; then
    ugreen_log_error "api.bootstrap_failed" "API 启动初始化失败" \
        "error=$API_BOOTSTRAP_ERROR" "library_dir=$LIB_DIR" "runtime_dir=$RUNTIME_DIR"
fi

SETTINGS_FILE="${VAR_DIR}/settings.conf"
PID_FILE="${RUNTIME_DIR}/led_daemon.pid"
DISK_STATUS_FILE="${RUNTIME_DIR}/disk_status.tsv"
NET_STATUS_FILE="${RUNTIME_DIR}/net_status.tsv"
UPDATE_CACHE_FILE="${RUNTIME_DIR}/update_check.cache"
UPDATE_REPOSITORY="BearHero520/LLLED_FPK"
UPDATE_LATEST_URL="https://github.com/${UPDATE_REPOSITORY}/releases/latest"
UPDATE_API_URL="https://api.github.com/repos/${UPDATE_REPOSITORY}/releases/latest"
UPDATE_CACHE_TTL=21600
UGREEN_CLI="${UGREEN_CLI_OVERRIDE:-}"
if [[ -z "$UGREEN_CLI" ]]; then
    for c in "${SERVER_DIR}/bin/ugreen_leds_cli" "${APP_ROOT}/target/server/bin/ugreen_leds_cli"; do
        [[ -x "$c" ]] && UGREEN_CLI="$c" && break
    done
fi

export TARGET="$APP_ROOT" SERVER_DIR
export UGREEN_CLI LED_API_CACHE_DIR="${RUNTIME_DIR}/led_cache" DISK_IO_CACHE_DIR="${RUNTIME_DIR}/disk_io"
export NET_SPEED_CACHE_FILE="${RUNTIME_DIR}/net_speed.cache" NET_STATE_CACHE_FILE="${RUNTIME_DIR}/net_state.cache"

if ! $API_BOOTSTRAP_FAILED; then
    for library in settings hardware_profile system_info bios_control fan_telemetry driver_manager led_api disk_map disk_state net_state led_apply; do
        if ! source "${LIB_DIR}/${library}.sh" 2>/dev/null; then
            API_BOOTSTRAP_FAILED=true
            API_BOOTSTRAP_ERROR="dependency library failed to load: ${library}.sh"
            ugreen_log_error "api.library_source_failed" "API 依赖库加载失败" "library=$library" "path=${LIB_DIR}/${library}.sh"
        fi
    done
fi

QUERY_STRING="${QUERY_STRING:-}"
REQUEST_METHOD="${REQUEST_METHOD:-GET}"
POST_DATA=""
POST_TOO_LARGE=false
if [[ "$REQUEST_METHOD" == "POST" && "${CONTENT_LENGTH:-0}" =~ ^[0-9]+$ && "${CONTENT_LENGTH:-0}" -gt 65536 ]]; then
    POST_TOO_LARGE=true
elif [[ "$REQUEST_METHOD" == "POST" && "${CONTENT_LENGTH:-0}" =~ ^[0-9]+$ ]]; then
    POST_DATA=$(head -c "${CONTENT_LENGTH:-0}")
fi

# fnOS/nginx 传参方式不一：PATH_INFO 可能是 /status、status、或整段 .../api.cgi/status
ugreen_api_path() {
    local p="" uri="" c
    for c in "${PATH_INFO:-}" "${REQUEST_URI:-}" "${REDIRECT_URL:-}" "${DOCUMENT_URI:-}"; do
        [[ -z "$c" ]] && continue
        uri="${c%%\?*}"
        case "$uri" in
            */api.cgi/*) p="/${uri#*api.cgi/}"; break ;;
            */api.cgi) p="/"; break ;;
            *)
                [[ "$uri" == /* ]] && p="$uri" || p="/${uri}"
                break
                ;;
        esac
    done
    [[ -z "$p" ]] && p="/"
    [[ "$p" != /* ]] && p="/$p"
    echo "$p"
}
API_PATH="$(ugreen_api_path)"

json_str() {
    local s="$1" code octal control
    for code in {1..8} 11 12 {14..31} 127; do
        printf -v octal '%03o' "$code"
        printf -v control '%b' "\\${octal}"
        s="${s//$control/}"
    done
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

api_http_reason() {
    case "${1:-500}" in
        200) printf '%s' "OK" ;;
        400) printf '%s' "Bad Request" ;;
        404) printf '%s' "Not Found" ;;
        405) printf '%s' "Method Not Allowed" ;;
        409) printf '%s' "Conflict" ;;
        413) printf '%s' "Payload Too Large" ;;
        503) printf '%s' "Service Unavailable" ;;
        *) printf '%s' "Internal Server Error" ;;
    esac
}

api_http_status_for_response() {
    local response="${1:-}" handler_rc="${2:-0}"
    if [[ "$handler_rc" != "0" ]]; then
        printf '%s' 500
    elif [[ $response != '{"ok":false'* ]]; then
        printf '%s' 200
    elif [[ "$response" == *'"error":"method not allowed"'* ]]; then
        printf '%s' 405
    elif [[ "$response" == *'"error":"unknown"'* ]]; then
        printf '%s' 404
    elif [[ "$response" == *"too large"* ]]; then
        printf '%s' 413
    elif [[ "$response" == *"会话已结束"* || "$response" == *"session ended"* ]]; then
        printf '%s' 409
    elif [[ "$response" == *"unavailable"* || "$response" == *"不可用"* || "$response" == *"尚未就绪"* ]]; then
        printf '%s' 503
    elif [[ "$response" == *"initialization failed"* || "$response" == *"empty API response"* || \
        "$response" == *"failed"* || "$response" == *"失败"* || "$response" == *"无法"* || \
        "$response" == *"symlink is not allowed"* ]]; then
        printf '%s' 500
    else
        printf '%s' 400
    fi
}

url_decode() {
    local value="${1//+/ }" decoded="" hex byte

    while [[ -n "$value" ]]; do
        if [[ "${value:0:1}" == "%" ]]; then
            hex="${value:1:2}"
            [[ "$hex" =~ ^[0-9A-Fa-f]{2}$ && "$hex" != "00" ]] || return 1
            printf -v byte '%b' "\\x${hex}"
            decoded+="$byte"
            value="${value:3}"
        else
            decoded+="${value:0:1}"
            value="${value:1}"
        fi
    done

    printf '%s' "$decoded"
}

query_value() {
    local key="$1" query="$QUERY_STRING" pair name value

    while :; do
        pair="${query%%&*}"
        if [[ "$pair" == "$query" ]]; then
            query=""
        else
            query="${query#*&}"
        fi

        name="${pair%%=*}"
        if [[ "$name" == "$key" && "$pair" == *=* ]]; then
            value="${pair#*=}"
            url_decode "$value" || return 1
            return 0
        fi
        [[ -z "$query" ]] && return 0
    done
}

current_app_version() {
    local manifest_file version
    for manifest_file in \
        "${APP_ROOT}/manifest" \
        "${APP_ROOT}/target/manifest" \
        "${APP_ROOT}/../manifest" \
        "/var/apps/@appcenter/${APP_NAME}/manifest"; do
        [[ -f "$manifest_file" ]] || continue
        version=$(sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$manifest_file" | head -n 1)
        version="${version//[[:space:]]/}"
        [[ -n "$version" ]] && { printf '%s' "$version"; return; }
    done
    printf '%s' "unknown"
}

fetch_latest_release_tag() {
    local response="" tag="" effective_url="" location=""
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -fsSL --retry 2 --connect-timeout 5 --max-time 20 \
            -H 'Accept: application/vnd.github+json' -H 'User-Agent: UGreenLED-fnOS' \
            "$UPDATE_API_URL" 2>/dev/null || true)
        tag=$(printf '%s\n' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        if [[ -z "$tag" ]]; then
            effective_url=$(curl -fsSL --retry 1 --connect-timeout 5 --max-time 20 -o /dev/null \
                -w '%{url_effective}' "$UPDATE_LATEST_URL" 2>/dev/null || true)
            tag="${effective_url##*/}"
        fi
    elif command -v wget >/dev/null 2>&1; then
        response=$(wget -qO- --timeout=20 --header='Accept: application/vnd.github+json' \
            --header='User-Agent: UGreenLED-fnOS' "$UPDATE_API_URL" 2>/dev/null || true)
        tag=$(printf '%s\n' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        if [[ -z "$tag" ]]; then
            location=$(wget --spider --server-response --max-redirect=10 --timeout=20 "$UPDATE_LATEST_URL" 2>&1 | \
                sed -n 's/^[[:space:]]*[Ll]ocation:[[:space:]]*\([^[:space:]]*\).*/\1/p' | tail -n 1)
            effective_url="${location//$'\r'/}"
            tag="${effective_url##*/}"
        fi
    else
        return 1
    fi

    [[ "$tag" =~ ^v?[0-9]+([.][0-9]+){1,3}([._-][0-9A-Za-z.-]+)?$ ]] || return 1
    printf '%s' "$tag"
}

update_check_json() {
    local force="$1" current latest_tag="" latest_version="" now cached_tag="" cached_at=0
    local release_url download_url cache_age
    current=$(current_app_version)
    now=$(date +%s)

    if [[ "$force" != "1" && -f "$UPDATE_CACHE_FILE" ]]; then
        IFS='|' read -r cached_tag cached_at < "$UPDATE_CACHE_FILE"
        cached_at="${cached_at:-0}"
        if [[ "$cached_at" =~ ^[0-9]+$ ]]; then
            cache_age=$((now - cached_at))
            if (( cache_age >= 0 && cache_age <= UPDATE_CACHE_TTL )); then
                latest_tag="$cached_tag"
            fi
        fi
    fi

    if [[ -z "$latest_tag" ]]; then
        latest_tag=$(fetch_latest_release_tag 2>/dev/null || true)
        if [[ -n "$latest_tag" ]]; then
            printf '%s|%s\n' "$latest_tag" "$now" > "${UPDATE_CACHE_FILE}.tmp" 2>/dev/null && \
                mv "${UPDATE_CACHE_FILE}.tmp" "$UPDATE_CACHE_FILE" 2>/dev/null || true
        fi
    fi

    if [[ -z "$latest_tag" ]]; then
        printf '{"ok":true,"reachable":false,"current_version":"%s","checked_at":%s,"error":"无法连接 GitHub Release"}' \
            "$(json_str "$current")" "$now"
        return
    fi

    latest_version="${latest_tag#v}"
    release_url="https://github.com/${UPDATE_REPOSITORY}/releases/tag/${latest_tag}"
    download_url="https://github.com/${UPDATE_REPOSITORY}/releases/download/${latest_tag}/App.Native.UGreenLED.fpk"
    printf '{"ok":true,"reachable":true,"current_version":"%s","latest_version":"%s","latest_tag":"%s","release_url":"%s","download_url":"%s","checked_at":%s}' \
        "$(json_str "$current")" "$(json_str "$latest_version")" "$(json_str "$latest_tag")" \
        "$(json_str "$release_url")" "$(json_str "$download_url")" "$now"
}

lab_mapping_resume_control() {
    lab_mapping_session_end
    led_clear_cache 2>/dev/null
    rm -f "$DISK_STATUS_FILE"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
    else
        bash "${SERVER_DIR}/led_daemon.sh" once >/dev/null 2>&1 || true
    fi
}

lab_mapping_status_json() {
    local message="${1:-}" active=false mode slot first dev hctl serial model size transport led
    local position=0 position_supported identity_supported position_led identity_led product profile auto_led physical_position
    declare -A position_led_map=() identity_led_map=()
    lab_mapping_session_active && active=true
    mode=$(disk_mapping_mode "$SETTINGS_FILE")
    product=$(hardware_detected_product_name)
    profile=$(hardware_profile_key)

    DISK_LED_MAP=()
    disk_load_position_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || true
    for dev in "${!DISK_LED_MAP[@]}"; do position_led_map["$dev"]="${DISK_LED_MAP[$dev]}"; done
    DISK_LED_MAP=()
    disk_load_identity_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || true
    for dev in "${!DISK_LED_MAP[@]}"; do identity_led_map["$dev"]="${DISK_LED_MAP[$dev]}"; done
    disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || DISK_LED_MAP=()

    printf '{"ok":true,"active":%s,"mode":"%s","product_name":"%s","profile":"%s","session_ttl":%s,"slots":[' \
        "$active" "$(json_str "$mode")" "$(json_str "$product")" "$(json_str "$profile")" "$LAB_MAPPING_SESSION_TTL"
    first=1
    while IFS= read -r slot; do
        [[ -n "$slot" ]] || continue
        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '{"led":"%s","position":%s}' "$(json_str "$slot")" "${slot#disk}"
    done < <(disk_available_slots)
    printf '],"disks":['
    first=1
    while IFS='|' read -r dev hctl serial model size transport; do
        [[ -n "$dev" ]] || continue
        position=$((position + 1))
        auto_led=$(disk_guess_led_by_hctl "$hctl")
        physical_position="$position"
        [[ "$auto_led" =~ ^disk([1-9][0-9]*)$ ]] && physical_position="${BASH_REMATCH[1]}"
        [[ $first -eq 0 ]] && printf ','
        first=0
        led="${DISK_LED_MAP[$dev]:-}"
        position_led="${position_led_map[$dev]:-}"
        identity_led="${identity_led_map[$dev]:-}"
        position_supported=false
        identity_supported=false
        [[ "$hctl" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] && position_supported=true
        [[ -n "$serial" ]] && identity_supported=true
        printf '{"position":%s,"device":"%s","hctl":"%s","serial":"%s","model":"%s","size":"%s","transport":"%s","led":"%s","position_led":"%s","identity_led":"%s","supported":%s,"position_supported":%s,"identity_supported":%s}' \
            "$physical_position" \
            "$(json_str "$dev")" "$(json_str "$hctl")" "$(json_str "$serial")" "$(json_str "$model")" \
            "$(json_str "$size")" "$(json_str "$transport")" "$(json_str "$led")" \
            "$(json_str "$position_led")" "$(json_str "$identity_led")" \
            "$position_supported" "$position_supported" "$identity_supported"
    done < <(disk_inventory_rows | sort -t'|' -k2,2V)
    printf ']'
    [[ -n "$message" ]] && printf ',"message":"%s"' "$(json_str "$message")"
    printf '}'
}

runtime_file_fresh() {
    local f="$1" max_age="${2:-30}" modified now
    [[ -f "$f" ]] || return 1
    modified=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    now=$(date +%s)
    (( now - modified <= max_age ))
}

hardware_status_json() {
    local product profile profile_name support protocol protocol_configured disk_count netdev_count configured active
    local system_hostname system_os system_kernel system_uptime system_cpu system_threads load_values load1 load5 load15
    local memory_values memory_total memory_used memory_percent cpu_temp cpu_temp_json=null
    local cli_ready=false driver_loaded=false sysfs_ready=false dkms_ready=false headers_ready=false conflict=false dkms_installed=false dkms_registered=false driver_managed=false driver_supported=true
    local it87_loaded=false led_plugin_conflict=false led_plugin_modules="" module_name _module_rest
    product=$(hardware_detected_product_name)
    profile=$(hardware_profile_key)
    profile_name=$(hardware_profile_display_name "$profile")
    support=$(hardware_support_level "$profile")
    protocol=$(hardware_write_protocol "$profile")
    protocol_configured=$(settings_get "$SETTINGS_FILE" hardware write_protocol "auto")
    disk_count=$(hardware_disk_count "$profile")
    netdev_count=$(hardware_netdev_count "$profile")
    configured=$(led_backend_configured)
    active=$(led_backend_name)
    led_cli_available && cli_ready=true
    driver_module_loaded && driver_loaded=true
    driver_sysfs_ready && sysfs_ready=true
    driver_dkms_ready && dkms_ready=true
    driver_headers_ready && headers_ready=true
    driver_vendor_conflict && conflict=true
    driver_dkms_installed 2>/dev/null && dkms_installed=true
    driver_dkms_registered 2>/dev/null && dkms_registered=true
    driver_managed_by_app && driver_managed=true
    declare -F hardware_driver_supported >/dev/null && ! hardware_driver_supported "$profile" && driver_supported=false
    if [[ -r /proc/modules ]]; then
        while read -r module_name _module_rest; do
            case "$module_name" in
                it87) it87_loaded=true ;;
                leds_mcu*|led_ugreen|ugreen_leds|leds_ugreen|n76e003*)
                    led_plugin_conflict=true
                    led_plugin_modules="${led_plugin_modules}${led_plugin_modules:+,}${module_name}"
                    ;;
            esac
        done < /proc/modules
    fi
    [[ "$disk_count" =~ ^[0-9]+$ ]] || disk_count=0
    system_hostname=$(system_info_hostname)
    system_os=$(system_info_os_name)
    system_kernel=$(system_info_kernel)
    system_uptime=$(system_info_uptime_seconds)
    system_cpu=$(system_info_cpu_model)
    system_threads=$(system_info_cpu_threads)
    load_values=$(system_info_load_averages)
    IFS='|' read -r load1 load5 load15 <<< "$load_values"
    memory_values=$(system_info_memory_metrics)
    IFS='|' read -r memory_total memory_used memory_percent <<< "$memory_values"
    cpu_temp=$(system_info_cpu_temperature)
    [[ "$system_uptime" =~ ^[0-9]+$ ]] || system_uptime=0
    [[ "$system_threads" =~ ^[0-9]+$ ]] || system_threads=0
    [[ "$load1" =~ ^[0-9]+([.][0-9]+)?$ ]] || load1=0
    [[ "$load5" =~ ^[0-9]+([.][0-9]+)?$ ]] || load5=0
    [[ "$load15" =~ ^[0-9]+([.][0-9]+)?$ ]] || load15=0
    [[ "$memory_total" =~ ^[0-9]+$ ]] || memory_total=0
    [[ "$memory_used" =~ ^[0-9]+$ ]] || memory_used=0
    [[ "$memory_percent" =~ ^[0-9]+$ ]] || memory_percent=0
    [[ "$cpu_temp" =~ ^[0-9]+([.][0-9]+)?$ ]] && cpu_temp_json="$cpu_temp"
    printf '{"ok":true,"product_name":"%s","profile":"%s","profile_name":"%s","support":"%s","cli_version":"%s","write_protocol":"%s","write_protocol_configured":"%s","disk_count":%s,"netdev_count":%s,"backend_configured":"%s","backend_active":"%s","cli_ready":%s,"driver_loaded":%s,"sysfs_ready":%s,"dkms_ready":%s,"headers_ready":%s,"driver_conflict":%s,"it87_loaded":%s,"led_plugin_conflict":%s,"led_plugin_modules":"%s","dkms_installed":%s,"dkms_registered":%s,"driver_managed":%s,"driver_supported":%s,"kernel":"%s","system_hostname":"%s","system_os":"%s","system_uptime_seconds":%s,"system_cpu_model":"%s","system_cpu_threads":%s,"system_load_1":%s,"system_load_5":%s,"system_load_15":%s,"system_memory_total_mb":%s,"system_memory_used_mb":%s,"system_memory_percent":%s,"system_cpu_temp_c":%s}' \
        "$(json_str "$product")" "$(json_str "$profile")" "$(json_str "$profile_name")" "$(json_str "$support")" \
        "$(json_str "$UGREEN_CLI_RELEASE")" "$(json_str "$protocol")" "$(json_str "$protocol_configured")" "$disk_count" "$netdev_count" "$(json_str "$configured")" "$(json_str "$active")" \
        "$cli_ready" "$driver_loaded" "$sysfs_ready" "$dkms_ready" "$headers_ready" "$conflict" "$it87_loaded" "$led_plugin_conflict" "$(json_str "$led_plugin_modules")" "$dkms_installed" "$dkms_registered" "$driver_managed" "$driver_supported" "$(json_str "$system_kernel")" \
        "$(json_str "$system_hostname")" "$(json_str "$system_os")" "$system_uptime" "$(json_str "$system_cpu")" "$system_threads" "$load1" "$load5" "$load15" \
        "$memory_total" "$memory_used" "$memory_percent" "$cpu_temp_json"
}

bios_status_json() {
    local message="${1:-}" chip_id="" error="" fan_error="" startup_error="" wol_error="" fan_curve="" telemetry_at=0 risk_acknowledged=false
    bios_read_status >/dev/null 2>&1 || true
    telemetry_at=$(date +%s 2>/dev/null || echo 0)
    fan_telemetry_append_bios_status "$telemetry_at" >/dev/null 2>&1 || true
    if [[ "$BIOS_CHIP_ID" =~ ^[0-9]+$ ]]; then
        printf -v chip_id '0x%04x' "$BIOS_CHIP_ID"
    fi
    error="$BIOS_LAST_ERROR"
    fan_error="$BIOS_FAN_ERROR"
    startup_error="$BIOS_STARTUP_ERROR"
    wol_error="$BIOS_WOL_ERROR"
    fan_curve=$(bios_fan_curve_status_json)
    bios_write_risk_acknowledged && risk_acknowledged=true
    printf '{"ok":true,"supported":%s,"available":%s,"startup_available":%s,"wol_available":%s,"model":"%s","experimental":%s,"min_pwm":%s,"fan_write_target":"%s","cpu_fan_present":%s,"fan_mode_writable":%s,"pwm_readable":%s,"write_confirmation_required":%s,"write_confirmation_acknowledged":%s,"direct_fan_fallback":%s,"product_name":"%s","backend":"%s","chip_id":"%s","revision":%s,"cpu_pwm":%s,"sys_pwm":%s,"sys2_pwm":%s,"cpu_rpm":%s,"sys_rpm":%s,"sys2_rpm":%s,"cpu_manual":%s,"sys_manual":%s,"sys2_manual":%s,"startup":"%s","wol":"%s","error":"%s","fan_error":"%s","startup_error":"%s","wol_error":"%s"' \
        "$BIOS_SUPPORTED" "$BIOS_AVAILABLE" "$BIOS_STARTUP_AVAILABLE" "$BIOS_WOL_AVAILABLE" "$(json_str "$BIOS_MODEL")" "$BIOS_EXPERIMENTAL" "${BIOS_MIN_PWM:-0}" "$(json_str "$BIOS_FAN_WRITE_TARGET")" \
        "$BIOS_CPU_FAN_PRESENT" "$BIOS_FAN_MODE_WRITABLE" "$BIOS_PWM_READABLE" "$BIOS_WRITE_CONFIRMATION_REQUIRED" "$risk_acknowledged" "$BIOS_DIRECT_FAN_FALLBACK" "$(json_str "$BIOS_PRODUCT_NAME")" "$(json_str "$BIOS_BACKEND")" \
        "$(json_str "$chip_id")" "${BIOS_REVISION:-0}" "${BIOS_CPU_PWM:--1}" "${BIOS_SYS_PWM:--1}" "${BIOS_SYS2_PWM:--1}" \
        "${BIOS_CPU_RPM:-0}" "${BIOS_SYS_RPM:-0}" "${BIOS_SYS2_RPM:-0}" "$BIOS_CPU_MANUAL" "$BIOS_SYS_MANUAL" "$BIOS_SYS2_MANUAL" \
        "$(json_str "$BIOS_STARTUP_POLICY")" "$(json_str "$BIOS_WOL_POLICY")" "$(json_str "$error")" "$(json_str "$fan_error")" "$(json_str "$startup_error")" "$(json_str "$wol_error")"
    printf ',"fan_curve":%s' "$fan_curve"
    printf ',"power_schedule":{"available":%s,"enabled":%s,"days":"%s","wake_time":"%s","shutdown_time":"%s","rtc_epoch":%s,"error":"%s"}' \
        "$BIOS_POWER_SCHEDULE_AVAILABLE" "$BIOS_POWER_SCHEDULE_ENABLED" \
        "$(json_str "$BIOS_POWER_SCHEDULE_DAYS")" "$(json_str "$BIOS_POWER_SCHEDULE_WAKE_TIME")" \
        "$(json_str "$BIOS_POWER_SCHEDULE_SHUTDOWN_TIME")" "${BIOS_RTC_WAKE_EPOCH:-0}" \
        "$(json_str "$BIOS_POWER_SCHEDULE_ERROR")"
    printf ',"telemetry":%s' "$(fan_telemetry_current_json "$telemetry_at")"
    [[ -n "$message" ]] && printf ',"message":"%s"' "$(json_str "$message")"
    printf '}'
}

bios_write_confirmation_token() {
    if bios_write_confirmation_required; then
        printf '%s\n' 'firmware-reversed'
    elif bios_direct_fan_fallback_active; then
        printf '%s\n' 'direct-superio'
    fi
}

bios_write_risk_acknowledgement_value() {
    local profile token
    profile=$(bios_detected_profile)
    token=$(bios_write_confirmation_token)
    case "$profile" in
        dxp4800|dxp4800_plus|dxp4800_pro|dxp4800s|dxp480t_plus|dxp6800pro) ;;
        *) return 1 ;;
    esac
    [[ -n "$token" ]] || return 1
    printf '%s\n' "v1:${token}:${profile}"
}

bios_write_risk_acknowledged() {
    local expected accepted
    bios_write_confirmation_required || return 0
    expected=$(bios_write_risk_acknowledgement_value) || return 1
    accepted=$(settings_get "$SETTINGS_FILE" bios write_risk_acknowledgement "")
    [[ "$accepted" == "$expected" ]]
}

bios_remember_write_risk() {
    local expected
    expected=$(bios_write_risk_acknowledgement_value) || return 1
    settings_set "$SETTINGS_FILE" bios write_risk_acknowledgement "$expected"
}

bios_telemetry_json() {
    local range="${1:-1m}" seconds=60 bucket_seconds=10 telemetry_at=0 history current model
    case "$range" in
        1m) seconds=60; bucket_seconds=10 ;;
        1h) seconds=3600; bucket_seconds=60 ;;
        24h) seconds=86400; bucket_seconds=1800 ;;
        *) printf '{"ok":false,"error":"invalid telemetry range"}'; return 0 ;;
    esac
    model=$(bios_detected_profile)
    current=$(fan_telemetry_latest_json "$model")
    if [[ -z "$current" ]]; then
        bios_read_status >/dev/null 2>&1 || true
        model="$BIOS_MODEL"
        telemetry_at=$(date +%s 2>/dev/null || echo 0)
        fan_telemetry_append_bios_status "$telemetry_at" >/dev/null 2>&1 || true
        current=$(fan_telemetry_current_json "$telemetry_at")
    fi
    history=$(fan_telemetry_history_json "$seconds" "$model" "$bucket_seconds")
    printf '{"ok":true,"range":"%s","sample_interval_seconds":%s,"history":%s,"current":%s}' \
        "$range" "$bucket_seconds" "$history" "$current"
}

bios_write_confirmation_valid() {
    local confirmation="$(query_value confirm)"
    local expected="$(bios_write_confirmation_token)"
    [[ -z "$expected" || "$confirmation" == "$expected" ]]
}

application_logs_json() {
    local requested_lines level file content="" size=0 updated=0 clipped=false content_bytes=0
    requested_lines=$(query_value lines)
    level=$(query_value level)
    file="$UGREEN_LOG_FILE"
    [[ "$requested_lines" =~ ^[0-9]+$ ]] || requested_lines=300
    (( requested_lines < 20 )) && requested_lines=20
    (( requested_lines > 1000 )) && requested_lines=1000
    case "${level,,}" in
        debug|info|warn|error) level="${level^^}" ;;
        *) level="all" ;;
    esac

    if [[ -L "$file" ]]; then
        echo '{"ok":false,"error":"log file symlink is not allowed"}'
        return 0
    fi
    if [[ -f "$file" ]]; then
        if [[ "$level" == "all" ]]; then
            content=$(tail -n "$requested_lines" "$file" 2>/dev/null | tail -c 131072 || true)
        else
            content=$(grep -F "[$level]" "$file" 2>/dev/null | tail -n "$requested_lines" | tail -c 131072 || true)
        fi
        size=$(wc -c < "$file" 2>/dev/null || echo 0)
        updated=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    fi
    content_bytes=$(printf '%s' "$content" | wc -c | tr -d ' ')
    if [[ "$content_bytes" =~ ^[0-9]+$ ]] && (( content_bytes >= 131072 )); then
        content="${content#*$'\n'}"
        clipped=true
    fi
    printf '{"ok":true,"source":"application","level":"%s","requested_lines":%s,"size_bytes":%s,"updated_at":%s,"clipped":%s,"write_level":"%s","content":"%s"}' \
        "$(json_str "$level")" "$requested_lines" "${size:-0}" "${updated:-0}" "$clipped" \
        "$(json_str "${UGREEN_LOG_LEVEL,,}")" "$(json_str "$content")"
}

hardware_diagnostics_json() {
    local collector="${SERVER_DIR}/nas_hardware_collect.sh"
    local report_file bundle_file report_size=0 bundle_size=0 collector_rc=0 clipped=false
    local filename content stamp

    if [[ ! -f "$collector" || -L "$collector" ]]; then
        echo '{"ok":false,"error":"hardware diagnostics collector unavailable"}'
        return 0
    fi
    mkdir -p "$RUNTIME_DIR" 2>/dev/null || {
        echo '{"ok":false,"error":"hardware diagnostics runtime unavailable"}'
        return 0
    }
    report_file=$(mktemp "$RUNTIME_DIR/hardware-report.XXXXXX" 2>/dev/null) || {
        echo '{"ok":false,"error":"failed to create hardware diagnostics report"}'
        return 0
    }
    bundle_file=$(mktemp "$RUNTIME_DIR/hardware-bundle.XXXXXX" 2>/dev/null) || {
        rm -f "$report_file" 2>/dev/null || true
        echo '{"ok":false,"error":"failed to create hardware diagnostics bundle"}'
        return 0
    }
    chmod 0600 "$report_file" "$bundle_file" 2>/dev/null || true

    if command -v timeout >/dev/null 2>&1; then
        timeout 60 bash "$collector" --stdout > "$report_file" 2>&1 || collector_rc=$?
    else
        bash "$collector" --stdout > "$report_file" 2>&1 || collector_rc=$?
    fi
    report_size=$(wc -c < "$report_file" 2>/dev/null || echo 0)
    [[ "$report_size" =~ ^[0-9]+$ ]] || report_size=0
    (( report_size > 524288 )) && clipped=true

    ugreen_log_audit "hardware.diagnostics_collected" "已通过 Web 生成硬件诊断包" \
        "collector_exit_code=$collector_rc" "collector_bytes=$report_size"

    {
        printf 'UGREEN LED diagnostic bundle\n'
        printf 'bundle_version=1\n'
        printf 'generated_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo unknown)"
        printf 'collector_exit_code=%s\n' "$collector_rc"
        printf 'collector_clipped=%s\n' "$clipped"
        printf '\n===== hardware-diagnostics =====\n'
        head -c 524288 "$report_file" 2>/dev/null || true
        printf '\n\n===== application-log-tail =====\n'
        if [[ -L "$UGREEN_LOG_FILE" ]]; then
            printf '<application log skipped: symlink is not allowed>\n'
        elif [[ -f "$UGREEN_LOG_FILE" ]]; then
            tail -n 1000 "$UGREEN_LOG_FILE" 2>/dev/null | tail -c 131072 || true
            printf '\n'
        else
            printf '<application log is empty or unavailable>\n'
        fi
    } > "$bundle_file"

    bundle_size=$(wc -c < "$bundle_file" 2>/dev/null || echo 0)
    [[ "$bundle_size" =~ ^[0-9]+$ ]] || bundle_size=0
    content=$(cat "$bundle_file" 2>/dev/null || true)
    stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo unknown-time)
    filename="ugreen-led-diagnostics-${stamp}.txt"
    rm -f "$report_file" "$bundle_file" 2>/dev/null || true

    printf '{"ok":true,"filename":"%s","size_bytes":%s,"collector_exit_code":%s,"clipped":%s,"content":"%s"}' \
        "$(json_str "$filename")" "$bundle_size" "$collector_rc" "$clipped" "$(json_str "$content")"
}

clear_application_logs() {
    local file="$UGREEN_LOG_FILE" lock="${UGREEN_LOG_FILE}.lock" fallback_lock index rc=0
    mkdir -p "${file%/*}" 2>/dev/null || return 1
    [[ -L "$file" ]] && return 1
    if [[ "${UGREEN_LOG_USE_FLOCK:-false}" == "true" ]]; then
        {
            flock -n 9 2>/dev/null || return 1
            [[ -L "$file" ]] && return 1
            : > "$file" || return 1
            for ((index = 1; index <= 10; index++)); do rm -f "${file}.${index}" 2>/dev/null || true; done
        } 9>>"$lock"
    elif declare -F _ugreen_log_acquire_fallback_lock >/dev/null && \
        declare -F _ugreen_log_release_fallback_lock >/dev/null; then
        fallback_lock="${file}.lockdir"
        _ugreen_log_acquire_fallback_lock "$fallback_lock" 20 || return 1
        if [[ -L "$file" ]]; then
            rc=1
        elif ! : > "$file"; then
            rc=1
        else
            for ((index = 1; index <= 10; index++)); do rm -f "${file}.${index}" 2>/dev/null || true; done
        fi
        _ugreen_log_release_fallback_lock "$fallback_lock"
        (( rc == 0 )) || return 1
    else
        : > "$file" || return 1
        for ((index = 1; index <= 10; index++)); do rm -f "${file}.${index}" 2>/dev/null || true; done
    fi
    rm -f "${RUNTIME_DIR}/log-rate/"* 2>/dev/null || true
    rmdir "${RUNTIME_DIR}/log-rate" 2>/dev/null || true
    chmod 0640 "$file" 2>/dev/null || true
}

handle_api_request() {
case "$API_PATH" in
    /hardware/diagnostics)
        if [[ "$REQUEST_METHOD" != "GET" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        else
            hardware_diagnostics_json
        fi
        ;;
    /logs)
        if [[ "$REQUEST_METHOD" != "GET" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ -n "$(query_value source)" && "$(query_value source)" != "application" ]]; then
            echo '{"ok":false,"error":"unknown log source"}'
        else
            application_logs_json
        fi
        ;;
    /logs/config)
        level=$(query_value level)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! [[ "$level" =~ ^(debug|info|warn|error)$ ]]; then
            echo '{"ok":false,"error":"invalid log level"}'
        elif settings_set "$SETTINGS_FILE" logging level "$level"; then
            UGREEN_LOG_LEVEL="${level^^}"
            if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
            fi
            ugreen_log_audit "logging.level_changed" "日志记录级别已更新" "level=$level"
            printf '{"ok":true,"level":"%s","message":"日志记录级别已切换为 %s"}' "$level" "${level^^}"
        else
            echo '{"ok":false,"error":"failed to save log level"}'
        fi
        ;;
    /logs/clear)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$(query_value confirm)" != "clear-logs" ]]; then
            echo '{"ok":false,"error":"log clear confirmation required"}'
        elif clear_application_logs; then
            ugreen_log_audit "logging.cleared" "应用诊断日志已清空"
            echo '{"ok":true,"message":"应用诊断日志已清空"}'
        else
            echo '{"ok":false,"error":"failed to clear logs"}'
        fi
        ;;
    /logs/client)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif $POST_TOO_LARGE || ! [[ "${CONTENT_LENGTH:-0}" =~ ^[0-9]+$ ]] || (( CONTENT_LENGTH > 8192 )); then
            echo '{"ok":false,"error":"client log payload too large"}'
        else
            client_payload="$POST_DATA"
            case "${client_payload,,}" in
                *password*|*passwd*|*token*|*secret*|*authorization*|*auth*|*cookie*|*api_key*|*apikey*|*credential*|*private_key*|*access_key*)
                    client_payload="<redacted-sensitive-client-payload>"
                    ;;
            esac
            if declare -F ugreen_log_rate_limited >/dev/null; then
                ugreen_log_rate_limited "web-client-error" 2 ERROR "client.error" \
                    "Web 前端上报运行时错误" "payload=$client_payload"
            else
                ugreen_log_error "client.error" "Web 前端上报运行时错误" "payload=$client_payload"
            fi
            echo '{"ok":true}'
        fi
        ;;

    /status)
        d="stopped"
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && d="running"
        mode=$(settings_get "$SETTINGS_FILE" mode global "smart")
        st=$(led_all_status 2>/dev/null || echo "")
        lab_active=false
        lab_mapping_session_active && lab_active=true

        net="disconnected" nlabel="断网" nd=0 no=0 rx=0 tx=0 total=0 updated=0
        if [[ -f "$NET_STATUS_FILE" ]]; then
            IFS='|' read -r net nlabel nd no rx tx total updated < "$NET_STATUS_FILE"
        fi
        printf '{"ok":true,"daemon":"%s","mode":"%s","network":"%s","network_label":"%s","net_domestic":%s,"net_overseas":%s,"net_rx_kbps":%s,"net_tx_kbps":%s,"net_total_kbps":%s,"updated_at":%s,"lab_mapping_active":%s,"led_status":"%s"}' \
            "$d" "$mode" "$net" "$(json_str "$nlabel")" "${nd:-0}" "${no:-0}" "${rx:-0}" "${tx:-0}" "${total:-0}" "${updated:-0}" "$lab_active" "$(json_str "$st")"
        ;;
    /hardware/status)
        hardware_status_json
        ;;
    /bios/status)
        bios_status_json
        ;;
    /bios/confirmation)
        confirmation=$(query_value confirm)
        expected_confirmation=$(bios_write_confirmation_token)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ -z "$expected_confirmation" ]]; then
            echo '{"ok":false,"error":"this model has no protected BIOS write confirmation"}'
        elif [[ "$confirmation" != "$expected_confirmation" ]]; then
            echo '{"ok":false,"error":"invalid BIOS write confirmation"}'
        elif bios_remember_write_risk; then
            echo '{"ok":true,"write_confirmation_acknowledged":true}'
        else
            echo '{"ok":false,"error":"unable to save BIOS write confirmation"}'
        fi
        ;;
    /bios/telemetry)
        bios_telemetry_json "$(query_value range)"
        ;;
    /bios/fan)
        channel=$(query_value channel)
        pwm=$(query_value pwm)
        fan_curve_was_running=false
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! [[ "$channel" =~ ^(cpu|sys|all)$ && "$pwm" =~ ^[0-9]+$ ]] || (( pwm < 0 || pwm > 255 )); then
            echo '{"ok":false,"error":"风扇参数无效"}'
        elif ! bios_write_confirmation_valid; then
            if [[ "$(bios_detected_profile)" == "dxp4800" || "$(bios_detected_profile)" == "dxp4800s" || "$(bios_detected_profile)" == "dxp6800pro" ]]; then
                echo '{"ok":false,"error":"固件逆向风扇写入需要先确认风险"}'
            else
                echo '{"ok":false,"error":"直控风扇写入需要先确认 IT8613 直控风险"}'
            fi
        else
            if bios_fan_curve_running; then
                fan_curve_was_running=true
                bios_fan_curve_stop true
            fi
            if bios_set_fan "$channel" "$pwm"; then
                settings_set "$SETTINGS_FILE" fan_curve enabled false
            if [[ "$channel" == "cpu" ]]; then fan_name="CPU 风扇"; elif [[ "$channel" == "all" ]]; then fan_name="系统风扇对"; else fan_name="系统风扇"; fi
                bios_status_json "${fan_name} 已切换为固定转速 PWM ${pwm}；自动温控已停止"
            else
                if $fan_curve_was_running; then bios_fan_curve_restore >/dev/null 2>&1 || true; fi
                printf '{"ok":false,"error":"%s"}' "$(json_str "${BIOS_LAST_ERROR:-风扇控制失败}")"
            fi
        fi
        ;;
    /bios/fan-curve)
        curve_action=$(query_value action)
        curve_mode=$(query_value mode); curve_mode="${curve_mode:-custom}"
        curve_interval=$(query_value interval); curve_interval="${curve_interval:-10}"
        curve_downshift=$(query_value downshift); curve_downshift="${curve_downshift:-60}"
        curve_minimum=$(query_value minimum); curve_minimum="${curve_minimum:-64}"
        curve_cpu=$(query_value cpu); curve_cpu="${curve_cpu:-50,55,75,80,90}"
        curve_hdd=$(query_value hdd); curve_hdd="${curve_hdd:-40,45,50,55,70}"
        curve_ssd=$(query_value ssd); curve_ssd="${curve_ssd:-45,50,60,65,70}"
        curve_pwm=$(query_value pwm); curve_pwm="${curve_pwm:-64,128,204,255}"
        curve_storage=$(query_value require_storage); curve_storage="${curve_storage:-false}"
        if [[ "$REQUEST_METHOD" == "GET" ]]; then
            bios_fan_curve_status_json
        elif [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$curve_action" == "stop" ]]; then
            bios_fan_curve_stop
            bios_status_json "自动温控曲线已停止；当前 PWM 保持最后一次安全写入值"
        elif [[ "$curve_action" != "start" ]]; then
            echo '{"ok":false,"error":"温控曲线操作无效"}'
        elif ! bios_write_confirmation_valid; then
            echo '{"ok":false,"error":"受保护机型启动自动温控前需要先确认风险"}'
        elif bios_fan_curve_start "$curve_mode" "$curve_interval" "$curve_downshift" "$curve_minimum" \
                "$curve_cpu" "$curve_hdd" "$curve_ssd" "$curve_pwm" "$curve_storage" true; then
            bios_status_json "自动温控曲线已启动"
        else
            printf '{"ok":false,"error":"%s"}' "$(json_str "${BIOS_LAST_ERROR:-自动温控曲线启动失败}")"
        fi
        ;;
    /bios/fan/mode)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        else
            echo '{"ok":false,"error":"暂时只开放手动 PWM；原厂自动模式由软件温控曲线实现，不能用 pwm*_enable=2 代替"}'
        fi
        ;;
    /bios/startup)
        policy=$(query_value policy)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! [[ "$policy" =~ ^(on|off|last)$ ]]; then
            echo '{"ok":false,"error":"来电启动参数无效"}'
        elif ! bios_write_confirmation_valid; then
            echo '{"ok":false,"error":"受保护写入需要先在页面确认风险"}'
        elif bios_set_startup "$policy"; then
            bios_status_json "来电启动策略已更新"
        else
            printf '{"ok":false,"error":"%s"}' "$(json_str "${BIOS_LAST_ERROR:-来电启动设置失败}")"
        fi
        ;;
    /bios/wol)
        policy=$(query_value policy)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! [[ "$policy" =~ ^(on|off)$ ]]; then
            echo '{"ok":false,"error":"网络唤醒参数无效"}'
        elif ! bios_write_confirmation_valid; then
            echo '{"ok":false,"error":"固件逆向网络唤醒写入需要先在页面确认风险"}'
        elif bios_set_wol "$policy"; then
            bios_status_json "网络唤醒策略已更新"
        else
            printf '{"ok":false,"error":"%s"}' "$(json_str "${BIOS_LAST_ERROR:-网络唤醒设置失败}")"
        fi
        ;;
    /bios/power-schedule)
        enabled=$(query_value enabled)
        days=$(query_value days)
        wake_time=$(query_value wake_time)
        shutdown_time=$(query_value shutdown_time)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! [[ "$enabled" =~ ^(true|false)$ ]]; then
            echo '{"ok":false,"error":"定时开关机开关无效"}'
        elif [[ "$enabled" == "true" ]] && ! { bios_schedule_days_valid "$days" && bios_schedule_time_valid "$wake_time" && bios_schedule_time_valid "$shutdown_time"; }; then
            echo '{"ok":false,"error":"定时开关机的日期或时间无效"}'
        elif ! bios_write_confirmation_valid; then
            echo '{"ok":false,"error":"固件逆向 RTC 定时开机需要先在页面确认风险"}'
        elif bios_power_schedule_set "$SETTINGS_FILE" "$enabled" "$days" "$wake_time" "$shutdown_time"; then
            bios_status_json "定时开关机计划已更新"
        else
            printf '{"ok":false,"error":"%s"}' "$(json_str "${BIOS_LAST_ERROR:-定时开关机设置失败}")"
        fi
        ;;
    /mapping)
        disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || DISK_LED_MAP=()
        printf '{"ok":true,"mapping":['
        first=1
        if runtime_file_fresh "$DISK_STATUS_FILE" 90; then
            while IFS='|' read -r dev led state read_kbps write_kbps total_kbps updated; do
                [[ -n "$dev" ]] || continue
                [[ $first -eq 0 ]] && printf ','
                first=0
                printf '{"device":"%s","led":"%s","state":"%s","read_kbps":%s,"write_kbps":%s,"total_kbps":%s,"updated_at":%s}' \
                    "$(json_str "$dev")" "$(json_str "$led")" "$state" "${read_kbps:-0}" "${write_kbps:-0}" "${total_kbps:-0}" "${updated:-0}"
            done < "$DISK_STATUS_FILE"
        else
            for dev in "${!DISK_LED_MAP[@]}"; do
                led="${DISK_LED_MAP[$dev]}"
                [[ $first -eq 0 ]] && printf ','
                first=0
                printf '{"device":"%s","led":"%s","state":"%s","read_kbps":%s,"write_kbps":%s,"total_kbps":%s}' \
                    "$(json_str "$dev")" "$(json_str "$led")" "unknown" 0 0 0
            done
        fi
        printf ']}'
        ;;
    /settings)
        if [[ "$REQUEST_METHOD" == "POST" ]]; then
            if $POST_TOO_LARGE; then
                echo '{"ok":false,"error":"settings payload too large"}'
            elif settings_apply_updates "$SETTINGS_FILE" <<< "$POST_DATA"; then
                led_clear_cache 2>/dev/null
                if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
                fi
                echo '{"ok":true}'
            else
                result=$?
                printf '{"ok":false,"error":"invalid settings payload (rc=%s)"}' "$result"
            fi
        else
            echo -n '{"ok":true,"raw":"'
            json_str "$(cat "$SETTINGS_FILE" 2>/dev/null)"
            echo '"}'
        fi
        ;;
    /update/check)
        force=$(query_value force)
        update_check_json "$force"
        ;;
    /lab/mapping/status)
        lab_mapping_status_json
        ;;
    /lab/mapping/start)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! ensure_led_backend; then
            printf '{"ok":false,"error":"%s"}' \
                "$(json_str "${LED_LAST_ERROR:-LED 控制程序不可用，无法进入检测模式}")"
        elif lab_mapping_show_all; then
            lab_mapping_status_json "检测模式已启动，全部硬盘灯已点亮"
        else
            lab_mapping_resume_control
            echo '{"ok":false,"error":"部分硬盘灯点亮失败，已退出检测模式"}'
        fi
        ;;
    /lab/mapping/highlight)
        led=$(query_value led)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! lab_mapping_session_active; then
            echo '{"ok":false,"error":"检测会话已结束，请重新开始"}'
        elif lab_mapping_highlight_slot "$led"; then
            lab_mapping_status_json "${led} 正在闪烁"
        else
            echo '{"ok":false,"error":"无法点亮指定盘位"}'
        fi
        ;;
    /lab/mapping/save)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! lab_mapping_session_active; then
            echo '{"ok":false,"error":"检测会话已结束，请重新开始"}'
        elif disk_save_identity_mapping "$SETTINGS_FILE" <<< "$POST_DATA"; then
            lab_mapping_resume_control
            lab_mapping_status_json "按硬盘绑定已保存"
        else
            result=$?
            case "$result" in
                3) error="包含不存在的 LED 盘位" ;;
                4) error="硬盘设备或序列号已变化，请重新开始检测" ;;
                5) error="同一硬盘或 LED 不能重复绑定" ;;
                6) error="请至少绑定一块硬盘" ;;
                *) error="映射数据无效，未保存任何更改" ;;
            esac
            printf '{"ok":false,"error":"%s"}' "$(json_str "$error")"
        fi
        ;;
    /lab/position/save)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! lab_mapping_session_active; then
            echo '{"ok":false,"error":"检测会话已结束，请重新开始"}'
        elif disk_save_position_mapping "$SETTINGS_FILE" <<< "$POST_DATA"; then
            lab_mapping_resume_control
            lab_mapping_status_json "灯光与硬盘位置绑定已保存"
        else
            result=$?
            case "$result" in
                3) error="包含不存在的 LED 盘位" ;;
                4) error="硬盘位置或 HCTL 已变化，请重新开始检测" ;;
                5) error="同一位置或 LED 不能重复绑定" ;;
                6) error="请至少绑定一个硬盘位置" ;;
                *) error="位置映射数据无效，未保存任何更改" ;;
            esac
            printf '{"ok":false,"error":"%s"}' "$(json_str "$error")"
        fi
        ;;
    /lab/mapping/cancel)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        else
            lab_mapping_resume_control
            lab_mapping_status_json "已退出检测模式，原映射保持不变"
        fi
        ;;
    /lab/mapping/reset)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif disk_reset_auto_mapping "$SETTINGS_FILE"; then
            lab_mapping_resume_control
            lab_mapping_status_json "已恢复自动 HCTL 映射"
        else
            echo '{"ok":false,"error":"恢复自动映射失败"}'
        fi
        ;;
    /mode)
        m=$(query_value mode)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! [[ "$m" =~ ^(off|on|smart)$ ]]; then
            echo '{"ok":false,"error":"invalid mode"}'
        elif ! settings_set "$SETTINGS_FILE" mode global "$m"; then
            echo '{"ok":false,"error":"failed to save mode"}'
        else
            led_clear_cache 2>/dev/null
            mode_apply_rc=0
            mode_apply_output=""
            if [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                if mode_apply_output=$(bash "${SERVER_DIR}/led_daemon.sh" once 2>&1); then :; else mode_apply_rc=$?; fi
            fi
            if [[ "$mode_apply_rc" -eq 0 ]]; then
                ugreen_log_info "mode.changed" "LED 运行模式已更新" "mode=$m"
                printf '{"ok":true,"mode":"%s"}' "$m"
            else
                ugreen_log_error "mode.apply_failed" "LED 模式已保存，但立即应用失败" \
                    "mode=$m" "exit_code=$mode_apply_rc" "output=$mode_apply_output"
                printf '{"ok":false,"error":"%s"}' \
                    "$(json_str "模式已保存，但立即应用失败：${LED_LAST_ERROR:-$mode_apply_output}")"
            fi
        fi
        ;;
    /remap)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! settings_set "$SETTINGS_FILE" behavior disk_map_mode auto; then
            echo '{"ok":false,"error":"failed to reset mapping mode"}'
        else
            remap_rc=0
            remap_output=""
            if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || remap_rc=$?
                sleep 0.2
            else
                if remap_output=$(bash "${SERVER_DIR}/led_daemon.sh" remap 2>&1); then :; else remap_rc=$?; fi
            fi
            rm -f "$DISK_STATUS_FILE"
            if [[ "$remap_rc" -eq 0 ]] && disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null; then
                n=${#DISK_LED_MAP[@]}
                ugreen_log_info "mapping.remapped" "硬盘灯映射已重新检测" "disk_count=$n"
                printf '{"ok":true,"message":"已重新检测 %s 块硬盘","disk_count":%s}' "$n" "$n"
            else
                ugreen_log_error "mapping.remap_failed" "硬盘灯映射重新检测失败" \
                    "exit_code=$remap_rc" "output=$remap_output"
                echo '{"ok":false,"error":"重新检测硬盘映射失败，请查看诊断日志"}'
            fi
        fi
        ;;
    /power26/apply)
        color=$(query_value color)
        effect=$(query_value effect)
        threshold=$(query_value threshold); threshold="${threshold:-32}"
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! hardware_power26_controller; then
            echo '{"ok":false,"error":"current model does not use the power-0x26 backend"}'
        elif [[ ! "$color" =~ ^(red|white)$ || ! "$effect" =~ ^(steady|fast|slow|breath|network|off)$ || ! "$threshold" =~ ^[0-9]+$ ]] || \
            (( threshold < 1 || threshold > 1048576 )); then
            echo '{"ok":false,"error":"invalid power light parameters"}'
        elif ! ensure_led_backend || [[ "$LED_BACKEND_ACTIVE" != "cli" ]]; then
            printf '{"ok":false,"error":"%s"}' "$(json_str "${LED_LAST_ERROR:-power-0x26 backend unavailable}")"
        else
            led_clear_cache 2>/dev/null
            command_effect="$effect"
            [[ "$command_effect" == "network" ]] && command_effect=steady
            if led_set_power26_effect "$color" "$command_effect"; then
                settings_set "$SETTINGS_FILE" power26 color "$color"
                if [[ "$effect" == "off" ]]; then
                    settings_set "$SETTINGS_FILE" mode global off
                    mode=off
                elif [[ "$effect" == "network" ]]; then
                    settings_set "$SETTINGS_FILE" power26 effect network
                    settings_set "$SETTINGS_FILE" power26 network_threshold_kbps "$threshold"
                    settings_set "$SETTINGS_FILE" mode global smart
                    mode=smart
                else
                    settings_set "$SETTINGS_FILE" power26 effect "$effect"
                    settings_set "$SETTINGS_FILE" power26 network_threshold_kbps "$threshold"
                    settings_set "$SETTINGS_FILE" mode global on
                    mode=on
                fi
                if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
                fi
                if [[ "$effect" == "off" ]]; then
                    printf '{"ok":true,"mode":"off","color":"%s","effect":"off","message":"电源灯已关闭"}' "$color"
                else
                    printf '{"ok":true,"mode":"%s","color":"%s","effect":"%s","message":"480T 电源灯设置已应用"}' "$mode" "$color" "$effect"
                fi
            else
                printf '{"ok":false,"error":"%s"}' "$(json_str "${LED_LAST_ERROR:-power light command failed}")"
            fi
        fi
        ;;
    /led/set)
        led=$(query_value led); r=$(query_value r); g=$(query_value g); b=$(query_value b); br=$(query_value brightness)
        br="${br:-64}"
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$led" =~ ^(power|netdev[1-9]*|disk[1-9][0-9]*)$ && "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$br" =~ ^[0-9]+$ ]] && \
            (( r <= 255 && g <= 255 && b <= 255 && br <= 255 )); then
            if led_set_color "$led" "$r" "$g" "$b" "$br"; then
                printf '{"ok":true,"led":"%s"}' "$led"
            else
                printf '{"ok":false,"error":"%s"}' "$(json_str "${LED_LAST_ERROR:-led command failed}")"
            fi
        else
            echo '{"ok":false,"error":"invalid led parameters"}'
        fi
        ;;
    /led/off)
        led=$(query_value led)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$led" =~ ^(power|netdev[1-9]*|disk[1-9][0-9]*)$ ]]; then
            if led_set_off "$led"; then
                printf '{"ok":true,"led":"%s"}' "$led"
            else
                printf '{"ok":false,"error":"%s"}' "$(json_str "${LED_LAST_ERROR:-led command failed}")"
            fi
        else
            echo '{"ok":false,"error":"invalid led"}'
        fi
        ;;
    /driver/install)
        echo '{"ok":false,"error":"kernel LED backends are disabled; use bundled ugreen_leds_cli"}'
        exit 0
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$(query_value confirm)" != "install-driver" ]]; then
            echo '{"ok":false,"error":"driver confirmation required"}'
        else
            daemon_was_running=false
            DRIVER_LOG="${VAR_DIR}/log/driver.log"
            DRIVER_OPERATION_ID="driver-install-${UGREEN_REQUEST_ID}"
            if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                daemon_was_running=true
                bash "${SERVER_DIR}/led_daemon.sh" stop >/dev/null 2>&1 || true
            fi
            if ugreen_log_run_raw "$DRIVER_LOG" 10485760 3 "$DRIVER_OPERATION_ID" driver_install; then rc=0; else rc=$?; fi
            if [[ $rc -eq 0 ]]; then
                settings_set "$SETTINGS_FILE" hardware backend cli
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                echo '{"ok":false,"error":"kernel LED backends are disabled; use bundled ugreen_leds_cli"}'
            else
                if driver_module_loaded; then
                    settings_set "$SETTINGS_FILE" hardware backend auto
                else
                    settings_set "$SETTINGS_FILE" hardware backend cli
                fi
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                printf '{"ok":false,"error":"%s"}' "$(json_str "$(driver_error_message "$rc")")"
            fi
        fi
        ;;
    /driver/unload)
        echo '{"ok":false,"error":"kernel LED backends are disabled; use bundled ugreen_leds_cli"}'
        exit 0
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$(query_value confirm)" != "unload-driver" ]]; then
            echo '{"ok":false,"error":"driver confirmation required"}'
        else
            daemon_was_running=false
            DRIVER_LOG="${VAR_DIR}/log/driver.log"
            DRIVER_OPERATION_ID="driver-unload-${UGREEN_REQUEST_ID}"
            if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                daemon_was_running=true
                bash "${SERVER_DIR}/led_daemon.sh" stop >/dev/null 2>&1 || true
            fi
            if ugreen_log_run_raw "$DRIVER_LOG" 10485760 3 "$DRIVER_OPERATION_ID" driver_unload; then
                settings_set "$SETTINGS_FILE" hardware backend cli
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                echo '{"ok":true,"message":"内核驱动已卸载，已切换到 CLI 后端"}'
            else
                rc=$?
                settings_set "$SETTINGS_FILE" hardware backend auto
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                printf '{"ok":false,"error":"%s"}' "$(json_str "$(driver_error_message "$rc")")"
            fi
        fi
        ;;
    /daemon/start)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
            return 0
        fi
        daemon_rc=0
        SERVICE_CONTROL_LOG="${VAR_DIR}/log/service-control.log"
        if [[ -x "${APP_ROOT}/cmd/main" ]]; then
            ugreen_log_run_raw "$SERVICE_CONTROL_LOG" 1048576 2 "daemon-start" \
                "${APP_ROOT}/cmd/main" start || daemon_rc=$?
        else
            ugreen_log_run_raw "$SERVICE_CONTROL_LOG" 1048576 2 "daemon-start" \
                bash "${SERVER_DIR}/led_daemon.sh" start || daemon_rc=$?
        fi
        d="stopped"
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && d="running"
        if [[ "$daemon_rc" -eq 0 && "$d" == "running" ]]; then
            printf '{"ok":true,"daemon":"%s","message":"后台已启动"}' "$d"
        else
            ugreen_log_error "daemon.api_start_failed" "通过 Web 启动后台服务失败" \
                "exit_code=$daemon_rc" "daemon_state=$d" "raw_log=service-control.log"
            printf '{"ok":false,"daemon":"%s","error":"后台服务启动失败，请查看诊断日志"}' "$d"
        fi
        ;;
    /daemon/stop)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
            return 0
        fi
        daemon_rc=0
        SERVICE_CONTROL_LOG="${VAR_DIR}/log/service-control.log"
        if [[ -x "${APP_ROOT}/cmd/main" ]]; then
            ugreen_log_run_raw "$SERVICE_CONTROL_LOG" 1048576 2 "daemon-stop" \
                "${APP_ROOT}/cmd/main" stop || daemon_rc=$?
        else
            ugreen_log_run_raw "$SERVICE_CONTROL_LOG" 1048576 2 "daemon-stop" \
                bash "${SERVER_DIR}/led_daemon.sh" stop || daemon_rc=$?
        fi
        if [[ "$daemon_rc" -eq 0 ]] && { [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }; then
            echo '{"ok":true,"daemon":"stopped","message":"后台已停止"}'
        else
            ugreen_log_error "daemon.api_stop_failed" "通过 Web 停止后台服务失败" \
                "exit_code=$daemon_rc" "raw_log=service-control.log"
            echo '{"ok":false,"error":"后台服务停止失败，请查看诊断日志"}'
        fi
        ;;
    *)
        printf '{"ok":false,"error":"unknown","path":"%s"}' "$(json_str "$API_PATH")"
        ;;
esac
}

API_STARTED_MS=$(ugreen_log_now_ms)
API_HANDLER_RC=0
API_RESPONSE=""
if $API_BOOTSTRAP_FAILED; then
    API_HANDLER_RC=70
    API_RESPONSE='{"ok":false,"error":"API initialization failed","code":"API_BOOTSTRAP_FAILED"}'
elif settings_init "$SETTINGS_FILE" 2>/dev/null; then
    ugreen_log_configure_from_settings "$SETTINGS_FILE"
else
    API_HANDLER_RC=$?
    [[ "$API_HANDLER_RC" -ne 0 ]] || API_HANDLER_RC=71
    API_RESPONSE='{"ok":false,"error":"settings initialization failed"}'
fi

API_QUERY_LOG=$(ugreen_log_redact_query "$QUERY_STRING")
API_CLIENT_ADDR=$(ugreen_log_mask_address "${REMOTE_ADDR:-${HTTP_X_REAL_IP:-unknown}}")
API_USER_AGENT="${HTTP_USER_AGENT:-unknown}"
API_USER_AGENT="${API_USER_AGENT//$'\r'/ }"
API_USER_AGENT="${API_USER_AGENT//$'\n'/ }"
API_USER_AGENT="${API_USER_AGENT:0:256}"
API_REQUEST_LOG_LEVEL=DEBUG
if [[ "$REQUEST_METHOD" != "GET" ]]; then
    API_REQUEST_LOG_LEVEL=INFO
fi
if [[ "$API_REQUEST_LOG_LEVEL" == "INFO" ]]; then
    ugreen_log_info "request.start" "收到 API 请求" "method=$REQUEST_METHOD" "path=$API_PATH" \
        "query=$API_QUERY_LOG" "content_length=${CONTENT_LENGTH:-0}" \
        "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
else
    ugreen_log_debug "request.start" "收到 API 请求" "method=$REQUEST_METHOD" "path=$API_PATH" \
        "query=$API_QUERY_LOG" "content_length=${CONTENT_LENGTH:-0}" \
        "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
fi

if [[ "$API_HANDLER_RC" -eq 0 ]]; then
    if API_RESPONSE=$(handle_api_request); then
        :
    else
        API_HANDLER_RC=$?
    fi
fi

if [[ -z "$API_RESPONSE" ]]; then
    [[ "$API_HANDLER_RC" -ne 0 ]] || API_HANDLER_RC=72
    API_RESPONSE='{"ok":false,"error":"empty API response"}'
fi
API_FINISHED_MS=$(ugreen_log_now_ms)
API_DURATION_MS=$((API_FINISHED_MS - API_STARTED_MS))
(( API_DURATION_MS < 0 )) && API_DURATION_MS=0
API_RESPONSE_BYTES=$(printf '%s' "$API_RESPONSE" | wc -c | tr -d ' ')
API_HTTP_STATUS=$(api_http_status_for_response "$API_RESPONSE" "$API_HANDLER_RC")
API_HTTP_REASON=$(api_http_reason "$API_HTTP_STATUS")

if [[ "$API_HANDLER_RC" -ne 0 ]]; then
    ugreen_log_error "request.failed" "API 请求异常退出" "method=$REQUEST_METHOD" "path=$API_PATH" \
        "exit_code=$API_HANDLER_RC" "http_status=$API_HTTP_STATUS" \
        "duration_ms=$API_DURATION_MS" "response_bytes=$API_RESPONSE_BYTES" \
        "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
elif [[ $API_RESPONSE == '{"ok":false'* ]]; then
    API_ERROR_SUMMARY=$(printf '%s' "$API_RESPONSE" | sed -n 's/.*"error":"\([^"]*\)".*/\1/p' | head -n 1)
    if (( API_HTTP_STATUS >= 500 )); then
        ugreen_log_error "request.failed" "API 请求处理失败" "method=$REQUEST_METHOD" "path=$API_PATH" \
            "http_status=$API_HTTP_STATUS" "duration_ms=$API_DURATION_MS" \
            "response_bytes=$API_RESPONSE_BYTES" "error=$API_ERROR_SUMMARY" \
            "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
    else
        ugreen_log_warn "request.rejected" "API 请求未成功" "method=$REQUEST_METHOD" "path=$API_PATH" \
            "http_status=$API_HTTP_STATUS" "duration_ms=$API_DURATION_MS" \
            "response_bytes=$API_RESPONSE_BYTES" "error=$API_ERROR_SUMMARY" \
            "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
    fi
elif [[ "$API_REQUEST_LOG_LEVEL" == "INFO" ]]; then
    ugreen_log_info "request.completed" "API 请求完成" "method=$REQUEST_METHOD" "path=$API_PATH" \
        "http_status=$API_HTTP_STATUS" "duration_ms=$API_DURATION_MS" "response_bytes=$API_RESPONSE_BYTES" \
        "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
else
    ugreen_log_debug "request.completed" "API 请求完成" "method=$REQUEST_METHOD" "path=$API_PATH" \
        "http_status=$API_HTTP_STATUS" "duration_ms=$API_DURATION_MS" "response_bytes=$API_RESPONSE_BYTES" \
        "client_addr=$API_CLIENT_ADDR" "user_agent=$API_USER_AGENT"
fi

echo "Status: $API_HTTP_STATUS $API_HTTP_REASON"
echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-store"
echo "X-Content-Type-Options: nosniff"
echo "X-Request-ID: $UGREEN_REQUEST_ID"
echo ""
printf '%s\n' "$API_RESPONSE"
