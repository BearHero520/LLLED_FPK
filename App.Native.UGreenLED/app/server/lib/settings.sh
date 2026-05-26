#!/bin/bash
# 应用配置读写（INI 风格，便于 shell 解析）

SETTINGS_FILE="${SETTINGS_FILE:-}"

settings_default() {
    local tpl="${TARGET:-}/server/default_settings.conf"
    if [[ -f "$tpl" ]]; then
        cat "$tpl"
    else
        cat <<'EOF'
[mode]
global=smart
[daemon]
enabled=true
check_interval=5
io_idle_seconds=8
[disk_map]
EOF
    fi
}

settings_init() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        mkdir -p "$(dirname "$f")"
        settings_default > "$f"
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
    settings_init "$f"
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
    mv "$tmp" "$f"
}

settings_color_triplet() {
    local f="$1" state="$2"
    settings_get "$f" colors "$state" "128 128 128"
}

settings_brightness() {
    local f="$1" state="$2"
    settings_get "$f" brightness "$state" "64"
}
