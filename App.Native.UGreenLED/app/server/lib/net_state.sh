#!/bin/bash
# 网络灯三态: disconnected(断网) | connected(联网) | vpn(外网)
# 规则（简化）:
#   ping 通海外检测地址 → 外网
#   否则 ping 通国内检测地址 → 联网
#   否则 → 断网

NET_PING_TIMEOUT="${NET_PING_TIMEOUT:-2}"
NET_DOMESTIC_HOSTS=(223.5.5.5 114.114.114.114)
NET_OVERSEAS_HOSTS=(8.8.8.8 1.1.1.1)

net_ping_host() {
    local host="$1"
    # 兼容 iputils / busybox
    if ping -c 1 -w "$NET_PING_TIMEOUT" "$host" >/dev/null 2>&1; then
        return 0
    fi
    if ping -c 1 -W "$NET_PING_TIMEOUT" "$host" >/dev/null 2>&1; then
        return 0
    fi
    return 1
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

net_detect_state() {
    if net_can_ping_overseas; then
        echo "vpn"
        return
    fi
    if net_can_ping_domestic; then
        echo "connected"
        return
    fi
    echo "disconnected"
}

# 状态中文名（日志/UI 用）
net_state_label() {
    case "$1" in
        vpn) echo "外网" ;;
        connected) echo "联网" ;;
        *) echo "断网" ;;
    esac
}
