#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export CLI_LOG="$TMP/calls" UGREEN_CLI="$TMP/cli"
cat > "$UGREEN_CLI" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CLI_LOG"
[[ "${MOCK_BUSY:-0}" != 1 ]] || { echo 'Err: LED controller busy'; exit 1; }
for name in "$@"; do
    [[ "$name" == -status ]] && continue
    if [[ "$name" == disk4 ]]; then
        echo "$name: unavailable or non-existent; detail=mock read error"
    else
        echo "$name: status = on, brightness = 64, color = RGB(1, 2, 3)"
    fi
done
EOF
chmod +x "$UGREEN_CLI"
LED_API_CACHE_DIR="$TMP/cache"
source "$ROOT/App.Native.UGreenLED/app/server/lib/led_api.sh"
led_backend_select() { :; }
led_power26_profile() { [[ "${PROFILE:-dx4600}" == dxp480t_plus ]]; }
led_list_disk_slots() { printf '%s\n' disk1 disk2 disk3 disk4; }
led_list_network_slots() { echo netdev; [[ "${PROFILE:-dx4600}" != idx6011_pro ]] || echo netdev2; }
hardware_cli_led_name() {
    if [[ "${PROFILE:-dx4600}" == idx6011_pro ]]; then
        case "$1" in
            netdev2) echo disk1; return ;;
            disk*) echo "disk$((${1#disk} + 1))"; return ;;
        esac
    fi
    echo "$1"
}
status=$(led_all_status)
[[ $(wc -l < "$CLI_LOG") == 1 ]] || fail 'snapshot must make one CLI call'
[[ $(cat "$CLI_LOG") == 'power netdev disk1 disk2 disk3 disk4 -status' ]] || fail 'wrong batch arguments'
grep -q '^disk1: status = on' <<< "$status" || fail 'missing disk state'
grep -q '^disk4: unavailable' <<< "$status" || fail 'lost per-LED read failure'
! grep -q 'disk1: disk1:' <<< "$status" || fail 'duplicate LED prefix'
PROFILE=idx6011_pro
status=$(led_all_status)
[[ $(tail -n 1 "$CLI_LOG") == 'power netdev disk1 disk2 disk3 disk4 disk5 -status' ]] || fail 'raw mapping lost'
grep -q '^netdev2: status = on' <<< "$status" || fail 'second network mapping lost'
grep -q '^disk3: unavailable' <<< "$status" || fail 'disk failure mapped to wrong logical slot'
export MOCK_BUSY=1
if led_all_status > "$TMP/failed"; then fail 'busy failure must propagate'; fi
! grep -q 'status = on' "$TMP/failed" || fail 'failure emitted fabricated state'
unset MOCK_BUSY
PROFILE=dxp480t_plus
before=$(wc -l < "$CLI_LOG")
led_write_cached_state power 'power26,white,steady'
status=$(led_all_status)
[[ $(wc -l < "$CLI_LOG") == "$before" ]] || fail '480T must retain its separate route'
grep -q '^power: status = on' <<< "$status" || fail '480T state missing'
echo 'LED batch, logical mapping, failure and 480T isolation passed'
