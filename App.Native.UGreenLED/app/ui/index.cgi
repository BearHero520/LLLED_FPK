#!/bin/bash
APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-/var/apps/${APP_NAME}}"

BASE_PATH=""
for d in "${APP_ROOT}/www" "${APP_ROOT}/target/www"; do
    if [[ -f "${d}/index.html" ]]; then
        BASE_PATH="$d"
        break
    fi
done
BASE_PATH="${BASE_PATH:-${APP_ROOT}/www}"

URI_NO_QUERY="${REQUEST_URI%%\?*}"
REL_PATH="/"
case "$URI_NO_QUERY" in
    *index.cgi*) REL_PATH="${URI_NO_QUERY#*index.cgi}" ;;
esac
[[ -z "$REL_PATH" || "$REL_PATH" == "/" ]] && REL_PATH="/index.html"
TARGET_FILE="${BASE_PATH}${REL_PATH}"
if echo "$TARGET_FILE" | grep -q '\.\.'; then
    echo "Status: 400 Bad Request"
    echo "Content-Type: text/plain; charset=utf-8"
    echo ""
    echo "Bad Request"
    exit 0
fi
if [[ ! -f "$TARGET_FILE" ]]; then
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain; charset=utf-8"
    echo ""
    echo "404 Not Found: ${REL_PATH}"
    exit 0
fi
ext="${TARGET_FILE##*.}"
case "$ext" in
    html|htm) mime="text/html; charset=utf-8" ;;
    css) mime="text/css; charset=utf-8" ;;
    js) mime="application/javascript; charset=utf-8" ;;
    png) mime="image/png" ;;
    json) mime="application/json; charset=utf-8" ;;
    *) mime="application/octet-stream" ;;
esac
echo "Content-Type: $mime"
echo ""
cat "$TARGET_FILE"
