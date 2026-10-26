#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/App.Native.UGreenLED/app/server/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_no_calls() { [[ ! -s "$TEST_CALLS" ]] || fail "$*: unexpected hardware call"; }
assert_saved() { [[ "$(settings_get "$SETTINGS_FILE" bios startup_selection)" == "$1" ]] || fail "selection not preserved: $1"; }
export SETTINGS_FILE="$TMP/settings.conf" UGREEN_PRODUCT_NAME=DX4600
export BIOS_UGREENCTL="$TMP/ugreenctl" BIOS_UGREENCTL_PLUGIN_DIR="$TMP/models"
export TEST_STATE="$TMP/hardware" TEST_CALLS="$TMP/calls" TEST_FAIL="$TMP/fail"
mkdir -p "$BIOS_UGREENCTL_PLUGIN_DIR"
for model in dx4600 dxp4800 dxp4800plus dxp4800s dxp480tplus dxp6800pro dxp6800plus; do
    touch "$BIOS_UGREENCTL_PLUGIN_DIR/$model.so"
done
cat > "$BIOS_UGREENCTL" <<'EOF'
#!/bin/bash
echo "$*" >> "$TEST_CALLS"
[[ ! -f "$TEST_FAIL" ]] || { echo 'error: simulated readback failure'; exit 1; }
case " $* " in
    *' power startup set '*) echo "${@: -1}" > "$TEST_STATE" ;;
    *' power startup get '*) cat "$TEST_STATE" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$BIOS_UGREENCTL"
source "$LIB/settings.sh"
source "$LIB/hardware_profile.sh"
source "$LIB/bios_control.sh"

# Every exact startup DMI accepted by the adapter must save and replay all
# explicit choices. Plugin-sharing variants still receive distinct bindings.
products=('DX4600' 'DX4600+' 'DX4600 Pro' 'DXP4800'
    'DXP4800 Plus' 'UGREEN DXP4800 Plus' 'DXP4800 Pro' 'UGREEN DXP4800 Pro'
    'DXP4800S' 'DXP480T Plus' 'UGREEN DXP480T Plus' 'DXP6800 Plus' 'DXP6800 Pro')
for UGREEN_PRODUCT_NAME in "${products[@]}"; do
    bios_supported_model || fail "supported exact DMI rejected: $UGREEN_PRODUCT_NAME"
    settings_set "$SETTINGS_FILE" bios startup_selection ''
    : > "$TEST_CALLS"
    bios_startup_restore
    assert_no_calls "unconfigured $UGREEN_PRODUCT_NAME restore"
    for policy in on off last; do
        echo unknown > "$TEST_STATE"
        bios_read_cli_startup || fail 'unknown policy made the interface unavailable'
        [[ "$BIOS_STARTUP_POLICY" == unknown ]] || fail 'unknown policy was replaced with a default'
        : > "$TEST_CALLS"
        bios_set_startup_saved "$policy"
        assert_saved "$UGREEN_PRODUCT_NAME|$policy"
        expected="$policy"; [[ "$policy" != last ]] || expected=restore
        [[ "$(cat "$TEST_STATE")" == "$expected" ]] || fail "write lost $policy on $UGREEN_PRODUCT_NAME"
        case "$UGREEN_PRODUCT_NAME" in
            *DXP480T*) guard='--apply' ;;
            *) guard='--force --apply' ;;
        esac
        grep -Fq -- "$guard power startup set $expected" "$TEST_CALLS" || fail 'missing guarded upstream write'
        echo unknown > "$TEST_STATE"
        : > "$TEST_CALLS"
        # A clean shell proves the value comes from persistent configuration.
        bash -c 'source "$1/settings.sh"; source "$1/hardware_profile.sh"; source "$1/bios_control.sh"; bios_startup_restore' _ "$LIB"
        [[ "$(cat "$TEST_STATE")" == "$expected" ]] || fail "lost $policy after $UGREEN_PRODUCT_NAME restart"
        [[ "$(wc -l < "$TEST_CALLS")" -eq 1 ]] || fail 'restore must make one guarded write'
        assert_saved "$UGREEN_PRODUCT_NAME|$policy"
    done
    touch "$TEST_FAIL"
    ! bios_set_startup_saved on || fail 'failed hardware write reported success'
    assert_saved "$UGREEN_PRODUCT_NAME|last"
    ! bios_startup_restore || fail 'failed restore reported success'
    rm "$TEST_FAIL"
    : > "$TEST_CALLS"
    ! bios_set_startup_saved invalid || fail 'invalid choice accepted'
    assert_saved "$UGREEN_PRODUCT_NAME|last"
    assert_no_calls 'invalid choice'
    for corrupt in "$UGREEN_PRODUCT_NAME|invalid" "$UGREEN_PRODUCT_NAME|on|last" "$UGREEN_PRODUCT_NAME"; do
        settings_set "$SETTINGS_FILE" bios startup_selection "$corrupt"
        ! bios_startup_restore || fail "corrupt choice accepted: $corrupt"
        assert_no_calls 'corrupt choice'
    done
