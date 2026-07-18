#!/bin/bash
# 应用配置读写（INI 风格，便于 shell 解析）

SETTINGS_FILE="${SETTINGS_FILE:-}"

_settings_log_debug() {
    if declare -F ugreen_log_debug >/dev/null; then ugreen_log_debug "$@"; fi
    return 0
}

_settings_log_info() {
    if declare -F ugreen_log_info >/dev/null; then ugreen_log_info "$@"; fi
    return 0
}

_settings_log_error() {
    if declare -F ugreen_log_error >/dev/null; then ugreen_log_error "$@"; fi
    return 0
}

settings_log_value() {
    local key="${1,,}" value="$2"
    case "$key" in
        *password*|*passwd*|*token*|*secret*|*authorization*|*auth*|*cookie*|*api_key*|*apikey*|*credential*|*private_key*|*access_key*) printf '%s' '<redacted>' ;;
        *) printf '%s' "$value" ;;
    esac
}

settings_default() {
    local tpl
    for tpl in \
        "${SERVER_DIR:-}/default_settings.conf" \
        "${TARGET:-}/server/default_settings.conf" \
        "${TARGET:-}/target/server/default_settings.conf"; do
        if [[ -n "$tpl" && -f "$tpl" ]]; then
            cat "$tpl"
            return
        fi
    done
    cat <<'EOF'
[mode]
global=smart
[daemon]
enabled=true
check_interval=5
io_idle_seconds=8
[logging]
level=info
max_size_kb=5120
retained_files=5
[hardware]
backend=cli
profile=auto
write_protocol=auto
[activity]
disk_blink=false
network_blink=false
disk_threshold_kbps=128
network_threshold_kbps=32
[power26]
color=white
effect=steady
network_threshold_kbps=32
[disk_map]
EOF
}

settings_init() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        if ! mkdir -p "$(dirname "$f")"; then
            _settings_log_error "settings.directory_failed" "无法创建配置目录" "settings_file=$f"
            return 1
        fi
        if ! settings_default > "$f"; then
            _settings_log_error "settings.create_failed" "无法创建默认配置文件" "settings_file=$f"
            return 1
        fi
        _settings_log_info "settings.created" "已创建默认应用配置" "settings_file=$f"
    fi
}

settings_get() {
    local f="$1" section="$2" key="$3" default="${4:-}"
    local cur="" val=""
    [[ -f "$f" ]] || { echo "$default"; return; }
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            cur="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$cur" == "$section" && "$line" =~ ^${key}=(.*)$ ]]; then
            val="${BASH_REMATCH[1]}"
        fi
    done < "$f"
    echo "${val:-$default}"
}

settings_set() {
    local f="$1" section="$2" key="$3" value="$4"
    local old_value
    settings_init "$f" || return 1
    old_value=$(settings_get "$f" "$section" "$key" "")
    local tmp="${f}.new.$$"
    local in_section=0 found=0 cur=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            if [[ $in_section -eq 1 && $found -eq 0 ]]; then
                echo "${key}=${value}"
                found=1
            fi
            cur="${BASH_REMATCH[1]}"
            in_section=0
            [[ "$cur" == "$section" ]] && in_section=1
            echo "$line"
            continue
        fi
        if [[ $in_section -eq 1 && "$line" =~ ^${key}= ]]; then
            echo "${key}=${value}"
            found=1
            continue
        fi
        echo "$line"
    done < "$f" > "$tmp"
    if [[ $found -eq 0 ]]; then
        # 追加 section/key
        if ! grep -q "^\[${section}\]" "$f" 2>/dev/null; then
            echo "" >> "$tmp"
            echo "[${section}]" >> "$tmp"
        fi
        echo "${key}=${value}" >> "$tmp"
    fi
    if ! mv "$tmp" "$f"; then
        rm -f "$tmp" 2>/dev/null || true
        _settings_log_error "settings.replace_failed" "无法原子替换应用配置" \
            "settings_file=$f" "section=$section" "key=$key"
        return 1
    fi
    if [[ "${SETTINGS_LOG_SILENT:-false}" != "true" ]]; then
        _settings_log_debug "settings.value_changed" "应用配置项已更新" \
            "settings_file=$f" "section=$section" "key=$key" \
            "old_value=$(settings_log_value "$key" "$old_value")" "new_value=$(settings_log_value "$key" "$value")"
    fi
}

# 批量更新 section.key=value，每次保存只原子替换一次正式配置文件。
settings_apply_updates() {
    local f="$1" tmp line section key value count=0 changed_keys="" previous_silent
    settings_init "$f" || return 1
    tmp="${f}.batch.$$"
    cp "$f" "$tmp" || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_-]+)=(.*)$ ]]; then
            section="${BASH_REMATCH[1]}"
            key="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
            count=$((count + 1))
            changed_keys+="${changed_keys:+,}${section}.${key}"
            previous_silent="${SETTINGS_LOG_SILENT:-false}"
            SETTINGS_LOG_SILENT=true
            settings_set "$tmp" "$section" "$key" "$value" || {
                SETTINGS_LOG_SILENT="$previous_silent"
                rm -f "$tmp" "${tmp}.new."* 2>/dev/null
                _settings_log_error "settings.batch_item_failed" "批量配置更新失败" \
                    "settings_file=$f" "section=$section" "key=$key" "count=$count"
                return 1
            }
            SETTINGS_LOG_SILENT="$previous_silent"
        else
            rm -f "$tmp" "${tmp}.new."* 2>/dev/null
            _settings_log_error "settings.batch_invalid" "批量配置包含无效行" \
                "settings_file=$f" "line_number=$((count + 1))"
            return 2
        fi
    done

    if ! mv "$tmp" "$f"; then
        rm -f "$tmp" 2>/dev/null || true
        _settings_log_error "settings.batch_replace_failed" "无法保存批量配置更新" \
            "settings_file=$f" "count=$count"
        return 1
    fi
    _settings_log_info "settings.batch_updated" "应用配置已批量更新" \
        "settings_file=$f" "count=$count" "keys=$changed_keys"
}

settings_color_triplet() {
    local f="$1" state="$2"
    settings_get "$f" colors "$state" "128 128 128"
}

settings_brightness() {
    local f="$1" state="$2"
    settings_get "$f" brightness "$state" "64"
}
