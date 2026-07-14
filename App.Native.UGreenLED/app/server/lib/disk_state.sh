#!/bin/bash
# 硬盘智能状态与吞吐采样：active | idle | standby | deep_sleep | offline

DISK_IO_CACHE_DIR="${DISK_IO_CACHE_DIR:-/tmp/ugreen-disk-io}"
DISKSTATS_FILE="${DISKSTATS_FILE:-/proc/diskstats}"

disk_io_cache_path() {
    echo "${DISK_IO_CACHE_DIR}/$(basename "$1").io"
}

disk_power_cache_path() {
    echo "${DISK_IO_CACHE_DIR}/$(basename "$1").power"
}

# 输出累计读取扇区、累计写入扇区。Linux diskstats 扇区固定按 512 字节计。
disk_io_read_totals() {
    local dev="$1" name
    name=$(basename "$dev")
    awk -v d="$name" '$3==d {print $6, $10; exit}' "$DISKSTATS_FILE" 2>/dev/null
}

# 输出 read_kbps|write_kbps|total_kbps|active，其中 active 表示最近 idle_sec 内有 I/O。
disk_sample_io() {
    local dev="$1" idle_sec="${2:-8}"
    local f read_now write_now now read_last write_last sampled_at last_activity
    local elapsed read_delta write_delta read_kbps write_kbps total_kbps active=0

    mkdir -p "$DISK_IO_CACHE_DIR"
    f=$(disk_io_cache_path "$dev")
    read -r read_now write_now < <(disk_io_read_totals "$dev")
    read_now="${read_now:-0}"
    write_now="${write_now:-0}"
    now=$(date +%s)

    if [[ -f "$f" ]]; then
        read -r read_last write_last sampled_at last_activity < "$f" 2>/dev/null || true
    fi
    read_last="${read_last:-$read_now}"
    write_last="${write_last:-$write_now}"
    sampled_at="${sampled_at:-$now}"
    last_activity="${last_activity:-0}"

    elapsed=$((now - sampled_at))
    (( elapsed < 1 )) && elapsed=1
    read_delta=$((read_now - read_last))
    write_delta=$((write_now - write_last))
    (( read_delta < 0 )) && read_delta=0
    (( write_delta < 0 )) && write_delta=0

    # sectors * 512 / 1024 / seconds
    read_kbps=$((read_delta / 2 / elapsed))
    write_kbps=$((write_delta / 2 / elapsed))
    total_kbps=$((read_kbps + write_kbps))

    if (( read_delta > 0 || write_delta > 0 )); then
        last_activity="$now"
    fi
    if (( last_activity > 0 && now - last_activity < idle_sec )); then
        active=1
    fi

    printf '%s %s %s %s\n' "$read_now" "$write_now" "$now" "$last_activity" > "$f"
    printf '%s|%s|%s|%s\n' "$read_kbps" "$write_kbps" "$total_kbps" "$active"
}

# 仅在缓存过期时执行 ATA CHECK POWER MODE，降低对兼容性较差桥接器的查询频率。
disk_read_power_state_cached() {
    local dev="$1" probe_interval="${2:-60}" f now cached_at cached_state out lower
    f=$(disk_power_cache_path "$dev")
    now=$(date +%s)

    if [[ -f "$f" ]]; then
        IFS='|' read -r cached_at cached_state < "$f" 2>/dev/null || true
        if [[ "$cached_at" =~ ^[0-9]+$ ]] && (( now - cached_at < probe_interval )); then
            echo "${cached_state:-idle}"
            return
        fi
    fi

    if ! out=$(timeout 5 hdparm -C "$dev" 2>&1); then
        cached_state="offline"
    else
        lower=$(echo "$out" | tr '[:upper:]' '[:lower:]')
        if echo "$lower" | grep -q "sleeping"; then
            cached_state="deep_sleep"
        elif echo "$lower" | grep -q "standby"; then
            cached_state="standby"
        elif echo "$lower" | grep -q "active/idle\|active"; then
            cached_state="idle"
        else
            cached_state="idle"
        fi
    fi

    printf '%s|%s\n' "$now" "$cached_state" > "${f}.tmp.$$"
    mv "${f}.tmp.$$" "$f"
    echo "$cached_state"
}

disk_mark_power_active() {
    local dev="$1" f now
    f=$(disk_power_cache_path "$dev")
    now=$(date +%s)
    printf '%s|idle\n' "$now" > "${f}.tmp.$$"
    mv "${f}.tmp.$$" "$f"
}

# 输出 state|read_kbps|write_kbps|total_kbps
disk_detect_smart_sample() {
    local dev="$1" idle_sec="${2:-8}" probe_interval="${3:-60}"
    local sample power_state read_kbps=0 write_kbps=0 total_kbps=0 active=0

    [[ -b "$dev" ]] || { echo "offline|0|0|0"; return; }

    sample=$(disk_sample_io "$dev" "$idle_sec")
    IFS='|' read -r read_kbps write_kbps total_kbps active <<< "$sample"
    if [[ "$active" == "1" ]]; then
        disk_mark_power_active "$dev"
        echo "active|${read_kbps:-0}|${write_kbps:-0}|${total_kbps:-0}"
        return
    fi

    power_state=$(disk_read_power_state_cached "$dev" "$probe_interval")
    case "$power_state" in
        offline) echo "offline|0|0|0" ;;
        deep_sleep) echo "deep_sleep|0|0|0" ;;
        standby) echo "standby|0|0|0" ;;
        *) echo "idle|${read_kbps:-0}|${write_kbps:-0}|${total_kbps:-0}" ;;
    esac
}

disk_detect_smart_state() {
    local sample
    sample=$(disk_detect_smart_sample "$1" "${2:-8}" "${3:-60}")
    echo "${sample%%|*}"
}