done

# Exact identity is required even for aliases and variants sharing a plugin.
for saved_product in "${products[@]}"; do
    settings_set "$SETTINGS_FILE" bios startup_selection "$saved_product|on"
    for UGREEN_PRODUCT_NAME in "${products[@]}"; do
        [[ "$saved_product" != "$UGREEN_PRODUCT_NAME" ]] || continue
        : > "$TEST_CALLS"
        bios_startup_restore
        assert_no_calls "$saved_product selection on $UGREEN_PRODUCT_NAME"
    done
done
for UGREEN_PRODUCT_NAME in 'DX4600 Engineering' 'UGREEN DX4600' 'UGREEN DXP4800' 'UGREEN DXP4800S' 'DXP4800S Engineering' 'UGREEN DXP6800 Plus' 'UGREEN DXP6800 Pro' 'DXP8800 Plus'; do
    : > "$TEST_CALLS"
    bios_startup_restore
    ! bios_set_startup_saved on || fail "unsupported product accepted: $UGREEN_PRODUCT_NAME"
    assert_no_calls "unsupported $UGREEN_PRODUCT_NAME"
done
UGREEN_PRODUCT_NAME=DX4600
settings_set "$SETTINGS_FILE" bios startup_selection 'DX4600|last'
: > "$TEST_CALLS"
(
    settings_get() { printf 'DX4600|on\n'; return 1; }
    ! bios_startup_restore || fail 'failed config read reported success'
    [[ "$BIOS_LAST_ERROR" == *读取*失败* ]] || fail 'missing config read error'
    assert_no_calls 'failed config read with partial data'
)
for identity_failure in error empty; do
    (
        # Emulate a DMI read failure after the initial supported-profile check.
        bios_detected_profile() { echo dx4600; }
        if [[ "$identity_failure" == error ]]; then
            hardware_detected_product_name() { echo DX4600; return 1; }
        else
            hardware_detected_product_name() { :; }
        fi
        ! bios_set_startup_saved on || fail 'unreadable DMI accepted for save'
        [[ "$BIOS_LAST_ERROR" == *精确机型* ]] || fail 'missing DMI save error'
        ! bios_startup_restore || fail 'unreadable DMI accepted for restore'
        [[ "$BIOS_LAST_ERROR" == *精确机型* ]] || fail 'missing DMI restore error'
        assert_no_calls "DMI $identity_failure"
    )
done
(
    unset SETTINGS_FILE
    ! bios_set_startup_saved on || fail 'missing config accepted for save'
    ! bios_startup_restore || fail 'missing config accepted for restore'
    assert_no_calls 'missing config service'
)
(
    unset -f settings_set
    ! bios_set_startup_saved on || fail 'missing config writer accepted'
    assert_no_calls 'missing config writer'
)
(
    unset -f settings_get
    ! bios_startup_restore || fail 'missing config reader accepted'
    assert_no_calls 'missing config reader'
)
# Hardware success followed by a persistence failure must be explicit, and the
# previous selection must remain intact rather than claiming durable success.
(
    settings_set() { return 1; }
    ! bios_set_startup_saved on || fail 'save failure reported success'
    [[ "$BIOS_LAST_ERROR" == *保存失败* ]] || fail 'missing persistence error'
    [[ "$(cat "$TEST_STATE")" == on ]] || fail 'save failure incorrectly hid hardware success'
    assert_saved 'DX4600|last'
)

