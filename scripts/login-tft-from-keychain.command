#!/bin/zsh
set -euo pipefail

unsetopt XTRACE VERBOSE
umask 077

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR:h}"
source "$PROJECT_DIR/scripts/android-environment.sh"
readonly ADB_SERVER_PORT="${TFT_ADB_SERVER_PORT:-5038}"
ADB="$(tft_resolve_adb)"
readonly ADB
readonly SERIAL="${TFT_SERIAL:-emulator-5582}"
readonly PACKAGE="${TFT_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly KEYCHAIN_SERVICE="${MACTICIAN_KEYCHAIN_SERVICE:-dev.sergeinaumov.mactician}"
readonly CDP_HELPER="$SCRIPT_DIR/login-tft-webview.mjs"

if [[ "$ADB_SERVER_PORT" != <-> ]] \
        || (( ADB_SERVER_PORT < 1024 || ADB_SERVER_PORT > 65534 )); then
    print "TFT_ADB_SERVER_PORT must be a TCP port from 1024 through 65534."
    exit 2
fi
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

CDP_PORT=""

cleanup() {
    if [[ -n "$CDP_PORT" ]]; then
        "$ADB" -s "$SERIAL" forward --remove "tcp:$CDP_PORT" >/dev/null 2>&1 || true
    fi
    CDP_PORT=""
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    print "The TFT AVD is not connected on $SERIAL."
    exit 1
fi

readonly DISPLAY_SIZE="$("$ADB" -s "$SERIAL" shell wm size 2>/dev/null | tr -d '\r')"
case "$DISPLAY_SIZE" in
    *"1600x900"*|*"2560x1440"*|*"2880x1620"*|*"3200x1800"*|*"3840x2160"*) ;;
    *)
        print "The login helper does not support the current display size: $DISPLAY_SIZE"
        exit 1
        ;;
esac

readonly TOP_ACTIVITY="$(
    "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
        | tr -d '\r' \
        | grep -m 1 'topResumedActivity=' || true
)"
if [[ "$TOP_ACTIVITY" != *"MobileFREWebViewActivity"* ]]; then
    print "The official Riot login form is not open; the helper entered nothing."
    exit 1
fi

readonly CURRENT_FOCUS="$(
    "$ADB" -s "$SERIAL" shell dumpsys window windows 2>/dev/null \
        | tr -d '\r' \
        | grep -m 1 'mCurrentFocus=' || true
)"
if [[ "$CURRENT_FOCUS" == *"Not Responding"* || "$CURRENT_FOCUS" == *"AppNotResponding"* ]]; then
    print "The Riot WebView is unresponsive; no password was entered."
    exit 1
fi

if [[ ! -f "$CDP_HELPER" ]]; then
    print "The scoped WebView helper was not found: $CDP_HELPER"
    exit 1
fi

readonly NODE_BIN="${TFT_NODE:-$(command -v node || true)}"
if [[ -z "$NODE_BIN" ]]; then
    print "Node.js is required for the scoped WebView login helper."
    exit 1
fi

APP_PID="$("$ADB" -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')"
APP_PID="${APP_PID%% *}"
if [[ -z "$APP_PID" ]]; then
    print "The main TFT process was not found; the helper entered nothing."
    exit 1
fi

readonly WEBVIEW_SOCKET="webview_devtools_remote_$APP_PID"
if ! "$ADB" -s "$SERIAL" shell grep -q "@$WEBVIEW_SOCKET" /proc/net/unix; then
    print "The official Riot WebView did not expose its local DevTools socket; the helper entered nothing."
    exit 1
fi

CDP_PORT="$(
    "$ADB" -s "$SERIAL" forward tcp:0 "localabstract:$WEBVIEW_SOCKET" 2>/dev/null \
        | tr -d '\r'
)"
if [[ "$CDP_PORT" != <-> ]]; then
    print "Could not create a temporary local WebView port."
    exit 1
fi

"$NODE_BIN" "$CDP_HELPER" "$CDP_PORT" "$KEYCHAIN_SERVICE"
sleep 2

readonly RESULT_ACTIVITY="$(
    "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
        | tr -d '\r' \
        | grep -m 1 'topResumedActivity=' || true
)"
if [[ "$RESULT_ACTIVITY" == *"GameActivity"* ]]; then
    print "The Riot WebView accepted the form and returned to TFT; waiting for the service response."
else
    print "Sign In was pressed, but the Riot WebView remains open; no secrets were printed."
fi
print "The helper does not bypass or automatically complete visible CAPTCHA or MFA challenges."
