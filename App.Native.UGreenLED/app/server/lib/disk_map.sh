#!/bin/bash
# 硬盘 HCTL 映射：自动探测 + 实验室手动盘位绑定。

LAB_MAPPING_SESSION_TTL="${LAB_MAPPING_SESSION_TTL:-1200}"

disk_inventory_field() {
    local line="$1" key="$2"
    printf '%s\n' "$line" | sed -n "s/.*${key}=\"\\([^\"]*\\)\".*/\\1/p"
}

# 输出：device|hctl|serial|model|size|transport
disk_inventory_rows() {
    local raw line name hctl serial model size transport dev
    raw=$(lsblk -S -n -P -o NAME,HCTL,SERIAL,MODEL,SIZE,TRAN 2>/dev/null || true)
    if [[ -n "$raw" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            name=$(disk_inventory_field "$line" NAME)
            hctl=$(disk_inventory_field "$line" HCTL)
            serial=$(disk_inventory_field "$line" SERIAL)
            model=$(disk_inventory_field "$line" MODEL)
            size=$(disk_inventory_field "$line" SIZE)
            transport=$(disk_inventory_field "$line" TRAN)
            dev="/dev/$name"
            [[ -n "$name" && -b "$dev" ]] || continue
            printf '%s|%s|%s|%s|%s|%s\n' "$dev" "$hctl" "$serial" "$model" "$size" "$transport"
        done <<< "$raw"
        return
    fi

    # 兼容不支持 lsblk -P 的旧环境；MODEL 可能包含空格，因此仅保证前三列稳定。
    while read -r name hctl serial model size; do
        dev="/dev/$name"
        [[ -n "$name" && -b "$dev" ]] || continue
        printf '%s|%s|%s|%s|%s|\n' "$dev" "$hctl" "$serial" "$model" "$size"
    done < <(lsblk -S -n -o NAME,HCTL,SERIAL,MODEL,SIZE 2>/dev/null)
}

disk_detect_by_hctl() {
    local dev hctl serial model size transport
    while IFS='|' read -r dev hctl serial model size transport; do
        printf '%s %s %s %s %s\n' "${dev#/dev/}" "$hctl" "$serial" "$model" "$size"
    done < <(disk_inventory_rows)
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
        6:0:0:0) echo "disk7" ;;
        7:0:0:0) echo "disk8" ;;
        *) echo "" ;;
    esac
}

# 自动生成映射行：device|hctl|led|serial
disk_build_mapping() {
    local dev hctl serial model size transport led
    while IFS='|' read -r dev hctl serial model size transport; do
        [[ -n "$dev" && -n "$hctl" ]] || continue
        led=$(disk_guess_led_by_hctl "$hctl")
        [[ -n "$led" ]] && printf '%s|%s|%s|%s\n' "$dev" "$hctl" "$led" "$serial"
    done < <(disk_inventory_rows)
}

declare -gA DISK_LED_MAP

disk_mapping_mode() {
    local settings="$1" mode
    mode=$(settings_get "$settings" behavior disk_map_mode "auto")
    case "$mode" in
        manual|position) echo "position" ;;
        disk) echo "disk" ;;
        *) echo "auto" ;;
    esac
}

