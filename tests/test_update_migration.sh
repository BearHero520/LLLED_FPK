#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/run"
export TRIM_APPDEST="$ROOT/App.Native.UGreenLED/app"
export TRIM_PKGVAR="$TMP/var" UGREEN_RUNTIME_DIR="$TMP/run"
export UGREEN_DIAG_I2C_PROBE=off UGREEN_DIAG_UGREENCTL=/bin/false
export MIGRATION_FETCH_LOG="$TMP/fetch.log"
unset ABOUT_README_RAW_URL_OVERRIDE
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/curl" <<'MOCK'
#!/bin/bash
printf '%s\n' "${@: -1}" >> "$MIGRATION_FETCH_LOG"
case "${@: -1}" in
    https://api.github.com/repos/BearHero520/UGreen-Control/releases/latest)
        printf '{"tag_name":"v3.0.6"}' ;;
    https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/README.md)
        printf '# UGreen Control\nMigration README fixture\n' ;;
    *) exit 1 ;;
esac
MOCK
chmod +x "$TMP/bin/curl"

# A recent cache from the old repository must never hide the new update source.
printf 'v9.9.9|%s\n' "$(date +%s)" > "$TMP/run/update_check.cache"
printf '# Stale LLLED README\n' > "$TMP/run/github_readme.cache"
request() {
    PATH_INFO="$1" QUERY_STRING='' REQUEST_METHOD=GET CONTENT_LENGTH=0 \
        bash "$ROOT/App.Native.UGreenLED/app/ui/api.cgi" < /dev/null
}
contains() { [[ "$1" == *"$2"* ]] || { echo "Missing: $2" >&2; exit 1; }; }

response=$(request /update/check)
contains "$response" '"reachable":true'
contains "$response" '"latest_tag":"v3.0.6"'
contains "$response" 'https://github.com/BearHero520/UGreen-Control/releases/tag/v3.0.6'
contains "$response" 'https://github.com/BearHero520/UGreen-Control/releases/download/v3.0.6/App.Native.UGreenLED.fpk'
response=$(request /about/readme)
contains "$response" 'Migration README fixture'
contains "$response" 'https://github.com/BearHero520/UGreen-Control/blob/main/README.md'
response=$(request /about/info)
contains "$response" '"repository_url":"https://github.com/BearHero520/UGreen-Control"'
[[ $(wc -l < "$MIGRATION_FETCH_LOG") -eq 2 ]]
request /update/check > /dev/null
request /about/readme > /dev/null
[[ $(wc -l < "$MIGRATION_FETCH_LOG") -eq 2 ]]
echo 'Update and README migration: new repository, stale-cache isolation and fresh-cache reuse passed'
