#!/bin/bash
# 网络状态与吞吐采样：disconnected(断网) | connected(联网) | vpn(外网)

NET_PING_TIMEOUT="${NET_PING_TIMEOUT:-2}"
NET_DOMESTIC_HOSTS=(223.5.5.5 114.114.114.114)
NET_OVERSEAS_HOSTS=(8.8.8.8 1.1.1.1)
NET_SPEED_CACHE_FILE="${NET_SPEED_CACHE_FILE:-/tmp/ugreen-net-speed.cache}"
NET_STATE_CACHE_FILE="${NET_STATE_CACHE_FILE:-/tmp/ugreen-net-state.cache}"
NET_SYS_CLASS_DIR="${NET_SYS_CLASS_DIR:-/sys/class/net}"

net_ping_host() {
    local host="$1"
    timeout "$((NET_PING_TIMEOUT + 1))" ping -c 1 -W "$NET_PING_TIMEOUT" "$host" >/dev/null 2>&1
}

net_can_ping_any() {
    local h
    for h in "$@"; do
        net_ping_host "$h" && return 0
    done
    return 1
}

net_can_ping_domestic() {
    net_can_ping_any "${NET_DOMESTIC_HOSTS[@]}"
}

net_can_ping_overseas() {
    net_can_ping_any "${NET_OVERSEAS_HOSTS[@]}"
}

# 国内与海外探测并行执行，输出 state|domestic_ok|overseas_ok。
net_probe_state() {
    local domestic=0 overseas=0 p_domestic p_overseas
    net_can_ping_domestic & p_domestic=$!
    net_can_ping_overseas & p_overseas=$!
    wait "$p_domestic" && domestic=1
    wait "$p_overseas" && overseas=1

    if [[ $overseas -eq 1 ]]; then
        echo "vpn|${domestic}|${overseas}"
    elif [[ $domestic -eq 1 ]]; then
        echo "connected|${domestic}|${overseas}"
    else
        echo "disconnected|${domestic}|${overseas}"
    fi
}

# 避免每个 5 秒灯控周期都做公网探测。
net_detect_state_cached() {
    local ttl="${1:-30}" now cached_at state domestic overseas sample
    now=$(date +%s)
    if [[ -f "$NET_STATE_CACHE_FILE" ]]; then
        IFS='|' read -r cached_at state domestic overseas < "$NET_STATE_CACHE_FILE" 2>/dev/null || true
        if [[ -n "$cached_at" && $((now - cached_at)) -lt $ttl ]]; then
            echo "${state:-disconnected}|${domestic:-0}|${overseas:-0}"
            return
        fi
    fi

    sample=$(net_probe_state)
    IFS='|' read -r state domestic overseas <<< "$sample"
    printf '%s|%s|%s|%s\n' "$now" "$state" "$domestic" "$overseas" > "${NET_STATE_CACHE_FILE}.tmp.$$"
    mv "${NET_STATE_CACHE_FILE}.tmp.$$" "$NET_STATE_CACHE_FILE"
    echo "$sample"
}

net_detect_state() {
    local sample
    sample=$(net_detect_state_cached 30)
    echo "${sample%%|*}"
}

net_state_label() {
    case "$1" in
        vpn) echo "外网" ;;
        connected) echo "联网" ;;
        *) echo "断网" ;;
    esac
}

net_list_monitored_interfaces() {
    local dev path found=0
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r dev; do
            [[ -n "$dev" && -r "${NET_SYS_CLASS_DIR}/${dev}/statistics/rx_bytes" ]] || continue
            echo "$dev"
            found=1
        done < <(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u)
    fi
    [[ $found -eq 1 ]] && return

    for path in "${NET_SYS_CLASS_DIR}"/*; do
        [[ -d "$path" ]] || continue
        dev=$(basename "$path")
        [[ "$dev" == "lo" || "$dev" =~ ^(docker|veth|virbr|br-|tun|tap) ]] && continue
        [[ -r "$path/statistics/rx_bytes" ]] && echo "$dev"
    done
}

net_read_byte_totals() {
    local dev rx=0 tx=0 value
    while IFS= read -r dev; do
        value=$(cat "${NET_SYS_CLASS_DIR}/${dev}/statistics/rx_bytes" 2>/dev/null || echo 0)
        rx=$((rx + ${value:-0}))
        value=$(cat "${NET_SYS_CLASS_DIR}/${dev}/statistics/tx_bytes" 2>/dev/null || echo 0)
        tx=$((tx + ${value:-0}))
    done < <(net_list_monitored_interfaces)
    echo "$rx $tx"
}

# 输出 rx_kbps|tx_kbps|total_kbps。
net_sample_speed() {
    local rx_now tx_now now rx_last tx_last sampled_at elapsed rx_delta tx_delta
    local rx_kbps tx_kbps
    mkdir -p "$(dirname "$NET_SPEED_CACHE_FILE")"
    read -r rx_now tx_now < <(net_read_byte_totals)
    rx_now="${rx_now:-0}"
    tx_now="${tx_now:-0}"
    now=$(date +%s)

    if [[ -f "$NET_SPEED_CACHE_FILE" ]]; then
        read -r rx_last tx_last sampled_at < "$NET_SPEED_CACHE_FILE" 2>/dev/null || true
    fi
    rx_last="${rx_last:-$rx_now}"
    tx_last="${tx_last:-$tx_now}"
    sampled_at="${sampled_at:-$now}"
    elapsed=$((now - sampled_at))
    (( elapsed < 1 )) && elapsed=1
    rx_delta=$((rx_now - rx_last))
    tx_delta=$((tx_now - tx_last))
    (( rx_delta < 0 )) && rx_delta=0
    (( tx_delta < 0 )) && tx_delta=0
    rx_kbps=$((rx_delta / 1024 / elapsed))
    tx_kbps=$((tx_delta / 1024 / elapsed))

    printf '%s %s %s\n' "$rx_now" "$tx_now" "$now" > "${NET_SPEED_CACHE_FILE}.tmp.$$"
    mv "${NET_SPEED_CACHE_FILE}.tmp.$$" "$NET_SPEED_CACHE_FILE"
    printf '%s|%s|%s\n' "$rx_kbps" "$tx_kbps" "$((rx_kbps + tx_kbps))"
}
