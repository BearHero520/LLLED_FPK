#!/bin/bash
# 硬盘智能状态：active | idle | standby | deep_sleep | offline

DISK_IO_CACHE_DIR="${DISK_IO_CACHE_DIR:-/tmp/ugreen-disk-io}"

disk_io_cache_path() {
    echo "${DISK_IO_CACHE_DIR}/$(basename "$1").io"
}

disk_io_read_sectors() {
    local dev="$1" name
    name=$(basename "$dev")
    awk -v d="$name" '$3==d {print $4+$8}' /proc/diskstats 2>/dev/null | head -1
}

disk_io_update_cache() {
    local dev="$1" sectors now
    mkdir -p "$DISK_IO_CACHE_DIR"
    sectors=$(disk_io_read_sectors "$dev")
    now=$(date +%s)
    echo "${sectors:-0} ${now}" > "$(disk_io_cache_path "$dev")"
}

disk_io_was_active() {
    local dev="$1" idle_sec="${2:-8}"
    local f sectors last now diff
    f=$(disk_io_cache_path "$dev")
    sectors=$(disk_io_read_sectors "$dev")
    now=$(date +%s)

    if [[ ! -f "$f" ]]; then
        disk_io_update_cache "$dev"
        return 1
    fi
    read -r last last_t < "$f" 2>/dev/null || { disk_io_update_cache "$dev"; return 1; }
    diff=$(( ${sectors:-0} - ${last:-0} ))
    if [[ $diff -gt 0 ]]; then
        disk_io_update_cache "$dev"
        return 0
    fi
    if [[ $((now - last_t)) -lt $idle_sec ]]; then
        return 0
    fi
    disk_io_update_cache "$dev"
    return 1
}

# 输出: offline | deep_sleep | standby | active | idle
disk_detect_smart_state() {
    local dev="$1"
    local idle_sec="${2:-8}"

    [[ -b "$dev" ]] || { echo "offline"; return; }

    local out lower
    if ! out=$(timeout 5 hdparm -C "$dev" 2>&1); then
        if echo "$out" | grep -qi "No such file"; then
            echo "offline"
        else
            echo "offline"
        fi
        return
    fi

    lower=$(echo "$out" | tr '[:upper:]' '[:lower:]')

    if echo "$lower" | grep -q "sleeping"; then
        echo "deep_sleep"
        return
    fi
    if echo "$lower" | grep -q "standby"; then
        echo "standby"
        return
    fi
    if echo "$lower" | grep -q "active/idle\|active"; then
        if disk_io_was_active "$dev" "$idle_sec"; then
            echo "active"
        else
            echo "idle"
        fi
        return
    fi
    echo "idle"
}
