#!/bin/bash
# 硬盘 HCTL 动态映射 -> disk1-4（按 HCTL 特征，非磁盘顺序）

disk_detect_by_hctl() {
    lsblk -S -x hctl -o NAME,HCTL,SERIAL,MODEL,SIZE 2>/dev/null | tail -n +2
}

disk_guess_led_by_hctl() {
    local hctl="$1"
    case "$hctl" in
        0:0:0:0) echo "disk1" ;;
        1:0:0:0) echo "disk2" ;;
        2:0:0:0) echo "disk3" ;;
        3:0:0:0) echo "disk4" ;;
        4:0:0:0) echo "disk5" ;;
        5:0:0:0) echo "disk6" ;;
        *) echo "" ;;
    esac
}

# 动态生成映射行 device|hctl|led|serial
disk_build_mapping() {
    local line name hctl serial led dev
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([a-z0-9]+)[[:space:]]+([0-9]+:[0-9]+:[0-9]+:[0-9]+)[[:space:]]*(.*)$ ]]; then
            name="${BASH_REMATCH[1]}"
            hctl="${BASH_REMATCH[2]}"
            serial="${BASH_REMATCH[3]}"
            dev="/dev/$name"
            [[ -b "$dev" ]] || continue
            led=$(disk_guess_led_by_hctl "$hctl")
            [[ -n "$led" ]] && echo "${dev}|${hctl}|${led}|${serial}"
        fi
    done < <(disk_detect_by_hctl)
}

declare -gA DISK_LED_MAP

disk_load_mapping_from_settings() {
    local settings="$1"
    DISK_LED_MAP=()
    [[ -f "$settings" ]] || return 1

    local in_maps=0 line key val
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == "[disk_map]" ]]; then
            in_maps=1
            continue
        fi
        if [[ "$line" =~ ^\[ ]]; then
            in_maps=0
            continue
        fi
        if [[ $in_maps -eq 1 && "$line" =~ ^(/dev/[^=]+)=(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val// /}"
            DISK_LED_MAP["$key"]="$val"
        fi
    done < "$settings"
    [[ ${#DISK_LED_MAP[@]} -gt 0 ]]
}

# 重写 settings 中的 [disk_map]（每次启动/热插拔动态生成）
disk_refresh_mapping() {
    local settings="$1"
    local -a lines=()

    while IFS='|' read -r dev hctl led serial; do
        [[ -n "$dev" && -n "$led" ]] && lines+=("${dev}=${led}")
    done < <(disk_build_mapping)

    if [[ -f "$settings" ]]; then
        awk '
            /^\[disk_map\]/ { skip=1; next }
            /^\[/ && skip { skip=0 }
            skip && /^\/dev\// { next }
            { print }
        ' "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
    fi

    {
        echo ""
        echo "[disk_map]"
        if [[ ${#lines[@]} -eq 0 ]]; then
            echo "# 未检测到硬盘"
        else
            for l in "${lines[@]}"; do
                echo "$l"
            done
        fi
    } >> "$settings"

    disk_load_mapping_from_settings "$settings"
}

disk_unmapped_slots() {
    local -a all_slots=() s
    mapfile -t all_slots < <(led_list_disk_slots 2>/dev/null)
    [[ ${#all_slots[@]} -eq 0 ]] && all_slots=(disk1 disk2 disk3 disk4)

    for s in "${all_slots[@]}"; do
        local found=0
        for led in "${DISK_LED_MAP[@]}"; do
            [[ "$led" == "$s" ]] && found=1
        done
        [[ $found -eq 0 ]] && echo "$s"
    done
}

disk_snapshot_devices() {
    lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}'
}

# 兼容旧名
disk_save_auto_mapping() {
    disk_refresh_mapping "$1"
}

disk_power_state() {
    disk_detect_smart_state "$1" "${2:-8}"
}