# Exercise the existing start/stop hooks through the real service entry point.
# All other service effects, the LED backend and module loading are mocked.
SERVICE_APP="$TMP/service-app"
mkdir -p "$SERVICE_APP/server/lib" "$SERVICE_APP/server/bin" "$TMP/service-var" "$TMP/service-run" "$TMP/mock-bin"
cp "$LIB/settings.sh" "$LIB/hardware_profile.sh" "$LIB/bios_control.sh" "$SERVICE_APP/server/lib/"
cat > "$SERVICE_APP/server/lib/logging.sh" <<'EOF'
ugreen_log_debug() { :; }
ugreen_log_info() { :; }
ugreen_log_warn() { printf '%s\n' "$*" >> "$TEST_SERVICE_WARNINGS"; }
ugreen_log_error() { :; }
ugreen_log_configure_from_settings() { :; }
ugreen_log_run_raw() { shift 4; "$@" >/dev/null 2>&1; }
EOF
cat > "$SERVICE_APP/server/lib/app_paths.sh" <<'EOF'
ugreen_resolve_runtime() { RUNTIME_DIR="$UGREEN_RUNTIME_DIR"; mkdir -p "$RUNTIME_DIR"; }
EOF
printf ':\n' > "$SERVICE_APP/server/lib/driver_manager.sh"
cat > "$SERVICE_APP/server/lib/led_api.sh" <<'EOF'
led_backend_configured() { echo cli; }
ensure_led_backend() { :; }
EOF
for daemon in led_daemon.sh fan_telemetry_daemon.sh http_api.sh; do
    printf '#!/bin/bash\nexit 0\n' > "$SERVICE_APP/server/$daemon"
done
printf '#!/bin/bash\nexit 0\n' > "$TMP/mock-bin/modprobe"
chmod +x "$TMP/mock-bin/modprobe"
export TRIM_APPDEST="$SERVICE_APP" TRIM_PKGVAR="$TMP/service-var" UGREEN_RUNTIME_DIR="$TMP/service-run" TEST_SERVICE_WARNINGS="$TMP/service-warnings"
export PATH="$TMP/mock-bin:$PATH"
SETTINGS_FILE="$TRIM_PKGVAR/settings.conf"
for UGREEN_PRODUCT_NAME in "${products[@]}"; do
    settings_set "$SETTINGS_FILE" bios startup_selection ''
    : > "$TEST_CALLS"
    bash "$ROOT/App.Native.UGreenLED/cmd/main" start
    bash "$ROOT/App.Native.UGreenLED/cmd/main" stop
    assert_no_calls "unconfigured service $UGREEN_PRODUCT_NAME"
    settings_set "$SETTINGS_FILE" bios startup_selection "$UGREEN_PRODUCT_NAME|last"
    for action in start stop; do
        echo unknown > "$TEST_STATE"
        : > "$TEST_CALLS"
        bash "$ROOT/App.Native.UGreenLED/cmd/main" "$action"
        [[ "$(cat "$TEST_STATE")" == restore ]] || fail "service $action lost policy on $UGREEN_PRODUCT_NAME"
        [[ "$(wc -l < "$TEST_CALLS")" -eq 1 ]] || fail "service $action must restore exactly once"
    done
done
touch "$TEST_FAIL"
for action in start stop; do
    : > "$TEST_SERVICE_WARNINGS"
    bash "$ROOT/App.Native.UGreenLED/cmd/main" "$action"
    grep -Fq 'bios.startup_restore_failed' "$TEST_SERVICE_WARNINGS" || fail "service $action hid restore failure"
    assert_saved "$UGREEN_PRODUCT_NAME|last"
done
echo 'Startup persistence tests passed (13 exact products, all policies, cross-model rejection, failures, service start/stop)'