disk_load_auto_mapping_from_settings() {
    local settings="$1" in_maps=0 line key val
    [[ -f "$settings" ]] || return 1
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
        if [[ $in_maps -eq 1 && "$line" =~ ^(/dev/[^=]+)=(disk[1-9][0-9]*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            DISK_LED_MAP["$key"]="$val"
        fi
    done < "$settings"
    [[ ${#DISK_LED_MAP[@]} -gt 0 ]]
}

disk_load_position_mapping_from_settings() {
    local settings="$1" in_maps=0 line key val hctl
    local dev serial model size transport led
    declare -A hctl_led=()
    [[ -f "$settings" ]] || return 1

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == "[manual_disk_map]" ]]; then
            in_maps=1
            continue
        fi
        if [[ "$line" =~ ^\[ ]]; then
            in_maps=0
            continue
        fi
        if [[ $in_maps -eq 1 && "$line" =~ ^hctl_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)=(disk[1-9][0-9]*)$ ]]; then
            hctl="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
            val="${BASH_REMATCH[5]}"
            hctl_led["$hctl"]="$val"
        fi
    done < "$settings"

    [[ ${#hctl_led[@]} -gt 0 ]] || return 1
    while IFS='|' read -r dev hctl serial model size transport; do
        led="${hctl_led[$hctl]:-}"
        [[ -n "$dev" && -n "$led" ]] && DISK_LED_MAP["$dev"]="$led"
    done < <(disk_inventory_rows)
    [[ ${#DISK_LED_MAP[@]} -gt 0 ]]
}

disk_load_identity_mapping_from_settings() {
    local settings="$1" in_maps=0 line led serial
    local dev hctl inv_serial model size transport mapped_led
    declare -A serial_led=()
    [[ -f "$settings" ]] || return 1

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == "[manual_disk_identity_map]" ]]; then
            in_maps=1
            continue
        fi
        if [[ "$line" =~ ^\[ ]]; then
            in_maps=0
            continue
        fi
        if [[ $in_maps -eq 1 && "$line" =~ ^(disk[1-9][0-9]*)=(.+)$ ]]; then
            led="${BASH_REMATCH[1]}"
            serial="${BASH_REMATCH[2]}"
            [[ -n "$serial" ]] && serial_led["$serial"]="$led"
        fi
    done < "$settings"

    [[ ${#serial_led[@]} -gt 0 ]] || return 1
    while IFS='|' read -r dev hctl inv_serial model size transport; do
        mapped_led="${serial_led[$inv_serial]:-}"
        [[ -n "$dev" && -n "$inv_serial" && -n "$mapped_led" ]] && DISK_LED_MAP["$dev"]="$mapped_led"
    done < <(disk_inventory_rows)
    [[ ${#DISK_LED_MAP[@]} -gt 0 ]]
}

disk_load_mapping_from_settings() {
    local settings="$1" mode
    DISK_LED_MAP=()
    [[ -f "$settings" ]] || return 1
    mode=$(disk_mapping_mode "$settings")
    case "$mode" in
        position) disk_load_position_mapping_from_settings "$settings" ;;
        disk) disk_load_identity_mapping_from_settings "$settings" ;;
        *) disk_load_auto_mapping_from_settings "$settings" ;;
    esac
}

disk_remove_section() {
    local source="$1" section="$2" destination="$3"
    awk -v section="$section" '
        $0 == "[" section "]" { skip=1; next }
        /^\[/ && skip { skip=0 }
        !skip { print }
    ' "$source" > "$destination"
}

# 重写 settings 中的自动 [disk_map]。
disk_refresh_mapping() {
    local settings="$1" tmp
    local -a lines=()
    while IFS='|' read -r dev hctl led serial; do
        [[ -n "$dev" && -n "$led" ]] && lines+=("${dev}=${led}")
    done < <(disk_build_mapping)

    settings_init "$settings"
    tmp="${settings}.auto.$$"
    disk_remove_section "$settings" disk_map "$tmp" || return 1
    {
        cat "$tmp"
        echo ""
        echo "[disk_map]"
        if [[ ${#lines[@]} -eq 0 ]]; then
            echo "# 未检测到可自动映射的硬盘"
        else
            printf '%s\n' "${lines[@]}"
        fi
    } > "${tmp}.next" || { rm -f "$tmp" "${tmp}.next"; return 1; }
    mv "${tmp}.next" "$settings"
    rm -f "$tmp"
    disk_load_mapping_from_settings "$settings"
}

disk_available_slots() {
    local slots
    slots=$(led_list_disk_slots 2>/dev/null | sed -n '/^disk[1-9][0-9]*$/p' | sort -V -u)
    if [[ -n "$slots" ]]; then
        printf '%s\n' "$slots"
    else
        printf '%s\n' disk1 disk2 disk3 disk4
    fi
}

# 位置绑定输入每行：diskN|/dev/sdX|H:C:T:L。保存为稳定的 HCTL -> LED 规则。
disk_save_position_mapping() {
    local settings="$1" line led dev hctl extra tmp key
    local inv_dev inv_hctl serial model size transport
    local -a entries=()
    declare -A valid_led=() hctl_dev=() dev_hctl=() used_led=() used_hctl=()

    while IFS= read -r led; do
        [[ -n "$led" ]] && valid_led["$led"]=1
    done < <(disk_available_slots)
    while IFS='|' read -r inv_dev inv_hctl serial model size transport; do
        [[ "$inv_hctl" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] || continue
        hctl_dev["$inv_hctl"]="$inv_dev"
        dev_hctl["$inv_dev"]="$inv_hctl"
    done < <(disk_inventory_rows)

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "$line" ]] || continue
        IFS='|' read -r led dev hctl extra <<< "$line"
        [[ -z "$extra" && "$led" =~ ^disk[1-9][0-9]*$ && "$dev" =~ ^/dev/[a-zA-Z0-9._/-]+$ && "$hctl" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] || return 2
        [[ -n "${valid_led[$led]:-}" ]] || return 3
        [[ "${hctl_dev[$hctl]:-}" == "$dev" && "${dev_hctl[$dev]:-}" == "$hctl" ]] || return 4
        [[ -z "${used_led[$led]:-}" && -z "${used_hctl[$hctl]:-}" ]] || return 5
        used_led["$led"]=1
        used_hctl["$hctl"]=1
        key="hctl_${hctl//:/_}"
        entries+=("${key}=${led}")
    done
    [[ ${#entries[@]} -gt 0 ]] || return 6

    settings_init "$settings"
    tmp="${settings}.manual.$$"
    disk_remove_section "$settings" manual_disk_map "$tmp" || return 1
    {
        cat "$tmp"
        echo ""
        echo "[manual_disk_map]"
        printf '%s\n' "${entries[@]}" | sort -t= -k2,2V
    } > "${tmp}.next" || { rm -f "$tmp" "${tmp}.next"; return 1; }
    mv "${tmp}.next" "$tmp"
    settings_set "$tmp" behavior disk_map_mode position || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$settings"
    disk_load_mapping_from_settings "$settings"
}

# 硬盘绑定输入每行：diskN|/dev/sdX|SERIAL。保存为序列号 -> LED 规则。
disk_save_identity_mapping() {
    local settings="$1" line led dev serial extra tmp
    local inv_dev hctl inv_serial model size transport
    local -a entries=()
    declare -A valid_led=() serial_dev=() dev_serial=() used_led=() used_serial=()

    while IFS= read -r led; do
        [[ -n "$led" ]] && valid_led["$led"]=1
    done < <(disk_available_slots)
    while IFS='|' read -r inv_dev hctl inv_serial model size transport; do
        [[ -n "$inv_serial" && "$inv_serial" != *"|"* ]] || continue
        serial_dev["$inv_serial"]="$inv_dev"
        dev_serial["$inv_dev"]="$inv_serial"
    done < <(disk_inventory_rows)

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -n "$line" ]] || continue
        IFS='|' read -r led dev serial extra <<< "$line"
        [[ -z "$extra" && "$led" =~ ^disk[1-9][0-9]*$ && "$dev" =~ ^/dev/[a-zA-Z0-9._/-]+$ && -n "$serial" ]] || return 2
        [[ -n "${valid_led[$led]:-}" ]] || return 3
        [[ "${serial_dev[$serial]:-}" == "$dev" && "${dev_serial[$dev]:-}" == "$serial" ]] || return 4
        [[ -z "${used_led[$led]:-}" && -z "${used_serial[$serial]:-}" ]] || return 5
        used_led["$led"]=1
        used_serial["$serial"]=1
        entries+=("${led}=${serial}")
    done
    [[ ${#entries[@]} -gt 0 ]] || return 6

    settings_init "$settings"
    tmp="${settings}.identity.$$"
    disk_remove_section "$settings" manual_disk_identity_map "$tmp" || return 1
    {
        cat "$tmp"
        echo ""
        echo "[manual_disk_identity_map]"
        printf '%s\n' "${entries[@]}" | sort -t= -k1,1V
    } > "${tmp}.next" || { rm -f "$tmp" "${tmp}.next"; return 1; }
    mv "${tmp}.next" "$tmp"
    settings_set "$tmp" behavior disk_map_mode disk || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$settings"
    disk_load_mapping_from_settings "$settings"
}

# 兼容 1.5.0 名称：旧“手动映射”实际保存的就是位置规则。
disk_save_manual_mapping() {
    disk_save_position_mapping "$@"
}

disk_reset_auto_mapping() {
    local settings="$1"
    settings_set "$settings" behavior disk_map_mode auto || return 1
    disk_refresh_mapping "$settings"
}

disk_unmapped_slots() {
    local -a all_slots=()
    local s led found
    mapfile -t all_slots < <(disk_available_slots)
    for s in "${all_slots[@]}"; do
        found=0
        for led in "${DISK_LED_MAP[@]}"; do
            [[ "$led" == "$s" ]] && found=1
        done
        [[ $found -eq 0 ]] && echo "$s"
    done
}

disk_snapshot_devices() {
    local dev hctl serial model size transport
    while IFS='|' read -r dev hctl serial model size transport; do
        [[ -n "$dev" ]] && echo "$dev"
    done < <(disk_inventory_rows)
}

lab_mapping_lock_file() {
    printf '%s' "${LAB_MAPPING_LOCK_FILE:-${RUNTIME_DIR:-/tmp}/lab_mapping.lock}"
}

lab_mapping_session_active() {
    local lock now started
    lock=$(lab_mapping_lock_file)
    [[ -f "$lock" ]] || return 1
    started=$(cat "$lock" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [[ ! "$started" =~ ^[0-9]+$ ]] || (( now - started > LAB_MAPPING_SESSION_TTL )); then
        rm -f "$lock"
        return 1
    fi
    return 0
}

lab_mapping_session_touch() {
    local lock
    lock=$(lab_mapping_lock_file)
    mkdir -p "$(dirname "$lock")" 2>/dev/null
    date +%s > "${lock}.tmp.$$" && mv "${lock}.tmp.$$" "$lock"
}

lab_mapping_session_end() {
    rm -f "$(lab_mapping_lock_file)"
}

lab_mapping_show_all() {
    local slot failed=0
    lab_mapping_session_touch || return 1
    led_clear_cache 2>/dev/null
    while IFS= read -r slot; do
        led_set_color "$slot" 220 232 255 96 || failed=1
    done < <(disk_available_slots)
    return "$failed"
}

lab_mapping_highlight_slot() {
    local selected="$1" slot valid=0 failed=0
    while IFS= read -r slot; do
        [[ "$slot" == "$selected" ]] && valid=1
    done < <(disk_available_slots)
    [[ $valid -eq 1 ]] || return 2
    lab_mapping_session_touch || return 1
    led_clear_cache 2>/dev/null
    while IFS= read -r slot; do
        if [[ "$slot" == "$selected" ]]; then
            led_set_blink "$slot" 22 119 255 820 360 180 || led_set_color "$slot" 22 119 255 180 || failed=1
        else
            led_set_color "$slot" 70 82 105 12 || failed=1
        fi
    done < <(disk_available_slots)
    return "$failed"
}

# 兼容旧名。
disk_save_auto_mapping() {
    disk_refresh_mapping "$1"
}

disk_power_state() {
    disk_detect_smart_state "$1" "${2:-8}"
}
